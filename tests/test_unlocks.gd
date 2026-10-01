extends NetCase
## Part tiers and launch prices (spec §3.6): launching costs a design's parts less
## what your old ship is worth (or her insurance once she's lost), alloy plates and
## lift stones must be unlocked, with money, at towns further in, test flights are
## free, and the server checks the town, the unlocks and the money.

var world: Node3D
var sync: WorldSync
var ledger: Ledger
var ship: Ship
var player: PlayerController


## A solo world, your ship at the first town's slipway 0.
func start() -> void:
	world = solo_world()
	await get_tree().process_frame
	sync = world.sync
	ledger = world.ledger
	ship = world.ship
	player = world.player


static func skiff() -> ShipGrid:
	var grid := StarterShip.build()
	for cell in grid.cells_of("balloon"):
		if absi(cell.z) > 1:
			grid.blocks.erase(cell)
	return grid


## The starter ship with ten iron plates under her keel: 120 crowns more.
static func armoured() -> ShipGrid:
	var grid := StarterShip.build()
	for z in range(-4, 6):
		grid.set_block(Vector3i(0, -2, z), "iron")
	return grid


## The starter ship with an alloy plate under her keel.
static func with_alloy() -> ShipGrid:
	var grid := StarterShip.build()
	grid.set_block(Vector3i(0, -2, 0), "alloy")
	return grid


func first_town_in(region: int) -> int:
	for i in world.gen.towns.size():
		if world.gen.towns[i]["region"] == region:
			return i
	return -1


## Launches design and waits for the new ship, or for nothing to happen.
func launch(design: ShipGrid) -> bool:
	var old: Ship = world.ship
	world.launch(design)
	return await wait_until(func() -> bool: return world.ship != old and world.ship != null, 1.0)


func test_launching_charges_the_difference() -> void:
	await start()
	assert_true(await launch(armoured()), "launched")
	assert_eq(ledger.mine["money"], 1380)
	assert_eq(world.hud._message.text, "Launched for 120 crowns.")
	await simulate(1.1)
	var now: Ship = world.ship
	sync.damage_ship(now, {now.grid.cells_of("frame")[0]: 50})
	assert_true(await launch(armoured()), "relaunched")
	assert_eq(ledger.mine["money"], 1378, "2 crowns to mend a frame")
	await simulate(1.1)
	assert_true(await launch(skiff()), "a smaller ship")
	assert_eq(ledger.mine["money"], 1378, "costs nothing")


func test_a_design_with_locked_parts_cant_launch() -> void:
	await start()
	assert_false(await launch(with_alloy()), "nothing launched")
	assert_eq(world.hud._message.text, "Unlock Alloy plate first.")
	assert_eq(ledger.mine["money"], 1500)
	world.open_shipyard()
	var yard: Shipyard = world.shipyard
	yard.design.replace(with_alloy())
	assert_true(yard._launch_button.disabled, "Launch is off")
	assert_eq(yard.note_text(), "Unlock Alloy plate to launch her.")


func test_test_flights_are_free_even_with_locked_parts() -> void:
	await start()
	world.test_flight(with_alloy())
	assert_true(world.ship != null and world.ship.test, "she flies")
	assert_eq(ledger.mine["money"], 1500)


func test_unlocking_at_a_town_further_in() -> void:
	await start()
	ledger.unlock("alloy")
	assert_eq(world.hud._message.text, "Alloy plate isn't sold here: try a town in The Shattered Belt or further in.")
	var town := first_town_in(WorldGen.Region.SHATTERED)
	ship.global_transform = Dock.slipway(world.gen.towns[town]["dock"], 0)
	ship.reset_physics_interpolation()
	ledger.account_of(1)["money"] = 2500
	ledger.unlock("alloy")
	assert_eq(world.hud._message.text, "Unlocked Alloy plate.")
	assert_eq(ledger.mine["unlocks"], ["alloy"])
	assert_eq(ledger.mine["money"], 500)
	assert_true(await launch(with_alloy()), "the alloy design launches")
	assert_eq(ledger.mine["money"], 470)
	ledger.unlock("alloy")
	assert_eq(world.hud._message.text, "You've unlocked Alloy plate already.")


func test_a_lost_ship_is_insured_for_half() -> void:
	await start()
	ship.global_position.y = -5.0
	sync._wear()
	assert_eq(ledger.mine["insured"], 740)
	assert_eq(world.hud._message.text, "Your ship is lost to the Roil. The shipyard has her blueprint, and her insurance pays half of her.")
	assert_true(await wait_until(func() -> bool: return player.ship == null and player.crew.is_on_floor(), 5.0), "on a quay")
	var dock: Vector3 = world.gen.towns[world.town_at(player.world_position()) if world.at_dock() else 0]["dock"]
	player.crew.position = dock + Vector3(5.0, -1.5 + CrewMember.HEIGHT / 2.0 + 0.05, 0)
	await simulate(0.2)
	assert_true(await launch(world.design.grid), "rebuilt")
	assert_eq(ledger.mine["money"], 760, "for half her cost")
	assert_eq(ledger.mine["insured"], 0, "the insurance is spent")


