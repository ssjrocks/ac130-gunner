extends Node3D
## Pooled visual effects: explosions, smoke, dust, tracers, fire, flashes,
## scorch marks and short-lived lights. Small things keep a minimum size in
## pixels so they stay visible from altitude, like they do on a real sensor.

const Mats := preload("res://scripts/world/mats.gd")
const MAX_PARTS := 1600

var battle
var quad: QuadMesh
var parts: Array = []
var pool := {}
var emitters: Array = []
var lights: Array = []
var light_pool: Array = []
var decals: Array = []
var scorch_tex: ImageTexture
var mpp_k := 0.001       # metres per pixel per metre of distance
var cam_pos := Vector3.ZERO
var recorder = null          # the mission recorder, while one runs
var _depth := 0              # >0 while effects call themselves (not recorded)


func _ready() -> void:
	quad = QuadMesh.new()
	quad.size = Vector2(1, 1)
	for k in ["puff", "glow", "beam", "ir", "irbeam"]:
		pool[k] = []
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, 0.6) * (0.75 + 0.25 * sin(x * 0.9) * cos(y * 0.7))
			img.set_pixel(x, y, Color(0.05, 0.045, 0.04, clampf(a, 0.0, 1.0)))
	scorch_tex = ImageTexture.create_from_image(img)
	for i in 8:
		var l := OmniLight3D.new()
		l.visible = false
		l.shadow_enabled = false
		add_child(l)
		light_pool.append(l)


func take(kind: String) -> MeshInstance3D:
	var list: Array = pool[kind]
	var n: MeshInstance3D
	if list.is_empty():
		n = MeshInstance3D.new()
		n.mesh = quad
		n.material_override = Mats.fx(kind)
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.layers = 4
		add_child(n)
	else:
		n = list.pop_back()
		n.visible = true
	return n


func give(kind: String, n: MeshInstance3D) -> void:
	n.visible = false
	pool[kind].append(n)


func mpp(p: Vector3) -> float:
	return cam_pos.distance_to(p) * mpp_k


## Places a beam node between two points with a minimum on-screen width.
func set_beam(n: MeshInstance3D, a: Vector3, b: Vector3, width: float, min_px: float) -> void:
	var mid := (a + b) * 0.5
	var ax := b - a
	if ax.length_squared() < 0.0001:
		ax = Vector3(0, 0.01, 0)
	var w := maxf(width, mpp(mid) * min_px)
	var side := ax.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized() * w
	n.transform = Transform3D(Basis(side, ax, side.cross(ax).normalized()), mid)


func spawn(kind: String, p: Vector3, opts: Dictionary) -> void:
	if recorder and _depth == 0:
		recorder.note("spawn", [kind, p, opts])
	if parts.size() >= MAX_PARTS:
		return
	var n := take(kind)
	var part := {
		"n": n, "k": kind, "t": 0.0, "life": opts.get("life", 1.0), "p": p, "v": opts.get("v", Vector3.ZERO),
		"s0": opts.get("s0", 1.0), "s1": opts.get("s1", 2.0), "a0": opts.get("a0", 1.0), "a1": opts.get("a1", 0.0),
		"h0": opts.get("h0", 0.5), "h1": opts.get("h1", 0.3), "px": opts.get("px", 0.0), "drag": opts.get("drag", 0.0),
		"rise": opts.get("rise", 0.0), "flick": opts.get("flick", 0.0),
	}
	n.set_instance_shader_parameter("fx_color", opts.get("c", Color(1, 1, 1)))
	n.position = p
	parts.append(part)
	_apply(part, 0.0)


