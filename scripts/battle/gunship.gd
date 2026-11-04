extends Node3D
## The AC-130: orbit flight, the stabilised sensor turret (the camera),
## guns, laser designator, support calls and countermeasures.

const Data := preload("res://scripts/data/data.gd")
const FOV_WIDE := 55.0
const ALTS := [2440.0, 3050.0, 3660.0]
const ALT_FT := ["8,000", "10,000", "12,000"]

var battle
var cam: Camera3D
var orbit_center := Vector3.ZERO
var orbit_goal := Vector3.ZERO
var manual_orbit := false
var radius := 2700.0
var alt_i := 1
var alt := 3050.0
var theta := 0.0
var speed := 77.0
var forward := Vector3.FORWARD
var left := Vector3.LEFT
var look_dir := Vector3.DOWN
var aim_valid := false
var aim_point := Vector3.ZERO
var aim_bidx := -1
var aim_water := false
var aim_range := 0.0
var mag := 1.0
var mag_goal := 1.0
var mag_max := 25.0
var last_narrow := 12.0
var modes: Array = [0]
var mode_i := 0
var weapons: Array = []
var wsel := 0
var supports: Array = []
var ssel := 0
var support_mode := false
var lasing := false
var laser_latch := false
var has_laser := false
var track_unit = null
var track_off := Vector3.ZERO
var hp := 100.0
var flares := 30
var flare_cd := 0.0
var shake := 0.0
var mouse_delta := Vector2.ZERO
var shots := 0
var auto_flares := false
var plane_dmg := 1.0
var bot := false
var bot_t := 0.0
var time := 0.0
var mg_on := false


func setup(cfg: Dictionary, loadout: Array) -> void:
	cam = Camera3D.new()
	cam.top_level = true
	# Frustum projection: Godot's perspective FOV stops at 1 degree, the
	# sensor needs far narrower fields of view than that.
	cam.projection = Camera3D.PROJECTION_FRUSTUM
	cam.near = 20.0
	cam.far = 60000.0
	add_child(cam)
	cam.current = true
	for id in Data.WEAPON_ORDER:
		if id in loadout:
			var def: Dictionary = Data.WEAPONS[id]
			var total: int = def.get("total", -1)
			weapons.append({"id": id, "def": def, "ammo": def.mag, "reload_t": 0.0, "cd": 0.0, "spare": total - 1 if total > 0 else -1})
	if weapons.is_empty():
		var d762: Dictionary = Data.WEAPONS["w_762"]
		weapons.append({"id": "w_762", "def": d762, "ammo": d762.mag, "reload_t": 0.0, "cd": 0.0, "spare": -1})
	if "v_nv" in loadout:
		modes.append(1)
	if "v_ir" in loadout:
		modes.append(2)
		modes.append(3)
	mag_max = 25.0
	if "o_60" in loadout:
		mag_max = 60.0
	if "o_150" in loadout:
		mag_max = 150.0
	has_laser = "laser" in loadout or "w_griffin" in loadout or "w_lgb" in loadout
	var sup: Dictionary = cfg.get("supports", {})
	for sid in Data.SUPPORT_ORDER:
		if sup.has(sid) and sid in loadout:
			supports.append({"id": sid, "def": Data.SUPPORT[sid], "charges": int(sup[sid])})
	var diff: Dictionary = Data.DIFFICULTY[clampi(int(cfg.get("difficulty", 1)), 0, 2)]
	auto_flares = diff.auto_flares
	plane_dmg = diff.plane_dmg
	flares = int(cfg.get("flares", 30))
	orbit_center = cfg.get("focus", Vector3.ZERO)
	orbit_goal = orbit_center
	theta = randf() * TAU
	_fly(0.0)
	aim_point = Vector3(orbit_center.x, battle.world.height(orbit_center.x, orbit_center.z), orbit_center.z)
	aim_valid = true
	look_dir = (aim_point - global_position).normalized()
	_update_camera(0.0)


func fov() -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(FOV_WIDE) * 0.5) / mag))


func view_height_m() -> float:
	return 2.0 * aim_range * tan(deg_to_rad(fov()) * 0.5)


func weapon() -> Dictionary:
	return weapons[wsel]


func heading_deg() -> float:
	return fposmod(rad_to_deg(atan2(forward.x, -forward.z)), 360.0)


func look_bearing() -> float:
	return fposmod(rad_to_deg(atan2(look_dir.x, -look_dir.z)), 360.0)


func set_orbit(p: Vector3, manual: bool) -> void:
	var lim := 2300.0
	orbit_goal = Vector3(clampf(p.x, -lim, lim), 0.0, clampf(p.z, -lim, lim))
	if manual:
		manual_orbit = true


