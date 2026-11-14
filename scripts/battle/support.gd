extends Node3D
## Call-ins beyond simple bombs: the A-10 gun run, the show of force, the
## ground QRF platoon and helicopter squad insertions.

const Meshes := preload("res://scripts/world/meshes.gd")
const Mats := preload("res://scripts/world/mats.gd")
const Maps := preload("res://scripts/data/maps.gd")

var battle
var runs: Array = []
var markers: Array = []      # {pos, text, kind, unit (optional, removed when it arrives)}
var qrf_n := 0
var aid: Array = []          # wounded at an aid station: {kind, group, base, ready_t}
var wia_t := 0.0


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
	_update_medevac(dt)
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
		# a QRF drives hard: half as fast again as ordinary traffic
		prev = battle.units.spawn(kinds[i], 0, base + dir * (i * 26.0), grp, {"order": "convoy", "path": path.duplicate(), "leader": prev,
			"cargo": cargo, "on_arrive": "dismount", "speed_mul": 1.5, "data": {"goal": target, "qrf": true}})
	var total := 0.0
	for k in path.size() - 1:
		total += path[k].distance_to(path[k + 1])
	var eta := int(ceil(total / 18.0 / 60.0))
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
# --- Medevac ---------------------------------------------------------------

## Downed friendlies (wounded, not yet dead) within r of p.
func wounded_near(p: Vector3, r: float) -> Array:
	var out: Array = []
	for u in battle.units.list:
		if u.downed and not u.boarded and Vector2(u.pos.x - p.x, u.pos.z - p.z).length() < r:
			out.append(u)
	return out


## Where medevacs fly from and bring the wounded to: the outpost nearest p
## (a big one if there is one, they have a clear pad), else a field hospital
## off the map.
func _medevac_base(p: Vector3) -> Dictionary:
	var w = battle.world
	var best := ""
	var bd := 1.0e9
	for sname in w.map.get("outposts", {}):
		var c: Vector3 = w.site(sname)
		var d := c.distance_to(p) * (1.0 if float(w.map.outposts[sname]) >= 45.0 else 1.6)
		if d < bd:
			bd = d
			best = sname
	if best == "":
		var a := atan2(p.x, p.z) + PI
		var far := Vector3(sin(a), 0, cos(a)) * 6500.0
		far.y = w.height(far.x, far.z)
		return {"name": "", "pos": far, "label": "the field hospital"}
	return {"name": best, "pos": w.site(best), "label": Maps.site_name(w.map, best)}


func _landing_spot(target: Vector3) -> Vector3:
	var w = battle.world
	for k in 30:
		var c := Vector2(target.x, target.z) + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * (6.0 + k * 6.0)
		if w.ground_ok(c) and not w.in_building(c, 14.0) and w.normal_at(c.x, c.y).y > 0.9:
			return w.to3(c)
	return target


## Sends a medevac for the wounded near p. It takes off from the nearest
## outpost with anyone healed there, drops them back with their unit on the
## way, picks up the wounded and flies them back to be patched up.
func call_medevac(p: Vector3) -> void:
	var w = battle.world
	var base := _medevac_base(p)
	var pad: Vector3 = base.pos
	var units = battle.units
	# healed men waiting at this base for a ride back
	var riders: Array = []
	var aboard: Array = []
	for u in units.list:
		if u.alive and u.data.get("wait_lift", "") == base.name and u.data.has("orig_group"):
			riders.append({"kind": u.kind, "group": u.data.orig_group})
			aboard.append(u)
	for u in aboard:
		units.remove_unit(u)
	var legs: Array = []
	if not riders.is_empty():
		var gc = _group_centre(String(riders[0].group))
		if gc != null and gc.distance_to(p) > 350.0:
			legs.append({"op": "drop", "lz": _landing_spot(gc), "riders": riders})
			riders = []
	var cas := _landing_spot(p)
	legs.append({"op": "collect", "lz": cas, "riders": riders, "near": p})
	legs.append({"op": "home", "lz": _landing_spot(pad) if base.name != "" else pad, "base": base.name, "label": base.label})
	var going_back := 0
	for lg in legs:
		going_back += lg.riders.size() if lg.has("riders") else 0
	# the bird parked at this outpost goes again; otherwise a new one comes up
	var h = null
	for u in units.list:
		if u.alive and u.data.get("medevac", false) and u.data.get("state", "") == "parked" and u.pos.distance_to(pad) < 120.0:
			h = u
			break
	if h != null:
		h.data.legs = legs
	else:
		var start: Vector3 = pad if base.name != "" else pad + Vector3(0, 150, 0)
		h = units.spawn("heli", 0, start, "medevac", {"airframe": "uh60", "heading": randf() * TAU,
			"data": {"state": "wait", "wait_t": 0.0, "go": true, "legs": legs, "patients": [], "brave": true, "medevac": true}})
	var n := wounded_near(p, 220.0).size()
	var extra := ""
	if going_back > 0:
		extra = ", taking %d of your guys back out" % going_back
	battle.radio("DUSTOFF 3-1", "Dustoff 3-1 lifting from %s for %d wounded%s." % [base.label, n, extra])
	markers.append({"pos": cas, "text": "MEDEVAC LZ", "kind": "friend", "heli": h})


