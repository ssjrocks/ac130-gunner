extends Node
## Test harness, started with: godot -- --autotest=SPEC [--secs=N] [--shots=DIR]
## SPEC: campaign:N | skirmish:MAP:TYPE:TIME | survival:MAP:TIME |
##       laststand:MAP:TIME:z|i | menu
## Runs the sortie with a bot gunner, prints progress, then quits.
## With --shots it saves screenshots at several zoom levels and sensor modes.

const Missions := preload("res://scripts/data/missions.gd")
const Data := preload("res://scripts/data/data.gd")

var t := 0.0
var next_print := 0.0
var shots_dir := ""
var plan: Array = []
var plan_i := 0
var spec := ""
var busy := false
var input_test := false
var gun_test := ""
var tracer_test := false
var gun_started := false
var flow_mode := false
var input_started := false
var frames := 0
var last_us := 0


func begin(s: String) -> void:
	spec = s
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.substr(8)
	var parts := s.split(":")
	var cfg := {}
	if parts[0] == "input":
		input_test = true
		parts = parts.slice(1)
	if parts[0] == "tracer":
		tracer_test = true
		parts = parts.slice(1)
	if parts[0] == "gun":
		gun_test = parts[1]
		parts = parts.slice(2)
	if parts[0] == "version":
		var out := OS.get_environment("AC130_VERSION_OUT")
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string("exe=%s v=%s" % [OS.get_executable_path(), Updater.current_version()])
		f.close()
		get_tree().quit()
		return
	if parts[0] == "callouts":
		flow_mode = true
		_callout_test(parts.slice(1))
		return
	if parts[0] == "resight":
		flow_mode = true
		_resight_test()
		return
	if parts[0] == "markers":
		flow_mode = true
		_markers_test(parts[1])
		return
	if parts[0] == "shake":
		flow_mode = true
		_shake_test()
		return
	if parts[0] == "los":
		flow_mode = true
		_los_test(parts[1])
		return
	if parts[0] == "update":
		flow_mode = true
		_update_test()
		return
	if parts[0] == "flow":
		flow_mode = true
		_flow(int(parts[1]))
		return
	match parts[0]:
		"campaign":
			cfg = Missions.campaign_cfg(int(parts[1]))
		"skirmish":
			cfg = Missions.skirmish_cfg(parts[1], parts[2], parts[3] if parts.size() > 3 else "day", 1)
			if parts.size() > 4:
				# skirmish:MAP:TYPE:TIME:N forces route N
				var mp: Dictionary = load("res://scripts/data/maps.gd").get_map(parts[1])
				cfg["route"] = mp.get(parts[2], [])[int(parts[4])]
		"survival":
			cfg = Missions.survival_cfg(parts[1], parts[2] if parts.size() > 2 else "day", 1)
		"laststand":
			cfg = Missions.laststand_cfg(parts[1], parts[2], 1, parts.size() > 3 and parts[3] == "z")
		"menu":
			_menu_shots()
			return
	Game.settings.loadout = "all"
	cfg["mode"] = "skirmish" if cfg.get("mode", "") == "campaign" else cfg.get("mode", "skirmish")
	Game.start_mission(cfg)
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir)
		plan = [
			{"at": 4.0, "mag": 1.0, "mode": 0, "name": "01_1x_tv"},
			{"at": 6.0, "mag": 6.0, "mode": 0, "name": "02_6x_tv"},
			{"at": 8.0, "mag": 25.0, "mode": 0, "name": "03_25x_tv"},
			{"at": 10.0, "mag": 80.0, "mode": 0, "name": "04_80x_tv"},
			{"at": 11.0, "mag": 150.0, "mode": 0, "name": "04b_150x_tv"},
			{"at": 12.0, "mag": 25.0, "mode": 1, "name": "05_25x_nv"},
			{"at": 14.0, "mag": 25.0, "mode": 2, "name": "06_25x_whot"},
			{"at": 16.0, "mag": 25.0, "mode": 3, "name": "07_25x_bhot"},
			{"at": 17.0, "mag": 25.0, "mode": 0, "name": "", "fire": "w_105"},
			{"at": 25.5, "mag": 25.0, "mode": 0, "name": "08_105_impact"},
			{"at": 30.0, "mag": 1.0, "mode": 0, "name": "09_1x_again"},
		]