func _apply(p: Dictionary, f: float) -> void:
	var s: float = lerpf(p.s0, p.s1, 1.0 - pow(1.0 - f, 2.0))
	if p.px > 0.0:
		s = maxf(s, mpp(p.p) * p.px)
	var n: MeshInstance3D = p.n
	n.position = p.p
	n.scale = Vector3(s, s, s)
	var a: float = lerpf(p.a0, p.a1, f)
	if p.flick > 0.0:
		a *= 1.0 - p.flick * randf()
	n.set_instance_shader_parameter("fx_alpha", a)
	n.set_instance_shader_parameter("fx_heat", lerpf(p.h0, p.h1, f))


func _process(dt: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam:
		cam_pos = cam.global_position
		var vh := get_viewport().get_visible_rect().size.y
		var fov_deg: float = battle.gunship.fov() if battle and battle.gunship else cam.fov
		mpp_k = 2.0 * tan(deg_to_rad(fov_deg) * 0.5) / maxf(vh, 1.0)
	var i := parts.size() - 1
	while i >= 0:
		var p: Dictionary = parts[i]
		p.t += dt
		if p.t >= p.life:
			give(p.k, p.n)
			parts[i] = parts[parts.size() - 1]
			parts.pop_back()
		else:
			if p.drag > 0.0:
				p.v *= maxf(0.0, 1.0 - p.drag * dt)
			p.v.y += p.rise * dt
			p.p += p.v * dt
			_apply(p, p.t / p.life)
		i -= 1
	_update_tracers(dt)
	_update_emitters(dt)
	_update_lights(dt)


# --- Emitters (fires, smoke columns) ---------------------------------------

func fire(p: Vector3, size: float, life: float, smoke := true) -> void:
	if recorder and _depth == 0:
		recorder.fire(p, size, life, smoke)
	_depth += 1
	_fire(p, size, life, smoke)
	_depth -= 1


func _fire(p: Vector3, size: float, life: float, smoke := true) -> void:
	emitters.append({"p": p, "t": 0.0, "life": life, "size": size, "acc": 0.0, "smoke": smoke})


func _update_emitters(dt: float) -> void:
	var i := emitters.size() - 1
	var sl := 1.0
	while i >= 0:
		var e: Dictionary = emitters[i]
		e.t += dt
		if e.t >= e.life:
			emitters.remove_at(i)
			i -= 1
			continue
		var fade: float = 1.0 - e.t / e.life
		e.acc += dt * (6.0 + e.size) * fade
		var sz: float = e.size
		while e.acc >= 1.0:
			e.acc -= 1.0
			var jitter := Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5)) * sz
			spawn("glow", e.p + jitter + Vector3(0, sz * 0.3, 0), {"life": randf_range(0.25, 0.6), "s0": sz * 0.7, "s1": sz * 0.25, "a0": 0.9, "a1": 0.0,
				"c": Color(1.6, 0.75, 0.25), "h0": 1.0, "h1": 0.8, "v": Vector3(0, sz * 1.5, 0), "px": 1.5, "flick": 0.4})
			if e.smoke and randf() < 0.45 * sl:
				var g := randf_range(0.08, 0.16)
				spawn("puff", e.p + jitter + Vector3(0, sz, 0), {"life": randf_range(6.0, 11.0), "s0": sz * 1.2, "s1": sz * 6.0, "a0": 0.7, "a1": 0.0,
					"c": Color(g, g, g), "h0": 0.6, "h1": 0.3, "v": Vector3(randf_range(1.0, 3.0), sz * 1.2 + 3.0, randf_range(-1.0, 1.0)), "drag": 0.15})
		i -= 1


# --- Lights ----------------------------------------------------------------

func flash_light(p: Vector3, energy: float, rng: float, life: float, col := Color(1.0, 0.7, 0.4)) -> void:
	if light_pool.is_empty():
		return
	var l: OmniLight3D = light_pool.pop_back()
	l.position = p
	l.omni_range = rng
	l.light_color = col
	l.light_energy = energy
	l.visible = true
	lights.append({"l": l, "t": 0.0, "life": life, "e": energy})


