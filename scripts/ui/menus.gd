extends Control
## Menus: title, campaign, skirmish, survival, last stand, career,
## settings, controls and the debrief after a sortie.

const UiTheme := preload("res://scripts/ui/theme.gd")
const Data := preload("res://scripts/data/data.gd")
const Missions := preload("res://scripts/data/missions.gd")
const Maps := preload("res://scripts/data/maps.gd")

const BG_SHADER := """
shader_type canvas_item;
float h(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float vn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), u.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), u.x), u.y); }
void fragment() {
	vec2 uv = UV;
	vec2 q = uv * vec2(7.0, 4.0) + vec2(TIME * 0.015, TIME * 0.004);
	float n = vn(q) * 0.5 + vn(q * 2.1) * 0.3 + vn(q * 4.3) * 0.2;
	float blobs = smoothstep(0.62, 0.66, vn(uv * vec2(60.0, 34.0) + vec2(TIME * 0.12, 0.0))) * 0.18;
	vec3 c = vec3(0.02, 0.05, 0.03) + vec3(0.05, 0.12, 0.06) * n + vec3(0.15, 0.3, 0.16) * blobs * n;
	float g = step(0.997, fract(uv.x * 24.0)) + step(0.995, fract(uv.y * 13.5));
	c += vec3(0.02, 0.05, 0.03) * g;
	c += (h(FRAGCOORD.xy + fract(TIME) * 100.0) - 0.5) * 0.03;
	vec2 d = uv - 0.5;
	c *= 1.0 - dot(d, d) * 1.2;
	COLOR = vec4(c, 1.0);
}
"""

var body: Control
var screen := ""
var sel_mission := 0
var brief_label: RichTextLabel
var launch_btn: Button
var update_box: HBoxContainer
var opts := {"map": 0, "type": 0, "time": 0, "diff": 1, "zombies": false}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BG_SHADER
	m.shader = sh
	bg.material = m
	add_child(bg)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Updater.changed.connect(_refresh_update)
	opts.diff = int(Game.settings.get("difficulty", 1))


func show_screen(sname: String, arg = null) -> void:
	screen = sname
	if body:
		body.queue_free()
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, 70)
	add_child(mc)
	body = mc
	match sname:
		"campaign":
			_campaign()
		"skirmish":
			_skirmish()
		"survival":
			_survival()
		"laststand":
			_laststand()
		"career":
			_career()
		"settings":
			_settings()
		"controls":
			_controls()
		"debrief":
			_debrief(arg if arg != null else Game.last_result)
		_:
			_title()
	_focus_first(body)


func _focus_first(n: Node) -> void:
	await get_tree().process_frame
	if not is_instance_valid(n):
		return
	var b := _find_button(n)
	if b:
		b.grab_focus()


func _find_button(n: Node) -> Button:
	for c in n.get_children():
		if c is Button and not c.disabled and c.visible:
			return c
		var r := _find_button(c)
		if r:
			return r
	return null


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("ui_cancel") and screen != "title" and screen != "debrief":
		_back()
		get_viewport().set_input_as_handled()


func _back() -> void:
	if screen == "settings":
		Game.save_settings()
	show_screen("title")


# --- Builders ---------------------------------------------------------------

