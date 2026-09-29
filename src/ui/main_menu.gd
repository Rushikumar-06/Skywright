extends Node3D
## The main menu: play solo, host, join, settings and quit, over a drifting sky.

var _message: Label
var _menu: VBoxContainer
var _join_panel: VBoxContainer
var _address: LineEdit
var _join_button: Button
var _settings: SettingsPanel


func _ready() -> void:
	add_child(SkyBackdrop.new())
	var layer := CanvasLayer.new()
	add_child(layer)

	var rail := PanelContainer.new()
	rail.theme = UiTheme.build()
	rail.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	rail.custom_minimum_size.x = 560
	layer.add_child(rail)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	rail.add_child(column)
	column.add_child(UiTheme.gap(40))
	column.add_child(UiTheme.title("SKYWRIGHT"))
	column.add_child(UiTheme.caption("Build a ship. Physics decides if it flies."))
	column.add_child(UiTheme.gap(48))

	_message = UiTheme.caption("")
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.visible = false
	column.add_child(_message)

	_menu = VBoxContainer.new()
	column.add_child(_menu)
	_menu.add_child(UiTheme.button("Play solo", _play_solo))
	_menu.add_child(UiTheme.button("Host game", _host))
	_menu.add_child(UiTheme.button("Join game", _open_join))
	_menu.add_child(UiTheme.button("Settings", _open_settings))
	_menu.add_child(UiTheme.button("Quit", get_tree().quit))

	_join_panel = _build_join_panel()
	column.add_child(_join_panel)
	_settings = SettingsPanel.new()
	_settings.closed.connect(_show_menu)
	column.add_child(_settings)

	_show_menu()
	if not Game.menu_message.is_empty():
		_show_problem(Game.menu_message)
		Game.menu_message = ""


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _menu.visible:
		_back()
		get_viewport().set_input_as_handled()


func _build_join_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 12)
	panel.add_child(UiTheme.caption("Host's address"))
	_address = LineEdit.new()
	_address.placeholder_text = "192.168.0.10 or 192.168.0.10:24650"
	_address.text_submitted.connect(func(_text: String) -> void: _join())
	panel.add_child(_address)
	var row := HBoxContainer.new()
	_join_button = UiTheme.button("Join", _join)
	row.add_child(_join_button)
	row.add_child(UiTheme.button("Back", _back))
	panel.add_child(row)
	return panel


func _show_menu() -> void:
	_menu.visible = true
	_join_panel.visible = false
	_settings.visible = false
	(_menu.get_child(0) as Button).grab_focus()


func _open_join() -> void:
	_menu.visible = false
	_join_panel.visible = true
	_address.text = Settings.last_address
	_address.grab_focus()
	_address.caret_column = _address.text.length()


func _open_settings() -> void:
	_menu.visible = false
	_settings.visible = true
	_settings.focus_first()


## Back out of a panel. While connecting, this cancels the connection, which
## returns to a fresh menu through Game.
func _back() -> void:
	if Session.mode != Session.Mode.NONE:
		Session.leave()
	else:
		_message.visible = false
		_show_menu()


func _play_solo() -> void:
	Session.start_solo(Settings.player_name)


func _host() -> void:
	var err := Session.host(Settings.player_name)
	if err == ERR_CANT_CREATE:
		_show_problem("Port %d is already in use. Is another game running?" % Session.DEFAULT_PORT)
	elif err != OK:
		_show_problem("Couldn't start hosting (%s)." % error_string(err))


func _join() -> void:
	var typed := _address.text.strip_edges()
	var target := Session.parse_address(typed)
	if target.is_empty():
		_show_problem("Enter an address like 192.168.0.10 or 192.168.0.10:24650.")
		return
	Settings.last_address = typed
	Settings.save()
	var err := Session.join(Settings.player_name, target["host"], target["port"])
	if err != OK:
		_show_problem("Couldn't start connecting (%s)." % error_string(err))
		return
	_show_note("Connecting to %s…" % typed)
	_join_button.disabled = true


func _show_problem(text: String) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", UiTheme.WARNING)
	_message.visible = true


func _show_note(text: String) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_message.visible = true
