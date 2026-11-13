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
	if parts[0] == "thermal":
		flow_mode = true
		_thermal_test()
		return
	if parts[0] == "pickup":
		flow_mode = true
		_pickup_test(int(parts[1]))
		return
	if parts[0] == "illum":
		flow_mode = true
		_illum_test()
		return
	if parts[0] == "recsupport":
		flow_mode = true
		_recsupport_test()
		return
	if parts[0] == "replay":
		flow_mode = true
		_replay_test(parts[1] if parts.size() > 1 else "latest", parts.size() > 2 and parts[2] == "support")
		return
	if parts[0] == "gfx":
		flow_mode = true
		_gfx_test(parts[1] if parts.size() > 1 else "kharim", parts[2] if parts.size() > 2 else "day")
		return
	if parts[0] == "support":
		flow_mode = true
		_support_test(parts[1], parts[2] if parts.size() > 2 else "kharim")
		return
	if parts[0] == "alt":
		flow_mode = true
		_alt_test(parts[1])
		return
	if parts[0] == "predict":
		flow_mode = true
		_predict_test()
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
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--diff="):
			cfg["difficulty"] = int(arg.substr(7))
			Game.settings.difficulty = int(arg.substr(7))
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
		if b.mission.type == "zombie":
			# how bunched up the infected are: neighbours within 30 m, and
			# the share standing alone
			var zs: Array = []
			for zu in b.units.list:
				if zu.alive and zu.beh == "zombie":
					zs.append(zu)
			var nb := 0
			var alone := 0
			for zu in zs:
				var k := 0
				for v in b.units.query(zu.pos, 30.0):
					if v != zu and v.alive and v.beh == "zombie" and v.pos.distance_to(zu.pos) < 30.0:
						k += 1
				nb += k
				if k == 0:
					alone += 1
			print("   infected %d: average %.1f others within 30 m, %d%% alone" % [zs.size(), float(nb) / maxf(zs.size(), 1), int(100.0 * alone / maxf(zs.size(), 1))])
		if b.mission.type == "strike":
			var smi = b.mission
			var hs = smi.data.get("heli")
			var cen: Vector3 = b.units.centroid("sf")
			print("   strike phase=%d sf=%d boarded=%d sf_hp=%s dist_to_lz=%.0f enemies_near_sf(400)=%d heli=%s" % [smi.phase, b.units.count("sf"), b.units.boarded("sf"),
				str(b.units.members("sf").map(func(x): return int(x.hp))), cen.distance_to(smi.data.lz), b.units.enemies_near(cen, 400.0), "-" if hs == null else str(hs.data.get("state", ""))])
		if b.mission.type == "csar":
			var mi = b.mission
			var h = mi.data.get("heli")
			print("   csar phase=%d pilots=%d boarded=%d enemies_near_lz(250)=%d near_crash(150)=%d heli=%s timer=%.0f" % [mi.phase, b.units.count("pilot"), b.units.boarded("pilot"),
				b.units.enemies_near(mi.data.lz, 250.0), b.units.enemies_near(mi.site, 150.0), "-" if h == null else str(h.data.get("state", "")), mi.timer_left])
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
	for sname in ["title", "campaign", "skirmish", "laststand", "career", "settings", "controls", "replays", "credits"]:
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
	g.ssel = 0
	var ch0: int = g.supports[0].charges
	var gd0: int = b.ordnance.guided.size()
	await _act("weapon_1")
	g.wsel = 0
	var shots_before: int = g.shots
	# designate with the trigger and keep holding it, as a player would
	var press := InputEventAction.new()
	press.action = "fire"
	press.pressed = true
	Input.parse_input_event(press)
	Input.action_press("fire")
	await _frames(45)
	_check("support call", g.supports[0].charges == ch0 - 1 and b.ordnance.guided.size() > gd0, g.supports[0].def.short)
	_check("held trigger after a call doesn't fire the gun", g.shots == shots_before, "%d rounds" % (g.shots - shots_before))
	Input.action_release("fire")
	var rel := InputEventAction.new()
	rel.action = "fire"
	rel.pressed = false
	Input.parse_input_event(rel)
	await _frames(3)
	Input.action_press("fire")
	await _frames(15)
	Input.action_release("fire")
	_check("next trigger pull fires again", g.shots > shots_before, "%d rounds" % (g.shots - shots_before))
	var f0: int = g.flares
	await _act("flares")
	_check("flares", g.flares == f0 - 1)
	var a0: int = g.alt_ft
	await _act("alt_up")
	_check("climb", g.alt_ft == mini(a0 + 1000, 20000), "%d -> %d ft" % [a0, g.alt_ft])
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
		g.track_unit = null
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


