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


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	# Godot front faces are clockwise; fix the order so the face looks along n.
	if (c - a).cross(b - a).dot(n) < 0.0:
		var t := b
		b = c
		c = t
	for v in [a, b, c]:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(v)


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
	var head := _c(0.36, 0.35, 0.27, 0.4)
	var skin: Color = SKIN[rng.randi() % SKIN.size()]
	skin.a = 0.62
	var gear := _c(0.22, 0.21, 0.17, 0.45)
	var weapon := 1
	var zombie := false
	var vest := true
	if id.begins_with("inf_friendly"):
		skin = SKIN[0]; skin.a = 0.62
	elif id.begins_with("inf_sf"):
		top = _c(0.3, 0.3, 0.24); pants = _c(0.3, 0.29, 0.23); head = _c(0.25, 0.25, 0.2, 0.4)
	elif id.begins_with("inf_enemy"):
		var cols := [Color(0.55, 0.5, 0.4), Color(0.24, 0.23, 0.22), Color(0.4, 0.38, 0.3), Color(0.62, 0.6, 0.56), Color(0.35, 0.3, 0.25)]
		var c: Color = cols[rng.randi() % cols.size()]
		top = _c(c.r, c.g, c.b)
		var c2: Color = cols[rng.randi() % cols.size()]
		pants = _c(c2.r * 0.9, c2.g * 0.9, c2.b * 0.9)
		var hc: Color = cols[rng.randi() % cols.size()]
		head = _c(hc.r, hc.g, hc.b, 0.5)
		vest = rng.randf() < 0.5
		skin = SKIN[1 + rng.randi() % 2]; skin.a = 0.62
		if id.ends_with("rpg"):
			weapon = 2
	elif id.begins_with("inf_civ") or id.begins_with("inf_surv"):
		var shirts := [Color(0.2, 0.3, 0.55), Color(0.85, 0.85, 0.8), Color(0.6, 0.2, 0.18), Color(0.25, 0.45, 0.3), Color(0.7, 0.6, 0.3), Color(0.5, 0.45, 0.5)]
		var s: Color = shirts[rng.randi() % shirts.size()]
		top = _c(s.r, s.g, s.b)
		pants = _c(0.2, 0.22, 0.3) if rng.randf() < 0.6 else _c(0.45, 0.4, 0.32)
		head = _c(0.2, 0.15, 0.1, 0.55)
		vest = id.begins_with("inf_surv")
		weapon = 1 if id.begins_with("inf_surv") else 0
	elif id.begins_with("inf_zombie"):
		zombie = true
		var rags := [Color(0.35, 0.33, 0.3), Color(0.3, 0.35, 0.4), Color(0.45, 0.35, 0.3)]
		var r: Color = rags[rng.randi() % rags.size()]
		top = _c(r.r, r.g, r.b, 0.45)
		pants = _c(r.r * 0.7, r.g * 0.7, r.b * 0.7, 0.45)
		skin = _c(0.5, 0.55, 0.45, 0.48)
		head = _c(0.25, 0.22, 0.2, 0.45)
		weapon = 0
		vest = false
	elif id.begins_with("inf_vip"):
		top = _c(0.12, 0.12, 0.14); pants = _c(0.12, 0.12, 0.14); head = _c(0.15, 0.12, 0.1, 0.55)
		weapon = 0
		vest = false
	elif id.begins_with("inf_pilot"):
		top = _c(0.42, 0.46, 0.36); pants = _c(0.42, 0.46, 0.36); head = _c(0.42, 0.46, 0.36, 0.5)
		weapon = 0
	var st := _st()
	# legs
	boxc(st, Vector3(-0.1, 0.42, 0), Vector3(0.15, 0.84, 0.17), pants)
	boxc(st, Vector3(0.1, 0.42, 0), Vector3(0.15, 0.84, 0.17), pants)
	# torso
	boxc(st, Vector3(0, 1.12, 0), Vector3(0.42, 0.58, 0.25), top)
	if vest:
		boxc(st, Vector3(0, 1.12, 0), Vector3(0.44, 0.42, 0.29), gear)
	# arms
	if zombie:
		boxc(st, Vector3(-0.26, 1.3, -0.22), Vector3(0.11, 0.11, 0.55), top)
		boxc(st, Vector3(0.26, 1.3, -0.22), Vector3(0.11, 0.11, 0.55), top)
	elif weapon > 0:
		boxc(st, Vector3(-0.2, 1.18, -0.2), Vector3(0.11, 0.11, 0.42), top, Vector3(0.3, 0.3, 0))
		boxc(st, Vector3(0.24, 1.12, -0.1), Vector3(0.11, 0.11, 0.42), top, Vector3(0.4, -0.2, 0))
	else:
		boxc(st, Vector3(-0.27, 1.12, 0), Vector3(0.11, 0.55, 0.12), top)
		boxc(st, Vector3(0.27, 1.12, 0), Vector3(0.11, 0.55, 0.12), top)
	# head
	boxc(st, Vector3(0, 1.55, 0), Vector3(0.2, 0.24, 0.22), skin)
	boxc(st, Vector3(0, 1.68, 0.01), Vector3(0.24, 0.09, 0.26), head)
	# weapon
	if weapon == 1:
		boxc(st, Vector3(0.05, 1.2, -0.42), Vector3(0.06, 0.08, 0.75), _c(0.1, 0.1, 0.1, 0.25))
	elif weapon == 2:
		boxc(st, Vector3(0.18, 1.5, -0.05), Vector3(0.11, 0.11, 1.1), _c(0.28, 0.32, 0.22, 0.25))
	return st.commit()


