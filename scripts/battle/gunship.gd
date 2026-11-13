extends Node3D
## The AC-130: orbit flight, the stabilised sensor turret (the camera),
## guns, laser designator, support calls and countermeasures.

const Data := preload("res://scripts/data/data.gd")
const FOV_WIDE := 55.0
const FT := 0.3048
const ALT_MIN_FT := 2000
const ALT_MAX_FT := 20000
const TERRAIN_CLEARANCE := 200.0

var battle
var cam: Camera3D
var orbit_center := Vector3.ZERO
var orbit_goal := Vector3.ZERO
var manual_orbit := false
var radius := 2700.0
var alt_ft := 10000          # commanded altitude above the orbit centre
var alt_floor := 0.0         # lowest safe height over the terrain on the orbit
var alt_floor_t := 0.0
var alt_msg_t := -1.0
var fire_lock := false       # a click used for a support call never fires the gun
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
var line_ang := 0.0          # compass heading of a strafe-line call (A-10, show of force)
var lasing := false
var laser_latch := false
var has_laser := false
var track_unit = null
var track_off := Vector3.ZERO
var track_vel := Vector3.ZERO
var track_last := Vector3.ZERO
var hp := 100.0
var flares := 30
var flare_cd := 0.0
# Recoil and hit jolts, as a fraction of the field of view; eases back to 0.
var kick := Vector2.ZERO
var mouse_delta := Vector2.ZERO
var shots := 0
var auto_flares := false
var plane_dmg := 1.0
var bot := false
var bot_t := 0.0
var time := 0.0
var mg_on := false
# Supercomputer target prediction: off at the start of every sortie. Heat
# builds while it predicts (100% after 30 s) and bleeds off at a third of
# that rate, so it runs 30 s in every 2 min; at 100% it shuts down for 60 s.
const PRED_HEAT_RATE := 100.0 / 30.0
const PRED_COOL_RATE := 100.0 / 90.0
const PRED_SHUTDOWN := 60.0
var predict_on := false
var pred_heat := 0.0
var pred_shutdown := 0.0
var predictions: Array = []


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
	alt_floor_t -= dt
	if alt_floor_t <= 0.0:
		alt_floor_t = 1.0
		alt_floor = _terrain_floor()
	alt = move_toward(alt, alt_target(), 25.0 * dt)
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
	if ev is InputEventMouseButton and ev.pressed and line_placement():
		# while placing a strafe line the wheel turns it instead of zooming
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			line_ang = fposmod(line_ang + deg_to_rad(10.0), TAU)
			return
		if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			line_ang = fposmod(line_ang - deg_to_rad(10.0), TAU)
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
	if ev.is_action_pressed("alt_up", true) and alt_ft < ALT_MAX_FT:
		alt_ft = mini(alt_ft + 1000, ALT_MAX_FT)
		alt_msg_t = 1.0
	if ev.is_action_pressed("alt_down", true) and alt_ft > ALT_MIN_FT:
		alt_ft = maxi(alt_ft - 1000, ALT_MIN_FT)
		alt_msg_t = 1.0
	if ev.is_action_pressed("support") and not supports.is_empty():
		support_mode = not support_mode
		if support_mode:
			line_ang = deg_to_rad(look_bearing())
		Sfx.play("click", -6.0)
	if ev.is_action_pressed("laser_toggle") and has_laser:
		laser_latch = not laser_latch
	if ev.is_action_pressed("fire") and support_mode:
		fire_lock = true
		_call_support()
	if ev.is_action_pressed("map"):
		battle.hud.toggle_map()
	if ev.is_action_pressed("predictor"):
		predict_on = not predict_on
		Sfx.play("click", -6.0)
	if ev.is_action_pressed("iff"):
		Game.settings.iff = not Game.settings.get("iff", true)
	if ev.is_action_pressed("help"):
		battle.hud.show_help = not battle.hud.show_help


## Height the aircraft actually flies at: the commanded altitude, raised if
## the terrain under the orbit needs it.
func alt_target() -> float:
	return maxf(alt_ft * FT, alt_floor)


func alt_text() -> String:
	return _commas(int(round(alt / FT / 100.0)) * 100)


static func _commas(n: int) -> String:
	var s := str(n)
	return s.substr(0, s.length() - 3) + "," + s.substr(s.length() - 3) if s.length() > 3 else s


## Highest ground on the orbit circle, as height above the orbit centre
## plus clearance.
func _terrain_floor() -> float:
	var w = battle.world
	var gy: float = w.height(orbit_center.x, orbit_center.z)
	var top := gy
	for k in 36:
		var a := TAU * k / 36.0
		for r in [radius * 0.85, radius, radius * 1.15]:
			top = maxf(top, w.height(orbit_center.x + cos(a) * r, orbit_center.z + sin(a) * r))
	return top - gy + TERRAIN_CLEARANCE


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
		track_vel = Vector3.ZERO
		track_last = u.pos
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
	kick += Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * (0.02 if src != "aaa" else 0.006)
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
	_altitude_radio(dt)
	_predict(dt)
	flare_cd -= dt
	if auto_flares and flare_cd <= 0.0:
		for m in battle.ordnance.threats:
			if not m.decoy and float(m.tti) < 2.6:
				release_flares()
				break


