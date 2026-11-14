extends Node3D
## Call-ins beyond simple bombs: the A-10 gun run, the show of force, the
## ground QRF platoon and helicopter squad insertions.

const Meshes := preload("res://scripts/world/meshes.gd")
const Mats := preload("res://scripts/world/mats.gd")

var battle
var runs: Array = []
var markers: Array = []      # {pos, text, kind, unit (optional, removed when it arrives)}
var qrf_n := 0


static func line_dir(ang: float) -> Vector3:
	# ang is a compass heading: 0 flies north (-z), PI/2 east
	return Vector3(sin(ang), 0.0, -cos(ang))


func _jet(kind: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.get_mesh(kind)
	mi.material_override = Meshes.get_material(kind, Mats.solid())
	mi.set_instance_shader_parameter("heat", 0.75)
	add_child(mi)
	return mi


# --- A-10 gun run ---------------------------------------------------------------

func gun_run(center: Vector3, ang: float, def: Dictionary) -> void:
	var dir := line_dir(ang)
	var L: float = def.len
	runs.append({"kind": "gunrun", "dir": dir, "start": center - dir * L * 0.5, "len": L, "t": 0.0,
		"fire_t": float(def.tot) - 0.9, "def": def, "node": _jet("jet_a10"), "speed": 190.0, "alt": 140.0,
		"acc": 0.0, "fired": false, "dust": 0.0})


# --- Show of force --------------------------------------------------------------

func show_of_force(center: Vector3, ang: float, def: Dictionary) -> void:
	var dir := line_dir(ang)
	runs.append({"kind": "sof", "dir": dir, "start": center - dir * float(def.len) * 0.5, "center": center, "len": def.len,
		"t": 0.0, "pass_t": float(def.tot), "def": def, "node": _jet("jet_f18"), "speed": 320.0, "alt": 35.0,
		"dust": 0.0, "boomed": false, "scared": {}})


func _process(dt: float) -> void:
	var i := runs.size() - 1
	while i >= 0:
		var r: Dictionary = runs[i]
		r.t += dt
		var done := false
		if r.kind == "gunrun":
			done = _update_gunrun(r, dt)
		else:
			done = _update_sof(r, dt)
		if done:
			r.node.queue_free()
			runs.remove_at(i)
		i -= 1
	_update_markers()


## Jet position s metres along the run line (0 = line start), with height.
func _jet_pos(r: Dictionary, s: float, extra_alt: float) -> Vector3:
	var p: Vector3 = r.start + r.dir * s
	var w = battle.world
	p.y = maxf(w.height(p.x, p.z), w.height(p.x + r.dir.x * 200.0, p.z + r.dir.z * 200.0)) + float(r.alt) + extra_alt
	return p


func _place_jet(r: Dictionary, p: Vector3, climb: float) -> void:
	var fwd: Vector3 = (r.dir + Vector3.UP * climb).normalized()
	r.node.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), p)
	var s := maxf(1.0, battle.effects.mpp(p) * 2.0 / 12.0)
	r.node.scale = Vector3.ONE * s


func _update_gunrun(r: Dictionary, dt: float) -> bool:
	# the jet opens fire 900 m short of the line so the rounds walk it
	var s: float = (r.t - float(r.fire_t)) * float(r.speed) - 900.0
	var after: float = s - float(r.len)
	var climb := clampf(after / 1500.0, 0.0, 0.5)
	var dive := clampf(-s / 3000.0, 0.0, 1.0) * 300.0
	var p := _jet_pos(r, s, dive + maxf(after, 0.0) * 0.4)
	_place_jet(r, p, climb - dive / 3000.0)
	r.node.visible = s > -3500.0
	var fire_len: float = float(r.len) / 150.0
	if r.t >= r.fire_t and r.t <= float(r.fire_t) + fire_len:
		if not r.fired:
			r.fired = true
			Sfx.play("gau8", -2.0, 1.0, p.distance_to(battle.gunship.global_position) / 1500.0)
		r.acc = float(r.acc) + dt * 65.0
		var right: Vector3 = r.dir.cross(Vector3.UP).normalized()
		while r.acc >= 1.0:
			r.acc -= 1.0
			var along: float = (r.t - float(r.fire_t)) / fire_len * float(r.len) + randf_range(-6.0, 6.0)
			var tgt: Vector3 = r.start + r.dir * along + right * randfn(0.0, 3.0)
			tgt.y = battle.world.height(tgt.x, tgt.z)
			var hit: Dictionary = battle.world.raycast(p, (tgt - p).normalized(), p.distance_to(tgt) + 50.0)
			var to: Vector3 = hit.get("pos", tgt)
			var d: Dictionary = r.def.duplicate()
			d["fx"] = "medium" if randf() < 0.35 else "small"
			battle.ordnance.add_shell(p, to, "s_a10", d, int(hit.get("bidx", -1)), bool(hit.get("water", false)))
	return s > float(r.len) + 3500.0


