class_name SettingsPanel
extends VBoxContainer
## Edits Settings. Each change is applied and saved straight away, so leaving the
## panel any way (Back, Esc, closing the window) keeps it.

signal closed

var _name_field: LineEdit


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	add_child(UiTheme.caption("Your name"))
	_name_field = LineEdit.new()
	_name_field.max_length = Settings.MAX_NAME_LENGTH
	_name_field.text = Settings.player_name
	_name_field.text_changed.connect(func(text: String) -> void:
		Settings.player_name = Settings.clean_name(text)
		Settings.save()
	)
	add_child(_name_field)
	add_child(_toggle("Fullscreen", Settings.fullscreen, func(on: bool) -> void: Settings.fullscreen = on))
	add_child(_toggle("VSync", Settings.vsync, func(on: bool) -> void: Settings.vsync = on))
	add_child(UiTheme.caption("Master volume"))
	add_child(_slider(0.0, 1.0, Settings.master_volume, func(value: float) -> void: Settings.master_volume = value))
	add_child(UiTheme.caption("Mouse sensitivity"))
	add_child(_slider(0.1, 3.0, Settings.mouse_sensitivity, func(value: float) -> void: Settings.mouse_sensitivity = value))
	add_child(UiTheme.gap(8))
	add_child(UiTheme.button("Back", _close))


func focus_first() -> void:
	_name_field.grab_focus()


func _close() -> void:
	closed.emit()


func _commit() -> void:
	Settings.apply()
	Settings.save()


func _toggle(text: String, value: bool, set_value: Callable) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = text
	toggle.button_pressed = value
	toggle.toggled.connect(func(on: bool) -> void:
		set_value.call(on)
		_commit()
	)
	return toggle


func _slider(low: float, high: float, value: float, set_value: Callable) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size.x = 320
	slider.value_changed.connect(func(new_value: float) -> void:
		set_value.call(new_value)
		_commit()
	)
	return slider