func hold_light(p: Vector3, energy: float, rng: float, col: Color) -> OmniLight3D:
	if light_pool.is_empty():
		return null
	var l: OmniLight3D = light_pool.pop_back()
	l.position = p
	l.omni_range = rng
	l.light_color = col
	l.light_energy = energy
	l.visible = true
	return l


func release_light(l: OmniLight3D) -> void:
	if l:
		l.omni_attenuation = 1.0
		l.visible = false
		light_pool.append(l)


func _update_lights(dt: float) -> void:
	var i := lights.size() - 1
	while i >= 0:
		var L: Dictionary = lights[i]
		L.t += dt
		var l: OmniLight3D = L.l
		if L.t >= L.life:
			l.visible = false
			light_pool.append(l)
			lights.remove_at(i)
		else:
			l.light_energy = L.e * (1.0 - L.t / L.life)
		i -= 1


func scorch(p: Vector3, r: float) -> void:
	var d: Decal
	if decals.size() >= 120:
		d = decals.pop_front()
	else:
		d = Decal.new()
		d.texture_albedo = scorch_tex
		d.cull_mask = 1
		add_child(d)
	d.position = p
	d.size = Vector3(r * 2.0, maxf(8.0, r), r * 2.0)
	d.rotation.y = randf() * TAU
	decals.append(d)


# --- Composite effects ------------------------------------------------------

func _dust() -> Color:
	if battle and battle.world:
		return battle.world.dust_color
	return Color(0.6, 0.55, 0.45)


func impact(p: Vector3, fx: String, water: bool) -> void:
	if recorder and _depth == 0:
		recorder.impact(p, fx, water)
	_depth += 1
	_impact(p, fx, water)
	_depth -= 1


func _impact(p: Vector3, fx: String, water: bool) -> void:
	var dc := Color(0.85, 0.9, 0.95) if water else _dust()
	var night: float = battle.world.night if battle else 0.0
	match fx:
		"small":
			spawn("puff", p + Vector3(0, 0.6, 0), {"life": randf_range(1.5, 2.5), "s0": 1.0, "s1": 3.2, "a0": 0.8, "a1": 0.0, "c": dc,
				"h0": 0.45, "h1": 0.3, "v": Vector3(0, 1.2, 0), "px": 1.0})
			spawn("glow", p + Vector3(0, 0.3, 0), {"life": 0.07, "s0": 0.8, "s1": 0.5, "a0": 1.0, "a1": 0.4, "c": Color(1.8, 1.4, 0.8), "h0": 1.0, "h1": 0.9, "px": 1.5})
		"medium":
			spawn("glow", p + Vector3(0, 1.0, 0), {"life": 0.18, "s0": 4.0, "s1": 7.0, "a0": 1.0, "a1": 0.0, "c": Color(2.0, 1.4, 0.6), "h0": 1.0, "h1": 0.9, "px": 3.0})
			for k in 5:
				spawn("puff", p + Vector3(randf_range(-1.5, 1.5), 1.0, randf_range(-1.5, 1.5)), {"life": randf_range(3.0, 6.0), "s0": 2.5, "s1": 8.0,
					"a0": 0.85, "a1": 0.0, "c": dc.darkened(randf_range(0.0, 0.35)), "h0": 0.8, "h1": 0.3, "v": Vector3(randf_range(-2, 2), randf_range(2, 5), randf_range(-2, 2)), "drag": 0.4, "px": 1.0})
			for k in 6:
				spawn("glow", p, {"life": randf_range(0.4, 0.9), "s0": 0.35, "s1": 0.2, "a0": 1.0, "a1": 0.0, "c": Color(2.0, 1.3, 0.5), "h0": 1.0, "h1": 0.7,
					"v": Vector3(randf_range(-14, 14), randf_range(8, 22), randf_range(-14, 14)), "rise": -9.8, "px": 1.0})
			if not water:
				scorch(p, 2.8)
			if night > 0.3:
				flash_light(p + Vector3(0, 4, 0), 6.0, 40.0, 0.25)
		"large":
			_big(p, 1.0, dc, water)
			if night > 0.3:
				flash_light(p + Vector3(0, 10, 0), 12.0, 160.0, 0.5)
		"bomb":
			_big(p, 2.0, dc, water)
			if night > 0.3:
				flash_light(p + Vector3(0, 20, 0), 16.0, 400.0, 0.8)
		"huge":
			_big(p, 3.0, dc, water)
			fire(p, 8.0, 40.0)
			if night > 0.3:
				flash_light(p + Vector3(0, 30, 0), 20.0, 700.0, 1.2)
		"air":
			spawn("glow", p, {"life": 0.25, "s0": 6.0, "s1": 12.0, "a0": 1.0, "a1": 0.0, "c": Color(2.0, 1.5, 0.8), "h0": 1.0, "h1": 0.9, "px": 4.0})
			spawn("puff", p, {"life": 6.0, "s0": 6.0, "s1": 20.0, "a0": 0.6, "a1": 0.0, "c": Color(0.15, 0.15, 0.15), "h0": 0.5, "h1": 0.25, "drag": 0.3, "px": 2.0})
		"flak":
			spawn("glow", p, {"life": 0.12, "s0": 2.0, "s1": 3.5, "a0": 0.9, "a1": 0.0, "c": Color(2.0, 1.6, 1.0), "h0": 1.0, "h1": 0.8, "px": 2.0})
			spawn("puff", p, {"life": 3.0, "s0": 2.0, "s1": 6.0, "a0": 0.5, "a1": 0.0, "c": Color(0.2, 0.2, 0.2), "h0": 0.4, "h1": 0.2, "drag": 0.5, "px": 1.0})