func _update_sof(r: Dictionary, dt: float) -> bool:
	var s: float = (r.t - float(r.pass_t)) * float(r.speed) + float(r.len) * 0.5
	var p := _jet_pos(r, s, maxf(-s - 500.0, 0.0) * 0.15 + maxf(s - float(r.len) - 300.0, 0.0) * 0.3)
	_place_jet(r, p, 0.0)
	r.node.visible = s > -3500.0
	if not r.boomed and r.t >= r.pass_t:
		r.boomed = true
		Sfx.play("sonic", 2.0, 1.0, p.distance_to(battle.gunship.global_position) / 1500.0)
		battle.radio("VIPER 2-1", "Viper's through, that got their attention.")
	if s > -200.0 and s < float(r.len) + 200.0:
		# a wall of dust kicked up behind the jet
		r.dust = float(r.dust) + dt * float(r.speed)
		while float(r.dust) >= 9.0:
			r.dust = float(r.dust) - 9.0
			var g: Vector3 = p - r.dir * randf_range(0.0, 9.0)
			g.y = battle.world.height(g.x, g.z) + 4.0
			var side: Vector3 = r.dir.cross(Vector3.UP).normalized() * randf_range(-30.0, 30.0)
			battle.effects.spawn("puff", g + side, {"life": randf_range(30.0, 55.0), "s0": 24.0, "s1": 90.0, "a0": 0.95, "a1": 0.0,
				"c": battle.world.dust_color.darkened(0.3), "h0": 0.4, "h1": 0.3, "v": side.normalized() * randf_range(8.0, 18.0) + Vector3(0, randf_range(2, 6), 0), "drag": 0.25, "px": 2.0})
		_scare_from(r, p)
	return s > float(r.len) + 4000.0


## Everyone the jet roars over runs from the path for 30-60 s; groups break
## up in different directions.
func _scare_from(r: Dictionary, p: Vector3) -> void:
	var right: Vector3 = r.dir.cross(Vector3.UP).normalized()
	for u in battle.units.query(p, 260.0):
		# our own troops know it's coming; everyone else scatters
		if not u.alive or u.team == 0 or r.scared.has(u.id):
			continue
		var rel: Vector3 = u.pos - p
		var off := rel.dot(right)
		if Vector2(rel.x, rel.z).length() > 260.0:
			continue
		r.scared[u.id] = true
		var away := right * (1.0 if off >= 0.0 else -1.0)
		away = away.rotated(Vector3.UP, randf_range(-1.3, 1.3))
		battle.units.panic(u, away, randf_range(30.0, 60.0) * (1.0 - absf(off) / 400.0))


# --- Ground QRF -------------------------------------------------------------------

func send_qrf(target: Vector3) -> bool:
	var w = battle.world
	if not w.map.get("sites", {}).has("qrf"):
		return false
	# the platoon forms up outside the base's gate (the +z wall) and drives
	# from there; inside the walls the trucks would never find the way out
	var size: float = float(w.map.get("outposts", {}).get("qrf", 60.0))
	var g2: Vector2 = w.gates.get("qrf", Vector2(0, 1))
	var gate: Vector3 = w.site("qrf") + Vector3(g2.x, 0, g2.y) * (size * 0.5 + 18.0)
	var path: Array = w.drive_path(gate, target)
	qrf_n += 1
	var grp := "qrf%d" % qrf_n
	var kinds := ["humvee", "mrap", "humvee", "mrap"]
	var prev = null
	var dir := Vector3(g2.x, 0, g2.y)
	var base := gate
	for i in kinds.size():
		var cargo: Array = ["soldier", "soldier", "soldier", "mg", "soldier", "soldier", "soldier"]
		prev = battle.units.spawn(kinds[i], 0, base + dir * (i * 26.0), grp, {"order": "convoy", "path": path.duplicate(), "leader": prev,
			"cargo": cargo, "on_arrive": "dismount", "data": {"goal": target}})
	var total := 0.0
	for k in path.size() - 1:
		total += path[k].distance_to(path[k + 1])
	var eta := int(ceil(total / 11.0 / 60.0))
	var base_name: String = w.map.get("site_names", {}).get("qrf", "THE QRF BASE")
	battle.radio("WARHORSE 2-6", "Warhorse 2-6, QRF platoon rolling from %s. Four trucks, thirty dismounts. ETA %d minute%s." % [base_name, eta, "" if eta == 1 else "s"])
	markers.append({"pos": target, "text": "QRF OBJECTIVE", "kind": "friend", "group": grp})
	return true


