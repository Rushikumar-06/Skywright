extends NetCase
## Fuel (spec §4.4): tanks hold it, engines and trim above 1 burn it, a ship without
## it drifts at trim 1, it's bought at docks and priced into launches, and every
## machine hears how much a ship has.

const AT := Vector3(0, 880, 7000)

var world: Node3D
var sync: WorldSync
var ledger: Ledger
var ship: Ship


## A plain ship in calm air, with fuel units in her tanks (full when below 0).
func plain(grid: ShipGrid, fuel := -1.0) -> Ship:
	var plain_ship := Ship.new(grid)
	plain_ship.calm = true
	plain_ship.fuel = fuel
	plain_ship.position = AT
	add_child(plain_ship)
	return plain_ship


## A solo world, your ship at the first town's slipway 0.
func start() -> void:
	world = solo_world()
	await get_tree().process_frame
	sync = world.sync
	ledger = world.ledger
	ship = world.ship


func test_the_starter_ship_carries_two_tanks_and_still_floats_level() -> void:
	var grid := StarterShip.build()
	assert_eq(grid.type_at(Vector3i(0, -1, 4)), "fuel_tank")
	assert_eq(grid.type_at(Vector3i(0, -1, 6)), "fuel_tank")
	assert_eq(grid.type_at(Vector3i(-2, 1, 5)), "deck")
	assert_eq(grid.type_at(Vector3i(2, 1, 5)), "deck")
	var stats := ShipStats.of(grid, 880.0)
	assert_near(stats.mass, 9566.0, 1.0, "mass")
	assert_near(stats.float_altitude, 882.5, 1.0, "floats")
	assert_true(absf(stats.bow_down) < 0.1, "trim %.3f" % stats.bow_down)
	assert_true(absf(stats.list) < 0.01, "list %.3f" % stats.list)
	assert_eq(stats.blocks, 301)
	assert_eq(stats.fuel, 400.0)
	assert_true(stats.describe().contains("Fuel       400 units, 9.8 km at full throttle"), stats.describe())
	assert_eq(Economy.cost(grid), 1480)


func test_engines_burn_fuel_with_the_throttle() -> void:
	var flying := plain(StarterShip.build())
	assert_eq(flying.fuel, 400.0, "she comes full")
	flying.throttle = 1.0
	await simulate(10.0)
	assert_near(flying.fuel, 392.0, 0.1, "full throttle")
	flying.throttle = 0.5
	await simulate(10.0)
	assert_near(flying.fuel, 388.0, 0.1, "half throttle")
	flying.throttle = 0.0
	flying.trim = 1.1
	await simulate(10.0)
	assert_near(flying.fuel, 381.15, 0.1, "trim held at 1.1")
	flying.trim = 1.0
	flying.throttle = 1.0
	flying.set_hands([{"id": 1, "name": "Fenn", "role": "engineer", "post": Vector3i(0, -1, -5), "at": Vector3.ZERO}])
	await simulate(10.0)
	assert_near(flying.fuel, 371.15, 0.1, "an engineer drives her harder")
	flying.trim = 1.1
	flying.anchored = true
	await simulate(2.0)
	assert_near(flying.fuel, 371.15, 0.1, "anchored, nothing")


func test_a_ship_without_fuel_drifts() -> void:
	var dry := plain(StarterShip.build(), 0.0)
	dry.throttle = 1.0
	await simulate(20.0)
	assert_true(Vector2(dry.linear_velocity.x, dry.linear_velocity.z).length() < 1.0, "no thrust: %.2f m/s" % dry.linear_velocity.length())
	dry.trim = 1.1
	await simulate(1.0 / 60.0)
	assert_eq(dry.trim, 1.0, "trim falls back")
	var most := [0.0]
	dry.helm.take(1)
	dry.helm.climb_input = 1.0
	await simulate(5.0, func(_tick: int) -> void: most[0] = maxf(most[0], dry.trim))
	assert_true(most[0] <= 1.0, "climbing at the helm: %.3f" % most[0])
	dry.helm.climb_input = 0.0
	dry.helm.set_autopilot(true)
	dry.helm.target_altitude = 1100.0
	await simulate(20.0, func(_tick: int) -> void: most[0] = maxf(most[0], dry.trim))
	assert_true(most[0] <= 1.0, "the autopilot: %.3f" % most[0])


func test_a_shot_tank_spills_its_fuel() -> void:
	var hit := plain(StarterShip.build())
	assert_eq(hit.fuel_capacity(), 400.0)
	hit.damage({Vector3i(0, -1, 4): 0})
	hit.rebuild()
	assert_eq(hit.fuel_capacity(), 200.0)
	assert_eq(hit.fuel, 200.0)