func _big(p: Vector3, scale: float, dc: Color, water: bool) -> void:
	var s := scale
	spawn("glow", p + Vector3(0, 3.0 * s, 0), {"life": 0.3 * s, "s0": 14.0 * s, "s1": 26.0 * s, "a0": 1.0, "a1": 0.0, "c": Color(2.2, 1.5, 0.7), "h0": 1.0, "h1": 1.0, "px": 6.0})
	spawn("glow", p + Vector3(0, 6.0 * s, 0), {"life": 0.9 * s, "s0": 10.0 * s, "s1": 18.0 * s, "a0": 0.9, "a1": 0.0, "c": Color(1.6, 0.6, 0.2), "h0": 1.0, "h1": 0.8, "v": Vector3(0, 6 * s, 0), "px": 3.0})
	for k in int(10 * s):
		var a := randf() * TAU
		var out := Vector3(cos(a), 0, sin(a))
		spawn("puff", p + out * randf_range(0, 6.0 * s) + Vector3(0, 2.0 * s, 0), {"life": randf_range(6.0, 12.0) * (0.7 + 0.3 * s), "s0": 6.0 * s, "s1": 22.0 * s,
			"a0": 0.9, "a1": 0.0, "c": dc.darkened(randf_range(0.0, 0.5)), "h0": 0.9, "h1": 0.35,
			"v": out * randf_range(4.0, 14.0) * s + Vector3(0, randf_range(4.0, 14.0) * s, 0), "drag": 0.35, "rise": 0.4, "px": 1.5})
	for k in int(8 * s):
		var a2 := randf() * TAU
		spawn("puff", p + Vector3(cos(a2), 0.05, sin(a2)) * 4.0 * s, {"life": randf_range(3.0, 5.0), "s0": 4.0 * s, "s1": 14.0 * s, "a0": 0.7, "a1": 0.0,
			"c": dc, "h0": 0.6, "h1": 0.3, "v": Vector3(cos(a2), 0, sin(a2)) * 40.0 * s, "drag": 1.6, "px": 1.0})
	for k in int(10 * s):
		spawn("glow", p, {"life": randf_range(0.6, 1.6), "s0": 0.6 * s, "s1": 0.3, "a0": 1.0, "a1": 0.0, "c": Color(2.0, 1.2, 0.4), "h0": 1.0, "h1": 0.6,
			"v": Vector3(randf_range(-30, 30), randf_range(20, 50), randf_range(-30, 30)) * s, "rise": -9.8, "px": 1.5})
	if not water:
		scorch(p, 9.0 * s)


