extends NetCase
## Sinking into the Roil (spec §3.5): below 200 m the storm wears a ship's blocks,
## and below 0 m she's lost. Her captain's shipyard gets her blueprint, and launching
## rebuilds her whole, for free until stage 7. Nobody falls forever: the Roil's
## rescue puts you aboard a ship, or with none left on the nearest town's quay.

const LOST := "Your ship is lost to the Roil. The shipyard has her blueprint: launch to rebuild her."

var world: Node3D
var sync: WorldSync
var ship: Ship
var player: PlayerController


## A solo world with your ship calm in open sky at 250 m, anchored unless told not.
func start(anchor := true) -> void:
	world = solo_world()
	await get_tree().process_frame
	sync = world.sync
	ship = world.ship
	ship.calm = true
	ship.anchored = anchor
	ship.global_position = open_sky(world, 250.0)
	player = world.player


## The town whose dock is nearest p.
func nearest_town(p: Vector3) -> Dictionary:
	var best: Dictionary = world.gen.towns[0]
	for town: Dictionary in world.gen.towns:
		if (town["dock"] as Vector3).distance_to(p) < (best["dock"] as Vector3).distance_to(p):
			best = town
	return best


## Whether you stand on the quay of town.
func on_quay_of(town: Dictionary) -> bool:
	var spot := Dock.quay_spot(town["dock"])
	return player.ship == null and player.crew.is_on_floor() and player.world_position().distance_to(spot) < 3.0


func test_the_roil_wears_a_ship_down() -> void:
	await start()
	ship.global_position.y = 199.0
	for i in 3:
		sync._wear()
	for cell: Vector3i in ship.grid.blocks:
		var full: int = Tuning.BLOCKS[ship.grid.type_at(cell)]["hp"]
		var left: int = ship.grid.blocks[cell]["hp"]
		if cell.y <= 0:
			assert_eq(left, full - 3 * Damage.ROIL_DAMAGE, "%s, under 200 m, lost 30" % cell)
		else:
			assert_eq(left, full, "%s, above it, lost nothing" % cell)


func test_a_ship_below_the_roil_is_lost_and_its_crew_rescued() -> void:
	await start(false)
	var balloons := {}
	for cell in ship.grid.cells_of("balloon"):
		balloons[cell] = 0
	sync.damage_ship(ship, balloons)
	var said := [""]
	var lost := [false]
	sync.ship_removed.connect(func(gone: Ship, _next: Ship) -> void:
		if gone == ship:
			lost[0] = gone.lost
			said[0] = world.hud._message.text)
	assert_true(await wait_until(func() -> bool: return lost[0], 60.0), "she sinks and is lost")
	assert_eq(said[0], LOST)
	var town := nearest_town(player.world_position())
	assert_true(await wait_until(func() -> bool: return on_quay_of(town), 5.0), "you wake on %s's quay" % town["name"])


func test_nobody_falls_forever_when_every_ship_is_gone() -> void:
	await start()
	sync.remove_ship(ship)
	await get_tree().process_frame
	var crew := player.crew
	crew.position = Vector3(3000, 190, 3000)
	crew.velocity = Vector3.ZERO
	var town := nearest_town(crew.position)
	assert_true(await wait_until(func() -> bool: return on_quay_of(town), 5.0), "you wake on the quay")
	assert_eq(world.hud._message.text, "The Roil nearly took you. You wake on the quay at %s." % town["name"])