## Target prediction: where the computer says each target will be when the
## rounds land vs where it actually is then, and the heat timings.
func _predict_test() -> void:
	Game.settings.loadout = "all"
	var cfg := Missions.skirmish_cfg("flats", "cas", "day", 1)
	cfg["civ"] = 0.0
	Game.start_mission(cfg)
	while _battle() == null:
		await get_tree().process_frame
	var b = _battle()
	b.mission.set_process(false)
	var g = b.gunship
	g.bot = false
	for u in b.units.list.duplicate():
		b.units.remove_unit(u)
	var road: Array = b.world.route_points(0, false, 0.3, 0.7)
	var truck = b.units.spawn("truck", 1, road[0], "e", {"order": "path", "path": road.duplicate()})
	var start: Vector3 = road[0] + Vector3(40, 0, 40)
	var man = b.units.spawn("rifle", 1, start, "e", {"order": "move", "path": [start + Vector3(300, 0, 120)], "speed_mul": 1.4})
	for u in [truck, man]:
		u.hp = 1.0e6
	var civ = b.units.spawn("civ", 2, road[0] + Vector3(15, 0, 0), "c", {"order": "move", "path": [road[0] + Vector3(200, 0, 0)]})
	var pal = b.units.spawn("soldier", 0, road[0] + Vector3(-15, 0, 0), "f", {"order": "move", "path": [road[0] + Vector3(-200, 0, 0)]})
	civ.hp = 1.0e6
	pal.hp = 1.0e6
	await _frames(60)
	await _act("predictor")
	print("[predict] predictor on: ", g.predict_on)
	g.aim_point = truck.pos
	g.aim_valid = true
	await _frames(5)
	var teams := {0: 0, 1: 0, 2: 0}
	for x in g.predictions:
		for u in [truck, man, civ, pal]:
			if x.from.distance_to(u.pos) < 3.0:
				teams[u.team] += 1
	print("[predict] marked near the aim point: %d enemy, %d civilian, %d friendly" % [teams[1], teams[2], teams[0]])
	for target in [truck, man]:
		for wid in ["w_762", "w_105"]:
			for i in g.weapons.size():
				if g.weapons[i].id == wid:
					g.wsel = i
			g.aim_point = target.pos
			g.aim_valid = true
			g.track_unit = target
			await _frames(20)
			var pr = null
			for x in g.predictions:
				if x.from.distance_to(target.pos) < 5.0:
					pr = x
			if pr == null:
				print("[predict] FAIL no prediction for ", target.kind)
				continue
			if shots_dir != "" and wid == "w_105" and target == truck:
				g.mag = 12.0
				g.mag_goal = 12.0
				g.pred_heat = 40.0
				await _frames(10)
				DirAccess.make_dir_recursive_absolute(shots_dir)
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(shots_dir.path_join("predict.png"))
				print("[predict] screenshot saved")
				get_tree().quit()
				return
			var t0 := t
			var to: Vector3 = pr.to
			var moved: float = pr.from.distance_to(to)
			while t - t0 < float(pr.t):
				await get_tree().process_frame
			print("[predict] %-6s %-6s T+%.1f s: predicted %.0f m of travel, missed actual position by %.1f m" % [target.kind, wid, pr.t, moved, to.distance_to(target.pos)])
	g.track_unit = truck
	g.pred_heat = 0.0
	var t1 := t
	while g.pred_shutdown <= 0.0 and t - t1 < 120.0:
		await get_tree().process_frame
	print("[predict] continuous use until overheat: %.1f s" % (t - t1))
	var t2 := t
	while g.pred_shutdown > 0.0 and t - t2 < 200.0:
		await get_tree().process_frame
	print("[predict] shutdown lasted %.1f s, heat now %.0f%%, predictions during shutdown: none" % [t - t2, g.pred_heat])
	var t3 := t
	while g.pred_heat < 50.0 and t - t3 < 60.0:
		await get_tree().process_frame
	await _act("predictor")
	var t4 := t
	while g.pred_heat > 0.0 and t - t4 < 200.0:
		await get_tree().process_frame
	print("[predict] from 50%% heat, switched off: cooled to 0 in %.1f s" % (t - t4))
	get_tree().quit()


