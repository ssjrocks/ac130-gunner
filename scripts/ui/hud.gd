extends Control
## The sensor operator's display: reticle, readouts, weapon status,
## objectives, radio log, warnings, markers and the moving map.

const UiTheme := preload("res://scripts/ui/theme.gd")
const Data := preload("res://scripts/data/data.gd")

var SH := Color(0, 0, 0, 0.6)

var battle
var font: Font
var C := UiTheme.FG
var radio_log: Array = []
var msg := ""
var msg_t := 0.0
var warn_text := ""
var warn_t := 0.0
var banner_title := ""
var banner_sub := ""
var map_big := false
var show_help := false
var popups: Array = []
var hit_t := 0.0
var time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = UiTheme.mono()
	show_help = int(Game.career.get("missions_flown", 0)) < 2


func radio(who: String, text: String) -> void:
	for r in radio_log:
		if r.text == text and time - float(r.t) < 8.0:
			return
	radio_log.append({"who": who, "text": text, "t": time})
	if radio_log.size() > 7:
		radio_log.pop_front()


func message(text: String, dur: float) -> void:
	msg = text
	msg_t = dur


func warn(text: String) -> void:
	warn_text = text
	warn_t = 4.0


func banner(title: String, sub: String) -> void:
	banner_title = title
	banner_sub = sub


func hit_flash(a: float) -> void:
	hit_t = maxf(hit_t, a)
	if battle.post:
		battle.post.flash = maxf(battle.post.flash, a * 0.6)


func kill_popup(u) -> void:
	var text := "KIA"
	if u.beh == "zombie":
		text = "KILL"
	elif u.veh:
		text = "VEHICLE DESTROYED"
	popups.append({"text": text, "t": 0.0})
	if popups.size() > 5:
		popups.pop_front()


func toggle_map() -> void:
	map_big = not map_big
	if Game.autotest == "":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if map_big else Input.MOUSE_MODE_CAPTURED


func _unhandled_input(ev: InputEvent) -> void:
	if map_big and ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var r := _map_rect()
		if r.has_point(ev.position):
			var f: Vector2 = (ev.position - r.position) / r.size
			var wp := Vector3(f.x * 6000.0 - 3000.0, 0.0, f.y * 6000.0 - 3000.0)
			battle.gunship.set_orbit(wp, true)
			battle.radio("PILOT", "Copy, moving the orbit.")
			get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	time += dt
	var vs := get_viewport().get_visible_rect().size
	if size != vs:
		position = Vector2.ZERO
		size = vs
	msg_t -= dt
	warn_t -= dt
	hit_t = maxf(0.0, hit_t - dt * 1.5)
	for p in popups:
		p.t += dt
	while not popups.is_empty() and popups[0].t > 1.6:
		popups.pop_front()
	queue_redraw()


# --- Drawing helpers ----------------------------------------------------------

func _line(a: Vector2, b: Vector2, col := C, w := 2.0) -> void:
	draw_line(a, b, SH, w + 2.0)
	draw_line(a, b, col, w)


func _text(p: Vector2, s: String, size := 18, col := C, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string_outline(font, p, s, align, width, size, 5, SH)
	draw_string(font, p, s, align, width, size, col)


func _circle(c: Vector2, r: float, col := C, w := 2.0) -> void:
	draw_arc(c, r, 0.0, TAU, 48, SH, w + 2.0)
	draw_arc(c, r, 0.0, TAU, 48, col, w)


func _diamond(c: Vector2, r: float, col: Color, w := 2.0) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0), c + Vector2(0, -r)])
	draw_polyline(pts, SH, w + 2.0)
	draw_polyline(pts, col, w)


func _box(r: Rect2, col: Color, w := 1.5) -> void:
	draw_rect(r, SH, false, w + 2.0)
	draw_rect(r, col, false, w)


# --- Main draw ------------------------------------------------------------------