func _group_centre(group: String):
	var sum := Vector3.ZERO
	var n := 0
	for u in battle.units.list:
		if u.alive and u.group == group and u.team == 0:
			sum += u.pos
			n += 1
	return sum / n if n > 0 else null


func _update_medevac(dt: float) -> void:
	# the wounded heal at the aid station, then wait for a ride back out
	var i := aid.size() - 1
	while i >= 0:
		var a: Dictionary = aid[i]
		if battle.time >= float(a.ready_t):
			aid.remove_at(i)
			if a.base != "":
				var c: Vector3 = battle.world.site(a.base)
				var spot: Vector3 = battle.world.free_spot(Vector2(c.x, c.z) + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 10.0, 10.0)
				battle.units.spawn(a.kind, 0, spot, "healed", {"order": "hold", "data": {"wait_lift": a.base, "orig_group": a.group}})
		i -= 1
	# casualty markers: one per cluster, with the time the worst one has left
	wia_t -= dt
	if wia_t > 0.0:
		return
	wia_t = 1.0
	markers = markers.filter(func(m): return not m.get("wia", false))
	var clusters: Array = []
	for u in battle.units.list:
		if not u.downed or u.boarded:
			continue
		var placed := false
		for cl in clusters:
			if cl.pos.distance_to(u.pos) < 80.0:
				cl.n += 1
				cl.left = minf(cl.left, 300.0 - (battle.units.time - u.down_t))
				placed = true
				break
		if not placed:
			clusters.append({"pos": u.pos, "n": 1, "left": 300.0 - (battle.units.time - u.down_t)})
	for cl in clusters:
		var left := maxi(0, int(cl.left))
		markers.append({"pos": cl.pos, "text": "WIA %d  %d:%02d" % [cl.n, left / 60, left % 60], "kind": "friend", "wia": true})


## A medevac has landed somewhere on its route (called from the helicopter).
func medevac_leg(h, leg: Dictionary) -> void:
	var units = battle.units
	for r in leg.get("riders", []):
		var p: Vector3 = battle.world.free_spot(Vector2(h.pos.x, h.pos.z) + Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * 12.0, 8.0)
		var gc = _group_centre(String(r.group))
		units.spawn(r.kind, 0, p, String(r.group), {"order": "assault" if gc != null else "hold", "goal": gc if gc != null else p})
	if not leg.get("riders", []).is_empty():
		battle.radio("DUSTOFF 3-1", "%d of your guys are back on the ground." % leg.riders.size())
	match leg.op:
		"collect":
			var got := 0
			for u in wounded_near(leg.near, 260.0):
				u.boarded = true
				u.downed = false
				u.node.visible = false
				h.data.patients.append({"kind": u.kind, "group": u.group})
				got += 1
			battle.radio("DUSTOFF 3-1", "%d wounded aboard, lifting." % got if got > 0 else "Nobody here to lift, Dustoff heading home.")
		"home":
			for pt in h.data.patients:
				aid.append({"kind": pt.kind, "group": pt.group, "base": leg.base, "ready_t": battle.time + 60.0})
			if not h.data.patients.is_empty():
				battle.radio("DUSTOFF 3-1", "Wounded delivered to %s. They'll be back on their feet in a minute or so." % leg.label)
			h.data.patients = []


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