## Commanded altitude 2,000 then 20,000 ft: actual height, and the lowest
## clearance over terrain anywhere on the orbit.
func _alt_test(map_id: String) -> void:
	Game.settings.loadout = "all"
	Game.start_mission(Missions.skirmish_cfg(map_id, "cas", "day", 1))
	while _battle() == null:
		await get_tree().process_frame
	var b = _battle()
	b.gunship.bot = false
	b.gunship.plane_dmg = 0.0
	b.mission.set_process(false)
	var g = b.gunship
	for want in [2000, 20000]:
		g.alt_ft = want
		var clear := 1.0e9
		var t0 := t
		while t - t0 < 300.0:
			await get_tree().process_frame
			var p: Vector3 = g.global_position
			clear = minf(clear, p.y - b.world.height(p.x, p.z))
		print("[alt] %s commanded %d ft: flying %s ft above the orbit centre, lowest clearance over terrain %.0f m" % [map_id, want, g.alt_text(), clear])
	get_tree().quit()


## Each new support call, checked by what it does on the ground.
func _support_test(kind: String, map_id: String) -> void:
	Game.settings.loadout = "all"
	var cfg := Missions.skirmish_cfg(map_id, "cas", "day", 1)
	cfg["civ"] = 0.0
	Game.start_mission(cfg)
	while _battle() == null:
		await get_tree().process_frame
	var b = _battle()
	b.mission.set_process(false)
	var g = b.gunship
	g.bot = false
	g.plane_dmg = 0.0
	for u in b.units.list.duplicate():
		if u.group != "garrison":
			b.units.remove_unit(u)
	var w = b.world
	var c: Vector3 = w.to3(Vector2(400, -600))
	for k in 30:
		var cc := Vector2(randf_range(-1500, 1500), randf_range(-1500, 1500))
		if w.ground_ok(cc) and not w.in_building(cc, 40.0):
			c = w.to3(cc)
			break
	var ang := 1.0
	var dir := Vector3(sin(ang), 0, -cos(ang))
	match kind:
		"a10":
			var on_line: Array = []
			for k in 12:
				var p: Vector3 = c + dir * randf_range(-130.0, 130.0) + dir.cross(Vector3.UP) * randf_range(-6.0, 6.0)
				on_line.append(b.units.spawn("technical" if k % 4 == 0 else "rifle", 1, p, "e", {"order": "hold"}))
			var off_line: Array = []
			for k in 6:
				var p2: Vector3 = c + dir.cross(Vector3.UP) * randf_range(60.0, 100.0) + dir * randf_range(-100.0, 100.0)
				off_line.append(b.units.spawn("rifle", 1, p2, "e2", {"order": "hold"}))
			for u in on_line + off_line:
				u.halted = true
			b.support.gun_run(c, ang, b.gunship.Data.SUPPORT["s_a10"])
			await _wait_s(22.0)
			var k1 := 0
			for u in on_line:
				if not u.alive:
					k1 += 1
			var k2 := 0
			for u in off_line:
				if not u.alive:
					k2 += 1
			print("[support] A-10: %d of 12 on the strafe line killed, %d of 6 standing 60-100 m off the line killed" % [k1, k2])
		"sof":
			var grp: Array = b.units.squad(["rifle", "rifle", "emg", "rifle", "rpg", "rifle", "rifle", "rifle", "rifle", "rifle", "rifle", "rifle"], 1, c + dir.cross(Vector3.UP) * 70.0, 25.0, "e", {"order": "hold"})
			var far: Array = b.units.squad(["rifle", "rifle", "rifle"], 1, c + dir.cross(Vector3.UP) * 700.0, 10.0, "far", {"order": "hold"})
			var start := {}
			for u in grp + far:
				start[u.id] = u.pos
			b.support.show_of_force(c, ang, b.gunship.Data.SUPPORT["s_sof"])
			await _wait_s(20.0)
			var fled := 0
			var dirs: Array = []
			for u in grp:
				var mv: Vector3 = u.pos - start[u.id]
				if u.order == "flee" or mv.length() > 20.0:
					fled += 1
				dirs.append(rad_to_deg(atan2(mv.x, -mv.z)))
			var far_moved := 0
			for u in far:
				if u.pos.distance_to(start[u.id]) > 5.0:
					far_moved += 1
			dirs.sort()
			print("[support] show of force: %d of 12 near the path ran (headings %d..%d deg), %d of 3 standing 700 m away moved" % [fled, int(dirs[0]), int(dirs[dirs.size() - 1]), far_moved])
			await _wait_s(70.0)
			var back := 0
			for u in grp:
				if u.order == "hold" and not u.data.has("panic_until"):
					back += 1
			print("[support] show of force: 70 s later %d of 12 have stopped running and gone back to their orders" % back)
		"qrf":
			var target: Vector3 = c
			var base: Vector3 = w.site("qrf")
			var t0 := t
			b.support.send_qrf(target)
			var path: Array = b.units.members("qrf1")[0].path
			var on_road := 0
			for p in path:
				if w.road_at(Vector2(p.x, p.z)) > 0.3:
					on_road += 1
			print("[support] QRF: %d vehicles, route %d points, %d%% on roads, %.0f m straight-line" % [b.units.count("qrf1"), path.size(), int(100.0 * on_road / maxf(path.size(), 1)), base.distance_to(target)])
			while t - t0 < 900.0:
				await _wait_s(5.0)
				if int(t - t0) % 60 < 5:
					for u in b.units.members("qrf1"):
						if u.veh:
							print("   %s path %d/%d moving=%s order=%s pos=%s detour=%.1f leader=%s" % [u.kind, u.path_i, u.path.size(), u.moving, u.order, str(u.pos.round()), float(u.data.get("detour_t", 0.0)), "none" if u.leader == null else "%s %d" % [u.leader.order, u.leader.path_i]])
				var inf := 0
				for u in b.units.members("qrf1"):
					if not u.veh:
						inf += 1
				if inf >= 25:
					break
			var near := 0
			var inf2 := 0
			for u in b.units.members("qrf1"):
				if not u.veh:
					inf2 += 1
					if u.pos.distance_to(target) < 120.0:
						near += 1
			print("[support] QRF: after %.0f s, %d infantry dismounted, %d of them within 120 m of the objective" % [t - t0, inf2, near])
		"heli":
			var t1 := t
			b.support.insert_squad(c)
			var h = b.units.members("airmob_heli")[0]
			var landed := -1.0
			while t - t1 < 240.0:
				await get_tree().process_frame
				if landed < 0.0 and h.data.get("state", "") == "wait":
					landed = t - t1
				if h.data.get("state", "") == "gone":
					break
			var sq: Array = b.units.members("airmob")
			var dist := 0.0
			for u in sq:
				dist = maxf(dist, u.pos.distance_to(c))
			print("[support] Black Hawk: landed after %.0f s, %d soldiers on the ground (all within %.0f m of the call), helicopter %s after %.0f s" % [landed, sq.size(), dist, h.data.get("state", ""), t - t1])
	get_tree().quit()


