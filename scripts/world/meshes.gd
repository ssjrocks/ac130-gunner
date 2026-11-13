extends RefCounted
## Low-poly meshes built in code: people, vehicles, trees, aircraft and the
## building cube. Vertex alpha is the thermal heat multiplier (0.5 = 1x).

static var _cache := {}

const SKIN := [Color(0.78, 0.62, 0.5), Color(0.62, 0.46, 0.34), Color(0.45, 0.32, 0.24), Color(0.85, 0.7, 0.6)]


static func get_mesh(id: String) -> Mesh:
	if _cache.has(id):
		return _cache[id]
	var m := _build(id)
	_cache[id] = m
	return m


# People carry a limb tag in UV2 for the walking animation in the unit
# shader: x = limb (0 none, 1/2 left/right leg, 3/4 left/right arm),
# y = height of the joint it swings from.
static var _uv2_on := false
static var _uv2 := Vector2.ZERO


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	# Godot front faces are clockwise; fix the order so the face looks along n.
	if (c - a).cross(b - a).dot(n) < 0.0:
		var t := b
		b = c
		c = t
	for v in [a, b, c]:
		st.set_color(col)
		st.set_normal(n)
		if _uv2_on:
			st.set_uv2(_uv2)
		st.add_vertex(v)


## A tapered cylinder from a to b (radius r0 at a, r1 at b).
static func cyl_between(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, seg: int, col: Color, caps := true, squash := 1.0) -> void:
	var up := (b - a)
	var h := up.length()
	if h < 0.0001:
		return
	var y := up / h
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized() * squash
	cyl(st, Transform3D(Basis(x, y, z), a), r0, r1, h, seg, col, caps)


## A low-poly ball (latitude/longitude rings).
static func ball(st: SurfaceTool, c: Vector3, r: Vector3, col: Color, rings := 4, seg := 8) -> void:
	for i in rings:
		var t0 := PI * i / rings - PI * 0.5
		var t1 := PI * (i + 1) / rings - PI * 0.5
		for j in seg:
			var p0 := TAU * j / seg
			var p1 := TAU * (j + 1) / seg
			var q := [Vector3(cos(t0) * cos(p0), sin(t0), cos(t0) * sin(p0)), Vector3(cos(t0) * cos(p1), sin(t0), cos(t0) * sin(p1)),
				Vector3(cos(t1) * cos(p1), sin(t1), cos(t1) * sin(p1)), Vector3(cos(t1) * cos(p0), sin(t1), cos(t1) * sin(p0))]
			var n: Vector3 = (q[0] + q[1] + q[2] + q[3]).normalized()
			var w: Array = []
			for v in q:
				w.append(c + v * r)
			if i > 0:
				_tri(st, w[0], w[1], w[2], n, col)
			if i < rings - 1:
				_tri(st, w[0], w[2], w[3], n, col)