func _fly(dt: float) -> void:
	orbit_center = orbit_center.move_toward(orbit_goal, 45.0 * dt)
	alt = move_toward(alt, ALTS[alt_i], 15.0 * dt)
	theta -= speed / radius * dt
	var gy: float = battle.world.height(orbit_center.x, orbit_center.z)
	global_position = Vector3(orbit_center.x + cos(theta) * radius, gy + alt, orbit_center.z + sin(theta) * radius)
	forward = Vector3(sin(theta), 0.0, -cos(theta))
	left = Vector3.UP.cross(forward)


# --- Input ----------------------------------------------------------------

func _unhandled_input(ev: InputEvent) -> void:
	if get_tree().paused or battle.ended:
		return
	if ev is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or Game.autotest != "":
			mouse_delta += ev.relative
		return
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			mag_goal = minf(mag_goal * 1.2, mag_max)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			mag_goal = maxf(mag_goal / 1.2, 1.0)
	if ev.is_action_pressed("next_weapon"):
		_cycle(1)
	elif ev.is_action_pressed("prev_weapon"):
		_cycle(-1)
	for k in 6:
		if ev.is_action_pressed("weapon_%d" % (k + 1)):
			if support_mode:
				if k < supports.size():
					ssel = k
			elif k < weapons.size():
				_select(k)
	if ev.is_action_pressed("zoom_toggle"):
		if mag > 1.5:
			last_narrow = mag
			mag_goal = 1.0
		else:
			mag_goal = minf(last_narrow, mag_max)
	if ev.is_action_pressed("view_mode") and modes.size() > 1:
		mode_i = (mode_i + 1) % modes.size()
		battle.set_view_mode(modes[mode_i])
		Sfx.play("click", -6.0)
	if ev.is_action_pressed("flares"):
		release_flares()
	if ev.is_action_pressed("track"):
		_toggle_track()
	if ev.is_action_pressed("shift_orbit") and aim_valid:
		set_orbit(aim_point, true)
		battle.radio("PILOT", "Copy, shifting orbit to your sensor point.")
	if ev.is_action_pressed("alt_up") and alt_i < 2:
		alt_i += 1
		battle.radio("PILOT", "Climbing to %s feet." % ALT_FT[alt_i])
	if ev.is_action_pressed("alt_down") and alt_i > 0:
		alt_i -= 1
		battle.radio("PILOT", "Descending to %s feet." % ALT_FT[alt_i])
	if ev.is_action_pressed("support") and not supports.is_empty():
		support_mode = not support_mode
		Sfx.play("click", -6.0)
	if ev.is_action_pressed("laser_toggle") and has_laser:
		laser_latch = not laser_latch
	if ev.is_action_pressed("fire") and support_mode:
		_call_support()
	if ev.is_action_pressed("map"):
		battle.hud.toggle_map()
	if ev.is_action_pressed("iff"):
		Game.settings.iff = not Game.settings.get("iff", true)
	if ev.is_action_pressed("help"):
		battle.hud.show_help = not battle.hud.show_help


func _cycle(dir: int) -> void:
	if support_mode:
		if not supports.is_empty():
			ssel = posmod(ssel + dir, supports.size())
		return
	_select(posmod(wsel + dir, weapons.size()))


func _select(k: int) -> void:
	if k == wsel:
		return
	wsel = k
	Sfx.play("click", -8.0)


func _toggle_track() -> void:
	if track_unit != null:
		track_unit = null
		Sfx.play("click", -8.0)
		return
	if not aim_valid:
		return
	var u = battle.units.nearest(aim_point, maxf(12.0, view_height_m() * 0.06))
	if u != null:
		track_unit = u
		track_off = Vector3(0, 0.8, 0)
		Sfx.play("lock", -6.0)


func release_flares() -> void:
	if flares <= 0 or flare_cd > 0.0:
		return
	flares -= 1
	flare_cd = 0.7
	var n: int = battle.ordnance.flares()
	Sfx.play("flare", -2.0)
	battle.hud.message("FLARES" if n == 0 else "FLARES - MISSILE DECOYED", 1.5)


func take_damage(amount: float, src: String) -> void:
	if battle.ended:
		return
	hp -= amount * plane_dmg
	shake = maxf(shake, 1.2 if src != "aaa" else 0.4)
	battle.hud.hit_flash(0.5 if src != "aaa" else 0.15)
	Sfx.play("hit", 0.0 if src != "aaa" else -8.0)
	if src != "aaa":
		battle.radio("PILOT", ["We're hit! Number two engine is out!", "Missile impact! Still flying, keep working!", "Taking damage, hydraulics are holding."][randi() % 3])
	if hp <= 0.0:
		hp = 0.0
		battle.mission.lose("SPECTRE WAS SHOT DOWN")