func _wait_s(secs: float) -> void:
	var t0 := t
	while t - t0 < secs:
		await get_tree().process_frame


## Close-up screenshots of people, vehicles, buildings and the new jets.
func _gfx_test(map_id: String, tod: String) -> void:
	Game.settings.loadout = "all"
	var cfg := Missions.skirmish_cfg(map_id, "cas", tod, 1)
	Game.start_mission(cfg)
	while _battle() == null:
		await get_tree().process_frame
	var b = _battle()
	b.mission.set_process(false)
	var g = b.gunship
	g.bot = false
	g.track_unit = null
	g.plane_dmg = 0.0
	var w = b.world
	DirAccess.make_dir_recursive_absolute(shots_dir)
	# an open spot near the orbit centre for the vehicle line-up
	var spot: Vector3 = g.orbit_center
	for k in 60:
		var c2 := Vector2(g.orbit_center.x, g.orbit_center.z) + Vector2(randf_range(-600, 600), randf_range(-600, 600))
		if w.ground_ok(c2) and not w.in_building(c2, 45.0) and w.road_at(c2) < 0.1:
			spot = w.to3(c2)
			break
	var kinds := ["tank", "btr", "truck", "technical", "humvee", "mrap", "suv", "car", "pickup", "sam"]
	for i in kinds.size():
		var p: Vector3 = spot + Vector3((i - 4.5) * 9.0, 0, 0)
		var u = b.units.spawn(kinds[i], 1 if i < 4 or i > 7 else 0, p, "show", {"order": "hold", "heading": 0.3})
		u.hp = 1.0e6
	for i in 2:
		b.units.spawn("heli", 0, spot + Vector3(-12.0 + i * 26.0, 0, -45), "show", {"beh": "static", "airframe": ["uh60", "ch47"][i], "heading": 0.5})
	var walkers: Array = b.units.squad(["rifle", "rifle", "rpg", "emg", "civ", "civ", "civ", "soldier", "zombie", "survivor", "sf", "pilot"], 1, spot + Vector3(0, 0, 30), 6.0, "walk", {"order": "move"})
	for u in walkers:
		u.team = 2
		u.path = [u.pos + Vector3(0, 0, 300)]
		u.path_i = 0
		u.hp = 1.0e6
	var shots := [
		["gfx_vehicles_60x", spot, 60.0], ["gfx_vehicles_150x", spot + Vector3(-15, 0, 0), 150.0],
		["gfx_people_150x", null, 150.0], ["gfx_helis_40x", spot + Vector3(0, 0, -45), 40.0],
		["gfx_helis_120x", spot + Vector3(14, 0, -45), 120.0], ["gfx_people_whot", null, 100.0],
	]
	for sh in shots:
		var p = sh[1]
		if p == null:
			p = walkers[0].pos
			g.track_unit = walkers[0]
		Game.set_view_mode(2 if sh[0].ends_with("whot") else 0)
		g.aim_point = p
		g.aim_valid = true
		g.mag_max = 150.0
		g.mag = sh[2]
		g.mag_goal = sh[2]
		await _frames(8)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shots_dir.path_join(sh[0] + ".png"))
		print("[gfx] saved ", sh[0])
	g.track_unit = null
	# buildings: the mosque, a city block, a few houses
	var picks := {}
	for bd in w.buildings:
		if not picks.has(bd.kind):
			picks[bd.kind] = bd
	for kind in ["mosque", "tall", "house"]:
		if picks.has(kind):
			var bd: Dictionary = picks[kind]
			g.aim_point = Vector3(bd.c.x, bd.c.y, bd.c.z)
			g.mag = 40.0 if kind != "house" else 70.0
			g.mag_goal = g.mag
			await _frames(8)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(shots_dir.path_join("gfx_bld_%s.png" % kind))
			print("[gfx] saved building ", kind)
	# the jets: an A-10 run and a show of force over the line-up
	b.support.gun_run(spot, 1.2, b.gunship.Data.SUPPORT["s_a10"])
	g.aim_point = spot
	g.mag = 6.0
	g.mag_goal = 6.0
	await _wait_s(15.4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots_dir.path_join("gfx_a10.png"))
	await _wait_s(1.5)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots_dir.path_join("gfx_a10_impacts.png"))
	b.support.show_of_force(spot + Vector3(200, 0, 0), 2.6, b.gunship.Data.SUPPORT["s_sof"])
	g.aim_point = spot + Vector3(200, 0, 0)
	g.mag = 3.0
	g.mag_goal = 3.0
	await _wait_s(16.0)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots_dir.path_join("gfx_sof.png"))
	print("[gfx] done")
	get_tree().quit()


