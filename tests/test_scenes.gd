extends TestCase
## The menu and world scenes build and run a few frames without engine errors.


func test_main_menu_builds() -> void:
	await _run_scene("res://src/ui/main_menu.tscn")


func test_world_builds() -> void:
	await _run_scene("res://src/world/world.tscn")


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