# --- Per frame ------------------------------------------------------------

func _process(dt: float) -> void:
	time += dt
	_fly(dt)
	if not battle.ended:
		_poll_input(dt)
	_update_camera(dt)
	if not battle.ended:
		_weapons(dt)
	flare_cd -= dt
	if auto_flares and flare_cd <= 0.0:
		for m in battle.ordnance.threats:
			if not m.decoy and float(m.tti) < 2.6:
				release_flares()
				break


func _poll_input(dt: float) -> void:
	var z := Input.get_axis("zoom_out", "zoom_in")
	if absf(z) > 0.05:
		mag_goal = clampf(mag_goal * exp(z * 2.2 * dt), 1.0, mag_max)
	mag = exp(lerpf(log(mag), log(mag_goal), minf(1.0, dt * 8.0)))
	lasing = has_laser and (Input.is_action_pressed("laser") or laser_latch) and aim_valid


func _update_camera(dt: float) -> void:
	var cpos := global_position + Vector3(0, -3.0, 0)
	if track_unit != null:
		if track_unit.alive:
			aim_point = track_unit.pos + track_off
			aim_valid = true
		else:
			track_unit = null
	if aim_valid:
		look_dir = (aim_point - cpos).normalized()
	var fov_rad := deg_to_rad(fov())
	var vh := get_viewport().get_visible_rect().size.y
	var sens := float(Game.settings.get("mouse_sens", 1.0))
	var d := mouse_delta * sens * fov_rad / maxf(vh, 1.0) * 0.9
	mouse_delta = Vector2.ZERO
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick.length() > 0.0:
		stick = stick * stick.length()
		d += stick * fov_rad * 1.1 * float(Game.settings.get("pad_sens", 1.0)) * dt
	if bot:
		d = _bot_aim(dt)
	if bool(Game.settings.get("invert_y", false)):
		d.y = -d.y
	var slewed := d.length_squared() > 0.0
	if slewed:
		look_dir = look_dir.rotated(Vector3.UP, -d.x)
		var right := look_dir.cross(Vector3.UP).normalized()
		var nd := look_dir.rotated(right, -d.y)
		if nd.y < 0.087 and nd.y > -0.9995:
			look_dir = nd
	_clamp_gimbal()
	var hit: Dictionary = battle.world.raycast(cpos, look_dir, 30000.0)
	if hit.is_empty():
		aim_valid = false
		aim_range = 8000.0
	else:
		aim_point = hit.pos
		aim_valid = true
		aim_bidx = hit.bidx
		aim_water = hit.water
		aim_range = cpos.distance_to(aim_point)
		if track_unit != null and slewed:
			track_off = aim_point - track_unit.pos
	# image shake from our own guns plus a little turret vibration
	shake = maxf(0.0, shake - dt * 2.5)
	var jit := Vector2(sin(time * 23.0) + sin(time * 37.0) * 0.5, cos(time * 29.0) + sin(time * 17.0) * 0.5) * fov_rad * 0.0012
	jit += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * fov_rad * 0.03 * shake
	var view := look_dir.rotated(Vector3.UP, jit.x)
	var r2 := view.cross(Vector3.UP).normalized()
	view = view.rotated(r2, jit.y)
	cam.global_position = cpos
	cam.look_at(cpos + view, Vector3.UP)
	cam.size = 2.0 * cam.near * tan(deg_to_rad(fov()) * 0.5)
	battle.world.fit_shadows(aim_range, view_height_m())


func _clamp_gimbal() -> void:
	var h := Vector3(look_dir.x, 0.0, look_dir.z)
	if h.length() < 0.05:
		return
	h = h.normalized()
	var a := left.signed_angle_to(h, Vector3.UP)
	var lim := deg_to_rad(80.0)
	if absf(a) > lim:
		var nh := left.rotated(Vector3.UP, clampf(a, -lim, lim))
		var y := look_dir.y
		var hl := sqrt(maxf(0.0, 1.0 - y * y))
		look_dir = Vector3(nh.x * hl, y, nh.z * hl)


func in_gimbal() -> bool:
	var h := Vector3(look_dir.x, 0.0, look_dir.z)
	if h.length() < 0.05:
		return true
	return absf(left.signed_angle_to(h.normalized(), Vector3.UP)) < deg_to_rad(79.0)


