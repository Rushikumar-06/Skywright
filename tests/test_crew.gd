extends TestCase
## Walking on a moving deck (spec §4.5): crew live in the ship's interior, where
## gravity is the ship's "down". Here the ship is held and rocked by the test,
## far harder than wind ever will: ±15° of roll and ±8° of pitch.

var ship: Ship
var crew: CrewMember


func board(at: Vector3) -> void:
	ship = Ship.new(StarterShip.build())
	ship.freeze = true
	ship.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	ship.position = Vector3(0, 877, 7000)
	add_child(ship)
	crew = CrewMember.new(ship, at)
	ship.interior.add_child(crew)


func rock(tick: int) -> void:
	var t := tick / 60.0
	ship.rotation = Vector3(deg_to_rad(8.0) * sin(t * 0.9), 0.0, deg_to_rad(15.0) * sin(t * 1.3))


func test_the_interior_holds_a_still_copy_of_the_hull() -> void:
	board(Vector3(0, 1.45, -2))
	var hull := ship.interior.get_child(0) as StaticBody3D
	var boxes: Array[AABB] = []
	for shape: CollisionShape3D in hull.get_children():
		boxes.append(AABB(shape.position - (shape.shape as BoxShape3D).size / 2.0, (shape.shape as BoxShape3D).size))
	assert_eq(boxes, ship.grid.merged_boxes(), "the ship's boxes, in ship space")
	assert_eq(crew.get_world_3d(), ship.interior.find_world_3d())
	assert_true(crew.get_world_3d() != ship.get_world_3d(), "a physics world of its own")


func test_standing_on_a_rolling_deck_stays_put() -> void:
	board(Vector3(0, 1.45, -2))
	await simulate(1.0)
	var start := crew.position
	var standing := [0]
	await simulate(20.0, func(tick: int) -> void:
		rock(tick)
		if crew.is_on_floor():
			standing[0] += 1)
	assert_true(crew.position.distance_to(start) < 0.05, "drifted %.3f m" % crew.position.distance_to(start))
	assert_eq(standing[0], 20 * 60, "on the deck every tick")


func test_walking_goes_along_the_deck_while_it_rolls() -> void:
	board(Vector3(0, 1.45, 0))
	await simulate(1.0)
	crew.move = Vector2(0, -1)  # forward, toward the bow
	await simulate(1.0, rock)
	assert_near(crew.position.z, -CrewMember.WALK_SPEED, 0.2, "walked 4 m toward the bow")
	assert_near(crew.position.y, 1.4, 0.05, "and stayed on the deck")


func test_jumping_leaves_the_deck_and_lands_again() -> void:
	board(Vector3(0, 1.45, -2))
	await simulate(1.0)
	crew.jump = true
	var highest := [0.0]
	await simulate(1.5, func(tick: int) -> void:
		rock(tick)
		highest[0] = maxf(highest[0], crew.position.y))
	assert_near(highest[0] - 1.4, 1.08, 0.1, "rose about a metre")
	assert_true(crew.is_on_floor(), "landed")


func test_climbing_a_ladder_up_to_the_helm_deck() -> void:
	board(Vector3(1, 1.45, 1))  # on the main deck, in front of the starboard ladder
	await simulate(1.0)
	crew.look_yaw = PI  # facing aft
	crew.move = Vector2(0, -1)
	crew.climb = 1.0
	await simulate(5.0, rock)
	assert_near(crew.position.y, 3.4, 0.05, "standing on the helm deck")
	assert_true(crew.position.z > 3.5, "past the top of the ladder")


func test_falling_overboard_brings_you_back_aboard() -> void:
	board(Vector3(0, 1.45, -2))
	var fell := [false]
	crew.fell_overboard.connect(func() -> void: fell[0] = true)
	crew.position = Vector3(0, -40, 0)
	await simulate(0.1)
	assert_true(fell[0], "fell_overboard fires")
	assert_true(crew.position.distance_to(crew.home) < 0.1, "back where you came aboard")


func test_nobody_walks_while_at_a_station() -> void:
	board(Vector3(0, 1.45, -2))
	await simulate(1.0)
	var start := crew.position
	var station := Node.new()
	add_child(station)
	crew.station = station
	crew.move = Vector2(0, -1)
	crew.jump = true
	await simulate(1.0)
	assert_true(crew.position.distance_to(start) < 0.01, "stayed put")


func test_taking_a_station_from_a_ladder_stops_the_climb() -> void:
	board(Vector3(1, 2.5, 3))  # holding on to the starboard ladder
	crew.climb = 1.0  # still held when E is pressed
	await simulate(0.2)
	var station := Node.new()
	add_child(station)
	crew.station = station
	var height := crew.position.y
	await simulate(1.0)
	assert_near(crew.position.y, height, 0.05, "stays where they took it")

