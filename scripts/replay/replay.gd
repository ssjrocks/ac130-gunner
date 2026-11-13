extends Node3D
## Plays back a recorded sortie (see scripts/battle/recorder.gd) with a free
## camera: the world is rebuilt from the same map, units and aircraft follow
## their recorded tracks and the effects are replayed as they happened.
## Cameras: free flight, the gunship's sensor, or chasing the gunship.

const World := preload("res://scripts/world/world.gd")
const Effects := preload("res://scripts/battle/effects.gd")
const Units := preload("res://scripts/battle/units.gd")
const Recorder := preload("res://scripts/battle/recorder.gd")
const Meshes := preload("res://scripts/world/meshes.gd")
const Mats := preload("res://scripts/world/mats.gd")
const Post := preload("res://scripts/ui/post.gd")
const Maps := preload("res://scripts/data/maps.gd")
const UiTheme := preload("res://scripts/ui/theme.gd")

const FOV_WIDE := 55.0
const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0]
const CAM_NAMES := ["FREE CAMERA", "GUNSHIP SENSOR", "CHASE GUNSHIP"]
const MODE_NAMES := ["TV", "NV", "WHT", "BHT"]

var path := ""
var data := {}
var cfg := {}
var world
var effects
var post
var gunship = self          # effects ask battle.gunship.fov(); the replay answers
var built := false
var length := 0.0
var rt := 0.0               # replay time
var speed_i := 2
var paused := false
var cam: Camera3D
var cam_mode := 0
var view_mode := 0
var cam_yaw := 0.0
var cam_pitch := -0.5
var cam_speed := 60.0
var look_mouse := Vector2.ZERO
var last_us := 0
var show_hud := true
var show_line := true
var sensor_fov := FOV_WIDE

var units := {}             # id -> {node, kind, team, veh, track, k, heat, rotors}
var ev: PackedFloat32Array
var ev_i := 0
var fx_names: Array = []
var misc: Array = []
var misc_i := 0
var frame_t := PackedFloat32Array()
var frame_off := PackedInt32Array()
var frames: PackedFloat32Array
var objects := {}           # rid -> {node, glow, light, type, trail}
var ship: MeshInstance3D
var ship_pos := Vector3.ZERO
var ship_fwd := Vector3.FORWARD
var aim := Vector3.ZERO
var aim_line: MeshInstance3D
var flights: Array = []     # rockets and tank rounds in the air: {a, b, t0, T, tank}
var saved_bld := {}         # building index -> state before it collapsed
var hud: Control
var info: Label
var help: Label
var radio_lbl: Label
var radio_t := 0.0
var bar: Control
var loading: CanvasLayer


func _init(p := "") -> void:
	path = p


func _ready() -> void:
	loading = CanvasLayer.new()
	loading.layer = 10
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.015, 0.01)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading.add_child(bg)
	var lbl := _label(loading, "LOADING REPLAY...", 28)
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(loading)
	await get_tree().process_frame
	await get_tree().process_frame
	data = Recorder.load_file(path)
	if data.is_empty():
		Game.goto_menu("replays")
		return
	_build()


func _build() -> void:
	cfg = data.cfg
	length = float(data.length)
	ev = data.events
	fx_names = data.fx
	misc = data.misc
	frames = data.frames
	var i := 0
	while i < frames.size():
		frame_t.append(frames[i])
		frame_off.append(i)
		i += 11 + int(frames[i + 1]) * 7
	world = World.new()
	world.battle = self
	add_child(world)
	world.build(Maps.get_map(cfg.get("map", "kharim")), cfg.get("time", "day"), cfg.get("weather", "clear"))
	effects = Effects.new()
	effects.battle = self
	add_child(effects)
	cam = Camera3D.new()
	cam.near = 0.5
	cam.far = 60000.0
	cam.fov = 70.0
	add_child(cam)
	cam.make_current()
	for id in data.units:
		_make_unit(int(id), data.units[id])
	ship = MeshInstance3D.new()
	ship.mesh = Meshes.get_mesh("gunship")
	ship.material_override = Meshes.get_material("gunship", Mats.solid())
	ship.set_instance_shader_parameter("heat", 0.75)
	add_child(ship)
	aim_line = effects.take("beam")
	aim_line.set_instance_shader_parameter("fx_color", Color(0.4, 2.0, 0.6))
	aim_line.set_instance_shader_parameter("fx_alpha", 0.25)
	aim_line.set_instance_shader_parameter("fx_heat", 1.0)
	post = Post.new()
	add_child(post)
	_build_hud()
	# night sorties open in night vision, as the gunner would see them
	_set_view_mode(1 if world.night > 0.5 else 0)
	_sample_ship(0.0)
	# start above and behind where the gunner was looking
	var p := aim + Vector3(-250, 220, 250)
	cam.global_position = p
	_look_at(aim)
	_seek(0.0)
	loading.queue_free()
	built = true
	last_us = Time.get_ticks_usec()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func fov() -> float:
	return sensor_fov if cam_mode == 1 else cam.fov


