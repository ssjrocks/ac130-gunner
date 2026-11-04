extends Node
## Mission logic: places the forces for the chosen mission type, runs
## waves and events, tracks objectives and decides the outcome.

const Maps := preload("res://scripts/data/maps.gd")
const Data := preload("res://scripts/data/data.gd")

var battle
var world
var units
var cfg: Dictionary
var map: Dictionary
var type := "cas"
var state := "running"     # running | won | lost | ended (endless modes)
var result_text := ""
var t := 0.0
var objectives: Array = []
var markers: Array = []
var timer_label := ""
var timer_left := -1.0
var focus := Vector3.ZERO
var site := Vector3.ZERO
var site_label := ""
var level := 1.0
var enemy_mult := 1.0
var wave := 0
var wave_t := 0.0
var phase := 0
var data := {}
var score_bonus := 0
var endless := false
var events: Array = []
var failures := 0
var casualty_t := 0.0
var mark_t := 0.0
var follow_t := 0.0


func setup(c: Dictionary) -> void:
	cfg = c
	world = battle.world
	units = battle.units
	map = Maps.get_map(cfg.get("map", "kharim"))
	type = cfg.get("type", "cas")
	level = float(cfg.get("level", 1.0))
	var diff: Dictionary = Data.DIFFICULTY[clampi(int(cfg.get("difficulty", 1)), 0, 2)]
	enemy_mult = diff.enemy
	units.acc_mult = diff.acc
	units.aa_mult = diff.aa
	match type:
		"range":
			_setup_range()
		"cas":
			_setup_defend()
		"laststand":
			_setup_laststand()
		"zombie":
			_setup_zombie()
		"escort":
			_setup_escort()
		"interdict":
			_setup_interdict()
		"strike":
			_setup_strike()
		"csar":
			_setup_csar()
		"sam":
			_setup_sam()
		"hvt":
			_setup_hvt()
		"survival":
			_setup_survival()
	if type != "range":
		_spawn_civilians(float(cfg.get("civ", 0.4)))
	if type not in ["range", "sam", "survival"]:
		_spawn_aa(int(cfg.get("aa", 0)))
	_update_markers()


# --- Helpers ----------------------------------------------------------------

func P(sname: String) -> Vector3:
	return world.site(sname)


func radio(who: String, text: String) -> void:
	battle.radio(who, text)


func add_obj(text: String) -> int:
	objectives.append({"text": text, "state": 0})
	return objectives.size() - 1


func set_obj(i: int, st: int, text := "") -> void:
	if i < 0 or i >= objectives.size():
		return
	objectives[i].state = st
	if text != "":
		objectives[i].text = text


func win(text: String) -> void:
	if state != "running":
		return
	state = "won"
	result_text = text
	for o in objectives:
		if o.state == 0:
			o.state = 1


func lose(text: String) -> void:
	if state != "running":
		return
	state = "ended" if endless else "lost"
	result_text = text


static func compass(v: Vector3) -> String:
	var a := fposmod(rad_to_deg(atan2(v.x, -v.z)), 360.0)
	var names := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	return names[int(round(a / 45.0)) % 8]


static func meters(d: float) -> String:
	return "%d meters" % (int(round(d / 50.0)) * 50)


## A valid ground point around a centre, at a distance band, near an angle.
func ring_point(center: Vector3, dmin: float, dmax: float, ang := -999.0) -> Vector3:
	for k in 30:
		var a := ang + randf_range(-0.35, 0.35) if ang > -900.0 else randf() * TAU
		var d := randf_range(dmin, dmax)
		var p := Vector2(center.x + sin(a) * d, center.z - cos(a) * d)
		p.x = clampf(p.x, -2950.0, 2950.0)
		p.y = clampf(p.y, -2950.0, 2950.0)
		if world.ground_ok(p):
			return world.to3(p)
	return world.free_spot(Vector2(center.x, center.z), dmax)


func _rand_inf(n: int) -> Array:
	var kinds: Array = []
	for i in n:
		var r := randf()
		kinds.append("emg" if r < 0.15 else ("rpg" if r < 0.3 else "rifle"))
	return kinds


## One enemy wave aimed at goal. Returns the compass names of the directions.
func spawn_wave(L: float, goal: Vector3, group: String, dirs := 2, dmin := 700.0, dmax := 1100.0, base_ang := -999.0) -> Array:
	var armor := int(cfg.get("armor", 1))
	var squads := maxi(1, int(round((1.5 + L * 0.8) * enemy_mult)))
	var techs := int(floor(L * 0.5 * enemy_mult)) if cfg.get("vehicles", true) else 0
	var trucks := int(floor((L - 1.0) * 0.3 * enemy_mult)) if cfg.get("vehicles", true) else 0
	var btrs := int(floor((L - 3.0) * 0.28 * enemy_mult)) if armor >= 1 else 0
	var tanks := int(floor((L - 4.0) * 0.22 * enemy_mult)) if armor >= 2 else 0
	var angs: Array = []
	var base := base_ang if base_ang > -900.0 else randf() * TAU
	for k in dirs:
		angs.append(base + k * TAU / maxf(dirs, 1) + randf_range(-0.3, 0.3))
	var names: Array = []
	for a in angs:
		var n := compass(Vector3(sin(a), 0, -cos(a)))
		if n not in names:
			names.append(n)
	var aa := int(cfg.get("aa", 0))
	for s in squads:
		var a: float = angs[s % angs.size()]
		var from := ring_point(goal, dmin, dmax, a)
		var kinds := _rand_inf(randi_range(5, 9))
		if aa > 0 and randf() < 0.18 * aa:
			kinds.append("manpads")
		units.squad(kinds, 1, from, 18.0, group, {"order": "assault", "goal": goal})
	var vk: Array = []
	for i in techs:
		vk.append("technical")
	for i in trucks:
		vk.append("truck")
	for i in btrs:
		vk.append("btr")
	for i in tanks:
		vk.append("tank")
	for i in vk.size():
		var a2: float = angs[i % angs.size()]
		var from2 := ring_point(goal, dmin + 100.0, dmax + 200.0, a2)
		var kind: String = vk[i]
		var o := {"order": "assault", "goal": goal + Vector3(randf_range(-60, 60), 0, randf_range(-60, 60))}
		if kind == "truck":
			var stop: Vector3 = goal + (from2 - goal).normalized() * 320.0
			o = {"order": "assault", "goal": stop, "cargo": _rand_inf(7), "on_arrive": "dismount", "data": {"goal": goal}}
		units.spawn(kind, 1, from2, group, o)
	return names


