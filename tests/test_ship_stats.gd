extends TestCase
## What ShipStats says about designs, without flying them.

const ALT := 880.0


func add_up(grid: ShipGrid, from: Vector3i, to: Vector3i, type: String) -> void:
	for x in range(from.x, to.x + 1):
		for y in range(from.y, to.y + 1):
			for z in range(from.z, to.z + 1):
				grid.set_block(Vector3i(x, y, z), type)


func test_the_starter_ship_by_the_numbers() -> void:
	var grid := StarterShip.build()
	var s := ShipStats.of(grid, ALT)
	assert_eq(s.mass, grid.mass_properties()["mass"])
	assert_near(s.weight, s.mass * 9.81, 0.001)
	assert_near(s.lift, 131.0 * 900.0 * ShipForces.air_density(ALT), 1.0)
	var ship := Ship.new(grid)
	add_child(ship)
	assert_near(ship.trim_to_float_at(s.float_altitude), 1.0, 1e-4)
	assert_near(ship.trim_to_float_at(s.ceiling), Tuning.TRIM_MAX, 1e-4)
	assert_eq(s.thrust, 5000.0)
	var area := 0.0
	for zone in grid.drag_zones():
		area += zone["area"].z
	assert_eq(s.top_speed, ShipForces.top_speed(5000.0, area, ALT))
	assert_true(s.climb_rate > 0.0)
	assert_eq(s.warnings.size(), 0, str(s.warnings))


func test_lift_stones_lift_the_same_at_any_height() -> void:
	var grid := ShipGrid.new()
	grid.set_block(Vector3i.ZERO, "helm")
	grid.set_block(Vector3i(0, 1, 0), "lift_stone")
	assert_eq(ShipStats.of(grid, 300.0).lift, ShipStats.of(grid, 1500.0).lift)


func test_an_overloaded_ship_is_too_heavy_to_fly() -> void:
	var grid := StarterShip.build()
	add_up(grid, Vector3i(-1, 1, -4), Vector3i(1, 1, 3), "iron")
	var s := ShipStats.of(grid, ALT)
	assert_eq(s.ceiling, -INF)
	assert_true(s.warnings.has("Too heavy to fly: she sinks into the Roil."), str(s.warnings))


func test_a_ship_too_heavy_for_this_height_says_how_high_she_can_go() -> void:
	var grid := StarterShip.build()
	for cell in grid.cells_of("balloon"):
		if cell.y == 10:
			grid.blocks.erase(cell)
	var s := ShipStats.of(grid, ALT)
	assert_true(s.ceiling > 200.0 and s.ceiling < ALT, "ceiling %.0f" % s.ceiling)
	assert_true(s.warnings.has("Too heavy to hold 880 m: she can climb no higher than %d m." % roundi(s.ceiling)), str(s.warnings))


func test_lift_stones_that_carry_her_alone_climb_forever() -> void:
	var grid := ShipGrid.new()
	grid.set_block(Vector3i.ZERO, "helm")
	grid.set_block(Vector3i(0, 1, 0), "lift_stone")
	var s := ShipStats.of(grid, ALT)
	assert_eq(s.float_altitude, INF)
	assert_true(s.warnings.has("Too much lift: her lift stones alone carry her, so she'll climb forever."), str(s.warnings))


func test_a_lopsided_ship_says_which_way_it_lists() -> void:
	for side in [3, -3]:
		var grid := StarterShip.build()
		for z in range(-2, 4):
			grid.set_block(Vector3i(side, 0, z), "iron")
		var s := ShipStats.of(grid, ALT)
		var com := s.center_of_mass
		var col := s.center_of_lift
		assert_near(s.list, rad_to_deg(atan2(com.x - col.x, col.y - com.y)), 1e-4)
		var text := "Lists %d° to %s." % [roundi(absf(s.list)), "starboard" if side > 0 else "port"]
		assert_true(s.warnings.has(text), "%s in %s" % [text, str(s.warnings)])


