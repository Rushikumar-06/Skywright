extends NetCase
## Cargo crates (spec §3.6): stowed in cargo bays, a crate weighs a ship down where
## it's stowed, goes with its bay when the bay is shot away or breaks off, and
## reaches every machine.

const START := Vector3(0, 877, 7000)
const FORE := [Vector3i(-1, 0, -2), Vector3i(1, 0, -2)]
const AFT := [Vector3i(-1, 0, 4), Vector3i(1, 0, 4)]
const PORT := [Vector3i(-1, 0, -2), Vector3i(-1, 0, 4)]


func crates(cells: Array, owner := "Ann") -> Dictionary:
	var cargo := {}
	for cell: Vector3i in cells:
		cargo[cell] = {"good": "grain", "owner": owner}
	return cargo


## A ship from grid in still air at START, plus x metres east.
func launch(grid: ShipGrid, x := 0.0) -> Ship:
	var ship := Ship.new(grid)
	ship.calm = true
	ship.position = START + Vector3(x, 0, 0)
	add_child(ship)
	return ship


func listing(ship: Ship) -> float:
	return rad_to_deg(asin(-ship.global_basis.x.y))


func pitch(ship: Ship) -> float:
	return rad_to_deg(asin(-ship.global_basis.z.y))


func test_the_starter_ship_has_four_bays_and_two_bunks_and_still_floats_level() -> void:
	var grid := StarterShip.build()
	var bays := grid.cells_of("cargo_bay")
	bays.sort()
	assert_eq(bays, [Vector3i(-1, 0, -2), Vector3i(-1, 0, 4), Vector3i(1, 0, -2), Vector3i(1, 0, 4)])
	var bunks := grid.cells_of("bunk")
	bunks.sort()
	assert_eq(bunks, [Vector3i(0, -1, -3), Vector3i(0, -1, 3)])
	var stats := ShipStats.of(grid, 880.0)
	assert_near(stats.float_altitude, 882.5, 1.0, "floats where she did")
	assert_true(absf(stats.bow_down) < 0.1, "level fore and aft (%.3f°)" % stats.bow_down)
	assert_near(stats.list, 0.0, 1e-4, "no list")
	assert_near(stats.mass, 9566.0, 1.0)
	assert_eq(grid.blocks.size(), 301)
	assert_eq(Economy.cost(grid), 1350)


func test_crates_weigh_the_ship_down_where_they_are_stowed() -> void:
	var grid := StarterShip.build()
	var empty := launch(grid.copy(), 200.0)
	var empty_trim := empty.trim_to_float_at(877.0)
	empty.free()
	var ship := launch(grid.copy())
	ship.set_cargo(crates(FORE + AFT))
	assert_near(ship.mass, grid.mass_properties()["mass"] + 400.0, 0.01, "four crates, 400 kg")
	assert_near(ship.trim_to_float_at(877.0) / empty_trim, 1.0418, 0.001, "she needs more lift")
	ship.free()
	var fore := launch(StarterShip.build())
	fore.set_cargo(crates(FORE))
	var twin := launch(StarterShip.build(), 200.0)
	await simulate(60.0)
	assert_true(pitch(fore) < -0.3, "crates in the bow put her down by the bow (%.2f°)" % pitch(fore))
	assert_true(absf(pitch(twin)) < 0.15, "her twin stays level (%.2f°)" % pitch(twin))
	fore.free()
	twin.free()
	var port := launch(StarterShip.build())
	port.set_cargo(crates(PORT))
	twin = launch(StarterShip.build(), 200.0)
	await simulate(60.0)
	assert_true(listing(port) < -0.1, "crates to port make her list to port (%.2f°)" % listing(port))
	assert_true(absf(listing(twin)) < 0.05, "her twin doesn't (%.2f°)" % listing(twin))


