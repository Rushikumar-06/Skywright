extends NetCase
## The map and compass that fill in as you explore.

const START := WorldGen.START


## Presses action in world, as a key press would.
func press(world: Node3D, action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	world._unhandled_input(event)


func test_exploring_reveals_cells_around_you() -> void:
	var seen := Exploration.new()
	assert_false(seen.seen(START), "nothing seen yet")
	assert_eq(seen.seen_fraction(), 0.0)
	assert_true(seen.reveal(START), "something new")
	assert_true(seen.seen(START))
	assert_true(seen.seen(START + Vector3(1100.0, 0.0, 0.0)), "1,100 m away is in sight")
	assert_false(seen.seen(START + Vector3(1400.0, 0.0, 0.0)), "1,400 m away is not")
	assert_true(seen.seen_fraction() > 0.0)
	assert_false(seen.reveal(START), "nothing new the second time")
	assert_eq(seen.image.get_size(), Vector2i(Exploration.SIZE, Exploration.SIZE))
	assert_eq(seen.image.get_format(), Image.FORMAT_L8)


func test_the_edges_of_the_world_are_safe() -> void:
	var seen := Exploration.new()
	for p in [Vector3(9000.0, 0.0, 9000.0), Vector3(-8192.0, 0.0, -8192.0), Vector3(8191.9, 0.0, 0.0)]:
		seen.reveal(p)
		seen.seen(p)
	assert_false(seen.seen(Vector3(9000.0, 0.0, 9000.0)), "nothing outside the grid")
	assert_false(seen.seen(Vector3(-9000.0, 0.0, 0.0)))
	assert_true(seen.seen(Vector3(8191.9, 0.0, 0.0)), "the last cell is inside")
	assert_true(seen.seen(Vector3(-8192.0, 0.0, -8192.0)), "and the first")


func test_the_map_shows_only_what_you_have_seen() -> void:
	var gen := WorldGen.new(7)
	var seen := Exploration.new()
	var map := MapView.new(gen, seen, null, func() -> Array: return [START, 0.0])
	seen.reveal(START)
	var towns: Array[int] = [0]
	assert_eq(map.known_towns(), towns, "only the town you start at")
	seen.reveal(gen.towns[2]["dock"])
	towns = [0, 2]
	assert_eq(map.known_towns(), towns, "and the one you have flown to")
	var landmarks: Array[int] = []
	for i in gen.landmarks.size():
		if seen.seen(gen.landmarks[i]["at"]):
			landmarks.append(i)
	assert_eq(map.known_landmarks(), landmarks, "landmarks likewise")
	assert_true(landmarks.size() < gen.landmarks.size(), "not all of them")
	var everything := Exploration.new()
	for x in range(-8000, 8001, 1000):
		for z in range(-8000, 8001, 1000):
			everything.reveal(Vector3(x, 0.0, z))
	var whole := MapView.new(gen, everything, null, func() -> Array: return [START, 0.0])
	assert_eq(whole.known_landmarks().size(), gen.landmarks.size(), "a fully explored world shows all")
	map.free()
	whole.free()


func test_the_map_places_the_world() -> void:
	var map := MapView.new(WorldGen.new(7), Exploration.new(), null, func() -> Array: return [START, 0.0])
	map.size = Vector2(1000.0, 1000.0)
	assert_near(map.place_of(Vector3.ZERO).x, 500.0, 0.01)
	assert_near(map.place_of(Vector3.ZERO).y, 500.0, 0.01)
	assert_near(map.place_of(Vector3(8000.0, 0.0, 0.0)).x, 960.0, 1.0, "40 px from the right edge")
	assert_near(map.place_of(Vector3(0.0, 0.0, -8000.0)).y, 40.0, 1.0, "north is up")
	map.free()


func test_m_opens_and_closes_the_map() -> void:
	var world := solo_world()
	await get_tree().process_frame
	assert_true(world.map != null)
	assert_false(world.map.visible, "hidden at first")
	assert_true(world.hud.compass.visible)
	press(world, "map")
	assert_true(world.map.visible, "M opens it")
	assert_false(world.hud.compass.visible, "and hides the compass")
	assert_true(world.player.enabled, "you can still steer")
	press(world, "map")
	assert_false(world.map.visible, "M closes it")
	assert_true(world.hud.compass.visible)
	press(world, "map")
	press(world, "pause")
	assert_false(world.map.visible, "Esc closes it")
	assert_true(world.player.enabled, "without opening the pause menu")
	assert_true(world.hud.compass.visible)
	await get_tree().process_frame


func test_m_only_mirrors_in_the_shipyard() -> void:
	var world := solo_world()
	await get_tree().process_frame
	press(world, "shipyard")
	assert_true(world.shipyard != null, "the shipyard is open")
	press(world, "map")
	assert_false(world.map.visible, "the map stays shut")
	world.close_shipyard()
	press(world, "pause")
	press(world, "map")
	assert_false(world.map.visible, "and while paused")


func test_opening_the_shipyard_closes_the_map() -> void:
	var world := solo_world()
	await get_tree().process_frame
	press(world, "map")
	assert_true(world.map.visible, "the map is open")
	press(world, "shipyard")
	assert_true(world.shipyard != null, "B opens the shipyard")
	assert_false(world.map.visible, "and closes the map")
	world.close_shipyard()
	assert_false(world.map.visible, "which doesn't come back when the shipyard closes")
	assert_true(world.hud.compass.visible, "but the compass does")


func test_the_compass_reads_the_way_you_look() -> void:
	var world := solo_world()
	await get_tree().process_frame
	await get_tree().process_frame
	var compass: Compass = world.hud.compass
	assert_near(compass.bearing, 0.0, 1.0, "facing the bow, which points north")
	assert_eq(compass.region, "The Calm Reaches")
	assert_eq(Compass.label_at(90.0), "E")
	assert_eq(Compass.label_at(225.0), "SW")
	assert_eq(Compass.label_at(0.0), "N")
	assert_eq(Compass.label_at(360.0), "N")
	assert_eq(Compass.label_at(10.0), "")


func test_you_explore_as_you_fly() -> void:
	var world := solo_world()
	await get_tree().process_frame
	assert_true(world.exploration.seen(START), "the start is seen at once")
	world.ship.global_position = START + Vector3(-3000.0, 0.0, 0.0)
	world.ship.reset_physics_interpolation()
	await play(1.0)
	assert_true(world.exploration.seen(world.ship.global_position), "and where you fly")
