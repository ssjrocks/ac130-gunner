extends Node3D
## Everything in flight: gunship rounds, guided weapons, support strikes,
## enemy rockets and tank rounds, and the missiles fired at the aircraft.

const Meshes := preload("res://scripts/world/meshes.gd")
const Mats := preload("res://scripts/world/mats.gd")
const G := 9.8

var battle
var shells: Array = []
var guided: Array = []
var threats: Array = []
var ground: Array = []
var illum: Array = []
var shell_n := 0


# --- Gunship rounds ---------------------------------------------------------

func add_shell(from: Vector3, to: Vector3, wid: String, def: Dictionary, bidx: int, water: bool) -> void:
	var dist := from.distance_to(to)
	var tt := dist / float(def.speed)
	shell_n += 1
	var s := {"a": from, "b": to, "t": 0.0, "T": tt, "wid": wid, "def": def, "bidx": bidx, "water": water, "n": null}
	if shell_n % int(def.get("tracer", 1)) == 0:
		s.n = battle.effects.take("beam")
		var col := Color(2.0, 0.7, 0.35) if wid == "w_762" else Color(2.0, 1.4, 0.7)
		s.n.set_instance_shader_parameter("fx_color", col)
		s.n.set_instance_shader_parameter("fx_alpha", 0.9)
		s.n.set_instance_shader_parameter("fx_heat", 1.0)
	shells.append(s)


func _shell_pos(s: Dictionary, f: float) -> Vector3:
	var tt: float = s.T
	return s.a.lerp(s.b, f) + Vector3.UP * (0.5 * G * tt * tt * f * (1.0 - f))


func _update_shells(dt: float) -> void:
	var i := shells.size() - 1
	while i >= 0:
		var s: Dictionary = shells[i]
		s.t += dt
		if s.t >= s.T:
			if s.n:
				battle.effects.give("beam", s.n)
			shells[i] = shells[shells.size() - 1]
			shells.pop_back()
			explode(s.b, s.def, true, s.wid, s.bidx, s.water)
		elif s.n:
			var f: float = s.t / s.T
			var p := _shell_pos(s, f)
			var p2 := _shell_pos(s, maxf(0.0, f - 0.012))
			var heavy: bool = s.wid in ["w_105", "w_40"]
			battle.effects.set_beam(s.n, p2, p, 0.25 if heavy else 0.12, 2.2 if heavy else 1.4)
		i -= 1


## Blast at p. def needs dmg, radius, pen and fx.
func explode(p: Vector3, def: Dictionary, by_player: bool, wid: String, bidx := -1, water := false) -> void:
	var radius: float = def.radius
	var fx: String = def.get("fx", "medium")
	if fx != "":
		battle.effects.impact(p, fx, water)
	var kills: int = battle.units.damage_area(p, radius, float(def.dmg), int(def.pen), by_player, wid)
	battle.world.damage_buildings(p, radius, float(def.dmg), int(def.pen), bidx)
	if fx != "small":
		battle.units.scare(p, radius * 4.0 + 40.0)
	if by_player:
		battle.on_player_impact(p, def, kills)
	if fx in ["large", "bomb", "huge"]:
		var d: float = battle.gunship.global_position.distance_to(p) if battle.gunship else 4000.0
		var vol := -14.0 + (6.0 if fx == "bomb" else (9.0 if fx == "huge" else 0.0))
		Sfx.play("boom_far", vol, randf_range(0.85, 1.1), d / 1500.0)


# --- Enemy rockets and tank rounds ------------------------------------------

func ground_shot(from: Vector3, to: Vector3, shooter) -> void:
	var tank: bool = shooter.kind == "tank"
	var spd := 900.0 if tank else 140.0
	var def := {"dmg": shooter.d.dmg, "radius": shooter.d.explosive, "pen": shooter.d.get("pen", 2), "fx": "medium"}
	var g := {"a": from, "b": to, "t": 0.0, "T": from.distance_to(to) / spd, "def": def, "tank": tank, "trail": 0.0}
	ground.append(g)
	if battle.near_view(from):
		battle.effects.muzzle(from, 2.5 if tank else 1.2)
		if not tank:
			battle.effects.smoke_trail(from, true, 1.2, 3.0)