func test_a_design_without_a_tank_is_warned() -> void:
	var grid := StarterShip.build()
	for cell in grid.cells_of("fuel_tank"):
		grid.blocks.erase(cell)
	var stats := ShipStats.of(grid, 880.0)
	assert_true(stats.warnings.has("No fuel tank: her engines won't run."), str(stats.warnings))
	assert_true(stats.describe().contains("Fuel       0 units, 0.0 km at full throttle"), stats.describe())


func test_fuel_is_bought_at_a_dock() -> void:
	await start()
	ship.fuel = 100.0
	ledger.buy_fuel()
	assert_eq(ship.fuel, 400.0)
	assert_eq(ledger.mine["money"], 1425)
	assert_eq(world.hud._message.text, "Bought 300 fuel for 75 crowns.")
	ledger.buy_fuel()
	assert_eq(world.hud._message.text, "Her tanks are full.")
	ledger.account_of(1)["money"] = 10
	ship.fuel = 0.0
	ledger.buy_fuel()
	assert_eq(ship.fuel, 40.0)
	assert_eq(ledger.mine["money"], 0)
	assert_eq(world.hud._message.text, "Bought 40 fuel for 10 crowns.")
	ledger.buy_fuel()
	assert_eq(world.hud._message.text, "You can't afford fuel.")
	assert_eq(ship.fuel, 40.0)
	world.open_town()
	var panel: TownPanel = world.town_panel
	assert_true(await wait_until(func() -> bool:
		return panel.market_rows.has("fuel") and (panel.market_rows["fuel"] as Label).text == "Fuel      40/400   4 units a crown", 1.0),
			"the market's fuel row")
	var row := (panel.market_rows["fuel"] as Label).get_parent()
	assert_true(row.get_children().any(func(child: Node) -> bool: return child is Button and child.text == "Fill"), "with Fill")
	world.close_town()
	ledger.account_of(1)["money"] = 500
	ship.anchored = true
	ship.global_position = open_sky(world, 1000.0)
	ledger.buy_fuel()
	assert_eq(world.hud._message.text, "Buy fuel at a town's dock, aboard a ship.")
	assert_eq(ship.fuel, 40.0)
	assert_eq(ledger.account_of(1)["money"], 500)


func test_a_new_ship_comes_fuelled_and_priced() -> void:
	await start()
	ship.fuel = 300.0
	ship.spares = 40
	var old: Ship = world.ship
	world.launch(StarterShip.build())
	assert_true(await wait_until(func() -> bool: return world.ship != old and world.ship != null, 1.0), "launched")
	assert_eq(world.hud._message.text, "Launched for 25 crowns.")
	assert_eq(ledger.mine["money"], 1475)
	assert_eq((world.ship as Ship).fuel, 400.0)


func test_fuel_reaches_the_guest() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var ours: Ship = host_world.ship
	var id: int = host_world.sync.id_of(ours)
	var copy: Ship = client_world.sync.ships[id]
	assert_eq(copy.fuel, 400.0, "her entry had it")
	ours.fuel = 250.0
	assert_true(await play_until(func() -> bool: return copy.fuel == 250.0, 1.5), "the guest hears it: %.1f" % copy.fuel)
	assert_eq(host_world.sync._entry(id)[12], 250.0, "and a late joiner's entry has it")


func test_a_junk_fuel_message_is_refused() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var id: int = host_world.sync.id_of(host_world.ship)
	var theirs: WorldSync = client_world.sync
	var copy: Ship = theirs.ships[id]
	theirs._fuel(999, 100.0)
	for junk: Variant in [-5.0, 401.0, NAN, "x", 3]:
		theirs._fuel(id, junk)
		assert_eq(copy.fuel, 400.0, str(junk))


func test_the_server_ignores_junk_fuel_asks() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var ours: Ship = host_world.ship
	ours.fuel = 100.0
	await play(0.3)  # where the guest is reaches the host
	var books: Ledger = host_world.ledger
	var answers := [0]
	(client_world.ledger as Ledger).told.connect(func(_text: String) -> void: answers[0] += 1)
	for i in 20:
		client_world.ledger._buy_fuel.rpc_id(1)
	await play(0.5)
	assert_eq(answers[0], 1, "answered once")
	assert_eq(ours.fuel, 400.0)
	assert_eq(books.accounts["Guest"]["money"], 1425, "charged once")
	var player: PlayerController = client_world.player
	client_world.go_ashore()
	player.crew.position = open_sky(client_world, 1000.0)
	player.crew.velocity = Vector3.ZERO
	ours.fuel = 100.0
	await play(0.5)
	client_world.ledger._buy_fuel.rpc_id(1)
	await play(0.5)
	assert_eq(ours.fuel, 100.0, "nothing changes from 3 km off")
	assert_eq(books.accounts["Guest"]["money"], 1425)