func _draw() -> void:
	if battle == null or not battle.built or size.x < 200.0:
		return
	var g = battle.gunship
	var sz := size
	var c := sz * 0.5
	# black-hot is mostly white: draw the symbology in dark ink instead
	C = Color(0.02, 0.16, 0.05) if Game.view_mode == 3 else UiTheme.FG
	SH = Color(1, 1, 1, 0.55) if Game.view_mode == 3 else Color(0, 0, 0, 0.6)
	_draw_markers(g, sz)
	_draw_predictions(g)
	_draw_reticle(c, g)
	_draw_frame(g, sz)
	_draw_readouts(g, sz)
	_draw_weapons(g, sz)
	_draw_objectives(sz)
	_draw_radio(sz)
	_draw_map(g, sz)
	_draw_alerts(sz)
	_draw_popups(c)
	if show_help:
		_draw_help(sz)
	if banner_title != "":
		_draw_banner(sz)
	if hit_t > 0.0:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(1.0, 0.25, 0.1, hit_t * 0.3))


func _draw_reticle(c: Vector2, g) -> void:
	var w: Dictionary = g.weapon()
	var kind: String = w.def.get("reticle", "cross")
	if g.support_mode:
		kind = "support"
	match kind:
		"cross":
			for s in [-1.0, 1.0]:
				_line(c + Vector2(s * 14, 0), c + Vector2(s * 150, 0))
				_line(c + Vector2(0, s * 14), c + Vector2(0, s * 150))
				for k in range(1, 6):
					var o: float = s * (14 + k * 27)
					_line(c + Vector2(o, -5), c + Vector2(o, 5), C, 1.5)
					_line(c + Vector2(-5, o), c + Vector2(5, o), C, 1.5)
			draw_circle(c, 2.0, C)
		"bracket":
			var r := 40.0
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					var p := c + Vector2(sx * r, sy * r)
					_line(p, p + Vector2(-sx * 16, 0))
					_line(p, p + Vector2(0, -sy * 16))
				_line(c + Vector2(sx * 64, 0), c + Vector2(sx * 180, 0))
				_line(c + Vector2(0, sx * 64), c + Vector2(0, sx * 180))
			_line(c + Vector2(-8, 0), c + Vector2(8, 0), C, 1.5)
			_line(c + Vector2(0, -8), c + Vector2(0, 8), C, 1.5)
		"circle":
			_circle(c, 32.0)
			for s in [-1.0, 1.0]:
				_line(c + Vector2(s * 32, 0), c + Vector2(s * 220, 0))
				_line(c + Vector2(0, s * 32), c + Vector2(0, s * 220))
				for k in [70.0, 110.0, 150.0, 190.0]:
					_line(c + Vector2(s * k, -7), c + Vector2(s * k, 7), C, 1.5)
					_line(c + Vector2(-7, s * k), c + Vector2(7, s * k), C, 1.5)
			draw_circle(c, 2.0, C)
		"diamond":
			_diamond(c, 30.0, C)
			_line(c + Vector2(-10, 0), c + Vector2(10, 0), C, 1.5)
			_line(c + Vector2(0, -10), c + Vector2(0, 10), C, 1.5)
			for s in [-1.0, 1.0]:
				_line(c + Vector2(s * 50, 0), c + Vector2(s * 160, 0))
				_line(c + Vector2(0, s * 50), c + Vector2(0, s * 160))
		"support":
			var r2 := 46.0
			var col := UiTheme.ACCENT
			for k in 8:
				var a0 := k * TAU / 8.0
				draw_arc(c, r2, a0, a0 + TAU / 16.0, 6, col, 2.5)
			_line(c + Vector2(-12, 0), c + Vector2(12, 0), col)
			_line(c + Vector2(0, -12), c + Vector2(0, 12), col)
			var s: Dictionary = g.supports[g.ssel]
			_text(c + Vector2(-200, 90), "%s  [FIRE] TO CALL" % s.def.short, 20, col, HORIZONTAL_ALIGNMENT_CENTER, 400)
			if s.def.get("placement", "") == "line":
				_draw_strafe_line(g, s.def)
				_text(c + Vector2(-250, 116), "WHEEL OR , . TO TURN THE RUN  (HDG %03d)" % int(rad_to_deg(g.line_ang)), 16, col, HORIZONTAL_ALIGNMENT_CENTER, 500)
			elif s.def.kind == "qrf":
				_text(c + Vector2(-250, 116), "PLATOON DRIVES HERE FROM %s" % String(battle.world.map.get("site_names", {}).get("qrf", "BASE")), 16, col, HORIZONTAL_ALIGNMENT_CENTER, 500)
			elif s.def.kind == "heli":
				_text(c + Vector2(-250, 116), "BLACK HAWK LANDS A SQUAD HERE", 16, col, HORIZONTAL_ALIGNMENT_CENTER, 500)
			elif s.def.guide == "laser":
				_text(c + Vector2(-200, 116), "LASER GUIDED: KEEP THE SPOT ON TARGET", 16, col, HORIZONTAL_ALIGNMENT_CENTER, 400)
	if g.lasing and fmod(time, 0.5) < 0.35:
		_text(c + Vector2(48, -44), "LSR", 20, UiTheme.ACCENT)
	if g.track_unit != null:
		_box(Rect2(c - Vector2(56, 56), Vector2(112, 112)), C, 1.0)
		_text(c + Vector2(48, 66), "TRK", 18)


