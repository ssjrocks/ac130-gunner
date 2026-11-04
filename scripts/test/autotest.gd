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
	if b == null or flow_mode:
		return
	t += dt
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
