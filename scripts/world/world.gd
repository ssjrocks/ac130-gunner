extends Node3D
## The battlefield: terrain, water, towns, roads, trees, sky and lighting.
## Also answers height, raycast and building queries for everything else.

const Mats := preload("res://scripts/world/mats.gd")
const Meshes := preload("res://scripts/world/meshes.gd")

const CORE := 8000.0      # detailed terrain size (centred on 0,0)
const CORE_RES := 640     # height samples per side inside CORE
const FAR := 26000.0      # terrain continues (coarser) out to here
const ROAD_RES := 4096
const BCELL := 50.0

var battle
var map: Dictionary = {}
var biome := "desert"
var water_level := -10000.0
var coast_x := 1.0e9
var night := 0.0
var tod := "day"
var dust_color := Color(0.62, 0.55, 0.45)

var rng := RandomNumberGenerator.new()
var n_low := FastNoiseLite.new()
var n_mid := FastNoiseLite.new()
var n_det := FastNoiseLite.new()
var flats: Array = []          # [{p: Vector2, r: float, h: float}]
var river := PackedVector2Array()
var bridges: Array = []
var core_h := PackedFloat32Array()
var sp := CORE / CORE_RES
var towns: Array = []
var roads: Array = []          # PackedVector2Array per map road (same indices as the map)
var streets: Array = []        # extra painted streets (city grids)
var road_img: Image
var exclusions: Array = []     # [Vector3(x, z, r)] where towns must not build
var buildings: Array = []
var bgrid := {}
var bmm: MultiMesh
var props := {}              # prop mesh id -> [{xf, col, heat}] (roof parapets, tanks, domes...)
var prop_mm := {}            # prop mesh id -> MultiMesh
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var terrain_mat: ShaderMaterial
var tv := {}
var gates := {}             # outpost site -> unit vector (x, z) its gate faces
var road_nodes := PackedVector2Array()
var baked := false             # terrain and roads come from assets/maps (tools/maps/bake.py)
var far_h := PackedFloat32Array()
var far_res := 0
var far_span := 1.0
var road_adj: Array = []


func build(m: Dictionary, time_of_day: String, weather: String) -> void:
	map = m
	biome = m.get("biome", "desert")
	tod = time_of_day
	rng.seed = int(m.get("seed", 1))
	water_level = float(m.get("water", -10000.0))
	coast_x = float(m.get("coast_x", 1.0e9))
	_setup_noise()
	for r in m.get("roads", []):
		_parse_road(r)
	river = PackedVector2Array(m.get("river", []))
	bridges = m.get("bridges", [])
	for t in m.get("towns", []):
		towns.append(t.duplicate())
	baked = _load_baked(String(m.get("id", "")))
	if not baked:
		_setup_flats()
		_gen_heights()
	_build_terrain_mesh()
	_paint_roads()
	_build_water()
	_build_bridges()
	_build_outposts()
	for t in towns:
		_gen_town(t)
	_make_building_multimesh()
	_build_trees()
	_setup_sky(weather)


# --- Height field -------------------------------------------------------

## Loads the map's baked heights and graded roads. Roads keep the layout's
## order, so missions' route indices still point at the same roads.
func _load_baked(id: String) -> bool:
	var path := "res://assets/maps/%s.ter" % id
	if id == "" or not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f.get_buffer(4).get_string_from_ascii() != "ACT2":
		return false
	var res := f.get_32()
	far_res = f.get_32()
	var core_size := f.get_float()
	far_span = f.get_float()
	if res != CORE_RES or not is_equal_approx(core_size, CORE):
		return false
	core_h = f.get_buffer(res * res * 4).to_float32_array()
	far_h = f.get_buffer(far_res * far_res * 4).to_float32_array()
	var rf := FileAccess.open("res://assets/maps/%s_roads.json" % id, FileAccess.READ)
	if rf:
		var data = JSON.parse_string(rf.get_as_text())
		if data is Array and data.size() == roads.size():
			for i in data.size():
				var pts := PackedVector2Array()
				for p in data[i]:
					pts.append(Vector2(p[0], p[1]))
				roads[i] = pts
	return true