## Battle code asks this when deciding whether to draw small effects.
func near_view(p: Vector3) -> bool:
	return cam.global_position.distance_to(p) < 4000.0


# --- Units ------------------------------------------------------------------

func _make_unit(id: int, u: Dictionary) -> void:
	var kind: String = u.kind
	var d: Dictionary = Units.KINDS.get(kind, {})
	var veh: bool = d.get("veh", false)
	var mi := MeshInstance3D.new()
	var mesh_id: String = u.mesh
	mi.mesh = Meshes.get_mesh(mesh_id)
	mi.material_override = Meshes.get_material(mesh_id, Mats.solid() if veh else Mats.unit())
	mi.layers = 2
	var heat: float = d.get("heat", 0.85)
	mi.set_instance_shader_parameter("heat", heat)
	mi.scale = Vector3.ONE * float(u.get("scale", 1.0))
	mi.visible = false
	add_child(mi)
	var rot = null
	if not veh and Meshes.is_model(mesh_id):
		Units.arm(mi, mesh_id, kind)
	if kind == "heli":
		rot = Units.rotors(mi, mesh_id)
	units[id] = {"node": mi, "kind": kind, "team": int(u.team), "veh": veh, "track": u.track, "k": 0, "heat": heat,
		"rotors": rot, "dead": false, "phase": randf() * TAU, "striding": false}


## Index of the last key at or before time t (keys are 7 floats, time first).
func _key_at(tr: PackedFloat32Array, t: float, from: int) -> int:
	var n := tr.size() / 7
	var k := clampi(from, 0, n - 1)
	if tr[k * 7] > t:
		k = 0
	while k + 1 < n and tr[(k + 1) * 7] <= t:
		k += 1
	return k


func _update_units(dt: float) -> void:
	for id in units:
		var u: Dictionary = units[id]
		var tr: PackedFloat32Array = u.track
		var mi: MeshInstance3D = u.node
		if tr.is_empty() or rt < tr[0]:
			mi.visible = false
			continue
		var k := _key_at(tr, rt, u.k)
		u.k = k
		var o := k * 7
		var fl := int(tr[o + 6])
		var p := Vector3(tr[o + 1], tr[o + 2], tr[o + 3])
		var hd: float = tr[o + 4]
		var pitch: float = tr[o + 5]
		if o + 7 < tr.size() and fl & 1:
			var t0: float = tr[o]
			var t1: float = tr[o + 7]
			var f := clampf((rt - t0) / maxf(t1 - t0, 0.001), 0.0, 1.0)
			p = p.lerp(Vector3(tr[o + 8], tr[o + 9], tr[o + 10]), f)
			hd = lerp_angle(hd, tr[o + 11], f)
			pitch = lerpf(pitch, tr[o + 12], f)
		mi.visible = bool(fl & 2)
		var alive := bool(fl & 1)
		var b := Basis(Vector3.UP, hd)
		if not alive:
			if not u.dead:
				u.dead = true
				mi.set_instance_shader_parameter("tint", Color(0.2, 0.19, 0.18) if u.veh else Color(0.6, 0.6, 0.6))
				if u.veh:
					mi.set_instance_shader_parameter("heat", 1.0)
				mi.set_instance_shader_parameter("stride", 0.0)
			if not u.veh:
				b = b * Basis(Vector3.RIGHT, -PI * 0.5)
				p.y += 0.15
			else:
				b = b * Basis(Vector3.RIGHT, pitch)
		else:
			if u.dead:
				u.dead = false
				mi.set_instance_shader_parameter("tint", Color.WHITE)
				mi.set_instance_shader_parameter("heat", u.heat)
			if u.veh:
				b = b * Basis(Vector3.RIGHT, pitch)
				if u.kind == "heli":
					b = Basis(Vector3.UP, hd)
			var moving := bool(fl & 4)
			if not u.veh and moving:
				var ph: float = rt * 9.0 + u.phase
				p.y += absf(sin(ph)) * 0.04
				mi.set_instance_shader_parameter("walk", ph)
			if not u.veh and moving != u.striding:
				u.striding = moving
				mi.set_instance_shader_parameter("stride", 0.55 if moving else 0.0)
			if u.rotors and dt > 0.0:
				for r in u.rotors.get_children():
					var spin: Vector3 = r.get_meta("spin")
					r.rotate_object_local(spin.normalized(), dt * 30.0 * spin.length())
		mi.transform = Transform3D(b.scaled(mi.scale), p)


