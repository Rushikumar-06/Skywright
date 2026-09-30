extends TestCase
## A ship designed in the shipyard flies as her stats say (spec §6).

const AT := Vector3(0, 880, 7000)

var dir := "user://test_designed_%d" % randi()


func after_each() -> void:
	for file in DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray():
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


## A small ship built only through ShipDesign, mirror on: a 3 × 9 deck on a keel
## with iron in it, an engine, two propellers and a rudder at the stern, a helm,
## and posts up to a 3 × 9 × 2 envelope.
func skiff() -> ShipDesign:
	var design := ShipDesign.new()
	design.mirror = true
	for z in range(-4, 5):
		for x in range(0, 2):
			design.place(Vector3i(x, 0, z), "deck")
		design.place(Vector3i(0, -1, z), "iron" if z == -2 or z == -1 else "frame")
	design.remove(Vector3i(0, -1, -4))
	design.place(Vector3i(0, -1, -4), "engine")
	design.place(Vector3i(2, 0, 4), "propeller")  # beside the deck, so joined to it
	design.place(Vector3i(0, 0, 5), "rudder")
	design.place(Vector3i(0, 1, 3), "helm")
	design.place(Vector3i(0, 1, 4), "deck")
	for y in range(1, 5):
		for z in [-4, 4]:
			design.place(Vector3i(1, y, z), "frame")
	for y in range(5, 7):
		for z in range(-4, 5):
			for x in range(0, 2):
				design.place(Vector3i(x, y, z), "balloon")
	return design


func launch(grid: ShipGrid, at: Vector3) -> Ship:
	var ship := Ship.new(grid)
	ship.calm = true
	ship.position = at
	add_child(ship)
	return ship


func listing(ship: Ship) -> float:
	return rad_to_deg(asin(-ship.global_basis.x.y))


func pitch(ship: Ship) -> float:
	return rad_to_deg(asin(-ship.global_basis.z.y))


func test_a_designed_ship_round_trips_through_a_blueprint() -> void:
	var design := skiff()
	design.set_paint("balloon", Color.RED)
	assert_eq(Blueprint.save(design.grid, "Skiff", dir), OK)
	var loaded := Blueprint.load_file(Blueprint.path_for("Skiff", dir))
	assert_eq(loaded.get("problem"), null)
	var grid: ShipGrid = loaded["grid"]
	assert_eq(grid.blocks, design.grid.blocks, "same blocks and rotations")
	assert_eq(grid.paint, design.grid.paint, "same paint")
	assert_eq(ShipStats.of(grid, 880.0).warnings, PackedStringArray(), "nothing is lacking")


func test_a_designed_ship_floats_and_balances_as_her_stats_say() -> void:
	var grid := skiff().grid
	var stats := ShipStats.of(grid, 880.0)
	assert_true(stats.float_altitude > 400.0 and stats.float_altitude < 1500.0, "she floats at %.0f m" % stats.float_altitude)
	var ship := launch(grid, Vector3(AT.x, stats.float_altitude + 40.0, AT.z))
	await simulate(180.0)
	assert_near(ship.global_position.y, stats.float_altitude, 20.0, "floats at %.0f m" % stats.float_altitude)
	assert_near(listing(ship), stats.list, 0.5, "lists as the stats say")
	assert_near(pitch(ship), -stats.bow_down, 0.5, "trims as the stats say")


func test_a_designed_ship_reaches_her_top_speed() -> void:
	var grid := skiff().grid
	var ship := launch(grid, Vector3(AT.x, ShipStats.of(grid, 880.0).float_altitude, AT.z))
	ship.throttle = 1.0
	await simulate(240.0)
	var estimate := ShipStats.of(grid, ship.global_position.y).top_speed
	assert_near(ship.linear_velocity.length(), estimate, estimate * 0.1, "estimate %.1f m/s" % estimate)


func test_a_lopsided_design_lists_as_warned() -> void:
	var design := skiff()
	design.mirror = false
	design.place(Vector3i(2, -1, 0), "iron")
	design.place(Vector3i(2, -1, 1), "iron")
	var stats := ShipStats.of(design.grid, 880.0)
	var warned := false
	for warning in stats.warnings:
		warned = warned or warning.begins_with("Lists ") and warning.ends_with("° to starboard.")
	assert_true(warned, "warns of a list to starboard: %s" % [stats.warnings])
	var ship := launch(design.grid, Vector3(AT.x, stats.float_altitude, AT.z))
	await simulate(90.0)
	assert_near(listing(ship), stats.list, 0.5, "lists %.1f° as warned" % stats.list)