# --- Helicopter insertion ----------------------------------------------------------

func insert_squad(target: Vector3) -> void:
	var w = battle.world
	var lz := target
	for k in 30:
		var c := Vector2(target.x, target.z) + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * (8.0 + k * 6.0)
		if w.ground_ok(c) and not w.in_building(c, 14.0) and w.normal_at(c.x, c.y).y > 0.9:
			lz = w.to3(c)
			break
	var a := randf() * TAU
	var start: Vector3 = lz + Vector3(sin(a), 0, -cos(a)) * 4200.0
	start.y = w.height(start.x, start.z) + 150.0
	var exit: Vector3 = lz + Vector3(sin(a + 2.2), 0, -cos(a + 2.2)) * 4500.0
	var squad := ["soldier", "soldier", "soldier", "mg", "soldier", "soldier", "soldier", "soldier", "mg", "soldier"]
	var h = battle.units.spawn("heli", 0, start, "airmob_heli", {"data": {"state": "inbound", "lz": lz, "exit": exit, "unload": squad}, "heading": a + PI})
	battle.radio("PALE HORSE 2-1", "Pale Horse 2-1, Black Hawk inbound with ten pax, about a minute out. Keep the LZ clear for us.")
	markers.append({"pos": lz, "text": "HELO LZ", "kind": "friend", "heli": h})


## When the mission's extraction helicopter launches, every group of troops
## the player called in (QRF dismounts, helicopter squads) gets a pickup of
## its own from the same distance, so it lands at the same time. Their trucks
## drive home. The mission doesn't wait for any of them.
func extract_called_troops() -> void:
	var w = battle.world
	var called: Array = []
	# trucks still carrying troops stop and put them down for the lift
	for u in battle.units.list.duplicate():
		if u.alive and u.team == 0 and u.veh and u.group.begins_with("qrf") and not u.cargo.is_empty():
			u.data["goal"] = u.pos
			battle.units.dismount(u)
	for u in battle.units.list:
		if not u.alive or u.team != 0:
			continue
		var called_group: bool = u.group.begins_with("qrf") or u.group == "airmob"
		if not called_group:
			continue
		if u.veh:
			if w.map.get("sites", {}).has("qrf"):
				u.order = "path"
				u.path = w.drive_path(u.pos, w.site("qrf"))
				u.path_i = 0
				u.on_arrive = ""
		else:
			called.append(u)
	# clusters of up to 12 within 150 m, one helicopter each
	var lifts := 0
	while not called.is_empty():
		var seed_u = called.pop_back()
		var team: Array = [seed_u]
		var i := called.size() - 1
		while i >= 0 and team.size() < 12:
			if called[i].pos.distance_to(seed_u.pos) < 150.0:
				team.append(called.pop_at(i))
			i -= 1
		var c := Vector3.ZERO
		for u in team:
			c += u.pos
		c /= team.size()
		var lz := c
		for k in 30:
			var c2 := Vector2(c.x, c.z) + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * (8.0 + k * 6.0)
			if w.ground_ok(c2) and not w.in_building(c2, 14.0) and w.normal_at(c2.x, c2.y).y > 0.9:
				lz = w.to3(c2)
				break
		var a := randf() * TAU
		var start: Vector3 = lz + Vector3(sin(a), 0, -cos(a)) * 3800.0
		start.y = w.height(start.x, start.z) + 140.0
		var exit: Vector3 = lz + Vector3(sin(a + 2.2), 0, -cos(a + 2.2)) * 4500.0
		var ids: Array = []
		for u in team:
			ids.append(u.id)
		var h = battle.units.spawn("heli", 0, start, "lift_heli", {"airframe": "ch47", "data": {"state": "inbound", "lz": lz, "exit": exit, "pickup": ids, "brave": true}, "heading": a + PI})
		markers.append({"pos": lz, "text": "PICKUP", "kind": "friend", "heli": h})
		lifts += 1
	if lifts > 0:
		battle.radio("PALE HORSE 2-1", "Pale Horse sending %d bird%s to lift out your QRF and squads." % [lifts, "" if lifts == 1 else "s"])


func _update_markers() -> void:
	var i := markers.size() - 1
	while i >= 0:
		var m: Dictionary = markers[i]
		var keep := true
		if m.has("heli"):
			var h = m.heli
			keep = h.alive and h.data.get("state", "") in ["inbound", "hold", "land"]
		elif m.has("group"):
			var any := false
			var arrived := true
			for u in battle.units.members(m.group):
				any = true
				if u.veh and u.order == "convoy":
					arrived = false
			keep = any and not arrived
		if not keep:
			markers.remove_at(i)
		i -= 1