func _wave_radio(names: Array, L: float, d: float) -> void:
	var what := "Enemy infantry"
	if L >= 4.0 and cfg.get("armor", 1) >= 1:
		what = "Infantry and armor"
	elif L >= 2.0:
		what = "Infantry and technicals"
	var dirs := " and ".join(PackedStringArray(names))
	radio(cfg.get("jtac", "HAMMER 1-1"), "%s moving in from the %s, %s out!" % [what, dirs, meters(d)])


func _spawn_civilians(dens: float) -> void:
	if dens <= 0.0:
		return
	for tw in world.towns:
		var n := int(dens * float(tw.r) / 9.0)
		var c: Vector2 = tw.pos
		for i in n:
			var p: Vector3 = world.free_spot(c, float(tw.r) * 0.75)
			var u = units.spawn("civ", 2, p, "civ", {"order": "wander", "goal": p})
			u.home = p
	var cars := int(dens * 14.0)
	for i in cars:
		var ri: int = randi() % world.roads.size()
		var pts: Array = world.route_points(ri, randf() < 0.5, randf_range(0.0, 0.6), 1.0)
		if pts.size() < 4:
			continue
		var kind := "car" if randf() < 0.75 else "ctruck"
		var start: Vector3 = pts[0]
		units.spawn(kind, 2, start, "traffic", {"order": "path", "path": pts.duplicate(), "speed_mul": randf_range(0.7, 1.0)})


func _spawn_aa(aa: int) -> void:
	if aa <= 0:
		return
	for i in int(round(aa * 1.5 * enemy_mult)):
		var p := ring_point(focus, 500.0, 1700.0)
		units.squad(["manpads", "rifle", "rifle"], 1, p, 10.0, "aa", {"order": "hold"})
	for i in maxi(0, aa - 1):
		var p2 := ring_point(focus, 700.0, 1600.0)
		units.spawn("zu23", 1, p2, "aa")
		units.squad(["rifle", "rifle", "emg"], 1, p2, 14.0, "aa", {"order": "hold"})


func _friendly_squad(center: Vector3, n: int, spread: float, group: String, vehicles := 0) -> void:
	var kinds: Array = []
	for i in n:
		kinds.append("mg" if i % 5 == 4 else "soldier")
	units.squad(kinds, 0, center, spread, group, {"order": "hold"})
	for i in vehicles:
		units.spawn("humvee", 0, world.free_spot(Vector2(center.x, center.z), spread), group, {"order": "hold"})


func _outpost_r(sname: String) -> float:
	return float(map.get("outposts", {}).get(sname, 40.0)) * 0.35


func _pick(list_key: String, cfg_key: String):
	if cfg.has(cfg_key):
		return cfg[cfg_key]
	var arr: Array = map.get(list_key, [])
	if arr.is_empty():
		return null
	return arr[randi() % arr.size()]


func _heli(lz: Vector3, from_ang := -999.0) -> Object:
	var a := from_ang if from_ang > -900.0 else randf() * TAU
	var start := lz + Vector3(sin(a), 0, -cos(a)) * 3800.0
	start.y = world.height(start.x, start.z) + 140.0
	var exit := lz + Vector3(sin(a + PI * 0.6), 0, -cos(a + PI * 0.6)) * 4500.0
	return units.spawn("heli", 0, start, "heli", {"data": {"state": "inbound", "lz": lz, "exit": exit}, "heading": a + PI})


# --- Range (tutorial) ---------------------------------------------------------

func _setup_range() -> void:
	site = P("range")
	site_label = "RANGE 4"
	focus = site
	for i in 4:
		var p: Vector3 = world.free_spot(Vector2(site.x, site.z), 110.0)
		units.spawn("hulk", 1, p, "hulks", {"tint": Color(0.75, 0.55, 0.4)})
	var loop: Array = world.route_points(1, false, 0.0, 1.0)
	for i in 2:
		var start: Vector3 = loop[i * int(loop.size() / 2)]
		units.spawn("target_truck", 1, start, "trucks", {"order": "path", "path": loop.duplicate(), "on_arrive": "loop", "speed_mul": 0.8})
	data.path = loop
	add_obj("Find RANGE 4 and zoom in (mouse wheel / W S)")
	radio("RANGE", "Spectre 21, Range 4 is hot. Find the target area and zoom in. Mouse wheel or W and S zoom.")
	phase = 0


func _update_range(dt: float) -> void:
	for u in units.members("trucks"):
		if u.order == "hold":
			u.order = "path"
			u.path_i = 0
			u.on_arrive = "loop"
	var g = battle.gunship
	match phase:
		0:
			if g.mag > 6.0 and g.aim_point.distance_to(site) < 450.0:
				set_obj(0, 1)
				add_obj("Destroy the 4 hulks (left mouse fires)")
				radio("RANGE", "Good eye. Four hulks in the impact area. Cleared hot, engage with the minigun.")
				phase = 1
		1:
			var n: int = units.count("hulks")
			set_obj(1, 0, "Destroy the 4 hulks (%d left)" % n)
			if n == 0:
				set_obj(1, 1)
				add_obj("Destroy the 2 moving trucks: lead them, rounds take seconds to land")
				radio("RANGE", "Hulks destroyed. Two trucks running the loop. Your rounds take about five seconds to land, so aim ahead of them, or press C to lock on and the fire-control computer leads the target for you.")
				phase = 2
		2:
			var n2: int = units.count("trucks")
			set_obj(2, 0, "Destroy the 2 moving trucks (%d left)" % n2)
			if n2 == 0:
				radio("RANGE", "Good hits. That's a qualification. Welcome to the squadron, Spectre.")
				win("QUALIFIED ON THE GAU-2/A")


# --- Close air support (defend) ---------------------------------------------

