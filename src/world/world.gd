extends Node3D
## The game world. In stage 1 it's the sky backdrop and a HUD showing the session;
## stage 2 adds the ship.

var _status: Label
var _crew: Label
var _pause: PanelContainer
var _resume: Button


func _ready() -> void:
	add_child(SkyBackdrop.new())
	var layer := CanvasLayer.new()
	add_child(layer)
	var theme := UiTheme.build()

	var hud := PanelContainer.new()
	hud.theme = theme
	hud.position = Vector2(32, 32)
	layer.add_child(hud)
	var column := VBoxContainer.new()
	hud.add_child(column)
	_status = Label.new()
	column.add_child(_status)
	_crew = UiTheme.caption("")
	column.add_child(_crew)
	column.add_child(UiTheme.gap(8))
	column.add_child(UiTheme.caption("Flying arrives in stage 2. Press Esc for the menu."))

	var center := CenterContainer.new()
	center.theme = theme
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	_pause = PanelContainer.new()
	_pause.visible = false
	center.add_child(_pause)
	var pause_column := VBoxContainer.new()
	_pause.add_child(pause_column)
	_resume = UiTheme.button("Resume", _toggle_pause)
	pause_column.add_child(_resume)
	pause_column.add_child(UiTheme.button("Leave game", Session.leave))

	Session.players_changed.connect(_refresh)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _toggle_pause() -> void:
	_pause.visible = not _pause.visible
	if _pause.visible:
		_resume.grab_focus()


func _refresh() -> void:
	_status.text = _status_text()
	var names: PackedStringArray = []
	for id: int in Session.players:
		names.append(Session.players[id]["name"])
	_crew.text = "Crew (%d): %s" % [names.size(), ", ".join(names)]


func _status_text() -> String:
	if Session.mode == Session.Mode.SOLO:
		return "Solo game"
	if Session.mode == Session.Mode.HOST:
		var lan := Session.lan_addresses(IP.get_local_addresses())
		if lan.is_empty():
			return "Hosting on port %d" % Session.port
		return "Hosting. Friends on your network join at %s:%d" % [lan[0], Session.port]
	if Session.mode == Session.Mode.CLIENT:
		return "Connected to the host"
	return ""