func support_def() -> Dictionary:
	if supports.is_empty():
		return {}
	return supports[ssel].def


func line_placement() -> bool:
	return support_mode and support_def().get("placement", "") == "line"


func _poll_input(dt: float) -> void:
	if line_placement():
		var rot := Input.get_axis("rotate_left", "rotate_right")
		if absf(rot) > 0.1:
			line_ang = fposmod(line_ang + rot * 1.6 * dt, TAU)
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
			if dt > 0.0:
				var v: Vector3 = (track_unit.pos - track_last) / dt
				track_vel = track_vel.lerp(Vector3(v.x, 0.0, v.z), minf(1.0, dt * 4.0))
			track_last = track_unit.pos
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
	# The turret is gyro-stabilised: the only image motion is a recoil or
	# hit jolt that eases back smoothly.
	kick = kick.lerp(Vector2.ZERO, minf(1.0, dt * 8.0))
	var jit := kick * fov_rad
	var view := look_dir.rotated(Vector3.UP, jit.x)
	var r2 := view.cross(Vector3.UP).normalized()
	view = view.rotated(r2, jit.y)
	# Build the rotation straight from the direction: look_at() at a point
	# 1 m ahead of a camera kilometres from the origin loses ~0.4 mrad to
	# float rounding, which is tens of pixels of shake at high zoom.
	cam.global_transform = Transform3D(Basis.looking_at(view, Vector3.UP), cpos)
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


## Seconds until something fired now with the selected weapon (or support
## call) lands at p.
func impact_time(p: Vector3) -> float:
	var origin := global_position + left * 4.0 + Vector3(0, -2.5, 0)
	if support_mode and not supports.is_empty():
		return float(supports[ssel].def.tot)
	var def: Dictionary = weapon().def
	if def.has("guided"):
		if def.guided == "missile":
			return origin.distance_to(p) / float(def.flight_speed)
		return float(def.tot)
	return origin.distance_to(p) / float(def.speed)


func _predict(dt: float) -> void:
	predictions.clear()
	if pred_shutdown > 0.0:
		pred_shutdown -= dt
		pred_heat = 100.0 * maxf(pred_shutdown, 0.0) / PRED_SHUTDOWN
		return
	var working := false
	if predict_on and aim_valid and not battle.ended:
		var r := maxf(40.0, view_height_m() * 0.6)
		var near: Array = []
		for u in battle.units.query(aim_point, r):
			# everyone, not just enemies: the computer predicts motion, it
			# doesn't tell friend from foe or find hidden targets
			if u.alive and u.beh != "static" and u.beh != "heli" and Vector2(u.pos.x - aim_point.x, u.pos.z - aim_point.z).length() < r:
				near.append(u)
		near.sort_custom(func(a, b): return a.pos.distance_squared_to(aim_point) < b.pos.distance_squared_to(aim_point))
		for i in mini(near.size(), 12):
			var u = near[i]
			var tof := impact_time(u.pos)
			predictions.append({"from": u.pos, "to": battle.units.predict(u, tof), "t": tof})
		working = not predictions.is_empty()
	if working:
		pred_heat += PRED_HEAT_RATE * dt
		if pred_heat >= 100.0:
			pred_heat = 100.0
			pred_shutdown = PRED_SHUTDOWN
			predictions.clear()
			battle.radio("SPECTRE", "Fire control computer overheated, prediction offline for one minute.")
	else:
		pred_heat = maxf(0.0, pred_heat - PRED_COOL_RATE * dt)


## True while point track is computing a lead on a moving target.
func leading() -> bool:
	return track_unit != null and track_vel.length() > 0.4


func in_gimbal() -> bool:
	var h := Vector3(look_dir.x, 0.0, look_dir.z)
	if h.length() < 0.05:
		return true
	return absf(left.signed_angle_to(h.normalized(), Vector3.UP)) < deg_to_rad(79.0)