func _vbox(parent: Node, sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	parent.add_child(v)
	return v


func _hbox(parent: Node, sep := 16) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	parent.add_child(h)
	return h


func _label(parent: Node, text: String, size := 20, col := UiTheme.FG) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l


func _button(parent: Node, text: String, cb: Callable, w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 46)
	b.pressed.connect(func(): Sfx.play("click", -6.0))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _option(parent: Node, items: Array, selected: int, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.selected = clampi(selected, 0, items.size() - 1)
	o.custom_minimum_size = Vector2(380, 44)
	o.item_selected.connect(cb)
	parent.add_child(o)
	return o


func _header(parent: Node, text: String) -> void:
	var h := _hbox(parent)
	_button(h, "< BACK", _back, 140)
	var l := _label(h, text, 40)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _grid(parent: Node) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 24)
	g.add_theme_constant_override("v_separation", 12)
	parent.add_child(g)
	return g


func _rank_line() -> String:
	var r: Dictionary = Game.rank()
	var ri := Game.rank_index()
	var xp := int(Game.career.get("xp", 0))
	var nxt := ""
	if ri + 1 < Data.RANKS.size():
		nxt = "   next: %s at %d XP" % [Data.RANKS[ri + 1].abbr, int(Data.RANKS[ri + 1].xp)]
	return "%s %s   XP %d%s" % [r.abbr, String(r.name).to_upper(), xp, nxt]


# --- Title --------------------------------------------------------------------

func _title() -> void:
	var v := _vbox(body, 14)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	v.add_child(spacer)
	_label(v, "AC-130 GUNNER", 72)
	_label(v, "SENSOR OPERATOR  //  SPECTRE 21", 22, UiTheme.DIM)
	_label(v, _rank_line(), 20, UiTheme.ACCENT)
	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0, 20)
	v.add_child(sp2)
	var col := _vbox(v, 10)
	col.custom_minimum_size = Vector2(420, 0)
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_button(col, "CAMPAIGN", func(): show_screen("campaign"))
	_button(col, "SKIRMISH", func(): show_screen("skirmish"))
	_button(col, "SURVIVAL", func(): show_screen("survival"))
	_button(col, "LAST STAND", func(): show_screen("laststand"))
	_button(col, "CAREER", func(): show_screen("career"))
	_button(col, "SETTINGS", func(): show_screen("settings"))
	_button(col, "CONTROLS", func(): show_screen("controls"))
	_button(col, "QUIT", func(): get_tree().quit())
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fill)
	update_box = _hbox(v)
	_refresh_update()


func _refresh_update() -> void:
	if update_box == null or not is_instance_valid(update_box):
		return
	for c in update_box.get_children():
		c.queue_free()
	var txt := "v%s" % Updater.current_version()
	match Updater.status:
		"checking":
			txt += "   checking for updates..."
		"current":
			txt += "   up to date"
		"available":
			txt += "   UPDATE AVAILABLE: v%s" % Updater.latest
		"downloading":
			txt += "   downloading v%s  %d%%" % [Updater.latest, int(Updater.progress * 100.0)]
		"ready":
			txt += "   v%s installed" % Updater.latest
		"error":
			txt += "   update: %s" % Updater.error
	_label(update_box, txt, 16, UiTheme.ACCENT if Updater.status in ["available", "ready"] else UiTheme.DIM)
	if Updater.status == "available":
		_button(update_box, "INSTALL UPDATE", func(): Updater.install(), 220)
	elif Updater.status == "ready":
		_button(update_box, "RESTART NOW", func(): Updater.restart(), 200)
	elif Updater.status in ["error", "current"]:
		_button(update_box, "CHECK AGAIN", func(): Updater.check(), 180)


# --- Campaign -----------------------------------------------------------------