func _setup_defend() -> void:
	var sname: String = _pick("defend", "site")
	site = P(sname)
	site_label = Maps.site_name(map, sname)
	data.site_name = sname
	focus = site
	_friendly_squad(site, int(cfg.get("friendlies", 10)), maxf(_outpost_r(sname), 15.0), "def", int(cfg.get("friendly_vehicles", 1)))
	timer_left = float(cfg.get("duration", 360.0))
	data.duration = timer_left
	data.interval = float(cfg.get("interval", 75.0))
	add_obj("Protect friendly forces at %s" % site_label)
	data.hold = add_obj("Hold until the QRF arrives")
	var names := spawn_wave(level, site, "wave", 1, 500.0, 800.0)
	radio(cfg.get("jtac", "HAMMER 1-1"), "Spectre, Hammer 1-1, troops in contact! Enemy to our %s, %s. We are marked with IR strobes." % [names[0], meters(650.0)])
	wave_t = data.interval * 0.6


func _update_defend(dt: float) -> void:
	timer_left = float(data.duration) - t
	timer_label = "QRF ETA"
	wave_t -= dt
	if wave_t <= 0.0 and timer_left > 40.0:
		wave += 1
		wave_t = float(data.interval)
		var L := level + wave * 0.55
		var names := spawn_wave(L, site, "wave", 1 + int(wave / 2) % 3)
		_wave_radio(names, L, 1100.0)
	if units.count("def") == 0:
		lose("%s WAS OVERRUN" % site_label)
	elif timer_left <= 0.0:
		radio("QRF", "QRF on station. Spectre, outstanding work. We've got it from here.")
		win("POSITION HELD")


# --- Last stand -------------------------------------------------------------

func _setup_laststand() -> void:
	var sname: String = _pick("defend", "site")
	site = P(sname)
	site_label = Maps.site_name(map, sname)
	focus = site
	endless = int(cfg.get("waves", 0)) == 0
	data.zombies = cfg.get("enemy", "insurgents") == "zombies"
	if data.zombies:
		var kinds: Array = []
		for i in int(cfg.get("friendlies", 12)):
			kinds.append("survivor")
		units.squad(kinds, 0, site, maxf(_outpost_r(sname), 12.0), "def", {"order": "hold"})
	else:
		_friendly_squad(site, int(cfg.get("friendlies", 12)), maxf(_outpost_r(sname), 15.0), "def", 1)
	add_obj("Defend %s" % site_label)
	data.wobj = add_obj("Survive the waves")
	phase = 0
	wave_t = 12.0
	radio("BASE", "Spectre, they're massing for an attack on %s. First wave in about ten seconds." % site_label)


func _update_laststand(dt: float) -> void:
	var total := int(cfg.get("waves", 0))
	var zombies: bool = data.zombies
	if units.count("def") == 0:
		lose("%s FELL AFTER %d WAVES" % [site_label, maxi(wave - 1, 0)])
		return
	if phase == 0:
		wave_t -= dt
		timer_label = "WAVE %d IN" % (wave + 1)
		timer_left = wave_t
		if wave_t <= 0.0:
			wave += 1
			phase = 1
			data.wave_start = t
			var L := level + wave * 0.8
			if zombies:
				data.spawned = 0
				data.to_spawn = int((40 + wave * 30) * enemy_mult)
				radio("BASE", "Wave %d! Here they come, %d plus!" % [wave, data.to_spawn])
			else:
				var names := spawn_wave(L, site, "wave", mini(1 + wave / 2, 4))
				data.spawned = units.count("wave")
				_wave_radio(names, L, 1100.0)
	else:
		timer_label = "WAVE %d" % wave
		timer_left = -1.0
		if zombies and int(data.spawned) < int(data.to_spawn):
			data.spawn_acc = float(data.get("spawn_acc", 0.0)) + dt * (6.0 + wave * 2.0)
			while float(data.spawn_acc) >= 1.0 and int(data.spawned) < int(data.to_spawn):
				data.spawn_acc = float(data.spawn_acc) - 1.0
				_zombie_one("wave", 450.0, 900.0, wave >= 3)
				data.spawned = int(data.spawned) + 1
		var left: int = units.count("wave")
		var done := (not zombies or int(data.spawned) >= int(data.to_spawn)) and (left <= maxi(2, int(data.get("spawned", 10)) / 12) or t - float(data.wave_start) > 210.0)
		if done:
			score_bonus += 300 * wave
			set_obj(data.wobj, 0, "Survive the waves (%d survived)" % wave)
			if total > 0 and wave >= total:
				radio("BASE", "That's the last of them. %s holds!" % site_label)
				win("%s HELD - ALL %d WAVES" % [site_label, total])
				return
			phase = 0
			wave_t = 20.0
			radio("BASE", "Wave %d beaten. Reinforcements are coming in, rearm." % wave)
			if units.count("def") < 16:
				var kinds2: Array = ["survivor", "survivor"] if zombies else ["soldier", "soldier"]
				units.squad(kinds2, 0, site, 10.0, "def", {"order": "hold"})


# --- Zombies ----------------------------------------------------------------

func _zombie_one(group: String, dmin: float, dmax: float, brutes: bool) -> void:
	var p := ring_point(site, dmin, dmax, data.get("horde_ang", -999.0))
	var kind := "brute" if brutes and randf() < 0.06 else "zombie"
	var u = units.spawn(kind, 1, p, group, {"order": "assault", "goal": site + Vector3(randf_range(-15, 15), 0, randf_range(-15, 15))})
	u.speed_mul = randf_range(0.7, 1.3)


func _setup_zombie() -> void:
	var sname: String = _pick("defend", "site")
	site = P(sname)
	site_label = Maps.site_name(map, sname)
	focus = site
	var kinds: Array = []
	for i in int(cfg.get("survivors", 12)):
		kinds.append("survivor")
	units.squad(kinds, 0, site, maxf(_outpost_r(sname), 10.0), "surv", {"order": "hold"})
	data.min_surv = int(cfg.get("min_survivors", 3))
	timer_left = float(cfg.get("duration", 420.0))
	data.duration = timer_left
	add_obj("Keep the survivors at %s alive" % site_label)
	data.evac = add_obj("Cover the evacuation (need %d survivors)" % data.min_surv)
	radio("MERCY BASE", "Spectre, this is Mercy Base. We've got %d survivors and they're coming from everywhere. Evac bird is %d minutes out." % [kinds.size(), int(timer_left / 60.0)])
	data.spawn_acc = 0.0
	data.horde_t = 90.0
	for i in int(40 * enemy_mult):
		_zombie_one("z", 250.0, 900.0, false)