func test_a_destroyed_bay_loses_its_crate() -> void:
	var ship := launch(StarterShip.build())
	ship.anchored = true
	ship.set_cargo(crates([Vector3i(1, 0, -2)]))
	var before := ship.mass
	ship.damage({Vector3i(1, 0, -2): 0})
	assert_true(ship.grid.cargo.is_empty(), "the crate went with the bay")
	await get_tree().process_frame
	assert_near(ship.mass, before - 150.0, 0.01, "the bay and its crate")


func test_crates_go_with_a_piece_that_breaks_away() -> void:
	var world := solo_world()
	await get_tree().process_frame
	var sync: WorldSync = world.sync
	var ship: Ship = world.ship
	ship.anchored = true
	ship.global_position = open_sky(world, 1000.0)
	sync.set_cargo(ship, crates(FORE + AFT))
	var cut := {}
	for cell: Vector3i in ship.grid.blocks:
		if cell.z == 0:
			cut[cell] = 0
	sync.damage_ship(ship, cut)
	var wrecks := sync.ships.values().filter(func(each: Ship) -> bool: return each != ship)
	assert_eq(wrecks.size(), 1, "the bow broke off")
	if wrecks.size() != 1:
		return
	var bow: Ship = wrecks[0]
	assert_eq(bow.grid.cargo, crates(FORE), "the bow took the fore crates")
	assert_eq(ship.grid.cargo, crates(AFT), "she kept the aft ones")
	await get_tree().process_frame
	for each: Ship in [ship, bow]:
		assert_near(each.mass, each.grid.mass_properties()["mass"], 0.01, "her mass counts her crates")


func test_cargo_reaches_the_guest() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var sync: WorldSync = host_world.sync
	var ours: Ship = host_world.ship
	sync.set_cargo(ours, crates(FORE))
	var id := sync.id_of(ours)
	var theirs: Ship = client_world.sync.ships[id]
	assert_true(await play_until(func() -> bool: return theirs.grid.cargo_list() == ours.grid.cargo_list(), 1.0), "the guest has the crates")
	assert_eq(theirs.grid.cargo_list(), [[-1, 0, -2, "grain", "Ann"], [1, 0, -2, "grain", "Ann"]])
	var late := make_session("Late")
	late.join("Cy", "127.0.0.1", host.port)
	assert_true(await play_until(func() -> bool: return late.sailing, 5.0), "a late joiner")
	var late_world := add_world(late)
	assert_true(await play_until(func() -> bool: return late_world.ship != null, 5.0), "gets the world")
	assert_eq((late_world.sync.ships[id] as Ship).grid.cargo_list(), ours.grid.cargo_list(), "with the crates in her entry")


func test_a_junk_cargo_list_is_refused() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var sync: WorldSync = host_world.sync
	var ours: Ship = host_world.ship
	sync.set_cargo(ours, crates([Vector3i(-1, 0, -2)]))
	var id := sync.id_of(ours)
	var theirs: Ship = client_world.sync.ships[id]
	assert_true(await play_until(func() -> bool: return theirs.grid.cargo.size() == 1, 1.0), "one crate aboard")
	var guest := client.multiplayer.get_unique_id()
	for junk: Array in [[99, [[1, 0, -2, "grain", "Ann"]]], [id, [[0, 0, 0, "grain", "Ann"]]], [id, [[1, 0, -2, "gold", "Ann"]]],
			[id, [[1, 0, -2, "grain", "x".repeat(25)]]], [id, [[1, 0, -2, "grain", "Ann"], [1, 0, -2, "tools", "Ann"]]],
			[id, "crates"], [id, [[1, 0, -2, "grain", ""]]], [id, [[1.5, 0, -2, "grain", "Ann"]]], ["1", []]]:
		sync._cargo.rpc_id(guest, junk[0], junk[1])
	await play(0.3)
	assert_eq(theirs.grid.cargo_list(), [[-1, 0, -2, "grain", "Ann"]], "nothing changed")
