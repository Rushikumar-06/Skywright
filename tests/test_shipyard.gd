extends NetCase
## The shipyard (spec §3.8): building a design block by block at the dock, with its
## stats, warnings and blueprints, and taking it on a test flight or launching it.

var _dir := ""


func after_each() -> void:
	if not _dir.is_empty() and DirAccess.dir_exists_absolute(_dir):
		for file in DirAccess.get_files_at(_dir):
			DirAccess.remove_absolute(_dir.path_join(file))
		DirAccess.remove_absolute(_dir)
	super.after_each()


## A solo world at the dock, with the shipyard open and blueprints in a temp folder.
func open_world() -> Node3D:
	var world := solo_world()
	await get_tree().process_frame
	press_key(world, "shipyard")
	if world.shipyard != null:
		_dir = OS.get_user_data_dir().path_join("test_blueprints_%d" % randi())
		(world.shipyard as Shipyard).blueprint_dir = _dir
	return world


## Presses action in world, as a key press would.
func press_key(world: Node3D, action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	world._unhandled_input(event)


## Presses a key in the shipyard.
func key(shipyard: Shipyard, keycode: Key, ctrl := false, shift := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	event.pressed = true
	shipyard._unhandled_input(event)


## The shipyard's button whose text is text, or null.
func button(shipyard: Shipyard, text: String) -> Button:
	for node in shipyard.find_children("*", "Button", true, false):
		if (node as Button).text == text:
			return node
	return null


func press_button(shipyard: Shipyard, text: String) -> void:
	var found := button(shipyard, text)
	assert_true(found != null, "a %s button" % text)
	if found != null:
		found.pressed.emit()


func centre(shipyard: Shipyard) -> Vector2:
	return Vector2(shipyard.view.size) / 2.0


func test_b_opens_the_shipyard_at_the_dock() -> void:
	var world := await open_world()
	var shipyard: Shipyard = world.shipyard
	assert_true(shipyard != null, "the shipyard is open")
	if shipyard == null:
		return
	assert_false(world.player.enabled, "your controls are off")
	assert_false(world.hud.visible, "the HUD is hidden")
	assert_eq(shipyard.design.grid.blocks.size(), 287, "designing the starter ship")
	assert_true(shipyard.stats_text().begins_with("Blocks     287 of 4000"), shipyard.stats_text())
	assert_eq(shipyard.warnings_text(), "No warnings. She should fly.")


func test_the_shipyard_is_only_at_the_dock() -> void:
	var world := solo_world()
	await get_tree().process_frame
	var ship: Ship = world.ship
	ship.global_position += Vector3(2000, 0, 0)
	ship.reset_physics_interpolation()
	press_key(world, "shipyard")
	assert_true(world.shipyard == null, "no shipyard opens")
	assert_eq(world.hud._message.text, "The shipyard is at the dock.")


func test_b_or_esc_closes_the_shipyard() -> void:
	var world := await open_world()
	for action in ["shipyard", "pause"]:
		if action == "pause":
			press_key(world, "shipyard")
		assert_true(world.shipyard != null, "open")
		press_key(world, action)
		assert_true(world.shipyard == null, "%s closes it" % action)
		assert_true(world.player.enabled, "your controls are back")
		assert_true(world.hud.visible, "and the HUD")
		assert_false(world._pause.visible, "no pause menu")


func test_stats_and_warnings_follow_the_design() -> void:
	var world := await open_world()
	var shipyard: Shipyard = world.shipyard
	var helm: Vector3i = shipyard.design.grid.cells_of("helm")[0]
	shipyard.design.remove(helm)
	assert_true(shipyard.warnings_text().contains("Every ship needs a helm."), shipyard.warnings_text())
	assert_true(button(shipyard, "Test flight (F)").disabled, "no test flight")
	assert_true(button(shipyard, "Launch").disabled, "no launch")
	assert_eq(shipyard.note_text(), "Every ship needs a helm.")
	assert_true(shipyard.stats_text().begins_with("Blocks     286 of 4000"))
	press_button(shipyard, "Undo")
	assert_eq(shipyard.warnings_text(), "No warnings. She should fly.")
	assert_false(button(shipyard, "Test flight (F)").disabled, "test flight again")


func test_clicking_places_on_the_face_you_point_at() -> void:
	var world := await open_world()
	var shipyard: Shipyard = world.shipyard
	var one := ShipGrid.new()
	one.set_block(Vector3i.ZERO, "frame")
	shipyard.design.replace(one)
	shipyard.view.look_from(Vector3(0, 10, 0.001), Vector3.ZERO)
	shipyard.select("deck")
	key(shipyard, KEY_R)
	shipyard.click(centre(shipyard), MOUSE_BUTTON_LEFT)
	assert_eq(shipyard.design.grid.type_at(Vector3i(0, 1, 0)), "deck", "on top of the frame")
	assert_eq(shipyard.design.grid.blocks.get(Vector3i(0, 1, 0), {}).get("rotation"), Blocks.turned(0), "turned")
	shipyard.click(centre(shipyard), MOUSE_BUTTON_RIGHT)
	assert_eq(shipyard.design.grid.type_at(Vector3i(0, 1, 0)), "", "removed again")
	assert_eq(shipyard.design.grid.blocks.size(), 1)
	shipyard.design.replace(ShipGrid.new())
	shipyard.click(centre(shipyard), MOUSE_BUTTON_LEFT)
	assert_eq(shipyard.design.grid.type_at(Vector3i.ZERO), "deck", "on the grid")


func test_keys_turn_tip_mirror_undo_and_redo() -> void:
	var world := await open_world()
	var shipyard: Shipyard = world.shipyard
	key(shipyard, KEY_R)
	assert_eq(shipyard.block_rotation, Blocks.turned(0))
	key(shipyard, KEY_T)
	assert_eq(shipyard.block_rotation, Blocks.tipped(Blocks.turned(0)))
	key(shipyard, KEY_M)
	assert_true(shipyard.design.mirror, "mirror on")
	assert_true(button(shipyard, "Mirror: on (M)") != null, "and the button says so")
	var helm: Vector3i = shipyard.design.grid.cells_of("helm")[0]
	shipyard.design.remove(helm)
	key(shipyard, KEY_Z, true)
	assert_eq(shipyard.design.grid.type_at(helm), "helm", "Ctrl+Z undoes")
	key(shipyard, KEY_Y, true)
	assert_eq(shipyard.design.grid.type_at(helm), "", "Ctrl+Y redoes")
	key(shipyard, KEY_Z, true)
	key(shipyard, KEY_Z, true, true)
	assert_eq(shipyard.design.grid.type_at(helm), "", "Ctrl+Shift+Z redoes too")


func test_saving_and_loading_blueprints() -> void:
	var world := await open_world()
	var shipyard: Shipyard = world.shipyard
	var full := shipyard.design.grid.blocks.size()
	shipyard.save_blueprint("Test Ship")
	assert_eq(shipyard.note_text(), "Saved \"Test Ship\".")
	assert_true(FileAccess.file_exists(Blueprint.path_for("Test Ship", _dir)), "the file exists")
	assert_eq(shipyard.blueprint_name, "Test Ship")
	press_button(shipyard, "Blueprints")
	assert_true(button(shipyard, "Test Ship") != null, "the list shows it")
	var cells := shipyard.design.grid.blocks.keys().filter(func(c: Vector3i) -> bool: return shipyard.design.grid.type_at(c) == "balloon")
	for i in 5:
		shipyard.design.remove(cells[i])
	shipyard.load_blueprint(Blueprint.path_for("Test Ship", _dir))
	assert_eq(shipyard.design.grid.blocks.size(), full, "the block count is back")
	assert_eq(shipyard.note_text(), "Loaded \"Test Ship\".")
	shipyard.design.undo()
	assert_eq(shipyard.design.grid.blocks.size(), full - 5, "undo gives the edited design")


func test_saving_over_a_blueprint_asks_first() -> void:
	var world := await open_world()
	var shipyard: Shipyard = world.shipyard
	var path := Blueprint.path_for("Test Ship", _dir)
	shipyard.save_blueprint("Test Ship")
	var first := FileAccess.get_file_as_string(path)
	shipyard.design.remove(shipyard.design.grid.cells_of("balloon")[0])
	shipyard.save_blueprint("Test Ship")
	assert_eq(shipyard.note_text(), "\"Test Ship\" already exists. Save again to replace it.")
	assert_eq(FileAccess.get_file_as_string(path), first, "unchanged")
	shipyard.save_blueprint("Test Ship")
	assert_eq(shipyard.note_text(), "Saved \"Test Ship\".")
	assert_true(FileAccess.get_file_as_string(path) != first, "replaced")


func test_a_bad_blueprint_file_says_what_is_wrong() -> void:
	var world := await open_world()
	var shipyard: Shipyard = world.shipyard
	DirAccess.make_dir_recursive_absolute(_dir)
	var path := _dir.path_join("bad.skyship.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"format": "skywright-blueprint", "version": 1, "name": "X", "blocks": [[0, 0, 0, "wing", 0]]}')
	file.close()
	var before := shipyard.design.grid.blocks.duplicate(true)
	shipyard.load_blueprint(path)
	assert_eq(shipyard.note_text(), "Block 1 is an unknown type, \"wing\".")
	assert_eq(shipyard.design.grid.blocks, before, "the design is unchanged")
	assert_false(shipyard.design.can_undo(), "nothing to undo")


func test_painting_a_block_type() -> void:
	var world := await open_world()
	var shipyard: Shipyard = world.shipyard
	shipyard.select("balloon")
	var red := Color("c0392b")
	var swatch: Button = null
	for node in shipyard.find_children("*", "Button", true, false):
		if (node as Button).tooltip_text == "c0392b":
			swatch = node
	assert_true(swatch != null, "a red swatch")
	swatch.pressed.emit()
	assert_eq(shipyard.design.grid.paint.get("balloon"), red)
	var mesh: ArrayMesh = shipyard.view.ship_mesh.mesh
	var found := false
	for surface in mesh.get_surface_count():
		for color: Color in mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]:
			found = found or color.is_equal_approx(red)
	assert_true(found, "the view draws red")
	press_button(shipyard, "Default")
	assert_false(shipyard.design.grid.paint.has("balloon"), "back to its own colour")


func test_a_test_flight_and_back_keeps_the_design() -> void:
	var world := await open_world()
	var shipyard: Shipyard = world.shipyard
	var starter: Ship = world.ship
	assert_true(shipyard.design.place(Vector3i(0, 0, -12), "frame"), "a block placed")
	var blocks := shipyard.design.grid.blocks.size()
	press_button(shipyard, "Test flight (F)")
	var trial: Ship = world.ship
	assert_true(trial != starter and trial.test, "aboard a test ship")
	assert_eq(trial.grid.blocks.size(), blocks, "built to the design")
	assert_eq(world.player.crew.station, trial.helm, "at its helm")
	assert_true(world.shipyard == null, "the shipyard is closed")
	assert_true(world.player.enabled, "your controls are on")
	press_key(world, "shipyard")
	assert_eq(world.ship, starter, "back aboard the starter")
	assert_true(world.shipyard != null, "the shipyard is open again")
	if world.shipyard != null:
		assert_eq((world.shipyard as Shipyard).design.grid.blocks.size(), blocks, "with the placed block")
		assert_false(world.player.enabled)


func test_launch_sails_the_design() -> void:
	var world := await open_world()
	var shipyard: Shipyard = world.shipyard
	var starter: Ship = world.ship
	press_button(shipyard, "Launch")
	var ship: Ship = world.ship
	assert_true(ship != starter and not ship.test, "a new ship of your own")
	assert_eq(world.player.crew.station, ship.helm, "you're at its helm")
	assert_true(world.shipyard == null, "the shipyard is closed")
	assert_false(world.sync.ships.values().has(starter), "the starter is gone")


func test_the_design_is_kept_between_visits() -> void:
	var world := await open_world()
	assert_true((world.shipyard as Shipyard).design.place(Vector3i(0, 0, -12), "frame"), "a block placed")
	press_key(world, "shipyard")
	assert_true(world.shipyard == null, "closed")
	press_key(world, "shipyard")
	assert_eq((world.shipyard as Shipyard).design.grid.type_at(Vector3i(0, 0, -12)), "frame", "the block is still there")


func test_the_hud_says_b_opens_the_shipyard_at_the_dock() -> void:
	var world := solo_world()
	await get_tree().process_frame
	world.player.crew.position = Vector3(0, 1, -4)  # at the bow, out of the helm's reach
	await get_tree().process_frame
	assert_eq(world.hud._prompt.text, "B   Shipyard")
	var ship: Ship = world.ship
	ship.global_position += Vector3(2000, 0, 0)
	ship.reset_physics_interpolation()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(world.hud._prompt.text, "", "not away from it")


func test_leaving_with_the_shipyard_open_gives_back_the_3d() -> void:
	var world := await open_world()
	var viewport := world.get_viewport()
	assert_true(viewport.disable_3d, "the world isn't drawn behind the shipyard")
	world.get_parent().remove_child(world)
	assert_false(viewport.disable_3d, "drawn again once the world goes")
	world.free()


func test_the_name_box_gives_up_focus_when_you_click_the_view() -> void:
	var world := await open_world()
	var shipyard: Shipyard = world.shipyard
	var edit: LineEdit = shipyard.find_children("*", "LineEdit", true, false)[0]
	shipyard._blueprints.visible = true
	edit.grab_focus()
	assert_true(edit.has_focus(), "the name box has focus")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(4, 4)
	shipyard._on_view_input(click)
	assert_true(shipyard.get_viewport().gui_get_focus_owner() == null, "a click on the view takes it away")
	var turn := shipyard.block_rotation
	key(shipyard, KEY_R)
	assert_true(shipyard.block_rotation != turn, "and R turns the block")
	assert_eq(edit.text, Blueprint.DEFAULT_NAME, "without typing into the name")
	for each in shipyard.find_children("*", "Button", true, false):
		assert_eq((each as Button).focus_mode, Control.FOCUS_NONE, "buttons don't take focus")


func test_a_failed_save_says_so_and_keeps_the_old_file() -> void:
	var world := await open_world()
	var shipyard: Shipyard = world.shipyard
	DirAccess.make_dir_recursive_absolute(_dir)
	var path := Blueprint.path_for("Wreck", _dir)
	DirAccess.make_dir_recursive_absolute(path)  # a folder where the file should go: the rename can't work
	shipyard.save_blueprint("Wreck")
	assert_true(shipyard.note_text().begins_with("Couldn't save \"Wreck\""), shipyard.note_text())
	assert_false(FileAccess.file_exists(path + ".tmp"), "no half-written file is left")
	DirAccess.remove_absolute(path)
	assert_eq(Blueprint.save(shipyard.design.grid, "Fine", _dir), OK)
	assert_eq(Blueprint.save(shipyard.design.grid, "Fine", _dir), OK, "and saving over a blueprint works")


func test_a_launch_within_a_second_of_the_last_says_to_wait() -> void:
	var world := await open_world()
	world.launch(StarterShip.build())
	world.open_shipyard(false)
	(world.shipyard as Shipyard).blueprint_dir = _dir
	press_button(world.shipyard, "Test flight (F)")
	assert_eq((world.shipyard as Shipyard).note_text(), "Wait a moment, then try again.")
	assert_true(world.shipyard != null, "the shipyard stays open")


func test_coming_back_from_a_test_flight_with_the_pause_menu_open_leaves_the_shipyard_shut() -> void:
	var world := await open_world()
	press_button(world.shipyard, "Test flight (F)")
	assert_true(world.on_test_flight(), "on a test flight")
	press_key(world, "pause")
	assert_true(world._pause.visible, "paused")
	world.sync.end_test()
	assert_true(world.shipyard == null, "the shipyard stays shut behind the pause menu")
	assert_false(world.player.enabled, "your controls stay off")
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE)


func test_a_near_flat_aim_finds_nothing() -> void:
	var world := await open_world()
	var view: BuildView = (world.shipyard as Shipyard).view
	view.look_from(Vector3(0, 0, 100), Vector3(0, -0.05, 0))
	assert_eq(view.aim(Vector2(view.size) / 2.0, ShipGrid.new()), {}, "the plane is out of reach")
	view.look_from(Vector3(0, 10, 10), Vector3.ZERO)
	assert_true(view.aim(Vector2(view.size) / 2.0, ShipGrid.new()).has("place"), "but a steep look still finds it")
