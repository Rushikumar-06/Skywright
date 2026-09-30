extends TestCase
## The shipyard's data model: edits, mirror mode, undo and redo, paint.

var changes := 0


func count(design: ShipDesign) -> void:
	design.changed.connect(func() -> void: changes += 1)


func test_a_design_is_a_copy_at_full_strength() -> void:
	var source := ShipGrid.new()
	source.set_block(Vector3i.ZERO, "frame")
	source.blocks[Vector3i.ZERO]["hp"] = 5
	source.paint["frame"] = Color.RED
	var design := ShipDesign.new(source)
	assert_eq(source.blocks[Vector3i.ZERO]["hp"], 5)
	assert_eq(design.grid.blocks[Vector3i.ZERO]["hp"], Tuning.BLOCKS["frame"]["hp"])
	assert_eq(design.grid.paint, {"frame": Color.RED})
	assert_eq(ShipDesign.new().grid.blocks.size(), 0)


func test_place_and_remove() -> void:
	var design := ShipDesign.new()
	count(design)
	assert_true(design.place(Vector3i(1, 2, 3), "frame", 4))
	assert_eq(design.grid.blocks[Vector3i(1, 2, 3)]["rotation"], 4)
	assert_eq(changes, 1)
	assert_true(design.remove(Vector3i(1, 2, 3)))
	assert_eq(design.grid.blocks.size(), 0)
	assert_eq(changes, 2)
	assert_false(design.remove(Vector3i(1, 2, 3)))
	assert_eq(changes, 2)


func test_place_refuses_occupied_cells_the_edge_and_the_limit() -> void:
	var design := ShipDesign.new()
	design.place(Vector3i.ZERO, "frame")
	assert_false(design.place(Vector3i.ZERO, "iron"))
	assert_eq(design.grid.type_at(Vector3i.ZERO), "frame")
	assert_false(design.place(Vector3i(64, 0, 0), "frame"))
	assert_false(design.place(Vector3i(0, -65, 0), "frame"))
	assert_true(design.place(Vector3i(-64, 0, 0), "frame"))
	assert_true(design.place(Vector3i(63, 63, 63), "frame"))
	var full := ShipGrid.new()
	for i in ShipGrid.MAX_BLOCKS:
		full.set_block(Vector3i(i % 60, (floori(i / 60.0)) % 60, floori(i / 3600.0)), "frame")
	var big := ShipDesign.new(full)
	count(big)
	assert_false(big.place(Vector3i(-64, -64, -64), "frame"))
	assert_eq(big.grid.blocks.size(), ShipGrid.MAX_BLOCKS)
	assert_eq(changes, 0)


func test_mirror_builds_both_sides() -> void:
	var design := ShipDesign.new()
	design.mirror = true
	var rot := Blocks.turned(0)
	assert_true(design.place(Vector3i(2, 0, 0), "propeller", rot))
	assert_eq(design.grid.blocks[Vector3i(2, 0, 0)]["rotation"], rot)
	assert_eq(design.grid.blocks[Vector3i(-2, 0, 0)]["type"], "propeller")
	assert_eq(design.grid.blocks[Vector3i(-2, 0, 0)]["rotation"], Blocks.mirrored(rot))
	assert_true(design.remove(Vector3i(2, 0, 0)))
	assert_eq(design.grid.blocks.size(), 0)
	assert_true(design.undo())
	assert_eq(design.grid.blocks.size(), 2)


func test_mirror_on_the_keel_line_places_one_block() -> void:
	var design := ShipDesign.new()
	design.mirror = true
	design.place(Vector3i(0, 1, 2), "frame")
	assert_eq(design.grid.blocks.size(), 1)


func test_mirror_skips_cells_outside_the_build_area() -> void:
	var design := ShipDesign.new()
	design.mirror = true
	assert_true(design.place(Vector3i(-64, 0, 0), "frame"))
	assert_eq(design.grid.blocks.size(), 1)


func test_undo_and_redo() -> void:
	var design := ShipDesign.new()
	assert_false(design.can_undo())
	assert_false(design.can_redo())
	assert_false(design.undo())
	assert_false(design.redo())
	for x in 3:
		design.place(Vector3i(x, 0, 0), "frame")
	design.undo()
	design.undo()
	assert_eq(design.grid.blocks.keys(), [Vector3i(0, 0, 0)])
	assert_true(design.can_undo() and design.can_redo())
	design.redo()
	assert_eq(design.grid.blocks.size(), 2)
	design.place(Vector3i(9, 0, 0), "frame")
	assert_false(design.can_redo())
	assert_false(design.redo())
	assert_eq(design.grid.blocks.size(), 3)
	design.undo()
	design.undo()
	design.undo()
	assert_false(design.can_undo())
	assert_eq(design.grid.blocks.size(), 0)


func test_loading_a_blueprint_can_be_undone() -> void:
	var design := ShipDesign.new()
	design.place(Vector3i(0, 0, 0), "frame", 3)
	design.place(Vector3i(5, 0, 0), "iron")
	design.set_paint("frame", Color.RED)
	var before := design.grid.copy()
	var starter := StarterShip.build()
	starter.paint["balloon"] = Color.BLUE
	count(design)
	design.replace(starter)
	assert_eq(changes, 1)
	assert_eq(design.grid.paint, {"balloon": Color.BLUE})
	assert_eq(design.grid.blocks.size(), StarterShip.build().blocks.size())
	assert_true(design.undo())
	assert_eq(design.grid.blocks, before.blocks)
	assert_eq(design.grid.paint, {"frame": Color.RED})
	assert_true(design.redo())
	assert_eq(design.grid.blocks, starter.blocks)
	assert_eq(design.grid.paint, {"balloon": Color.BLUE})
	changes = 0
	design.replace(starter)
	assert_eq(changes, 0)
	design.undo()
	assert_eq(design.grid.paint, {"frame": Color.RED}, "the identical replace recorded no edit")


func test_paint_changes_the_colour_of_a_type() -> void:
	var design := ShipDesign.new()
	count(design)
	design.set_paint("balloon", Color.RED)
	assert_eq(design.grid.paint, {"balloon": Color.RED})
	design.set_paint("balloon", null)
	assert_eq(design.grid.paint, {})
	assert_eq(changes, 2)
	assert_false(design.can_undo())
