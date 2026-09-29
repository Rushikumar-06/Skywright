extends TestCase
## Ship blocks and the maths built on them: mass properties, collision boxes and
## drag zones (spec §4.4).


func grid_of(cells: Dictionary) -> ShipGrid:
	var grid := ShipGrid.new()
	for cell: Vector3i in cells:
		grid.set_block(cell, cells[cell])
	return grid


func test_blocks_start_at_full_hit_points_and_can_be_replaced() -> void:
	var grid := ShipGrid.new()
	grid.set_block(Vector3i(1, 2, 3), "frame")
	assert_eq(grid.blocks[Vector3i(1, 2, 3)], {"type": "frame", "rotation": 0, "hp": 100})
	grid.set_block(Vector3i(1, 2, 3), "iron", 5)
	assert_eq(grid.blocks[Vector3i(1, 2, 3)], {"type": "iron", "rotation": 5, "hp": 300})
	assert_eq(grid.type_at(Vector3i(1, 2, 3)), "iron")
	assert_eq(grid.type_at(Vector3i(0, 0, 0)), "")
	assert_eq(grid.cells_of("iron"), [Vector3i(1, 2, 3)] as Array[Vector3i])


func test_one_block_mass_properties() -> void:
	var props := grid_of({Vector3i(2, 0, 0): "frame"}).mass_properties()
	assert_eq(props["mass"], 60.0)
	assert_eq(props["center"], Vector3(2, 0, 0))
	assert_eq(props["inertia"], Vector3(10, 10, 10), "a 60 kg cube: m/6 about each axis")


func test_centre_of_mass_leans_to_the_heavy_block() -> void:
	var props := grid_of({Vector3i(0, 0, 0): "iron", Vector3i(4, 0, 0): "frame"}).mass_properties()
	assert_eq(props["mass"], 240.0)
	assert_eq(props["center"], Vector3(1, 0, 0), "(0 × 180 + 4 × 60) / 240")


func test_inertia_adds_the_parallel_axis_term() -> void:
	var props := grid_of({Vector3i(-1, 0, 0): "frame", Vector3i(1, 0, 0): "frame"}).mass_properties()
	# Each cube: 10 about every axis, plus 60 × 1² about y and z.
	assert_eq(props["inertia"], Vector3(20, 140, 140))


func test_a_solid_block_merges_into_one_box() -> void:
	var cells := {}
	for x in 3:
		for y in 2:
			for z in 4:
				cells[Vector3i(x, y, z)] = "deck"
	assert_eq(grid_of(cells).merged_boxes(), [AABB(Vector3(-0.5, -0.5, -0.5), Vector3(3, 2, 4))] as Array[AABB])


func test_merged_boxes_cover_every_solid_cell_once_and_skip_ladders() -> void:
	var grid := StarterShip.build()
	var boxes := grid.merged_boxes()
	var solid := 0
	for cell: Vector3i in grid.blocks:
		if grid.type_at(cell) != "ladder":
			solid += 1
			var inside := 0
			for box in boxes:
				if box.has_point(Vector3(cell)):
					inside += 1
			assert_eq(inside, 1, "%s is in exactly one box" % cell)
	var volume := 0.0
	for box in boxes:
		volume += box.get_volume()
	assert_eq(volume, float(solid))
	for cell in grid.cells_of("ladder"):
		for box in boxes:
			assert_false(box.has_point(Vector3(cell)), "ladder %s stays open to walk into" % cell)
	assert_true(boxes.size() < solid / 5, "%d boxes for %d cells" % [boxes.size(), solid])


func test_drag_zone_areas_are_outlines_along_each_axis() -> void:
	var zones := grid_of({Vector3i(0, 0, 0): "deck", Vector3i(1, 0, 0): "deck"}).drag_zones()
	assert_eq(zones.size(), 1)
	assert_eq(zones[0]["center"], Vector3(0.5, 0, 0))
	assert_eq(zones[0]["area"], Vector3(1, 2, 2), "a 2 × 1 × 1 bar seen along x, y and z")


func test_drag_zones_split_every_four_metres() -> void:
	var cells := {}
	for x in range(-4, 4):
		cells[Vector3i(x, 0, 0)] = "deck"
	var zones := grid_of(cells).drag_zones()
	assert_eq(zones.size(), 2)
	var total := Vector3.ZERO
	for zone in zones:
		total += zone["area"]
	assert_eq(total, Vector3(1, 8, 8), "each zone's outline, summed")


func test_the_starter_ship_balances_under_its_envelope() -> void:
	var grid := StarterShip.build()
	var props := grid.mass_properties()
	var com: Vector3 = props["center"]
	var balloons := grid.cells_of("balloon")
	var lift := Vector3.ZERO
	for cell in balloons:
		lift += Vector3(cell)
	lift /= balloons.size()
	assert_eq(com.x, 0.0, "port and starboard weigh the same")
	assert_near(com.z, lift.z, 0.01, "her weight hangs under her lift, so she flies level")
	assert_true(lift.y - com.y > 5.0, "the lift is well above the weight, so she rights herself")
	var weight: float = props["mass"] * 9.81
	var floats_at := Tuning.ROIL_ALTITUDE + Tuning.AIR_SCALE_HEIGHT * log(balloons.size() * Tuning.BALLOON_LIFT / weight)
	assert_near(floats_at, 877.0, 5.0, "at trim 1 she floats at about 877 m")