func _campaign() -> void:
	var v := _vbox(body, 16)
	_header(v, "CAMPAIGN")
	_label(v, _rank_line(), 18, UiTheme.ACCENT)
	var h := _hbox(v, 24)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(scroll)
	var list := _vbox(scroll, 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var last_ch := -1
	var first_open := 0
	for i in Missions.CAMPAIGN.size():
		var m: Dictionary = Missions.CAMPAIGN[i]
		if int(m.chapter) != last_ch:
			last_ch = int(m.chapter)
			_label(list, "%d. %s" % [last_ch + 1, Missions.CHAPTERS[last_ch]], 18, UiTheme.DIM)
		var open := Game.campaign_open(i)
		var done: bool = Game.career.completed.has(m.id)
		var tag := "  [DONE]" if done else ("" if open else "  [LOCKED]")
		var b := _button(list, "  %02d  %s%s" % [i + 1, String(m.name).to_upper(), tag], _select_mission.bind(i))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not open
		if open:
			first_open = i
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	var rv := _vbox(right, 14)
	brief_label = RichTextLabel.new()
	brief_label.bbcode_enabled = true
	brief_label.fit_content = false
	brief_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(brief_label)
	var row := _hbox(rv)
	_label(row, "DIFFICULTY", 18)
	_option(row, ["RECRUIT", "REGULAR", "VETERAN"], opts.diff, func(i): opts.diff = i)
	launch_btn = _button(rv, "LAUNCH SORTIE", _launch_campaign)
	_select_mission(first_open)


func _select_mission(i: int) -> void:
	sel_mission = i
	var m: Dictionary = Missions.CAMPAIGN[i]
	var mp: Dictionary = Maps.get_map(m.map)
	var t := "[font_size=34]%s[/font_size]\n" % String(m.name).to_upper()
	t += "[color=#6f9e72]%s  -  %s  -  %s[/color]\n\n" % [Missions.TYPE_NAMES.get(m.type, m.type).to_upper(), mp.name, String(m.time).to_upper()]
	t += "%s\n\n" % m.brief
	var lo: Array = Game.loadout_for(Missions.campaign_cfg(i))
	var ws: Array = []
	for w in Data.WEAPON_ORDER:
		if w in lo:
			ws.append(Data.WEAPONS[w].short)
	t += "[color=#ffd15a]WEAPONS[/color]  %s\n" % ", ".join(PackedStringArray(ws))
	var sensors := ["TV"]
	if "v_nv" in lo:
		sensors.append("NV")
	if "v_ir" in lo:
		sensors.append("THERMAL")
	var mag := 25
	if "o_150" in lo:
		mag = 150
	elif "o_60" in lo:
		mag = 60
	t += "[color=#ffd15a]SENSORS[/color]  %s, up to %dx\n" % [" / ".join(PackedStringArray(sensors)), mag]
	var sup: Array = []
	for s in m.get("supports", {}):
		if s in lo:
			sup.append("%s x%d" % [Data.SUPPORT[s].short, int(m.supports[s])])
	if not sup.is_empty():
		t += "[color=#ffd15a]SUPPORT[/color]  %s\n" % ", ".join(PackedStringArray(sup))
	var grants: Array = []
	for g in m.get("grants", []):
		grants.append(Data.UNLOCK_NAMES.get(g, g))
	if not grants.is_empty():
		t += "\n[color=#6fc8ff]COMPLETING THIS QUALIFIES YOU ON: %s[/color]\n" % ", ".join(PackedStringArray(grants))
	var best = Game.career.get("best", {}).get(m.id)
	if best != null:
		t += "\nBEST SCORE  %d" % int(best)
	brief_label.text = t


func _launch_campaign() -> void:
	var c := Missions.campaign_cfg(sel_mission)
	c["difficulty"] = opts.diff
	Game.start_mission(c)


# --- Skirmish, survival, last stand ---------------------------------------------

func _map_names() -> Array:
	var out: Array = []
	for id in Maps.ORDER:
		out.append(Maps.MAPS[id].name)
	return out


func _common_opts(g: GridContainer) -> void:
	_label(g, "MAP")
	_option(g, _map_names(), opts.map, _on_map)
	_label(g, "TIME OF DAY")
	_option(g, ["DAY", "DUSK", "NIGHT"], opts.time, func(i): opts.time = i)
	_label(g, "DIFFICULTY")
	_option(g, ["RECRUIT", "REGULAR", "VETERAN"], opts.diff, func(i): opts.diff = i)
	_label(g, "WEAPONS")
	_option(g, ["CAREER UNLOCKS (EARNS XP)", "EVERYTHING (NO XP)"], 1 if Game.settings.get("loadout", "career") == "all" else 0, func(i): Game.settings.loadout = "all" if i == 1 else "career")


var desc_label: Label


func _on_map(i: int) -> void:
	opts.map = i
	_refresh_desc()


func _on_zombies(i: int) -> void:
	opts.zombies = i == 1
	_refresh_desc()


func _on_difficulty(i: int) -> void:
	Game.settings.difficulty = i
	opts.diff = i


func _extra_skirmish(g: GridContainer) -> void:
	var names: Array = []
	for t in Missions.SKIRMISH_TYPES:
		names.append(String(Missions.TYPE_NAMES[t]).to_upper())
	_label(g, "MISSION")
	_option(g, names, opts.type, func(i): opts.type = i)


func _extra_laststand(g: GridContainer) -> void:
	_label(g, "ENEMY")
	_option(g, ["INSURGENTS", "ZOMBIES"], 1 if opts.zombies else 0, _on_zombies)


func _refresh_desc() -> void:
	if desc_label and is_instance_valid(desc_label):
		var mp: Dictionary = Maps.MAPS[Maps.ORDER[opts.map]]
		var txt: String = mp.desc
		if screen == "survival":
			txt += "\n\nBEST SCORE HERE: %d" % int(Game.career.get("survival_best", {}).get("survival_" + Maps.ORDER[opts.map], 0))
		elif screen == "laststand":
			var key := "laststand_%s_%s" % [Maps.ORDER[opts.map], "z" if opts.zombies else "i"]
			txt += "\n\nMOST WAVES HERE: %d" % int(Game.career.get("laststand_best", {}).get(key, 0))
		desc_label.text = txt


func _mode_screen(title: String, intro: String, extra: Callable, launch: Callable) -> void:
	var v := _vbox(body, 16)
	_header(v, title)
	_label(v, intro, 18, UiTheme.DIM).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var g := _grid(v)
	extra.call(g)
	_common_opts(g)
	desc_label = _label(v, "", 18)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(900, 0)
	_refresh_desc()
	var b := _button(v, "LAUNCH", launch, 300)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


func _skirmish() -> void:
	_mode_screen("SKIRMISH", "Pick a battlefield and a mission type. Forces and targets are placed fresh every time.",
		_extra_skirmish,
		func(): Game.start_mission(Missions.skirmish_cfg(Maps.ORDER[opts.map], Missions.SKIRMISH_TYPES[opts.type], Missions.TIMES[opts.time], opts.diff)))


func _survival() -> void:
	_mode_screen("SURVIVAL", "Endless sortie. Calls for fire come in from all over the map and the air defences grow. Lose three friendly positions, or the aircraft, and it's over.",
		func(_g): pass,
		func(): Game.start_mission(Missions.survival_cfg(Maps.ORDER[opts.map], Missions.TIMES[opts.time], opts.diff)))


func _laststand() -> void:
	_mode_screen("LAST STAND", "Hold one position against endless waves that keep getting stronger. How many can you survive?",
		_extra_laststand,
		func(): Game.start_mission(Missions.laststand_cfg(Maps.ORDER[opts.map], Missions.TIMES[opts.time], opts.diff, opts.zombies)))


# --- Career -------------------------------------------------------------------

func _career() -> void:
	var v := _vbox(body, 12)
	_header(v, "CAREER")
	var ri := Game.rank_index()
	var r: Dictionary = Data.RANKS[ri]
	_label(v, "%s  %s" % [r.abbr, String(r.name).to_upper()], 30, UiTheme.ACCENT)
	var xp := int(Game.career.get("xp", 0))
	if ri + 1 < Data.RANKS.size():
		var lo := int(r.xp)
		var hi := int(Data.RANKS[ri + 1].xp)
		var pb := ProgressBar.new()
		pb.min_value = lo
		pb.max_value = hi
		pb.value = xp
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(700, 20)
		pb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		v.add_child(pb)
		_label(v, "XP %d / %d to %s" % [xp, hi, String(Data.RANKS[ri + 1].name).to_upper()], 17)
	else:
		_label(v, "XP %d   (highest rank)" % xp, 17)
	var c: Dictionary = Game.career
	var ft := int(c.get("flight_time", 0.0))
	_label(v, "SORTIES %d    CONFIRMED KILLS %d    TIME ON STATION %dh %02dm    CAMPAIGN %d / %d" % [
		int(c.get("missions_flown", 0)), int(c.get("kills", 0)), ft / 3600, (ft / 60) % 60, c.completed.size(), Missions.CAMPAIGN.size()], 17, UiTheme.DIM)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var list := _vbox(scroll, 4)
	var have := Game.unlocked_list()
	for i in Data.RANKS.size():
		var rk: Dictionary = Data.RANKS[i]
		_label(list, "%-6s %-24s %6d XP" % [rk.abbr, String(rk.name).to_upper(), int(rk.xp)], 18, UiTheme.ACCENT if i <= ri else UiTheme.DIM)
		for u in rk.unlocks:
			var ok: bool = u in have
			_label(list, "        %s %s" % ["[X]" if ok else "[ ]", Data.UNLOCK_NAMES.get(u, u)], 17, UiTheme.FG if ok else UiTheme.DIM)
	_label(list, "\nCampaign missions also qualify you on equipment early.", 16, UiTheme.DIM)
	var h := _hbox(v)
	_button(h, "RESET CAREER", _confirm_reset, 240)


var reset_armed := false


func _confirm_reset() -> void:
	if not reset_armed:
		reset_armed = true
		_find_button_text(body, "RESET CAREER").text = "PRESS AGAIN TO ERASE ALL PROGRESS"
		return
	reset_armed = false
	Game.reset_career()
	show_screen("career")


func _find_button_text(n: Node, text: String) -> Button:
	for c in n.get_children():
		if c is Button and c.text == text:
			return c
		var r := _find_button_text(c, text)
		if r:
			return r
	return null


# --- Settings -----------------------------------------------------------------

func _slider(g: GridContainer, label: String, key: String, lo: float, hi: float, step: float) -> void:
	_label(g, label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Game.settings.get(key, 1.0))
	s.custom_minimum_size = Vector2(380, 30)
	s.value_changed.connect(_set_setting.bind(key))
	g.add_child(s)


func _check(g: GridContainer, label: String, key: String) -> void:
	_label(g, label)
	var c := CheckBox.new()
	c.text = "ON"
	c.button_pressed = bool(Game.settings.get(key, false))
	c.toggled.connect(_set_setting.bind(key))
	g.add_child(c)


func _set_setting(value, key: String) -> void:
	Game.settings[key] = value
	if key in ["fullscreen", "vsync", "volume"]:
		Game.apply_settings()


func _settings() -> void:
	var v := _vbox(body, 16)
	_header(v, "SETTINGS")
	var g := _grid(v)
	_slider(g, "MOUSE SENSITIVITY", "mouse_sens", 0.2, 3.0, 0.05)
	_slider(g, "GAMEPAD SENSITIVITY", "pad_sens", 0.2, 3.0, 0.05)
	_check(g, "INVERT Y", "invert_y")
	_slider(g, "VOLUME", "volume", 0.0, 1.0, 0.05)
	_check(g, "FULLSCREEN", "fullscreen")
	_check(g, "VSYNC", "vsync")
	_check(g, "SHADOWS", "shadows")
	_slider(g, "TREE DENSITY", "trees", 0.2, 1.5, 0.1)
	_check(g, "FRIENDLY MARKERS (IFF)", "iff")
	_label(g, "DEFAULT DIFFICULTY")
	_option(g, ["RECRUIT", "REGULAR", "VETERAN"], int(Game.settings.get("difficulty", 1)), _on_difficulty)


func _controls() -> void:
	var v := _vbox(body, 8)
	_header(v, "CONTROLS")
	var rows := [
		["ACTION", "KEYBOARD / MOUSE", "GAMEPAD"],
		["Slew sensor", "Mouse, arrow keys", "Right stick"],
		["Zoom", "Wheel, W / S", "Left stick up/down"],
		["Wide / narrow field of view", "Z", "L3"],
		["Fire", "Left mouse", "RT"],
		["Laser designator", "Right mouse (hold), L latch", "LT"],
		["Select weapon", "Q / E, 1-6", "LB / RB"],
		["Sensor mode TV / NV / WHT / BHT", "V", "Y"],
		["Support menu (fire calls it)", "G", "X"],
		["Flares", "F", "B"],
		["Track target", "C", "A"],
		["Move orbit to sensor point", "O", "R3"],
		["Climb / descend", "PgUp / PgDn", "D-pad up / down"],
		["Map (click to move orbit)", "Tab", "Back"],
		["Friendly markers", "I", ""],
		["Help overlay", "H, F1", ""],
		["Pause", "Esc", "Start"],
	]
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 40)
	g.add_theme_constant_override("v_separation", 8)
	v.add_child(g)
	for i in rows.size():
		for cell in rows[i]:
			_label(g, cell, 19, UiTheme.ACCENT if i == 0 else UiTheme.FG)
	_label(v, "\nRounds take several seconds to reach the ground from 10,000 ft: lead moving targets. Higher altitude keeps you safer from missiles but spreads your rounds. Friendly troops blink with IR strobes in night vision.", 17, UiTheme.DIM).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