func _update_zombie(dt: float) -> void:
	var surv: int = units.count("surv")
	var aboard: int = units.boarded("surv")
	set_obj(0, 0, "Keep the survivors at %s alive (%d left)" % [site_label, surv + aboard])
	if surv + aboard == 0:
		lose("THE SURVIVORS WERE OVERRUN")
		return
	var rate := (2.0 + t / 60.0) * enemy_mult
	var cap := int(340 * enemy_mult)
	if phase < 2 and units.count("z") < cap:
		data.spawn_acc = float(data.spawn_acc) + dt * rate
		while float(data.spawn_acc) >= 1.0:
			data.spawn_acc = float(data.spawn_acc) - 1.0
			data.horde_ang = -999.0
			_zombie_one("z", 450.0, 1000.0, t > 120.0)
	data.horde_t = float(data.horde_t) - dt
	if float(data.horde_t) <= 0.0 and phase < 2:
		data.horde_t = randf_range(80.0, 110.0)
		var a := randf() * TAU
		data.horde_ang = a
		var n := int((60 + t / 4.0) * enemy_mult)
		for i in n:
			_zombie_one("z", 600.0, 900.0, true)
		data.horde_ang = -999.0
		radio("MERCY BASE", "Big horde coming in from the %s! Hundreds of them!" % compass(Vector3(sin(a), 0, -cos(a))))
	timer_left = float(data.duration) - t
	timer_label = "EVAC ETA" if phase == 0 else "EVAC"
	match phase:
		0:
			if timer_left <= 0.0:
				data.heli = _heli(site)
				radio("PEDRO 6-6", "Pedro 6-6 inbound for pickup. Clear the LZ for us, Spectre.")
				phase = 1
		1, 2:
			var h = data.heli
			if h == null or (not h.alive and not h.boarded):
				lose("THE EVAC HELICOPTER WAS LOST")
				return
			var st: String = h.data.get("state", "")
			var hot: bool = units.enemies_near(site, 70.0) >= 6
			h.data["hot"] = hot
			if st == "hold" and int(data.get("hot_msg", 0)) == 0:
				data.hot_msg = 1
				radio("PEDRO 6-6", "LZ is crawling with them, I can't land! Clear it out!")
			if st == "wait":
				if phase == 1:
					phase = 2
					radio("PEDRO 6-6", "Wheels down! Get them on board, move!")
					for u in units.members("surv"):
						u.order = "board"
						u.goal = h.pos
				for u in units.members("surv"):
					if u.order != "board":
						u.order = "board"
						u.goal = h.pos
					if u.pos.distance_to(h.pos) < 9.0:
						u.boarded = true
						u.alive = false
						u.node.visible = false
				if units.count("surv") == 0 or float(h.data.wait_t) > 50.0:
					h.data["go"] = true
			if st == "gone":
				var n: int = units.boarded("surv")
				if n >= int(data.min_surv):
					win("%d SURVIVORS EVACUATED" % n)
				else:
					lose("ONLY %d SURVIVORS MADE IT OUT" % n)


# --- Convoy escort -------------------------------------------------------------

func _setup_escort() -> void:
	var r: Array = _pick("escort", "route")
	var pts: Array = world.route_points(r[0], r[1], r[2], r[3])
	data.pts = pts
	var kinds := ["humvee", "mrap", "humvee", "humvee"]
	var prev = null
	var dir: Vector3 = (pts[0] - pts[1]).normalized()
	for i in kinds.size():
		var p: Vector3 = pts[0] + dir * (i * 32.0)
		var grp := "vip" if kinds[i] == "mrap" else "convoy"
		var u = units.spawn(kinds[i], 0, p, grp, {"order": "convoy", "path": pts, "leader": prev, "heading": atan2(dir.x, dir.z)})
		if grp == "vip":
			data.vip = u
		prev = u
	var end: Vector3 = pts[pts.size() - 1]
	data.end = end
	data.dest = _place_name(end)
	focus = pts[0]
	add_obj("Escort the VIP convoy to %s" % data.dest)
	add_obj("The VIP vehicle (MRAP) must survive")
	var n_amb := 2 + int(level)
	data.ambush = []
	for k in n_amb:
		var f := 0.2 + 0.7 * float(k) / maxf(n_amb - 1, 1)
		var idx := clampi(int(f * pts.size()), 1, pts.size() - 2)
		var p0: Vector3 = pts[idx]
		var fwd: Vector3 = (pts[idx + 1] - pts[idx - 1]).normalized()
		var side := Vector3(-fwd.z, 0, fwd.x) * (1.0 if randf() < 0.5 else -1.0)
		var ap := ring_point(p0 + side * randf_range(150.0, 260.0), 0.0, 40.0)
		var grp2 := "amb%d" % k
		units.squad(_rand_inf(randi_range(7, 11)), 1, ap, 22.0, grp2, {"order": "hold"})
		if level >= 2.0 and randf() < 0.6:
			units.spawn("technical", 1, ring_point(ap, 20.0, 60.0), grp2, {"order": "hold"})
		if int(cfg.get("aa", 0)) > 0 and randf() < 0.4:
			units.spawn("manpads", 1, ap, grp2, {"order": "hold"})
		data.ambush.append({"pos": ap, "group": grp2, "on": false, "side": side})
	data.ied = int(round(0.5 * pts.size())) if level >= 2.0 else -1
	data.halt_t = 0.0
	data.halted = false
	radio("ROADRUNNER 2-6", "Spectre, Roadrunner 2-6. Four vehicles, VIP in the MRAP. Rolling for %s now. Watch the route ahead of us." % data.dest)


func _place_name(p: Vector3) -> String:
	var best := "THE OBJECTIVE"
	var bd := 1.0e9
	for tw in world.towns:
		var d: float = Vector2(p.x, p.z).distance_to(tw.pos)
		if d < bd:
			bd = d
			best = String(tw.name).to_upper()
	if bd > 1200.0:
		return "THE RALLY POINT"
	return best


func _convoy_halt(on: bool) -> void:
	for g in ["convoy", "vip"]:
		for u in units.members(g):
			u.halted = on