func _battle():
	var c = Game.main.current
	if c != null and c.has_method("set_view_mode") and c.built:
		return c
	return null


func _process(dt: float) -> void:
	var b = _battle()
	if b == null:
		return
	t += dt
	if flow_mode:
		return
	frames += 1
	if t >= next_print:
		next_print += 10.0
		var now := Time.get_ticks_usec()
		var ms := (now - last_us) / 1000.0 / maxf(frames, 1)
		last_us = now
		frames = 0
		var u = b.units
		print("[autotest] t=%.0f state=%s friendly=%d enemy=%d near=%d civ=%d parts=%d shells=%d score=%d hp=%.0f frame=%.1fms" % [
			t, b.mission.state, u.count_team(0), u.count_team(1), u.enemies_near(b.mission.focus, 450.0), u.count_team(2), b.effects.parts.size(),
			b.ordnance.shells.size(), b.stats.score + b.mission.score_bonus, b.gunship.hp, ms])
		if b.mission.type == "escort":
			for cu in b.units.members("convoy") + b.units.members("vip"):
				print("   %s %s path %d/%d halted=%s moving=%s order=%s pos=%s detour=%s" % [cu.group, cu.kind, cu.path_i, cu.path.size(), cu.halted, cu.moving, cu.order, str(cu.pos.round()), str(cu.data.get("detour_t", 0.0))])
	if tracer_test:
		if not gun_started and t > 2.0:
			gun_started = true
			_tracer_test(b)
		return
	if gun_test != "":
		if not gun_started and t > 2.0:
			gun_started = true
			_gun_test(b)
		return
	if input_test:
		if not input_started and t > 2.0:
			input_started = true
			_input_test(b)
		return
	if shots_dir != "":
		_shots(b)
	elif t > Game.autotest_secs and not b.ended:
		print("[autotest] time limit reached")
		b.mission.lose("AUTOTEST TIME LIMIT")


func _shots(b) -> void:
	var g = b.gunship
	g.bot = false
	if busy or plan_i >= plan.size():
		if plan_i >= plan.size() and not busy:
			print("[autotest] shots done")
			get_tree().quit()
		return
	var p: Dictionary = plan[plan_i]
	# look at the friendly position (the mission focus) to start with
	if t < 3.0:
		var best = b.units.nearest(b.mission.focus, 200.0, 0)
		if best != null:
			g.aim_point = best.pos
			g.aim_valid = true
			g.track_unit = best
	g.mag_max = 150.0
	g.mag_goal = p.mag
	g.mag = p.mag
	if t >= p.at - 1.0 and Game.view_mode != int(p.mode):
		b.set_view_mode(int(p.mode))
	if t < p.at:
		return
	plan_i += 1
	if p.has("fire"):
		for i in g.weapons.size():
			if g.weapons[i].id == p.fire:
				g.wsel = i
				g._shoot(g.weapons[i])
		return
	busy = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path: String = shots_dir.path_join(p.name + ".png")
	img.save_png(path)
	print("[autotest] saved ", path, " hud size=", b.hud.size, " vis=", b.hud.is_visible_in_tree(), " vp=", get_viewport().get_visible_rect().size)
	busy = false


func _menu_shots() -> void:
	if shots_dir == "":
		Game.main.show_menu("title")
		return
	DirAccess.make_dir_recursive_absolute(shots_dir)
	for sname in ["title", "campaign", "skirmish", "laststand", "career", "settings", "controls"]:
		Game.main.show_menu(sname)
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shots_dir.path_join("menu_%s.png" % sname))
		print("[autotest] saved menu ", sname)
	get_tree().quit()


var fails := 0


func _check(name: String, ok: bool, info := "") -> void:
	print("[input] %s %s %s" % ["PASS" if ok else "FAIL", name, info])
	if not ok:
		fails += 1


