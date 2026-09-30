extends NetCase
## Launching designs from the dock (spec §3.8): test flights that B brings you back
## from at once, ships of your own that replace the old one, one of each a player,
## built at their slipway clear of other ships, and gone when they leave.


## A small design: the starter ship with its envelope trimmed to 3 layers.
static func skiff() -> ShipGrid:
	var grid := StarterShip.build()
	for cell in grid.cells_of("balloon"):
		if absi(cell.z) > 1:
			grid.blocks.erase(cell)
	return grid


## Presses B in world, as a key press would.
func press_b(world: Node3D) -> void:
	var event := InputEventAction.new()
	event.action = "shipyard"
	event.pressed = true
	world._unhandled_input(event)


func test_a_test_flight_puts_you_at_the_helm_of_the_design() -> void:
	var world := solo_world()
	await get_tree().process_frame
	var starter: Ship = world.ship
	var design := skiff()
	world.test_flight(design)
	var ship: Ship = world.ship
	assert_true(ship != starter and ship.test, "a test ship")
	assert_eq(ship, world.sync.ship_of(1, true))
	assert_eq(ship.captain, 1, "yours")
	assert_eq(ship.grid.blocks.size(), design.blocks.size(), "built to the design")
	assert_eq(ship.global_transform, Dock.test_berth(world.START, 0), "at your test berth")
	assert_eq(world.player.crew.get_parent(), ship.interior, "you're aboard")
	assert_eq(world.player.crew.station, ship.helm, "at the helm")
	assert_true(world.on_test_flight())
	assert_true(world.at_dock(), "still at the dock")
	assert_eq(world.sync.ships.size(), 2)
	assert_true(world.sync.ships.values().has(starter), "the starter ship is still there")


func test_b_returns_from_a_test_flight_instantly() -> void:
	var world := solo_world()
	await get_tree().process_frame
	var starter: Ship = world.ship
	press(world.player, "interact")
	assert_eq(starter.helm.pilot, 1, "at the starter's helm")
	world.test_flight(skiff())
	var trial: Ship = world.ship
	assert_eq(starter.helm.pilot, 0, "let go of to board the test ship")
	trial.throttle = 1.0
	press(world.player, "autopilot")
	assert_true(trial.helm.autopilot, "the autopilot on")
	await simulate(20.0)
	press_b(world)
	assert_false(world.sync.ships.values().has(trial), "the test ship is gone")
	assert_eq(world.ship, starter, "you're back aboard the starter")
	assert_eq(world.player.crew.get_parent(), starter.interior)
	assert_true(world.player.crew.station == null, "not at the helm")
	assert_eq(starter.helm.pilot, 0, "which nobody holds")
	assert_false(world.on_test_flight())
	press_b(world)
	assert_eq(world.ship, starter, "B again does nothing more")
	assert_eq(world.sync.ships.size(), 1)
	await simulate(0.2)
	assert_false(is_instance_valid(trial), "freed")


func test_a_test_flight_sinking_into_the_roil_can_still_return() -> void:
	var world := solo_world()
	await get_tree().process_frame
	var starter: Ship = world.ship
	var overloaded := StarterShip.build()
	for z in range(-4, 4):
		for x in [-1, 0, 1]:
			overloaded.set_block(Vector3i(x, 1, z), "iron")
	world.test_flight(overloaded)
	var trial: Ship = world.ship
	await simulate(30.0)
	assert_true(trial.global_position.y < world.START.y - 300.0 and trial.linear_velocity.y < -5.0,
			"sinking fast (at %.0f m)" % trial.global_position.y)
	press_b(world)
	assert_eq(world.ship, starter, "back aboard the starter")
	assert_eq(world.player.crew.get_parent(), starter.interior)
	assert_eq(world.sync.ships.keys(), [world.sync.id_of(starter)], "the test ship is gone")


func test_a_second_test_flight_replaces_the_first() -> void:
	var world := solo_world()
	await get_tree().process_frame
	var sync: WorldSync = world.sync
	var starter: Ship = world.ship
	var trials := func() -> Array: return sync.ships.values().filter(func(ship: Ship) -> bool: return ship.test)
	world.test_flight(skiff())
	var first: Ship = world.ship
	await simulate(1.1)
	var second := StarterShip.build()
	world.test_flight(second)
	assert_false(sync.ships.values().has(first), "the first test ship is gone")
	assert_eq(trials.call().size(), 1, "one test ship")
	var ship: Ship = trials.call()[0]
	assert_eq(ship.grid.blocks.size(), second.blocks.size(), "the second design")
	assert_eq(world.ship, ship, "with you aboard")
	assert_eq(world.player.crew.station, ship.helm)
	await simulate(1.1)
	world.test_flight(skiff())
	world.test_flight(second)
	assert_eq(trials.call().size(), 1, "two in one frame make one ship")
	assert_eq((trials.call()[0] as Ship).grid.blocks.size(), skiff().blocks.size(), "the first of them")
	assert_eq(sync.ships.size(), 2, "beside the starter")
	press_b(world)
	assert_eq(world.ship, starter, "and B brings you back to your ship")


