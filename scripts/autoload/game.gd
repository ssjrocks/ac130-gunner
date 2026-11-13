extends Node
## Global state: settings, career save and progression, input bindings,
## sensor view mode and switching between menus and sorties.

const Data := preload("res://scripts/data/data.gd")
const Missions := preload("res://scripts/data/missions.gd")
const CAREER_PATH := "user://career.json"
const SETTINGS_PATH := "user://settings.json"

var settings := {
	"mouse_sens": 1.0, "pad_sens": 1.0, "invert_y": false, "volume": 0.8, "fullscreen": false,
	"iff": true, "shadows": true, "trees": 1.0, "vsync": true, "difficulty": 1, "loadout": "career",
}
var career := {}
var main: Node
var last_result := {}
var view_mode := 0
var autotest := ""
var autotest_secs := 60.0
var no_flock := false        # test flag: --noflock turns infected grouping off


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.global_shader_parameter_add("view_mode", RenderingServer.GLOBAL_VAR_TYPE_INT, 0)
	RenderingServer.global_shader_parameter_add("night", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	RenderingServer.global_shader_parameter_add("scene_light", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest="):
			autotest = a.substr(11)
		elif a == "--noflock":
			no_flock = true
		elif a.begins_with("--secs="):
			autotest_secs = float(a.substr(7))
	_setup_input()
	load_settings()
	load_career()
	if autotest == "":
		apply_settings()


func set_view_mode(m: int) -> void:
	view_mode = m
	RenderingServer.global_shader_parameter_set("view_mode", m)


# --- Screens --------------------------------------------------------------

func start_mission(cfg: Dictionary) -> void:
	var c := cfg.duplicate(true)
	c["loadout"] = loadout_for(c)
	c["difficulty"] = int(c.get("difficulty", settings.difficulty))
	main.start_battle(c)


func goto_menu(screen: String, arg = null) -> void:
	get_tree().paused = false
	main.show_menu(screen, arg)


func finish_mission(result: Dictionary) -> void:
	if autotest != "" and not autotest.begins_with("flow"):
		print("[autotest] RESULT state=%s text=%s score=%d time=%.0f stats=%s" % [result.state, result.text, result.score, result.time, str(result.stats)])
		get_tree().quit()
		return
	last_result = award(result)
	goto_menu("debrief", last_result)


func loadout_for(cfg: Dictionary) -> Array:
	var out: Array
	var mode: String = cfg.get("mode", "campaign")
	if mode != "campaign" and settings.get("loadout", "career") == "all":
		out = Data.all_unlocks()
	else:
		out = unlocked_list()
	for x in cfg.get("loadout_add", []):
		if x not in out:
			out.append(x)
	if cfg.has("only"):
		var only: Array = cfg.only
		out = out.filter(func(x): return x in only or not x.begins_with("w_"))
	return out


# --- Career ---------------------------------------------------------------

func default_career() -> Dictionary:
	return {"xp": 0, "completed": {}, "best": {}, "granted": [], "missions_flown": 0, "kills": 0,
		"survival_best": {}, "laststand_best": {}, "flight_time": 0.0}


func rank_index(xp := -1) -> int:
	if xp < 0:
		xp = int(career.get("xp", 0))
	var r := 0
	for i in Data.RANKS.size():
		if xp >= int(Data.RANKS[i].xp):
			r = i
	return r


func rank() -> Dictionary:
	return Data.RANKS[rank_index()]


func unlocked_list() -> Array:
	var out: Array = []
	var ri := rank_index()
	for i in ri + 1:
		for u in Data.RANKS[i].unlocks:
			if u not in out:
				out.append(u)
	for g in career.get("granted", []):
		if g not in out:
			out.append(g)
	return out


func unlocked(id: String) -> bool:
	return id in unlocked_list()


func campaign_open(i: int) -> bool:
	if i == 0:
		return true
	return career.completed.has(Missions.CAMPAIGN[i - 1].id)


## Works out XP, best scores, rank-ups and unlocks for a finished sortie.
func award(result: Dictionary) -> Dictionary:
	var cfg: Dictionary = result.cfg
	var mode: String = cfg.get("mode", "campaign")
	var diff: Dictionary = Data.DIFFICULTY[clampi(int(cfg.get("difficulty", 1)), 0, 2)]
	var score: int = maxi(0, int(result.score))
	var won: bool = result.state == "won"
	var counts_xp: bool = mode == "campaign" or settings.get("loadout", "career") == "career"
	var xp := 0
	if counts_xp:
		if won:
			xp = int(score * float(diff.xp))
		elif result.state == "ended":
			xp = int(score * 0.6 * float(diff.xp))
		else:
			xp = int(score * 0.25)
	var before := unlocked_list()
	var old_rank := rank_index()
	career.xp = int(career.get("xp", 0)) + xp
	career.missions_flown = int(career.get("missions_flown", 0)) + 1
	career.kills = int(career.get("kills", 0)) + int(result.stats.kills)
	career.flight_time = float(career.get("flight_time", 0.0)) + float(result.time)
	var key: String = cfg.get("id", "sortie")
	var best: Dictionary = career.get("best", {})
	var new_best := score > int(best.get(key, -1))
	if new_best:
		best[key] = score
	career.best = best
	if mode == "campaign" and won:
		career.completed[key] = true
		for g in cfg.get("grants", []):
			if g not in career.granted:
				career.granted.append(g)
	if mode == "survival" or mode == "laststand":
		var bk := "survival_best" if mode == "survival" else "laststand_best"
		var tbl: Dictionary = career.get(bk, {})
		var val: int = int(result.wave) if mode == "laststand" else score
		if val > int(tbl.get(key, 0)):
			tbl[key] = val
		career[bk] = tbl
	save_career()
	var after := unlocked_list()
	var new_unlocks: Array = []
	for u in after:
		if u not in before:
			new_unlocks.append(u)
	var r := result.duplicate()
	r["xp"] = xp
	r["counts_xp"] = counts_xp
	r["new_best"] = new_best
	r["rank_up"] = rank_index() > old_rank
	r["new_unlocks"] = new_unlocks
	return r


func load_career() -> void:
	career = default_career()
	if FileAccess.file_exists(CAREER_PATH):
		var f := FileAccess.open(CAREER_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			for k in d:
				career[k] = d[k]


func save_career() -> void:
	if autotest != "":
		return
	var f := FileAccess.open(CAREER_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(career, "  "))


func reset_career() -> void:
	career = default_career()
	save_career()


# --- Settings -------------------------------------------------------------

func load_settings() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			for k in d:
				settings[k] = d[k]


func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(settings, "  "))


func apply_settings() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.vsync else DisplayServer.VSYNC_DISABLED)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(settings.volume), 0.0001)))