func _weapons(dt: float) -> void:
	for w in weapons:
		w.cd = maxf(float(w.cd) - dt, -0.1)
		if w.reload_t > 0.0:
			w.reload_t = float(w.reload_t) - dt
			if w.reload_t <= 0.0:
				if w.spare == 0:
					w.reload_t = 0.0
				else:
					w.ammo = w.def.mag
					if w.spare > 0:
						w.spare = int(w.spare) - 1
					if w.id in ["w_105", "w_40", "w_30"]:
						Sfx.play("reload", -10.0)
	var cur: Dictionary = weapons[wsel]
	var firing: bool = not support_mode and not battle.hud.map_big and (Input.is_action_pressed("fire") or (bot and bot_t > 0.0))
	var can: bool = firing and cur.reload_t <= 0.0 and int(cur.ammo) > 0 and aim_valid
	if can:
		while float(cur.cd) <= 0.0 and int(cur.ammo) > 0:
			_shoot(cur)
			cur.ammo = int(cur.ammo) - 1
			cur.cd = float(cur.cd) + 1.0 / float(cur.def.rate)
		if int(cur.ammo) <= 0:
			cur.reload_t = float(cur.def.reload)
	else:
		cur.cd = maxf(float(cur.cd), 0.0)
	var mg: bool = can and cur.id == "w_762"
	if mg != mg_on:
		mg_on = mg
		Sfx.loop("mg", mg, -3.0)


func _shoot(w: Dictionary) -> void:
	var def: Dictionary = w.def
	shots += 1
	battle.stats.shots += 1
	var origin := global_position + left * 4.0 + Vector3(0, -2.5, 0)
	if def.has("guided"):
		var target: Vector3 = aim_point
		var spot = battle.laser_point()
		if spot != null:
			target = spot
		var tot: float
		if def.guided == "missile":
			tot = origin.distance_to(target) / float(def.flight_speed)
		else:
			tot = float(def.tot)
		battle.ordnance.launch_guided(def.guided, def, origin, target, tot, def.guide, true, w.id)
		Sfx.play(def.sound, -4.0)
		battle.radio("SPECTRE", "%s away, %d seconds." % [def.short, int(tot)])
		return
	var disp: float = float(def.disp) * 0.001 * (alt / 3050.0)
	var right := look_dir.cross(Vector3.UP).normalized()
	var up := right.cross(look_dir).normalized()
	var dir := (look_dir + right * randfn(0.0, 1.0) * disp + up * randfn(0.0, 1.0) * disp).normalized()
	var cpos := global_position + Vector3(0, -3.0, 0)
	var hit: Dictionary = battle.world.raycast(cpos, dir, 30000.0)
	if hit.is_empty():
		return
	battle.ordnance.add_shell(origin, hit.pos, w.id, def, hit.bidx, hit.water)
	shake = maxf(shake, float(def.shake))
	if def.sound != "mg":
		Sfx.play(def.sound, -2.0, randf_range(0.95, 1.05))


func _call_support() -> void:
	if supports.is_empty():
		return
	var s: Dictionary = supports[ssel]
	if int(s.charges) <= 0:
		Sfx.play("click", -4.0, 0.6)
		battle.hud.message("NO CHARGES LEFT", 1.5)
		return
	if not aim_valid:
		battle.hud.message("NO SENSOR POINT", 1.5)
		return
	var def: Dictionary = s.def
	if def.kind == "illum" and battle.world.night < 0.3:
		battle.hud.message("ILLUM ONLY AT NIGHT", 1.5)
		return
	s.charges = int(s.charges) - 1
	var target := aim_point
	var tot: float = def.tot
	var count: int = def.get("count", 1)
	var dir := Vector2(randf() - 0.5, randf() - 0.5).normalized()
	for k in count:
		var t2 := target
		if count > 1:
			var off := (k - (count - 1) * 0.5) * float(def.get("spread", 15.0))
			t2 += Vector3(-dir.y, 0, dir.x) * off
			t2.y = battle.world.height(t2.x, t2.z)
		var start := t2 + Vector3(dir.x * 3000.0, 6500.0, dir.y * 3000.0)
		if def.kind == "missile":
			start = t2 + Vector3(dir.x * 3500.0, 4500.0, dir.y * 3500.0)
		battle.ordnance.launch_guided(def.kind, def, start, t2, tot + k * 0.9, def.guide, true, s.id)
	battle.radio("STRIKE", def.radio % int(tot))
	Sfx.play("lock", -4.0)
	support_mode = false


# --- Autotest bot ---------------------------------------------------------

func _bot_aim(dt: float) -> Vector2:
	bot_t -= dt
	if bot_t < -1.5:
		var best = null
		var bd := 1.0e9
		for u in battle.units.list:
			if u.alive and u.team == 1 and u.beh != "static":
				var dd: float = u.pos.distance_to(orbit_center)
				if dd < bd:
					bd = dd
					best = u
		if best != null:
			aim_point = best.pos
			aim_valid = true
			look_dir = (aim_point - global_position).normalized()
			mag_goal = 20.0
			bot_t = 2.0
			if weapons.size() > 1:
				wsel = randi() % weapons.size()
	return Vector2.ZERO