## The ground track of a gun run or show of force, with an arrow for the
## direction of flight.
func _draw_strafe_line(g, def: Dictionary) -> void:
	var cam: Camera3D = g.cam
	var dir := Vector3(sin(g.line_ang), 0.0, -cos(g.line_ang))
	var L: float = def.len
	var pts := PackedVector2Array()
	var w = battle.world
	for k in 21:
		var p: Vector3 = g.aim_point + dir * (L * (float(k) / 20.0 - 0.5))
		p.y = w.height(p.x, p.z) + 1.0
		if cam.is_position_behind(p):
			return
		pts.append(cam.unproject_position(p))
	var col := UiTheme.ACCENT
	draw_polyline(pts, SH, 6.0)
	draw_polyline(pts, col, 3.0)
	var tip: Vector2 = pts[pts.size() - 1]
	var back: Vector2 = pts[pts.size() - 3]
	var d := (tip - back).normalized()
	var side := Vector2(-d.y, d.x) * 10.0
	draw_colored_polygon(PackedVector2Array([tip + d * 16.0, tip + side, tip - side]), col)
	_text(pts[0] + Vector2(-40, -12), "IN", 15, col)


func _draw_frame(g, sz: Vector2) -> void:
	var m := 34.0
	var L := 60.0
	for corner in [Vector2(m, m), Vector2(sz.x - m, m), Vector2(sz.x - m, sz.y - m), Vector2(m, sz.y - m)]:
		var sx := 1.0 if corner.x < sz.x * 0.5 else -1.0
		var sy := 1.0 if corner.y < sz.y * 0.5 else -1.0
		_line(corner, corner + Vector2(sx * L, 0), C, 2.0)
		_line(corner, corner + Vector2(0, sy * L), C, 2.0)
	# bearing tape
	var brg: float = g.look_bearing()
	var cx := sz.x * 0.5
	var y := 52.0
	for k in range(-30, 31):
		var deg := floorf(brg) + k
		if int(deg) % 5 != 0:
			continue
		var x := cx + (deg - brg) * 9.0
		var tall := int(deg) % 10 == 0
		_line(Vector2(x, y), Vector2(x, y + (12 if tall else 6)), C, 1.5)
		if tall:
			_text(Vector2(x - 20, y + 32), "%03d" % (int(fposmod(deg, 360.0))), 15, C, HORIZONTAL_ALIGNMENT_CENTER, 40)
	_line(Vector2(cx, y - 8), Vector2(cx, y + 16), UiTheme.ACCENT, 2.0)
	# zoom bar on the right edge
	var top := sz.y * 0.25
	var bot := sz.y * 0.75
	var bx := sz.x - 60.0
	_line(Vector2(bx, top), Vector2(bx, bot), C, 1.5)
	for mg in [1.0, 2.0, 5.0, 10.0, 25.0, 60.0, 150.0]:
		if mg > g.mag_max + 0.1:
			continue
		var f := log(mg) / log(maxf(g.mag_max, 2.0))
		var yy := lerpf(bot, top, f)
		_line(Vector2(bx - 6, yy), Vector2(bx + 6, yy), C, 1.5)
		_text(Vector2(bx - 70, yy + 6), "%dx" % int(mg), 14, UiTheme.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 56)
	var fz := log(g.mag) / log(maxf(g.mag_max, 2.0))
	var yz := lerpf(bot, top, fz)
	draw_colored_polygon(PackedVector2Array([Vector2(bx + 6, yz), Vector2(bx + 18, yz - 7), Vector2(bx + 18, yz + 7)]), UiTheme.ACCENT)