func _act(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	Input.parse_input_event(r)
	await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Drives the gunship through real input events and checks each effect.
func _input_test(b) -> void:
	var g = b.gunship
	g.bot = false
	await _frames(5)
	var d0: Vector3 = g.look_dir
	var m := InputEventMouseMotion.new()
	m.relative = Vector2(300, 0)
	Input.parse_input_event(m)
	await _frames(3)
	_check("mouse slews sensor", g.look_dir.angle_to(d0) > 0.001, str(rad_to_deg(g.look_dir.angle_to(d0))))
	var mag0: float = g.mag_goal
	for i in 6:
		var w := InputEventMouseButton.new()
		w.button_index = MOUSE_BUTTON_WHEEL_UP
		w.pressed = true
		Input.parse_input_event(w)
		await get_tree().process_frame
	await _frames(30)
	_check("wheel zooms in", g.mag > mag0 * 2.0, "%.1f -> %.1f" % [mag0, g.mag])
	Input.action_press("zoom_in")
	await _frames(30)
	Input.action_release("zoom_in")
	_check("W zooms in further", g.mag_goal > 6.0, "%.1f" % g.mag_goal)
	await _act("weapon_1")
	var shots0: int = g.shots
	Input.action_press("fire")
	await _frames(30)
	Input.action_release("fire")
	_check("fire shoots", g.shots > shots0 + 10, "%d rounds" % (g.shots - shots0))
	var w0: int = g.wsel
	await _act("next_weapon")
	_check("next weapon", g.wsel != w0, "%d -> %d" % [w0, g.wsel])
	await _act("weapon_4")
	_check("weapon key 4", g.wsel == 3, g.weapon().def.short)
	var mode0: int = Game.view_mode
	await _act("view_mode")
	_check("view mode cycles", Game.view_mode != mode0, "%d -> %d" % [mode0, Game.view_mode])
	await _act("view_mode")
	await _act("view_mode")
	await _act("view_mode")
	_check("view mode wraps to TV", Game.view_mode == 0, str(Game.view_mode))
	Input.action_press("laser")
	await _frames(3)
	_check("laser on", g.lasing and b.laser_point() != null)
	Input.action_release("laser")
	await _frames(2)
	await _act("support")
	_check("support mode", g.support_mode)
	var ch0: int = g.supports[0].charges
	var gd0: int = b.ordnance.guided.size()
	await _act("fire")
	_check("support call", g.supports[0].charges == ch0 - 1 and b.ordnance.guided.size() > gd0, g.supports[0].def.short)
	var f0: int = g.flares
	await _act("flares")
	_check("flares", g.flares == f0 - 1)
	var a0: int = g.alt_i
	await _act("alt_up")
	_check("climb", g.alt_i == mini(a0 + 1, 2))
	await _act("map")
	_check("map opens", b.hud.map_big)
	await _act("map")
	_check("map closes", not b.hud.map_big)
	await _act("pause")
	_check("pause", get_tree().paused and b.pause_menu.is_open)
	await _act("pause")
	_check("unpause", not get_tree().paused)
	var u = b.units.nearest(g.aim_point, 3000.0)
	if u != null:
		g.aim_point = u.pos
		g.aim_valid = true
		await _frames(2)
		await _act("track")
		_check("track", g.track_unit != null)
	await _act("shift_orbit")
	_check("shift orbit", g.manual_orbit)
	print("[input] done, %d failures" % fails)
	get_tree().quit()


## Wins campaign mission i straight away, then checks the debrief and career.
func _flow(i: int) -> void:
	var xp0 := int(Game.career.get("xp", 0))
	var cfg := Missions.campaign_cfg(i)
	Game.start_mission(cfg)
	while _battle() == null:
		await get_tree().process_frame
	var b = _battle()
	await _frames(60)
	b.stats.kills = 5
	b.stats.score = 120
	b.mission.win("TEST WIN")
	while not (Game.main.current != null and Game.main.current.get("screen") == "debrief"):
		await get_tree().process_frame
	await _frames(10)
	var r: Dictionary = Game.last_result
	print("[flow] state=%s xp=%d->%d earned=%d completed=%s granted=%s new=%s rank_up=%s" % [r.state, xp0, int(Game.career.xp), int(r.xp),
		str(Game.career.completed.keys()), str(Game.career.granted), str(r.new_unlocks), str(r.rank_up)])
	print("[flow] next mission open: ", Game.campaign_open(i + 1))
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shots_dir.path_join("debrief.png"))
	get_tree().quit()


