class_name UiTheme
## The game's UI look: night-sky glass panels, brass accents, warm cream text.

const TEXT := Color("f4ecdb")
const TEXT_DIM := Color("c9c0ae")
const ACCENT := Color("e8a948")
const WARNING := Color("ff9b7a")
const PANEL := Color(0.04, 0.07, 0.13, 0.84)


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 20
	theme.set_color("font_color", "Label", TEXT)

	var clear := Color(0, 0, 0, 0)
	theme.set_stylebox("normal", "Button", _button_box(clear, clear))
	theme.set_stylebox("hover", "Button", _button_box(Color(1, 1, 1, 0.06), ACCENT))
	theme.set_stylebox("pressed", "Button", _button_box(Color(1, 1, 1, 0.1), ACCENT))
	theme.set_stylebox("hover_pressed", "Button", _button_box(Color(1, 1, 1, 0.1), ACCENT))
	theme.set_stylebox("focus", "Button", _button_box(clear, ACCENT))
	theme.set_stylebox("disabled", "Button", _button_box(clear, clear))
	theme.set_color("font_color", "Button", TEXT)
	for state in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(state, "Button", ACCENT)
	theme.set_color("font_disabled_color", "Button", Color(TEXT, 0.35))
	theme.set_font_size("font_size", "Button", 26)

	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.border_color = Color(1, 1, 1, 0.08)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(32)
	theme.set_stylebox("panel", "PanelContainer", panel)

	var field := StyleBoxFlat.new()
	field.bg_color = Color(1, 1, 1, 0.07)
	field.border_color = Color(1, 1, 1, 0.15)
	field.border_width_bottom = 2
	field.set_corner_radius_all(4)
	field.set_content_margin_all(10)
	theme.set_stylebox("normal", "LineEdit", field)
	var field_focus := field.duplicate() as StyleBoxFlat
	field_focus.border_color = ACCENT
	theme.set_stylebox("focus", "LineEdit", field_focus)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", Color(TEXT, 0.4))
	theme.set_color("caret_color", "LineEdit", ACCENT)
	return theme


## A big, widely spaced title.
static func title(text: String) -> Label:
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.spacing_glyph = 10
	font.variation_embolden = 0.8
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 84)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	label.add_theme_constant_override("shadow_offset_y", 3)
	return label


## Secondary text.
static func caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", TEXT_DIM)
	return label


## A left-aligned text button that calls on_pressed.
static func button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(on_pressed)
	return b


## Empty vertical space.
static func gap(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	return spacer


static func _button_box(fill: Color, bar: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = bar
	box.border_width_left = 3
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box