static func box(st: SurfaceTool, xf: Transform3D, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	for axis in 3:
		for s in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = s
			var ua := (axis + 1) % 3
			var va := (axis + 2) % 3
			var pts: Array[Vector3] = []
			for uv in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var p := Vector3.ZERO
				p[axis] = s * h[axis]
				p[ua] = uv.x * h[ua]
				p[va] = uv.y * h[va]
				pts.append(xf * p)
			var wn := (xf.basis * n).normalized()
			_tri(st, pts[0], pts[1], pts[2], wn, col)
			_tri(st, pts[0], pts[2], pts[3], wn, col)


static func boxc(st: SurfaceTool, center: Vector3, size: Vector3, col: Color, rot := Vector3.ZERO) -> void:
	var b := Basis.from_euler(rot)
	box(st, Transform3D(b, center), size, col)


## Cylinder/cone along +Y of xf from 0 to h.
static func cyl(st: SurfaceTool, xf: Transform3D, r0: float, r1: float, h: float, seg: int, col: Color, caps := true) -> void:
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var p00 := xf * (d0 * r0)
		var p10 := xf * (d1 * r0)
		var p01 := xf * (d0 * r1 + Vector3(0, h, 0))
		var p11 := xf * (d1 * r1 + Vector3(0, h, 0))
		var slope := (r0 - r1) / maxf(h, 0.001)
		var nm := (xf.basis * ((d0 + d1).normalized() + Vector3(0, slope, 0))).normalized()
		_tri(st, p00, p10, p11, nm, col)
		if r1 > 0.001:
			_tri(st, p00, p11, p01, nm, col)
		if caps:
			var up := (xf.basis * Vector3.UP).normalized()
			if r1 > 0.001:
				_tri(st, xf * Vector3(0, h, 0), p01, p11, up, col)
			_tri(st, xf * Vector3.ZERO, p10, p00, -up, col)


static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _c(r: float, g: float, b: float, heat := 0.5) -> Color:
	return Color(r, g, b, heat)


static func _build(id: String) -> Mesh:
	var parts := id.split("_")
	match parts[0]:
		"inf":
			return _infantry(id)
		"cube":
			return _cube()
		"tree":
			return _tree(parts[1])
		"heli":
			return _heli()
		"rotor":
			return _rotor()
		"missile":
			return _missile()
		"bomb":
			return _bomb()
		"jet":
			return _jet(parts[1])
		"prop":
			return _prop(parts[1])
		_:
			return _vehicle(id)


static func _cube() -> Mesh:
	var st := _st()
	box(st, Transform3D(Basis(), Vector3(0, 0.5, 0)), Vector3.ONE, _c(1, 1, 1))
	return st.commit()


# --- People -------------------------------------------------------------

static func _infantry(id: String) -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var top := _c(0.45, 0.42, 0.32)
	var pants := _c(0.42, 0.4, 0.3)
	var skin: Color = SKIN[rng.randi() % SKIN.size()]
	var hat := "none"      # helmet, wrap, cap, scarf, hair
	var hat_col := _c(0.36, 0.35, 0.27, 0.4)
	var gear := _c(0.24, 0.23, 0.18, 0.45)
	var weapon := 1        # 0 none, 1 rifle, 2 rocket launcher
	var vest := true
	var pack := false
	var robe := false
	var zombie := false
	var boots := _c(0.12, 0.1, 0.08, 0.45)
	if id.begins_with("inf_friendly"):
		top = _c(0.47, 0.44, 0.34); pants = _c(0.44, 0.42, 0.32)
		hat = "helmet"; hat_col = _c(0.4, 0.38, 0.29, 0.4); pack = true
		skin = SKIN[0]
	elif id.begins_with("inf_sf"):
		top = _c(0.3, 0.3, 0.25); pants = _c(0.32, 0.31, 0.25); gear = _c(0.2, 0.2, 0.16, 0.45)
		hat = "helmet"; hat_col = _c(0.26, 0.26, 0.21, 0.4); pack = true
	elif id.begins_with("inf_enemy"):
		var cols := [Color(0.55, 0.5, 0.4), Color(0.24, 0.23, 0.22), Color(0.4, 0.38, 0.3), Color(0.62, 0.6, 0.56), Color(0.35, 0.3, 0.25)]
		var c: Color = cols[rng.randi() % cols.size()]
		top = _c(c.r, c.g, c.b)
		var c2: Color = cols[rng.randi() % cols.size()]
		pants = _c(c2.r * 0.9, c2.g * 0.9, c2.b * 0.9)
		var hc: Color = cols[rng.randi() % cols.size()]
		hat_col = _c(hc.r, hc.g, hc.b, 0.5)
		hat = ["wrap", "wrap", "cap", "none"][rng.randi() % 4]
		robe = rng.randf() < 0.35
		vest = rng.randf() < 0.6
		skin = SKIN[1 + rng.randi() % 2]
		if id.ends_with("rpg"):
			weapon = 2
	elif id.begins_with("inf_civ") or id.begins_with("inf_surv"):
		var shirts := [Color(0.2, 0.3, 0.55), Color(0.86, 0.85, 0.8), Color(0.6, 0.2, 0.18), Color(0.25, 0.45, 0.3), Color(0.7, 0.6, 0.3), Color(0.5, 0.45, 0.5), Color(0.9, 0.88, 0.82)]
		var sc: Color = shirts[rng.randi() % shirts.size()]
		top = _c(sc.r, sc.g, sc.b)
		pants = _c(0.2, 0.22, 0.3) if rng.randf() < 0.6 else _c(0.45, 0.4, 0.32)
		hat_col = _c(0.2, 0.15, 0.1, 0.55)
		var survivor := id.begins_with("inf_surv")
		vest = survivor and rng.randf() < 0.5
		weapon = 1 if survivor else 0
		if not survivor:
			match rng.randi() % 4:
				0:
					robe = true
					top = _c(0.9, 0.89, 0.85)
					hat = "wrap"
					hat_col = _c(0.85, 0.85, 0.82, 0.5)
				1:
					robe = true
					top = _c(0.12, 0.12, 0.14)
					hat = "scarf"
					hat_col = _c(0.12, 0.12, 0.14, 0.5)
				2:
					hat = "cap"
				_:
					hat = "hair"
		else:
			hat = ["cap", "hair", "helmet"][rng.randi() % 3]
	elif id.begins_with("inf_zombie"):
		zombie = true
		var rags := [Color(0.35, 0.33, 0.3), Color(0.3, 0.35, 0.4), Color(0.45, 0.35, 0.3), Color(0.5, 0.48, 0.42)]
		var r: Color = rags[rng.randi() % rags.size()]
		top = _c(r.r, r.g, r.b, 0.45)
		pants = _c(r.r * 0.7, r.g * 0.7, r.b * 0.7, 0.45)
		skin = Color(0.5, 0.55, 0.45)
		hat = "hair"
		weapon = 0
		vest = false
	elif id.begins_with("inf_vip"):
		top = _c(0.12, 0.12, 0.14); pants = _c(0.12, 0.12, 0.14); hat = "hair"
		weapon = 0
		vest = false
	elif id.begins_with("inf_pilot"):
		top = _c(0.42, 0.46, 0.36); pants = _c(0.42, 0.46, 0.36); hat = "helmet"; hat_col = _c(0.4, 0.43, 0.36, 0.45)
		weapon = 0
	var skin_c := Color(skin.r, skin.g, skin.b, 0.6 if not zombie else 0.46)
	var st := _st()
	_uv2_on = true
	var hip := 0.92
	# legs (swing from the hip) with boots
	for side in [-1.0, 1.0]:
		_uv2 = Vector2(1.0 if side < 0.0 else 2.0, hip)
		if not robe:
			cyl_between(st, Vector3(side * 0.1, hip, 0.0), Vector3(side * 0.1, 0.48, 0.01), 0.085, 0.07, 7, pants)
			cyl_between(st, Vector3(side * 0.1, 0.48, 0.01), Vector3(side * 0.105, 0.09, 0.0), 0.07, 0.055, 7, pants)
		else:
			cyl_between(st, Vector3(side * 0.1, 0.4, 0.0), Vector3(side * 0.105, 0.09, 0.0), 0.06, 0.05, 6, pants)
		boxc(st, Vector3(side * 0.105, 0.05, -0.04), Vector3(0.11, 0.1, 0.27), boots)
	_uv2 = Vector2.ZERO
	if robe:
		# a long tunic over the legs
		cyl_between(st, Vector3(0, 0.22, 0), Vector3(0, 1.42, 0), 0.24, 0.19, 9, top, true, 0.75)
	else:
		boxc(st, Vector3(0, hip, 0), Vector3(0.32, 0.16, 0.2), pants)
		cyl_between(st, Vector3(0, 0.95, 0), Vector3(0, 1.43, 0), 0.165, 0.2, 9, top, true, 0.65)
	if vest:
		boxc(st, Vector3(0, 1.2, 0), Vector3(0.38, 0.4, 0.27), gear)
		for x in [-0.1, 0.0, 0.1]:
			boxc(st, Vector3(x, 1.08, -0.15), Vector3(0.08, 0.12, 0.06), gear.darkened(0.15))
	if pack:
		boxc(st, Vector3(0, 1.22, 0.2), Vector3(0.32, 0.42, 0.16), gear.darkened(0.1))
	# arms: carried weapons fix them in a firing grip; otherwise they swing
	var sh_y := 1.4
	if zombie:
		for side in [-1.0, 1.0]:
			cyl_between(st, Vector3(side * 0.22, sh_y, 0.0), Vector3(side * 0.2, 1.36, -0.3), 0.06, 0.05, 6, top)
			cyl_between(st, Vector3(side * 0.2, 1.36, -0.3), Vector3(side * 0.18, 1.34, -0.55), 0.05, 0.045, 6, skin_c)
	elif weapon == 1:
		cyl_between(st, Vector3(0.22, sh_y, 0.0), Vector3(0.24, 1.16, -0.05), 0.06, 0.05, 6, top)
		cyl_between(st, Vector3(0.24, 1.16, -0.05), Vector3(0.1, 1.22, -0.28), 0.05, 0.042, 6, top)
		cyl_between(st, Vector3(-0.22, sh_y, 0.0), Vector3(-0.2, 1.2, -0.18), 0.06, 0.05, 6, top)
		cyl_between(st, Vector3(-0.2, 1.2, -0.18), Vector3(0.0, 1.26, -0.5), 0.05, 0.042, 6, top)
		var gun := _c(0.09, 0.09, 0.09, 0.25)
		boxc(st, Vector3(0.05, 1.26, -0.38), Vector3(0.05, 0.09, 0.62), gun)
		boxc(st, Vector3(0.05, 1.27, -0.78), Vector3(0.025, 0.025, 0.24), gun)
		boxc(st, Vector3(0.05, 1.16, -0.4), Vector3(0.035, 0.14, 0.06), gun)
	elif weapon == 2:
		cyl_between(st, Vector3(0.22, sh_y, 0.0), Vector3(0.2, 1.42, -0.2), 0.06, 0.05, 6, top)
		cyl_between(st, Vector3(-0.22, sh_y, 0.0), Vector3(-0.08, 1.4, -0.3), 0.06, 0.05, 6, top)
		cyl_between(st, Vector3(0.16, 1.55, 0.55), Vector3(0.16, 1.55, -0.6), 0.055, 0.055, 7, _c(0.28, 0.32, 0.22, 0.25))
		cyl_between(st, Vector3(0.16, 1.55, -0.6), Vector3(0.16, 1.55, -0.85), 0.04, 0.09, 7, _c(0.3, 0.33, 0.24, 0.25))
	else:
		for side in [-1.0, 1.0]:
			_uv2 = Vector2(3.0 if side < 0.0 else 4.0, sh_y)
			cyl_between(st, Vector3(side * 0.22, sh_y, 0.0), Vector3(side * 0.25, 1.12, 0.0), 0.06, 0.05, 6, top)
			cyl_between(st, Vector3(side * 0.25, 1.12, 0.0), Vector3(side * 0.26, 0.88, -0.03), 0.05, 0.04, 6, top)
			ball(st, Vector3(side * 0.26, 0.85, -0.03), Vector3(0.045, 0.05, 0.045), skin_c, 3, 6)
		_uv2 = Vector2.ZERO
	# neck and head
	cyl_between(st, Vector3(0, 1.42, 0), Vector3(0, 1.5, 0), 0.055, 0.05, 6, skin_c)
	ball(st, Vector3(0, 1.6, -0.01), Vector3(0.1, 0.12, 0.11), skin_c, 4, 8)
	match hat:
		"helmet":
			ball(st, Vector3(0, 1.65, 0.0), Vector3(0.125, 0.09, 0.135), hat_col, 3, 8)
			if not id.begins_with("inf_pilot") and not id.begins_with("inf_surv"):
				boxc(st, Vector3(0, 1.69, -0.12), Vector3(0.06, 0.06, 0.07), _c(0.08, 0.08, 0.08, 0.6))
		"wrap":
			ball(st, Vector3(0, 1.66, 0.0), Vector3(0.12, 0.08, 0.125), hat_col, 3, 8)
			boxc(st, Vector3(0, 1.52, 0.09), Vector3(0.2, 0.18, 0.05), hat_col)
		"cap":
			cyl_between(st, Vector3(0, 1.66, 0), Vector3(0, 1.72, 0), 0.11, 0.1, 8, hat_col)
			boxc(st, Vector3(0, 1.665, -0.13), Vector3(0.16, 0.02, 0.1), hat_col)
		"scarf":
			ball(st, Vector3(0, 1.62, 0.01), Vector3(0.125, 0.14, 0.13), hat_col, 4, 8)
			cyl_between(st, Vector3(0, 1.5, 0.01), Vector3(0, 1.36, 0.01), 0.12, 0.2, 8, hat_col)
		"hair":
			ball(st, Vector3(0, 1.65, 0.015), Vector3(0.105, 0.075, 0.115), _c(0.1, 0.07, 0.05, 0.5), 3, 8)
	_uv2_on = false
	return st.commit()


# --- Vehicles -----------------------------------------------------------

## One road wheel: tyre with a hub, axle along X.
static func wheel(st: SurfaceTool, c: Vector3, r: float, w: float) -> void:
	var b := Basis(Vector3(0, 0, 1), -PI * 0.5)
	var tire := _c(0.07, 0.07, 0.07, 0.6)
	var hub := _c(0.32, 0.32, 0.3, 0.55)
	cyl(st, Transform3D(b, c - Vector3(w * 0.5, 0, 0)), r, r, w, 10, tire)
	var sx := signf(c.x) if absf(c.x) > 0.01 else 1.0
	cyl(st, Transform3D(b, c + Vector3(sx * (w * 0.5 - 0.02) - 0.01, 0, 0)), r * 0.55, r * 0.5, 0.04, 8, hub)


static func _wheels(st: SurfaceTool, xs: float, zs: Array, r: float, w: float) -> void:
	for z in zs:
		for sx in [-1.0, 1.0]:
			wheel(st, Vector3(sx * xs, r, z), r, w)


## Windows round a cab: windscreen (front), side windows, rear window.
static func _glass(st: SurfaceTool, c: Vector3, size: Vector3, rake := 0.0) -> void:
	var g := _c(0.07, 0.09, 0.12, 0.4)
	boxc(st, c + Vector3(0, 0, -size.z * 0.5), Vector3(size.x * 0.92, size.y, 0.04), g, Vector3(rake, 0, 0))
	for sx in [-1.0, 1.0]:
		boxc(st, c + Vector3(sx * size.x * 0.5, 0, 0), Vector3(0.04, size.y * 0.85, size.z * 0.8), g)
	boxc(st, c + Vector3(0, 0, size.z * 0.5), Vector3(size.x * 0.8, size.y * 0.8, 0.04), g)


static func _lights(st: SurfaceTool, front_z: float, y: float, xs: float, rear_z: float) -> void:
	for sx in [-1.0, 1.0]:
		boxc(st, Vector3(sx * xs, y, front_z), Vector3(0.22, 0.12, 0.05), _c(0.9, 0.88, 0.75, 0.7))
		boxc(st, Vector3(sx * xs, y, rear_z), Vector3(0.16, 0.1, 0.05), _c(0.6, 0.08, 0.06, 0.6))


static func _vehicle(id: String) -> Mesh:
	var parts := id.split("_")
	var kind := parts[0]
	var paint := _c(0.85, 0.85, 0.82)
	if parts.size() > 1:
		match parts[1]:
			"white": paint = _c(0.8, 0.8, 0.78)
			"tan": paint = _c(0.58, 0.51, 0.38)
			"dark": paint = _c(0.18, 0.19, 0.2)
			"red": paint = _c(0.55, 0.14, 0.12)
			"blue": paint = _c(0.18, 0.26, 0.5)
			"green": paint = _c(0.27, 0.31, 0.21)
			"rust": paint = _c(0.42, 0.28, 0.18)
			"black": paint = _c(0.07, 0.07, 0.08)
			"silver": paint = _c(0.6, 0.62, 0.64)
			"sand": paint = _c(0.52, 0.47, 0.35)
	var dark := _c(0.12, 0.12, 0.12, 0.5)
	var metal := _c(0.2, 0.2, 0.19, 0.4)
	var engine := Color(paint.r, paint.g, paint.b, 0.95)
	var trim := paint.darkened(0.25)
	var st := _st()
	match kind:
		"technical", "pickup":
			# Hilux-style pickup: bonnet, cab, bed, bull bar
			boxc(st, Vector3(0, 0.62, 0), Vector3(1.66, 0.22, 4.9), metal)
			boxc(st, Vector3(0, 0.88, -1.75), Vector3(1.76, 0.42, 1.35), engine)
			boxc(st, Vector3(0, 1.1, -1.75), Vector3(1.68, 0.06, 1.25), paint, Vector3(0.08, 0, 0))
			boxc(st, Vector3(0, 1.0, -0.55), Vector3(1.78, 0.62, 1.15), paint)
			boxc(st, Vector3(0, 1.5, -0.5), Vector3(1.7, 0.42, 1.0), paint)
			_glass(st, Vector3(0, 1.48, -0.52), Vector3(1.72, 0.36, 1.02), 0.35)
			boxc(st, Vector3(0, 1.73, -0.48), Vector3(1.64, 0.06, 0.95), paint)
			boxc(st, Vector3(0, 0.82, 1.2), Vector3(1.74, 0.12, 2.3), trim)
			for sx in [-1.0, 1.0]:
				boxc(st, Vector3(sx * 0.84, 1.06, 1.2), Vector3(0.06, 0.42, 2.3), paint)
			boxc(st, Vector3(0, 1.06, 2.33), Vector3(1.74, 0.42, 0.06), paint)
			boxc(st, Vector3(0, 0.78, -2.48), Vector3(1.7, 0.3, 0.12), metal)
			for sx in [-1.0, 1.0]:
				boxc(st, Vector3(sx * 0.95, 1.38, -1.05), Vector3(0.1, 0.12, 0.06), dark)
			_lights(st, -2.43, 0.92, 0.6, 2.37)
			_wheels(st, 0.82, [-1.6, 1.45], 0.38, 0.27)
			if kind == "technical":
				# DShK on a pintle with a gun shield
				cyl_between(st, Vector3(0, 0.9, 1.1), Vector3(0, 1.9, 1.1), 0.06, 0.05, 6, metal)
				boxc(st, Vector3(0, 2.0, 0.75), Vector3(0.18, 0.2, 0.9), dark)
				cyl_between(st, Vector3(0, 2.02, 0.3), Vector3(0, 2.02, -0.85), 0.04, 0.035, 6, dark)
				boxc(st, Vector3(0, 2.05, 0.35), Vector3(0.75, 0.55, 0.05), metal, Vector3(-0.15, 0, 0))
				boxc(st, Vector3(-0.08, 2.0, 1.05), Vector3(0.12, 0.16, 0.2), _c(0.3, 0.3, 0.2, 0.4))
		"car":
			boxc(st, Vector3(0, 0.55, 0), Vector3(1.74, 0.4, 4.3), paint)
			boxc(st, Vector3(0, 0.78, -1.45), Vector3(1.68, 0.1, 1.3), paint, Vector3(0.06, 0, 0))
			boxc(st, Vector3(0, 0.78, 1.65), Vector3(1.66, 0.1, 0.9), paint, Vector3(-0.06, 0, 0))
			boxc(st, Vector3(0, 1.0, 0.15), Vector3(1.56, 0.42, 1.95), paint)
			_glass(st, Vector3(0, 1.0, 0.15), Vector3(1.58, 0.34, 1.97), 0.5)
			boxc(st, Vector3(0, 1.24, 0.2), Vector3(1.5, 0.05, 1.6), paint)
			boxc(st, Vector3(0, 0.45, -2.17), Vector3(1.74, 0.16, 0.08), metal)
			boxc(st, Vector3(0, 0.45, 2.17), Vector3(1.74, 0.16, 0.08), metal)
			_lights(st, -2.17, 0.62, 0.6, 2.17)
			_wheels(st, 0.8, [-1.35, 1.35], 0.31, 0.21)
		"suv":
			boxc(st, Vector3(0, 0.75, 0), Vector3(1.9, 0.62, 4.7), paint)
			boxc(st, Vector3(0, 1.08, -1.75), Vector3(1.86, 0.06, 1.2), paint, Vector3(0.06, 0, 0))
			boxc(st, Vector3(0, 1.4, 0.4), Vector3(1.84, 0.62, 3.0), paint)
			_glass(st, Vector3(0, 1.42, 0.4), Vector3(1.86, 0.44, 3.02), 0.3)
			boxc(st, Vector3(0, 1.74, 0.4), Vector3(1.82, 0.06, 3.0), paint)
			for z in [-0.4, 0.8]:
				boxc(st, Vector3(0, 1.8, z), Vector3(1.6, 0.05, 0.06), metal)
			boxc(st, Vector3(0, 0.62, -2.37), Vector3(1.86, 0.22, 0.1), metal)
			_lights(st, -2.37, 0.85, 0.65, 2.36)
			_wheels(st, 0.9, [-1.5, 1.45], 0.4, 0.26)
		"truck":
			boxc(st, Vector3(0, 0.75, 0.4), Vector3(1.9, 0.3, 6.8), metal)
			boxc(st, Vector3(0, 1.0, -3.05), Vector3(2.15, 0.7, 1.05), engine)
			boxc(st, Vector3(0, 1.75, -2.45), Vector3(2.3, 1.15, 1.6), paint)
			_glass(st, Vector3(0, 1.95, -2.45), Vector3(2.32, 0.5, 1.62), 0.1)
			boxc(st, Vector3(0, 0.75, -3.62), Vector3(2.2, 0.3, 0.12), metal)
			boxc(st, Vector3(0, 1.12, 1.15), Vector3(2.4, 0.2, 4.6), trim)
			# canvas cover over ribs
			var canvas := _c(paint.r * 0.75, paint.g * 0.8, paint.b * 0.65, 0.45)
			boxc(st, Vector3(0, 1.85, 1.15), Vector3(2.4, 1.3, 4.6), canvas)
			cyl(st, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 2.5, -1.15)), 1.2, 1.2, 4.6, 10, canvas, false)
			for z in [-1.1, 0.0, 1.15, 2.3, 3.4]:
				boxc(st, Vector3(0, 2.52, z), Vector3(2.44, 0.06, 0.06), trim)
			_lights(st, -3.6, 1.0, 0.8, 3.46)
			_wheels(st, 1.0, [-2.7, 0.6, 2.3], 0.5, 0.36)
		"humvee":
			boxc(st, Vector3(0, 0.95, 0.1), Vector3(2.2, 0.75, 4.7), paint)
			boxc(st, Vector3(0, 1.18, -1.75), Vector3(2.12, 0.3, 1.25), engine, Vector3(0.1, 0, 0))
			boxc(st, Vector3(0, 0.95, -2.3), Vector3(1.6, 0.45, 0.1), _c(0.1, 0.1, 0.1, 0.8))
			boxc(st, Vector3(0, 1.65, 0.45), Vector3(2.0, 0.65, 2.3), paint.darkened(0.06))
			_glass(st, Vector3(0, 1.66, 0.45), Vector3(2.02, 0.4, 2.32), 0.2)
			boxc(st, Vector3(0, 2.0, 0.45), Vector3(1.96, 0.06, 2.25), paint)
			for sx in [-1.0, 1.0]:
				boxc(st, Vector3(sx * 1.1, 0.65, 0), Vector3(0.12, 0.35, 4.4), paint.darkened(0.15))
			# turret ring, shield and gun
			cyl(st, Transform3D(Basis(), Vector3(0, 2.02, 0.5)), 0.55, 0.55, 0.12, 10, metal)
			boxc(st, Vector3(0, 2.38, 0.05), Vector3(1.1, 0.6, 0.06), metal, Vector3(-0.1, 0, 0))
			for sx in [-1.0, 1.0]:
				boxc(st, Vector3(sx * 0.55, 2.35, 0.35), Vector3(0.06, 0.5, 0.6), metal)
			cyl_between(st, Vector3(0, 2.32, 0.4), Vector3(0, 2.32, -0.7), 0.05, 0.04, 6, dark)
			_lights(st, -2.33, 1.15, 0.75, 2.45)
			_wheels(st, 1.08, [-1.6, 1.6], 0.46, 0.34)
		"mrap":
			boxc(st, Vector3(0, 0.95, 0.2), Vector3(1.4, 0.6, 5.8), metal, Vector3(0, 0, 0))
			for sx in [-1.0, 1.0]:
				boxc(st, Vector3(sx * 0.65, 0.9, 0.2), Vector3(0.6, 0.12, 5.6), metal, Vector3(0, 0, sx * 0.55))
			boxc(st, Vector3(0, 1.75, 0.6), Vector3(2.5, 1.5, 4.8), paint)
			boxc(st, Vector3(0, 1.3, -2.55), Vector3(2.3, 0.9, 1.4), engine)
			boxc(st, Vector3(0, 2.15, -1.55), Vector3(2.4, 0.75, 0.9), paint)
			_glass(st, Vector3(0, 2.2, -1.55), Vector3(2.42, 0.55, 0.92), 0.15)
			for z in [0.0, 1.2, 2.2]:
				for sx in [-1.0, 1.0]:
					boxc(st, Vector3(sx * 1.26, 2.1, z), Vector3(0.04, 0.32, 0.5), _c(0.07, 0.09, 0.12, 0.4))
			boxc(st, Vector3(0, 2.52, 0.6), Vector3(2.44, 0.06, 4.7), paint)
			cyl(st, Transform3D(Basis(), Vector3(0, 2.55, 0.6)), 0.6, 0.6, 0.12, 10, metal)
			boxc(st, Vector3(0, 2.95, 0.15), Vector3(1.2, 0.65, 0.06), metal)
			cyl_between(st, Vector3(0, 2.9, 0.5), Vector3(0, 2.9, -0.6), 0.06, 0.05, 6, dark)
			_lights(st, -3.26, 1.4, 0.85, 3.0)
			_wheels(st, 1.2, [-2.3, 0.4, 2.2], 0.58, 0.42)
		"btr":
			boxc(st, Vector3(0, 1.3, 0.3), Vector3(2.8, 1.1, 6.0), paint)
			boxc(st, Vector3(0, 1.2, -3.15), Vector3(2.6, 0.9, 1.2), paint, Vector3(-0.55, 0, 0))
			for sx in [-1.0, 1.0]:
				boxc(st, Vector3(sx * 1.3, 1.95, 0.3), Vector3(0.5, 0.35, 6.0), paint, Vector3(0, 0, -sx * 0.45))
			boxc(st, Vector3(0, 2.05, 0.3), Vector3(2.0, 0.2, 6.0), paint)
			boxc(st, Vector3(0, 1.95, 2.6), Vector3(2.4, 0.15, 1.2), engine)
			for z in [-1.8, -0.8]:
				cyl(st, Transform3D(Basis(), Vector3(0.6 * signf(z + 1.3), 2.15, z)), 0.3, 0.3, 0.06, 8, metal)
			cyl(st, Transform3D(Basis(), Vector3(0, 2.15, -0.9)), 0.68, 0.55, 0.55, 10, paint)
			cyl_between(st, Vector3(0, 2.4, -1.4), Vector3(0, 2.4, -3.2), 0.07, 0.06, 6, dark)
			_wheels(st, 1.45, [-2.4, -0.95, 0.75, 2.2], 0.56, 0.36)
		"tank":
			boxc(st, Vector3(0, 1.05, 0), Vector3(3.4, 0.8, 6.9), paint)
			boxc(st, Vector3(0, 0.85, -3.6), Vector3(3.2, 0.5, 0.8), paint, Vector3(-0.6, 0, 0))
			boxc(st, Vector3(0, 1.2, 2.6), Vector3(3.2, 0.7, 1.9), engine)
			for sx in [-1.0, 1.0]:
				boxc(st, Vector3(sx * 1.55, 0.6, 0), Vector3(0.65, 0.9, 6.9), _c(0.09, 0.09, 0.08, 0.6))
				for k in 6:
					wheel(st, Vector3(sx * 1.55, 0.42, -2.6 + k * 1.04), 0.4, 0.5)
				for k in 3:
					wheel(st, Vector3(sx * 1.55, 0.95, -2.0 + k * 2.0), 0.13, 0.3)
				boxc(st, Vector3(sx * 1.88, 1.0, -0.5), Vector3(0.05, 0.45, 5.6), paint.darkened(0.1))
			ball(st, Vector3(0, 1.55, 0.2), Vector3(1.6, 0.5, 1.75), paint, 3, 10)
			boxc(st, Vector3(0, 1.75, 1.3), Vector3(1.6, 0.4, 0.9), paint.darkened(0.08))
			cyl(st, Transform3D(Basis(), Vector3(0.5, 1.95, 0.6)), 0.32, 0.3, 0.15, 8, metal)
			boxc(st, Vector3(0, 1.65, -1.55), Vector3(0.7, 0.45, 0.4), paint)
			cyl_between(st, Vector3(0, 1.68, -1.7), Vector3(0, 1.72, -5.8), 0.11, 0.09, 8, dark)
			cyl_between(st, Vector3(0, 1.72, -5.8), Vector3(0, 1.72, -6.2), 0.15, 0.15, 8, dark)
		"zu23":
			boxc(st, Vector3(0, 0.45, 0), Vector3(1.8, 0.3, 2.4), paint)
			for sx in [-1.0, 1.0]:
				boxc(st, Vector3(sx * 0.9, 0.3, 1.3), Vector3(0.08, 0.08, 1.4), metal, Vector3(0, sx * 0.4, 0))
			cyl(st, Transform3D(Basis(), Vector3(0, 0.6, 0.1)), 0.55, 0.5, 0.25, 10, paint)
			boxc(st, Vector3(0, 1.05, 0.2), Vector3(1.1, 0.6, 1.0), paint)
			boxc(st, Vector3(0, 1.2, 0.75), Vector3(0.4, 0.4, 0.4), metal)
			for sx in [-0.25, 0.25]:
				cyl_between(st, Vector3(sx, 1.25, 0.0), Vector3(sx, 2.3, -1.5), 0.05, 0.04, 6, dark)
				boxc(st, Vector3(sx, 1.4, 0.3), Vector3(0.15, 0.25, 0.4), _c(0.3, 0.3, 0.2, 0.4))
			_wheels(st, 0.9, [0.2], 0.35, 0.2)
		"sam":
			boxc(st, Vector3(0, 0.95, 0), Vector3(3.0, 1.0, 6.5), paint)
			for sx in [-1.0, 1.0]:
				boxc(st, Vector3(sx * 1.45, 0.55, 0), Vector3(0.6, 0.8, 6.4), _c(0.09, 0.09, 0.08, 0.6))
				for k in 5:
					wheel(st, Vector3(sx * 1.45, 0.4, -2.4 + k * 1.2), 0.38, 0.45)
			cyl(st, Transform3D(Basis(), Vector3(0, 1.45, 0.5)), 1.1, 1.0, 0.35, 10, paint)
			for x in [-0.9, 0.0, 0.9]:
				var b := Basis.from_euler(Vector3(0.55, 0, 0))
				cyl(st, Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, 2.3, 2.2)), 0.22, 0.22, 4.6, 8, _c(0.75, 0.75, 0.7))
				box(st, Transform3D(b, Vector3(x, 1.95, 0.2)), Vector3(0.5, 0.12, 4.0), metal)
		"radar":
			boxc(st, Vector3(0, 0.75, 0.3), Vector3(2.0, 0.3, 6.2), metal)
			boxc(st, Vector3(0, 1.5, -2.4), Vector3(2.3, 1.2, 1.5), paint)
			_glass(st, Vector3(0, 1.75, -2.4), Vector3(2.32, 0.45, 1.52), 0.1)
			boxc(st, Vector3(0, 1.7, 0.9), Vector3(2.4, 1.6, 3.8), paint)
			cyl_between(st, Vector3(0, 2.5, 0.9), Vector3(0, 4.3, 0.9), 0.12, 0.1, 6, metal)
			box(st, Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, 4.6, 0.9)), Vector3(3.4, 1.6, 0.15), _c(0.62, 0.64, 0.6))
			_wheels(st, 1.1, [-2.2, 0.4, 2.0], 0.5, 0.35)
		"wreck":
			var burnt := _c(0.15, 0.15, 0.14, 0.9)
			boxc(st, Vector3(0, 1.0, 0), Vector3(2.4, 1.6, 9.0), burnt)
			boxc(st, Vector3(0, 2.4, 4.5), Vector3(0.6, 2.2, 1.8), burnt, Vector3(0, 0, 0.6))
			boxc(st, Vector3(1.0, 0.4, -4.0), Vector3(6.0, 0.15, 0.4), _c(0.1, 0.1, 0.1, 0.8), Vector3(0, 0.7, 0))
			boxc(st, Vector3(-1.2, 0.3, 2.0), Vector3(1.8, 0.1, 0.35), _c(0.1, 0.1, 0.1, 0.8), Vector3(0, -0.4, 0.2))
		_:
			boxc(st, Vector3(0, 1.0, 0), Vector3(2.0, 1.5, 4.5), paint)
	return st.commit()