## Heights outside the detailed core: the baked far grid, bilinear.
func _far_height(x: float, z: float) -> float:
	var fsp := far_span / far_res
	var fx := clampf((x + far_span * 0.5) / fsp - 0.5, 0.0, far_res - 1.001)
	var fz := clampf((z + far_span * 0.5) / fsp - 0.5, 0.0, far_res - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var k := j * far_res + i
	var a := lerpf(far_h[k], far_h[k + 1], tx)
	var b := lerpf(far_h[k + far_res], far_h[k + far_res + 1], tx)
	return lerpf(a, b, tz)


func _setup_noise() -> void:
	var s := int(map.get("seed", 1))
	n_low.seed = s
	n_low.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_low.frequency = 1.0 / 2600.0
	n_low.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_low.fractal_octaves = 3
	n_mid.seed = s + 1
	n_mid.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_mid.frequency = 1.0 / 650.0
	n_mid.fractal_type = FastNoiseLite.FRACTAL_RIDGED if biome == "mountain" else FastNoiseLite.FRACTAL_FBM
	n_mid.fractal_octaves = 3
	n_det.seed = s + 2
	n_det.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_det.frequency = 1.0 / 110.0
	n_det.fractal_octaves = 2


func _base_height(x: float, z: float) -> float:
	var lo := n_low.get_noise_2d(x, z)
	var mi := n_mid.get_noise_2d(x, z)
	var de := n_det.get_noise_2d(x, z)
	var h := 0.0
	match biome:
		"desert":
			var amp := 0.35 if map.get("flat", false) else 1.0
			h = 40.0 + (lo * 55.0 + mi * 16.0) * amp + de * 2.5
		"mountain":
			var r := sqrt(x * x + z * z)
			var bowl := smoothstep(900.0, 3400.0, r + mi * 250.0)
			h = 600.0 + lo * 90.0 + bowl * (650.0 + lo * 450.0 + (mi * 0.5 + 0.5) * 520.0) + mi * 18.0 + de * 5.0
		"green":
			h = 55.0 + lo * 22.0 + mi * 7.0 + de * 1.2
		"coastal":
			var land := 30.0 + lo * 20.0 + mi * 7.0 + de * 1.5
			h = land - smoothstep(coast_x - 450.0, coast_x + 250.0, x + mi * 120.0) * (land + 22.0)
		"urban":
			h = 20.0 + lo * 10.0 + mi * 3.0 + de * 0.5
		_:
			h = 40.0 + lo * 40.0
	return h


func _raw_height(x: float, z: float) -> float:
	var h := _base_height(x, z)
	for f in flats:
		var fp: Vector2 = f.p
		var fr: float = f.r
		var dx := x - fp.x
		var dz := z - fp.y
		var lim := fr * 1.5
		if absf(dx) > lim or absf(dz) > lim:
			continue
		var d := sqrt(dx * dx + dz * dz)
		if d < lim:
			h = lerpf(h, f.h, 1.0 - smoothstep(fr * 0.7, lim, d))
	if river.size() > 1:
		var rd := _river_dist(x, z)
		if rd < 140.0:
			# a causeway carries the road across the whole river cut
			var keep := 0.0
			var pz := Vector2(x, z)
			for b in bridges:
				if pz.distance_to(b) < 180.0:
					var rdist := 1.0e9
					for pts in roads:
						for k in pts.size() - 1:
							rdist = minf(rdist, _seg_dist(pz, pts[k], pts[k + 1]))
					keep = maxf(keep, 1.0 - smoothstep(9.0, 22.0, rdist))
			var carve := (1.0 - smoothstep(22.0, 140.0, rd)) * (1.0 - keep)
			h = lerpf(h, water_level - 4.0, carve)
	return h


func _river_dist(x: float, z: float) -> float:
	var best := 1.0e9
	var p := Vector2(x, z)
	for i in river.size() - 1:
		var a := river[i]
		var b := river[i + 1]
		if z < minf(a.y, b.y) - 200.0 or z > maxf(a.y, b.y) + 200.0:
			continue
		best = minf(best, _seg_dist(p, a, b))
	return best


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _setup_flats() -> void:
	var pts: Array = []
	for t in towns:
		pts.append([t.pos, float(t.r) * 0.9])
	var outposts: Dictionary = map.get("outposts", {})
	for sname in map.get("sites", {}):
		var r := 60.0
		if outposts.has(sname):
			r = float(outposts[sname]) * 0.9 + 30.0
		pts.append([map.sites[sname], r])
	for p in pts:
		var c: Vector2 = p[0]
		flats.append({"p": c, "r": p[1], "h": 0.0})
	# Each flat's height is the unflattened ground at its centre.
	var saved := flats
	flats = []
	for f in saved:
		f.h = _raw_height(f.p.x, f.p.y)
	flats = saved


func _gen_heights() -> void:
	core_h.resize(CORE_RES * CORE_RES)
	var half := CORE * 0.5
	var all_flats := flats
	for j in CORE_RES:
		var z := -half + (j + 0.5) * sp
		# only the flats that can touch this row
		var row: Array = []
		for f in all_flats:
			if absf(z - f.p.y) < f.r * 1.5:
				row.append(f)
		flats = row
		for i in CORE_RES:
			core_h[j * CORE_RES + i] = _raw_height(-half + (i + 0.5) * sp, z)
	flats = all_flats


## Ground height at x, z. Inside the core this matches the rendered triangles.
func height(x: float, z: float) -> float:
	var hx := (x + CORE * 0.5) / sp - 0.5
	var hz := (z + CORE * 0.5) / sp - 0.5
	if hx >= 0.0 and hz >= 0.0 and hx < CORE_RES - 1 and hz < CORE_RES - 1:
		var i := int(hx)
		var j := int(hz)
		var fx := hx - i
		var fz := hz - j
		var k := j * CORE_RES + i
		var h00 := core_h[k]
		var h11 := core_h[k + CORE_RES + 1]
		if fx >= fz:
			var h10 := core_h[k + 1]
			return h00 + (h10 - h00) * fx + (h11 - h10) * fz
		var h01 := core_h[k + CORE_RES]
		return h00 + (h11 - h01) * fx + (h01 - h00) * fz
	if baked:
		return _far_height(x, z)
	return _raw_height(x, z)


func normal_at(x: float, z: float) -> Vector3:
	var e := 3.0
	var hl := height(x - e, z)
	var hr := height(x + e, z)
	var hd := height(x, z - e)
	var hu := height(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func _axis_coords() -> PackedFloat32Array:
	var half := CORE * 0.5
	var outer := PackedFloat32Array()
	var e := half - sp * 0.5
	var s := sp * 1.3
	while e < FAR:
		e += s
		s *= 1.12
		outer.append(e)
	var res := PackedFloat32Array()
	for k in range(outer.size() - 1, -1, -1):
		res.append(-outer[k])
	for i in CORE_RES:
		res.append(-half + (i + 0.5) * sp)
	res.append_array(outer)
	return res


func _build_terrain_mesh() -> void:
	var xs := _axis_coords()
	var n := xs.size()
	var off := (n - CORE_RES) / 2
	var hgrid := PackedFloat32Array()
	hgrid.resize(n * n)
	for j in n:
		var cj := j - off
		for i in n:
			var ci := i - off
			if ci >= 0 and ci < CORE_RES and cj >= 0 and cj < CORE_RES:
				hgrid[j * n + i] = core_h[cj * CORE_RES + ci]
			else:
				hgrid[j * n + i] = _far_height(xs[i], xs[j]) if baked else _base_height(xs[i], xs[j])
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(n * n)
	norms.resize(n * n)
	for j in n:
		var j0 := maxi(j - 1, 0)
		var j1 := mini(j + 1, n - 1)
		var dz := xs[j1] - xs[j0]
		for i in n:
			var i0 := maxi(i - 1, 0)
			var i1 := mini(i + 1, n - 1)
			var k := j * n + i
			verts[k] = Vector3(xs[i], hgrid[k], xs[j])
			var sx := (hgrid[j * n + i1] - hgrid[j * n + i0]) / (xs[i1] - xs[i0])
			var sz := (hgrid[j1 * n + i] - hgrid[j0 * n + i]) / dz
			norms[k] = Vector3(-sx, 1.0, -sz).normalized()
	var idx := PackedInt32Array()
	idx.resize((n - 1) * (n - 1) * 6)
	var q := 0
	for j in n - 1:
		var r0 := j * n
		var r1 := r0 + n
		for i in n - 1:
			var a := r0 + i
			idx[q] = a
			idx[q + 1] = a + 1
			idx[q + 2] = r1 + i + 1
			idx[q + 3] = a
			idx[q + 4] = r1 + i + 1
			idx[q + 5] = r1 + i
			q += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	terrain_mat = Mats.terrain()
	_terrain_colors()
	mi.material_override = terrain_mat
	add_child(mi)


func _terrain_colors() -> void:
	var m := terrain_mat
	var bi := {"desert": 0, "mountain": 1, "green": 2, "coastal": 3, "urban": 4}
	m.set_shader_parameter("biome", bi.get(biome, 0))
	m.set_shader_parameter("core_size", CORE)
	m.set_shader_parameter("water_level", water_level)
	m.set_shader_parameter("field_top", float(map.get("field_top", 100000.0)))
	match biome:
		"desert":
			_tc(Color(0.72, 0.62, 0.47), Color(0.64, 0.54, 0.4), Color(0.52, 0.45, 0.37), Color(0.5, 0.46, 0.4), Color(0.7, 0.62, 0.5), Color(0.42, 0.42, 0.28))
			dust_color = Color(0.7, 0.62, 0.5)
			m.set_shader_parameter("base_heat", 0.26)
		"mountain":
			_tc(Color(0.52, 0.47, 0.38), Color(0.44, 0.4, 0.32), Color(0.42, 0.4, 0.38), Color(0.5, 0.46, 0.4), Color(0.6, 0.54, 0.44), Color(0.3, 0.34, 0.22))
			m.set_shader_parameter("c_snow", Color(0.88, 0.9, 0.93))
			m.set_shader_parameter("snow_line", 1950.0)
			dust_color = Color(0.58, 0.53, 0.45)
		"green":
			_tc(Color(0.36, 0.42, 0.24), Color(0.45, 0.42, 0.3), Color(0.42, 0.4, 0.35), Color(0.36, 0.35, 0.33), Color(0.5, 0.46, 0.38), Color(0.26, 0.36, 0.17))
			dust_color = Color(0.5, 0.46, 0.38)
			m.set_shader_parameter("base_heat", 0.2)
		"coastal":
			_tc(Color(0.62, 0.57, 0.45), Color(0.55, 0.52, 0.4), Color(0.5, 0.47, 0.42), Color(0.33, 0.33, 0.33), Color(0.55, 0.53, 0.48), Color(0.35, 0.4, 0.24))
			dust_color = Color(0.6, 0.56, 0.48)
		"urban":
			# a dusty Afghan basin, a little scrub and garden green
			_tc(Color(0.62, 0.56, 0.45), Color(0.55, 0.5, 0.41), Color(0.48, 0.44, 0.39), Color(0.27, 0.27, 0.28), Color(0.56, 0.52, 0.45), Color(0.34, 0.38, 0.24))
			dust_color = Color(0.5, 0.49, 0.46)
	var tarr: Array[Vector4] = []
	for t in towns:
		if tarr.size() < 8:
			tarr.append(Vector4(t.pos.x, t.pos.y, t.r, 0.0))
	while tarr.size() < 8:
		tarr.append(Vector4(0, 0, 0, 0))
	m.set_shader_parameter("towns", tarr)
	m.set_shader_parameter("town_count", mini(towns.size(), 8))


func _tc(g: Color, g2: Color, rock: Color, road: Color, town: Color, veg: Color) -> void:
	terrain_mat.set_shader_parameter("c_ground", g)
	terrain_mat.set_shader_parameter("c_ground2", g2)
	terrain_mat.set_shader_parameter("c_rock", rock)
	terrain_mat.set_shader_parameter("c_road", road)
	terrain_mat.set_shader_parameter("c_town", town)
	terrain_mat.set_shader_parameter("c_veg", veg)


# --- Roads --------------------------------------------------------------

func _parse_road(r) -> void:
	if r is String:
		var bits: PackedStringArray = r.split(":")
		var nums := bits[1].split(",")
		var cx := float(nums[0])
		var cz := float(nums[1])
		var rad := float(nums[2])
		if bits[0] == "loop":
			var pts := PackedVector2Array()
			for k in 17:
				var a := TAU * k / 16.0
				pts.append(Vector2(cx + cos(a) * rad, cz + sin(a) * rad))
			roads.append(pts)
		elif bits[0] == "grid":
			var spacing := float(nums[3])
			var kmax := int(rad / spacing)
			for k in range(-kmax, kmax + 1):
				var o := k * spacing
				streets.append(PackedVector2Array([Vector2(cx + o, cz - rad), Vector2(cx + o, cz + rad)]))
				streets.append(PackedVector2Array([Vector2(cx - rad, cz + o), Vector2(cx + rad, cz + o)]))
			roads.append(PackedVector2Array([Vector2(cx - rad, cz), Vector2(cx + rad, cz)]))
	else:
		roads.append(PackedVector2Array(r))


func _paint_roads() -> void:
	road_img = Image.create_empty(ROAD_RES, ROAD_RES, false, Image.FORMAT_L8)
	road_img.fill(Color(0, 0, 0))
	for r in roads:
		_paint_poly(r, 8.0)
	for s in streets:
		_paint_poly(s, 10.0)
	var tex := ImageTexture.create_from_image(road_img)
	terrain_mat.set_shader_parameter("road_tex", tex)


func _paint_poly(pts: PackedVector2Array, w: float) -> void:
	var ppm := ROAD_RES / CORE
	var wpx := maxi(2, int(round(w * ppm)))
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var steps := int(a.distance_to(b) * ppm) + 1
		for s in steps + 1:
			var p := a.lerp(b, float(s) / steps)
			var px := int((p.x + CORE * 0.5) * ppm) - wpx / 2
			var py := int((p.y + CORE * 0.5) * ppm) - wpx / 2
			road_img.fill_rect(Rect2i(px, py, wpx, wpx), Color(1, 1, 1))


func road_at(p: Vector2) -> float:
	var ppm := ROAD_RES / CORE
	var px := int((p.x + CORE * 0.5) * ppm)
	var py := int((p.y + CORE * 0.5) * ppm)
	if px < 0 or py < 0 or px >= ROAD_RES or py >= ROAD_RES:
		return 0.0
	return road_img.get_pixel(px, py).r


func road_near(p: Vector2, r: float) -> bool:
	if road_at(p) > 0.3:
		return true
	for k in 8:
		var a := TAU * k / 8.0
		if road_at(p + Vector2(cos(a), sin(a)) * r) > 0.3:
			return true
	return false


## Points along a map road for vehicles, every ~30 m, with ground height.
func route_points(road_i: int, reversed: bool, f0: float, f1: float) -> Array:
	var pts: PackedVector2Array = roads[clampi(road_i, 0, roads.size() - 1)]
	if reversed:
		var rp := PackedVector2Array()
		for k in range(pts.size() - 1, -1, -1):
			rp.append(pts[k])
		pts = rp
	var total := 0.0
	for k in pts.size() - 1:
		total += pts[k].distance_to(pts[k + 1])
	var out: Array = []
	var d0 := total * f0
	var d1 := total * f1
	var d := d0
	while d <= d1 + 0.1:
		var p := _along(pts, d)
		out.append(Vector3(p.x, height(p.x, p.y), p.y))
		d += 30.0
	return out


## Road network as a graph: points every 40 m, joined along each road and
## wherever two roads come within 25 m of each other.
func _build_road_graph() -> void:
	var cell := {}
	for list in [roads, streets]:
		for pts in list:
			var prev := -1
			var total := 0.0
			for k in pts.size() - 1:
				total += pts[k].distance_to(pts[k + 1])
			var d := 0.0
			while d <= total + 0.1:
				var p := _along(pts, d)
				var id := road_nodes.size()
				road_nodes.append(p)
				road_adj.append([])
				if prev >= 0:
					road_adj[id].append(prev)
					road_adj[prev].append(id)
				var key := Vector2i(floori(p.x / 25.0), floori(p.y / 25.0))
				for dx in [-1, 0, 1]:
					for dz in [-1, 0, 1]:
						var k2 := key + Vector2i(dx, dz)
						if cell.has(k2):
							for other in cell[k2]:
								if other != prev and road_nodes[other].distance_to(p) < 25.0 and other not in road_adj[id]:
									road_adj[id].append(other)
									road_adj[other].append(id)
				if not cell.has(key):
					cell[key] = []
				cell[key].append(id)
				prev = id
				d += 40.0


static func _heap_push(h: Array, item: Array) -> void:
	h.append(item)
	var i := h.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if h[parent][0] <= h[i][0]:
			break
		var tmp = h[parent]
		h[parent] = h[i]
		h[i] = tmp
		i = parent


static func _heap_pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if not h.is_empty():
		h[0] = last
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < h.size() and h[l][0] < h[m][0]:
				m = l
			if r < h.size() and h[r][0] < h[m][0]:
				m = r
			if m == i:
				break
			var tmp = h[m]
			h[m] = h[i]
			h[i] = tmp
			i = m
	return top


func _nearest_node(p: Vector2) -> int:
	var best := -1
	var bd := 1.0e18
	for i in road_nodes.size():
		var d := road_nodes[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


## A driving route from a to b: along the roads when that isn't a big
## detour, otherwise straight across country.
func drive_path(a: Vector3, b: Vector3) -> Array:
	if road_nodes.is_empty():
		_build_road_graph()
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var straight := a2.distance_to(b2)
	var out: Array = []
	var na := _nearest_node(a2)
	var nb := _nearest_node(b2)
	if na >= 0 and nb >= 0:
		# Dijkstra over a few thousand nodes
		var n := road_nodes.size()
		var dist := PackedFloat32Array()
		dist.resize(n)
		dist.fill(1.0e18)
		var from := PackedInt32Array()
		from.resize(n)
		from.fill(-1)
		var done := PackedByteArray()
		done.resize(n)
		dist[na] = 0.0
		var heap: Array = [[0.0, na]]
		while not heap.is_empty():
			var top: Array = _heap_pop(heap)
			var cur: int = top[1]
			if done[cur] == 1:
				continue
			done[cur] = 1
			if cur == nb:
				break
			for nxt in road_adj[cur]:
				var nd := dist[cur] + road_nodes[cur].distance_to(road_nodes[nxt])
				if nd < dist[nxt]:
					dist[nxt] = nd
					from[nxt] = cur
					_heap_push(heap, [nd, nxt])
		if from[nb] >= 0 or na == nb:
			var road_len := dist[nb] + a2.distance_to(road_nodes[na]) + b2.distance_to(road_nodes[nb])
			if road_len < straight * 2.2 + 300.0:
				var chain: Array = []
				var c := nb
				while c >= 0:
					chain.push_front(c)
					c = from[c]
				out.append(a)
				for id in chain:
					out.append(to3(road_nodes[id]))
				out.append(b)
				return out
	var steps := maxi(1, int(straight / 50.0))
	for k in steps + 1:
		out.append(to3(a2.lerp(b2, float(k) / steps)))
	return out


static func _along(pts: PackedVector2Array, dist: float) -> Vector2:
	var acc := 0.0
	for k in pts.size() - 1:
		var seg := pts[k].distance_to(pts[k + 1])
		if acc + seg >= dist:
			return pts[k].lerp(pts[k + 1], (dist - acc) / maxf(seg, 0.001))
		acc += seg
	return pts[pts.size() - 1]


# --- Water and bridges ----------------------------------------------------

func _build_water() -> void:
	if water_level < -1000.0:
		return
	var pm := PlaneMesh.new()
	pm.size = Vector2(FAR * 2.0, FAR * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = Mats.water()
	mi.position = Vector3(0, water_level, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_bridges() -> void:
	for b in bridges:
		var bp: Vector2 = b
		# deck follows the nearest road direction
		var dir := Vector2.RIGHT
		for r in roads:
			for k in r.size() - 1:
				if _seg_dist(bp, r[k], r[k + 1]) < 30.0:
					dir = (r[k + 1] - r[k]).normalized()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var ang := atan2(dir.x, dir.y)
		var y := height(bp.x, bp.y) + 0.4
		Meshes.boxc(st, Vector3.ZERO, Vector3(10.0, 1.0, 90.0), Color(0.5, 0.49, 0.46, 0.55))
		Meshes.boxc(st, Vector3(-4.8, 1.0, 0), Vector3(0.4, 1.0, 90.0), Color(0.45, 0.44, 0.42, 0.5))
		Meshes.boxc(st, Vector3(4.8, 1.0, 0), Vector3(0.4, 1.0, 90.0), Color(0.45, 0.44, 0.42, 0.5))
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = Mats.solid()
		mi.set_instance_shader_parameter("heat", 0.3)
		mi.position = Vector3(bp.x, y - 0.5, bp.y)
		mi.rotation.y = ang
		add_child(mi)


# --- Buildings ------------------------------------------------------------

func _excluded(p: Vector2, r: float) -> bool:
	for e in exclusions:
		if p.distance_to(Vector2(e.x, e.y)) < e.z + r:
			return true
	return false


## True when a circle of radius r at p comes within half a road width of
## any road or street (exact distance to every road segment).
func touches_road(p: Vector2, r: float) -> bool:
	for list in [roads, streets]:
		for pts in list:
			for k in pts.size() - 1:
				var a: Vector2 = pts[k]
				var b: Vector2 = pts[k + 1]
				if _seg_dist(p, a, b) < r + 6.0:
					return true
	return false


func _add_bld(c: Vector2, w: float, d: float, h: float, ang: float, col: Color, kind: String, windows: bool, hp: float, heat := 0.33, near_road_ok := false, roof := "") -> void:
	if not near_road_ok and touches_road(c, 0.5 * sqrt(w * w + d * d)):
		return
	var ca := cos(ang)
	var sa := sin(ang)
	var ax := Vector2(ca, -sa)
	var az := Vector2(sa, ca)
	var gc := height(c.x, c.y)
	if gc < water_level + 0.6:
		return
	var gmin := gc
	for cr in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector2 = c + ax * (w * 0.5 * cr.x) + az * (d * 0.5 * cr.y)
		gmin = minf(gmin, height(p.x, p.y))
	var base := gmin - 0.6
	buildings.append({
		"c": Vector3(c.x, gc, c.y), "w": w, "d": d, "base": base, "top": gc + h, "ang": ang,
		"ca": ca, "sa": sa, "hp": hp, "maxhp": hp, "alive": true, "kind": kind, "col": col,
		"win": windows, "seed": rng.randi() % 1000, "heat": heat, "props": [],
	})
	if roof == "":
		roof = {"house": "flat", "tall": "city", "shed": "shed", "mosque": "dome"}.get(kind, "none")
	_decorate(buildings.size() - 1, roof)


func _prop(bi: int, mesh_id: String, xf: Transform3D, col: Color, heat: float) -> void:
	if not props.has(mesh_id):
		props[mesh_id] = []
	props[mesh_id].append({"xf": xf, "col": col, "heat": heat})
	buildings[bi].props.append([mesh_id, props[mesh_id].size() - 1])


## Roof furniture: parapets, water tanks, AC units, dishes, pitched and
## shed roofs, a dome and minaret on a mosque.
func _decorate(bi: int, roof: String) -> void:
	if roof == "none":
		return
	var b: Dictionary = buildings[bi]
	var R := Basis(Vector3.UP, b.ang)
	var top := Vector3(b.c.x, b.top, b.c.z)
	var w: float = b.w
	var d: float = b.d
	var col: Color = b.col
	var at := func(lx: float, ly: float, lz: float) -> Vector3:
		return top + R * Vector3(lx, ly, lz)
	match roof:
		"flat", "city":
			if roof == "city" or rng.randf() < 0.7:
				var ph := 0.8
				var t := 0.25
				var pc := col.darkened(0.08)
				_prop(bi, "cube", Transform3D(R * Basis.from_scale(Vector3(w, ph, t)), at.call(0.0, 0.0, d * 0.5 - t * 0.5)), pc, b.heat)
				_prop(bi, "cube", Transform3D(R * Basis.from_scale(Vector3(w, ph, t)), at.call(0.0, 0.0, -d * 0.5 + t * 0.5)), pc, b.heat)
				_prop(bi, "cube", Transform3D(R * Basis.from_scale(Vector3(t, ph, d)), at.call(w * 0.5 - t * 0.5, 0.0, 0.0)), pc, b.heat)
				_prop(bi, "cube", Transform3D(R * Basis.from_scale(Vector3(t, ph, d)), at.call(-w * 0.5 + t * 0.5, 0.0, 0.0)), pc, b.heat)
			if rng.randf() < (0.55 if roof == "city" else 0.3) and w > 4.0 and d > 4.0:
				var tc: Color = [Color(0.85, 0.85, 0.82), Color(0.12, 0.12, 0.13), Color(0.25, 0.35, 0.55)][rng.randi() % 3]
				_prop(bi, "prop_tank", Transform3D(R * Basis.from_scale(Vector3(1.4, 1.3, 1.4)), at.call(rng.randf_range(-0.3, 0.3) * w, 0.0, rng.randf_range(-0.3, 0.3) * d)), tc, 0.3)
			if roof == "city":
				for k in rng.randi() % 4:
					_prop(bi, "cube", Transform3D(R * Basis.from_scale(Vector3(0.9, 0.7, 0.7)), at.call(rng.randf_range(-0.38, 0.38) * w, 0.0, rng.randf_range(-0.38, 0.38) * d)), Color(0.75, 0.75, 0.72), 0.5)
				if rng.randf() < 0.3:
					_prop(bi, "prop_dish", Transform3D(R * Basis(Vector3.UP, rng.randf() * TAU), at.call(rng.randf_range(-0.35, 0.35) * w, 0.0, rng.randf_range(-0.35, 0.35) * d)), Color(0.8, 0.8, 0.78), 0.3)
		"pitched":
			var rh := minf(w, d) * 0.32
			var rc: Color = [Color(0.6, 0.28, 0.2), Color(0.38, 0.38, 0.4), Color(0.5, 0.33, 0.25)][rng.randi() % 3]
			var long_x := w >= d
			var sc := Vector3(w + 0.6, rh, d + 0.6) if long_x else Vector3(d + 0.6, rh, w + 0.6)
			var rb := R if long_x else R * Basis(Vector3.UP, PI * 0.5)
			_prop(bi, "prop_roof", Transform3D(rb * Basis.from_scale(sc), top), rc, 0.33)
		"shed":
			var long_x2 := w >= d
			var sc2 := Vector3(w, 1.6, d) if long_x2 else Vector3(d, 1.6, w)
			var rb2 := R if long_x2 else R * Basis(Vector3.UP, PI * 0.5)
			_prop(bi, "prop_roof", Transform3D(rb2 * Basis.from_scale(sc2), top), col.darkened(0.15), b.heat)
		"dome":
			var dc: Color = [Color(0.88, 0.86, 0.8), Color(0.2, 0.55, 0.55), Color(0.75, 0.62, 0.3)][rng.randi() % 3]
			_prop(bi, "prop_dome", Transform3D(R * Basis.from_scale(Vector3(w * 0.75, w * 0.45, d * 0.75)), top), dc, 0.3)
			var corner: Vector3 = at.call(w * 0.5 + 1.6, 0.0, -d * 0.5 - 1.6)
			corner.y = height(corner.x, corner.z) - 0.5
			_prop(bi, "prop_minaret", Transform3D(Basis.from_scale(Vector3(2.4, (b.top - b.base) * 3.0, 2.4)), corner), col.lightened(0.05), 0.32)


func _outpost_walls(c: Vector2, s: float, h: float, t: float, col: Color, gate_side: int, gate_w: float, hp: float, ang := 0.0, road_ok := false) -> void:
	var ax := Vector2(cos(ang), -sin(ang))
	var az := Vector2(sin(ang), cos(ang))
	var half := s * 0.5
	var normals := [-az, ax, az, -ax]
	var alongs := [ax, az, ax, az]
	for side in 4:
		var nrm: Vector2 = normals[side]
		var along: Vector2 = alongs[side]
		var wc: Vector2 = c + nrm * half
		var horizontal: bool = side % 2 == 0
		if side == gate_side:
			var seg := (s - gate_w) * 0.5
			for sgn in [-1.0, 1.0]:
				var sc: Vector2 = wc + along * (sgn * (gate_w * 0.5 + seg * 0.5))
				if horizontal:
					_add_bld(sc, seg, t, h, ang, col, "wall", false, hp, 0.3, road_ok)
				else:
					_add_bld(sc, t, seg, h, ang, col, "wall", false, hp, 0.3, road_ok)
		else:
			if horizontal:
				_add_bld(wc, s + t, t, h, ang, col, "wall", false, hp, 0.3, road_ok)
			else:
				_add_bld(wc, t, s + t, h, ang, col, "wall", false, hp, 0.3, road_ok)


func _build_outposts() -> void:
	var sites: Dictionary = map.get("sites", {})
	var outposts: Dictionary = map.get("outposts", {})
	for sname in sites:
		var c: Vector2 = sites[sname]
		if outposts.has(sname):
			exclusions.append(Vector3(c.x, c.y, float(outposts[sname]) * 0.8 + 8.0))
		else:
			exclusions.append(Vector3(c.x, c.y, 30.0))
	for sname in outposts:
		var c: Vector2 = sites[sname]
		var s := float(outposts[sname])
		var hesco := Color(0.66, 0.6, 0.47)
		if biome == "urban":
			hesco = Color(0.58, 0.58, 0.56)
		# the gate faces the nearest road
		var to_road := Vector2(0, 1)
		var best := 1.0e9
		for r in roads:
			for k in r.size() - 1:
				var d := _seg_dist(c, r[k], r[k + 1])
				if d < best:
					best = d
					var ab: Vector2 = r[k + 1] - r[k]
					var tt := clampf((c - r[k]).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
					to_road = (r[k] + ab * tt - c).normalized()
		var normals := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
		var side := 2
		for k in 4:
			if to_road.dot(normals[k]) > to_road.dot(normals[side]):
				side = k
		gates[sname] = normals[side]
		_outpost_walls(c, s, 2.4, 1.6, hesco, side, 9.0, 900.0, 0.0, true)
		if s >= 45.0:
			for cr in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				_add_bld(c + cr * (s * 0.5 - 2.0), 3.4, 3.4, 6.5, 0.0, Color(0.55, 0.5, 0.42), "tower", false, 700.0, 0.33, true)
			var huts := int(s / 14.0)
			for k in huts:
				var hp2 := Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3)) * s
				if hp2.length() < 16.0:
					# keep the middle clear for a helicopter
					hp2 = hp2.normalized() * 16.0 if hp2.length() > 0.1 else Vector2(16.0, 0.0)
				var vertical := rng.randf() < 0.5
				var hw := 6.0 if vertical else 12.0
				var hd := 12.0 if vertical else 6.0
				var cols := [Color(0.5, 0.5, 0.42), Color(0.62, 0.58, 0.48), Color(0.4, 0.44, 0.36)]
				_add_bld(c + hp2, hw, hd, 3.0, 0.0, cols[k % 3], "hut", false, 900.0, 0.36, true)
		else:
			_add_bld(c + Vector2(4, -4), 6.0, 3.0, 2.6, 0.0, Color(0.5, 0.5, 0.42), "hut", false, 700.0, 0.36, true)


func _gen_town(t: Dictionary) -> void:
	var style: String = t.get("style", "compound")
	var c: Vector2 = t.pos
	var r: float = t.r
	var ang: float = t.get("ang", rng.randf() * PI)
	t["ang"] = ang
	var blocks := {"compound": 44.0, "village": 54.0, "city": 62.0, "industrial": 85.0, "mixed": 40.0}
	var block: float = blocks.get(style, 44.0)
	var u := Vector2(cos(ang), -sin(ang))
	var v := Vector2(sin(ang), cos(ang))
	var n := int(r / block) + 1
	for gi in range(-n, n + 1):
		for gj in range(-n, n + 1):
			var lc := c + u * (gi * block) + v * (gj * block)
			if style == "village":
				lc += Vector2(rng.randf_range(-14, 14), rng.randf_range(-14, 14))
			var dist := lc.distance_to(c)
			if dist > r:
				continue
			var dens: float = float(t.get("density", 0.85)) * (1.0 - pow(dist / r, 2.0) * 0.55)
			if style == "village":
				dens *= 0.55
			if rng.randf() > dens:
				continue
			var lot := block - 10.0
			if _excluded(lc, lot * 0.6) or road_near(lc, lot * 0.55 + 3.0):
				continue
			var st := style
			if style == "mixed":
				st = "city" if dist < r * 0.33 else "suburb"
			match st:
				"compound":
					_lot_compound(lc, lot, ang)
				"village":
					_lot_village(lc, lot, ang + rng.randf_range(-0.25, 0.25))
				"city":
					_lot_city(lc, lot, ang, dist / r)
				"suburb":
					_lot_suburb(lc, lot, ang)
				"industrial":
					_lot_industrial(lc, lot, ang)


	# a mosque near the middle of every town
	if style in ["compound", "village", "city", "mixed"]:
		for k in 30:
			var a := rng.randf() * TAU
			var mp: Vector2 = c + Vector2(cos(a), sin(a)) * rng.randf_range(20.0, r * 0.35)
			var ms := rng.randf_range(12.0, 18.0)
			if not _excluded(mp, ms) and not touches_road(mp, ms) and not in_building(mp, ms * 0.8):
				_add_bld(mp, ms, ms, rng.randf_range(6.0, 8.0), ang, Color(0.86, 0.83, 0.76), "mosque", false, 4000.0)
				break

func _mud() -> Color:
	var k := rng.randf_range(-0.05, 0.05)
	return Color(0.66 + k, 0.56 + k, 0.43 + k * 0.8)


func _lot_compound(lc: Vector2, lot: float, ang: float) -> void:
	var wall := _mud()
	_outpost_walls(lc, lot, 2.6, 0.6, wall, rng.randi() % 4, 4.0, 450.0, ang)
	var ax := Vector2(cos(ang), -sin(ang))
	var az := Vector2(sin(ang), cos(ang))
	var half := lot * 0.5
	var placed: Array = []
	for k in 1 + rng.randi() % 3:
		var hw := rng.randf_range(6.0, minf(13.0, lot * 0.45))
		var hd := rng.randf_range(5.0, minf(9.0, lot * 0.35))
		var side := rng.randi() % 4
		var lx := 0.0
		var lz := 0.0
		var ww := hw
		var dd := hd
		if side % 2 == 1:
			ww = hd
			dd = hw
		var slide := rng.randf_range(-1.0, 1.0)
		match side:
			0:
				lz = -(half - dd * 0.5 - 0.8)
				lx = slide * (half - ww * 0.5 - 1.0)
			1:
				lx = half - ww * 0.5 - 0.8
				lz = slide * (half - dd * 0.5 - 1.0)
			2:
				lz = half - dd * 0.5 - 0.8
				lx = slide * (half - ww * 0.5 - 1.0)
			3:
				lx = -(half - ww * 0.5 - 0.8)
				lz = slide * (half - dd * 0.5 - 1.0)
		var rect := Rect2(lx - ww * 0.5, lz - dd * 0.5, ww, dd)
		var ok := true
		for p in placed:
			if rect.grow(1.0).intersects(p):
				ok = false
		if not ok:
			continue
		placed.append(rect)
		var floors := 1 if rng.randf() < 0.75 else 2
		var col := _mud().lightened(0.04)
		_add_bld(lc + ax * lx + az * lz, ww, dd, 3.3 * floors, ang, col, "house", false, 1300.0 * floors)


func _lot_village(lc: Vector2, lot: float, ang: float) -> void:
	var ax := Vector2(cos(ang), -sin(ang))
	var az := Vector2(sin(ang), cos(ang))
	var stone := biome != "desert"
	var col := Color(0.6, 0.57, 0.5) if stone else _mud()
	var w := rng.randf_range(7.0, 13.0)
	var d := rng.randf_range(6.0, 10.0)
	var floors := 1 if rng.randf() < 0.7 else 2
	_add_bld(lc, w, d, 3.2 * floors, ang, col, "house", false, 1300.0 * floors)
	if rng.randf() < 0.5:
		_add_bld(lc + ax * (w * 0.5 + 4.0) + az * rng.randf_range(-3, 3), 4.0, 5.0, 2.6, ang, col.darkened(0.08), "shed", false, 800.0)
	if rng.randf() < 0.35:
		_add_bld(lc + az * (d * 0.5 + 6.0), lot * 0.8, 0.5, 1.6, ang, col.darkened(0.05), "wall", false, 300.0)


func _lot_city(lc: Vector2, lot: float, ang: float, frac: float) -> void:
	var ax := Vector2(cos(ang), -sin(ang))
	var palette := [Color(0.72, 0.71, 0.68), Color(0.62, 0.6, 0.55), Color(0.78, 0.74, 0.66), Color(0.86, 0.85, 0.82), Color(0.6, 0.55, 0.5), Color(0.5, 0.52, 0.55)]
	var hmax := lerpf(38.0, 10.0, clampf(frac, 0.0, 1.0))
	var two := rng.randf() < 0.4
	var count := 2 if two else 1
	for k in count:
		var w := lot * (0.44 if two else rng.randf_range(0.7, 0.95))
		var d := lot * rng.randf_range(0.65, 0.95)
		var floors := maxi(2, int(rng.randf_range(6.0, hmax) / 3.2))
		var h := floors * 3.2 + 0.6
		var off := Vector2.ZERO
		if two:
			off = ax * (lot * 0.26 * (-1.0 if k == 0 else 1.0))
		var col: Color = palette[rng.randi() % palette.size()]
		_add_bld(lc + off, w, d, h, ang, col, "tall", true, 1800.0 + h * 90.0, 0.34)
		if rng.randf() < 0.35:
			_add_bld(lc + off + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)), rng.randf_range(3, 6), rng.randf_range(3, 6), h + 2.6, ang, col.darkened(0.15), "roof", false, 600.0)


func _lot_suburb(lc: Vector2, lot: float, ang: float) -> void:
	var palette := [Color(0.8, 0.76, 0.68), Color(0.7, 0.62, 0.52), Color(0.62, 0.66, 0.7), Color(0.75, 0.7, 0.58), Color(0.66, 0.5, 0.42)]
	var col: Color = palette[rng.randi() % palette.size()]
	var w := rng.randf_range(9.0, 13.0)
	var d := rng.randf_range(8.0, 11.0)
	var floors := 1 if rng.randf() < 0.55 else 2
	_add_bld(lc + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)), w, d, 3.3 * floors + 0.4, ang, col, "house", true, 1200.0 * floors, 0.33, false, "pitched")
	if rng.randf() < 0.3:
		var ax := Vector2(cos(ang), -sin(ang))
		_add_bld(lc + ax * (w * 0.5 + 4.0), 5.0, 6.0, 2.8, ang, col.darkened(0.1), "shed", false, 700.0)


