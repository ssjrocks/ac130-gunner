extends Node3D
## One sortie: builds the world and every system, routes events between
## them, keeps score and ends the mission.

const World := preload("res://scripts/world/world.gd")
const Units := preload("res://scripts/battle/units.gd")
const Effects := preload("res://scripts/battle/effects.gd")
const Ordnance := preload("res://scripts/battle/ordnance.gd")
const Gunship := preload("res://scripts/battle/gunship.gd")
const Mission := preload("res://scripts/battle/mission.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Post := preload("res://scripts/ui/post.gd")
const PauseMenu := preload("res://scripts/ui/pause.gd")
const Maps := preload("res://scripts/data/maps.gd")
const Data := preload("res://scripts/data/data.gd")
const UiTheme := preload("res://scripts/ui/theme.gd")
const Support := preload("res://scripts/battle/support.gd")
const Recorder := preload("res://scripts/battle/recorder.gd")

var cfg: Dictionary
var world
var units
var effects
var ordnance
var gunship
var mission
var hud
var post
var pause_menu
var support
var recorder = null
var replay_path := ""
var stats := {"shots": 0, "hits": 0, "kills": 0, "score": 0, "friendly_kills": 0, "civ_kills": 0,
	"inf": 0, "veh": 0, "zombies": 0}
var sf_laser := {}
var ended := false
var built := false
var end_t := 0.0
var time := 0.0
var loading: CanvasLayer
var chatter_t := 0.0
var aaa_msg_t := 0.0


func _init(c := {}) -> void:
	cfg = c


func _ready() -> void:
	loading = CanvasLayer.new()
	loading.layer = 10
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.015, 0.01)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading.add_child(bg)
	var lbl := Label.new()
	lbl.text = "PREPARING SORTIE...\n\n" + String(cfg.get("name", "")).to_upper()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_override("font", UiTheme.mono())
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", UiTheme.FG)
	loading.add_child(lbl)
	add_child(loading)
	await get_tree().process_frame
	await get_tree().process_frame
	_build()


func _build() -> void:
	var t0 := Time.get_ticks_msec()
	var map: Dictionary = Maps.get_map(cfg.get("map", "kharim"))
	world = World.new()
	world.battle = self
	add_child(world)
	world.build(map, cfg.get("time", "day"), cfg.get("weather", "clear"))
	var t1 := Time.get_ticks_msec()
	effects = Effects.new()
	effects.battle = self
	add_child(effects)
	if Game.autotest == "" or Game.record_test:
		recorder = Recorder.new()
		recorder.battle = self
		add_child(recorder)
		effects.recorder = recorder
	units = Units.new()
	units.battle = self
	add_child(units)
	ordnance = Ordnance.new()
	ordnance.battle = self
	add_child(ordnance)
	support = Support.new()
	support.battle = self
	add_child(support)
	mission = Mission.new()
	mission.battle = self
	add_child(mission)
	mission.setup(cfg)
	units.man_posts()
	cfg["focus"] = mission.focus
	gunship = Gunship.new()
	gunship.battle = self
	add_child(gunship)
	gunship.bot = Game.autotest != ""
	gunship.setup(cfg, cfg.get("loadout", ["w_762"]))
	if gunship.bot:
		gunship.auto_flares = true
	post = Post.new()
	add_child(post)
	var hl := CanvasLayer.new()
	hl.layer = 2
	add_child(hl)
	hud = Hud.new()
	hud.battle = self
	hl.add_child(hud)
	pause_menu = PauseMenu.new()
	pause_menu.battle = self
	add_child(pause_menu)
	set_view_mode(0)
	if Game.autotest == "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Sfx.loop("engine", true, -9.0)
	loading.queue_free()
	built = true
	print("battle built: world %d ms, total %d ms, %d buildings, %d units" % [t1 - t0, Time.get_ticks_msec() - t0, world.buildings.size(), units.list.size()])


func set_view_mode(m: int) -> void:
	Game.set_view_mode(m)
	world.apply_view_mode(m)
	post.set_mode(m, world.night)


func radio(who: String, text: String) -> void:
	if recorder:
		recorder.note("radio", [who, text])
	if Game.autotest != "":
		print("[radio %.0f] %s: %s" % [time, who, text])
	if hud:
		hud.radio(who, text)
	Sfx.play("beep", -12.0)


## True when p is close enough to what the sensor is looking at to bother
## drawing small effects there.
func near_view(p: Vector3) -> bool:
	if gunship == null:
		return true
	var r := maxf(500.0, gunship.view_height_m() * 1.6)
	return Vector2(p.x - gunship.aim_point.x, p.z - gunship.aim_point.z).length() < r


## Where laser-guided weapons should go: our own spot first, then the SF's.
func laser_point():
	if gunship and gunship.lasing:
		return gunship.aim_point
	if sf_laser.has("to"):
		var to = sf_laser.to
		if to != null and to.alive:
			return to.pos + Vector3(0, 1.0, 0)
	return null