func _update_ground(dt: float) -> void:
	var i := ground.size() - 1
	while i >= 0:
		var g: Dictionary = ground[i]
		g.t += dt
		var f: float = minf(g.t / g.T, 1.0)
		var p: Vector3 = g.a.lerp(g.b, f)
		if not g.tank:
			g.trail -= dt
			if g.trail <= 0.0 and battle.near_view(p):
				g.trail = 0.03
				battle.effects.smoke_trail(p, true, 0.5, 2.5)
				battle.effects.muzzle(p, 0.3)
		if f >= 1.0:
			ground.remove_at(i)
			explode(g.b, g.def, false, "")
		i -= 1


# --- Guided weapons and support strikes -------------------------------------

## kind: missile, bomb, cruise, illum. guide: laser or gps.
func launch_guided(kind: String, def: Dictionary, start: Vector3, target: Vector3, tot: float, guide: String, by_player: bool, wid: String) -> Dictionary:
	var g := {"kind": kind, "def": def, "start": start, "target": target, "t": 0.0, "T": tot, "guide": guide,
		"by_player": by_player, "wid": wid, "pos": start, "trail": 0.0, "lased": 0.0, "n": null, "glow": null}
	if kind == "cruise":
		var dir2 := Vector2(randf() - 0.5, randf() - 0.5).normalized()
		if battle.world.coast_x < 1.0e8:
			dir2 = Vector2(1, randf_range(-0.4, 0.4)).normalized()
		var dist := 240.0 * tot
		var s2 := Vector2(target.x, target.z) + dir2 * dist
		g.start = Vector3(s2.x, battle.world.height(s2.x, s2.y) + 80.0, s2.y)
	if kind != "illum":
		var mi := MeshInstance3D.new()
		mi.mesh = Meshes.get_mesh("bomb" if kind == "bomb" else "missile")
		mi.material_override = Mats.solid()
		mi.set_instance_shader_parameter("heat", 0.9 if kind != "bomb" else 0.5)
		if kind == "cruise":
			mi.scale = Vector3(2.0, 2.0, 2.6)
		add_child(mi)
		g.n = mi
	if kind in ["missile", "cruise"]:
		g.glow = battle.effects.take("glow")
		g.glow.set_instance_shader_parameter("fx_color", Color(2.2, 1.6, 0.9))
		g.glow.set_instance_shader_parameter("fx_alpha", 1.0)
		g.glow.set_instance_shader_parameter("fx_heat", 1.0)
	guided.append(g)
	return g


func _guided_pos(g: Dictionary, f: float) -> Vector3:
	var a: Vector3 = g.start
	var b: Vector3 = g.target
	match g.kind:
		"missile":
			var ctrl := a.lerp(b, 0.4) + Vector3.UP * a.distance_to(b) * 0.08
			var e := f * f * (3.0 - 2.0 * f) * 0.3 + f * 0.7
			return a.lerp(ctrl, e).lerp(ctrl.lerp(b, e), e)
		"bomb":
			var h := 1.0 - pow(1.0 - f, 1.6)
			var p := a.lerp(b, h)
			p.y = lerpf(a.y, b.y, f * f)
			return p
		"cruise":
			var p := a.lerp(b, f)
			var dist_left := a.distance_to(b) * (1.0 - f)
			var gy: float = battle.world.height(p.x, p.z)
			if dist_left > 900.0:
				p.y = gy + 70.0
			else:
				var k := 1.0 - dist_left / 900.0
				p.y = lerpf(gy + 70.0 + sin(k * PI) * 260.0, b.y, k * k)
			return p
		"illum":
			return b + Vector3.UP * lerpf(800.0, 550.0, f)
	return a.lerp(b, f)


