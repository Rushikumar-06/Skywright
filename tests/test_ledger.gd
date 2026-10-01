extends NetCase
## Purses (spec §3.6): the server keeps every player's account by name, sends each
## their own, sells spares at docks, pays crowns for salvage, and takes asks no
## faster than Ledger.ASK_EVERY.

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


func test_you_start_with_a_purse() -> void:
	await start()
	assert_eq(ledger.mine["money"], 1500)
	await get_tree().process_frame
	assert_eq(world.hud._purse.text, "1500 crowns")


func test_spares_are_bought_at_a_dock() -> void:
	await start()
	ship.spares = 5
	await simulate(1.5)
	assert_eq(ship.spares, 5, "no free refill")
	ledger.buy_spares()
	assert_eq(ship.spares, 40)
	assert_eq(ledger.mine["money"], 1325)
	assert_eq(world.hud._message.text, "Bought 35 spares for 175 crowns.")
	ship.anchored = true
	ship.global_position = open_sky(world, 1000.0)
	ship.spares = 5
	ledger.buy_spares()
	assert_eq(world.hud._message.text, "Buy spares at a town's dock, aboard a ship.")
	assert_eq(ship.spares, 5)
	assert_eq(ledger.mine["money"], 1325)


func test_you_buy_what_you_can_afford() -> void:
	await start()
	ledger.account_of(1)["money"] = 50
	ship.spares = 5
	ledger.buy_spares()
	assert_eq(ship.spares, 15)
	assert_eq(ledger.mine["money"], 0)
	ledger.buy_spares()
	assert_eq(world.hud._message.text, "You can't afford a spare (5 crowns).")
	assert_eq(ship.spares, 15)


func test_salvage_pays_crowns() -> void:
	await start()
	ship.anchored = true
	ship.global_position = open_sky(world, 1000.0)
	ship.spares = 40
	world.go_ashore()
	player.crew.position = Sites.wreck_center(world.gen.wrecks[0])
	player.crew.velocity = Vector3.ZERO
	press(player, "interact")
	assert_eq(ledger.mine["money"], 1650, "150 crowns")
	assert_eq(world.hud._message.text, "Salvaged 150 crowns.")
	assert_true(sync.salvaged.has(0), "the site is stripped, though no spares fit")
	ship.spares = 10
	var grid := ShipGrid.new()
	for x in range(-1, 2):
		for z in range(-5, 5):
			grid.set_block(Vector3i(x, 0, z), "deck")
	var wreck := sync.add_ship(grid, Transform3D(Basis.IDENTITY, player.world_position() + Vector3(0, 3, 0)))
	wreck.anchored = true
	press(player, "interact")
	assert_eq(ship.spares, 13, "3 spares")
	assert_eq(ledger.mine["money"], 1680, "and 30 crowns")
	assert_eq(world.hud._message.text, "Salvaged 30 crowns and 3 spares.")
	assert_eq(sync.id_of(wreck), 0, "she's broken up")


func test_each_player_has_their_own_purse() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var guest := client.multiplayer.get_unique_id()
	var theirs: Ledger = client_world.ledger
	assert_eq(theirs.mine["money"], 1500)
	host_world.ledger.pay(guest, 100)
	assert_true(await play_until(func() -> bool: return theirs.mine["money"] == 1600, 1.0), "the guest is paid")
	assert_eq(host_world.ledger.mine["money"], 1500, "the host isn't")


func test_a_purse_is_kept_by_name() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var books: Ledger = host_world.ledger
	books.pay(client.multiplayer.get_unique_id(), 100)
	client.leave()
	assert_true(await play_until(func() -> bool: return host.players.size() == 1, 5.0), "the guest left")
	for who: Array in [["Guest", 1600], ["Cy", 1500]]:
		var again := make_session("Again" + who[0])
		again.join(who[0], "127.0.0.1", host.port)
		assert_true(await play_until(func() -> bool: return again.sailing, 5.0), "%s joins" % who[0])
		var again_world := add_world(again)
		assert_true(await play_until(func() -> bool: return again_world.ship != null and again_world.ledger.mine["money"] == who[1], 5.0),
				"%s has %d crowns" % who)
		again.leave()
		assert_true(await play_until(func() -> bool: return host.players.size() == 1, 5.0), "and leaves")


func test_asks_are_rate_limited() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var ours: Ship = host_world.ship
	ours.spares = 5
	await play(0.3)  # where the guest is reaches the host
	var answers := [0]
	(client_world.ledger as Ledger).told.connect(func(_text: String) -> void: answers[0] += 1)
	for i in 20:
		client_world.ledger._buy_spares.rpc_id(1)
	await play(0.5)
	assert_eq(answers[0], 1, "answered once")
	assert_eq(ours.spares, 40)