func _lot_industrial(lc: Vector2, lot: float, ang: float) -> void:
	if rng.randf() < 0.45:
		var cols := [Color(0.62, 0.2, 0.15), Color(0.2, 0.32, 0.55), Color(0.3, 0.45, 0.3), Color(0.8, 0.8, 0.78), Color(0.75, 0.55, 0.2)]
		var az := Vector2(sin(ang), cos(ang))
		var ax := Vector2(cos(ang), -sin(ang))
		for row in 3:
			for stack in 1 + rng.randi() % 3:
				var p := lc + az * ((row - 1) * 8.0) + ax * rng.randf_range(-6.0, 6.0)
				_add_bld(p, 12.2, 2.5, 2.6 * (stack + 1), ang, cols[rng.randi() % cols.size()], "container", false, 500.0)
		return
	var w := rng.randf_range(25.0, minf(55.0, lot))
	var d := rng.randf_range(30.0, minf(65.0, lot))
	var col := Color(0.55, 0.58, 0.6) if rng.randf() < 0.6 else Color(0.6, 0.47, 0.38)
	_add_bld(lc, w, d, rng.randf_range(8.0, 14.0), ang, col, "shed", false, 3000.0)


func _make_building_multimesh() -> void:
	var cube := Meshes.get_mesh("cube")
	bmm = MultiMesh.new()
	bmm.transform_format = MultiMesh.TRANSFORM_3D
	bmm.use_custom_data = true
	bmm.mesh = cube
	bmm.instance_count = buildings.size()
	for i in buildings.size():
		_update_building(i)
		_grid_add(i)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = bmm
	mmi.material_override = Mats.building()
	add_child(mmi)
	for mesh_id in props:
		var list: Array = props[mesh_id]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = Meshes.get_mesh(mesh_id)
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i].xf)
			var pc: Color = list[i].col
			mm.set_instance_custom_data(i, Color(pc.r, pc.g, pc.b, float(list[i].heat)))
		var pmi := MultiMeshInstance3D.new()
		pmi.multimesh = mm
		pmi.material_override = Mats.tree()
		add_child(pmi)
		prop_mm[mesh_id] = mm