func _update_guided(dt: float) -> void:
	var spot = battle.laser_point()
	var i := guided.size() - 1
	while i >= 0:
		var g: Dictionary = guided[i]
		g.t += dt
		if g.guide == "laser":
			if spot != null:
				g.target = g.target.lerp(spot, minf(1.0, dt * 3.0))
				g.lased = g.t
		var f: float = minf(g.t / g.T, 1.0)
		var p := _guided_pos(g, f)
		var p2 := _guided_pos(g, minf(1.0, f + 0.01))
		g.pos = p
		if g.n:
			var dir := (p2 - p)
			if dir.length_squared() > 0.0001:
				g.n.transform = Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.FORWARD), p)
				if g.kind == "cruise":
					g.n.scale = Vector3(2.0, 2.0, 2.6)
		if g.glow:
			g.glow.position = p
			var s := maxf(0.8, battle.effects.mpp(p) * 3.0)
			g.glow.scale = Vector3(s, s, s)
		if g.kind in ["missile", "cruise"]:
			g.trail -= dt
			if g.trail <= 0.0:
				g.trail = 0.04
				battle.effects.smoke_trail(p, true, 1.2 if g.kind == "missile" else 2.0, 5.0)
		if f >= 1.0:
			_guided_done(g)
			guided.remove_at(i)
		i -= 1


func _guided_done(g: Dictionary) -> void:
	if g.n:
		g.n.queue_free()
	if g.glow:
		battle.effects.give("glow", g.glow)
	if g.kind == "illum":
		var l: OmniLight3D = battle.effects.hold_light(g.target + Vector3.UP * 550.0, 0.0, 1500.0, Color(1.0, 0.95, 0.82))
		if l:
			# constant brightness through the light's range instead of
			# falling off with distance, or none of it reaches the ground
			l.omni_attenuation = 0.0
		illum.append({"l": l, "t": 0.0, "life": 75.0, "p": g.target, "glow": battle.effects.take("glow")})
		return
	var target: Vector3 = g.target
	if g.guide == "laser" and g.t - float(g.lased) > 3.0:
		# lost the spot: goes ballistic and misses
		target += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(12.0, 30.0)
		target.y = battle.world.height(target.x, target.z)
		if g.by_player:
			battle.radio("SPECTRE", "Lost the spot, weapon went ballistic.")
	var hit: Dictionary = battle.world.raycast(target + Vector3(0, 60, 0), Vector3.DOWN, 200.0)
	var p: Vector3 = hit.get("pos", target)
	explode(p, g.def, g.by_player, g.wid, int(hit.get("bidx", -1)), bool(hit.get("water", false)))


func _update_illum(dt: float) -> void:
	var i := illum.size() - 1
	while i >= 0:
		var it: Dictionary = illum[i]
		it.t += dt
		# a flare under a parachute: lights at ~550 m, drifts down, burns out
		# about 60 m up
		var y := lerpf(550.0, 60.0, it.t / it.life)
		var pos: Vector3 = it.p + Vector3.UP * y + Vector3(sin(it.t * 0.05) * 30.0, 0.0, it.t * 0.6)
		var l: OmniLight3D = it.l
		if l:
			l.position = pos
			l.omni_range = y * 2.2 + 300.0
			var fade := minf(1.0, it.t / 1.5) * (1.0 - pow(it.t / it.life, 6.0))
			l.light_energy = 1.8 * fade * randf_range(0.85, 1.0)
		var gl: MeshInstance3D = it.glow
		gl.set_instance_shader_parameter("fx_color", Color(2.5, 2.4, 2.0))
		gl.set_instance_shader_parameter("fx_alpha", 1.0)
		gl.set_instance_shader_parameter("fx_heat", 1.0)
		gl.position = pos
		gl.scale = Vector3.ONE * maxf(3.0, battle.effects.mpp(pos) * 5.0)
		if randf() < dt * 8.0:
			battle.effects.smoke_trail(pos + Vector3(0, 2, 0), true, 3.0, 8.0)
		if it.t >= it.life:
			battle.effects.release_light(l)
			battle.effects.give("glow", gl)
			illum.remove_at(i)
		i -= 1