## Runs the updater against AC130_UPDATE_URL: check, download, swap.
func _update_test() -> void:
	print("[update] running ", OS.get_executable_path(), " v", Updater.current_version())
	Updater.check()
	var t0 := Time.get_ticks_msec()
	while Updater.status in ["idle", "checking"] and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	print("[update] check: ", Updater.status, " latest=", Updater.latest, " ", Updater.error)
	if Updater.status != "available":
		get_tree().quit()
		return
	Updater.install()
	while Updater.status == "downloading" and Time.get_ticks_msec() - t0 < 120000:
		await get_tree().process_frame
	print("[update] install: ", Updater.status, " ", Updater.error)
	if Updater.status == "ready" and OS.get_environment("AC130_VERSION_OUT") != "":
		print("[update] restarting")
		Updater.restart(PackedStringArray(["--headless", "--", "--autotest=version"]))
	get_tree().quit()


## Time to kill single soldiers with one weapon, aiming with point track:
## five standing still, then five on the move.
func _gun_test(b) -> void:
	var g = b.gunship
	g.bot = false
	for i in g.weapons.size():
		if g.weapons[i].id == gun_test:
			g.wsel = i
	g.mag_goal = 25.0
	for moving in [false, true]:
		var times: Array = []
		var rounds: Array = []
		for k in 5:
			var u = null
			for c in b.units.list:
				if c.alive and c.team == 1 and not c.veh and c.beh == "soldier" and c.pos.distance_to(g.orbit_center) < 1500.0:
					u = c
					break
			if u == null:
				break
			if moving:
				u.order = "move"
				u.path = [u.pos + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * 400.0]
				u.path_i = 0
				u.speed_mul = 1.6
			else:
				u.order = "hold"
				u.halted = true
			u.supp_t = 0.0
			g.aim_point = u.pos
			g.aim_valid = true
			g.track_unit = u
			await _frames(45)
			var s0: int = g.shots
			var t0 := t
			Input.action_press("fire")
			while u.alive and t - t0 < 15.0:
				u.supp_t = 0.0
				await get_tree().process_frame
			Input.action_release("fire")
			times.append(t - t0 if not u.alive else 99.0)
			rounds.append(g.shots - s0)
			if u.alive:
				b.units.kill(u, false, "")
			g.track_unit = null
			await _frames(60)
		print("[gun] %s %s: seconds to kill %s  rounds %s" % [gun_test, "moving" if moving else "standing", str(times), str(rounds)])
	get_tree().quit()


## Fires ground tracers and checks, every frame, that the drawn streak
## stays between the muzzle and the target.
func _tracer_test(b) -> void:
	var fx = b.effects
	var worst_behind := 0.0
	var worst_beyond := 0.0
	var first_gap := 0.0
	for k in 20:
		var a := Vector3(randf_range(-500, 500), 40.0, randf_range(-500, 500))
		var tgt := a + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(50.0, 600.0)
		var dir := (tgt - a).normalized()
		var dist := a.distance_to(tgt)
		fx.tracer(a, tgt, Color.GREEN, 800.0)
		var p: Dictionary = fx.tracers[fx.tracers.size() - 1]
		var n: MeshInstance3D = p.n
		var first := true
		while p in fx.tracers:
			var tail: Vector3 = n.transform.origin - n.transform.basis.y * 0.5
			var head: Vector3 = n.transform.origin + n.transform.basis.y * 0.5
			worst_behind = maxf(worst_behind, -(tail - a).dot(dir))
			worst_beyond = maxf(worst_beyond, (head - a).dot(dir) - dist)
			if first:
				first_gap = maxf(first_gap, (tail - a).length())
				first = false
			await get_tree().process_frame
	print("[tracer] max tail behind muzzle %.2f m, max head past target %.2f m, max first-frame tail gap %.2f m" % [worst_behind, worst_beyond, first_gap])
	get_tree().quit()


