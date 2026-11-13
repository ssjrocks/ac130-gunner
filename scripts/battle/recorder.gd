extends Node
## Records a sortie for the replay viewer. Units keep a track of keyframes,
## added only when a straight-line guess from the last two would be off (so
## parked trucks and men holding a position cost nothing). Aircraft, missiles
## and the gunship are sampled five times a second, and effects, shots and
## collapsing buildings are logged as they happen. Saved when the sortie ends.

const DIR := "user://replays/"
const TEST_DIR := "user://replays-test/"   # autotests never touch the player's replays
const KEEP := 30
const VERSION := 1
const RATE := 0.2
const KEY_MAX_GAP := 5.0

# Event codes and the number of floats after [t, code].
const EV_IMPACT := 1      # x y z fx water
const EV_FIRE := 2        # x y z size life smoke
const EV_VEHDEAD := 3     # x y z big
const EV_BUILDING := 4    # index
const EV_SHOT := 5        # ax ay az bx by bz team veh
const EV_GSHOT := 6       # ax ay az bx by bz T tank
const EV_SHELL := 7       # ax ay az bx by bz T is762
const EV_TRACER := 8      # ax ay az bx by bz (anti-aircraft)
const EV_ARGS := {1: 5, 2: 6, 3: 4, 4: 1, 5: 8, 6: 8, 7: 8, 8: 6}

# Object types in the 5 Hz samples.
const OB_MISSILE := 1
const OB_BOMB := 2
const OB_THREAT := 3
const OB_FLARE := 4
const OB_A10 := 5
const OB_F18 := 6
const OB_ILLUM := 7

var battle
var t := 0.0
var next_t := 0.0
var ev := PackedFloat32Array()
var misc: Array = []          # [t, kind, args] for rare events (radio, dust puffs)
var fx_names: Array = []
var units := {}               # id -> {kind, team, mesh, scale, heat, track}
var _last := {}               # id -> [t, pos, heading, flags, vel]
var frames := PackedFloat32Array()   # per sample: t, n, gunship(9), then n * (rid type x y z yaw pitch)
var next_rid := 1


func _process(_dt: float) -> void:
	if battle == null or not battle.built:
		return
	t = battle.time
	if t >= next_t:
		next_t = t + RATE
		_sample_units()
		_sample_frame()


# --- Events -----------------------------------------------------------------

func _ev(code: int, args: Array) -> void:
	ev.append(t)
	ev.append(code)
	for a in args:
		ev.append(float(a))


func impact(p: Vector3, fx: String, water: bool) -> void:
	var i := fx_names.find(fx)
	if i < 0:
		fx_names.append(fx)
		i = fx_names.size() - 1
	_ev(EV_IMPACT, [p.x, p.y, p.z, i, 1 if water else 0])


func fire(p: Vector3, size: float, life: float, smoke: bool) -> void:
	_ev(EV_FIRE, [p.x, p.y, p.z, size, life, 1 if smoke else 0])


func vehicle_destroyed(p: Vector3, big: bool) -> void:
	_ev(EV_VEHDEAD, [p.x, p.y, p.z, 1 if big else 0])


func building(bi: int) -> void:
	_ev(EV_BUILDING, [bi])


func shot(a: Vector3, b: Vector3, team: int, veh: bool) -> void:
	_ev(EV_SHOT, [a.x, a.y, a.z, b.x, b.y, b.z, team, 1 if veh else 0])


func ground_shot(a: Vector3, b: Vector3, tt: float, tank: bool) -> void:
	_ev(EV_GSHOT, [a.x, a.y, a.z, b.x, b.y, b.z, tt, 1 if tank else 0])


func shell(a: Vector3, b: Vector3, tt: float, wid: String) -> void:
	_ev(EV_SHELL, [a.x, a.y, a.z, b.x, b.y, b.z, tt, 1 if wid == "w_762" else 0])


func tracer(a: Vector3, b: Vector3) -> void:
	_ev(EV_TRACER, [a.x, a.y, a.z, b.x, b.y, b.z])


func note(kind: String, args: Array) -> void:
	misc.append([t, kind, args])


# --- Samples ----------------------------------------------------------------

func _flags(u) -> int:
	var f := 0
	if u.alive:
		f |= 1
	if u.node.visible and not u.boarded:
		f |= 2
	if u.moving:
		f |= 4
	return f


func _sample_units() -> void:
	var present := {}
	for u in battle.units.list:
		present[u.id] = true
		var pitch: float = float(u.data.get("pitch", 0.0)) if u.veh else 0.0
		var fl := _flags(u)
		if not units.has(u.id):
			units[u.id] = {"kind": u.kind, "team": u.team, "mesh": u.mesh_id, "scale": float(u.d.get("scale", 1.0)),
				"track": PackedFloat32Array()}
			_key(u, pitch, fl, Vector3.ZERO)
			continue
		var l: Array = _last[u.id]
		var dt: float = t - float(l[0])
		var guess: Vector3 = l[1] + l[4] * dt
		if fl != l[3] or dt >= KEY_MAX_GAP or guess.distance_to(u.pos) > 0.6 or absf(angle_difference(l[2], u.heading)) > 0.15:
			var vel: Vector3 = (u.pos - l[1]) / maxf(dt, 0.001)
			_key(u, pitch, fl, vel if fl & 4 else Vector3.ZERO)
	# units cleaned up or flown off the map: a last key that hides them
	for id in _last:
		var l: Array = _last[id]
		if not present.has(id) and l[3] != -1:
			var tr: PackedFloat32Array = units[id].track
			var o := tr.size() - 7
			tr.append_array(PackedFloat32Array([t, tr[o + 1], tr[o + 2], tr[o + 3], tr[o + 4], tr[o + 5], int(tr[o + 6]) & 1]))
			units[id].track = tr
			l[3] = -1


