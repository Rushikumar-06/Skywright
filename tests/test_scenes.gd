extends TestCase
## The menu and world scenes build and run a few frames without engine errors.


func test_main_menu_builds() -> void:
	await _run_scene("res://src/ui/main_menu.tscn")


func test_world_builds() -> void:
	await _run_scene("res://src/world/world.tscn")


func test_esc_while_connecting_returns_to_a_fresh_menu() -> void:
	# As in the game: the menu is the current scene, so ending the session swaps it out.
	var menu: Node = (load("res://src/ui/main_menu.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await get_tree().process_frame
	Session.join("Tester", "127.0.0.1", 20000 + randi() % 10000)  # nobody listens there
	menu.call("_open_join")
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	menu.call("_unhandled_input", esc)
	assert_eq(Session.mode, Session.Mode.NONE, "the connection attempt is cancelled")
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().unload_current_scene()  # the fresh menu that Game loaded
	await get_tree().process_frame


func _run_scene(path: String) -> void:
	var packed := load(path) as PackedScene
	assert_true(packed != null, "%s loads" % path)
	if packed == null:
		return
	var scene := packed.instantiate()
	add_child(scene)
	for i in 5:
		await get_tree().process_frame
	scene.queue_free()
	await get_tree().process_frame