## Pairs of enemies and friendlies that can or can't see each other
## (terrain or buildings between). Only the visible pairs should trade fire.
func _los_test(map_id: String) -> void:
	Game.settings.loadout = "all"
	var cfg := Missions.skirmish_cfg(map_id, "cas", "day", 1)
	cfg["civ"] = 0.0
	Game.start_mission(cfg)
	while _battle() == null:
		await get_tree().process_frame
	var b = _battle()
	b.mission.set_process(false)
	b.gunship.bot = false
	for u in b.units.list.duplicate():
		b.units.remove_unit(u)
	var w = b.world
	var pairs: Array = []
	var want := {"terrain": 0, "building": 0, "clear": 0}
	var need := {"terrain": 3, "building": 3, "clear": 3}
	for tries in 20000:
		if want.terrain >= 3 and want.building >= 3 and want.clear >= 3:
			break
		var a := Vector2(randf_range(-2500, 2500), randf_range(-2500, 2500))
		if int(want.building) < 3 and tries % 2 == 0 and not w.towns.is_empty():
			var tw: Dictionary = w.towns[randi() % w.towns.size()]
			a = tw.pos + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * float(tw.r)
		var ang := randf() * TAU
		var c := a + Vector2(cos(ang), sin(ang)) * randf_range(150.0, 320.0)
		if not w.ground_ok(a) or not w.ground_ok(c):
			continue
		var far := true
		for pr in pairs:
			if a.distance_to(pr.a) < 950.0:
				far = false
		if not far:
			continue
		var A: Vector3 = w.to3(a)
		var C: Vector3 = w.to3(c)
		var vis: bool = w.los(A + Vector3(0, 1.6, 0), C + Vector3(0, 1.0, 0)) and w.los(C + Vector3(0, 1.6, 0), A + Vector3(0, 1.0, 0))
		var terrain_only: bool = w.los(A + Vector3(0, 1.6, 0), C + Vector3(0, 1.0, 0), false)
		var kind := "clear" if vis else ("building" if terrain_only else "terrain")
		if int(want[kind]) >= int(need[kind]):
			continue
		want[kind] = int(want[kind]) + 1
		var e = b.units.spawn("rifle", 1, A, "pe", {"order": "hold"})
		var f = b.units.spawn("soldier", 0, C, "pf", {"order": "hold"})
		e.hp = 100000.0
		f.hp = 100000.0
		pairs.append({"a": a, "kind": kind, "e": e, "f": f, "d": a.distance_to(c)})
	var t0 := t
	while t - t0 < 40.0:
		await get_tree().process_frame
	var bad := 0
	for pr in pairs:
		for side in [[pr.e, pr.f], [pr.f, pr.e]]:
			var shooter = side[0]
			var sees: bool = b.units.can_see(shooter, side[1])
			var shots: int = int(shooter.data.get("shots", 0))
			var ok: bool = (shots > 0) == sees
			if not ok:
				bad += 1
			print("[los] %-8s %4dm  %s %s, fired %3d  %s" % [pr.kind, int(pr.d), "enemy" if shooter.team == 1 else "friend", "sees" if sees else "blind", shots, "OK" if ok else "WRONG"])
	print("[los] %s done, %d wrong" % [map_id, bad])
	get_tree().quit()


## Frame-to-frame image motion at high zoom, in 1080p pixels: idle,
## minigun firing, and after a 105 round.
func _shake_test() -> void:
	Game.settings.loadout = "all"
	Game.start_mission(Missions.skirmish_cfg("kharim", "cas", "day", 1))
	while _battle() == null:
		await get_tree().process_frame
	var b = _battle()
	var g = b.gunship
	g.bot = false
	g.mag_max = 150.0
	g.mag_goal = 150.0
	g.mag = 150.0
	await _frames(30)
	for phase in ["idle", "minigun", "105"]:
		if phase == "minigun":
			g.wsel = 0
			Input.action_press("fire")
		elif phase == "105":
			Input.action_release("fire")
			await _frames(20)
			for i in g.weapons.size():
				if g.weapons[i].id == "w_105":
					g.wsel = i
			g._shoot(g.weapons[g.wsel])
		var anchor: Vector3 = g.aim_point
		var prev := Vector2.INF
		var jumps: Array = []
		var first := Vector2.ZERO
		var drift := 0.0
		for f in 90:
			await get_tree().process_frame
			var xf: Transform3D = g.cam.global_transform
			var to: Vector3 = (anchor - xf.origin).normalized()
			var px: float = deg_to_rad(g.fov()) / 1080.0
			var sp := Vector2(to.dot(xf.basis.x), to.dot(xf.basis.y)) / px
			if prev != Vector2.INF:
				jumps.append((sp - prev).length())
			else:
				first = sp
			drift = maxf(drift, (sp - first).length())
			prev = sp
		jumps.sort()
		print("[shake] %-7s ground point jumps per frame px: median %.2f  p90 %.2f  max %.2f   drift over 1.5 s %.1f px" % [phase, jumps[jumps.size() / 2], jumps[int(jumps.size() * 0.9)], jumps[jumps.size() - 1], drift])
	get_tree().quit()