func _altitude_radio(dt: float) -> void:
	if alt_msg_t < 0.0:
		return
	alt_msg_t -= dt
	if alt_msg_t < 0.0:
		var want := alt_ft * FT
		if want < alt_floor - 1.0:
			battle.radio("PILOT", "Terrain! Can't go below %s feet here." % _commas(int(round(alt_floor / FT / 100.0)) * 100))
		else:
			battle.radio("PILOT", "%s to %s feet." % ["Climbing" if want > alt else "Descending", _commas(alt_ft)])


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
	if fire_lock and not Input.is_action_pressed("fire"):
		fire_lock = false
	var firing: bool = not support_mode and not fire_lock and not battle.hud.map_big and (Input.is_action_pressed("fire") or (bot and bot_t > 0.0))
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
	var cpos := global_position + Vector3(0, -3.0, 0)
	var aim_dir := look_dir
	if leading():
		# Fire control leads a tracked target by the round's time of flight.
		var tof := origin.distance_to(aim_point) / float(def.speed)
		var lead := aim_point + track_vel * tof
		lead.y = battle.world.height(lead.x, lead.z) + track_off.y
		aim_dir = (lead - cpos).normalized()
	var right := aim_dir.cross(Vector3.UP).normalized()
	var up := right.cross(aim_dir).normalized()
	var dir := (aim_dir + right * randfn(0.0, 1.0) * disp + up * randfn(0.0, 1.0) * disp).normalized()
	var hit: Dictionary = battle.world.raycast(cpos, dir, 30000.0)
	if hit.is_empty():
		return
	battle.ordnance.add_shell(origin, hit.pos, w.id, def, hit.bidx, hit.water)
	if float(def.shake) > 0.0:
		kick += Vector2(randf_range(-0.3, 0.3), -1.0).normalized() * float(def.shake) * 0.015
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
	match def.kind:
		"gunrun", "sof", "qrf", "heli":
			if def.kind == "qrf" and not battle.world.map.get("sites", {}).has("qrf"):
				battle.hud.message("NO QRF BASE ON THIS MAP", 1.5)
				return
			s.charges = int(s.charges) - 1
			match def.kind:
				"gunrun":
					battle.support.gun_run(aim_point, line_ang, def)
				"sof":
					battle.support.show_of_force(aim_point, line_ang, def)
				"qrf":
					battle.support.send_qrf(aim_point)
				"heli":
					battle.support.insert_squad(aim_point)
			if def.radio != "":
				battle.radio("STRIKE", def.radio % int(def.tot))
			Sfx.play("lock", -4.0)
			support_mode = false
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
# Plays like a competent gunner, for balance testing: engages the enemies
# closest to friendly troops, locks on so fire control leads them, picks a
# gun that won't hit friendlies, and drops a JDAM on big clusters.

var bot_think := 0.0


func _bot_aim(dt: float) -> Vector2:
	bot_t -= dt
	bot_think -= dt
	if bot_think <= 0.0:
		bot_think = 1.5
		_bot_pick()
	return Vector2.ZERO


func _weapon_index(id: String) -> int:
	for i in weapons.size():
		if weapons[i].id == id and (int(weapons[i].ammo) > 0 or float(weapons[i].reload_t) < 1.0):
			return i
	return -1


func _bot_pick() -> void:
	var friends: Array = []
	var enemies: Array = []
	for u in battle.units.list:
		if not u.alive:
			continue
		if u.team == 0 and u.kind != "wreck" and u.beh != "heli":
			friends.append(u.pos)
		elif u.team == 1 and u.beh != "static":
			enemies.append(u)
	var best = null
	var best_score := 1.0e18
	var best_friend := 1.0e9
	for u in enemies:
		var nf := 1.0e9
		for f in friends:
			nf = minf(nf, u.pos.distance_squared_to(f))
		nf = sqrt(nf)
		if friends.is_empty():
			nf = u.pos.distance_to(orbit_center)
		if nf < 10.0:
			continue
		var score := nf
		if u.d.has("aa"):
			score *= 0.5
		if u.veh:
			score *= 0.8
		if score < best_score:
			best_score = score
			best = u
			best_friend = nf
	if best == null:
		bot_t = 0.0
		return
	# Locking on makes fire control lead the target; near friendlies a
	# charging enemy gets led right onto them, so aim straight at it there.
	track_unit = best if best_friend > 40.0 else null
	track_off = Vector3(0, 0.8, 0)
	track_vel = Vector3.ZERO
	track_last = best.pos
	aim_point = best.pos
	aim_valid = true
	mag_goal = 20.0
	var cluster := 0
	for u in enemies:
		if u.pos.distance_to(best.pos) < 15.0:
			cluster += 1
	var pick := -1
	# big guns need more room near survivors packed behind walls
	var room := 1.6 if battle.mission.type in ["zombie", "laststand"] else 1.0
	if best_friend < 22.0 * room:
		pick = _weapon_index("w_762")
	elif best.veh and int(best.d.get("armor", 0)) >= 2:
		pick = _weapon_index("w_105")
		if pick < 0:
			pick = _weapon_index("w_40")
	elif cluster >= 3 and best_friend > 45.0 * room:
		pick = _weapon_index("w_105")
	if pick < 0 and best_friend > 25.0 * room:
		pick = _weapon_index("w_40")
	if pick < 0:
		pick = _weapon_index("w_30")
	if pick < 0:
		pick = _weapon_index("w_762")
	if pick >= 0:
		wsel = pick
	bot_t = 1.5
	if cluster >= 6 and best_friend > 130.0:
		for i in supports.size():
			if supports[i].id == "s_jdam" and int(supports[i].charges) > 0:
				ssel = i
				_call_support()
				break