func _grid(p: Vector3) -> String:
	var e := int(p.x + 50000.0) % 100000
	var n := int(-p.z + 50000.0) % 100000
	return "38S MB %05d %05d" % [e, n]


func _draw_readouts(g, sz: Vector2) -> void:
	var x := 64.0
	var y := 96.0
	var mode_names := ["TV", "NV", "WHT", "BHT"]
	_text(Vector2(x, y), mode_names[Game.view_mode], 34, C)
	_text(Vector2(x + 110, y - 4), "%5.1fx  FOV %.2f" % [g.mag, g.fov()], 20)
	y += 34
	var alt_line := "ALT   %s FT AGL" % g.alt_text()
	if absf(g.alt - g.alt_target()) > 15.0:
		alt_line += "  > %s" % g._commas(int(round(g.alt_target() / g.FT / 100.0)) * 100)
	_text(Vector2(x, y), alt_line, 18)
	y += 24
	if g.aim_valid:
		_text(Vector2(x, y), "SLANT %s M" % _commas(int(g.aim_range)), 18)
		y += 24
		_text(Vector2(x, y), "ELEV  %d M" % int(g.aim_point.y), 18)
		y += 24
		_text(Vector2(x, y), "GRID  %s" % _grid(g.aim_point), 18)
	else:
		_text(Vector2(x, y), "SLANT ----", 18)
		y += 48
	y += 24
	_text(Vector2(x, y), "HDG %03d  BRG %03d" % [int(g.heading_deg()), int(g.look_bearing())], 18)
	y += 24
	var line := ""
	if g.has_laser:
		line += "LSR %s  " % ("ON" if g.lasing else ("ARM" if g.laser_latch else "SAFE"))
	line += "TRK %s" % (("LEAD" if g.leading() else "LOCK") if g.track_unit != null else "OFF")
	_text(Vector2(x, y), line, 18, UiTheme.ACCENT if g.lasing else C)
	y += 30
	_draw_heat(g, Vector2(x, y))
	if not g.in_gimbal():
		_text(Vector2(sz.x * 0.5 - 200, sz.y * 0.5 + 150), "GIMBAL LIMIT", 22, UiTheme.BAD, HORIZONTAL_ALIGNMENT_CENTER, 400)