# --- Gunship and objects ----------------------------------------------------

func _frame_at(t: float) -> int:
	var lo := 0
	var hi := frame_t.size() - 1
	if hi < 0:
		return -1
	if t <= frame_t[0]:
		return 0
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if frame_t[mid] <= t:
			lo = mid
		else:
			hi = mid - 1
	return lo


func _sample_ship(t: float) -> void:
	var i := _frame_at(t)
	if i < 0:
		return
	var o := frame_off[i]
	var j := mini(i + 1, frame_t.size() - 1)
	var o2 := frame_off[j]
	var f := 0.0 if j == i else clampf((t - frame_t[i]) / maxf(frame_t[j] - frame_t[i], 0.001), 0.0, 1.0)
	var a := Vector3(frames[o + 2], frames[o + 3], frames[o + 4])
	var b := Vector3(frames[o2 + 2], frames[o2 + 3], frames[o2 + 4])
	ship_pos = a.lerp(b, f)
	ship_fwd = Vector3(frames[o + 5], 0, frames[o + 6]).lerp(Vector3(frames[o2 + 5], 0, frames[o2 + 6]), f).normalized()
	aim = Vector3(frames[o + 7], frames[o + 8], frames[o + 9]).lerp(Vector3(frames[o2 + 7], frames[o2 + 8], frames[o2 + 9]), f)
	var mag := lerpf(frames[o + 10], frames[o2 + 10], f)
	sensor_fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(FOV_WIDE) * 0.5) / maxf(mag, 1.0)))
	# banked into the turn, the gun side (left) down towards the target
	var bas := Basis.looking_at(ship_fwd, Vector3.UP)
	var to := aim - ship_pos
	var side := signf(ship_fwd.cross(Vector3(to.x, 0, to.z)).y)
	bas = bas * Basis(Vector3.FORWARD, -side * deg_to_rad(28.0))
	ship.global_transform = Transform3D(bas, ship_pos)
	# objects: interpolate each one between the two samples it appears in
	var now := _objects_in(i)
	var nxt := _objects_in(j)
	var seen := {}
	for rid in now:
		var ob: Array = now[rid]
		var p: Vector3 = ob[1]
		if nxt.has(rid):
			p = p.lerp(nxt[rid][1], f)
		seen[rid] = true
		_show_object(rid, int(ob[0]), p, ob[2], ob[3], ob[4])
	for rid in objects.keys():
		if not seen.has(rid):
			_drop_object(rid)


func _objects_in(i: int) -> Dictionary:
	var out := {}
	var o := frame_off[i]
	var n := int(frames[o + 1])
	for k in n:
		var q := o + 11 + k * 7
		out[int(frames[q])] = [frames[q + 1], Vector3(frames[q + 2], frames[q + 3], frames[q + 4]), frames[q + 5], frames[q + 6], 0]
	return out


