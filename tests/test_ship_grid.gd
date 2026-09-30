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


func test_to_blocks_and_back() -> void:
	var grid := StarterShip.build()
	grid.blocks[Vector3i(0, 0, 0)]["hp"] = 5  # damage comes through
	grid.set_block(Vector3i(0, -2, 0), "frame", 7)  # and so does rotation
	var sent: Variant = bytes_to_var(var_to_bytes(grid.to_blocks()))  # as the network carries it
	var copy := ShipGrid.from_blocks(sent)
	assert_true(copy != null, "it reads back")
	if copy != null:
		assert_eq(copy.blocks, grid.blocks)


func test_from_blocks_refuses_bad_ships() -> void:
	var good := StarterShip.build().to_blocks()
	assert_true(ShipGrid.from_blocks(good) != null, "the starter ship is fine")
	var too_many: Array = [[0, 0, 0, "helm", 0, 150]]
	for i in ShipGrid.MAX_BLOCKS:
		too_many.append([i % 100 - 50, i / 100 - 30, 1, "frame", 0, 100])
	var no_helm := good.filter(func(block: Array) -> bool: return block[3] != "helm")
	var cases := {
		"not an array": "a ship",
		"empty": [],
		"too many": too_many,
		"a block that isn't an array": good + ["frame"],
		"a short block": good + [[0, 20, 0, "frame"]],
		"an unknown type": good + [[0, 20, 0, "gold", 0, 100]],
		"a type that isn't text": good + [[0, 20, 0, 3, 0, 100]],
		"x past 63": good + [[64, 20, 0, "frame", 0, 100]],
		"y below -64": good + [[0, -65, 0, "frame", 0, 100]],
		"a fractional coordinate": good + [[0.5, 20, 0, "frame", 0, 100]],
		"rotation 24": good + [[0, 20, 0, "frame", 24, 100]],
		"rotation -1": good + [[0, 20, 0, "frame", -1, 100]],
		"hp 0": good + [[0, 20, 0, "frame", 0, 0]],
		"hp above the block's": good + [[0, 20, 0, "frame", 0, 101]],
		"a duplicate cell": good + [good[0]],
		"no helm": no_helm,
	}
	for problem: String in cases:
		assert_eq(ShipGrid.from_blocks(cases[problem]), null, problem)


func test_copy_is_independent() -> void:
	var grid := grid_of({Vector3i(0, 0, 0): "helm", Vector3i(1, 0, 0): "frame"})
	grid.blocks[Vector3i(1, 0, 0)]["hp"] = 7
	grid.paint = {"frame": Color.RED}
	var copy := grid.copy()
	assert_eq(copy.blocks, grid.blocks)
	assert_eq(copy.paint, grid.paint)
	copy.set_block(Vector3i(0, 0, 0), "iron")
	copy.blocks[Vector3i(1, 0, 0)]["hp"] = 1
	copy.paint["frame"] = Color.BLUE
	assert_eq(grid.type_at(Vector3i(0, 0, 0)), "helm")
	assert_eq(grid.blocks[Vector3i(1, 0, 0)]["hp"], 7)
	assert_eq(grid.paint["frame"], Color.RED)


## Header (count) plus the zstd body of the given raw bytes.
func packed(count: int, body: PackedByteArray) -> PackedByteArray:
	var data := PackedByteArray([0, 0])
	data.encode_u16(0, count)
	data.append_array(body.compress(FileAccess.COMPRESSION_ZSTD))
	return data


## Raw 7-byte block records: [x+64, y+64, z+64, type index, rotation, hp lo, hp hi].
func record(x: int, y: int, z: int, type: int, hp := 100) -> PackedByteArray:
	return PackedByteArray([x + 64, y + 64, z + 64, type, 0, hp & 255, hp >> 8])


func test_to_bytes_and_back() -> void:
	var grid := StarterShip.build()
	grid.set_block(Vector3i(0, 20, 0), "frame", 13)
	grid.blocks[Vector3i(0, 20, 0)]["hp"] = 5
	var bytes := grid.to_bytes()
	assert_true(bytes.size() < 2000, "the starter is %d bytes" % bytes.size())
	var copy := ShipGrid.from_bytes(bytes)
	assert_true(copy != null, "it reads back")
	if copy != null:
		assert_eq(copy.blocks, grid.blocks)
	var big := ShipGrid.new()
	for x in 20:
		for y in 10:
			for z in 20:
				big.set_block(Vector3i(x, y, z), "frame")
	big.set_block(Vector3i(0, 0, 0), "helm")
	assert_eq(big.blocks.size(), 4000)
	assert_true(big.to_bytes().size() < 40000, "4,000 blocks are %d bytes" % big.to_bytes().size())
	assert_eq(ShipGrid.from_bytes(big.to_bytes()).blocks, big.blocks)


