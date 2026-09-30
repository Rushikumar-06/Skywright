extends TestCase
## The damage rules: shots, blasts, applying changes, splitting, fire, repair and the Roil.


func grid_of(cells: Dictionary) -> ShipGrid:
	var grid := ShipGrid.new()
	for cell: Vector3i in cells:
		grid.set_block(cell, cells[cell])
	return grid


func row(types: Array, helm_at := Vector3i(0, 5, 0)) -> ShipGrid:
	var grid := ShipGrid.new()
	for x in types.size():
		grid.set_block(Vector3i(x, 0, 0), types[x])
	grid.set_block(helm_at, "helm")
	return grid


func test_round_shot_breaks_planks_and_stops_at_iron() -> void:
	var grid := row(["deck", "deck", "iron", "frame"])
	assert_eq(Damage.shot(grid, Vector3(-2, 0, 0), Vector3.RIGHT, "round"), {Vector3i(0, 0, 0): 0, Vector3i(1, 0, 0): 0})
	grid = row(["deck", "iron"])
	assert_eq(Damage.shot(grid, Vector3(-2, 0, 0), Vector3.RIGHT, "round"), {Vector3i(0, 0, 0): 0, Vector3i(1, 0, 0): 220})


func test_chain_shot_shreds_balloons() -> void:
	var grid := row(["balloon", "balloon", "balloon", "balloon", "frame"])
	var chain := Damage.shot(grid, Vector3(-2, 0, 0), Vector3.RIGHT, "chain")
	assert_eq(chain, {Vector3i(0, 0, 0): 0, Vector3i(1, 0, 0): 0, Vector3i(2, 0, 0): 0, Vector3i(3, 0, 0): 0, Vector3i(4, 0, 0): 70})
	# Round shot reaches only four cells, so it spends 120 on the balloons and never meets the frame.
	var round_shot := Damage.shot(grid, Vector3(-2, 0, 0), Vector3.RIGHT, "round")
	assert_eq(round_shot, {Vector3i(0, 0, 0): 0, Vector3i(1, 0, 0): 0, Vector3i(2, 0, 0): 0, Vector3i(3, 0, 0): 0})


func test_damage_only_reaches_so_far() -> void:
	var grid := row(["balloon", "balloon", "balloon", "balloon", "balloon", "balloon"])
	var changes := Damage.shot(grid, Vector3(-2, 0, 0), Vector3.RIGHT, "round")
	assert_eq(changes.size(), 4)
	assert_false(changes.has(Vector3i(4, 0, 0)))
	assert_false(changes.has(Vector3i(5, 0, 0)))


func test_a_shell_bursts() -> void:
	var grid := ShipGrid.new()
	for x in range(-3, 4):
		for z in range(-3, 4):
			grid.set_block(Vector3i(x, 0, z), "deck")
	var changes := Damage.blast(grid, Vector3.ZERO, 3.0, 90.0)
	assert_eq(changes[Vector3i(0, 0, 0)], 0)
	assert_eq(changes[Vector3i(2, 0, 0)], 50)
	assert_false(changes.has(Vector3i(3, 0, 0)))
	assert_false(changes.has(Vector3i(0, 0, 3)))
	assert_false(changes.has(Vector3i(3, 0, 3)))
	for cell: Vector3i in changes:
		assert_eq(changes[Vector3i(-cell.x, 0, cell.z)], changes[cell])
		assert_eq(changes[Vector3i(cell.x, 0, -cell.z)], changes[cell])


func test_applying_changes_removes_dead_blocks_and_restores_from_the_blueprint() -> void:
	var blueprint := grid_of({Vector3i(0, 0, 0): "deck", Vector3i(1, 0, 0): "frame", Vector3i(2, 0, 0): "frame"})
	blueprint.blocks[Vector3i(1, 0, 0)]["rotation"] = 7
	var grid := grid_of({Vector3i(0, 0, 0): "deck"})
	assert_false(Damage.apply(grid, {Vector3i(0, 0, 0): 30}))
	assert_eq(grid.blocks[Vector3i(0, 0, 0)]["hp"], 30)
	Damage.apply(grid, {Vector3i(0, 0, 0): 999})
	assert_eq(grid.blocks[Vector3i(0, 0, 0)]["hp"], 80)
	assert_false(Damage.apply(grid, {Vector3i(1, 0, 0): 50}), "no blueprint: ignored")
	assert_false(grid.blocks.has(Vector3i(1, 0, 0)))
	assert_true(Damage.apply(grid, {Vector3i(1, 0, 0): 50}, blueprint))
	assert_eq(grid.blocks[Vector3i(1, 0, 0)], {"type": "frame", "rotation": 7, "hp": 50})
	assert_false(Damage.apply(grid, {Vector3i(9, 0, 0): 50}, blueprint), "the blueprint has nothing there")
	assert_true(Damage.apply(grid, {Vector3i(0, 0, 0): 0}))
	assert_false(grid.blocks.has(Vector3i(0, 0, 0)))