func _update_building(i: int) -> void:
	var b: Dictionary = buildings[i]
	var basis := Basis(Vector3.UP, b.ang) * Basis.from_scale(Vector3(b.w, b.top - b.base, b.d))
	bmm.set_instance_transform(i, Transform3D(basis, Vector3(b.c.x, b.base, b.c.z)))
	var col: Color = b.col
	var packed: float = (1000.0 if b.win else 0.0) + float(b.seed) + clampf(b.heat, 0.0, 0.99)
	bmm.set_instance_custom_data(i, Color(col.r, col.g, col.b, packed))


func _grid_add(i: int) -> void:
	var b: Dictionary = buildings[i]
	var rad: float = 0.5 * sqrt(b.w * b.w + b.d * b.d)
	var x0 := floori((b.c.x - rad) / BCELL)
	var x1 := floori((b.c.x + rad) / BCELL)
	var z0 := floori((b.c.z - rad) / BCELL)
	var z1 := floori((b.c.z + rad) / BCELL)
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var key := Vector2i(cx, cz)
			if not bgrid.has(key):
				bgrid[key] = []
			bgrid[key].append(i)


func buildings_near(p: Vector2, r: float) -> Array:
	var out: Array = []
	var seen := {}
	for cx in range(floori((p.x - r) / BCELL), floori((p.x + r) / BCELL) + 1):
		for cz in range(floori((p.y - r) / BCELL), floori((p.y + r) / BCELL) + 1):
			var key := Vector2i(cx, cz)
			if bgrid.has(key):
				for bi in bgrid[key]:
					if not seen.has(bi):
						seen[bi] = true
						out.append(bi)
	return out