func _show_object(rid: int, ty: int, p: Vector3, a: float, b: float, _c) -> void:
	var ob: Dictionary = objects.get(rid, {})
	if ob.is_empty():
		ob = {"type": ty, "node": null, "glow": null, "light": null, "trail": 0.0, "last": p}
		match ty:
			Recorder.OB_MISSILE, Recorder.OB_BOMB, Recorder.OB_THREAT:
				var mi := MeshInstance3D.new()
				mi.mesh = Meshes.get_mesh("bomb" if ty == Recorder.OB_BOMB else "missile")
				mi.material_override = Mats.solid()
				mi.set_instance_shader_parameter("heat", 0.9)
				add_child(mi)
				ob.node = mi
				if ty != Recorder.OB_BOMB:
					ob.glow = effects.take("glow")
					ob.glow.set_instance_shader_parameter("fx_color", Color(2.2, 1.6, 0.9))
			Recorder.OB_FLARE:
				ob.glow = effects.take("glow")
				ob.glow.set_instance_shader_parameter("fx_color", Color(2.5, 2.2, 1.6))
			Recorder.OB_A10, Recorder.OB_F18:
				var id := "jet_a10" if ty == Recorder.OB_A10 else "jet_f18"
				var mi := MeshInstance3D.new()
				mi.mesh = Meshes.get_mesh(id)
				mi.material_override = Meshes.get_material(id, Mats.solid())
				mi.set_instance_shader_parameter("heat", 0.75)
				add_child(mi)
				ob.node = mi
			Recorder.OB_ILLUM:
				ob.glow = effects.take("glow")
				ob.glow.set_instance_shader_parameter("fx_color", Color(2.5, 2.4, 2.0))
				ob.light = effects.hold_light(p, 0.0, 1500.0, Color(1.0, 0.95, 0.82))
		objects[rid] = ob
	var vel: Vector3 = p - ob.last
	ob.last = p
	if ob.node:
		if ty == Recorder.OB_A10 or ty == Recorder.OB_F18:
			ob.node.global_transform = Transform3D(Basis.from_euler(Vector3(b, a, 0.0)), p)
		else:
			ob.node.global_position = p
			if vel.length() > 0.01 and absf(vel.normalized().dot(Vector3.UP)) < 0.999:
				ob.node.look_at(p + vel, Vector3.UP)
	if ob.glow:
		ob.glow.set_instance_shader_parameter("fx_alpha", 1.0)
		ob.glow.set_instance_shader_parameter("fx_heat", 1.0)
		ob.glow.position = p
		ob.glow.scale = Vector3.ONE * maxf(1.5 if ty != Recorder.OB_ILLUM else 3.0, effects.mpp(p) * 5.0)
	if ob.light:
		var y: float = lerpf(550.0, 60.0, a)
		ob.light.position = p
		ob.light.omni_range = y * 2.2 + 300.0
		ob.light.light_energy = 1.8 * minf(1.0, a * 50.0) * (1.0 - pow(a, 6.0))
	if not paused and ty in [Recorder.OB_MISSILE, Recorder.OB_THREAT, Recorder.OB_FLARE, Recorder.OB_ILLUM] and near_view(p):
		ob.trail -= get_process_delta_time()
		if ob.trail <= 0.0:
			ob.trail = 0.05 if ty != Recorder.OB_ILLUM else 0.15
			effects.smoke_trail(p, true, 1.5 if ty != Recorder.OB_ILLUM else 3.0, 5.0)


func _drop_object(rid: int) -> void:
	var ob: Dictionary = objects[rid]
	if ob.node:
		ob.node.queue_free()
	if ob.glow:
		effects.give("glow", ob.glow)
	if ob.light:
		effects.release_light(ob.light)
	objects.erase(rid)


# --- Events -----------------------------------------------------------------