static func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _draw_weapons(g, sz: Vector2) -> void:
	var x := sz.x - 430.0
	var y := sz.y * 0.2
	_text(Vector2(x, y), "WEAPONS", 16, UiTheme.DIM)
	y += 26
	for i in g.weapons.size():
		var w: Dictionary = g.weapons[i]
		var sel: bool = i == g.wsel and not g.support_mode
		var col := UiTheme.ACCENT if sel else C
		var label := "%d %s" % [i + 1, w.def.short]
		var status := ""
		if w.reload_t > 0.0:
			var f: float = 1.0 - float(w.reload_t) / float(w.def.reload)
			var bars := int(f * 10.0)
			status = "RELOAD " + "|".repeat(bars) + ".".repeat(10 - bars)
		elif int(w.ammo) == 0 and int(w.spare) == 0:
			status = "EMPTY"
		else:
			status = "%d" % w.ammo
			if int(w.spare) >= 0:
				status += " +%d" % w.spare
		_text(Vector2(x, y), ("> " if sel else "  ") + label, 20, col)
		_text(Vector2(x + 150, y), status, 18, col)
		y += 26
	if not g.supports.is_empty():
		y += 10
		_text(Vector2(x, y), "SUPPORT [G]", 16, UiTheme.ACCENT if g.support_mode else UiTheme.DIM)
		y += 26
		for i in g.supports.size():
			var s: Dictionary = g.supports[i]
			var sel2: bool = g.support_mode and i == g.ssel
			var col2 := UiTheme.ACCENT if sel2 else C
			_text(Vector2(x, y), ("> " if sel2 else "  ") + "%d %s" % [i + 1, s.def.short], 18, col2)
			_text(Vector2(x + 190, y), "x%d" % s.charges, 18, col2 if int(s.charges) > 0 else UiTheme.DIM)
			y += 24
	var pend: Array = []
	for gd in battle.ordnance.guided:
		if gd.by_player:
			pend.append(gd)
	if not pend.is_empty():
		y += 10
		for gd in pend:
			var left: float = maxf(0.0, float(gd.T) - float(gd.t))
			var wname: String = gd.def.get("short", "WEAPON")
			_text(Vector2(x, y), "%s  TOT %02d:%02d" % [wname, int(left) / 60, int(left) % 60], 18, UiTheme.ACCENT)
			y += 24
	y += 14
	_text(Vector2(x, y), "FLARES %d" % g.flares, 18, C if g.flares > 5 else UiTheme.BAD)
	y += 24
	var hpc := C if g.hp > 60 else (UiTheme.ACCENT if g.hp > 30 else UiTheme.BAD)
	_text(Vector2(x, y), "AIRFRAME %d%%" % int(g.hp), 18, hpc)


func _draw_objectives(sz: Vector2) -> void:
	var mi = battle.mission
	var x := sz.x - 640.0
	var y := 96.0
	_text(Vector2(x, y), String(battle.cfg.get("name", "SORTIE")).to_upper(), 20, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT, 580)
	y += 26
	if mi.timer_label != "":
		var tl: String = mi.timer_label
		if mi.timer_left >= 0.0:
			var tt := int(ceil(mi.timer_left))
			tl += "  %02d:%02d" % [tt / 60, tt % 60]
		_text(Vector2(x, y), tl, 18, C, HORIZONTAL_ALIGNMENT_RIGHT, 580)
		y += 24
	for o in mi.objectives:
		var mark := "[ ]"
		var col := C
		if o.state == 1:
			mark = "[X]"
			col = UiTheme.DIM
		elif o.state == 2:
			mark = "[!]"
			col = UiTheme.BAD
		_text(Vector2(x, y), "%s %s" % [o.text, mark], 17, col, HORIZONTAL_ALIGNMENT_RIGHT, 580)
		y += 22
	_text(Vector2(x, y + 6), "SCORE %d" % (battle.stats.score + mi.score_bonus), 17, UiTheme.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 580)


func _draw_radio(sz: Vector2) -> void:
	var x := 64.0
	var y := sz.y - 70.0 - radio_log.size() * 26.0
	for r in radio_log:
		var age: float = time - float(r.t)
		var a := clampf(1.6 - age / 25.0, 0.25, 1.0)
		var col := Color(C.r, C.g, C.b, a)
		var line := "%s: %s" % [r.who, r.text]
		draw_string_outline(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, 1100, 17, 5, Color(0, 0, 0, 0.6 * a))
		draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, 1100, 17, col)
		y += 26


func _map_rect() -> Rect2:
	var sz := size
	if map_big:
		var s := minf(sz.y - 160.0, 820.0)
		return Rect2(Vector2(sz.x * 0.5 - s * 0.5, sz.y * 0.5 - s * 0.5), Vector2(s, s))
	return Rect2(Vector2(sz.x - 330.0, sz.y - 330.0), Vector2(270.0, 270.0))