func in_building(p: Vector2, margin: float) -> bool:
	var key := Vector2i(floori(p.x / BCELL), floori(p.y / BCELL))
	if not bgrid.has(key):
		return false
	for bi in bgrid[key]:
		var b: Dictionary = buildings[bi]
		if not b.alive:
			continue
		var dx: float = p.x - b.c.x
		var dz: float = p.y - b.c.z
		var lx: float = dx * b.ca - dz * b.sa
		var lz: float = dx * b.sa + dz * b.ca
		if absf(lx) < b.w * 0.5 + margin and absf(lz) < b.d * 0.5 + margin:
			return true
	return false


## Slides a ground position out of any standing building it is inside.
## Climbers (the infected) go over walls and only houses stop them.
func push_out(pos: Vector3, r: float, climber := false) -> Vector3:
	var key := Vector2i(floori(pos.x / BCELL), floori(pos.z / BCELL))
	if not bgrid.has(key):
		return pos
	for bi in bgrid[key]:
		var b: Dictionary = buildings[bi]
		if not b.alive or (climber and b.kind == "wall"):
			continue
		var dx: float = pos.x - b.c.x
		var dz: float = pos.z - b.c.z
		var ca: float = b.ca
		var sa: float = b.sa
		var lx := dx * ca - dz * sa
		var lz := dx * sa + dz * ca
		var hw: float = b.w * 0.5 + r
		var hd: float = b.d * 0.5 + r
		if absf(lx) < hw and absf(lz) < hd:
			if hw - absf(lx) < hd - absf(lz):
				lx = hw if lx >= 0.0 else -hw
			else:
				lz = hd if lz >= 0.0 else -hd
			pos.x = b.c.x + ca * lx + sa * lz
			pos.z = b.c.z - sa * lx + ca * lz
	return pos