func _run_events(upto: float, show: bool) -> void:
	while ev_i < ev.size() and ev[ev_i] <= upto:
		var t: float = ev[ev_i]
		var code := int(ev[ev_i + 1])
		var o := ev_i + 2
		ev_i += 2 + int(Recorder.EV_ARGS.get(code, 0))
		match code:
			Recorder.EV_BUILDING:
				_collapse(int(ev[o]), show)
			Recorder.EV_FIRE:
				var life: float = ev[o + 4] - (upto - t)
				if life > 0.0:
					effects.fire(Vector3(ev[o], ev[o + 1], ev[o + 2]), ev[o + 3], life, ev[o + 5] > 0.5)
			Recorder.EV_VEHDEAD:
				var p := Vector3(ev[o], ev[o + 1], ev[o + 2])
				if show:
					effects.vehicle_destroyed(p, ev[o + 3] > 0.5)
				elif upto - t < 80.0:
					effects.fire(p + Vector3(0, 1, 0), 3.5 if ev[o + 3] > 0.5 else 2.2, 80.0 - (upto - t))
		if not show:
			continue
		match code:
			Recorder.EV_IMPACT:
				var p := Vector3(ev[o], ev[o + 1], ev[o + 2])
				var fx: String = fx_names[int(ev[o + 3])]
				effects.impact(p, fx, ev[o + 4] > 0.5)
				if fx in ["large", "bomb", "huge"] and not paused:
					Sfx.play("boom_far", -12.0, randf_range(0.85, 1.1), cam.global_position.distance_to(p) / 1500.0)
			Recorder.EV_SHOT:
				var a := Vector3(ev[o], ev[o + 1], ev[o + 2])
				if near_view(a):
					var col := Color(2.0, 0.45, 0.25) if int(ev[o + 6]) == 0 else Color(0.6, 2.0, 0.45)
					effects.tracer(a, Vector3(ev[o + 3], ev[o + 4], ev[o + 5]), col, 800.0)
					effects.muzzle(a, 0.8 if ev[o + 7] > 0.5 else 0.5)
			Recorder.EV_GSHOT:
				var a := Vector3(ev[o], ev[o + 1], ev[o + 2])
				var b := Vector3(ev[o + 3], ev[o + 4], ev[o + 5])
				flights.append({"a": a, "b": b, "t0": t, "T": maxf(ev[o + 6], 0.05), "tank": ev[o + 7] > 0.5, "trail": 0.0})
				if near_view(a):
					effects.muzzle(a, 2.5 if ev[o + 7] > 0.5 else 1.2)
			Recorder.EV_SHELL:
				var a := Vector3(ev[o], ev[o + 1], ev[o + 2])
				var b := Vector3(ev[o + 3], ev[o + 4], ev[o + 5])
				var col := Color(2.0, 0.7, 0.35) if ev[o + 7] > 0.5 else Color(2.0, 1.4, 0.7)
				effects.tracer(a, b, col, a.distance_to(b) / maxf(ev[o + 6], 0.05))
			Recorder.EV_TRACER:
				effects.tracer(Vector3(ev[o], ev[o + 1], ev[o + 2]), Vector3(ev[o + 3], ev[o + 4], ev[o + 5]), Color(2.0, 1.2, 0.4), 950.0)
	while misc_i < misc.size() and float(misc[misc_i][0]) <= upto:
		var m: Array = misc[misc_i]
		misc_i += 1
		if not show:
			continue
		match m[1]:
			"radio":
				radio_lbl.text = "%s: %s" % [m[2][0], m[2][1]]
				radio_t = 6.0
			"spawn":
				effects.spawn(m[2][0], m[2][1], m[2][2])


func _update_flights() -> void:
	var i := flights.size() - 1
	while i >= 0:
		var fl: Dictionary = flights[i]
		var f: float = (rt - fl.t0) / fl.T
		if f >= 1.0 or f < 0.0:
			flights.remove_at(i)
		elif not fl.tank and near_view(fl.a):
			var p: Vector3 = fl.a.lerp(fl.b, f)
			fl.trail -= get_process_delta_time()
			if fl.trail <= 0.0:
				fl.trail = 0.03
				effects.smoke_trail(p, true, 0.5, 2.5)
				effects.muzzle(p, 0.3)
		i -= 1


func _collapse(bi: int, show: bool) -> void:
	if saved_bld.has(bi):
		return
	var b: Dictionary = world.buildings[bi]
	var props: Array = []
	for pr in b.props:
		var mm: MultiMesh = world.prop_mm.get(pr[0])
		if mm:
			props.append([mm, pr[1], mm.get_instance_transform(pr[1])])
	saved_bld[bi] = {"top": b.top, "col": b.col, "heat": b.heat, "win": b.win, "props": props}
	if show:
		world._collapse(bi)
	else:
		var eff = world.battle
		world.battle = null
		world._collapse(bi)
		world.battle = eff


func _restore(bi: int) -> void:
	var s: Dictionary = saved_bld[bi]
	var b: Dictionary = world.buildings[bi]
	b.alive = true
	b.top = s.top
	b.col = s.col
	b.heat = s.heat
	b.win = s.win
	for pr in s.props:
		pr[0].set_instance_transform(pr[1], pr[2])
	world._update_building(bi)
	saved_bld.erase(bi)


## Jumps to time t: restores buildings that fell later, drops what is in the
## air, then catches up silently so fires that should be burning are lit.
func _seek(t: float) -> void:
	t = clampf(t, 0.0, length)
	for bi in saved_bld.keys():
		_restore(bi)
	for rid in objects.keys():
		_drop_object(rid)
	flights.clear()
	for e in effects.emitters:
		e.life = 0.0
	ev_i = 0
	misc_i = 0
	_run_events(t, false)
	for id in units:
		units[id].k = 0
		units[id].dead = false
		units[id].node.set_instance_shader_parameter("tint", Color.WHITE)
		units[id].node.set_instance_shader_parameter("heat", units[id].heat)
	rt = t