func test_a_nose_heavy_ship_is_down_by_the_bow() -> void:
	var grid := StarterShip.build()
	add_up(grid, Vector3i(-1, 1, -6), Vector3i(1, 1, -6), "iron")
	grid.set_block(Vector3i(0, 2, -6), "iron")
	var s := ShipStats.of(grid, ALT)
	assert_true(s.bow_down > 2.0, "bow down %.2f" % s.bow_down)
	assert_true(s.warnings.has("Down by the bow %d°." % roundi(s.bow_down)), str(s.warnings))


func test_a_top_heavy_ship_will_roll_over() -> void:
	var grid := ShipGrid.new()
	add_up(grid, Vector3i(-1, 0, -1), Vector3i(1, 0, 1), "balloon")
	add_up(grid, Vector3i(-1, 1, -1), Vector3i(1, 1, 1), "deck")
	grid.set_block(Vector3i(0, 2, 0), "helm")
	var s := ShipStats.of(grid, ALT)
	assert_true(s.warnings.has("Top-heavy: her lift is below her weight, so she'll roll over."), str(s.warnings))
	for w in s.warnings:
		assert_false(w.begins_with("Lists") or w.begins_with("Down by"), w)


func test_missing_parts_are_named() -> void:
	var no_helm := StarterShip.build()
	no_helm.blocks.erase(Vector3i(0, 3, 4))
	assert_eq(ShipStats.of(no_helm, ALT).warnings[0], "Every ship needs a helm.")

	var none := StarterShip.build()
	for cell in none.cells_of("propeller"):
		none.blocks.erase(cell)
	assert_eq(ShipStats.of(none, ALT).warnings, PackedStringArray(["No propellers: she can only drift."]))

	var no_engine := StarterShip.build()
	no_engine.blocks.erase(no_engine.cells_of("engine")[0])
	assert_eq(ShipStats.of(no_engine, ALT).warnings[0], "No engine: her propellers won't turn.")

	var aft := StarterShip.build()
	for cell in aft.cells_of("propeller"):
		aft.set_block(cell, "propeller", Blocks.rotation_of(Basis(Vector3.UP, PI)))
	assert_eq(ShipStats.of(aft, ALT).warnings[0], "None of her propellers push her forward.")

	var no_rudder := StarterShip.build()
	for cell in no_rudder.cells_of("rudder"):
		no_rudder.blocks.erase(cell)
	assert_eq(ShipStats.of(no_rudder, ALT).warnings, PackedStringArray(["No rudder: she can't steer."]))

	var both := StarterShip.build()
	both.blocks.erase(Vector3i(0, 3, 4))
	for cell in both.cells_of("rudder"):
		both.blocks.erase(cell)
	assert_eq(ShipStats.of(both, ALT).warnings, PackedStringArray(["Every ship needs a helm.", "No rudder: she can't steer."]))


func test_an_empty_design_only_needs_a_helm() -> void:
	var s := ShipStats.of(ShipGrid.new(), ALT)
	assert_eq(s.warnings, PackedStringArray(["Every ship needs a helm."]))
	for value in [s.mass, s.lift, s.thrust, s.top_speed, s.climb_rate, s.list, s.bow_down]:
		assert_false(is_nan(value))


func test_the_readout() -> void:
	var text := ShipStats.of(StarterShip.build(), ALT).describe()
	assert_true(text.contains("Blocks     295 of 4000"), text)
	assert_true(text.contains("Weight     9.2 t"), text)
	assert_true(text.contains("Thrust     5.0 kN"), text)
	var lines := text.split("\n")
	assert_eq(lines.size(), 8)
	for i in 8:
		assert_true(lines[i].begins_with(["Blocks     ", "Weight     ", "Lift       ", "Floats at  ", "Ceiling    ", "Thrust     ", "Top speed  ", "Climb      "][i]), lines[i])


func test_blocks_not_joined_to_the_helm_are_named() -> void:
	var loose := StarterShip.build()
	for z in range(-1, 2):
		loose.set_block(Vector3i(0, -4, z), "frame")  # hung under the keel with a gap
	assert_true(ShipStats.of(loose, ALT).warnings.has("3 blocks aren't joined to the helm: they'll fall away when she's hit."),
			str(ShipStats.of(loose, ALT).warnings))
	for warning in ShipStats.of(StarterShip.build(), ALT).warnings:
		assert_false(warning.contains("joined"), "the starter ship is one piece: " + warning)