func ground_ok(p: Vector2) -> bool:
	if absf(p.x) > CORE * 0.5 - 50.0 or absf(p.y) > CORE * 0.5 - 50.0:
		return false
	if height(p.x, p.y) < water_level + 0.5:
		return false
	return not in_building(p, 1.0)


## A random free ground spot within radius of centre.
func free_spot(center: Vector2, radius: float) -> Vector3:
	for k in 24:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * radius
		var p := center + Vector2(cos(a), sin(a)) * d
		if ground_ok(p):
			return Vector3(p.x, height(p.x, p.y), p.y)
	return Vector3(center.x, height(center.x, center.y), center.y)


func damage_buildings(pos: Vector3, radius: float, dmg: float, pen: int, bidx: int) -> void:
	var mul := 0.0
	if pen >= 3:
		mul = 1.0
	elif pen == 2:
		mul = 0.35
	elif pen == 1:
		mul = 0.05
	if mul <= 0.0:
		return
	var reach := maxf(radius * 0.6, 1.0)
	for bi in buildings_near(Vector2(pos.x, pos.z), radius + 30.0):
		var b: Dictionary = buildings[bi]
		if not b.alive:
			continue
		var dx: float = pos.x - b.c.x
		var dz: float = pos.z - b.c.z
		var lx: float = dx * b.ca - dz * b.sa
		var lz: float = dx * b.sa + dz * b.ca
		var ex := maxf(0.0, absf(lx) - b.w * 0.5)
		var ez := maxf(0.0, absf(lz) - b.d * 0.5)
		var ey := maxf(0.0, maxf(b.base - pos.y, pos.y - b.top))
		var dist := sqrt(ex * ex + ey * ey + ez * ez)
		if bi == bidx:
			dist = 0.0
		if dist > reach:
			continue
		b.hp -= dmg * mul * (1.0 - dist / reach)
		if b.hp <= 0.0:
			_collapse(bi)