func _update_escort(dt: float) -> void:
	var vip = data.vip
	if not vip.alive:
		lose("THE VIP WAS KILLED")
		return
	follow_t -= dt
	if follow_t <= 0.0:
		follow_t = 2.0
		if not battle.gunship.manual_orbit:
			battle.gunship.set_orbit(vip.pos + Vector3(-sin(vip.heading), 0, -cos(vip.heading)) * 300.0, false)
	for a in data.ambush:
		if not a.on and vip.pos.distance_to(a.pos) < 650.0:
			a.on = true
			for u in units.members(a.group):
				u.order = "assault"
				u.goal = vip.pos + Vector3(randf_range(-30, 30), 0, randf_range(-30, 30))
			var rel: Vector3 = a.pos - vip.pos
			radio("ROADRUNNER 2-6", "Contact %s! Ambush, %s!" % [compass(rel), meters(rel.length())])
	if int(data.ied) > 0 and vip.path_i >= int(data.ied) - 2:
		var lead = null
		for u in units.members("convoy"):
			if lead == null or u.path_i > lead.path_i:
				lead = u
		if lead != null:
			battle.ordnance.explode(lead.pos + Vector3(4, 0, 3), {"dmg": 500.0, "radius": 9.0, "pen": 2, "fx": "large"}, false, "")
			radio("ROADRUNNER 2-6", "IED! IED! Lead vehicle is hit, we're stopped!")
			data.halt_t = 12.0
		data.ied = -1
	var near: int = units.enemies_near(vip.pos, 380.0)
	if near >= 3:
		data.halt_t = 6.0
	data.halt_t = float(data.halt_t) - dt
	var h: bool = float(data.halt_t) > 0.0
	if h != data.halted:
		data.halted = h
		_convoy_halt(h)
		if h:
			radio("ROADRUNNER 2-6", "We're halted, taking fire! Spectre, clear the road!")
		else:
			radio("ROADRUNNER 2-6", "Road's clear, Roadrunner rolling.")
	var end: Vector3 = data.end
	if vip.pos.distance_to(end) < 45.0:
		win("CONVOY REACHED %s" % data.dest)
	var rest: float = vip.pos.distance_to(end)
	timer_label = "TO %s" % data.dest
	timer_left = -1.0
	data.dist_left = rest


# --- Convoy interdiction ------------------------------------------------------

func _setup_interdict() -> void:
	var r: Array = _pick("interdict", "route")
	var pts: Array = world.route_points(r[0], r[1], r[2], r[3])
	data.pts = pts
	var kinds: Array = ["technical", "truck", "technical"]
	for i in int(level):
		kinds.append(["truck", "technical", "btr" if level >= 3.0 else "truck", "technical"][i % 4])
	if level >= 5.0:
		kinds.append("tank")
	var prev = null
	var dir: Vector3 = (pts[0] - pts[1]).normalized()
	for i in kinds.size():
		var p: Vector3 = pts[0] + dir * (i * 35.0)
		var o := {"order": "convoy", "path": pts, "leader": prev, "on_arrive": "escape"}
		if kinds[i] == "truck":
			o["cargo"] = _rand_inf(7)
		prev = units.spawn(kinds[i], 1, p, "convoy", o)
	data.total = kinds.size()
	data.escaped = 0
	data.max_escape = int(cfg.get("max_escape", 2))
	data.dest = _place_name(pts[pts.size() - 1])
	data.intel_t = 0.0
	data.intel = pts[0]
	data.dismounted = false
	focus = pts[int(pts.size() * 0.45)]
	data.obj = add_obj("Destroy the enemy convoy (%d vehicles)" % kinds.size())
	add_obj("Fewer than %d may reach %s" % [data.max_escape, data.dest])
	radio("HAMMER 1-1", "Spectre, intel has an enemy convoy, about %d vehicles, moving toward %s. Civilian traffic on that road, check your targets." % [kinds.size(), data.dest])


func _update_interdict(dt: float) -> void:
	var left: int = units.count("convoy")
	var veh_left := 0
	var lead = null
	for u in units.members("convoy"):
		if u.veh:
			veh_left += 1
			if lead == null or u.path_i > lead.path_i:
				lead = u
	set_obj(data.obj, 0, "Destroy the enemy convoy (%d of %d left)" % [veh_left, data.total])
	set_obj(1, 0, "Fewer than %d may reach %s (%d escaped)" % [data.max_escape, data.dest, data.escaped])
	data.intel_t = float(data.intel_t) - dt
	if lead != null and float(data.intel_t) <= 0.0:
		data.intel_t = 15.0
		data.intel = lead.pos + Vector3(randf_range(-120, 120), 0, randf_range(-120, 120))
	if not data.dismounted and veh_left < int(data.total):
		data.dismounted = true
		for u in units.members("convoy"):
			if u.kind == "truck":
				u.order = "hold"
				units.dismount(u)
		radio("HAMMER 1-1", "Good hit! They're scattering, trucks are dismounting.")
	if int(data.escaped) >= int(data.max_escape):
		lose("THE CONVOY GOT THROUGH TO %s" % data.dest)
	elif veh_left == 0:
		win("CONVOY DESTROYED")
	if left > 0 and not battle.gunship.manual_orbit:
		follow_t -= dt
		if follow_t <= 0.0 and lead != null:
			follow_t = 4.0
			battle.gunship.set_orbit(lead.pos, false)


# --- Coordinated strike + exfil ------------------------------------------------

func _setup_strike() -> void:
	var s: Dictionary = _pick("strike", "strike")
	var tp := P(s.target)
	var op := P(s.op)
	data.lz = P(s.lz)
	var hvt = units.spawn("suv", 1, world.free_spot(Vector2(tp.x, tp.z), 10.0), "target", {"paint": "black"})
	data.target = hvt
	units.squad(_rand_inf(int(10 * enemy_mult)), 1, tp, 30.0, "guards", {"order": "hold"})
	for i in 2:
		units.spawn("technical", 1, world.free_spot(Vector2(tp.x, tp.z), 40.0), "guards", {"order": "hold"})
	units.squad(["sf", "sf", "sf", "sf"], 0, op, 6.0, "sf", {"order": "hold"})
	battle.sf_laser = {"from": units.members("sf")[0], "to": hvt}
	data.window = float(cfg.get("window", 150.0))
	focus = tp
	add_obj("Destroy the HVT vehicle VIKING is lasing")
	radio("VIKING 3-1", "Spectre, Viking 3-1. We have eyes on the HVT, black SUV in the compound. Sparkle is on, laser code 1688. He's leaving in about %d minutes." % int(data.window / 60.0 + 0.5))
	radio("VIKING 3-1", "Your laser-guided weapons and strike aircraft can ride our sparkle.")