# --- Input map ------------------------------------------------------------

func _act(action: String, events: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
	for e in events:
		InputMap.action_add_event(action, e)


func _k(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _m(b: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = b
	return e


func _jb(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	return e


func _ja(axis: JoyAxis, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = v
	return e


func _setup_input() -> void:
	_act("fire", [_m(MOUSE_BUTTON_LEFT), _ja(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_act("laser", [_m(MOUSE_BUTTON_RIGHT), _ja(JOY_AXIS_TRIGGER_LEFT, 1.0)])
	_act("laser_toggle", [_k(KEY_L)])
	_act("zoom_in", [_k(KEY_W), _ja(JOY_AXIS_LEFT_Y, -1.0)])
	_act("zoom_out", [_k(KEY_S), _ja(JOY_AXIS_LEFT_Y, 1.0)])
	_act("zoom_toggle", [_k(KEY_Z), _jb(JOY_BUTTON_LEFT_STICK)])
	_act("aim_left", [_k(KEY_LEFT), _ja(JOY_AXIS_RIGHT_X, -1.0)])
	_act("aim_right", [_k(KEY_RIGHT), _ja(JOY_AXIS_RIGHT_X, 1.0)])
	_act("aim_up", [_k(KEY_UP), _ja(JOY_AXIS_RIGHT_Y, -1.0)])
	_act("aim_down", [_k(KEY_DOWN), _ja(JOY_AXIS_RIGHT_Y, 1.0)])
	_act("next_weapon", [_k(KEY_E), _jb(JOY_BUTTON_RIGHT_SHOULDER)])
	_act("prev_weapon", [_k(KEY_Q), _jb(JOY_BUTTON_LEFT_SHOULDER)])
	var keys := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6]
	for i in 6:
		_act("weapon_%d" % (i + 1), [_k(keys[i])])
	_act("view_mode", [_k(KEY_V), _jb(JOY_BUTTON_Y)])
	_act("flares", [_k(KEY_F), _jb(JOY_BUTTON_B)])
	_act("track", [_k(KEY_C), _jb(JOY_BUTTON_A)])
	_act("support", [_k(KEY_G), _jb(JOY_BUTTON_X)])
	_act("shift_orbit", [_k(KEY_O), _jb(JOY_BUTTON_RIGHT_STICK)])
	_act("alt_up", [_k(KEY_PAGEUP), _jb(JOY_BUTTON_DPAD_UP)])
	_act("alt_down", [_k(KEY_PAGEDOWN), _jb(JOY_BUTTON_DPAD_DOWN)])
	_act("map", [_k(KEY_TAB), _jb(JOY_BUTTON_BACK)])
	_act("iff", [_k(KEY_I)])
	_act("predictor", [_k(KEY_P), _jb(JOY_BUTTON_DPAD_LEFT)])
	_act("rotate_left", [_k(KEY_COMMA), _ja(JOY_AXIS_LEFT_X, -1.0)])
	_act("rotate_right", [_k(KEY_PERIOD), _ja(JOY_AXIS_LEFT_X, 1.0)])
	_act("help", [_k(KEY_H), _k(KEY_F1)])
	_act("pause", [_k(KEY_ESCAPE), _jb(JOY_BUTTON_START)])