func _draw_map(g, sz: Vector2) -> void:
	var r := _map_rect()
	var k := r.size.x / 6000.0
	var to_map := func(p: Vector3) -> Vector2:
		return r.position + Vector2((p.x + 3000.0) * k, (p.z + 3000.0) * k)
	draw_rect(r, Color(0.0, 0.05, 0.02, 0.55 if not map_big else 0.85))
	_box(r, UiTheme.DIM, 1.0)
	var w = battle.world
	for road in w.roads:
		var pts := PackedVector2Array()
		for p in road:
			pts.append(to_map.call(Vector3(p.x, 0, p.y)))
		draw_polyline(pts, Color(0.5, 0.6, 0.45, 0.6), 1.5)
	for tw in w.towns:
		var tc: Vector2 = to_map.call(Vector3(tw.pos.x, 0, tw.pos.y))
		draw_arc(tc, float(tw.r) * k, 0, TAU, 32, Color(0.6, 0.7, 0.55, 0.6), 1.0)
		if map_big:
			_text(tc + Vector2(-60, -float(tw.r) * k - 6), String(tw.name).to_upper(), 14, UiTheme.DIM, HORIZONTAL_ALIGNMENT_CENTER, 120)
	# friendlies
	for u in battle.units.list:
		if u.alive and u.team == 0:
			draw_rect(Rect2(to_map.call(u.pos) - Vector2(1.5, 1.5), Vector2(3, 3)), UiTheme.FRIEND)
	for m in battle.mission.markers + battle.support.markers:
		var mp: Vector2 = to_map.call(m.pos)
		var col := _marker_col(m.kind)
		if m.kind == "intel":
			draw_arc(mp, float(m.get("r", 150.0)) * k, 0, TAU, 24, col, 1.5)
		else:
			_diamond(mp, 5.0, col, 1.5)
		if map_big:
			_text(mp + Vector2(8, -6), m.text, 14, col)
	# orbit, aircraft and sensor footprint
	var oc: Vector2 = to_map.call(g.orbit_center)
	draw_arc(oc, g.radius * k, 0, TAU, 48, Color(C.r, C.g, C.b, 0.35), 1.0)
	var pp: Vector2 = to_map.call(g.global_position)
	var f2 := Vector2(g.forward.x, g.forward.z)
	var s2 := Vector2(-f2.y, f2.x)
	draw_colored_polygon(PackedVector2Array([pp + f2 * 9.0, pp - f2 * 6.0 + s2 * 6.0, pp - f2 * 6.0 - s2 * 6.0]), C)
	if g.aim_valid:
		var foot := PackedVector2Array()
		var cam: Camera3D = g.cam
		for corner in [Vector2.ZERO, Vector2(sz.x, 0), sz, Vector2(0, sz.y), Vector2.ZERO]:
			var o := cam.project_ray_origin(corner)
			var d := cam.project_ray_normal(corner)
			var tt := 9000.0
			if d.y < -0.01:
				tt = minf((g.aim_point.y - o.y) / d.y, 9000.0)
			foot.append(to_map.call(o + d * tt))
		draw_polyline(foot, UiTheme.ACCENT, 1.0)
		draw_circle(to_map.call(g.aim_point), 2.5, UiTheme.ACCENT)
	if map_big:
		_text(r.position + Vector2(0, r.size.y + 26), "CLICK TO MOVE THE ORBIT     TAB TO CLOSE", 16, UiTheme.DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	_text(r.position + Vector2(4, -6), "N", 14, UiTheme.DIM)


func _marker_col(kind: String) -> Color:
	match kind:
		"friend":
			return UiTheme.FRIEND
		"enemy":
			return UiTheme.BAD
		"intel":
			return Color(1.0, 0.6, 0.3)
	return UiTheme.ACCENT


func _draw_markers(g, sz: Vector2) -> void:
	var cam: Camera3D = g.cam
	var c := sz * 0.5
	for m in battle.mission.markers + battle.support.markers:
		var p: Vector3 = m.pos + Vector3(0, 4, 0)
		var col := _marker_col(m.kind)
		var dist := Vector2(p.x - g.aim_point.x, p.z - g.aim_point.z).length()
		var label := "%s %s" % [m.text, ("%dM" % int(dist)) if dist < 9500 else ""]
		if cam.is_position_behind(p):
			continue
		var sp := cam.unproject_position(p)
		var inside := Rect2(Vector2(40, 40), sz - Vector2(80, 80)).has_point(sp)
		if inside:
			if m.kind == "intel":
				var rpx: float = float(m.get("r", 150.0)) / maxf(battle.effects.mpp(p), 0.001)
				if rpx < sz.y:
					draw_arc(sp, rpx, 0, TAU, 32, Color(col.r, col.g, col.b, 0.6), 1.5)
			_diamond(sp, 9.0, col)
			_text(sp + Vector2(14, -10), label, 15, col)
		else:
			var dir := (sp - c).normalized()
			var e := Vector2(clampf(c.x + dir.x * 10000.0, 70.0, sz.x - 70.0), clampf(c.y + dir.y * 10000.0, 70.0, sz.y - 70.0))
			var tip := e
			var bse := e - dir * 16.0
			var side := Vector2(-dir.y, dir.x) * 8.0
			draw_colored_polygon(PackedVector2Array([tip, bse + side, bse - side]), col)
			_text(bse - dir * 20.0 + Vector2(-60, 4), m.text, 13, col, HORIZONTAL_ALIGNMENT_CENTER, 120)
	# friendly IFF chevrons
	if bool(Game.settings.get("iff", true)):
		var n := 0
		for u in battle.units.list:
			if not u.alive or u.team != 0 or n > 150:
				continue
			var hp: Vector3 = u.pos + Vector3(0, 2.5 if not u.veh else 4.0, 0)
			if cam.is_position_behind(hp):
				continue
			var s := cam.unproject_position(hp)
			if s.x < 0 or s.y < 0 or s.x > sz.x or s.y > sz.y:
				continue
			n += 1
			var sc := 5.0
			draw_polyline(PackedVector2Array([s + Vector2(-sc, -sc - 6), s + Vector2(0, -6), s + Vector2(sc, -sc - 6)]), UiTheme.FRIEND, 2.0)
	# SF laser spot and our strikes
	var spot_unit = battle.sf_laser.get("to")
	if spot_unit != null and spot_unit.alive:
		var lp: Vector3 = spot_unit.pos + Vector3(0, 1, 0)
		if not cam.is_position_behind(lp):
			var ls := cam.unproject_position(lp)
			if fmod(time, 0.6) < 0.4:
				_diamond(ls, 14.0, UiTheme.BAD)
			_text(ls + Vector2(18, 20), "SF LSR 1688", 14, UiTheme.BAD)
	for gd in battle.ordnance.guided:
		if not gd.by_player:
			continue
		var tp: Vector3 = gd.target
		if cam.is_position_behind(tp):
			continue
		var ts := cam.unproject_position(tp)
		_line(ts + Vector2(-10, -10), ts + Vector2(10, 10), UiTheme.ACCENT, 1.5)
		_line(ts + Vector2(-10, 10), ts + Vector2(10, -10), UiTheme.ACCENT, 1.5)
		var left: float = maxf(0.0, float(gd.T) - float(gd.t))
		_text(ts + Vector2(14, -8), "%s %ds" % [gd.def.get("short", ""), int(left)], 14, UiTheme.ACCENT)


## Heat bar for the prediction computer, under the readouts.
func _draw_heat(g, p: Vector2) -> void:
	if not g.predict_on and g.pred_heat <= 0.0 and g.pred_shutdown <= 0.0:
		return
	var status := "OFF"
	var col := C
	if g.pred_shutdown > 0.0:
		status = "OVERHEAT %02d s" % int(ceil(g.pred_shutdown))
		col = UiTheme.BAD
	elif g.predict_on:
		status = "PREDICTING" if not g.predictions.is_empty() else "STANDBY"
		if g.pred_heat > 75.0:
			col = UiTheme.ACCENT
	_text(p, "PRED %s" % status, 16, col)
	var bar := Rect2(p + Vector2(0, 8), Vector2(220, 9))
	draw_rect(bar, Color(0, 0, 0, 0.5))
	var f := clampf(g.pred_heat / 100.0, 0.0, 1.0)
	var fill := C if f < 0.75 else (UiTheme.ACCENT if f < 1.0 else UiTheme.BAD)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), fill)
	_box(bar, col, 1.0)
	_text(p + Vector2(230, 17), "%d%%" % int(g.pred_heat), 14, col)


