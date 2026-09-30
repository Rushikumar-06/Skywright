extends NetCase
## The main menu's online panels: joining by address, the lobby, and what they say
## when something goes wrong. The menu drives the Session autoload, as in the game.

const TEMP_PATH := "user://test_menu_settings.cfg"

var menu: Node
var _real_path := ""
var _real_address := ""
var _real_name := ""


func _ready() -> void:
	# Joining saves the address typed, so keep the real settings file out of it.
	_real_path = Settings.path
	_real_address = Settings.last_address
	_real_name = Settings.player_name
	Settings.path = TEMP_PATH
	Settings.player_name = "Bob"
	menu = (load("res://src/ui/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)


func after_each() -> void:
	if Session.mode != Session.Mode.NONE:
		Session.leave()
		# Game swaps in a fresh menu, as it does in the game. Throw that away.
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().unload_current_scene()
	super.after_each()
	Settings.path = _real_path
	Settings.last_address = _real_address
	Settings.player_name = _real_name
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


func test_hosting_opens_the_lobby() -> void:
	var port := free_port()
	assert_eq(Session.host("Ann", port), OK)
	var lobby: Control = menu.get("_lobby")
	assert_true(lobby.visible, "the lobby opens")
	assert_eq(crew_names(), ["Ann (host)"] as Array[String])
	assert_true((menu.get("_sail_button") as Button).is_visible_in_tree(), "the host can set sail")
	assert_true((menu.get("_invite") as Label).is_visible_in_tree(), "and sees how friends join")
	var guest := make_session("Guest")
	guest.join("Cy", "127.0.0.1", port)
	assert_true(await wait_until(func() -> bool: return crew_names().size() == 2, 5.0), "the guest appears")
	assert_eq(crew_names(), ["Ann (host)", "Cy"] as Array[String])


func test_joining_shows_the_lobby_and_waits_for_the_host() -> void:
	var host := make_session("Host")
	var port := free_port()
	host.host("Ann", port)
	menu.call("_open_join")
	menu.get("_address").text = "127.0.0.1:%d" % port
	menu.call("_join")
	var lobby: Control = menu.get("_lobby")
	assert_true(await wait_until(func() -> bool: return lobby.visible and crew_names().size() == 2, 5.0), "the lobby opens")
	assert_eq(crew_names(), ["Ann (host)", "Bob"] as Array[String])
	assert_false((menu.get("_sail_button") as Button).is_visible_in_tree(), "only the host sets sail")
	assert_true((menu.get("_waiting") as Label).is_visible_in_tree(), "the guest is told to wait")
	assert_false((menu.get("_message") as Label).visible, "the connecting note is gone")


func crew_names() -> Array[String]:
	var names: Array[String] = []
	for label: Label in (menu.get("_crew_list") as Node).get_children():
		names.append(label.text)
	return names
