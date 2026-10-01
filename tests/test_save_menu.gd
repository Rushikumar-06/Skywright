extends NetCase
## Saved games in the menus (spec §4.10): Play solo and Host game choose a slot to
## continue or start over, the pause menu saves, leaving autosaves, and a dedicated
## server plays the "server" slot.

var menu: Node
var dir := ""
var _real_name := ""


func _ready() -> void:
	dir = "user://test_saves_%d" % randi()
	SaveGame.dir = dir
	_real_name = Settings.player_name
	Settings.player_name = "Bob"
	menu = (load("res://src/ui/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)


func after_each() -> void:
	if Session.mode != Session.Mode.NONE:
		Session.leave()
		await get_tree().process_frame  # Game swaps in a fresh menu: throw it away
		await get_tree().process_frame
		get_tree().unload_current_scene()
	super.after_each()
	Session.save_slot = ""
	Session.loaded = {}
	Session.requested_seed = -1
	Settings.player_name = _real_name
	remove_tree(dir)
	SaveGame.dir = "user://saves"


static func remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		remove_tree(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


## A save of seed world_seed, with one ship, nobody's, at the first town's slipway.
static func a_save(world_seed: int) -> Dictionary:
	var at := Dock.slipway(WorldGen.START, 0)
	var q := at.basis.get_rotation_quaternion()
	var ship := {"captain": "", "at": [at.origin.x, at.origin.y, at.origin.z, q.x, q.y, q.z, q.w], "trim": 1.0, "anchored": true,
			"spares": 40, "blocks": StarterShip.build().to_blocks(), "blueprint": StarterShip.build().to_blocks(), "paint": {},
			"cargo": [], "hands": []}
	return {"world": {"seed": world_seed, "time": 50.0, "salvaged": [], "exploration": "", "host": "", "saved": 1790000000.0},
			"ships": [ship], "players": {}}


## The saved games panel's rows: [summary Label, Continue, New game].
func rows() -> Array:
	var found := []
	for row: Node in (menu.get("_saves") as Node).find_children("*", "HBoxContainer", true, false):
		var label: Label = row.get_child(0)
		found.append([label, row.get_child(1), row.get_child(2)])
	return found


func test_play_solo_shows_the_slots() -> void:
	menu.call("_play_solo")
	assert_true((menu.get("_saves") as Control).visible, "the saved games")
	assert_eq(Session.mode, Session.Mode.NONE, "nothing starts yet")
	var shown := rows()
	assert_eq(shown.map(func(row: Array) -> String: return (row[0] as Label).text), ["Slot 1   empty", "Slot 2   empty", "Slot 3   empty"])
	for row: Array in shown:
		assert_true((row[1] as Button).disabled, "nothing to continue")


func test_continue_loads_the_slot() -> void:
	SaveGame.write(SaveGame.slot_path("2"), a_save(7))
	menu.call("_play_solo")
	var row: Array = rows()[1]
	assert_eq((row[0] as Label).text, SaveGame.summary("2"))
	assert_false((row[1] as Button).disabled)
	(row[1] as Button).pressed.emit()
	assert_eq(Session.mode, Session.Mode.SOLO, "a solo game starts")
	assert_eq(Session.world_seed, 7)
	assert_eq(Session.save_slot, "2")
	assert_false(Session.loaded.is_empty(), "with the save to play")


func test_a_broken_slot_says_so() -> void:
	SaveGame.write(SaveGame.slot_path("1"), a_save(7))
	var file := FileAccess.open(SaveGame.slot_path("1").path_join("world.json"), FileAccess.WRITE)
	file.store_string("{")
	file.close()
	menu.call("_play_solo")
	var row: Array = rows()[0]
	assert_eq((row[0] as Label).text, "Slot 1   can't be read")
	assert_true((row[1] as Button).disabled)


func test_new_game_on_a_used_slot_asks_twice() -> void:
	SaveGame.write(SaveGame.slot_path("2"), a_save(7))
	menu.call("_play_solo")
	var new_game: Button = rows()[1][2]
	new_game.pressed.emit()
	assert_eq(new_game.text, "Start over: press again")
	assert_eq(Session.mode, Session.Mode.NONE, "nothing starts yet")
	new_game.pressed.emit()
	assert_eq(Session.mode, Session.Mode.SOLO, "a new game")
	assert_eq(Session.save_slot, "2")
	assert_true(Session.loaded.is_empty(), "from scratch")


func test_save_game_in_the_pause_menu() -> void:
	var world := solo_world()
	await get_tree().process_frame
	world.session.save_slot = "3"
	world._toggle_pause()
	var button: Button = world._save_button
	assert_true(button.visible, "Save game is there")
	button.pressed.emit()
	assert_true(FileAccess.file_exists(SaveGame.slot_path("3").path_join("world.json")), "saved")
	assert_eq(world._pause_note.text, "Saved to slot 3.")
	world._toggle_pause()
	world.session.save_slot = ""
	world._toggle_pause()
	assert_false(button.visible, "no slot, no Save game")


func test_leaving_saves_first() -> void:
	var world := solo_world()
	await get_tree().process_frame
	world.session.save_slot = "3"
	world.leave_game()
	assert_true(FileAccess.file_exists(SaveGame.autosave_paths("3")[0].path_join("world.json")), "an autosave")
	assert_eq(world.session.mode, SessionScript.Mode.NONE, "and the game's left")


func test_a_dedicated_server_plays_the_server_slot() -> void:
	SaveGame.write(SaveGame.slot_path("server"), a_save(9))
	host = make_session("Server")
	var loaded := SaveGame.prepare(host, "server")
	assert_true(loaded.has("save"))
	assert_eq(host.save_slot, "server")
	assert_false(host.loaded.is_empty())
	assert_eq(host.requested_seed, 9)
	host.host("Skyport", free_port(), true)
	assert_eq(host.world_seed, 9)
	host_world = add_world(host)
	await get_tree().process_frame
	var ships: Array = host_world.sync.ships.values()
	assert_eq(ships.size(), 1, "the saved ship, not a new one")
	assert_eq((ships[0] as Ship).captain, 0, "nobody's")