# --- Camera and controls ----------------------------------------------------

func _look_at(p: Vector3) -> void:
	var d := (p - cam.global_position).normalized()
	cam_yaw = atan2(-d.x, -d.z)
	cam_pitch = asin(clampf(d.y, -1.0, 1.0))


func _unhandled_input(e: InputEvent) -> void:
	if not built:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look_mouse += e.relative
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_speed = minf(cam_speed * 1.25, 2000.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_speed = maxf(cam_speed / 1.25, 5.0)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				var mp: Vector2 = e.position
				var r := bar.get_global_rect()
				if r.has_point(mp):
					_seek(length * (mp.x - r.position.x) / r.size.x)
				else:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e is InputEventKey and e.pressed and not e.echo:
		_key(e.physical_keycode, e.shift_pressed)
	elif e is InputEventJoypadButton and e.pressed:
		match e.button_index:
			JOY_BUTTON_A:
				paused = not paused
			JOY_BUTTON_X:
				_cycle_cam()
			JOY_BUTTON_Y:
				_set_view_mode((view_mode + 1) % 4)
			JOY_BUTTON_LEFT_SHOULDER:
				_seek(rt - 10.0)
			JOY_BUTTON_RIGHT_SHOULDER:
				_seek(rt + 10.0)
			JOY_BUTTON_DPAD_UP:
				speed_i = mini(speed_i + 1, SPEEDS.size() - 1)
			JOY_BUTTON_DPAD_DOWN:
				speed_i = maxi(speed_i - 1, 0)
			JOY_BUTTON_B, JOY_BUTTON_BACK:
				_exit()


func _key(k: Key, shift: bool) -> void:
	match k:
		KEY_SPACE, KEY_P:
			paused = not paused
		KEY_LEFT:
			_seek(rt - (60.0 if shift else 10.0))
		KEY_RIGHT:
			_seek(rt + (60.0 if shift else 10.0))
		KEY_HOME:
			_seek(0.0)
		KEY_BRACKETLEFT, KEY_MINUS:
			speed_i = maxi(speed_i - 1, 0)
		KEY_BRACKETRIGHT, KEY_EQUAL:
			speed_i = mini(speed_i + 1, SPEEDS.size() - 1)
		KEY_C, KEY_1, KEY_2, KEY_3:
			if k == KEY_C:
				_cycle_cam()
			else:
				cam_mode = k - KEY_1
				_cam_mode_changed()
		KEY_V:
			_set_view_mode((view_mode + 1) % 4)
		KEY_H:
			show_hud = not show_hud
			hud.visible = show_hud
		KEY_L:
			show_line = not show_line
		KEY_TAB:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		KEY_ESCAPE:
			_exit()


func _cycle_cam() -> void:
	cam_mode = (cam_mode + 1) % 3
	_cam_mode_changed()


func _cam_mode_changed() -> void:
	if cam_mode == 0:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.near = 0.5
		_look_at(aim)
	elif cam_mode == 1:
		cam.projection = Camera3D.PROJECTION_FRUSTUM
		cam.near = 20.0
	else:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.near = 0.5
		cam_yaw = atan2(-ship_fwd.x, -ship_fwd.z)
		cam_pitch = -0.18


func _set_view_mode(m: int) -> void:
	view_mode = m
	Game.set_view_mode(m)
	world.apply_view_mode(m)
	post.set_mode(m, world.night)


func _exit() -> void:
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.stop_all()
	Game.set_view_mode(0)
	Game.goto_menu("replays")


func _move_camera(rdt: float) -> void:
	var sens := 0.0025 * float(Game.settings.get("mouse_sens", 1.0))
	var look := look_mouse * sens
	look_mouse = Vector2.ZERO
	var rs := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if rs.length() > 0.15:
		look += rs * rs.length() * 2.2 * rdt
	if bool(Game.settings.get("invert_y", false)):
		look.y = -look.y
	match cam_mode:
		0:
			cam_yaw -= look.x
			cam_pitch = clampf(cam_pitch - look.y, -1.55, 1.55)
			cam.global_transform.basis = Basis.from_euler(Vector3(cam_pitch, cam_yaw, 0.0))
			var mv := Vector3.ZERO
			if Input.is_physical_key_pressed(KEY_W):
				mv.z -= 1
			if Input.is_physical_key_pressed(KEY_S):
				mv.z += 1
			if Input.is_physical_key_pressed(KEY_A):
				mv.x -= 1
			if Input.is_physical_key_pressed(KEY_D):
				mv.x += 1
			var ls := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
			if ls.length() > 0.15:
				mv.x += ls.x
				mv.z += ls.y
			var up := 0.0
			if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_R):
				up += 1
			if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_F):
				up -= 1
			up += Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
			var fast := 6.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
			var step := (cam.global_transform.basis * mv + Vector3.UP * up) * cam_speed * fast * rdt
			var p := cam.global_position + step
			var gy: float = world.height(p.x, p.z)
			p.y = maxf(p.y, gy + 1.5)
			cam.global_position = p
		1:
			var cpos := ship_pos + Vector3(0, -3.0, 0)
			cam.global_transform = Transform3D(Basis.looking_at((aim - cpos).normalized(), Vector3.UP), cpos)
			cam.size = 2.0 * cam.near * tan(deg_to_rad(sensor_fov) * 0.5)
		2:
			cam_yaw -= look.x
			cam_pitch = clampf(cam_pitch - look.y, -1.4, 0.6)
			var b := Basis.from_euler(Vector3(cam_pitch, cam_yaw, 0.0))
			cam.global_transform = Transform3D(b, ship_pos + b * Vector3(0, 8, 95))