func _update_strike(dt: float) -> void:
	var sf: Array = units.members("sf")
	var sf_n: int = sf.size() + units.boarded("sf")
	if sf_n == 0:
		lose("VIKING TEAM WAS KILLED")
		return
	var hvt = data.target
	if not sf.is_empty() and battle.sf_laser.size() > 0:
		battle.sf_laser["from"] = sf[0]
	match phase:
		0:
			timer_left = float(data.window) - t
			timer_label = "HVT LEAVES"
			if not hvt.alive:
				_strike_exfil()
			elif timer_left <= 0.0 and hvt.order == "hold":
				var away := ring_point(hvt.pos, 2200.0, 2600.0)
				hvt.order = "path"
				hvt.path = [away]
				hvt.on_arrive = "escape"
				radio("VIKING 3-1", "HVT is moving! He's getting away, hit him now!")
		1:
			timer_label = "EXFIL"
			timer_left = -1.0
			var c: Vector3 = units.centroid("sf")
			var lz: Vector3 = data.lz
			wave_t -= dt
			if wave_t <= 0.0:
				wave += 1
				wave_t = 45.0
				var names := spawn_wave(level + wave * 0.5, c, "pursuit", 2, 600.0, 900.0)
				_wave_radio(names, level, 750.0)
			follow_t -= dt
			if follow_t <= 0.0:
				follow_t = 10.0
				for u in units.members("pursuit"):
					if u.order == "assault":
						u.goal = c + Vector3(randf_range(-30, 30), 0, randf_range(-30, 30))
				if not battle.gunship.manual_orbit:
					battle.gunship.set_orbit(c, false)
			if data.get("heli") == null and c.distance_to(lz) < 60.0:
				data.heli = _heli(lz)
				radio("VIKING 3-1", "At the LZ. Spectre, keep them off us till the bird lands.")
			var h = data.get("heli")
			if h != null:
				if not h.alive and not h.boarded:
					lose("THE EXFIL HELICOPTER WAS LOST")
					return
				h.data["hot"] = units.enemies_near(lz, 200.0) >= 3
				var st: String = h.data.get("state", "")
				if st == "hold" and int(data.get("hot_msg", 0)) == 0:
					data.hot_msg = 1
					radio("PEDRO 6-6", "LZ is hot, I can't come in! Clear it, Spectre!")
				if st == "wait":
					for u in units.members("sf"):
						u.order = "board"
						u.goal = h.pos
						if u.pos.distance_to(h.pos) < 9.0:
							u.boarded = true
							u.alive = false
							u.node.visible = false
					if units.count("sf") == 0:
						h.data["go"] = true
				if st == "gone":
					win("VIKING TEAM EXTRACTED")


func _strike_exfil() -> void:
	phase = 1
	set_obj(0, 1)
	add_obj("Cover VIKING's exfil to the LZ")
	battle.sf_laser = {}
	radio("VIKING 3-1", "Good effect on target! HVT is dead. We're compromised, moving to the LZ.")
	for u in units.members("sf"):
		u.order = "move"
		u.path = [data.lz + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))]
		u.path_i = 0
	for u in units.members("guards"):
		u.order = "assault"
		u.goal = units.centroid("sf")
	wave_t = 20.0
	score_bonus += 1000


# --- CSAR -----------------------------------------------------------------------

func _setup_csar() -> void:
	var c: Dictionary = _pick("csar", "csar")
	var crash := P(c.crash)
	data.lz = P(c.lz)
	site = crash
	site_label = "CRASH SITE"
	units.spawn("wreck", 0, crash, "wreck", {"tint": Color(0.35, 0.33, 0.3)})
	battle.effects.fire(crash + Vector3(0, 2, 0), 3.0, 600.0)
	units.squad(["pilot", "pilot"], 0, crash, 25.0, "pilot", {"order": "hold"})
	timer_left = float(cfg.get("duration", 240.0))
	data.duration = timer_left
	focus = crash
	add_obj("Protect the downed crew (BUSTER 1 and 2)")
	add_obj("Cover the rescue helicopter")
	radio("BUSTER 1", "Mayday, Buster 1, we're down, two of us alive by the wreck! Lots of movement coming our way!")
	radio("SANDY", "Spectre, Pedro is %d minutes out. Keep them alive." % maxi(1, int(timer_left / 60.0)))
	var names := spawn_wave(level, crash, "wave", 2, 700.0, 1100.0)
	wave_t = 55.0


func _update_csar(dt: float) -> void:
	var pil: Array = units.members("pilot")
	if pil.size() + units.boarded("pilot") == 0:
		lose("THE DOWNED CREW WERE KILLED")
		return
	var lz: Vector3 = data.lz
	wave_t -= dt
	if wave_t <= 0.0 and phase < 2:
		wave += 1
		wave_t = 55.0
		var L := level + wave * 0.5
		var names := spawn_wave(L, site, "wave", 2, 800.0, 1200.0)
		_wave_radio(names, L, 1000.0)
	timer_left = float(data.duration) - t
	timer_label = "PEDRO ETA" if phase == 0 else "PICKUP"
	if phase == 0 and timer_left <= 40.0 and not data.get("moved", false):
		data.moved = true
		radio("SANDY", "Buster, move to the LZ now, pickup in forty seconds.")
		for u in pil:
			u.order = "move"
			u.path = [lz + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))]
			u.path_i = 0
	if phase == 0 and timer_left <= 0.0:
		phase = 1
		data.heli = _heli(lz)
		radio("PEDRO 6-6", "Pedro 6-6 inbound. Spectre, sanitize that LZ.")
	if phase >= 1:
		var h = data.heli
		if not h.alive and not h.boarded:
			lose("THE RESCUE HELICOPTER WAS LOST")
			return
		h.data["hot"] = units.enemies_near(lz, 250.0) >= 3
		var st: String = h.data.get("state", "")
		if st == "hold" and int(data.get("hot_msg", 0)) == 0:
			data.hot_msg = 1
			radio("PEDRO 6-6", "Taking fire, the LZ is too hot! Pedro holding off.")
		if st == "wait":
			phase = 2
			for u in units.members("pilot"):
				u.order = "board"
				u.goal = h.pos
				if u.pos.distance_to(h.pos) < 9.0:
					u.boarded = true
					u.alive = false
					u.node.visible = false
			if units.count("pilot") == 0 or float(h.data.wait_t) > 60.0:
				h.data["go"] = true
		if st == "gone":
			win("CREW RESCUED (%d)" % units.boarded("pilot"))


