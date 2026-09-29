extends TestCase
## Ships built from blocks, and flight tests: real physics, run headless, decides
## whether they fly (spec §6). Ships fly in still air unless a test says otherwise.

const START := Vector3(0, 877, 7000)


## A ship from grid, in still air at START.
func launch(grid: ShipGrid) -> Ship:
	var ship := Ship.new(grid)
	ship.calm = true
	ship.position = START
	add_child(ship)
	return ship


## Degrees the ship leans to starboard (negative: to port).
func listing(ship: Ship) -> float:
	return rad_to_deg(asin(-ship.global_basis.x.y))


## Degrees the bow points up (negative: down).
func pitch(ship: Ship) -> float:
	return rad_to_deg(asin(-ship.global_basis.z.y))


## Where the balloons' lift acts in ship space.
func lift_center(grid: ShipGrid) -> Vector3:
	var sum := Vector3.ZERO
	for cell in grid.cells_of("balloon"):
		sum += Vector3(cell)
	return sum / grid.cells_of("balloon").size()


func test_a_ship_takes_its_mass_and_shape_from_its_blocks() -> void:
	var grid := StarterShip.build()
	var ship := launch(grid)
	var props := grid.mass_properties()
	assert_eq(ship.mass, props["mass"])
	assert_eq(ship.center_of_mass, props["center"])
	assert_eq(ship.inertia, props["inertia"])
	assert_eq(ship.find_children("*", "CollisionShape3D", false, false).size(), grid.merged_boxes().size())
	assert_eq(ship.max_thrust(), 5000.0, "one engine drives both propellers at full power")


func test_the_starter_ship_floats_where_the_numbers_say() -> void:
	var ship := launch(StarterShip.build())
	assert_near(ship.trim_to_float_at(START.y), 1.0, 0.01, "she floats near 877 m at trim 1")
	await simulate(60.0)
	assert_near(ship.global_position.y, START.y, 25.0, "and stays near there")


func test_a_balanced_ship_holds_level() -> void:
	var ship := launch(StarterShip.build())
	await simulate(60.0)
	assert_near(listing(ship), 0.0, 0.3)
	assert_near(pitch(ship), 0.0, 0.3)


func test_a_lopsided_ship_lists_toward_its_heavy_side() -> void:
	var grid := StarterShip.build()
	for z in range(-2, 4):
		grid.set_block(Vector3i(3, 0, z), "iron")  # iron bolted along the starboard side
	var props := grid.mass_properties()
	var com: Vector3 = props["center"]
	var lift := lift_center(grid)
	var expected := rad_to_deg(atan2(com.x - lift.x, lift.y - com.y))  # the lift ends up straight above the weight
	var ship := launch(grid)
	await simulate(60.0)
	assert_true(expected > 2.0, "the test ship is lopsided enough to see (%.2f°)" % expected)
	assert_near(listing(ship), expected, 0.3, "lists to starboard as the balance says")


func test_an_overloaded_ship_sinks() -> void:
	var grid := StarterShip.build()
	for z in range(-4, 4):
		for x in [-1, 0, 1]:
			grid.set_block(Vector3i(x, 1, z), "iron")
	var ship := launch(grid)
	assert_true(ship.trim_to_float_at(Tuning.ROIL_ALTITUDE) > Tuning.TRIM_MAX, "too heavy to float anywhere")
	await simulate(40.0)
	assert_true(ship.global_position.y < Tuning.ROIL_ALTITUDE, "sank into the Roil (at %.0f m)" % ship.global_position.y)
	assert_true(ship.linear_velocity.y < -5.0, "and is still sinking")


func test_top_speed_is_within_ten_percent_of_the_estimate() -> void:
	var ship := launch(StarterShip.build())
	ship.throttle = 1.0
	await simulate(240.0)
	var forward_area := 0.0
	for zone in ship.grid.drag_zones():
		forward_area += zone["area"].z
	var estimate := ShipForces.top_speed(ship.max_thrust(), forward_area, ship.global_position.y)
	var speed := ship.linear_velocity.length()
	assert_near(speed, estimate, estimate * 0.1, "estimate %.1f m/s" % estimate)


func test_starboard_rudder_turns_to_starboard() -> void:
	var ship := launch(StarterShip.build())
	ship.throttle = 1.0
	await simulate(30.0)
	var before := ship.heading()
	ship.rudder = 1.0
	await simulate(10.0)
	var turned := rad_to_deg(wrapf(before - ship.heading(), -PI, PI))
	assert_true(turned > 30.0, "turned %.0f° clockwise" % turned)


func test_a_physics_blow_up_puts_the_ship_back() -> void:
	var ship := launch(StarterShip.build())
	await simulate(0.5)
	var good := ship.global_transform
	ship.linear_velocity = Vector3(1000, 0, 0)
	await simulate(0.1)
	assert_true(ship.global_position.distance_to(good.origin) < 1.0, "back where it was")
	assert_true(ship.linear_velocity.length() < 1.0, "and stopped")