## Night: the ground before an illumination round and while it burns, and
## the flare's height when it burns out.
func _illum_test() -> void:
	Game.settings.loadout = "all"
	Game.start_mission(Missions.skirmish_cfg("kharim", "cas", "night", 1))
	while _battle() == null:
		await get_tree().process_frame
	var b = _battle()
	b.mission.set_process(false)
	var g = b.gunship
	g.bot = false
	g.track_unit = null
	g.plane_dmg = 0.0
	DirAccess.make_dir_recursive_absolute(shots_dir)
	var c: Vector3 = b.world.site("hq")
	g.aim_point = c
	g.aim_valid = true
	g.mag = 4.0
	g.mag_goal = 4.0
	await _frames(10)
	for shot in [["illum_0_before", 0.0], ["illum_1_lit", 20.0], ["illum_2_late", 45.0]]:
		if shot[0] == "illum_1_lit":
			g.support_mode = true
			for i in g.supports.size():
				if g.supports[i].id == "s_illum":
					g.ssel = i
			g._call_support()
		await _wait_s(float(shot[1]) - (20.0 if shot[0] == "illum_2_late" else 0.0))
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shots_dir.path_join(shot[0] + ".png"))
		var y := -1.0
		for it in b.ordnance.illum:
			y = it.l.position.y - b.world.height(it.l.position.x, it.l.position.z)
		print("[illum] %s: flare %s" % [shot[0], "not lit" if y < 0.0 else "%.0f m above the ground" % y])
	var last := 0.0
	while not b.ordnance.illum.is_empty():
		var it2: Dictionary = b.ordnance.illum[0]
		last = it2.l.position.y - b.world.height(it2.l.position.x, it2.l.position.z)
		await get_tree().process_frame
	print("[illum] burned out %.0f m above the ground" % last)
	get_tree().quit()