# --- Threats to the aircraft --------------------------------------------------

func launch_threat(from: Vector3, kind: String) -> void:
	var plane: Vector3 = battle.gunship.global_position
	var spd := 560.0 if kind == "manpads" else 780.0
	var m := {"pos": from, "vel": (plane - from).normalized() * 60.0 + Vector3.UP * 30.0, "kind": kind, "speed": spd,
		"t": 0.0, "decoy": false, "decoy_pt": Vector3.ZERO, "trail": 0.0, "from": from, "tti": 99.0}
	m["glow"] = battle.effects.take("glow")
	m.glow.set_instance_shader_parameter("fx_color", Color(2.4, 2.0, 1.4))
	m.glow.set_instance_shader_parameter("fx_alpha", 1.0)
	m.glow.set_instance_shader_parameter("fx_heat", 1.0)
	threats.append(m)
	battle.on_missile_launch(m)


func aaa_burst(from: Vector3, slant: float) -> void:
	var plane: Vector3 = battle.gunship.global_position
	var dir := (plane - from).normalized()
	for k in 6:
		var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.03
		var reach := minf(slant, 2600.0) * randf_range(0.75, 1.0)
		var end := from + (dir + jitter).normalized() * reach
		battle.effects.tracer(from, end, Color(2.0, 1.2, 0.4), 950.0)
		if reach >= slant * 0.9:
			battle.effects.impact(end, "flak", false)
	var p := 0.35 * (1.0 - slant / 3300.0)
	if randf() < p:
		battle.gunship.take_damage(randf_range(3.0, 7.0), "aaa")
	battle.on_aaa(from)


func flares() -> int:
	var plane: Vector3 = battle.gunship.global_position
	var n := 0
	for m in threats:
		if m.decoy:
			continue
		var tti: float = m.tti
		var chance := 0.15
		if tti > 0.4 and tti < 3.6:
			chance = 0.92
		elif tti < 6.5:
			chance = 0.5
		if randf() < chance:
			m.decoy = true
			m.decoy_pt = plane + Vector3(randf_range(-150, 150), -randf_range(80, 250), randf_range(-150, 150))
			n += 1
	return n


func _update_threats(dt: float) -> void:
	if battle.gunship == null:
		return
	var plane: Vector3 = battle.gunship.global_position
	var i := threats.size() - 1
	while i >= 0:
		var m: Dictionary = threats[i]
		m.t += dt
		var aim: Vector3 = m.decoy_pt if m.decoy else plane
		var to: Vector3 = aim - m.pos
		var dist := to.length()
		var cur: float = m.vel.length()
		var spd := minf(cur + 420.0 * dt, m.speed)
		var desired := to.normalized() * spd
		m.vel = m.vel.lerp(desired, minf(1.0, dt * (2.2 if m.t > 0.6 else 0.6))).normalized() * spd
		m.pos += m.vel * dt
		m.tti = dist / maxf(spd, 1.0)
		m.trail -= dt
		if m.trail <= 0.0:
			m.trail = 0.035
			battle.effects.smoke_trail(m.pos, true, 1.6, 9.0)
		var gl: MeshInstance3D = m.glow
		gl.position = m.pos
		gl.scale = Vector3.ONE * maxf(1.0, battle.effects.mpp(m.pos) * 3.5)
		var done := false
		if not m.decoy and dist < 35.0:
			battle.gunship.take_damage(34.0 if m.kind == "manpads" else 50.0, m.kind)
			done = true
		elif m.decoy and (dist < 30.0 or m.t > 16.0):
			battle.effects.impact(m.pos, "air", false)
			done = true
		elif m.t > 22.0:
			battle.effects.impact(m.pos, "air", false)
			done = true
		if done:
			battle.effects.give("glow", gl)
			threats.remove_at(i)
		i -= 1


func _process(dt: float) -> void:
	_update_shells(dt)
	_update_ground(dt)
	_update_guided(dt)
	_update_illum(dt)
	_update_threats(dt)
