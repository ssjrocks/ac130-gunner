extends Node3D
## Every ground unit and helicopter: spawning, movement, target picking,
## firing, damage and death. One manager updates them all each frame.

const Meshes := preload("res://scripts/world/meshes.gd")
const Models := preload("res://scripts/world/models.gd")
const Mats := preload("res://scripts/world/mats.gd")
const CELL := 100.0

# acc: hit chance per shot at point blank. armor: 0 soft .. 3 heavy.
const KINDS := {
	"soldier": {"mesh": "friendly", "hp": 100.0, "speed": 3.0, "run": 4.8, "range": 420.0, "dmg": 9.0, "rof": 1.0, "acc": 0.14, "heat": 0.85, "score": 0},
	"mg": {"mesh": "friendly", "hp": 100.0, "speed": 2.6, "run": 4.2, "range": 650.0, "dmg": 6.0, "rof": 5.0, "acc": 0.06, "heat": 0.85, "score": 0},
	"sf": {"mesh": "sf", "hp": 260.0, "speed": 3.4, "run": 5.2, "range": 480.0, "dmg": 13.0, "rof": 1.4, "acc": 0.24, "heat": 0.85, "score": 0},
	"survivor": {"mesh": "surv", "hp": 140.0, "speed": 2.8, "run": 4.6, "range": 260.0, "dmg": 35.0, "rof": 0.9, "acc": 0.5, "heat": 0.85, "score": 0},
	"vip": {"mesh": "vip", "hp": 150.0, "speed": 2.6, "run": 4.4, "range": 0.0, "heat": 0.85, "score": 0},
	"pilot": {"mesh": "pilot", "hp": 320.0, "speed": 2.6, "run": 4.4, "range": 180.0, "dmg": 5.0, "rof": 0.6, "acc": 0.25, "heat": 0.85, "score": 0},
	"rifle": {"mesh": "enemy", "hp": 100.0, "speed": 3.0, "run": 4.8, "range": 380.0, "dmg": 7.0, "rof": 1.0, "acc": 0.1, "heat": 0.85, "score": 10},
	"emg": {"mesh": "enemy", "hp": 100.0, "speed": 2.6, "run": 4.2, "range": 600.0, "dmg": 5.0, "rof": 5.0, "acc": 0.045, "heat": 0.85, "score": 15},
	"rpg": {"mesh": "enemyrpg", "hp": 100.0, "speed": 2.8, "run": 4.6, "range": 330.0, "dmg": 170.0, "rof": 0.12, "acc": 0.35, "pen": 2, "explosive": 3.0, "av": true, "heat": 0.85, "score": 20},
	"manpads": {"mesh": "enemyrpg", "hp": 100.0, "speed": 2.8, "run": 4.6, "range": 0.0, "aa": "manpads", "aa_range": 4300.0, "aa_cd": 30.0, "heat": 0.85, "score": 40},
	"civ": {"mesh": "civ", "hp": 60.0, "speed": 1.3, "run": 4.2, "range": 0.0, "beh": "civ", "heat": 0.85, "score": 0},
	# the infected: a rage virus that runs them hot and makes them sprint once they see prey
	"zombie": {"mesh": "zombie", "hp": 75.0, "speed": 1.8, "run": 6.0, "range": 1.8, "dmg": 20.0, "rof": 0.9, "acc": 0.7, "melee": true, "beh": "zombie", "heat": 1.0, "score": 5},
	"brute": {"mesh": "zombie", "hp": 300.0, "speed": 2.0, "run": 5.0, "range": 2.2, "dmg": 45.0, "rof": 0.8, "acc": 0.8, "melee": true, "beh": "zombie", "heat": 1.0, "score": 25, "scale": 1.35},
	"technical": {"mesh": "technical", "hp": 380.0, "speed": 13.0, "range": 850.0, "dmg": 6.0, "rof": 5.0, "acc": 0.06, "armor": 1, "veh": true, "r": 2.6, "heat": 0.75, "score": 60},
	"truck": {"mesh": "truck", "hp": 320.0, "speed": 12.0, "range": 0.0, "armor": 1, "veh": true, "r": 3.6, "heat": 0.72, "score": 40},
	"btr": {"mesh": "btr", "hp": 1200.0, "speed": 12.0, "range": 1000.0, "dmg": 14.0, "rof": 2.5, "acc": 0.1, "armor": 2, "veh": true, "r": 3.6, "heat": 0.8, "score": 150},
	"tank": {"mesh": "tank", "hp": 2600.0, "speed": 8.0, "range": 1800.0, "dmg": 260.0, "rof": 0.12, "acc": 0.45, "pen": 3, "explosive": 6.0, "av": true, "armor": 3, "veh": true, "r": 3.8, "heat": 0.85, "score": 300},
	"zu23": {"mesh": "zu23", "hp": 300.0, "speed": 0.0, "range": 1500.0, "dmg": 10.0, "rof": 3.0, "acc": 0.08, "armor": 1, "veh": true, "r": 1.8, "heat": 0.55, "aa": "aaa", "aa_range": 3300.0, "aa_cd": 4.0, "score": 150},
	"sam": {"mesh": "sam", "hp": 500.0, "speed": 0.0, "range": 0.0, "armor": 1, "veh": true, "r": 3.4, "heat": 0.7, "aa": "sam", "aa_range": 9000.0, "aa_cd": 24.0, "score": 400},
	"radar": {"mesh": "radar", "hp": 420.0, "speed": 0.0, "range": 0.0, "armor": 1, "veh": true, "r": 3.2, "heat": 0.85, "score": 200},
	"suv": {"mesh": "suv", "hp": 450.0, "speed": 15.0, "range": 0.0, "armor": 1, "veh": true, "r": 2.6, "heat": 0.72, "score": 250},
	"pickup": {"mesh": "pickup", "hp": 300.0, "speed": 14.0, "range": 0.0, "armor": 1, "veh": true, "r": 2.6, "heat": 0.72, "score": 0},
	"car": {"mesh": "car", "hp": 200.0, "speed": 13.0, "range": 0.0, "armor": 1, "veh": true, "r": 2.3, "heat": 0.72, "beh": "civ", "score": 0},
	"ctruck": {"mesh": "truck", "hp": 320.0, "speed": 11.0, "range": 0.0, "armor": 1, "veh": true, "r": 3.6, "heat": 0.72, "beh": "civ", "score": 0},
	"humvee": {"mesh": "humvee", "hp": 800.0, "speed": 14.0, "range": 850.0, "dmg": 7.0, "rof": 5.0, "acc": 0.08, "armor": 1, "veh": true, "r": 2.6, "heat": 0.75, "score": 0},
	"mrap": {"mesh": "mrap", "hp": 1500.0, "speed": 13.0, "range": 800.0, "dmg": 7.0, "rof": 5.0, "acc": 0.08, "armor": 2, "veh": true, "r": 3.2, "heat": 0.78, "score": 0},
	"hulk": {"mesh": "tank", "hp": 700.0, "speed": 0.0, "range": 0.0, "armor": 1, "veh": true, "r": 3.8, "heat": 0.35, "beh": "static", "score": 30},
	"target_truck": {"mesh": "truck", "hp": 400.0, "speed": 9.0, "range": 0.0, "armor": 1, "veh": true, "r": 3.6, "heat": 0.72, "beh": "static", "score": 50},
	"heli": {"mesh": "heli", "hp": 3000.0, "speed": 55.0, "range": 0.0, "armor": 2, "veh": true, "r": 7.0, "heat": 0.85, "beh": "heli", "score": 0},
	"wreck": {"mesh": "wreck", "hp": 99999.0, "speed": 0.0, "range": 0.0, "armor": 4, "veh": true, "r": 5.0, "heat": 0.9, "beh": "static", "score": 0},
}