# --- Vehicles -----------------------------------------------------------

static func _wheels(st: SurfaceTool, xs: float, zs: Array, r: float, w: float) -> void:
	var tire := _c(0.08, 0.08, 0.08, 0.6)
	# Basis turning the cylinder's +Y axis onto +X.
	var b := Basis(Vector3(0, 0, 1), -PI * 0.5)
	for z in zs:
		for sx in [-1.0, 1.0]:
			cyl(st, Transform3D(b, Vector3(sx * xs - w * 0.5, r, z)), r, r, w, 8, tire)


static func _vehicle(id: String) -> Mesh:
	var parts := id.split("_")
	var kind := parts[0]
	var paint := _c(0.85, 0.85, 0.82)
	if parts.size() > 1:
		match parts[1]:
			"white": paint = _c(0.86, 0.86, 0.84)
			"tan": paint = _c(0.68, 0.6, 0.45)
			"dark": paint = _c(0.18, 0.19, 0.2)
			"red": paint = _c(0.55, 0.14, 0.12)
			"blue": paint = _c(0.18, 0.26, 0.5)
			"green": paint = _c(0.32, 0.36, 0.25)
			"rust": paint = _c(0.42, 0.28, 0.18)
			"black": paint = _c(0.07, 0.07, 0.08)
			"silver": paint = _c(0.6, 0.62, 0.64)
			"sand": paint = _c(0.62, 0.56, 0.42)
	var glass := _c(0.08, 0.1, 0.12, 0.4)
	var dark := _c(0.12, 0.12, 0.12, 0.5)
	var engine := Color(paint.r, paint.g, paint.b, 0.95)
	var st := _st()
	match kind:
		"technical", "pickup":
			boxc(st, Vector3(0, 0.75, -1.6), Vector3(1.85, 0.55, 1.4), engine)
			boxc(st, Vector3(0, 1.15, -0.4), Vector3(1.8, 1.0, 1.3), paint)
			boxc(st, Vector3(0, 1.3, -1.06), Vector3(1.7, 0.6, 0.06), glass)
			boxc(st, Vector3(0, 0.75, 1.15), Vector3(1.85, 0.5, 2.4), paint)
			boxc(st, Vector3(0, 0.45, 0), Vector3(1.6, 0.3, 4.8), dark)
			_wheels(st, 0.95, [-1.55, 1.5], 0.38, 0.28)
			if kind == "technical":
				boxc(st, Vector3(0, 1.45, 1.1), Vector3(0.3, 0.9, 0.3), dark)
				boxc(st, Vector3(0, 1.95, 0.5), Vector3(0.18, 0.18, 1.5), dark)
				boxc(st, Vector3(0, 1.85, 1.2), Vector3(0.6, 0.5, 0.08), dark)
		"car":
			boxc(st, Vector3(0, 0.6, 0), Vector3(1.75, 0.55, 4.3), paint)
			boxc(st, Vector3(0, 0.6, -1.5), Vector3(1.7, 0.5, 1.0), engine)
			boxc(st, Vector3(0, 1.08, 0.2), Vector3(1.6, 0.48, 2.1), glass)
			boxc(st, Vector3(0, 1.33, 0.25), Vector3(1.55, 0.06, 1.8), paint)
			_wheels(st, 0.9, [-1.35, 1.35], 0.32, 0.22)
		"suv":
			boxc(st, Vector3(0, 0.85, 0), Vector3(1.9, 0.8, 4.7), paint)
			boxc(st, Vector3(0, 0.85, -1.7), Vector3(1.88, 0.75, 1.1), engine)
			boxc(st, Vector3(0, 1.55, 0.35), Vector3(1.8, 0.65, 3.1), glass)
			boxc(st, Vector3(0, 1.9, 0.35), Vector3(1.82, 0.08, 3.1), paint)
			_wheels(st, 0.98, [-1.5, 1.5], 0.4, 0.26)
		"truck":
			boxc(st, Vector3(0, 1.45, -2.6), Vector3(2.3, 1.6, 1.9), paint)
			boxc(st, Vector3(0, 1.7, -3.56), Vector3(2.1, 0.7, 0.06), glass)
			boxc(st, Vector3(0, 0.95, -3.0), Vector3(2.2, 0.7, 1.2), engine)
			boxc(st, Vector3(0, 0.7, 0.4), Vector3(2.0, 0.4, 6.6), dark)
			boxc(st, Vector3(0, 1.8, 1.1), Vector3(2.4, 1.9, 4.6), _c(paint.r * 0.75, paint.g * 0.78, paint.b * 0.7))
			_wheels(st, 1.15, [-2.6, 0.6, 2.4], 0.5, 0.35)
		"humvee":
			boxc(st, Vector3(0, 0.95, 0), Vector3(2.2, 0.9, 4.8), paint)
			boxc(st, Vector3(0, 0.95, -1.8), Vector3(2.15, 0.8, 1.2), engine)
			boxc(st, Vector3(0, 1.65, 0.3), Vector3(2.0, 0.55, 2.4), _c(paint.r * 0.9, paint.g * 0.9, paint.b * 0.9))
			boxc(st, Vector3(0, 1.62, -0.92), Vector3(1.8, 0.4, 0.06), glass)
			cyl(st, Transform3D(Basis(), Vector3(0, 1.92, 0.4)), 0.5, 0.5, 0.35, 8, dark)
			boxc(st, Vector3(0, 2.2, -0.2), Vector3(0.14, 0.14, 1.2), dark)
			_wheels(st, 1.12, [-1.6, 1.6], 0.46, 0.35)
		"mrap":
			boxc(st, Vector3(0, 1.5, 0.3), Vector3(2.5, 1.9, 5.2), paint)
			boxc(st, Vector3(0, 1.1, -2.6), Vector3(2.3, 1.1, 1.4), engine)
			boxc(st, Vector3(0, 2.05, -1.95), Vector3(2.1, 0.55, 0.06), glass)
			boxc(st, Vector3(0, 0.7, 0), Vector3(2.0, 0.5, 6.0), dark)
			cyl(st, Transform3D(Basis(), Vector3(0, 2.45, 0.6)), 0.55, 0.55, 0.4, 8, dark)
			boxc(st, Vector3(0, 2.75, 0.0), Vector3(0.14, 0.14, 1.3), dark)
			_wheels(st, 1.25, [-2.2, 0.6, 2.2], 0.55, 0.4)
		"btr":
			boxc(st, Vector3(0, 1.35, 0.2), Vector3(2.8, 1.3, 6.4), paint)
			boxc(st, Vector3(0, 1.1, -3.3), Vector3(2.6, 0.9, 1.2), paint, Vector3(-0.45, 0, 0))
			boxc(st, Vector3(0, 1.35, 2.4), Vector3(2.6, 1.0, 1.6), engine)
			cyl(st, Transform3D(Basis(), Vector3(0, 2.0, -0.8)), 0.65, 0.55, 0.55, 8, paint)
			boxc(st, Vector3(0, 2.3, -2.0), Vector3(0.14, 0.14, 2.2), dark)
			_wheels(st, 1.4, [-2.4, -0.9, 0.9, 2.4], 0.55, 0.35)
		"tank":
			boxc(st, Vector3(0, 0.95, 0), Vector3(3.5, 1.0, 6.9), paint)
			boxc(st, Vector3(0, 1.1, 2.5), Vector3(3.3, 0.8, 1.8), engine)
			boxc(st, Vector3(-1.6, 0.55, 0), Vector3(0.65, 1.0, 6.6), dark)
			boxc(st, Vector3(1.6, 0.55, 0), Vector3(0.65, 1.0, 6.6), dark)
			cyl(st, Transform3D(Basis(), Vector3(0, 1.45, 0.2)), 1.55, 1.25, 0.75, 10, paint)
			boxc(st, Vector3(0, 1.85, -3.0), Vector3(0.2, 0.2, 5.2), dark)
		"zu23":
			boxc(st, Vector3(0, 0.45, 0), Vector3(1.8, 0.35, 2.4), paint)
			boxc(st, Vector3(0, 0.95, 0.2), Vector3(1.2, 0.7, 1.0), paint)
			boxc(st, Vector3(-0.25, 1.7, -0.7), Vector3(0.1, 0.1, 2.2), dark, Vector3(0.75, 0, 0))
			boxc(st, Vector3(0.25, 1.7, -0.7), Vector3(0.1, 0.1, 2.2), dark, Vector3(0.75, 0, 0))
			_wheels(st, 0.9, [0.2], 0.35, 0.2)
		"sam":
			boxc(st, Vector3(0, 1.0, 0), Vector3(3.0, 1.2, 6.5), paint)
			boxc(st, Vector3(0, 0.45, 0), Vector3(3.0, 0.9, 6.5), dark)
			cyl(st, Transform3D(Basis(), Vector3(0, 1.6, 0.5)), 1.1, 1.0, 0.4, 10, paint)
			for x in [-0.9, 0.0, 0.9]:
				var b := Basis.from_euler(Vector3(0.55, 0, 0))
				box(st, Transform3D(b, Vector3(x, 2.7, 0.2)), Vector3(0.42, 0.42, 4.6), _c(0.75, 0.75, 0.7))
		"radar":
			boxc(st, Vector3(0, 1.3, 0), Vector3(2.5, 1.6, 6.0), paint)
			_wheels(st, 1.2, [-2.0, 0.5, 2.0], 0.5, 0.35)
			boxc(st, Vector3(0, 3.2, 0.5), Vector3(0.3, 2.2, 0.3), dark)
			boxc(st, Vector3(0, 4.4, 0.5), Vector3(3.2, 1.4, 0.2), _c(0.6, 0.62, 0.6), Vector3(0.3, 0, 0))
		"wreck":
			boxc(st, Vector3(0, 1.0, 0), Vector3(2.4, 1.6, 9.0), _c(0.15, 0.15, 0.14, 0.9))
			boxc(st, Vector3(0, 2.4, 4.5), Vector3(0.6, 2.2, 1.8), _c(0.15, 0.15, 0.14, 0.9), Vector3(0, 0, 0.6))
			boxc(st, Vector3(1.0, 0.4, -4.0), Vector3(6.0, 0.15, 0.4), _c(0.1, 0.1, 0.1, 0.8), Vector3(0, 0.7, 0))
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