func bar(order: Array) -> ShipGrid:
	var grid := ShipGrid.new()
	for z: int in order:
		grid.set_block(Vector3i(0, 0, z), "helm" if z == 11 else "frame")
	return grid


func test_split_finds_every_piece() -> void:
	var grid := bar(range(12))
	grid.blocks.erase(Vector3i(0, 0, 4))
	var parts := Damage.split(grid)
	assert_eq(parts["keep"].size(), 7)
	assert_true(parts["keep"].has(Vector3i(0, 0, 11)))
	assert_eq(parts["wrecks"].size(), 1)
	assert_eq(parts["wrecks"][0], [Vector3i(0, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, 2), Vector3i(0, 0, 3)] as Array[Vector3i])
	assert_eq(parts["debris"].size(), 0)
	grid.blocks.erase(Vector3i(0, 0, 1))
	parts = Damage.split(grid)
	assert_eq(parts["wrecks"].size(), 0)
	assert_eq(parts["debris"], [Vector3i(0, 0, 0), Vector3i(0, 0, 2), Vector3i(0, 0, 3)] as Array[Vector3i])
	var reversed := bar(range(11, -1, -1))
	reversed.blocks.erase(Vector3i(0, 0, 4))
	reversed.blocks.erase(Vector3i(0, 0, 1))
	assert_eq(Damage.split(reversed), parts)


func test_split_counts_faces_not_corners() -> void:
	var grid := grid_of({Vector3i(0, 0, 0): "frame", Vector3i(1, 1, 0): "frame"})
	assert_eq(Damage.split(grid)["debris"].size(), 1, "two pieces of one block")
	grid.set_block(Vector3i(1, 0, 0), "ladder")
	var parts := Damage.split(grid)
	assert_eq(parts["keep"].size(), 3)
	assert_eq(parts["debris"].size(), 0)


func test_without_a_helm_the_largest_piece_stays() -> void:
	var grid := ShipGrid.new()
	for x in 6:
		grid.set_block(Vector3i(x, 0, 0), "frame")
	for x in 9:
		grid.set_block(Vector3i(x, 0, 5), "frame")
	var parts := Damage.split(grid)
	assert_eq(parts["keep"].size(), 9)
	assert_eq(parts["wrecks"].size(), 1)
	grid = ShipGrid.new()
	for x in 6:
		grid.set_block(Vector3i(x, 0, 5), "frame")
		grid.set_block(Vector3i(x, 0, 0), "frame")
	parts = Damage.split(grid)
	assert_eq(parts["keep"][0], Vector3i(0, 0, 0))
	assert_eq(parts["wrecks"][0][0], Vector3i(0, 0, 5))


func test_the_starter_ship_breaks_in_two_across_her_keel() -> void:
	var grid := StarterShip.build()
	for cell: Vector3i in grid.blocks.keys():
		if cell.z == 0:
			grid.blocks.erase(cell)
	var parts := Damage.split(grid)
	assert_true(parts["keep"].has(grid.cells_of("helm")[0]))
	for cell: Vector3i in parts["keep"]:
		assert_true(cell.z > 0)
	# The envelope floats free of the hull by faces (its posts stop a cell short), so
	# it is already a wreck of its own and the cut splits it too: three wrecks.
	assert_eq(parts["wrecks"].size(), 3)
	var engine := Vector3i(0, -1, -5)
	var bow_hull: Array = parts["wrecks"].filter(func(w: Array) -> bool: return w.has(engine))[0]
	for cell: Vector3i in bow_hull:
		assert_true(cell.z < 0)
	assert_eq(parts["debris"].size(), 0)