func test_launching_replaces_your_ship() -> void:
	var world := solo_world()
	await get_tree().process_frame
	var starter: Ship = world.ship
	world.launch(skiff())
	var ship: Ship = world.ship
	assert_eq(world.sync.ships.keys(), [world.sync.id_of(ship)], "the new ship replaces the starter")
	assert_eq(ship.captain, 1, "yours")
	assert_false(ship.test, "not a test flight")
	assert_eq(ship.global_transform, Dock.slipway(world.START, 0), "at your slipway")
	assert_eq(world.player.crew.station, ship.helm, "you're at its helm")
	assert_false(world.on_test_flight())
	await get_tree().process_frame
	assert_false(is_instance_valid(starter), "the starter is freed")


func test_a_guest_launches_a_ship_of_their_own() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var guest := client.multiplayer.get_unique_id()
	var sync: WorldSync = host_world.sync
	var starter: Ship = host_world.ship
	await play(0.2)
	press(client_world.player, "interact")
	assert_true(await wait_until(func() -> bool: return starter.helm.pilot == guest, 2.0), "the guest takes the starter's helm")
	client_world.launch(skiff())
	assert_true(await wait_until(func() -> bool: return sync.ship_of(guest, false) != null, 2.0), "the host builds the guest's ship")
	var ours: Ship = sync.ship_of(guest, false)
	assert_true(ours.global_position.distance_to(Dock.slipway(host_world.START, 1).origin) < 1.0, "at slipway 1")
	assert_eq(ours.helm.pilot, guest, "with the guest at its helm")
	assert_true(await wait_until(func() -> bool: return starter.helm.pilot == 0, 2.0), "who lets go of the starter's")
	assert_eq(host_world.ship, starter, "the host stays aboard the starter")
	var theirs: Ship = client_world.sync.ships.get(sync.id_of(ours))
	assert_true(await wait_until(func() -> bool: return client_world.ship == theirs and theirs != null, 2.0), "the guest boards theirs")
	assert_eq(client_world.player.crew.station, theirs.helm, "at the helm")
	assert_eq(sync.ships.size(), 2)
	assert_eq(client_world.sync.ships.size(), 2)


func test_the_crew_follow_the_host_to_a_new_ship() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var sync: WorldSync = host_world.sync
	var starter_id := sync.id_of(host_world.ship)
	host_world.launch(skiff())
	var id := sync.id_of(host_world.ship)
	assert_true(id != starter_id and not sync.ships.has(starter_id), "the host's new ship replaces the starter")
	assert_true(await wait_until(func() -> bool: return client_world.ship == client_world.sync.ships.get(id), 2.0), "the guest follows")
	assert_eq(client_world.player.crew.get_parent(), (client_world.ship as Ship).interior)
	assert_eq(client_world.sync.ships.keys(), [id], "the starter is gone for the guest too")


func test_a_guest_can_end_only_their_own_test_flight() -> void:
	assert_true(await sail_together(), "the ship arrives")
	host_world.test_flight(skiff())
	var trial: Ship = host_world.ship
	assert_true(host_world.on_test_flight(), "the host is on a test flight")
	var id: int = host_world.sync.id_of(trial)
	assert_true(await wait_until(func() -> bool: return client_world.sync.ships.has(id), 2.0), "the guest sees it")
	client_world.sync.end_test()
	await play(0.3)
	assert_true(host_world.sync.ships.has(id), "it goes on")
	assert_eq(host_world.ship, trial, "with the host aboard")


func test_a_leaving_guests_ships_go_with_them() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var guest := client.multiplayer.get_unique_id()
	var sync: WorldSync = host_world.sync
	client_world.launch(skiff())
	assert_true(await play_until(func() -> bool: return sync.ship_of(guest, false) != null, 2.0), "the guest's ship")
	await play(1.1)
	client_world.test_flight(skiff())
	assert_true(await play_until(func() -> bool: return sync.ship_of(guest, true) != null, 2.0), "and test flight")
	assert_eq(sync.ships.size(), 3)
	client.leave()
	assert_true(await play_until(func() -> bool: return sync.ships.size() == 1, 2.0), "both go when the guest leaves")
	assert_eq(sync.ships.keys(), [sync.id_of(host_world.ship)], "the host's stays")


func test_a_guest_back_from_a_second_test_flight_boards_their_own_ship() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var guest := client.multiplayer.get_unique_id()
	var sync: WorldSync = host_world.sync
	client_world.launch(skiff())
	assert_true(await play_until(func() -> bool: return sync.ship_of(guest, false) != null, 2.0), "the guest's ship")
	var own_id := sync.id_of(sync.ship_of(guest, false))
	await play(1.1)
	client_world.test_flight(skiff())
	assert_true(await play_until(func() -> bool: return client_world.on_test_flight(), 2.0), "a test flight")
	var first_id: int = client_world.sync.id_of(client_world.ship)
	await play(1.1)
	client_world.test_flight(skiff())
	assert_true(await play_until(func() -> bool: return client_world.on_test_flight() and client_world.sync.id_of(client_world.ship) != first_id, 2.0),
			"and another in its place")
	press_b(client_world)
	assert_true(await play_until(func() -> bool: return client_world.ship == client_world.sync.ships.get(own_id), 2.0),
			"B brings the guest back to their own ship, not the host's")


