extends RefCounted
## Shared look for menus and the HUD: green-on-black monochrome displays.

const FG := Color(0.72, 1.0, 0.72)
const DIM := Color(0.42, 0.62, 0.44)
const BG := Color(0.02, 0.045, 0.03, 0.94)
const ACCENT := Color(1.0, 0.82, 0.35)
const BAD := Color(1.0, 0.38, 0.32)
const FRIEND := Color(0.45, 0.82, 1.0)

static var _font: SystemFont
static var _theme: Theme


static func mono() -> Font:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "Consolas", "Lucida Console", "Courier New", "monospace"])
	return _font


static func _box(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = mono()
	t.default_font_size = 20
	for cls in ["Button", "OptionButton", "CheckBox", "CheckButton"]:
		t.set_stylebox("normal", cls, _box(Color(0.04, 0.09, 0.05, 0.9), DIM, 1))
		t.set_stylebox("hover", cls, _box(Color(0.08, 0.18, 0.1, 0.95), FG, 1))
		t.set_stylebox("pressed", cls, _box(Color(0.12, 0.25, 0.14, 1.0), FG, 2))
		t.set_stylebox("focus", cls, _box(Color(0, 0, 0, 0), ACCENT, 2))
		t.set_stylebox("disabled", cls, _box(Color(0.03, 0.05, 0.04, 0.8), Color(0.2, 0.3, 0.22), 1))
		t.set_color("font_color", cls, FG)
		t.set_color("font_hover_color", cls, Color(0.9, 1.0, 0.9))
		t.set_color("font_pressed_color", cls, ACCENT)
		t.set_color("font_focus_color", cls, Color(0.9, 1.0, 0.9))
		t.set_color("font_disabled_color", cls, Color(0.3, 0.42, 0.32))
	t.set_stylebox("panel", "PanelContainer", _box(BG, DIM, 1))
	t.set_stylebox("panel", "Panel", _box(BG, DIM, 1))
	t.set_color("font_color", "Label", FG)
	t.set_color("default_color", "RichTextLabel", FG)
	t.set_font("normal_font", "RichTextLabel", mono())
	t.set_font_size("normal_font_size", "RichTextLabel", 19)
	var grab := StyleBoxFlat.new()
	grab.bg_color = FG
	t.set_stylebox("slider", "HSlider", _box(Color(0.05, 0.1, 0.06), DIM, 1))
	t.set_stylebox("grabber_area", "HSlider", grab)
	t.set_stylebox("grabber_area_highlight", "HSlider", grab)
	t.set_stylebox("panel", "PopupMenu", _box(Color(0.02, 0.05, 0.03, 0.98), FG, 1))
	t.set_color("font_color", "PopupMenu", FG)
	t.set_color("font_hover_color", "PopupMenu", ACCENT)
	t.set_stylebox("hover", "PopupMenu", _box(Color(0.1, 0.2, 0.12), FG, 0))
	var sbg := StyleBoxFlat.new()
	sbg.bg_color = Color(0.1, 0.2, 0.12)
	t.set_stylebox("scroll", "VScrollBar", sbg)
	_theme = t
	return t
