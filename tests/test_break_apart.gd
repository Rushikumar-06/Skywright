extends NetCase
## Breaking apart (spec §4.4): the part with the helm stays the ship, every other
## piece big enough falls away as a wreck with the velocity it had there, splinters
## vanish, wrecks are cleared away in time, and nobody is put aboard one.

var world: Node3D
var sync: WorldSync
var ship: Ship


## A solo world with its ship calm and, unless anchor is off, anchored.
func start(anchor := true) -> void:
	world = solo_world()
	await get_tree().process_frame
	sync = world.sync
	ship = world.ship
	ship.calm = true
	ship.anchored = anchor


## Every cell of on's at z, destroyed.
static func row(on: Ship, z: int) -> Dictionary:
	var changes := {}
	for cell: Vector3i in on.grid.blocks:
		if cell.z == z:
			changes[cell] = 0
	return changes


## The ship added last.
func newest(in_sync: WorldSync) -> Ship:
	return in_sync.ships.values().back()


## A wreck of four planks, at ship's place moved by offset.
func add_wreck(offset: Vector3) -> Ship:
	var grid := ShipGrid.new()
	for x in 4:
		grid.set_block(Vector3i(x, 0, 0), "deck")
	return sync.add_ship(grid, ship.global_transform.translated(offset))


func test_the_part_with_the_helm_stays_the_ship() -> void:
	await start()
	var count := sync.ships.size()
	sync.damage_ship(ship, row(ship, 0))
	assert_eq(sync.ships.size(), count + 1, "one more ship")
	var wreck := newest(sync)
	assert_true(wreck != ship, "a new one")
	assert_eq(ship.grid.cells_of("helm").size(), 1, "the ship keeps her helm")
	assert_true(ship.grid.blocks.keys().all(func(cell: Vector3i) -> bool: return cell.z > 0), "and nothing forward of the cut")
	assert_false(wreck.grid.blocks.is_empty(), "the wreck has blocks")
	assert_true(wreck.grid.blocks.keys().all(func(cell: Vector3i) -> bool: return cell.z < 0), "all of them forward of the cut")
	assert_eq(wreck.global_transform, ship.global_transform, "where they were")
	assert_true(wreck.is_wreck(), "a wreck")
	assert_eq(wreck.captain, 0, "nobody's")
	assert_false(wreck.test or wreck.pirate, "not a test flight or a pirate")
	assert_eq(wreck.spares, 0, "with no spares")
	await simulate(0.5)
	assert_false(ship.is_wreck(), "the ship can still be steered")
	assert_true(world.ship == ship, "you're still aboard")
	assert_true(world.player.crew.get_parent() == ship.interior, "in her interior")


func test_crew_on_a_piece_that_breaks_away_fall_off_the_ship() -> void:
	await start()
	world.come_aboard(ship, Vector3(0, 1.45, -3))
	await simulate(0.3)
	assert_true(world.player.crew.is_on_floor(), "standing on the foredeck")
	sync.damage_ship(ship, row(ship, 0))
	assert_true(await simulate_until(func() -> bool: return world.ship != ship, 1.0), "off the ship")


func test_broken_off_sections_keep_their_velocity() -> void:
	await start(false)
	ship.linear_velocity = Vector3(10, 0, 0)
	ship.angular_velocity = Vector3(0, 0.3, 0)
	sync.damage_ship(ship, row(ship, 0))
	var wreck := newest(sync)
	assert_true(wreck != ship, "a wreck")
	var expected := ship.point_velocity(wreck.global_transform * wreck.center_of_mass)
	assert_true(wreck.linear_velocity.distance_to(expected) <= 0.05, "the velocity it had there (%s, not %s)" % [wreck.linear_velocity, expected])
	assert_true(wreck.angular_velocity.distance_to(ship.angular_velocity) <= 0.01, "and the ship's spin (%s)" % wreck.angular_velocity)