# --- SAM hunt ------------------------------------------------------------------------

func _setup_sam() -> void:
	var spots: Array = map.get("sam", []).duplicate()
	spots.shuffle()
	var n := mini(int(cfg.get("sites", 3)), spots.size())
	data.sites = []
	for i in n:
		var p: Vector3 = world.to3(spots[i])
		units.spawn("sam", 1, p, "launcher", {"heading": randf() * TAU})
		units.spawn("radar", 1, ring_point(p, 25.0, 40.0), "samdef")
		for k in 2:
			units.spawn("zu23", 1, ring_point(p, 50.0, 90.0), "samdef")
		units.squad(_rand_inf(6) + ["manpads"], 1, p, 50.0, "samdef", {"order": "hold"})
		data.sites.append({"pos": p, "guess": p + Vector3(randf_range(-160, 160), 0, randf_range(-160, 160))})
	data.total = n
	for i in int(3 * enemy_mult):
		var a := ring_point(Vector3.ZERO, 300.0, 1800.0)
		units.squad(_rand_inf(6), 1, a, 20.0, "patrol", {"order": "assault", "goal": ring_point(a, 400.0, 900.0)})
	focus = Vector3.ZERO
	data.obj = add_obj("Destroy the SAM launchers (%d)" % n)
	radio("MAGIC", "Spectre, Magic. %d SAM sites are active in your area. Find them and kill the launchers. Use flares, F, when you get a launch warning." % n)


func _update_sam(dt: float) -> void:
	var n: int = units.count("launcher")
	set_obj(data.obj, 0, "Destroy the SAM launchers (%d of %d left)" % [n, data.total])
	if n == 0:
		radio("MAGIC", "All SAM launchers destroyed. Airspace is clear, nice work.")
		win("SAM NETWORK DESTROYED")


# --- HVT hunt -------------------------------------------------------------------

func _setup_hvt() -> void:
	var r: Array = _pick("hvt", "route")
	var pts: Array = world.route_points(r[0], r[1], r[2], r[3])
	var hvt = units.spawn("pickup", 1, pts[0], "hvt", {"order": "path", "path": pts, "on_arrive": "escape", "paint": "white", "speed_mul": 0.75})
	data.hvt = hvt
	var prev = hvt
	var dir: Vector3 = (pts[0] - pts[1]).normalized()
	for i in 2:
		prev = units.spawn("technical", 1, pts[0] + dir * ((i + 1) * 30.0), "escort", {"order": "convoy", "path": pts, "leader": prev, "speed_mul": 0.8})
	for i in 4 + int(level):
		var ri: int = randi() % world.roads.size()
		var dp: Array = world.route_points(ri, randf() < 0.5, randf_range(0.0, 0.5), 1.0)
		if dp.size() > 3:
			units.spawn("pickup", 2, dp[0], "traffic", {"order": "path", "path": dp.duplicate(), "paint": "white", "beh": "civ", "speed_mul": randf_range(0.7, 1.0)})
	data.from = _place_name(pts[0])
	data.dest = _place_name(pts[pts.size() - 1])
	data.start = pts[0]
	focus = pts[int(pts.size() * 0.3)]
	add_obj("Find and destroy the HVT: white pickup with two technicals")
	add_obj("Civilian casualties: %d max" % int(cfg.get("max_civ", 3)))
	radio("HAMMER 1-1", "Spectre, the HVT just left %s heading for %s. White pickup, escorted by two technicals. There are a lot of white pickups out there, positive ID before you engage." % [data.from, data.dest])


func _update_hvt(dt: float) -> void:
	var hvt = data.hvt
	if not hvt.alive and not hvt.boarded:
		radio("HAMMER 1-1", "Target destroyed. Good kill, Spectre.")
		win("HVT ELIMINATED")
	set_obj(1, 0, "Civilian casualties: %d of %d max" % [battle.stats.civ_kills, int(cfg.get("max_civ", 3))])


# --- Survival -----------------------------------------------------------------

func _setup_survival() -> void:
	endless = true
	focus = Vector3.ZERO
	data.next = 5.0
	data.eid = 0
	data.aa_t = 200.0
	data.obj = add_obj("Answer calls for fire. 3 lost positions ends the sortie")
	radio("CROWN", "Spectre, Crown. You're the only gunship up tonight. Stand by for tasking.")


func _new_event() -> void:
	data.eid = int(data.eid) + 1
	var id: int = data.eid
	var p := Vector3.ZERO
	for k in 20:
		var c := Vector2(randf_range(-1900, 1900), randf_range(-1900, 1900))
		if world.ground_ok(c):
			p = world.to3(c)
			break
	var L := level
	var fg := "ev%d_f" % id
	var eg := "ev%d_e" % id
	var conv := randf() < 0.3
	if conv:
		for i in 3:
			units.spawn("humvee", 0, world.free_spot(Vector2(p.x, p.z), 30.0), fg, {"order": "hold"})
		_friendly_squad(p, 3, 15.0, fg)
	else:
		_friendly_squad(p, 6, 18.0, fg)
	spawn_wave(L, p, eg, 1 + int(L / 3.0) % 3, 500.0, 800.0)
	var calls := ["DAGGER", "BLADE", "HAVOC", "RAPTOR", "TITAN", "NOMAD", "WRAITH", "COBRA"]
	var cs: String = "%s %d-%d" % [calls[id % calls.size()], 1 + randi() % 4, 1 + randi() % 6]
	var rel: Vector3 = p - battle.gunship.orbit_center if battle.gunship else p
	events.append({"id": id, "pos": p, "f": fg, "e": eg, "state": 0, "cs": cs, "t0": t})
	radio(cs, "Spectre, %s, %s! %s of your orbit, %s. Need fire now!" % [cs, "convoy under attack" if conv else "troops in contact", compass(rel).capitalize(), meters(rel.length())])
	if not battle.gunship.manual_orbit:
		battle.gunship.set_orbit(p, false)