class U extends RefCounted:
	var id := 0
	var kind := ""
	var d: Dictionary
	var team := 1
	var beh := "soldier"
	var group := ""
	var pos := Vector3.ZERO
	var heading := 0.0
	var hp := 100.0
	var alive := true
	var boarded := false
	var node: MeshInstance3D
	var extra: Node3D
	var mesh_id := ""
	var order := "hold"
	var goal := Vector3.ZERO
	var home := Vector3.ZERO
	var path: Array = []
	var path_i := 0
	var target = null
	var think_t := 0.0
	var fire_t := 0.0
	var pause_t := 0.0
	var supp_t := 0.0
	var moving := false
	var halted := false
	var speed_mul := 1.0
	var leader = null
	var cargo: Array = []
	var dead_t := 0.0
	var heat := 0.85
	var player_hit := false
	var stuck_t := 0.0
	var climb_t := 0.0
	var last_pos := Vector3.ZERO
	var aa_t := 0.0
	var phase := 0.0
	var veh := false
	var vel := Vector3.ZERO
	var r := 0.45
	var on_arrive := ""
	var data := {}
	var elev := 0.0          # standing this high above the ground (a guard tower, a firing step)
	var prone := false       # lying behind sandbags: low and hard to hit
	var downed := false      # a wounded friendly waiting for medevac (alive is false)
	var down_t := 0.0


var battle
var world
var list: Array = []
var grid := {}
var grid_t := 0.0
var next_id := 1
var time := 0.0
var acc_mult := 1.0
var hp_mult := 1.0
var aa_mult := 1.0
var cleanup_t := 0.0
var audit_shots := 0        # autotest: ranged shots fired, and how many had no fresh sight line
var audit_blind := 0


func _ready() -> void:
	world = battle.world


func mesh_id_for(kind: String, team: int, opts: Dictionary) -> String:
	var base: String = KINDS[kind].mesh
	var id := ""
	match base:
		"friendly":
			id = "inf_friendly"
		"sf":
			id = "inf_sf"
		"enemy":
			id = "inf_enemy_%d" % (randi() % 5)
		"enemyrpg":
			id = "inf_enemy_%d_rpg" % (randi() % 5)
		"civ":
			id = "inf_civ_%d" % (randi() % 8)
		"surv":
			id = "inf_surv_%d" % (randi() % 4)
		"zombie":
			id = "inf_zombie_%d" % (randi() % 4)
		"vip":
			id = "inf_vip"
		"pilot":
			id = "inf_pilot"
		_:
			var paint: String = opts.get("paint", "")
			if paint == "":
				match base:
					"technical", "truck", "suv", "pickup":
						paint = ["white", "tan", "dark", "white", "sand"][randi() % 5] if team == 1 else ["white", "silver", "blue", "red", "tan"][randi() % 5]
					"car":
						paint = ["white", "silver", "blue", "red", "dark", "tan", "black"][randi() % 7]
					"humvee", "mrap":
						paint = "sand"
					"btr", "tank", "zu23", "sam", "radar":
						paint = "green" if world.biome in ["green", "mountain", "urban"] else "sand"
					"heli":
						paint = opts.get("airframe", "uh60")
			id = base + ("_" + paint if paint != "" else "")
	return id


func spawn(kind: String, team: int, pos: Vector3, group := "", opts := {}) -> U:
	var u := U.new()
	u.id = next_id
	next_id += 1
	u.kind = kind
	u.d = KINDS[kind]
	u.team = team
	u.group = group
	u.beh = u.d.get("beh", "soldier")
	if u.d.has("aa"):
		u.beh = "aa"
	u.beh = opts.get("beh", u.beh)
	u.hp = float(u.d.hp) * (hp_mult if team == 1 else 1.0)
	u.veh = u.d.get("veh", false)
	u.r = u.d.get("r", 0.45)
	if u.beh == "heli":
		u.pos = pos
	else:
		u.pos = Vector3(pos.x, world.height(pos.x, pos.z), pos.z)
	u.home = u.pos
	u.last_pos = u.pos
	u.heading = opts.get("heading", randf() * TAU)
	u.heat = u.d.get("heat", 0.85)
	u.phase = randf() * TAU
	u.think_t = randf() * 0.8
	u.aa_t = randf_range(20.0, 20.0 + float(u.d.get("aa_cd", 10.0)))
	var mi := MeshInstance3D.new()
	var mesh_id: String = opts.get("mesh_id", mesh_id_for(kind, team, opts))
	u.mesh_id = mesh_id
	mi.mesh = Meshes.get_mesh(mesh_id)
	mi.material_override = Meshes.get_material(mesh_id, Mats.solid() if u.veh else Mats.unit())
	mi.layers = 2
	mi.set_instance_shader_parameter("heat", u.heat)
	if opts.has("tint"):
		mi.set_instance_shader_parameter("tint", opts.tint)
	add_child(mi)
	u.node = mi
	if u.d.has("scale"):
		mi.scale = Vector3.ONE * float(u.d.scale)
	if team == 0 and not u.veh:
		var s := MeshInstance3D.new()
		s.mesh = battle.effects.quad
		s.material_override = Mats.fx("ir")
		s.set_instance_shader_parameter("fx_color", Color(1.4, 1.4, 1.4))
		s.set_instance_shader_parameter("fx_heat", 1.0)
		s.position = Vector3(0, 1.9, 0)
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.visible = false
		mi.add_child(s)
		u.extra = s
	if not u.veh and Meshes.is_model(mesh_id):
		arm(mi, mesh_id, kind)
	if kind == "heli":
		u.extra = rotors(mi, mesh_id)
	u.order = opts.get("order", "hold")
	u.goal = opts.get("goal", u.pos)
	u.path = opts.get("path", [])
	u.cargo = opts.get("cargo", [])
	u.on_arrive = opts.get("on_arrive", "")
	u.speed_mul = opts.get("speed_mul", 1.0)
	u.leader = opts.get("leader", null)
	u.data = opts.get("data", {})
	list.append(u)
	_pose(u, 0.0)
	return u