# --- Aircraft and munitions ---------------------------------------------

static func _heli() -> Mesh:
	var st := _st()
	var body := _c(0.28, 0.3, 0.25)
	var dark := _c(0.12, 0.12, 0.12, 0.5)
	boxc(st, Vector3(0, 1.9, -0.5), Vector3(2.3, 2.0, 6.5), body)
	boxc(st, Vector3(0, 1.7, -4.2), Vector3(1.9, 1.4, 1.4), _c(0.15, 0.18, 0.2, 0.4), Vector3(-0.3, 0, 0))
	boxc(st, Vector3(0, 2.3, 5.0), Vector3(0.6, 0.6, 6.5), body)
	boxc(st, Vector3(0, 3.4, 8.0), Vector3(0.25, 2.2, 1.0), body)
	boxc(st, Vector3(0, 3.05, -0.2), Vector3(1.3, 0.5, 2.6), _c(0.3, 0.3, 0.26, 0.95))
	boxc(st, Vector3(0, 3.5, 0), Vector3(0.3, 0.6, 0.3), dark)
	boxc(st, Vector3(-0.9, 0.35, -0.5), Vector3(0.15, 0.15, 4.0), dark)
	boxc(st, Vector3(0.9, 0.35, -0.5), Vector3(0.15, 0.15, 4.0), dark)
	return st.commit()