func test_a_ship_without_a_helm_is_a_wreck() -> void:
	await start()
	var other := sync.add_ship(StarterShip.build(), Dock.slipway(world.START, 1))
	other.anchored = true
	var count := sync.ships.size()
	sync.damage_ship(ship, {ship.helm.cell: 0})
	await get_tree().process_frame
	assert_eq(sync.ships.size(), count, "no ship added")
	assert_true(ship.is_wreck(), "she's a wreck")
	assert_true(sync.home_ship() == other, "and not the home ship")
	sync.damage_ship(ship, row(ship, 0))
	assert_eq(sync.ships.size(), count + 1, "a cut through her breaks off a piece")
	var piece := newest(sync)
	assert_true(ship.grid.blocks.size() > piece.grid.blocks.size(),
			"she keeps the larger (%d blocks, %d broke off)" % [ship.grid.blocks.size(), piece.grid.blocks.size()])


func test_a_severed_balloon_floats_away() -> void:
	await start(false)
	var balloons := ship.grid.cells_of("balloon").size()
	sync.damage_ship(ship, {Vector3i(-2, 5, -4): 0, Vector3i(2, 5, -4): 0, Vector3i(-2, 5, 6): 0, Vector3i(2, 5, 6): 0})
	var envelope := newest(sync)
	assert_true(envelope != ship and envelope.is_wreck(), "the envelope is a wreck")
	assert_eq(envelope.grid.cells_of("balloon").size(), balloons, "with every balloon")
	assert_eq(ship.grid.cells_of("balloon").size(), 0, "and none left on the ship")
	var parted := [(envelope.global_transform * envelope.center_of_mass).y, (ship.global_transform * ship.center_of_mass).y]
	await simulate(10.0)
	var rose: float = (envelope.global_transform * envelope.center_of_mass).y - parted[0]
	var sank: float = parted[1] - (ship.global_transform * ship.center_of_mass).y
	assert_true(rose >= 20.0, "the envelope floats away (%.1f m up)" % rose)
	assert_true(sank >= 20.0, "and the ship sinks (%.1f m down)" % sank)


func test_splinters_vanish() -> void:
	await start()
	var grid := ShipGrid.new()
	for x in range(-1, 2):
		for z in range(-1, 2):
			grid.set_block(Vector3i(x, 0, z), "deck")
	grid.set_block(Vector3i(0, 1, 0), "helm")
	for z in range(2, 5):
		grid.set_block(Vector3i(0, 0, z), "deck")
	var small := sync.add_ship(grid, Dock.slipway(world.START, 1))
	small.anchored = true
	var count := sync.ships.size()
	sync.damage_ship(small, {Vector3i(0, 0, 2): 0})
	assert_eq(sync.ships.size(), count, "no ship added")
	assert_false(small.grid.blocks.has(Vector3i(0, 0, 3)), "the second plank is gone")
	assert_false(small.grid.blocks.has(Vector3i(0, 0, 4)), "and the third")
	assert_eq(small.grid.blocks.size(), 10, "the deck and helm stay")


func test_wrecks_are_cleared_away() -> void:
	await start()
	assert_true(sync.crewed_ships() == ([ship] as Array[Ship]), "you crew your ship")
	var old := add_wreck(Vector3(0, 30, 0))
	old.born = sync.now() - 181.0
	sync._wear()
	assert_eq(sync.id_of(old), 0, "an old wreck goes")
	var wrecks: Array[Ship] = []
	for i in 9:
		var wreck := add_wreck(Vector3(10.0 * i - 40.0, 30, 30))
		wreck.born = sync.now() - 9.0 + i
		wrecks.append(wreck)
	sync._wear()
	assert_eq(sync.id_of(wrecks[0]), 0, "with nine, the oldest goes")
	assert_true(wrecks.slice(1).all(func(wreck: Ship) -> bool: return sync.id_of(wreck) != 0), "and only it")
	wrecks[1].global_position += Vector3(3500, 0, 0)
	sync._wear()
	assert_eq(sync.id_of(wrecks[1]), 0, "one far from every crewed ship goes")
	assert_true(wrecks.slice(2).all(func(wreck: Ship) -> bool: return sync.id_of(wreck) != 0), "the rest stay")
	assert_true(sync.id_of(ship) != 0, "and so does your ship")