func _collapse(bi: int) -> void:
	var b: Dictionary = buildings[bi]
	b.alive = false
	for pr in b.props:
		var mm: MultiMesh = prop_mm.get(pr[0])
		if mm:
			mm.set_instance_transform(pr[1], Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(b.c.x, b.base, b.c.z)))
	var h: float = b.top - b.base
	b.top = b.base + maxf(h * 0.22, 0.8)
	b.col = b.col.darkened(0.45)
	b.heat = 0.55
	b.win = false
	_update_building(bi)
	if battle:
		if battle.get("recorder"):
			battle.recorder.building(bi)
		battle.effects.collapse(b.c, maxf(b.w, b.d), h)


func site(sname: String) -> Vector3:
	var sites: Dictionary = map.get("sites", {})
	var p: Vector2 = sites.get(sname, Vector2.ZERO)
	return Vector3(p.x, height(p.x, p.y), p.y)


func to3(p: Vector2) -> Vector3:
	return Vector3(p.x, height(p.x, p.y), p.y)


# --- Raycasts -----------------------------------------------------------

## Ray against terrain, water and buildings.
## Returns {} or {pos, t, bidx (-1 = ground), water}.
func raycast(o: Vector3, d: Vector3, maxd := 30000.0) -> Dictionary:
	var hor := Vector2(d.x, d.z).length()
	var slope_k := 1.2 if biome == "mountain" else 0.6
	var denom := maxf(-d.y + hor * slope_k, 0.02)
	var t := 0.0
	var pt := 0.0
	var hit := false
	for i in 400:
		var p := o + d * t
		var gap := p.y - height(p.x, p.z)
		if gap <= 0.0:
			hit = true
			break
		if t >= maxd:
			break
		pt = t
		t += maxf(gap / denom * 0.9, 0.5)
	if not hit:
		return {}
	var lo := pt
	var hi := t
	for k in 14:
		var mid := (lo + hi) * 0.5
		var p := o + d * mid
		if p.y - height(p.x, p.z) > 0.0:
			lo = mid
		else:
			hi = mid
	var best := hi
	var res := {"pos": o + d * hi, "t": hi, "bidx": -1, "water": false}
	if d.y < 0.0 and water_level > -1000.0:
		var tw := (water_level - o.y) / d.y
		if tw > 0.0 and tw < best:
			best = tw
			res = {"pos": o + d * tw, "t": tw, "bidx": -1, "water": true}
	var hp: Vector3 = res.pos
	for bi in buildings_near(Vector2(hp.x, hp.z), 90.0):
		var tb := _ray_box(o, d, buildings[bi])
		if tb >= 0.0 and tb < best:
			best = tb
			res = {"pos": o + d * tb, "t": tb, "bidx": bi, "water": false}
	return res


## True when nothing solid lies between a and b: terrain, and (if
## with_buildings) houses and other buildings. Compound walls don't block
## (people fire over them), nor does anything within 8 m of either end
## (firing from a doorway or round a corner).
func los(a: Vector3, b: Vector3, with_buildings := true) -> bool:
	var d := b - a
	var L := d.length()
	if L < 2.0:
		return true
	var n := clampi(int(L / 12.0), 2, 150)
	for i in range(1, n):
		var f := float(i) / n
		if f * L < 5.0 or (1.0 - f) * L < 5.0:
			continue
		var p := a + d * f
		if p.y < height(p.x, p.z) - 0.3:
			return false
	if not with_buildings:
		return true
	var dir := d / L
	var seen := {}
	var step := BCELL * 0.5
	var k := 0.0
	while k <= L + step:
		var p := a + dir * minf(k, L)
		var key := Vector2i(floori(p.x / BCELL), floori(p.z / BCELL))
		if bgrid.has(key):
			for bi in bgrid[key]:
				if seen.has(bi):
					continue
				seen[bi] = true
				var bd: Dictionary = buildings[bi]
				if not bd.alive or bd.kind == "wall":
					continue
				var tb := _ray_box(a, dir, bd)
				if tb > 8.0 and tb < L - 8.0:
					return false
		k += step
	return true


func _ray_box(o: Vector3, d: Vector3, b: Dictionary) -> float:
	var ca: float = b.ca
	var sa: float = b.sa
	var dx: float = o.x - b.c.x
	var dz: float = o.z - b.c.z
	var lo := Vector3(dx * ca - dz * sa, o.y, dx * sa + dz * ca)
	var ld := Vector3(d.x * ca - d.z * sa, d.y, d.x * sa + d.z * ca)
	var mn := Vector3(-b.w * 0.5, b.base, -b.d * 0.5)
	var mx := Vector3(b.w * 0.5, b.top, b.d * 0.5)
	var tmin := -1.0e9
	var tmax := 1.0e9
	for a in 3:
		if absf(ld[a]) < 1.0e-6:
			if lo[a] < mn[a] or lo[a] > mx[a]:
				return -1.0
		else:
			var t1 := (mn[a] - lo[a]) / ld[a]
			var t2 := (mx[a] - lo[a]) / ld[a]
			if t1 > t2:
				var tt := t1
				t1 = t2
				t2 = tt
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return -1.0
	if tmax < 0.0:
		return -1.0
	return maxf(tmin, 0.0)


# --- Trees --------------------------------------------------------------