static func _rotor() -> Mesh:
	var st := _st()
	cyl(st, Transform3D(), 8.0, 8.0, 0.05, 20, _c(0.1, 0.1, 0.1, 0.35))
	return st.commit()


static func _missile() -> Mesh:
	var st := _st()
	cyl(st, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, 1.2)), 0.18, 0.18, 2.4, 8, _c(0.7, 0.7, 0.68, 0.8))
	return st.commit()


static func _bomb() -> Mesh:
	var st := _st()
	cyl(st, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, 1.6)), 0.28, 0.2, 3.2, 8, _c(0.45, 0.47, 0.4, 0.4))
	return st.commit()


## A-10 (straight wings, engines on the rear fuselage, twin tails) or a
## swept-wing fighter. Nose points along -Z.
static func _jet(kind: String) -> Mesh:
	var st := _st()
	var grey := _c(0.42, 0.44, 0.46)
	var dark := _c(0.2, 0.21, 0.22)
	var hot := _c(0.25, 0.25, 0.25, 0.98)
	var nose := Basis(Vector3.RIGHT, -PI * 0.5)
	if kind == "a10":
		cyl(st, Transform3D(nose, Vector3(0, 0, 8.0)), 0.9, 0.55, 16.0, 8, grey)
		cyl(st, Transform3D(nose, Vector3(0, 0, -8.0)), 0.55, 0.15, 1.6, 8, dark)
		boxc(st, Vector3(0, 0.75, -5.0), Vector3(0.9, 0.5, 1.6), _c(0.15, 0.18, 0.2, 0.4))
		boxc(st, Vector3(0, -0.2, -0.5), Vector3(17.5, 0.25, 2.8), grey)
		for x in [-1.3, 1.3]:
			cyl(st, Transform3D(nose, Vector3(x, 1.2, 5.5)), 0.65, 0.65, 3.4, 10, grey)
			boxc(st, Vector3(x, 1.2, 6.9), Vector3(0.9, 0.9, 0.3), hot)
		boxc(st, Vector3(0, 0.3, 7.6), Vector3(5.6, 0.18, 1.6), grey)
		for x in [-2.7, 2.7]:
			boxc(st, Vector3(x, 1.2, 7.7), Vector3(0.15, 2.4, 1.5), grey)
		boxc(st, Vector3(0, -0.6, -8.4), Vector3(0.2, 0.2, 1.2), dark)
	else:
		cyl(st, Transform3D(nose, Vector3(0, 0, 8.0)), 0.8, 0.5, 13.0, 8, grey)
		cyl(st, Transform3D(nose, Vector3(0, 0, -5.0)), 0.5, 0.05, 3.5, 8, grey)
		boxc(st, Vector3(0, 0.55, -3.0), Vector3(0.8, 0.5, 2.4), _c(0.15, 0.18, 0.2, 0.4))
		for sx in [-1.0, 1.0]:
			box(st, Transform3D(Basis(Vector3.UP, sx * 0.55), Vector3(sx * 2.8, -0.1, 1.5)), Vector3(5.5, 0.18, 3.2), grey)
			box(st, Transform3D(Basis(Vector3.FORWARD, sx * 0.35), Vector3(sx * 1.2, 1.5, 6.6)), Vector3(0.15, 2.4, 1.8), grey)
			box(st, Transform3D(Basis(Vector3.UP, sx * 0.5), Vector3(sx * 1.6, -0.1, 7.6)), Vector3(2.4, 0.15, 1.3), grey)
		boxc(st, Vector3(0, 0, 8.2), Vector3(1.4, 0.8, 0.4), hot)
	return st.commit()


