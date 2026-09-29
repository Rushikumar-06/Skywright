extends TestCase
## The world scene: the starter ship with you aboard, islands to fly between, the
## sky's day, and the helm's instruments.


func test_you_start_aboard_the_starter_ship_by_the_helm() -> void:
	var world: Node3D = (load("res://src/world/world.tscn") as PackedScene).instantiate()
	add_child(world)
	await get_tree().process_frame
	var ship: Ship = world.ship
	var player: PlayerController = world.player
	assert_eq(ship.global_position, world.START)
	assert_eq(player.crew.get_parent(), ship.interior)
	assert_eq(player.prompt(), "Take the helm")
	assert_true(player.camera.is_current())
	world.queue_free()
	await get_tree().process_frame


func test_islands_are_solid() -> void:
	var island := Island.create(Vector3(0, 800, 0), 50.0)
	add_child(island)
	var shapes := island.find_children("*", "CollisionShape3D", false, false)
	assert_eq(shapes.size(), 2, "the rock and the grassy cap")
	for shape: CollisionShape3D in shapes:
		assert_true(shape.shape != null)


func test_ramming_an_island_is_survivable() -> void:
	add_child(Island.create(Vector3(0, 877, 6700), 60.0))
	var ship := Ship.new(StarterShip.build())
	ship.calm = true
	ship.position = Vector3(0, 877, 7000)
	ship.throttle = 1.0
	add_child(ship)
	var crew := CrewMember.new(ship, ship.crew_spawn())
	ship.interior.add_child(crew)
	var worst := [0.0]
	var standing := [0]
	await simulate(40.0, func(_tick: int) -> void:
		worst[0] = maxf(worst[0], ship.angular_velocity.length())
		if crew.is_on_floor():
			standing[0] += 1)
	assert_true(ship.global_position.z > 6700.0, "stopped by the island (at z %.0f)" % ship.global_position.z)
	assert_true(worst[0] < Ship.MAX_SPIN / 4.0, "no blow-up (spun at %.2f rad/s at most)" % worst[0])
	assert_true(standing[0] > 40 * 60 - 60, "the crew kept their feet (%d ticks)" % standing[0])


func test_the_helm_readout() -> void:
	var ship := Ship.new(StarterShip.build())
	ship.calm = true
	ship.position = Vector3(0, 877, 7000)
	add_child(ship)
	ship.throttle = 0.5
	ship.rudder = -0.4
	var text := Hud.readout(ship)
	assert_true(text.contains("50% ahead"), text)
	assert_true(text.contains("40% port"), text)
	assert_true(text.contains("Heading   000°"), text)
	assert_true(text.contains("Altitude   877 m"), text)
	assert_true(text.contains("Autopilot off"), text)