## Sighting markers: none before friendlies see a group; while they keep
## sight the marker stays where it was placed even as the group moves; it
## only moves on a fresh sighting after sight was lost.
func _markers_test(type: String) -> void:
	Game.settings.loadout = "all"
	Game.start_mission(Missions.skirmish_cfg("kharim", type, "day", 1))
	while _battle() == null:
		await get_tree().process_frame
	var b = _battle()
	b.gunship.bot = false
	b.gunship.plane_dmg = 0.0
	var last := {}
	var placed := 0
	var moved_on_resight := 0
	var bad := 0
	var held_while_group_moved := 0.0
	var anchor_centre := {}
	for step in 9000:
		await get_tree().process_frame
		for fu in b.units.list:
			if fu.team == 0:
				fu.hp = 1.0e6
		var mi = b.mission
		for id in mi.contacts:
			var c: Dictionary = mi.contacts[id]
			var was = last.get(id)
			if c.pos != null and (was == null or was.pos == null):
				placed += 1
				if not c.seen:
					bad += 1
			elif c.pos != null and was != null and c.pos != was.pos:
				if was.seen:
					bad += 1
					print("[markers] WRONG: moved while still in sight")
				else:
					moved_on_resight += 1
			if c.pos != null and c.seen:
				var sum := Vector3.ZERO
				var n := 0
				for u in b.units.list:
					if u.alive and u.data.get("contact", -1) == id:
						sum += u.pos
						n += 1
				if n > 0:
					if not anchor_centre.has(id) or (was != null and not was.seen):
						anchor_centre[id] = sum / n
					held_while_group_moved = maxf(held_while_group_moved, (sum / n).distance_to(anchor_centre[id]))
			last[id] = {"pos": c.pos, "seen": c.seen}
	print("[markers] %s: %d markers placed on sighting, %d moved on re-sighting, %d wrong; while in sight a group moved up to %.0f m and its marker stayed put" % [type, placed, moved_on_resight, bad, held_while_group_moved])
	get_tree().quit()