## Roof furniture, white so the instance colour tints it. Origin at the base.
static func _prop(kind: String) -> Mesh:
	var st := _st()
	var w := _c(1, 1, 1)
	match kind:
		"tank":
			cyl(st, Transform3D(), 0.5, 0.5, 1.0, 10, w)
		"dish":
			cyl(st, Transform3D(), 0.04, 0.04, 0.9, 5, _c(0.4, 0.4, 0.4))
			box(st, Transform3D(Basis(Vector3.RIGHT, -0.9), Vector3(0, 1.0, 0)), Vector3(0.9, 0.9, 0.06), w)
		"roof":
			# gable roof over a unit footprint, ridge along X
			var a := Vector3(-0.5, 0, -0.5)
			var b := Vector3(0.5, 0, -0.5)
			var c := Vector3(0.5, 0, 0.5)
			var d := Vector3(-0.5, 0, 0.5)
			var r0 := Vector3(-0.5, 1, 0)
			var r1 := Vector3(0.5, 1, 0)
			var n1 := Vector3(0, 0.5, -1).normalized()
			var n2 := Vector3(0, 0.5, 1).normalized()
			_tri(st, a, b, r1, n1, w)
			_tri(st, a, r1, r0, n1, w)
			_tri(st, d, r1, c, n2, w)
			_tri(st, d, r0, r1, n2, w)
			_tri(st, a, r0, d, Vector3.LEFT, w)
			_tri(st, b, c, r1, Vector3.RIGHT, w)
		"dome":
			ball(st, Vector3.ZERO, Vector3(0.5, 1.0, 0.5), w, 6, 12)
			cyl(st, Transform3D(Basis(), Vector3(0, 0.98, 0)), 0.03, 0.0, 0.18, 6, _c(0.8, 0.7, 0.3))
		"minaret":
			cyl(st, Transform3D(), 0.5, 0.42, 0.82, 10, w)
			cyl(st, Transform3D(Basis(), Vector3(0, 0.78, 0)), 0.72, 0.72, 0.025, 10, w)
			cyl(st, Transform3D(Basis(), Vector3(0, 0.8, 0)), 0.38, 0.36, 0.08, 10, w)
			cyl(st, Transform3D(Basis(), Vector3(0, 0.88, 0)), 0.42, 0.0, 0.12, 10, w)
	return st.commit()