func _draw_predictions(g) -> void:
	var cam: Camera3D = g.cam
	for pr in g.predictions:
		var a: Vector3 = pr.from + Vector3(0, 1, 0)
		var b: Vector3 = pr.to + Vector3(0, 1, 0)
		if cam.is_position_behind(a) or cam.is_position_behind(b):
			continue
		var sa := cam.unproject_position(a)
		var sb := cam.unproject_position(b)
		var col := Color(1.0, 0.55, 0.15)
		if sa.distance_to(sb) > 6.0:
			draw_dashed_line(sa, sb, Color(col.r, col.g, col.b, 0.9), 2.0, 6.0)
		_line(sb + Vector2(-7, 0), sb + Vector2(7, 0), col, 1.5)
		_line(sb + Vector2(0, -7), sb + Vector2(0, 7), col, 1.5)
		draw_arc(sb, 10.0, 0.0, TAU, 16, col, 1.5)
		_text(sb + Vector2(13, -8), "T+%.1f" % float(pr.t), 13, col)


func _draw_alerts(sz: Vector2) -> void:
	if warn_t > 0.0 and fmod(time, 0.5) < 0.32:
		_text(Vector2(0, sz.y * 0.5 - 200), warn_text, 34, UiTheme.BAD, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
	for m in battle.ordnance.threats:
		if not m.decoy:
			_text(Vector2(0, sz.y * 0.5 - 160), "INCOMING  %.1fs   [F] FLARES" % float(m.tti), 24, UiTheme.BAD, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
			break
	if msg_t > 0.0:
		_text(Vector2(0, sz.y * 0.5 + 200), msg, 24, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
	var w: Dictionary = battle.gunship.weapon()
	if float(w.reload_t) > 0.0 and not battle.gunship.support_mode:
		_text(Vector2(0, sz.y * 0.5 + 250), "RELOADING %s" % w.def.short, 18, C, HORIZONTAL_ALIGNMENT_CENTER, sz.x)


func _draw_popups(c: Vector2) -> void:
	var y := c.y + 70.0
	for p in popups:
		var a := clampf(1.6 - float(p.t), 0.0, 1.0)
		_text(Vector2(c.x + 60, y), p.text, 16, Color(C.r, C.g, C.b, a))
		y += 20


func _draw_help(sz: Vector2) -> void:
	var lines := [
		"CONTROLS                         (H to hide)",
		"Mouse / right stick ....... slew sensor",
		"Wheel, W/S / left stick ... zoom    Z: wide/narrow",
		"Left mouse / RT ........... fire",
		"Right mouse / LT .......... laser   L: laser latch",
		"Q E / bumpers, 1-6 ........ select weapon",
		"V / Y ..................... sensor mode (TV NV WHT BHT)",
		"G / X ..................... support calls (fire to call)",
		"Wheel, , . / left stick X . turn a strafe line (A-10, show of force)",
		"F / B ..................... flares",
		"C / A ..................... track target",
		"O / R3 .................... move orbit to sensor point",
		"PgUp PgDn / D-pad ......... change altitude",
		"Tab / Back ................ map (click to move orbit)",
		"I ......................... friendly markers on/off",
		"P / D-pad left ............ target prediction (heats up)",
		"Esc / Start ............... pause",
	]
	var w := 540.0
	var h := lines.size() * 21.0 + 24.0
	var r := Rect2(Vector2(54.0, 300.0), Vector2(w, h))
	draw_rect(r, Color(0, 0.04, 0.02, 0.6))
	_box(r, UiTheme.DIM)
	var y := r.position.y + 26.0
	for l in lines:
		_text(Vector2(r.position.x + 16, y), l, 15, C)
		y += 21


func _draw_banner(sz: Vector2) -> void:
	var r := Rect2(Vector2(0, sz.y * 0.5 - 90), Vector2(sz.x, 150))
	draw_rect(r, Color(0, 0, 0, 0.6))
	var col := UiTheme.FG if battle.mission.state == "won" else (UiTheme.ACCENT if battle.mission.state == "ended" else UiTheme.BAD)
	_text(Vector2(0, sz.y * 0.5 - 20), banner_title, 54, col, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
	_text(Vector2(0, sz.y * 0.5 + 30), banner_sub, 24, C, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
