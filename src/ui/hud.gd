class_name Hud
extends CanvasLayer
## Everything drawn over the world: the session and crew, a dot to aim with, what
## E does, the helm's instruments while you steer, and short messages.

const MESSAGE_TIME := 4.0  ## Seconds a message stays up.
const SessionScript := preload("res://src/net/session.gd")

var player: PlayerController
var session: Node

var _status: Label
var _crew: Label
var _prompt: Label
var _helm: PanelContainer
var _readout: Label
var _message: Label
var _message_left := 0.0
var _crew_names: Dictionary = {}  ## The roster as last shown: peer id -> name.


func _init(for_player: PlayerController, world_session: Node) -> void:
	player = for_player
	session = world_session


func _ready() -> void:
	var theme := UiTheme.build()
	var crew_panel := PanelContainer.new()
	crew_panel.theme = theme
	crew_panel.position = Vector2(32, 32)
	add_child(crew_panel)
	var column := VBoxContainer.new()
	crew_panel.add_child(column)
	_status = Label.new()
	column.add_child(_status)
	_crew = UiTheme.caption("")
	column.add_child(_crew)

	var dot := ColorRect.new()
	dot.color = Color(UiTheme.TEXT, 0.8)
	dot.size = Vector2(4, 4)
	dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dot)

	_prompt = Label.new()
	_prompt.theme = theme
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.offset_top = 40
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_prompt)

	_message = Label.new()
	_message.theme = theme
	_message.add_theme_color_override("font_color", UiTheme.ACCENT)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_message.offset_top = 120
	_message.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_message)

	_helm = PanelContainer.new()
	_helm.theme = theme
	_helm.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_helm.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_helm.offset_left = 32
	_helm.offset_bottom = -32
	add_child(_helm)
	var helm_column := VBoxContainer.new()
	_helm.add_child(helm_column)
	_readout = Label.new()
	_readout.add_theme_font_override("font", _monospace())
	helm_column.add_child(_readout)
	helm_column.add_child(UiTheme.caption("W/S throttle · A/D rudder · Space/Ctrl climb · H autopilot · V view · E leave"))

	session.players_changed.connect(_refresh_session)
	player.fell_overboard.connect(func() -> void: show_message("You fell overboard. Back aboard!"))
	_refresh_session()


func show_message(text: String) -> void:
	_message.text = text
	_message_left = MESSAGE_TIME


func _process(delta: float) -> void:
	var action := player.prompt()
	var holder: int = player.ship.helm.pilot if player.ship.helm != null else 0
	if not action.is_empty():
		_prompt.text = "E   " + action
	elif holder != 0 and holder != player.peer and player.helm_in_reach():
		_prompt.text = "%s is at the helm" % name_of(holder)
	else:
		_prompt.text = ""
	_message_left -= delta
	_message.visible = _message_left > 0.0
	_helm.visible = player.crew.station != null
	if _helm.visible:
		_readout.text = readout(player.ship)


## A player's name, from the session's roster.
func name_of(peer: int) -> String:
	return session.players.get(peer, {}).get("name", "Someone")


## The helm's instruments as text.
static func readout(ship: Ship) -> String:
	var lines: PackedStringArray = []
	lines.append("Throttle  %s" % ("%3d%% ahead" % roundi(ship.throttle * 100.0) if ship.throttle >= 0.0 else "%3d%% astern" % roundi(-ship.throttle * 100.0)))
	lines.append("Rudder    %s" % ("centred" if absf(ship.rudder) < 0.05 else "%3d%% %s" % [roundi(absf(ship.rudder) * 100.0), "starboard" if ship.rudder > 0.0 else "port"]))
	lines.append("Trim      %.2f" % ship.trim)
	lines.append("Speed     %3d m/s" % roundi(ship.linear_velocity.length()))
	lines.append("Altitude  %4d m   %+.1f m/s" % [roundi(ship.global_position.y), ship.linear_velocity.y])
	lines.append("Heading   %03d°" % posmod(roundi(-rad_to_deg(ship.heading())), 360))
	if ship.helm.autopilot:
		lines.append("Autopilot %03d° at %d m" % [posmod(roundi(-rad_to_deg(ship.helm.target_heading)), 360), roundi(ship.helm.target_altitude)])
	else:
		lines.append("Autopilot off")
	return "\n".join(lines)


func _refresh_session() -> void:
	_status.text = _status_text()
	var names: PackedStringArray = []
	var news: PackedStringArray = []
	for id: int in session.players:
		var crew_name: String = session.players[id]["name"]
		names.append(crew_name)
		if not _crew_names.is_empty() and not _crew_names.has(id):
			news.append("%s came aboard." % crew_name)
	for id: int in _crew_names:
		if not session.players.has(id) and not session.players.is_empty():
			news.append("%s left." % _crew_names[id])
	_crew.text = "Crew (%d): %s" % [names.size(), ", ".join(names)]
	_crew_names.clear()
	for id: int in session.players:
		_crew_names[id] = session.players[id]["name"]
	if not news.is_empty():
		show_message(" ".join(news))


func _status_text() -> String:
	if session.mode == SessionScript.Mode.SOLO:
		return "Solo game"
	if session.mode == SessionScript.Mode.HOST:
		return "Hosting. " + invite_text(session.port)
	if session.mode == SessionScript.Mode.CLIENT:
		return "Connected to the host"
	return ""


## What to tell friends so they can join a game hosted here on port.
static func invite_text(port: int) -> String:
	var targets: PackedStringArray = []
	for address in SessionScript.lan_addresses_by_interface(IP.get_local_interfaces()):
		targets.append("%s:%d" % [address, port])
	if targets.is_empty():
		return "Friends join at this computer's address, port %d." % port
	var text := "Friends on your network join at " + targets[0]
	if targets.size() > 1:
		text += " (or " + ", ".join(targets.slice(1)) + ")"
	return text + "."


static func _monospace() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["DejaVu Sans Mono", "Consolas", "Menlo", "monospace"])
	return font