# --- Trees --------------------------------------------------------------

static func _tree(kind: String) -> Mesh:
	var st := _st()
	var trunk := _c(0.32, 0.25, 0.18, 0.55)
	match kind:
		"palm":
			cyl(st, Transform3D(Basis(), Vector3.ZERO), 0.22, 0.15, 9.0, 6, trunk, false)
			for i in 7:
				var a := TAU * i / 7.0
				var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.35)
				box(st, Transform3D(b, Vector3(0, 9.0, 0) + Basis(Vector3.UP, a) * Vector3(0, -0.4, -2.0)), Vector3(0.9, 0.08, 4.2), _c(0.3, 0.38, 0.18, 0.5))
		"conifer":
			cyl(st, Transform3D(Basis(), Vector3.ZERO), 0.25, 0.2, 2.5, 6, trunk, false)
			cyl(st, Transform3D(Basis(), Vector3(0, 2.0, 0)), 2.6, 0.0, 6.0, 8, _c(0.18, 0.26, 0.16, 0.48))
			cyl(st, Transform3D(Basis(), Vector3(0, 5.0, 0)), 2.0, 0.0, 6.0, 8, _c(0.2, 0.28, 0.17, 0.48))
		"bush":
			cyl(st, Transform3D(Basis(), Vector3.ZERO), 1.3, 0.9, 1.4, 7, _c(0.28, 0.33, 0.2, 0.5))
		_:
			cyl(st, Transform3D(Basis(), Vector3.ZERO), 0.3, 0.22, 3.5, 6, trunk, false)
			cyl(st, Transform3D(Basis(), Vector3(0, 2.6, 0)), 2.2, 3.4, 2.2, 9, _c(0.24, 0.32, 0.17, 0.48), false)
			cyl(st, Transform3D(Basis(), Vector3(0, 4.8, 0)), 3.4, 1.6, 2.4, 9, _c(0.26, 0.34, 0.18, 0.48))
	return st.commit()