func test_from_bytes_refuses_junk() -> void:
	var helm := record(0, 0, 0, Tuning.BLOCKS.keys().find("helm"))
	var frame := Tuning.BLOCKS.keys().find("frame")
	var cut := packed(2, helm + record(1, 0, 0, frame))
	var bad_y := helm + record(1, 0, 0, frame)
	bad_y[8] = 200
	var junk_after := packed(1, helm)
	junk_after.append_array(PackedByteArray([1, 2, 3, 4, 5]))
	var cases := {
		"a string": "ship",
		"no bytes": [],
		"two bytes": PackedByteArray([1, 0]),
		"count 0": packed(0, PackedByteArray()),
		"count 4001": packed(4001, PackedByteArray()),
		"junk after a count": PackedByteArray([1, 0, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9]),
		"junk after a valid body": junk_after,
		"a body cut short": packed(2, helm),
		"a compressed body cut short": cut.slice(0, cut.size() - 3),
		"a type index of 200": packed(1, record(0, 0, 0, 200)),
		"a coordinate byte of 200": packed(2, bad_y),
		"two blocks in one cell": packed(2, helm + record(0, 0, 0, frame)),
		"no helm": packed(1, record(0, 0, 0, frame)),
	}
	for problem: String in cases:
		assert_eq(ShipGrid.from_bytes(cases[problem]), null, problem)
	assert_true(ShipGrid.from_bytes(packed(1, helm)) != null, "the test's own bytes are fine")


func test_read_blocks_names_the_first_problem() -> void:
	var helm := [0, 0, 0, "helm", 0]
	var cases := [
		["a ship", "The ship has no blocks."],
		[[], "The ship has no blocks."],
		[[helm] + range(4000).map(func(i: int) -> Array: return [i % 100 - 50, i / 100 - 30, 1, "frame", 0]), "The ship has 4001 blocks; the most a ship can have is 4000."],
		[[helm, "frame"], "Block 2 isn't written as [x, y, z, type, rotation]."],
		[[helm, [1, 0, 0, "frame"]], "Block 2 isn't written as [x, y, z, type, rotation]."],
		[[helm, [1, 0, 0, 3, 0]], "Block 2 isn't written as [x, y, z, type, rotation]."],
		[[[0.5, 0, 0, "helm", 0]], "Block 1 has a number that isn't a whole number."],
		[[[INF, 0, 0, "helm", 0]], "Block 1 has a number that isn't a whole number."],
		[[[0, 0, 0, "helm", "a"]], "Block 1 has a number that isn't a whole number."],
		[[helm, [64, 0, 0, "frame", 0]], "Block 2 is outside the build area (-64 to 63)."],
		[[helm, [0, -65, 0, "frame", 0]], "Block 2 is outside the build area (-64 to 63)."],
		[[helm, [1, 0, 0, "x".repeat(40), 0]], "Block 2 is an unknown type, \"%s\"." % "x".repeat(24)],
		[[helm, [1, 0, 0, "frame", 24]], "Block 2 has rotation 24; rotations go from 0 to 23."],
		[[helm, [1, 0, 0, "frame", 0, 0]], "Block 2 has 0 hit points; a frame has 1 to 100."],
		[[helm, [1, 0, 0, "frame", 0, 101]], "Block 2 has 101 hit points; a frame has 1 to 100."],
		[[helm, [0, 0, 0, "frame", 0]], "Block 2 is in the same place as another block."],
		[[[1, 0, 0, "frame", 0]], "Every ship needs a helm."],
	]
	for item: Array in cases:
		assert_eq(ShipGrid.read_blocks(item[0]).get("problem"), item[1])
	assert_true(ShipGrid.read_blocks([[0, 0, 0, "helm", 0.0]]).has("grid"), "a whole float is accepted")
	assert_true(ShipGrid.read_blocks([[0.5, 0, 0, "helm", 0]]).has("problem"), "a half isn't")
	assert_eq(ShipGrid.read_blocks([[0, 0, 0, "helm", 3, 20]])["grid"].blocks[Vector3i.ZERO], {"type": "helm", "rotation": 3, "hp": 20})
	assert_eq(ShipGrid.read_blocks([helm])["grid"].blocks[Vector3i.ZERO]["hp"], 150, "five items mean full hit points")