func test_crates_move_to_the_new_ship() -> void:
	await start()
	var crates := {Vector3i(1, 0, -2): {"good": "grain", "owner": "Ann"}, Vector3i(1, 0, 4): {"good": "tools", "owner": "Ann"}}
	sync.set_cargo(ship, crates)
	var one_bay := StarterShip.build()
	for cell in one_bay.cells_of("cargo_bay").slice(1):
		one_bay.set_block(cell, "deck")
	assert_false(await launch(one_bay), "no room")
	assert_eq(world.hud._message.text, "She has room for 1 of the 2 crates aboard. Sell some first.")
	await simulate(1.1)
	assert_true(await launch(StarterShip.build()), "launched")
	assert_eq((world.ship as Ship).grid.cargo, {Vector3i(-1, 0, -2): crates[Vector3i(1, 0, -2)], Vector3i(-1, 0, 4): crates[Vector3i(1, 0, 4)]},
			"the crates came along, to her first bays")


func test_the_shipyard_shows_the_price_and_the_locks() -> void:
	await start()
	world.open_shipyard()
	var yard: Shipyard = world.shipyard
	assert_eq(yard._launch_button.text, "Launch · free")
	yard.design.replace(armoured())
	assert_eq(yard._launch_button.text, "Launch · 120 crowns")
	assert_eq(yard._palette["alloy"].text, "Alloy plate   110 kg   locked")
	yard.select("alloy")
	assert_eq(yard._block_stats.text, "110 kg · 260 hit points · 30 crowns")
	yard.design.replace(with_alloy())
	var captions := yard.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text)
	assert_true(captions.has("Alloy plate is sold at towns in The Shattered Belt or further in."), "where to unlock it")


func test_the_server_refuses_a_launch_it_shouldnt_make() -> void:
	assert_true(await sail_together(), "the ship arrives")
	await play(0.3)  # where the guest is reaches the host
	var host_sync: WorldSync = host_world.sync
	var books: Ledger = host_world.ledger
	var theirs: Ledger = client_world.ledger
	var guest := client.multiplayer.get_unique_id()
	var said := [""]
	theirs.told.connect(func(text: String) -> void: said[0] = text)
	var starter := StarterShip.build()
	var ask := func(design: ShipGrid, town: int) -> void:
		client_world.sync._launch.rpc_id(1, design.to_bytes(), design.paint_names(), false, town)
	ask.call(starter, 3)
	assert_true(await play_until(func() -> bool: return said[0] == "Launch from a town's dock.", 1.0), said[0])
	await play(1.1)
	books.account_of(guest)["money"] = 100
	ask.call(starter, 0)
	assert_true(await play_until(func() -> bool: return said[0] == "She costs 1480 crowns and you have 100.", 1.0), said[0])
	await play(1.1)
	books.account_of(guest)["money"] = 1500
	ask.call(with_alloy(), 0)
	assert_true(await play_until(func() -> bool: return said[0] == "Unlock Alloy plate first.", 1.0), said[0])
	assert_true(host_sync.ship_of(guest, false) == null, "nothing built")
	assert_eq(books.account_of(guest)["money"], 1500, "nothing charged")
	await play(1.1)
	ask.call(starter, 0)
	ask.call(starter, 0)
	assert_true(await play_until(func() -> bool: return host_sync.ship_of(guest, false) != null, 2.0), "a fair launch")
	await play(0.5)
	assert_eq(host_sync.ships.values().filter(func(each: Ship) -> bool: return each.captain == guest).size(), 1, "one ship")
	assert_eq(books.account_of(guest)["money"], 20, "charged once")


func test_a_test_flight_earns_nothing() -> void:
	await start()
	world.test_flight(with_alloy())
	var trial: Ship = world.ship
	assert_true(trial.test, "on a test flight")
	trial.anchored = true
	trial.global_position = open_sky(world, 1000.0)
	ledger.account_of(1)["contracts"] = [{"id": 8, "kind": "bounty", "title": "Sink a pirate", "reward": 250, "target": -1, "count": 1, "done": 0},
			{"id": 9, "kind": "scout", "title": "Scout it", "reward": 180, "target": 0, "count": 1, "done": 0}]
	var pirate := sync.add_ship(PirateShip.build(), trial.global_transform.translated(Vector3(300, 0, 0)), 0, false, 0, true)
	sync.remove_ship(pirate, null, true)
	world.go_ashore()
	player.crew.position = Sites.wreck_center(world.gen.wrecks[0])
	player.crew.velocity = Vector3.ZERO
	press(player, "interact")
	assert_eq(world.hud._message.text, "Test flights can't salvage.")
	assert_false(sync.salvaged.has(0), "the wreck keeps her loot")
	player.crew.position = (world.gen.landmarks[0]["at"] as Vector3) + Vector3(300, 0, 0)
	sync._wear()
	assert_eq(ledger.account_of(1)["contracts"].size(), 2, "no bounty or scouting counts")
	assert_eq(ledger.account_of(1)["contracts"][0]["done"], 0)
	assert_eq(ledger.mine["money"], 1500, "and no crowns")