# --- Loop -------------------------------------------------------------------

func _process(_dt: float) -> void:
	if not built:
		return
	var now := Time.get_ticks_usec()
	var rdt := minf((now - last_us) / 1000000.0, 0.1)
	last_us = now
	var dt: float = 0.0 if paused else rdt * float(SPEEDS[speed_i])
	Engine.time_scale = 0.0001 if paused else float(SPEEDS[speed_i])
	if not paused:
		rt += dt
		if rt >= length:
			rt = length
			paused = true
		_run_events(rt, true)
	_update_units(dt)
	_update_flights()
	_sample_ship(rt)
	_move_camera(rdt)
	aim_line.visible = show_line and cam_mode != 1
	if aim_line.visible:
		effects.set_beam(aim_line, ship_pos + Vector3(0, -3, 0), aim, 0.08, 1.0)
	radio_t -= rdt
	radio_lbl.visible = radio_t > 0.0
	_update_hud()


# --- HUD --------------------------------------------------------------------

func _label(parent: Node, text: String, size := 18) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.mono())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", UiTheme.FG)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)
	return l


func _build_hud() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 3
	add_child(cl)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(hud)
	info = _label(hud, "", 18)
	info.position = Vector2(24, 18)
	help = _label(hud, "", 15)
	help.modulate = Color(1, 1, 1, 0.75)
	help.text = "WASD move  Q/E down/up  Shift fast  Wheel speed  Mouse look  |  Space pause  Left/Right seek  [ ] speed  C camera  V sensor  L sight line  H hide  Tab mouse  Esc exit"
	radio_lbl = _label(hud, "", 20)
	radio_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar = Control.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bar)
	bar.draw.connect(_draw_bar)


func _draw_bar() -> void:
	var sz := bar.size
	bar.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.45))
	bar.draw_rect(Rect2(Vector2.ZERO, Vector2(sz.x * rt / maxf(length, 1.0), sz.y)), Color(UiTheme.FG, 0.8))
	bar.draw_rect(Rect2(Vector2.ZERO, sz), Color(UiTheme.FG, 0.9), false, 1.0)


func _update_hud() -> void:
	if not show_hud:
		return
	var vs := hud.get_viewport_rect().size
	help.position = Vector2(24, vs.y - 34)
	help.size.x = vs.x - 48
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar.position = Vector2(24, vs.y - 60)
	bar.size = Vector2(vs.x - 48, 12)
	bar.queue_redraw()
	radio_lbl.position = Vector2(40, vs.y - 120)
	radio_lbl.size = Vector2(vs.x - 80, 30)
	var r: Dictionary = data.result
	info.text = "REPLAY  %s  -  %s\n%s / %s   %s   %s   %s%s" % [String(cfg.get("name", "")).to_upper(), String(r.text),
		_mmss(rt), _mmss(length), ("x%s" % str(SPEEDS[speed_i])).replace(".0", ""), CAM_NAMES[cam_mode], MODE_NAMES[view_mode],
		"   PAUSED" if paused else ""]


func _mmss(t: float) -> String:
	return "%02d:%02d" % [int(t) / 60, int(t) % 60]