func test_paint_is_checked() -> void:
	assert_eq(ShipGrid.read_paint({"balloon": "c0392b"}), {"balloon": Color("c0392b")})
	assert_eq(ShipGrid.read_paint({}), {})
	var too_many := {}
	for i in Tuning.BLOCKS.size() + 1:
		too_many["t%d" % i] = "ffffff"
	for bad: Variant in ["c0392b", {"gold": "c0392b"}, {"balloon": "zzz"}, {"balloon": 5}, too_many]:
		assert_eq(ShipGrid.read_paint(bad), null, var_to_str(bad))
	var grid := ShipGrid.new()
	grid.paint = {"balloon": Color("c0392b")}
	assert_eq(grid.paint_names(), {"balloon": "c0392b"})


func test_bounds_hold_every_block() -> void:
	var grid := grid_of({Vector3i(0, 0, 0): "deck", Vector3i(2, 1, -3): "frame"})
	assert_eq(grid.bounds(), AABB(Vector3(-0.5, -0.5, -3.5), Vector3(3, 2, 4)))


func test_raycast_finds_the_first_block_and_its_face() -> void:
	var grid := grid_of({Vector3i(0, 0, 0): "frame", Vector3i(0, 3, 0): "frame", Vector3i(5, 0, 0): "frame", Vector3i(2, 0, 0): "frame"})
	var down := grid.raycast(Vector3(0, 10, 0), Vector3.DOWN)
	assert_eq(down, {"cell": Vector3i(0, 3, 0), "normal": Vector3i(0, 1, 0)})
	var along := grid.raycast(Vector3(-10, 0, 0), Vector3.RIGHT)
	assert_eq(along, {"cell": Vector3i(0, 0, 0), "normal": Vector3i(-1, 0, 0)})
	# A diagonal ray from the origin enters (2, 2) before (4, 4).
	assert_eq(grid_of({Vector3i(2, 2, 0): "frame", Vector3i(4, 4, 0): "frame"}).raycast(Vector3(0, 0, 0), Vector3(1, 1, 0.01))["cell"], Vector3i(2, 2, 0))


func test_raycast_misses_and_stops_at_its_range() -> void:
	var grid := grid_of({Vector3i(0, 0, 0): "frame"})
	assert_eq(grid.raycast(Vector3(0, 10, 0), Vector3.UP), {})
	assert_eq(grid.raycast(Vector3(0, 100, 0), Vector3.DOWN, 50.0), {})
	assert_true(grid.raycast(Vector3(0, 100, 0), Vector3.DOWN, 150.0).has("cell"))


func test_cells_along_lists_blocks_in_order_with_their_faces() -> void:
	var grid := grid_of({Vector3i(1, 0, 0): "frame", Vector3i(2, 0, 0): "ladder", Vector3i(4, 0, 0): "deck"})
	var hits := grid.cells_along(Vector3(-3, 0, 0), Vector3.RIGHT, 200.0, 3)
	assert_eq(hits.size(), 3)
	assert_eq(hits[0], {"cell": Vector3i(1, 0, 0), "normal": Vector3i(-1, 0, 0)})
	assert_eq(hits[1]["cell"], Vector3i(2, 0, 0))
	assert_eq(hits[2]["cell"], Vector3i(4, 0, 0))
	assert_eq(grid.cells_along(Vector3(-3, 0, 0), Vector3.RIGHT, 200.0, 2).size(), 2)
	assert_eq(grid.cells_along(Vector3(-3, 0, 0), Vector3.RIGHT, 200.0, 9).size(), 3)
	assert_eq(grid.raycast(Vector3(-3, 0, 0), Vector3.RIGHT), hits[0])
	assert_eq(grid.raycast(Vector3(-3, 5, 0), Vector3.RIGHT), {})


func test_whole_restores_hit_points_and_keeps_paint() -> void:
	var grid := grid_of({Vector3i(0, 0, 0): "iron"})
	grid.blocks[Vector3i(0, 0, 0)]["hp"] = 7
	grid.paint["iron"] = Color.RED
	var fresh := grid.whole()
	assert_eq(fresh.blocks[Vector3i(0, 0, 0)]["hp"], 300)
	assert_eq(fresh.paint["iron"], Color.RED)
	assert_eq(grid.blocks[Vector3i(0, 0, 0)]["hp"], 7, "the original is untouched")
