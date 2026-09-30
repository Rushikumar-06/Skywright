extends NetCase
## The main menu's online panels: joining by address and what it says when that fails.

const TEMP_PATH := "user://test_menu_settings.cfg"

var menu: Node
var _real_path := ""
var _real_address := ""


func _ready() -> void:
	# Joining saves the address typed, so keep the real settings file out of it.
	_real_path = Settings.path
	_real_address = Settings.last_address
	Settings.path = TEMP_PATH
	menu = (load("res://src/ui/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)


func after_each() -> void:
	Session.leave()
	await super.after_each()
	Settings.path = _real_path
	Settings.last_address = _real_address
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))


func test_an_unknown_host_name_says_so() -> void:
	menu.call("_open_join")
	menu.get("_address").text = "no-such-host.invalid"
	menu.call("_join")
	var message: Label = menu.get("_message")
	assert_true(message.visible)
	assert_eq(message.text, "Couldn't find \"no-such-host.invalid\". Check the address.")
	assert_eq(Session.mode, Session.Mode.NONE)