# --- Debrief ------------------------------------------------------------------

func _debrief(r: Dictionary) -> void:
	var v := _vbox(body, 12)
	if r.is_empty():
		_title()
		return
	var cfg: Dictionary = r.cfg
	var st: String = r.state
	var title := "MISSION COMPLETE" if st == "won" else ("SORTIE ENDED" if st == "ended" else "MISSION FAILED")
	_label(v, title, 56, UiTheme.FG if st == "won" else (UiTheme.ACCENT if st == "ended" else UiTheme.BAD))
	_label(v, "%s   -   %s" % [String(cfg.get("name", "")).to_upper(), r.text], 22)
	var s: Dictionary = r.stats
	var tt := int(r.time)
	var lines := [
		"TIME ON STATION   %02d:%02d" % [tt / 60, tt % 60],
		"CONFIRMED KILLS   %d   (infantry %d, vehicles %d, infected %d)" % [s.kills, s.inf, s.veh, s.zombies],
		"ROUNDS FIRED      %d" % s.shots,
		"FRATRICIDE        %d" % s.friendly_kills,
		"CIVILIAN CASUALTIES %d" % s.civ_kills,
	]
	if cfg.get("type", "") == "laststand":
		lines.append("WAVES             %d" % maxi(int(r.wave) - (0 if st == "won" else 1), 0))
	lines.append("SCORE             %d%s" % [r.score, "   NEW BEST!" if r.get("new_best", false) else ""])
	for l in lines:
		_label(v, l, 22)
	if r.get("counts_xp", true):
		_label(v, "XP EARNED         +%d" % int(r.xp), 24, UiTheme.ACCENT)
	else:
		_label(v, "NO XP (everything unlocked)", 20, UiTheme.DIM)
	if r.get("rank_up", false):
		_label(v, "PROMOTED TO %s!" % String(Game.rank().name).to_upper(), 30, UiTheme.ACCENT)
	for u in r.get("new_unlocks", []):
		_label(v, "NEW: %s" % Data.UNLOCK_NAMES.get(u, u), 22, UiTheme.FRIEND)
	_label(v, _rank_line(), 18, UiTheme.DIM)
	var h := _hbox(v)
	var back_to: String = "campaign" if cfg.get("mode", "") == "campaign" else ("title" if cfg.get("mode", "") == "" else cfg.mode)
	if back_to == "skirmish" or back_to == "survival" or back_to == "laststand" or back_to == "campaign":
		_button(h, "CONTINUE", func(): show_screen(back_to), 240)
	else:
		_button(h, "CONTINUE", func(): show_screen("title"), 240)
	_button(h, "RETRY", func(): Game.start_mission(cfg), 200)
	_button(h, "MAIN MENU", func(): show_screen("title"), 220)