## Gives an imported person the weapon its kind carries, held in front
## between the hands (rocket tubes on the shoulder).
static func arm(mi: MeshInstance3D, mesh_id: String, kind: String) -> void:
	var w := ""
	match kind:
		"soldier", "sf", "rifle", "survivor":
			w = "rifle"
		"mg", "emg":
			w = "mg"
		"rpg", "manpads":
			w = "rpg"
	if w == "":
		return
	var gm := MeshInstance3D.new()
	gm.mesh = Meshes.get_mesh("wpn_" + w)
	gm.material_override = Mats.solid()
	gm.set_instance_shader_parameter("heat", 0.5)
	var hands: Array = Models.hands(Models.lookup(mesh_id)[0])
	if w == "rpg" or hands.size() < 2:
		gm.position = Vector3(0.16, 1.52, 0.05)
	else:
		var a: Array = hands[0]
		var b: Array = hands[1]
		gm.position = Vector3((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5 + 0.05, (a[2] + b[2]) * 0.5 - 0.1)
		gm.rotation = Vector3(-0.2, 0.0, 0.0)
	mi.add_child(gm)


## Spinning rotors: the model's own rotor parts, or the plain disc. Returns
## a holder whose children each carry their spin axis.
static func rotors(mi: MeshInstance3D, mesh_id: String) -> Node3D:
	var holder := Node3D.new()
	mi.add_child(holder)
	var model: String = Models.lookup(mesh_id)[0]
	var parts: Dictionary = Models.parts(model) if model != "" else {}
	if parts.is_empty():
		var rot := MeshInstance3D.new()
		rot.mesh = Meshes.get_mesh("rotor")
		rot.material_override = Mats.solid()
		rot.set_instance_shader_parameter("heat", 0.6)
		rot.position = Vector3(0, 3.75, 0)
		rot.set_meta("spin", Vector3.UP)
		holder.add_child(rot)
		return holder
	var dir := 1.0
	for pname in parts:
		var pd: Dictionary = parts[pname]
		var pm := pd.file.get_basename() as String
		var rot := MeshInstance3D.new()
		rot.mesh = Models.mesh(pm)
		rot.material_override = Models.material(pm, false, Color.WHITE)
		rot.set_instance_shader_parameter("heat", 0.6)
		rot.position = Vector3(pd.pos[0], pd.pos[1], pd.pos[2])
		var axis := Vector3.RIGHT if pd.axis == "x" else Vector3.UP
		# tandem rotors turn opposite ways; tail rotors spin faster
		rot.set_meta("spin", axis * (2.2 if pd.axis == "x" else dir))
		if pd.axis != "x":
			dir = -dir
		holder.add_child(rot)
	return holder


## Spawns several units spread around a centre. Returns them.
func squad(kinds: Array, team: int, center: Vector3, spread: float, group: String, opts := {}) -> Array:
	var out: Array = []
	for k in kinds:
		var p: Vector3 = world.free_spot(Vector2(center.x, center.z), spread)
		var o: Dictionary = opts.duplicate(true)
		if o.has("goal"):
			var g: Vector3 = o.goal
			o.goal = g + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * maxf(spread, 8.0)
		out.append(spawn(k, team, p, group, o))
	return out


# --- Queries --------------------------------------------------------------

func _rebuild_grid() -> void:
	grid.clear()
	for u in list:
		if u.alive:
			var key := Vector2i(floori(u.pos.x / CELL), floori(u.pos.z / CELL))
			if grid.has(key):
				grid[key].append(u)
			else:
				grid[key] = [u]


func query(p: Vector3, r: float) -> Array:
	var out: Array = []
	for cx in range(floori((p.x - r) / CELL), floori((p.x + r) / CELL) + 1):
		for cz in range(floori((p.z - r) / CELL), floori((p.z + r) / CELL) + 1):
			var key := Vector2i(cx, cz)
			if grid.has(key):
				out.append_array(grid[key])
	return out


func hostile(a: U, b: U) -> bool:
	if a.team == b.team or a.team == 2:
		return false
	if b.team == 2:
		return a.beh == "zombie"
	if b.beh == "heli" or b.kind == "wreck":
		return false
	return true


func count(group: String) -> int:
	var n := 0
	for u in list:
		if u.alive and u.group == group:
			n += 1
	return n


func boarded(group: String) -> int:
	var n := 0
	for u in list:
		if u.boarded and u.group == group:
			n += 1
	return n


func members(group: String) -> Array:
	var out: Array = []
	for u in list:
		if u.alive and u.group == group:
			out.append(u)
	return out


func count_team(team: int) -> int:
	var n := 0
	for u in list:
		if u.alive and u.team == team:
			n += 1
	return n


func enemies_near(p: Vector3, r: float) -> int:
	var n := 0
	for u in query(p, r):
		if u.alive and u.team == 1 and u.beh != "static" and Vector2(u.pos.x - p.x, u.pos.z - p.z).length() < r:
			n += 1
	return n


func nearest(p: Vector3, maxd: float, team := -1) -> U:
	var best: U = null
	var bd := maxd * maxd
	for u in query(p, maxd):
		if not u.alive or (team >= 0 and u.team != team):
			continue
		var d2: float = (u.pos - p).length_squared()
		if d2 < bd:
			bd = d2
			best = u
	return best


func centroid(group: String) -> Vector3:
	var s := Vector3.ZERO
	var n := 0
	for u in list:
		if u.alive and u.group == group:
			s += u.pos
			n += 1
	if n == 0:
		return Vector3.ZERO
	return s / n


## Where u will be in t seconds: along its route for units following a
## path, otherwise straight on at its current velocity.
func predict(u: U, t: float) -> Vector3:
	var spd := Vector2(u.vel.x, u.vel.z).length()
	if spd < 0.2:
		return u.pos
	var p := u.pos
	if u.order in ["move", "convoy", "path"] and u.path_i < u.path.size():
		var left := spd * t
		var i := u.path_i
		while left > 0.0 and i < u.path.size():
			var w: Vector3 = u.path[i]
			var seg := Vector2(w.x - p.x, w.z - p.z).length()
			if seg >= left:
				p += (w - p) * (left / maxf(seg, 0.001))
				left = 0.0
			else:
				p = w
				left -= seg
				i += 1
	else:
		p += Vector3(u.vel.x, 0.0, u.vel.z) * t
	p.y = world.height(p.x, p.z)
	return p


static func armor_mul(pen: int, armor: int) -> float:
	if pen >= armor:
		return 1.0
	if pen == armor - 1:
		return 0.3
	return 0.04


# --- Damage ---------------------------------------------------------------

func damage_area(p: Vector3, radius: float, dmg: float, pen: int, by_player: bool, wid: String) -> int:
	var kills := 0
	for u in query(p, radius + 6.0):
		if not u.alive or u.beh == "heli":
			continue
		var dx: float = u.pos.x - p.x
		var dz: float = u.pos.z - p.z
		var d := maxf(0.0, sqrt(dx * dx + dz * dz) - u.r)
		var dy := absf(u.pos.y + u.elev + 0.8 - p.y)
		d = sqrt(d * d + maxf(0.0, dy - 1.5) * maxf(0.0, dy - 1.5))
		if d > radius:
			continue
		var f := maxf(0.0, 1.0 - pow(d / radius, 1.5))
		var dam := dmg * f * armor_mul(pen, int(u.d.get("armor", 0)))
		if u.prone:
			dam *= 0.5
		if dam <= 0.0:
			continue
		if hurt(u, dam, by_player, wid):
			kills += 1
		elif not u.veh and u.beh == "soldier":
			u.supp_t = 4.0
	return kills


func hurt(u: U, dam: float, by_player: bool, wid: String) -> bool:
	if not u.alive:
		return false
	u.hp -= dam
	if by_player:
		u.player_hit = true
	if u.hp <= 0.0:
		kill(u, by_player, wid)
		return true
	if u.veh and u.cargo.size() > 0 and u.hp < float(u.d.hp) * 0.6:
		dismount(u)
	return false


func kill(u: U, by_player: bool, wid: String) -> void:
	u.alive = false
	u.moving = false
	u.dead_t = 0.0
	u.elev = 0.0
	u.prone = false
	# most friendly soldiers who go down are wounded, not dead: a medevac can
	# still save them if it gets there within five minutes
	if u.team == 0 and u.kind in ["soldier", "mg", "sf"] and u.hp > -float(u.d.hp) * 2.0 and randf() < 0.7:
		u.downed = true
		u.down_t = time
	if u.extra and u.kind != "heli":
		u.extra.visible = false
	if u.veh:
		u.node.set_instance_shader_parameter("tint", Color(0.2, 0.19, 0.18))
		u.heat = 1.0
		u.node.set_instance_shader_parameter("heat", 1.0)
		battle.effects.vehicle_destroyed(u.pos, u.kind in ["tank", "btr", "truck", "sam", "heli"])
		u.cargo = []
		# a secondary explosion catches anyone standing next to it
		damage_area(u.pos + Vector3(0, 1, 0), 6.0, 120.0, 1, by_player, wid)
	else:
		u.node.set_instance_shader_parameter("tint", Color(0.6, 0.6, 0.6))
	_pose(u, 0.0)
	battle.on_unit_killed(u, by_player, wid)


## Runs from something (a show of force) for dur seconds, then goes back to
## what it was doing.
func panic(u: U, away: Vector3, dur: float) -> void:
	if not u.alive or u.boarded or u.beh in ["static", "heli"] or dur <= 1.0:
		return
	var dist := randf_range(150.0, 350.0) * (2.0 if u.veh else 1.0)
	if u.beh == "civ":
		u.order = "flee"
		u.goal = u.pos + away * dist
		u.data["flee_t"] = dur
		return
	if not u.data.has("panic_until"):
		u.data["panic_prev"] = {"order": u.order, "goal": u.goal, "path": u.path, "path_i": u.path_i, "on_arrive": u.on_arrive}
	u.data["panic_until"] = time + dur
	u.order = "flee"
	u.goal = u.pos + away * dist
	u.on_arrive = ""
	u.target = null
	u.pause_t = 0.0


## Civilians near a blast run away; soldiers keep their heads down.
func scare(p: Vector3, r: float) -> void:
	for u in query(p, r):
		if not u.alive:
			continue
		var away := Vector3(u.pos.x - p.x, 0, u.pos.z - p.z)
		if away.length() > r:
			continue
		if u.beh == "civ" and u.order != "flee":
			u.order = "flee"
			var dirv := away.normalized() if away.length() > 0.1 else Vector3(randf() - 0.5, 0, randf() - 0.5).normalized()
			u.goal = u.pos + dirv * randf_range(150.0, 300.0)
			u.speed_mul = 1.0
			u.data["flee_t"] = 25.0
		elif u.beh == "soldier" and u.team == 1 and not u.veh:
			u.supp_t = maxf(u.supp_t, 3.0)


func dismount(u: U) -> void:
	if u.cargo.is_empty():
		return
	var goal: Vector3 = u.data.get("goal", u.goal)
	for k in u.cargo:
		var p: Vector3 = world.free_spot(Vector2(u.pos.x, u.pos.z), 8.0)
		var o := {"order": "assault", "goal": goal + Vector3(randf_range(-40, 40), 0, randf_range(-40, 40))}
		if u.data.has("contact"):
			o["data"] = {"contact": u.data.contact}
		spawn(k, u.team, p, u.group, o)
	u.cargo = []
	u.order = "hold"


## The QRF on the move: on contact the whole platoon stops and the troops
## get out and fight; once nothing hostile is near for a few seconds they
## mount up again and the trucks carry on to the objective.
func _qrf_think(u: U) -> void:
	var st: String = u.data.get("qrf_state", "driving")
	match st:
		"driving":
			if u.order == "convoy" and not u.cargo.is_empty() and time > float(u.data.get("contact_cd", 0.0)):
				var e = _find_target(u, 380.0, true)
				if e != null:
					for v in members(u.group):
						if v.veh and v.data.get("qrf_state", "driving") == "driving" and v.order == "convoy":
							_qrf_dismount(v, e.pos)
		"fighting":
			u.halted = true
			u.data.fight_t = float(u.data.get("fight_t", 0.0)) + 1.0
			var threat: Vector3 = u.data.get("threat", u.pos)
			if enemies_near(u.pos, 320.0) == 0 and enemies_near(threat, 200.0) == 0:
				u.data.clear_t = float(u.data.get("clear_t", 0.0)) + 1.0
			else:
				u.data.clear_t = 0.0
			# the objective matters more than a firefight that won't end:
			# after two minutes they break contact and push on
			if float(u.data.clear_t) >= 6.0 or float(u.data.fight_t) >= 120.0:
				u.data.qrf_state = "mounting"
				if u.leader == null:
					battle.radio("WARHORSE 2-6", "Area's clear, mounting up. Warhorse continuing to the objective.")
		"mounting":
			u.halted = true
			var threat2: Vector3 = u.data.get("threat", u.pos)
			if (enemies_near(u.pos, 320.0) > 0 or enemies_near(threat2, 200.0) > 0) and float(u.data.get("fight_t", 0.0)) < 120.0:
				u.data.qrf_state = "fighting"
				u.data.clear_t = 0.0
				for id in u.data.dismounts:
					var m = by_id(id)
					if m != null and m.alive:
						m.order = "assault"
						m.goal = u.pos + (m.pos - u.pos).normalized() * 40.0
				return
			var left := 0
			for id in u.data.dismounts:
				var m = by_id(id)
				if m == null or not m.alive or m.boarded:
					continue
				if m.pos.distance_to(u.pos) < 7.0:
					u.cargo.append(m.kind)
					remove_unit(m)
					continue
				m.order = "board"
				m.goal = u.pos
				left += 1
			if left == 0:
				u.data.dismounts = []
				u.data.qrf_state = "driving"
				u.data.fight_t = 0.0
				u.data["contact_cd"] = time + 60.0
				u.halted = false


func _qrf_dismount(u: U, threat: Vector3) -> void:
	var ids: Array = []
	var away := (threat - u.pos)
	away.y = 0.0
	away = away.normalized()
	for k in u.cargo:
		var p: Vector3 = world.free_spot(Vector2(u.pos.x, u.pos.z), 8.0)
		# go after the contact until they can see it
		var m := spawn(k, u.team, p, u.group, {"order": "assault", "goal": threat + Vector3(randf_range(-25, 25), 0, randf_range(-25, 25))})
		ids.append(m.id)
	u.cargo = []
	u.data.dismounts = ids
	u.data["threat"] = threat
	u.data.qrf_state = "fighting"
	u.data.clear_t = 0.0
	u.halted = true
	if u.leader == null:
		battle.radio("WARHORSE 2-6", "Contact! Warhorse is dismounting, %s." % battle.mission.compass(threat - u.pos))


func by_id(id: int):
	for u in list:
		if u.id == id:
			return u
	return null


## Puts the troops at each outpost onto its fighting positions: a guard up
## every tower, the rest prone on the sandbag steps along the walls.
func man_posts() -> void:
	for sname in world.posts:
		var posts: Array = world.posts[sname]
		var c: Vector3 = world.site(sname)
		var size := float(world.map.get("outposts", {}).get(sname, 40.0))
		var free := posts.duplicate()
		for u in list:
			if free.is_empty():
				break
			if not u.alive or u.team != 0 or u.veh or u.order != "hold" or u.beh != "soldier":
				continue
			if Vector2(u.pos.x - c.x, u.pos.z - c.z).length() > size * 0.6:
				continue
			# towers first, then the nearest step
			var pick := 0
			if free[0].kind != "tower":
				var bd := 1.0e9
				for i in free.size():
					var dd: float = free[i].pos.distance_to(u.pos)
					if dd < bd:
						bd = dd
						pick = i
			var ps: Dictionary = free[pick]
			free.remove_at(pick)
			u.pos = ps.pos
			u.home = ps.pos
			u.goal = ps.pos
			u.heading = ps.face
			u.elev = ps.elev
			u.prone = ps.kind == "step"
			u.data["post"] = ps.get("bi", -1)
			_pose(u, 0.0)


func remove_unit(u: U) -> void:
	u.alive = false
	if is_instance_valid(u.node):
		u.node.queue_free()
	list.erase(u)


# --- Update ---------------------------------------------------------------

func _process(dt: float) -> void:
	time += dt
	grid_t -= dt
	if grid_t <= 0.0:
		_rebuild_grid()
		grid_t = 0.25
	var blink := fposmod(time, 1.4)
	for u in list:
		if not u.alive:
			continue
		if u.beh == "heli":
			_heli(u, dt)
			continue
		u.think_t -= dt
		if u.think_t <= 0.0:
			_think(u)
		if u.supp_t > 0.0:
			u.supp_t -= dt
		_fight(u, dt)
		_move(u, dt)
		_pose(u, dt)
		if u.extra and u.team == 0 and not u.veh:
			var on := fposmod(blink + u.id * 0.37, 1.4) < 0.09
			u.extra.visible = on
			if on:
				u.extra.scale = Vector3.ONE * maxf(0.15, battle.effects.mpp(u.pos) * 3.0)
	cleanup_t -= dt
	if cleanup_t <= 0.0:
		cleanup_t = 1.0
		_cleanup()


func _cleanup() -> void:
	var dead := 0
	var i := list.size() - 1
	while i >= 0:
		var u: U = list[i]
		if u.alive and u.elev > 0.0 and int(u.data.get("post", -1)) >= 0 and not world.buildings[int(u.data.post)].alive:
			# the tower came down under him
			u.elev = 0.0
			hurt(u, 70.0, false, "")
		if not u.alive and u.downed:
			# the wounded stay warm and stay put; after five minutes without
			# a medevac they're lost
			if time - u.down_t > 300.0:
				u.downed = false
				battle.radio("JTAC", "We lost one of the wounded. He didn't make it.")
			i -= 1
			continue
		if not u.alive:
			u.dead_t += 1.0
			dead += 1
			if u.heat > 0.3 and not u.boarded:
				u.heat = maxf(0.3, u.heat - (0.004 if u.veh else 0.006))
				u.node.set_instance_shader_parameter("heat", u.heat)
			# boarded units stay listed (hidden): missions count them as rescued
			if not u.boarded and (u.dead_t > (400.0 if u.veh else 240.0) or (dead > 450 and not u.veh)):
				if is_instance_valid(u.node):
					u.node.queue_free()
				list.remove_at(i)
		i -= 1


func _think(u: U) -> void:
	if u.data.has("panic_until"):
		if time < float(u.data.panic_until):
			u.think_t = 1.0
			u.target = null
			return
		var pv: Dictionary = u.data.panic_prev
		u.order = pv.order
		u.goal = pv.goal
		u.path = pv.path
		u.path_i = pv.path_i
		u.on_arrive = pv.on_arrive
		u.data.erase("panic_until")
		u.data.erase("panic_prev")
	match u.beh:
		"soldier":
			u.think_t = randf_range(0.6, 1.2)
			var rng: float = u.d.range
			if rng > 0.0:
				if u.target == null or not u.target.alive or (u.target.pos - u.pos).length() > rng * 1.15 or not can_see(u, u.target):
					u.target = _find_target(u, rng)
			if u.data.get("qrf", false):
				_qrf_think(u)
			elif u.cargo.size() > 0 and u.order != "hold":
				var e = _find_target(u, 350.0, false)
				if e != null:
					u.order = "hold"
					dismount(u)
		"zombie":
			u.think_t = randf_range(0.35, 0.7)
			if u.target == null or not u.target.alive or (u.target.pos - u.pos).length() > 120.0:
				u.target = _find_target(u, 220.0, false)
			_flock(u)
		"civ":
			u.think_t = randf_range(1.0, 2.0)
			if u.order == "flee":
				u.data["flee_t"] = float(u.data.get("flee_t", 20.0)) - (u.think_t)
				if float(u.data.flee_t) <= 0.0:
					u.order = "wander"
			elif u.order == "wander" and not u.moving and randf() < 0.3:
				var p2: Vector3 = world.free_spot(Vector2(u.home.x, u.home.z), 90.0)
				u.goal = p2
		"aa":
			u.think_t = 1.0
			_aa(u)
		_:
			u.think_t = 5.0


static func eye(u: U) -> Vector3:
	return u.pos + Vector3(0, u.elev + (2.2 if u.veh else (0.45 if u.prone else 1.6)), 0)


static func body(u: U) -> Vector3:
	return u.pos + Vector3(0, u.elev + (1.4 if u.veh else (0.3 if u.prone else 1.0)), 0)


## Line of sight from a's eyes to b, blocked by terrain and buildings.
func can_see(a: U, b: U) -> bool:
	return world.los(eye(a), body(b))


## Nearest hostile in range that the unit can actually see. need_los false
## is for the infected, who go by sound and smell.
## The infected pull toward each other: a steer toward the middle of the
## others within 120 m (stronger the more there are), and away from any
## standing right on top of them.
func _flock(u: U) -> void:
	if Game.no_flock:
		return
	var sum := Vector3.ZERO
	var n := 0
	var push := Vector3.ZERO
	for v in query(u.pos, 120.0):
		if v == u or not v.alive or v.beh != "zombie":
			continue
		var rel: Vector3 = v.pos - u.pos
		rel.y = 0.0
		var dist := rel.length()
		if dist > 120.0:
			continue
		sum += rel
		n += 1
		if dist < 1.5 and dist > 0.01:
			push -= rel / dist
	if n == 0:
		u.data.erase("flock")
		return
	var pull := (sum / n)
	var w := clampf(n / 4.0, 0.4, 1.0) * clampf(pull.length() / 15.0, 0.0, 1.0)
	u.data["flock"] = pull.normalized() * w * 1.4 + push * 0.5


func _find_target(u: U, rng: float, need_los := true) -> U:
	var cands: Array
	if rng > 450.0:
		cands = list
	else:
		cands = query(u.pos, rng)
	var av: bool = u.d.get("av", false)
	var ranked: Array = []
	var lim := rng * rng
	for v in cands:
		if not v.alive or not hostile(u, v):
			continue
		var d2: float = (v.pos - u.pos).length_squared()
		if d2 > lim:
			continue
		# hiding units (downed crew, SF on an OP) are only found up close
		if v.data.has("hide_r") and d2 > float(v.data.hide_r) * float(v.data.hide_r):
			continue
		if av and v.veh:
			d2 *= 0.3
		ranked.append([d2, v])
	if ranked.is_empty():
		return null
	ranked.sort_custom(func(x, y): return x[0] < y[0])
	if not need_los:
		return ranked[0][1]
	# only the closest few get a sight check, to keep it cheap
	for i in mini(ranked.size(), 5):
		if can_see(u, ranked[i][1]):
			return ranked[i][1]
	return null


func _aa(u: U) -> void:
	if u.supp_t > 0.0 or battle.gunship == null:
		return
	u.aa_t -= 1.0
	var plane: Vector3 = battle.gunship.global_position
	var slant := u.pos.distance_to(plane)
	var kind: String = u.d.aa
	if slant > float(u.d.aa_range):
		return
	if not world.los(u.pos + Vector3(0, 2, 0), plane, false):
		return
	if u.aa_t > 0.0:
		return
	u.aa_t = float(u.d.aa_cd) * randf_range(0.8, 1.5) / aa_mult
	if kind == "aaa":
		battle.ordnance.aaa_burst(u.pos + Vector3(0, 2, 0), slant)
	else:
		battle.ordnance.launch_threat(u.pos + Vector3(0, 2, 0), kind)


func _fight(u: U, dt: float) -> void:
	if u.target == null:
		return
	var t: U = u.target
	if not t.alive:
		u.target = null
		return
	u.fire_t -= dt
	if u.fire_t > 0.0:
		return
	var rng: float = u.d.range
	var dv := t.pos - u.pos
	var dist := dv.length()
	if dist > rng * 1.1:
		return
	# never fire at what you can't see: check the sight line for every shot
	# and drop a target that has gone behind cover
	if not u.d.get("melee", false) and not can_see(u, t):
		u.target = null
		u.think_t = minf(u.think_t, 0.2)
		return
	u.fire_t = 1.0 / float(u.d.rof) * randf_range(0.7, 1.4)
	u.data["shots"] = int(u.data.get("shots", 0)) + 1
	if u.supp_t > 0.0:
		u.fire_t *= 2.5
	if not u.veh:
		u.heading = atan2(-dv.x, -dv.z)
	var acc: float = u.d.acc
	if u.team == 1:
		acc *= acc_mult
	var p := acc * (1.0 - 0.6 * dist / maxf(rng, 1.0))
	if t.order == "hold" and not t.veh and t.beh == "soldier":
		p *= 0.55
	# behind sandbags or a tower's parapet only a head and a rifle show
	if t.prone:
		p *= 0.3
	elif t.elev > 2.0:
		p *= 0.55
	if u.moving:
		p *= 0.6
	if u.d.get("melee", false):
		if randf() < p:
			hurt(t, float(u.d.dmg), false, "")
		return
	var muzzle := u.pos + Vector3(0, 2.0 if u.veh else 1.4, 0)
	var vis: bool = battle.near_view(u.pos)
	if Game.autotest != "":
		audit_shots += 1
		if not can_see(u, t):
			audit_blind += 1
	if u.d.has("explosive"):
		var miss := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * dist * 0.03 * (0.3 if randf() < p else 1.0)
		battle.ordnance.ground_shot(muzzle, t.pos + Vector3(0, 0.6, 0) + miss, u)
	else:
		var hit := randf() < p
		var rec = battle.get("recorder")
		if (vis or rec) and randf() < (0.6 if u.veh else 0.45):
			var aim := t.pos + Vector3(0, 1.0, 0)
			if not hit:
				aim += Vector3(randf_range(-1, 1), randf_range(-0.5, 1.5), randf_range(-1, 1)) * (2.0 + dist * 0.02)
			if rec:
				rec.shot(muzzle, aim, u.team, u.veh)
			if vis:
				battle.effects.tracer(muzzle, aim, Color(2.0, 0.45, 0.25) if u.team == 0 else Color(0.6, 2.0, 0.45), 800.0)
				battle.effects.muzzle(muzzle, 0.5 if not u.veh else 0.8)
		if hit:
			var dam := float(u.d.dmg) * armor_mul(int(u.d.get("pen", 0)), int(t.d.get("armor", 0)))
			hurt(t, dam, false, "")
	if u.order == "assault" and not u.veh and randf() < 0.35:
		u.pause_t = randf_range(2.0, 6.0)
	elif u.order == "assault" and u.veh and dist < rng * 0.7 and randf() < 0.5:
		u.pause_t = randf_range(4.0, 9.0)


func _move(u: U, dt: float) -> void:
	u.vel = Vector3.ZERO
	if u.halted or float(u.d.speed) <= 0.0:
		u.moving = false
		return
	if u.pause_t > 0.0:
		u.pause_t -= dt
		u.moving = false
		return
	var tgt := u.goal
	var run := false
	match u.order:
		"hold":
			u.moving = false
			return
		"move", "convoy", "path":
			if u.path_i >= u.path.size():
				_arrived(u)
				return
			tgt = u.path[u.path_i]
		"flee":
			run = true
		"board":
			run = true
		"assault":
			# close the distance quickly until something is in range
			run = u.target == null and not u.veh and (u.goal - u.pos).length() > 350.0
	var detouring := float(u.data.get("detour_t", 0.0)) > 0.0
	if detouring:
		u.data.detour_t = float(u.data.detour_t) - dt
		tgt = u.data.detour
	if u.beh == "zombie":
		if u.target != null and u.target.alive:
			tgt = u.target.pos
			run = true
		if (tgt - u.pos).length() < float(u.d.range) * 0.8:
			u.moving = false
			return
	var to := tgt - u.pos
	to.y = 0.0
	var d := to.length()
	var arrive := 7.0 if u.veh else 1.5
	if d < arrive and detouring:
		# round the obstacle: back to the route, without skipping waypoints
		u.data.detour_t = 0.0
		return
	if d < arrive:
		if u.order in ["move", "convoy", "path"]:
			u.path_i += 1
			if u.path_i >= u.path.size():
				_arrived(u)
		elif u.beh != "zombie":
			_arrived(u)
		u.moving = false
		return
	if u.order == "convoy" and u.leader != null and u.leader.alive and not u.leader.boarded \
			and u.leader.order == "convoy" and u.leader.path_i >= u.path_i:
		if u.leader.pos.distance_to(u.pos) < 28.0:
			u.moving = false
			return
	if u.elev > 0.0 or u.prone:
		# climb down off the tower or up off the sandbags first
		u.elev = 0.0
		u.prone = false
	var spd: float = float(u.d.get("run", u.d.speed)) if run else float(u.d.speed)
	spd *= u.speed_mul
	if u.supp_t > 0.0 and not u.veh:
		spd *= 0.4
	var dirv := to / d
	if u.beh == "zombie" and d > 40.0 and u.data.has("flock"):
		# drift toward the pack while still heading for the target
		dirv = (dirv + u.data.flock).normalized()
	spd *= slope_factor(u, dirv)
	var np := u.pos + dirv * minf(spd * dt, d)
	if u.climb_t > 0.0:
		u.climb_t -= dt
	else:
		np = world.push_out(np, u.r, u.beh == "zombie")
	np.y = world.height(np.x, np.z)
	if np.y < world.water_level - 0.3:
		u.moving = false
		return
	u.vel = (np - u.pos) / maxf(dt, 0.0001)
	u.pos = np
	var want := atan2(-to.x, -to.z)
	u.heading = lerp_angle(u.heading, want, minf(1.0, dt * (2.5 if u.veh else 8.0)))
	u.moving = true
	# Stuck against a wall or building: people climb over, vehicles back off
	# and go round.
	u.stuck_t += dt
	if u.stuck_t > 3.0:
		var moved := u.pos.distance_to(u.last_pos)
		if moved < spd * 3.0 * 0.3:
			if u.veh:
				var side := Vector3(-to.z, 0, to.x).normalized() * (1.0 if randf() < 0.5 else -1.0)
				u.data["detour"] = u.pos + side * 45.0 - to.normalized() * 15.0
				u.data["detour_t"] = 5.0
			else:
				u.climb_t = 3.0
		u.stuck_t = 0.0
		u.last_pos = u.pos


## Speed on a slope. People follow Tobler's hiking function (fastest on a
## slight downhill, a scramble on steep ground); vehicles labour uphill and
## ease off downhill.
func slope_factor(u: U, dirv: Vector3) -> float:
	var h0: float = world.height(u.pos.x, u.pos.z)
	var h1: float = world.height(u.pos.x + dirv.x * 4.0, u.pos.z + dirv.z * 4.0)
	var g := (h1 - h0) / 4.0
	if u.veh:
		if g > 0.0:
			return clampf(1.0 - g * 3.0, 0.15, 1.0)
		return clampf(1.0 - (-g - 0.08) * 2.0, 0.4, 1.0)
	return clampf(exp(-3.5 * absf(g + 0.05)) / exp(-0.175), 0.12, 1.1)


func _arrived(u: U) -> void:
	var what := u.on_arrive
	u.on_arrive = ""
	match what:
		"dismount":
			dismount(u)
		"escape":
			battle.on_unit_escaped(u)
			return
		"loop":
			u.path_i = 0
			u.on_arrive = "loop"
			return
	if u.beh == "civ" and u.veh:
		# civilian traffic just turns around and drives back
		u.path.reverse()
		u.path_i = 0
		u.on_arrive = ""
		return
	if u.order != "board":
		u.order = "hold"
	u.moving = false


func _pose(u: U, dt: float) -> void:
	var b := Basis(Vector3.UP, u.heading)
	var p := u.pos
	if not u.alive:
		if not u.veh:
			b = b * Basis(Vector3.RIGHT, -PI * 0.5)
			p.y += 0.15
		u.node.transform = Transform3D(b, p)
		return
	if u.veh:
		if u.moving or dt == 0.0:
			var fwd := Vector3(-sin(u.heading), 0, -cos(u.heading))
			var hf: float = world.height(p.x + fwd.x * 2.5, p.z + fwd.z * 2.5)
			var hb: float = world.height(p.x - fwd.x * 2.5, p.z - fwd.z * 2.5)
			var pitch := atan2(hf - hb, 5.0)
			b = b * Basis(Vector3.RIGHT, pitch)
			u.data["pitch"] = pitch
		else:
			b = b * Basis(Vector3.RIGHT, float(u.data.get("pitch", 0.0)))
	elif u.moving:
		# gait: about 1.4 strides a second walking, faster running
		var spd := Vector2(u.vel.x, u.vel.z).length()
		var ph := time * clampf(spd * 2.6, 4.0, 13.0) + u.phase
		p.y += absf(sin(ph)) * 0.04
		b = b * Basis(Vector3.FORWARD, sin(ph) * 0.03)
		u.node.set_instance_shader_parameter("walk", ph)
		if not u.data.get("striding", false):
			u.data["striding"] = true
			u.node.set_instance_shader_parameter("stride", 0.55)
	if not u.veh and not u.moving and u.data.get("striding", false):
		u.data["striding"] = false
		u.node.set_instance_shader_parameter("stride", 0.0)
	if u.beh == "zombie":
		b = b * Basis(Vector3.RIGHT, -0.28 + sin(time * 2.0 + u.phase) * 0.08)
	if u.prone and not u.moving:
		b = b * Basis(Vector3.RIGHT, -PI * 0.5)
		p.y += 0.25
	p.y += u.elev
	if u.d.has("scale"):
		b = b.scaled(Vector3.ONE * float(u.d.scale))
	u.node.transform = Transform3D(b, p)


# --- Helicopters ----------------------------------------------------------

## data: state (inbound, hold, land, wait, depart, gone), lz, exit, alt.
## Sends a helicopter on to the next stop of its route.
func _next_leg(u: U) -> void:
	var leg: Dictionary = u.data.legs.pop_front()
	u.data.leg = leg
	u.data.leg_done = false
	u.data.lz = leg.lz
	u.data.go = false
	u.data.wait_t = 0.0
	u.data.state = "inbound"


func _heli(u: U, dt: float) -> void:
	var st: String = u.data.get("state", "inbound")
	var lz: Vector3 = u.data.get("lz", u.pos)
	var ground: float = world.height(u.pos.x, u.pos.z)
	var target := lz
	var want_alt := 120.0
	var spd := 55.0
	match st:
		"inbound":
			var dl := Vector2(lz.x - u.pos.x, lz.z - u.pos.z).length()
			if u.data.get("hot", false) and not u.data.get("brave", false) and dl < 700.0:
				u.data.state = "hold"
			elif dl < 260.0:
				u.data.state = "land"
		"hold":
			# circle 700 m out until the LZ is cold
			var a := time * 0.08 + u.phase
			target = lz + Vector3(cos(a), 0, sin(a)) * 700.0
			u.data["hold_t"] = float(u.data.get("hold_t", 0.0)) + dt
			if not u.data.get("hot", false):
				u.data.state = "inbound"
			elif float(u.data.hold_t) > 45.0:
				# can't wait for ever: comes in anyway
				u.data["brave"] = true
				u.data.state = "inbound"
				battle.radio("PEDRO 6-6", "We can't hold any longer, coming in hot! Cover us!")
		"land":
			var dl2 := Vector2(lz.x - u.pos.x, lz.z - u.pos.z).length()
			spd = clampf(dl2 * 0.25, 3.0, 40.0)
			want_alt = clampf(dl2 * 0.3, 0.0, 120.0)
			if dl2 < 4.0 and u.pos.y - ground < 1.0:
				u.data.state = "wait"
				u.data["wait_t"] = 0.0
		"wait":
			u.data.wait_t = float(u.data.wait_t) + dt
			want_alt = 0.0
			spd = 0.0
			if u.data.has("pickup"):
				# a lift: called-in troops walk over and climb aboard
				var waiting := 0
				for v in list:
					if v.alive and v.id in u.data.pickup:
						if v.pos.distance_to(u.pos) < 9.0:
							v.boarded = true
							v.alive = false
							v.node.visible = false
						else:
							waiting += 1
							v.order = "board"
							v.goal = u.pos
							v.target = null
				if waiting == 0 or float(u.data.wait_t) > 50.0:
					u.data["go"] = true
			if u.data.has("unload"):
				# an insertion: put the squad on the ground, then leave
				if not u.data.get("unloaded", false):
					u.data["unloaded"] = true
					for k in u.data.unload:
						var p: Vector3 = world.free_spot(Vector2(u.pos.x, u.pos.z) + Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * 12.0, 8.0)
						spawn(k, 0, p, "airmob", {"order": "hold"})
					battle.radio("PALE HORSE 2-1", "Squad's on the ground. Pale Horse lifting.")
				elif float(u.data.wait_t) > 5.0:
					u.data["go"] = true
			if u.data.has("leg") and not u.data.get("leg_done", false):
				u.data["leg_done"] = true
				battle.support.medevac_leg(u, u.data.leg)
				if u.data.leg.op == "home":
					# parks at the outpost; a field hospital off the map is just gone
					u.data.state = "parked" if String(u.data.leg.base) != "" else "depart"
					u.data.erase("leg")
					return
			if u.data.has("leg") and float(u.data.wait_t) > 6.0:
				u.data["go"] = true
			if u.data.get("go", false):
				if u.data.has("legs") and not u.data.legs.is_empty():
					_next_leg(u)
				else:
					u.data.state = "depart"
		"parked":
			want_alt = 0.0
			spd = 0.0
			if u.data.has("legs") and not u.data.legs.is_empty():
				_next_leg(u)
		"depart":
			target = u.data.get("exit", lz + Vector3(4000, 0, 0))
			spd = minf(float(u.data.get("dspd", 5.0)) + dt * 12.0, 60.0)
			u.data["dspd"] = spd
			want_alt = 150.0
			if Vector2(target.x - u.pos.x, target.z - u.pos.z).length() < 100.0:
				u.data.state = "gone"
				u.alive = false
				u.boarded = true
				u.node.visible = false
				return
	var to := Vector3(target.x - u.pos.x, 0, target.z - u.pos.z)
	if to.length() > 1.0 and spd > 0.0:
		var step := to.normalized() * minf(spd * dt, to.length())
		u.pos += step
		u.heading = lerp_angle(u.heading, atan2(-to.x, -to.z), minf(1.0, dt * 1.5))
	var gy: float = world.height(u.pos.x, u.pos.z)
	u.pos.y = move_toward(u.pos.y, gy + want_alt, dt * (25.0 if want_alt > 0.0 else 8.0))
	u.pos.y = maxf(u.pos.y, gy)
	var tilt := clampf(spd / 55.0, 0.0, 1.0) * 0.18
	var b := Basis(Vector3.UP, u.heading) * Basis(Vector3.RIGHT, -tilt)
	u.node.transform = Transform3D(b, u.pos)
	if u.extra:
		for r in u.extra.get_children():
			var spin: Vector3 = r.get_meta("spin")
			r.rotate_object_local(spin.normalized(), dt * 30.0 * spin.length())