func _update_survival(dt: float) -> void:
	level = 1.0 + t / 110.0
	data.next = float(data.next) - dt
	var active := 0
	for e in events:
		if e.state == 0:
			active += 1
	if float(data.next) <= 0.0 and active < 3:
		data.next = maxf(30.0, 75.0 - t / 12.0)
		_new_event()
	for e in events:
		if e.state != 0:
			continue
		if units.count(e.f) == 0:
			e.state = 2
			failures += 1
			radio(e.cs, "...")
			radio("CROWN", "We lost %s. That's %d position%s lost." % [e.cs, failures, "" if failures == 1 else "s"])
		elif units.count(e.e) <= 1 and t - float(e.t0) > 20.0:
			e.state = 1
			score_bonus += int(400 * level)
			radio(e.cs, "Enemy is broken, we're good! Thanks, Spectre!")
			for u in units.members(e.e):
				u.order = "flee"
	data.aa_t = float(data.aa_t) - dt
	if float(data.aa_t) <= 0.0:
		data.aa_t = maxf(70.0, 160.0 - t / 10.0)
		if t > 420.0 and randf() < 0.5:
			var p := ring_point(Vector3.ZERO, 300.0, 2000.0)
			units.spawn("sam", 1, p, "aa")
			units.squad(_rand_inf(4), 1, p, 30.0, "aa", {"order": "hold"})
			radio("MAGIC", "Spectre, Magic, new SAM radar is up, %s of center." % compass(p))
		else:
			var p2 := ring_point(battle.gunship.orbit_center, 400.0, 1500.0)
			units.squad(["manpads", "rifle", "rifle"], 1, p2, 10.0, "aa", {"order": "hold"})
	var ok := 0
	for e in events:
		if e.state == 1:
			ok += 1
	set_obj(data.obj, 0, "Calls answered: %d   positions lost: %d of 3" % [ok, failures])
	timer_label = "SORTIE"
	timer_left = -1.0
	if failures >= 3:
		lose("THREE POSITIONS LOST")


# --- Frame ----------------------------------------------------------------

func _process(dt: float) -> void:
	if state != "running":
		return
	t += dt
	casualty_t -= dt
	match type:
		"range":
			_update_range(dt)
		"cas":
			_update_defend(dt)
		"laststand":
			_update_laststand(dt)
		"zombie":
			_update_zombie(dt)
		"escort":
			_update_escort(dt)
		"interdict":
			_update_interdict(dt)
		"strike":
			_update_strike(dt)
		"csar":
			_update_csar(dt)
		"sam":
			_update_sam(dt)
		"hvt":
			_update_hvt(dt)
		"survival":
			_update_survival(dt)
	mark_t -= dt
	if mark_t <= 0.0:
		mark_t = 0.2
		_update_markers()


func on_unit_killed(u, by_player: bool) -> void:
	if u.team == 0 and not by_player and casualty_t <= 0.0 and u.beh != "static":
		casualty_t = 12.0
		var who: String = {"surv": "MERCY BASE", "sf": "VIKING 3-1", "pilot": "BUSTER 1", "convoy": "ROADRUNNER 2-6", "vip": "ROADRUNNER 2-6"}.get(u.group, cfg.get("jtac", "HAMMER 1-1"))
		radio(who, ["Man down! Man down!", "We've got wounded, keep them off us!", "Lost one, Spectre, we need more fire!"][randi() % 3] if not u.veh else "Vehicle hit! We lost a truck!")
	if type == "strike" and u == data.get("target") and phase == 0:
		_strike_exfil()


func on_escape(u) -> void:
	if type == "interdict" and u.group == "convoy" and u.veh:
		data.escaped = int(data.escaped) + 1
		radio("HAMMER 1-1", "A vehicle made it into %s." % data.dest)
	elif type == "hvt" and u.group == "hvt":
		lose("THE HVT REACHED %s" % data.dest)
	elif type == "strike" and u == data.get("target"):
		lose("THE HVT GOT AWAY")
	units.remove_unit(u)


func _update_markers() -> void:
	markers.clear()
	match type:
		"cas", "laststand", "zombie":
			markers.append({"pos": site, "text": site_label, "kind": "friend"})
			var h = data.get("heli")
			if h != null and h.alive:
				markers.append({"pos": h.pos, "text": "EVAC HELO", "kind": "friend"})
		"range":
			markers.append({"pos": site, "text": "RANGE 4", "kind": "obj"})
		"escort":
			var vip = data.vip
			if vip.alive:
				markers.append({"pos": vip.pos, "text": "VIP", "kind": "friend"})
			markers.append({"pos": data.end, "text": data.dest, "kind": "obj"})
		"interdict":
			markers.append({"pos": data.intel, "text": "CONVOY (INTEL)", "kind": "intel", "r": 150.0})
		"strike":
			var hvt = data.target
			if phase == 0 and hvt.alive:
				markers.append({"pos": hvt.pos, "text": "SF LASER", "kind": "enemy"})
			if units.count("sf") > 0:
				markers.append({"pos": units.centroid("sf"), "text": "VIKING", "kind": "friend"})
			if phase == 1:
				markers.append({"pos": data.lz, "text": "LZ", "kind": "obj"})
			var h2 = data.get("heli")
			if h2 != null and h2.alive:
				markers.append({"pos": h2.pos, "text": "PEDRO", "kind": "friend"})
		"csar":
			markers.append({"pos": site, "text": "BUSTER", "kind": "friend"})
			markers.append({"pos": data.lz, "text": "LZ", "kind": "obj"})
			var h3 = data.get("heli")
			if h3 != null and h3.alive:
				markers.append({"pos": h3.pos, "text": "PEDRO", "kind": "friend"})
		"sam":
			for s in data.sites:
				for u in units.query(s.pos, 20.0):
					if u.alive and u.kind == "sam":
						markers.append({"pos": s.guess, "text": "SAM SITE (INTEL)", "kind": "intel", "r": 220.0})
						break
		"hvt":
			if t < 60.0:
				markers.append({"pos": data.start, "text": "HVT LAST SEEN", "kind": "intel", "r": 200.0})
		"survival":
			for e in events:
				if e.state == 0:
					markers.append({"pos": e.pos, "text": e.cs, "kind": "friend"})