## Called-in troops get lifted out when the mission's extraction comes.
func _pickup_test(m: int) -> void:
	Game.settings.loadout = "all"
	var cfg := Missions.campaign_cfg(m)
	cfg["mode"] = "skirmish"
	Game.start_mission(cfg)
	while _battle() == null:
		await get_tree().process_frame
	var b = _battle()
	b.gunship.plane_dmg = 0.0
	await _wait_s(3.0)
	var near: Vector3 = b.mission.site if b.mission.site != Vector3.ZERO else b.mission.focus
	b.support.send_qrf(near + Vector3(150, 0, 80))
	b.support.insert_squad(near + Vector3(-120, 0, -60))
	var main_t := -1.0
	var lift_t := -1.0
	var t0 := t
	var next_dbg := 0.0
	while not b.ended and t - t0 < 900.0:
		await get_tree().process_frame
		if lift_t > 0.0 and t - t0 > next_dbg:
			next_dbg = t - t0 + 15.0
			for h in b.units.list:
				if h.kind == "heli" and h.group == "lift_heli":
					var n_near := 0
					var n_far := 0
					var orders := {}
					for v in b.units.list:
						if v.alive and v.id in h.data.pickup:
							orders[v.order] = orders.get(v.order, 0) + 1
							if v.pos.distance_to(h.pos) < 60.0:
								n_near += 1
							else:
								n_far += 1
					print("   t=%.0f lift %s at %s, lz dist %.0f, passengers alive %d (near %d, far %d) orders %s" % [t - t0, h.data.get("state", ""), str(h.pos.round()), Vector2(h.pos.x - h.data.lz.x, h.pos.z - h.data.lz.z).length(), n_near + n_far, n_near, n_far, str(orders)])
		for u in b.units.list:
			if u.kind == "heli" and u.group == "heli" and main_t < 0.0:
				main_t = t - t0
			if u.kind == "heli" and u.group == "lift_heli" and lift_t < 0.0:
				lift_t = t - t0
	var aboard := 0
	var left := 0
	for u in b.units.list:
		if u.group.begins_with("qrf") or u.group == "airmob":
			if u.boarded:
				aboard += 1
			elif u.alive and not u.veh:
				left += 1
	var lifts := 0
	for u in b.units.list:
		if u.kind == "heli" and u.group == "lift_heli":
			lifts += 1
	print("[pickup] mission %s at %.0f s (%s). Extraction launched at %.0f s, %d pickup helicopter(s) launched at %.0f s. Called-in troops: %d aboard, %d still on the ground when it ended" % [b.mission.state, t - t0, b.mission.result_text, main_t, lifts, lift_t, aboard, left])
	get_tree().quit()