## Staged sighting: seen at A -> marker at A; hidden behind terrain -> marker
## stays at A; seen again at B -> marker moves to B.
func _resight_test() -> void:
	Game.settings.loadout = "all"
	var cfg := Missions.skirmish_cfg("ridge", "cas", "day", 1)
	cfg["civ"] = 0.0
	Game.start_mission(cfg)
	while _battle() == null:
		await get_tree().process_frame
	var b = _battle()
	b.mission.set_process(false)
	b.gunship.bot = false
	for u in b.units.list.duplicate():
		b.units.remove_unit(u)
	var w = b.world
	# a friendly, a visible spot A, a hidden spot H and another visible spot B
	var F := Vector3.ZERO
	var A := Vector3.ZERO
	var H := Vector3.ZERO
	var B := Vector3.ZERO
	var found := false
	for tries in 20000:
		var f2 := Vector2(randf_range(-1800, 1800), randf_range(-1800, 1800))
		if not w.ground_ok(f2):
			continue
		F = w.to3(f2)
		var pts: Array = []
		for k in 3:
			var a := randf() * TAU
			var p2 := f2 + Vector2(cos(a), sin(a)) * randf_range(150.0, 300.0)
			pts.append(w.to3(p2) if w.ground_ok(p2) else Vector3.INF)
		if Vector3.INF in pts:
			continue
		var vis := func(p: Vector3) -> bool: return w.los(F + Vector3(0, 1.6, 0), p + Vector3(0, 1.0, 0))
		if vis.call(pts[0]) and not vis.call(pts[1]) and vis.call(pts[2]) and pts[0].distance_to(pts[2]) > 80.0:
			A = pts[0]
			H = pts[1]
			B = pts[2]
			found = true
			break
	if not found:
		print("[resight] no suitable spots")
		get_tree().quit()
		return
	var f = b.units.spawn("soldier", 0, F, "f", {"order": "hold"})
	var es: Array = [b.units.spawn("rifle", 1, A, "e", {"order": "hold"}), b.units.spawn("rifle", 1, A + Vector3(3, 0, 0), "e", {"order": "hold"})]
	for u in es + [f]:
		u.hp = 1.0e6
		u.halted = true
	b.mission.add_contact(es)
	var id: int = b.mission.next_contact - 1
	var c: Dictionary = b.mission.contacts[id]
	var report := func(stage: String, want: Vector3) -> void:
		var ok: bool = c.pos != null and c.pos.distance_to(want) < 10.0
		print("[resight] %-28s marker %s  (%.0f m from %s)  %s" % [stage, "none" if c.pos == null else str(c.pos.round()), -1.0 if c.pos == null else c.pos.distance_to(want), "expected spot", "OK" if ok else "WRONG"])
	for i in 150:
		b.mission._update_contacts(1.0 / 30.0)
		await get_tree().process_frame
	report.call("seen at A", A)
	for u in es:
		u.pos = w.to3(Vector2(H.x, H.z))
	for i in 240:
		b.mission._update_contacts(1.0 / 30.0)
		await get_tree().process_frame
	report.call("hidden behind terrain", A)
	for u in es:
		u.pos = w.to3(Vector2(B.x, B.z))
	for i in 150:
		b.mission._update_contacts(1.0 / 30.0)
		await get_tree().process_frame
	report.call("seen again at B", B)
	get_tree().quit()


## Every radio callout of an enemy position must put markers on the map at
## once, on the called group.
func _callout_test(spec: Array) -> void:
	Game.settings.loadout = "all"
	var cfg: Dictionary
	if spec[0] == "campaign":
		cfg = Missions.campaign_cfg(int(spec[1]))
		cfg["mode"] = "skirmish"
	else:
		cfg = Missions.skirmish_cfg(spec[1], spec[2], spec[3], 1)
	Game.start_mission(cfg)
	while _battle() == null:
		await get_tree().process_frame
	var b = _battle()
	b.gunship.bot = false
	b.gunship.plane_dmg = 0.0
	var keys := ["moving in from", "Contact", "horde", "SAM radar", "troops in contact", "convoy under attack", "movement coming"]
	var seen_lines := 0
	var calls := 0
	var good := 0
	var before := {}
	for step in 7200:
		for fu in b.units.list:
			if fu.team == 0:
				fu.hp = 1.0e6
		var snap := {}
		for id in b.mission.contacts:
			snap[id] = b.mission.contacts[id].pos
		await get_tree().process_frame
		var log: Array = b.hud.radio_log
		var lines: Array = []
		for r in log:
			if not r.has("checked"):
				r["checked"] = true
				lines.append(r)
		for r in lines:
			var hit := false
			for k in keys:
				if String(r.text).contains(k):
					hit = true
			if not hit:
				continue
			calls += 1
			var fresh: Array = []
			for id in b.mission.contacts:
				var c: Dictionary = b.mission.contacts[id]
				if c.pos != null and (not before.has(id) or before[id] == null or before[id] != c.pos):
					fresh.append(c)
			var desc := []
			for c in fresh:
				desc.append("%s %s" % [c.text, str(Vector3(c.pos).round())])
			if not fresh.is_empty():
				good += 1
			print("[callout] t=%3d %s: \"%s\" -> %d new marker(s) %s" % [int(t), r.who, String(r.text).left(70), fresh.size(), ", ".join(PackedStringArray(desc))])
		before = snap
		if b.ended:
			break
	print("[callout] %d enemy callouts, %d with new markers" % [calls, good])
	get_tree().quit()