func on_unit_killed(u, by_player: bool, wid: String) -> void:
	if mission:
		mission.on_unit_killed(u, by_player)
	if not by_player:
		return
	if u.team == 0:
		if u.kind == "wreck":
			return
		if Game.autotest != "":
			print("[ff] %s killed by %s, sensor aim %.0f m away, %s" % [u.kind, wid, u.pos.distance_to(gunship.aim_point), "tracking %s" % gunship.track_unit.kind if gunship.track_unit != null else "no track"])
		stats.friendly_kills += 1
		stats.score -= 500
		radio("JTAC", "CEASE FIRE! CEASE FIRE! You're hitting friendlies!")
		hud.message("FRIENDLY KILLED", 3.0)
		if stats.friendly_kills >= int(cfg.get("max_ff", 6 if cfg.get("type", "") == "zombie" else 3)):
			mission.lose("RELIEVED OF DUTY: FRATRICIDE")
		return
	if u.team == 2:
		stats.civ_kills += 1
		stats.score -= 250
		hud.message("CIVILIAN CASUALTY", 2.5)
		var limit := int(cfg.get("max_civ", 8))
		if stats.civ_kills > limit:
			mission.lose("ROE VIOLATION: TOO MANY CIVILIAN CASUALTIES")
		elif stats.civ_kills == limit:
			radio("COMMAND", "Spectre, you are at the civilian casualty limit. One more and you're done.")
		return
	stats.kills += 1
	stats.score += int(u.d.get("score", 10))
	if u.beh == "zombie":
		stats.zombies += 1
	elif u.veh:
		stats.veh += 1
	else:
		stats.inf += 1
	hud.kill_popup(u)


func on_player_impact(p: Vector3, def: Dictionary, kills: int) -> void:
	if kills > 0:
		stats.hits += 1
	chatter_t -= 1.0
	if kills > 0 and chatter_t <= 0.0 and randf() < 0.5:
		chatter_t = 8.0
		var lines := ["Good hit.", "Direct hit.", "Splash, good effect.", "Target down.", "That's a kill.", "Good rounds."]
		if kills >= 4:
			lines = ["Multiple KIA, good effect on target.", "That got a lot of them.", "Good effect, several down."]
		radio("TV", lines[randi() % lines.size()])


func on_unit_escaped(u) -> void:
	mission.on_escape(u)


func on_missile_launch(m: Dictionary) -> void:
	var rel: Vector3 = m.from - gunship.global_position
	var ang: float = gunship.forward.signed_angle_to(Vector3(rel.x, 0, rel.z).normalized(), Vector3.UP)
	# clock position: 12 ahead, 9 on the left
	var clock := int(round(fposmod(-rad_to_deg(ang), 360.0) / 30.0)) % 12
	if clock == 0:
		clock = 12
	var kind := "SAM" if m.kind == "sam" else "MISSILE"
	hud.warn("%s LAUNCH  %d O'CLOCK" % [kind, clock])
	radio("SCANNER", "%s launch, %d o'clock! %s" % ["SAM" if m.kind == "sam" else "Missile", clock, "Flares! Flares!" if not gunship.auto_flares else "Flares out."])


func on_aaa(from: Vector3) -> void:
	aaa_msg_t -= 1.0
	if aaa_msg_t <= 0.0:
		aaa_msg_t = 25.0
		radio("SCANNER", "Triple-A coming up, %s! Consider climbing." % mission.compass(from - gunship.global_position))


func _process(dt: float) -> void:
	if not built:
		return
	time += dt
	if not ended and mission.state != "running":
		ended = true
		end_t = 0.0
		var won: bool = mission.state == "won"
		Sfx.loop("mg", false)
		Sfx.loop("warn", false)
		hud.banner("MISSION COMPLETE" if won else ("SORTIE ENDED" if mission.state == "ended" else "MISSION FAILED"), mission.result_text)
	if ended:
		end_t += dt
		if end_t > 5.0 and end_t < 100.0:
			end_t = 1000.0
			_finish()
	var warn := false
	for m in ordnance.threats:
		if not m.decoy:
			warn = true
	Sfx.loop("warn", warn and not ended, -8.0)


func _finish() -> void:
	var score: int = stats.score + mission.score_bonus
	if mission.state == "won":
		score += int(cfg.get("xp", 500))
	var result := {
		"cfg": cfg, "state": mission.state, "text": mission.result_text, "stats": stats.duplicate(),
		"score": score, "time": mission.t, "wave": mission.wave, "bonus": mission.score_bonus,
	}
	if Game.autotest != "":
		print("[los audit] %d ground shots, %d without a sight line at the moment of firing" % [units.audit_shots, units.audit_blind])
	if recorder:
		replay_path = recorder.save(result)
		result["replay"] = replay_path
	Sfx.stop_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.finish_mission(result)


func abort() -> void:
	Sfx.stop_all()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.goto_menu("title")


func restart() -> void:
	Sfx.stop_all()
	get_tree().paused = false
	Game.start_mission(cfg)