## A row of people in thermal: soldier, civilian, enemy, survivor, infected.
func _thermal_test() -> void:
	Game.settings.loadout = "all"
	Game.start_mission(Missions.skirmish_cfg("flats", "cas", "night", 1))
	while _battle() == null:
		await get_tree().process_frame
	var b = _battle()
	b.mission.set_process(false)
	var g = b.gunship
	g.bot = false
	g.track_unit = null
	for u in b.units.list.duplicate():
		b.units.remove_unit(u)
	var c: Vector3 = b.world.to3(Vector2(300, 600))
	var kinds := ["soldier", "civ", "zombie", "rifle", "zombie", "survivor", "brute"]
	for i in kinds.size():
		var u = b.units.spawn(kinds[i], 1 if kinds[i] in ["zombie", "brute", "rifle"] else 0, c + Vector3((i - 3) * 3.0, 0, 0), "row", {"order": "hold", "heading": PI})
		u.halted = true
		u.data["hide_r"] = 0.0
		u.d = u.d.duplicate()
		u.d["range"] = 0.0
	g.aim_point = c
	g.aim_valid = true
	g.mag_max = 150.0
	g.mag = 120.0
	g.mag_goal = 120.0
	DirAccess.make_dir_recursive_absolute(shots_dir)
	for m in [2, 3]:
		b.set_view_mode(m)
		await _frames(8)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shots_dir.path_join("thermal_%d.png" % m))
	print("[thermal] saved")
	get_tree().quit()


## Plays the newest (or a given) replay: screenshots from each camera at a
## few times, checks units move and a backward seek restores buildings.
func _replay_test(which: String, support := false) -> void:
	var Rec := load("res://scripts/battle/recorder.gd")
	var files: Array = Rec.list()
	var fp: String = files[0] if which == "latest" and not files.is_empty() else which
	print("[replay] file ", fp, " size ", FileAccess.get_file_as_bytes(fp).size() / 1024, " KB")
	Game.main.start_replay(fp)
	var r = Game.main.current
	while not r.built:
		await get_tree().process_frame
	var d: Dictionary = r.data
	var keys := 0
	for id in d.units:
		keys += d.units[id].track.size() / 7
	print("[replay] length %.0f s, %d units, %d keys, %d events, %d frames, %d buildings fell" % [r.length, d.units.size(), keys,
		r.ev.size(), r.frame_t.size(), _count_ev(r.ev, 4)])
	DirAccess.make_dir_recursive_absolute(shots_dir)
	var plan := [[0.25, 0, "free"], [0.25, 1, "sensor"], [0.25, 2, "chase"], [0.6, 0, "free_late"], [0.9, 1, "sensor_late"], [0.9, 0, "free_wide"]]
	r._seek(r.length)
	print("[replay] after seek to end: ev_i %d of %d, fallen %d" % [r.ev_i, r.ev.size(), r.saved_bld.size()])
	if support:
		# times in seconds: missiles inbound, the A-10 pass, the flare burning
		plan = [[-10.0, 0, "s_missile"], [-17.0, 0, "s_a10"], [-19.5, 2, "s_chase"], [-30.0, 1, "s_sensor_nv"], [-30.0, 0, "s_illum_wide"]]
	for st in plan:
		r._seek(r.length * st[0] if st[0] >= 0.0 else -st[0])
		r.cam_mode = st[1]
		r._cam_mode_changed()
		if st[1] == 0:
			var off := Vector3(-60, 35, 60) if not st[2].ends_with("wide") else Vector3(-900, 700, 900)
			if st[2] == "s_missile" or st[2] == "s_a10":
				off = Vector3(-300, 150, 300)
			r.cam.global_position = r.aim + off
			r._look_at(r.aim)
		if st[2] == "s_a10" or st[2] == "s_missile":
			await _frames(2)
			var want: int = 5 if st[2] == "s_a10" else 1
			for rid in r.objects:
				var ob: Dictionary = r.objects[rid]
				if ob.type == want and ob.node:
					r.paused = true
					var op: Vector3 = ob.node.global_position
					r.cam.global_position = op + Vector3(-40, 15, 40)
					r._look_at(op)
					print("[replay] %s object at %s" % [st[2], op])
		var moved := _unit_positions(r)
		await _wait_real(1.5)
		var moved2 := _unit_positions(r)
		var n := 0
		for id in moved:
			if moved2.has(id) and moved[id].distance_to(moved2[id]) > 0.5:
				n += 1
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shots_dir.path_join("replay_%s.png" % st[2]))
		r.paused = false
		print("[replay] %s at %.0f s: %d units visible, %d moved in 1.5 s, %d objects" % [st[2], r.rt, moved.size(), n, r.objects.size()])
	var fell: int = r.saved_bld.size()
	var top_fallen := -1.0
	if fell > 0:
		top_fallen = r.world.buildings[r.saved_bld.keys()[0]].top
	var first: int = r.saved_bld.keys()[0] if fell > 0 else -1
	r._seek(0.0)
	var top_back: float = r.world.buildings[first].top if first >= 0 else -1.0
	print("[replay] seek back: %d fallen buildings before, %d after; first one's top %.1f -> %.1f, alive %s" % [fell, r.saved_bld.size(),
		top_fallen, top_back, str(r.world.buildings[first].alive) if first >= 0 else "-"])
	r._exit()
	await _frames(3)
	get_tree().quit()


