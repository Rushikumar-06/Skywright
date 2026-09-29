extends Node
## Player settings, loaded from user://settings.cfg at startup and saved on change.
## Loaded values are cleaned, so a hand-edited or broken file can't put the game
## in a bad state.

const PATH := "user://settings.cfg"
const DEFAULT_NAME := "Captain"
const MAX_NAME_LENGTH := 24
const DEFAULT_ADDRESS := "127.0.0.1"

var player_name := DEFAULT_NAME
var fullscreen := false
var vsync := true
var master_volume := 0.8        ## 0 to 1
var mouse_sensitivity := 1.0    ## 0.1 to 3
var last_address := DEFAULT_ADDRESS


func _ready() -> void:
	load_from(PATH)
	apply()


## Reads settings from path. A missing or unreadable file leaves the current values.
func load_from(path: String) -> void:
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return
	player_name = clean_name(str(file.get_value("player", "name", player_name)))
	last_address = _clean_address(str(file.get_value("player", "last_address", last_address)))
	fullscreen = _as_bool(file.get_value("display", "fullscreen", fullscreen), fullscreen)
	vsync = _as_bool(file.get_value("display", "vsync", vsync), vsync)
	master_volume = _as_number(file.get_value("audio", "master_volume", master_volume), master_volume, 0.0, 1.0)
	mouse_sensitivity = _as_number(file.get_value("controls", "mouse_sensitivity", mouse_sensitivity), mouse_sensitivity, 0.1, 3.0)


func save_to(path: String) -> Error:
	var file := ConfigFile.new()
	file.set_value("player", "name", player_name)
	file.set_value("player", "last_address", last_address)
	file.set_value("display", "fullscreen", fullscreen)
	file.set_value("display", "vsync", vsync)
	file.set_value("audio", "master_volume", master_volume)
	file.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	return file.save(path)


## Saves to user://settings.cfg, warning rather than failing if the disk refuses.
func save() -> void:
	var err := save_to(PATH)
	if err != OK:
		push_warning("Couldn't save settings: %s" % error_string(err))


## Pushes the display and audio settings to the engine.
func apply() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	AudioServer.set_bus_mute(0, master_volume <= 0.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.001)))


## Trims a name, turns control characters into spaces, caps it at MAX_NAME_LENGTH,
## and falls back to DEFAULT_NAME when nothing is left.
static func clean_name(raw: String) -> String:
	var printable := ""
	for character in raw:
		printable += character if character.unicode_at(0) >= 32 else " "
	var cleaned := printable.strip_edges().left(MAX_NAME_LENGTH).strip_edges()
	return cleaned if not cleaned.is_empty() else DEFAULT_NAME


static func _clean_address(raw: String) -> String:
	var address := raw.strip_edges().left(253)
	return address if not address.is_empty() else DEFAULT_ADDRESS


static func _as_bool(value: Variant, fallback: bool) -> bool:
	return value if value is bool else fallback


static func _as_number(value: Variant, fallback: float, low: float, high: float) -> float:
	if (value is float or value is int) and is_finite(float(value)):
		return clampf(float(value), low, high)
	return fallback
