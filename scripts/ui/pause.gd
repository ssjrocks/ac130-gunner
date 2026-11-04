extends CanvasLayer
## Pause menu during a sortie.

const UiTheme := preload("res://scripts/ui/theme.gd")

var battle
var root: Control
var resume_btn: Button
var is_open := false


func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	resume_btn = _btn(v, "RESUME", close)
	_btn(v, "RESTART MISSION", func(): battle.restart())
	_btn(v, "SHOW / HIDE CONTROLS", func(): battle.hud.show_help = not battle.hud.show_help)
	var sl := Label.new()
	sl.text = "MOUSE SENSITIVITY"
	v.add_child(sl)
	var slider := HSlider.new()
	slider.min_value = 0.2
	slider.max_value = 3.0
	slider.step = 0.05
	slider.value = float(Game.settings.get("mouse_sens", 1.0))
	slider.custom_minimum_size = Vector2(0, 28)
	slider.value_changed.connect(_on_sens)
	v.add_child(slider)
	_btn(v, "ABORT MISSION", func(): battle.abort())
	root.visible = false


func _on_sens(x: float) -> void:
	Game.settings.mouse_sens = x
	Game.save_settings()


func _btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("pause") and battle.built and not battle.ended:
		if battle.hud.map_big and not is_open:
			battle.hud.toggle_map()
		elif is_open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	is_open = true
	root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.loop("mg", false)
	resume_btn.grab_focus()


func close() -> void:
	is_open = false
	root.visible = false
	get_tree().paused = false
	if Game.autotest == "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