func _count_ev(ev: PackedFloat32Array, code: int) -> int:
	var Rec := load("res://scripts/battle/recorder.gd")
	var i := 0
	var n := 0
	while i < ev.size():
		if int(ev[i + 1]) == code:
			n += 1
		i += 2 + int(Rec.EV_ARGS.get(int(ev[i + 1]), 0))
	return n


func _unit_positions(r) -> Dictionary:
	var out := {}
	for id in r.units:
		var mi: MeshInstance3D = r.units[id].node
		if mi.visible:
			out[id] = mi.global_position
	return out


func _wait_real(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


## Records a short night sortie with an A-10 run, a Hellfire, a show of force
## and an illumination round, then ends it normally so the replay is saved.
func _recsupport_test() -> void:
	Game.record_test = true
	Game.settings.loadout = "all"
	Game.start_mission(Missions.skirmish_cfg("kharim", "cas", "night", 1))
	while _battle() == null:
		await get_tree().process_frame
	var b = _battle()
	var g = b.gunship
	await _wait_s(4.0)
	var Data := load("res://scripts/data/data.gd")
	var p: Vector3 = g.aim_point
	b.support.gun_run(p, 1.2, Data.SUPPORT["s_a10"])
	b.support.show_of_force(p + Vector3(300, 0, 0), 2.6, Data.SUPPORT["s_sof"])
	var h: Dictionary = Data.SUPPORT["s_hellfire"]
	b.ordnance.launch_guided("missile", h, p + Vector3(3500, 4500, 0), p + Vector3(40, 0, 40), float(h.tot), h.guide, true, "s_hellfire")
	var il: Dictionary = Data.SUPPORT["s_illum"]
	b.ordnance.launch_guided("illum", il, p + Vector3(0, 6500, 3000), p, float(il.tot), il.guide, true, "s_illum")
	var near: Array = b.world.buildings_near(Vector2(p.x, p.z), 600.0)
	for k in mini(3, near.size()):
		b.world._collapse(near[k])
	print("[recsupport] calls at %.0f s, %d buildings dropped" % [b.time, mini(3, near.size())])
	await _wait_s(40.0)
	b.mission.lose("RECORDING TEST")