func test_launches_stay_clear_of_other_ships() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var guest := client.multiplayer.get_unique_id()
	var sync: WorldSync = host_world.sync
	var parked := sync.add_ship(StarterShip.build(), Dock.slipway(host_world.START, 1))
	client_world.launch(skiff())
	assert_true(await wait_until(func() -> bool: return sync.ship_of(guest, false) != null, 2.0), "the guest's ship")
	var ours: Ship = sync.ship_of(guest, false)
	assert_true(ours.global_position.y > parked.global_position.y + 5.0, "comes out above the parked ship")
	assert_near(ours.global_position.x, parked.global_position.x, 1.0, "over slipway 1")
	assert_false((ours.global_transform * ours.bounds).intersects(parked.global_transform * parked.bounds), "clear of it")


func test_a_test_flight_keeps_clear_of_your_own_ship() -> void:
	var world := solo_world()
	await get_tree().process_frame
	var starter: Ship = world.ship
	starter.global_transform = Dock.test_berth(world.START, 0)  # flown round to the test berth
	world.test_flight(skiff())
	var trial: Ship = world.ship
	assert_true(trial.global_position.y > starter.global_position.y + 5.0, "comes out above her")
	assert_false((trial.global_transform * trial.bounds).intersects(starter.global_transform * starter.bounds), "clear of her")


func test_the_server_ignores_junk_launches() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var sync: WorldSync = client_world.sync
	var blocks := skiff().to_bytes()
	sync._launch.rpc_id(1, "ship", {}, false, 0)
	sync._launch.rpc_id(1, PackedByteArray([1, 2, 3]), {}, false, 0)
	sync._launch.rpc_id(1, blocks, {"x": 1}, false, 0)
	sync._launch.rpc_id(1, blocks, {}, "yes", 0)
	sync._launch.rpc_id(1, blocks, {}, false, 0)
	sync._launch.rpc_id(1, blocks, {}, false, 0)
	assert_true(await play_until(func() -> bool: return host_world.sync.ships.size() > 1, 2.0), "a good launch is built")
	await play(0.3)
	assert_eq(host_world.sync.ships.size(), 2, "just one")


func test_guests_on_a_dedicated_server_launch_beside_its_ship() -> void:
	host = make_session("Server")
	var port := free_port()
	host.host("Skyport", port, true)
	host_world = add_world(host)
	client = make_session("Client")
	client.join("Guest", "127.0.0.1", port)
	assert_true(await wait_until(func() -> bool: return client.sailing, 5.0), "a guest joins")
	client_world = add_world(client)
	assert_true(await wait_until(func() -> bool: return client_world.ship != null, 5.0), "and boards the server's ship")
	var guest := client.multiplayer.get_unique_id()
	var sync: WorldSync = host_world.sync
	client_world.launch(skiff())
	assert_true(await wait_until(func() -> bool: return sync.ship_of(guest, false) != null, 2.0), "the server builds the guest's ship")
	assert_true(sync.ship_of(guest, false).global_position.distance_to(Dock.slipway(host_world.START, 1).origin) < 1.0,
			"at slipway 1, beside the server's")
	assert_eq(sync.ships.size(), 2, "whose ship stays")


func test_the_hud_says_you_are_on_a_test_flight() -> void:
	var world := solo_world()
	await get_tree().process_frame
	var banner: Control = world.hud._banner
	assert_false(banner.visible, "no banner at first")
	world.test_flight(skiff())
	await get_tree().process_frame
	assert_true(banner.visible, "a banner on a test flight")
	assert_eq((banner.get_child(0) as Label).text, "Test flight: B returns to the shipyard")
	press_b(world)
	await get_tree().process_frame
	assert_false(banner.visible, "and none after")


func test_a_second_test_flight_still_goes_back_to_the_ship_you_crewed() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var guest := client.multiplayer.get_unique_id()
	var sync: WorldSync = host_world.sync
	client_world.launch(skiff())
	assert_true(await play_until(func() -> bool: return sync.ship_of(guest, false) != null, 2.0), "the guest's ship")
	var theirs := sync.ship_of(guest, false)
	sync.add_ship(StarterShip.build(), Dock.slipway(host_world.START, 3))  # nobody's, which home_ship() would prefer
	sync.remove_ship(host_world.ship, theirs)  # the host has no ship of their own now
	assert_eq(host_world.ship, theirs, "the host crews the guest's ship")
	await play(1.1)
	host_world.test_flight(skiff())
	assert_true(await play_until(func() -> bool: return host_world.on_test_flight(), 2.0), "a test flight")
	var first_id: int = sync.id_of(host_world.ship)
	await play(1.1)
	host_world.test_flight(skiff())
	assert_true(await play_until(func() -> bool: return host_world.on_test_flight() and sync.id_of(host_world.ship) != first_id, 2.0), "and another")
	press_b(host_world)
	assert_eq(host_world.ship, theirs, "B goes back aboard the guest's ship")