func _key(u, pitch: float, fl: int, vel: Vector3) -> void:
	var tr: PackedFloat32Array = units[u.id].track
	tr.append_array(PackedFloat32Array([t, u.pos.x, u.pos.y, u.pos.z, u.heading, pitch, fl]))
	units[u.id].track = tr
	_last[u.id] = [t, u.pos, u.heading, fl, vel]


func _rid(d: Dictionary) -> int:
	if not d.has("rid"):
		d["rid"] = next_rid
		next_rid += 1
	return d.rid


func _sample_frame() -> void:
	var objs := PackedFloat32Array()
	var n := 0
	var o = battle.ordnance
	for g in o.guided:
		var ty := OB_ILLUM if g.kind == "illum" else (OB_BOMB if g.kind == "bomb" else OB_MISSILE)
		if ty == OB_ILLUM:
			continue
		var p: Vector3 = g.pos
		objs.append_array(PackedFloat32Array([_rid(g), ty, p.x, p.y, p.z, 0, 0]))
		n += 1
	for it in o.illum:
		var y := lerpf(550.0, 60.0, it.t / it.life)
		var p: Vector3 = it.p + Vector3.UP * y + Vector3(sin(it.t * 0.05) * 30.0, 0.0, it.t * 0.6)
		objs.append_array(PackedFloat32Array([_rid(it), OB_ILLUM, p.x, p.y, p.z, it.t / it.life, 0]))
		n += 1
	for m in o.threats:
		var p: Vector3 = m.pos
		objs.append_array(PackedFloat32Array([_rid(m), OB_FLARE if m.get("decoy", false) else OB_THREAT, p.x, p.y, p.z, 0, 0]))
		n += 1
	for r in battle.support.runs:
		var nd: Node3D = r.node
		var e: Vector3 = nd.global_transform.basis.get_euler()
		var p := nd.global_position
		objs.append_array(PackedFloat32Array([_rid(r), OB_A10 if r.kind == "gunrun" else OB_F18, p.x, p.y, p.z, e.y, e.x]))
		n += 1
	var g = battle.gunship
	var gp: Vector3 = g.global_position
	frames.append_array(PackedFloat32Array([t, n, gp.x, gp.y, gp.z, g.forward.x, g.forward.z,
		g.aim_point.x, g.aim_point.y, g.aim_point.z, g.mag]))
	frames.append_array(objs)


# --- Saving -----------------------------------------------------------------

func save(result: Dictionary) -> String:
	_sample_units()
	var cfg: Dictionary = battle.cfg.duplicate(true)
	cfg.erase("focus")
	var data := {
		"version": VERSION, "game": ProjectSettings.get_setting("application/config/version", ""),
		"date": Time.get_datetime_string_from_system(false, true), "cfg": cfg,
		"result": {"state": result.state, "text": result.text, "score": result.score, "time": result.time},
		"length": t, "units": units, "frames": frames, "events": ev, "fx": fx_names, "misc": misc,
	}
	var dir := dir_path()
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "").replace("-", "").replace("T", "-")
	var path := dir + "%s_%s.rep" % [stamp, String(cfg.get("id", cfg.get("map", "sortie"))).validate_filename()]
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return ""
	f.store_var(data)
	f.close()
	var info := {"name": cfg.get("name", ""), "map": cfg.get("map", ""), "date": data.date, "length": t, "result": data.result, "game": data.game}
	var fi := FileAccess.open(path + ".json", FileAccess.WRITE)
	if fi:
		fi.store_string(JSON.stringify(info))
	_prune()
	return path


static func dir_path() -> String:
	return TEST_DIR if Game.autotest != "" else DIR


static func list() -> Array:
	var out: Array = []
	var dir := dir_path()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for fn in d.get_files():
		if fn.ends_with(".rep"):
			out.append(dir + fn)
	out.sort()
	out.reverse()
	return out


## The small summary saved next to a replay, for listing without loading it.
static func summary(path: String) -> Dictionary:
	var f := FileAccess.open(path + ".json", FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


static func load_file(path: String) -> Dictionary:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var d = f.get_var()
	return d if d is Dictionary and int(d.get("version", 0)) == VERSION else {}


func _prune() -> void:
	var all := list()
	for i in range(KEEP, all.size()):
		DirAccess.remove_absolute(all[i])
		DirAccess.remove_absolute(all[i] + ".json")