func test_rebuilding_a_lost_ship_launches_her_blueprint_whole() -> void:
	await start()
	sync.damage_ship(ship, {Vector3i(0, 0, 1): 10, Vector3i(-2, 1, 0): 0})
	var blueprint := ship.blueprint
	ship.global_position.y = -5.0
	sync._wear()
	assert_eq(sync.id_of(ship), 0, "lost")
	assert_eq(world.design.grid.blocks, blueprint.blocks, "the shipyard has her blueprint")
	assert_true(await wait_until(func() -> bool: return player.ship == null and player.crew.is_on_floor(), 5.0), "on a quay")
	var dock: Vector3 = nearest_town(player.world_position())["dock"]
	player.crew.position = dock + Vector3(5.0, -1.5 + CrewMember.HEIGHT / 2.0 + 0.05, 0)  # at the dock
	await simulate(0.2)
	world.launch(world.design.grid)
	assert_true(await wait_until(func() -> bool: return world.ship != null, 5.0), "she's rebuilt, with you aboard")
	var rebuilt: Ship = world.ship
	assert_eq(rebuilt.grid.blocks, StarterShip.build().blocks, "whole")
	assert_eq(rebuilt.spares, Damage.SPARES_MAX, "with a full load of spares")
	var slipway := sync.berth_of(1, false, world.town_at(dock))
	assert_true(rebuilt.global_position.distance_to(slipway.origin) < 30.0, "at your slipway")


func test_wrecks_and_pirates_sink_without_a_word() -> void:
	await start()
	var grid := ShipGrid.new()
	for x in 3:
		grid.set_block(Vector3i(x, 0, 0), "deck")
		grid.set_block(Vector3i(x, 0, 1), "deck")
	var wreck := sync.add_ship(grid, ship.global_transform.translated(Vector3(40, -300, 0)))
	var pirate := sync.add_ship(PirateShip.build(), ship.global_transform.translated(Vector3(-40, -300, 0)), 0, false, 0, true)
	wreck.anchored = true
	pirate.anchored = true
	world.hud._message.text = ""
	sync._wear()
	assert_eq(sync.id_of(wreck), 0, "the wreck is gone")
	assert_eq(sync.id_of(pirate), 0, "the pirate is gone")
	assert_eq(world.hud._message.text, "", "without a word")


func test_a_guest_sees_their_ship_lost() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var host_sync: WorldSync = host_world.sync
	var ours: Ship = host_world.ship
	ours.anchored = true
	var blocks := ours.grid.blocks.duplicate(true)
	var guest: PlayerController = client_world.player
	client_world.launch(StarterShip.build())
	assert_true(await play_until(func() -> bool: return host_sync.ship_of(guest.peer, false) != null and client_world.ship != null \
			and client_world.ship.captain == guest.peer, 5.0), "the guest's own ship")
	var theirs := host_sync.ship_of(guest.peer, false)
	theirs.global_position.y = -5.0
	var said := [""]
	client_world.sync.ship_removed.connect(func(gone: Ship, _next: Ship) -> void:
		if gone.captain == guest.peer:
			said[0] = client_world.hud._message.text)
	assert_true(await play_until(func() -> bool: return said[0] != "", 2.0), "the guest hears")
	assert_eq(said[0], LOST)
	assert_eq(client_world.design.grid.blocks, StarterShip.build().blocks, "and has her blueprint")
	assert_true(host_sync.id_of(ours) != 0, "the host's ship is still here")
	assert_eq(ours.grid.blocks, blocks, "untouched")


func test_a_joiner_with_no_ship_to_board_stands_on_the_quay() -> void:
	host = make_session("Server")
	var port := free_port()
	host.host("Skyport", port, true)
	host_world = add_world(host)
	await get_tree().process_frame
	var host_sync: WorldSync = host_world.sync
	host_sync.remove_ship(host_sync.home_ship())
	assert_true(host_sync.ships.is_empty(), "the server has no ships")
	client = make_session("Client")
	client.join("Guest", "127.0.0.1", port)
	assert_true(await play_until(func() -> bool: return client.sailing, 5.0), "a guest joins")
	client_world = add_world(client)
	var guest_on_quay := func() -> bool:
		var guest: PlayerController = client_world.player
		return guest != null and guest.ship == null and guest.crew.is_on_floor() \
				and guest.world_position().distance_to(Dock.quay_spot(client_world.gen.towns[0]["dock"])) < 3.0
	assert_true(await play_until(guest_on_quay, 5.0), "and stands on the first town's quay")
