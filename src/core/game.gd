extends Node
## Moves between the main menu and the world as the crew set sail and sessions end, carries
## the reason a session ended back to the menu, and applies launch options (see
## LaunchOptions), for example: godot --path . -- --host --name=Ann
## A dedicated server: godot --headless --path . -- --server

const MENU_SCENE := "res://src/ui/main_menu.tscn"
const WORLD_SCENE := "res://src/world/world.tscn"

## Why the last session ended, for the menu to show once. "" when there's nothing to say.
var menu_message := ""


func _ready() -> void:
	Session.sailed.connect(_on_sailed)
	Session.ended.connect(_on_session_ended)
	_apply_launch_options.call_deferred(LaunchOptions.parse(OS.get_cmdline_user_args()))


func _apply_launch_options(options: Dictionary) -> void:
	var player_name: String = options.get("name", Settings.player_name)
	if options.has("server"):
		Engine.max_fps = Engine.physics_ticks_per_second  # nothing to draw, so no faster than it simulates
		var server_port: int = options.get("port", Session.DEFAULT_PORT)
		if Session.host(player_name, server_port, true) != OK:
			printerr("Port %d is already in use. Is another game running?" % server_port)
			get_tree().quit(1)
	elif options.has("solo"):
		Session.start_solo(player_name)
	elif options.has("host"):
		var host_port: int = options.get("port", Session.DEFAULT_PORT)
		var err := Session.host(player_name, host_port)
		if err != OK:
			push_error("Couldn't host on port %d: %s" % [host_port, error_string(err)])
	elif options.has("join"):
		var target := Session.parse_address(options["join"])
		if target.is_empty():
			push_error("Can't join '%s': that isn't an address." % options["join"])
		else:
			Session.join(player_name, target["host"], target["port"])


func _on_sailed() -> void:
	menu_message = ""
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_session_ended(reason: String) -> void:
	menu_message = reason
	get_tree().change_scene_to_file(MENU_SCENE)