func test_changes_pack_and_unpack() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var changes := {}
	while changes.size() < 50:
		changes[Vector3i(rng.randi_range(-64, 63), rng.randi_range(-64, 63), rng.randi_range(-64, 63))] = rng.randi_range(0, 400)
	var data := Damage.pack(changes)
	assert_eq(data.size(), 2 + 50 * Damage.BYTES_PER_CHANGE)
	assert_eq(Damage.unpack(data), changes)
	assert_eq(Damage.unpack(PackedByteArray([1, 2, 3])), null)
	var empty := PackedByteArray([0, 0])
	assert_eq(Damage.unpack(empty), null)
	var big := PackedByteArray()
	big.resize(2 + 4001 * 5)
	big.encode_u16(0, 4001)
	assert_eq(Damage.unpack(big), null)
	var bad := Damage.pack({Vector3i.ZERO: 5})
	bad[2] = 200
	assert_eq(Damage.unpack(bad), null)
	assert_eq(Damage.unpack("text"), null)


func test_fire_spreads_through_wood_and_burns_out() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var grid := row(["deck", "deck", "deck", "deck", "deck", "iron"])
	var fires := {Vector3i(0, 0, 0): 0.0}
	var changes := Damage.burn(grid, fires, rng)
	assert_eq(changes[Vector3i(0, 0, 0)], 75)
	Damage.apply(grid, changes)
	var iron_burned := false
	for i in 40:
		Damage.apply(grid, Damage.burn(grid, fires, rng))
		iron_burned = iron_burned or fires.has(Vector3i(5, 0, 0))
		for time: float in fires.values():
			assert_true(time <= Damage.FIRE_TIME)
	assert_true(fires.is_empty(), "every fire burned out")
	assert_false(iron_burned)
	var fresh := RandomNumberGenerator.new()
	fresh.seed = 3
	var lit := {}
	Damage.ignite(row(["iron", "deck"]), lit, [Vector3i(0, 0, 0), Vector3i(1, 0, 0)], fresh)
	assert_false(lit.has(Vector3i(0, 0, 0)), "iron never ignites")


func test_putting_out_a_fire() -> void:
	var fires := {Vector3i(0, 0, 0): 3.0, Vector3i(1, 1, 0): 1.0, Vector3i(3, 0, 0): 2.0}
	assert_true(Damage.put_out(fires, Vector3i(0, 0, 0)))
	assert_eq(fires, {Vector3i(3, 0, 0): 2.0})
	assert_false(Damage.put_out(fires, Vector3i(0, 0, 0)))


func test_one_repair_heals_or_rebuilds() -> void:
	var blueprint := grid_of({Vector3i(0, 0, 0): "deck", Vector3i(1, 0, 0): "deck", Vector3i(1, 1, 1): "deck", Vector3i(0, 1, 0): "cannon"})
	blueprint.blocks[Vector3i(1, 0, 0)]["rotation"] = 4
	var grid := grid_of({Vector3i(0, 0, 0): "deck"})
	grid.blocks[Vector3i(0, 0, 0)]["hp"] = 20
	assert_eq(Damage.repair(grid, blueprint, Vector3i(0, 0, 0)), {Vector3i(0, 0, 0): 45})
	grid.blocks[Vector3i(0, 0, 0)]["hp"] = 80
	var fix := Damage.repair(grid, blueprint, Vector3i(0, 0, 0))
	assert_eq(fix, {Vector3i(1, 0, 0): 25}, "the face before the corner, and never the cannon")
	Damage.apply(grid, fix, blueprint)
	assert_eq(grid.blocks[Vector3i(1, 0, 0)]["rotation"], 4)
	grid.blocks[Vector3i(1, 0, 0)]["hp"] = 80
	assert_eq(Damage.repair(grid, blueprint, Vector3i(0, 0, 0)), {Vector3i(1, 1, 1): 25})
	Damage.apply(grid, {Vector3i(1, 1, 1): 80}, blueprint)
	assert_eq(Damage.repair(grid, blueprint, Vector3i(0, 0, 0)), {})


func test_the_roil_wears_whats_under_it() -> void:
	var grid := StarterShip.build()
	var changes := Damage.roil(grid, Transform3D(Basis.IDENTITY, Vector3(0, 199, 0)))
	for cell: Vector3i in grid.blocks:
		assert_eq(changes.has(cell), cell.y <= 0, str(cell))
	assert_eq(changes[Vector3i(0, -1, 0)], 300 - 10)
	assert_eq(changes[Vector3i(1, 0, 0)], 70)