func muzzle(p: Vector3, size: float) -> void:
	spawn("glow", p, {"life": 0.06, "s0": size, "s1": size * 0.8, "a0": 1.0, "a1": 0.5, "c": Color(2.0, 1.6, 0.8), "h0": 1.0, "h1": 1.0, "px": 2.0})


## A short streak travelling from a to b (ground fire).
func tracer(a: Vector3, b: Vector3, col: Color, speed := 900.0) -> void:
	var dist := a.distance_to(b)
	if dist < 1.0 or parts.size() >= MAX_PARTS:
		return
	var n := take("beam")
	n.set_instance_shader_parameter("fx_color", col)
	n.set_instance_shader_parameter("fx_alpha", 1.0)
	n.set_instance_shader_parameter("fx_heat", 1.0)
	var p := {"n": n, "k": "beam", "t": 0.0, "life": dist / speed, "a": a, "b": b, "len": minf(dist * 0.3, 18.0)}
	tracers.append(p)
	_tracer_pos(p)


var tracers: Array = []


func _tracer_pos(p: Dictionary) -> void:
	var f: float = p.t / p.life
	var dist: float = p.a.distance_to(p.b)
	var head: Vector3 = p.a.lerp(p.b, f)
	# the tail never reaches back past the muzzle
	var tail: Vector3 = p.a.lerp(p.b, maxf(0.0, f - float(p.len) / maxf(dist, 0.001)))
	set_beam(p.n, tail, head, 0.12, 1.6)


func _update_tracers(dt: float) -> void:
	var i := tracers.size() - 1
	while i >= 0:
		var p: Dictionary = tracers[i]
		p.t += dt
		if p.t >= p.life:
			give("beam", p.n)
			tracers[i] = tracers[tracers.size() - 1]
			tracers.pop_back()
		else:
			_tracer_pos(p)
		i -= 1


func vehicle_destroyed(p: Vector3, big: bool) -> void:
	if recorder and _depth == 0:
		recorder.vehicle_destroyed(p, big)
	_depth += 1
	_vehicle_destroyed(p, big)
	_depth -= 1


func _vehicle_destroyed(p: Vector3, big: bool) -> void:
	impact(p, "large" if big else "medium", false)
	fire(p + Vector3(0, 1.0, 0), 3.5 if big else 2.2, randf_range(50.0, 110.0))


func collapse(c: Vector3, size: float, h: float) -> void:
	var dc := _dust()
	for k in 14:
		var a := randf() * TAU
		spawn("puff", c + Vector3(cos(a), 0, sin(a)) * randf_range(0, size * 0.6) + Vector3(0, randf_range(0, h * 0.5), 0),
			{"life": randf_range(8.0, 16.0), "s0": size * 0.5, "s1": size * 1.6, "a0": 0.85, "a1": 0.0, "c": dc.darkened(randf_range(0.0, 0.3)),
			"h0": 0.5, "h1": 0.3, "v": Vector3(cos(a), 0.3, sin(a)) * randf_range(2.0, 8.0), "drag": 0.3, "px": 1.0})
	if size > 10.0:
		fire(c + Vector3(0, 1, 0), size * 0.15, 40.0)


func smoke_trail(p: Vector3, white: bool, size := 1.5, life := 6.0) -> void:
	var g := 0.85 if white else 0.3
	spawn("puff", p, {"life": life, "s0": size, "s1": size * 4.0, "a0": 0.6, "a1": 0.0, "c": Color(g, g, g), "h0": 0.7, "h1": 0.3, "drag": 0.2, "px": 1.2})