func test_wrecks_stay_near_players_ashore() -> void:
	await start()
	var wreck := add_wreck(Vector3(0, 30, 0))
	wreck.anchored = true
	world.go_ashore()
	var crew: CrewMember = world.player.crew
	var hold := [ship.global_position + Vector3(40, 0, 0)]
	var held := func(_tick: int) -> void:
		crew.position = hold[0]
		crew.velocity = Vector3.ZERO
	assert_true(sync.crewed_ships().is_empty(), "nobody is aboard a ship")
	await simulate(3.5, held)
	assert_true(is_instance_valid(wreck) and sync.id_of(wreck) != 0, "the wreck stays through three wears while you're in the air nearby")
	hold[0] = wreck.global_position + Vector3(3500, 0, 0)
	await simulate(1.1, held)
	assert_true(not is_instance_valid(wreck) or sync.id_of(wreck) == 0, "and goes once you're more than 3 km away")


func test_nobody_is_put_aboard_a_wreck() -> void:
	await start()
	var other := sync.add_ship(StarterShip.build(), Dock.slipway(world.START, 1))
	other.anchored = true
	world.go_ashore()
	sync.damage_ship(ship, {ship.helm.cell: 0})
	await get_tree().process_frame
	assert_true(ship.is_wreck(), "your ship is a wreck")
	world.rescue()
	assert_true(world.ship == other, "the Roil sends you aboard the other ship, not the wreck")
	world.go_ashore()
	var crew: CrewMember = world.player.crew
	crew.position = other.global_transform * Vector3(3, 1.4, 1)
	assert_true(world.player.ship_in_reach() == other, "beside a ship, you can climb aboard")
	crew.position = ship.global_transform * Vector3(3, 1.4, 1)
	assert_true(world.player.ship_in_reach() == null, "beside a wreck, you can't")


func test_you_can_still_board_a_wreck() -> void:
	await start()
	sync.damage_ship(ship, row(ship, 0))
	var wreck := newest(sync)
	wreck.anchored = true
	world.go_ashore()
	var crew: CrewMember = world.player.crew
	crew.position = wreck.global_transform * Vector3(0, 13, -3)
	crew.velocity = Vector3.ZERO
	sync._wear()
	assert_true(sync.id_of(wreck) != 0, "she stays while you're ashore beside her")
	assert_true(await simulate_until(func() -> bool: return world.ship == wreck, 3.0), "landing on her boards her")
	world.board(wreck)
	assert_true(world.ship == wreck, "and so does boarding her")
	assert_true(world.player.crew.get_parent() == wreck.interior, "in her interior")
	await simulate(0.5)
	assert_true(world.player.crew.is_on_floor(), "standing on her")
	assert_true(world.ship == wreck, "still aboard")


func test_the_guest_sees_the_ship_break() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var host_sync: WorldSync = host_world.sync
	var guest_sync: WorldSync = client_world.sync
	var ours: Ship = host_world.ship
	ours.anchored = true
	host_sync.damage_ship(ours, row(ours, 0))
	var wreck := newest(host_sync)
	assert_true(wreck != ours, "a wreck on the host")
	var id := host_sync.id_of(wreck)
	assert_true(await play_until(func() -> bool: return guest_sync.ships.has(id), 1.0), "the guest gets it")
	assert_eq(guest_sync.ships.keys(), host_sync.ships.keys(), "the same ships")
	for each: int in host_sync.ships:
		assert_eq((guest_sync.ships[each] as Ship).grid.blocks, (host_sync.ships[each] as Ship).grid.blocks, "the same blocks in ship %d" % each)
	var drawn: Ship = guest_sync.ships[id]
	var apart := drawn.global_position.distance_to(wreck.global_position)
	assert_true(apart <= 0.5, "drawn where the host has it (%.2f m off)" % apart)
	assert_true(drawn.is_wreck(), "a wreck there too")