func _tree_density(p: Vector2, h: float) -> float:
	var nm := n_mid.get_noise_2d(p.x * 1.7, p.y * 1.7)
	match biome:
		"desert":
			var d := 0.015
			if road_near(p, 35.0):
				d = 0.25
			for t in towns:
				var td: float = p.distance_to(t.pos)
				if td < t.r * 1.3 and td > t.r * 0.5:
					d = maxf(d, 0.3)
			return d
		"mountain":
			var valley := 1.0 - smoothstep(700.0, 1100.0, p.length())
			return clampf(0.1 + nm * 0.9, 0.0, 0.8) * (1.0 - valley * 0.6) * (1.0 - smoothstep(1500.0, 1700.0, h))
		"green":
			var q := Vector2(0.96 * p.x - 0.28 * p.y, 0.28 * p.x + 0.96 * p.y)
			var fq := Vector2(fposmod(q.x / 110.0, 1.0), fposmod(q.y / 160.0, 1.0))
			var edge := minf(minf(fq.x, 1.0 - fq.x), minf(fq.y, 1.0 - fq.y))
			var d := 0.02
			if edge < 0.025:
				d = 0.55
			if nm > 0.25:
				d = 0.85
			return d
		"coastal":
			return 0.06 + (0.3 if nm > 0.35 else 0.0)
		"urban":
			if road_near(p, 9.0):
				return 0.12
			return 0.3 if nm > 0.4 else 0.03
	return 0.05


func _build_trees() -> void:
	var count := int(float(map.get("tree_count", 1000)) * float(Game.settings.get("trees", 1.0)))
	var kinds := {"desert": ["palm", "bush"], "mountain": ["conifer", "conifer", "broad"], "green": ["broad", "broad", "bush", "conifer"],
		"coastal": ["palm", "broad", "bush"], "urban": ["broad", "broad", "bush"]}
	var klist: Array = kinds.get(biome, ["broad"])
	var lists := {}
	for k in klist:
		lists[k] = []
	var placed := 0
	for tries in count * 6:
		if placed >= count:
			break
		var p := Vector2(rng.randf_range(-3800.0, 3800.0), rng.randf_range(-3800.0, 3800.0))
		var h := height(p.x, p.y)
		if h < water_level + 1.0:
			continue
		if rng.randf() > _tree_density(p, h):
			continue
		if road_at(p) > 0.05 or road_near(p, 6.0) or in_building(p, 3.0) or _excluded(p, 4.0):
			continue
		var inner := false
		for t in towns:
			if p.distance_to(t.pos) < t.r * 0.55 and biome != "urban":
				inner = true
		if inner and rng.randf() < 0.85:
			continue
		var kind: String = klist[rng.randi() % klist.size()]
		var s := rng.randf_range(0.7, 1.35)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.2), s)), Vector3(p.x, h - 0.2, p.y))
		lists[kind].append(xf)
		placed += 1
	for kind in lists:
		var xfs: Array = lists[kind]
		if xfs.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = Meshes.get_mesh("tree_" + kind)
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
			var v := rng.randf_range(0.8, 1.15)
			mm.set_instance_custom_data(i, Color(v, v * rng.randf_range(0.95, 1.05), v * 0.95, 0.27 + rng.randf() * 0.04))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = Mats.tree()
		add_child(mmi)


# --- Sky and light --------------------------------------------------------

func _setup_sky(weather: String) -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	we.environment = env
	add_child(we)
	sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_aerial_perspective = 0.2
	env.fog_sky_affect = 0.5
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	sun = DirectionalLight3D.new()
	add_child(sun)
	sun.shadow_enabled = bool(Game.settings.get("shadows", true))
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	var el := 52.0
	var az := 140.0
	var fog_d := 0.000045
	match tod:
		"day":
			night = 0.0
			sun.light_color = Color(1.0, 0.96, 0.9)
			sun.light_energy = 1.15
			sky_mat.sky_top_color = Color(0.3, 0.48, 0.74)
			sky_mat.sky_horizon_color = Color(0.72, 0.76, 0.8)
			sky_mat.ground_horizon_color = Color(0.65, 0.66, 0.66)
			sky_mat.ground_bottom_color = Color(0.3, 0.28, 0.25)
			env.ambient_light_energy = 0.4
			env.fog_light_color = Color(0.7, 0.74, 0.78)
		"dusk":
			night = 0.35
			el = 7.0
			az = 255.0
			sun.light_color = Color(1.0, 0.62, 0.38)
			sun.light_energy = 0.95
			sky_mat.sky_top_color = Color(0.16, 0.18, 0.32)
			sky_mat.sky_horizon_color = Color(0.86, 0.52, 0.36)
			sky_mat.ground_horizon_color = Color(0.5, 0.36, 0.3)
			sky_mat.ground_bottom_color = Color(0.15, 0.12, 0.1)
			env.ambient_light_energy = 0.55
			env.fog_light_color = Color(0.55, 0.43, 0.4)
			fog_d = 0.0001
		_:
			night = 1.0
			el = 38.0
			az = 60.0
			sun.light_color = Color(0.62, 0.7, 0.95)
			sun.light_energy = 0.1
			sky_mat.sky_top_color = Color(0.004, 0.006, 0.016)
			sky_mat.sky_horizon_color = Color(0.02, 0.025, 0.04)
			sky_mat.ground_horizon_color = Color(0.015, 0.017, 0.02)
			sky_mat.ground_bottom_color = Color(0.005, 0.005, 0.006)
			sky_mat.sky_energy_multiplier = 0.6
			env.ambient_light_energy = 0.6
			env.fog_light_color = Color(0.02, 0.025, 0.035)
			fog_d = 0.00007
	match weather:
		"haze":
			fog_d *= 2.0
		"dust":
			fog_d *= 3.2
			env.fog_light_color = env.fog_light_color.lerp(dust_color, 0.6 if night < 0.5 else 0.1)
	env.fog_density = fog_d
	var dir := Vector3(cos(deg_to_rad(el)) * sin(deg_to_rad(az)), sin(deg_to_rad(el)), cos(deg_to_rad(el)) * cos(deg_to_rad(az)))
	sun.basis = Basis.looking_at(-dir, Vector3.UP)
	RenderingServer.global_shader_parameter_set("night", night)
	RenderingServer.global_shader_parameter_set("scene_light", lerpf(1.0, 0.07, night))
	tv = {
		"fog_density": env.fog_density, "fog_light_color": env.fog_light_color,
		"ambient_light_energy": env.ambient_light_energy, "sun_energy": sun.light_energy,
	}


func apply_view_mode(m: int) -> void:
	if m >= 2:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.03, 0.03, 0.03) if m == 2 else Color(0.97, 0.97, 0.97)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		env.fog_light_color = Color(0.2, 0.2, 0.2) if m == 2 else Color(0.8, 0.8, 0.8)
		env.fog_density = float(tv.fog_density) * 0.55
		env.fog_sky_affect = 0.0
		env.fog_aerial_perspective = 0.0
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.glow_enabled = false
		sun.shadow_enabled = false
		sun.light_energy = 0.0
	else:
		env.background_mode = Environment.BG_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.fog_light_color = tv.fog_light_color
		env.fog_density = tv.fog_density
		env.fog_sky_affect = 0.5
		env.fog_aerial_perspective = 0.2
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.glow_enabled = true
		sun.shadow_enabled = bool(Game.settings.get("shadows", true))
		sun.light_energy = tv.sun_energy


## Fits the shadow cascades around what the sensor is looking at, so shadows
## stay sharp at high zoom even 4-5 km from the camera.
func fit_shadows(slant: float, view_h: float) -> void:
	if sun == null or not sun.shadow_enabled:
		return
	var w := clampf(view_h * 1.5, 60.0, 3000.0)
	var maxd := minf(slant + w * 2.0, 14000.0)
	sun.directional_shadow_max_distance = maxd
	var s1 := clampf((slant - w) / maxd, 0.02, 0.9)
	var s2 := clampf((slant + w * 0.5) / maxd, s1 + 0.01, 0.95)
	var s3 := clampf((slant + w) / maxd, s2 + 0.01, 0.98)
	sun.directional_shadow_split_1 = s1
	sun.directional_shadow_split_2 = s2
	sun.directional_shadow_split_3 = s3
