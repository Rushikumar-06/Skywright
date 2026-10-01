extends NetCase
## Markets (spec §3.6): T at a town's dock opens the town, whose market buys and
## sells crates at its own prices. Crates go in the ship you're aboard, owned by you;
## you sell only your own. The server decides every trade.

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


## Presses action for world, as a key press would.
func press_key(in_world: Node3D, action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	in_world._unhandled_input(event)


func move_to_town(town: int) -> void:
	ship.global_transform = Dock.slipway(world.gen.towns[town]["dock"], 0)
	ship.reset_physics_interpolation()


func row_text(town: int, good: String, aboard := 0) -> String:
	return "%-8s buy %3d   sell %3d   aboard %d" % [Economy.GOODS[good]["name"], Economy.price(world.gen, town, good),
			Economy.sell_price(world.gen, town, good), aboard]


func traded() -> Array[String]:
	var goods: Array[String] = []
	for good: String in Economy.GOODS:
		if Economy.GOODS[good]["price"] > 0:
			goods.append(good)
	return goods


## The first of panel's controls of type whose text starts with text, or null.
func find(panel: Node, type: String, text: String) -> Control:
	for control: Node in panel.find_children("*", type, true, false):
		if (control.get("text") as String).begins_with(text):
			return control
	return null


func test_t_opens_the_town_at_a_dock() -> void:
	await start()
	player.crew.position = Vector3(0, 1, -4)  # at the bow, out of the helm's reach
	await get_tree().process_frame
	assert_eq(world.hud._prompt.text, "B   Shipyard   T   Town")
	press_key(world, "town")
	var panel: TownPanel = world.town_panel
	assert_true(panel != null, "the town opens")
	if panel == null:
		return
	assert_true(find(panel, "Label", world.gen.towns[0]["name"]) != null, "titled with the town's name")
	assert_false(player.enabled, "your controls stop")
	press_key(world, "town")
	assert_true(world.town_panel == null, "T closes it")
	assert_true(player.enabled, "and gives them back")
	ship.anchored = true
	ship.global_position = open_sky(world, 1000.0)
	press_key(world, "town")
	assert_true(world.town_panel == null, "nothing opens away from a dock")
	assert_eq(world.hud._message.text, "The market is at the dock.")


func test_prices_differ_between_towns() -> void:
	await start()
	world.open_town()
	for good in traded():
		assert_eq((world.town_panel as TownPanel).market_rows[good].text, row_text(0, good))
	world.close_town()
	move_to_town(3)
	world.open_town()
	var differs := false
	for good in traded():
		assert_eq((world.town_panel as TownPanel).market_rows[good].text, row_text(3, good))
		differs = differs or Economy.price(world.gen, 3, good) != Economy.price(world.gen, 0, good)
	assert_true(differs, "some price differs")


func test_buying_a_crate_stows_it_and_charges_you() -> void:
	await start()
	world.open_town()
	var before := ship.mass
	ledger.trade("grain", 1)
	assert_eq(ship.grid.cargo, {Vector3i(-1, 0, -2): {"good": "grain", "owner": "Ann"}})
	assert_eq(ledger.mine["money"], 1500 - Economy.price(world.gen, 0, "grain"))
	assert_near(ship.mass, before + 100.0, 0.01)
	var panel: TownPanel = world.town_panel
	assert_true(await wait_until(func() -> bool: return panel.market_rows["grain"].text == row_text(0, "grain", 1), 1.0),
			panel.market_rows["grain"].text)


func test_selling_pays_you_and_frees_the_bay() -> void:
	await start()
	ledger.trade("grain", 1)
	ledger.trade("grain", -1)
	assert_true(ship.grid.cargo.is_empty(), "the bay is free")
	assert_eq(ledger.mine["money"], 1500 - Economy.price(world.gen, 0, "grain") + Economy.sell_price(world.gen, 0, "grain"))
	assert_true(ledger.mine["money"] < 1500, "selling where you bought loses money")


func test_a_full_hold_or_an_empty_purse_refuses() -> void:
	await start()
	for i in 4:
		ledger.trade("grain", 1)
	var money: int = ledger.mine["money"]
	ledger.trade("grain", 1)
	assert_eq(world.hud._message.text, "Her hold is full.")
	assert_eq(ledger.mine["money"], money)
	ledger.trade("grain", -1)
	ledger.account_of(1)["money"] = 10
	var cargo := ship.grid.cargo_list()
	ledger.trade("spirits", 1)
	assert_eq(world.hud._message.text, "You can't afford Spirits (%d crowns)." % Economy.price(world.gen, 0, "spirits"))
	ledger.trade("tools", -1)
	assert_eq(world.hud._message.text, "You have no Tools aboard.")
	ledger.trade("mail", -1)
	assert_eq(world.hud._message.text, "Mail isn't for sale.")
	assert_eq(ship.grid.cargo_list(), cargo, "nothing changed")
	assert_eq(ledger.account_of(1)["money"], 10)


func test_you_cant_sell_someone_elses_crates() -> void:
	await start()
	sync.set_cargo(ship, {Vector3i(-1, 0, -2): {"good": "grain", "owner": "Bo"}})
	ledger.trade("grain", -1)
	assert_eq(world.hud._message.text, "You have no Grain aboard.")
	assert_eq(ship.grid.cargo, {Vector3i(-1, 0, -2): {"good": "grain", "owner": "Bo"}}, "Bo's crate stays")
	assert_eq(ledger.mine["money"], 1500)


func test_the_panel_fills_your_spares() -> void:
	await start()
	ship.spares = 10
	world.open_town()
	var panel: TownPanel = world.town_panel
	(find(panel, "Button", "Fill") as Button).pressed.emit()
	assert_eq(ship.spares, 40)
	assert_true(await wait_until(func() -> bool:
		var spares := find(panel, "Label", "Spares")
		return spares != null and spares.get("text") == "Spares    40/40   5 crowns each", 1.0), "the row shows it")


func test_a_guest_trades() -> void:
	assert_true(await sail_together(), "the ship arrives")
	await play(0.3)  # where the guest is reaches the host
	var ours: Ship = host_world.ship
	var theirs: Ledger = client_world.ledger
	var price := Economy.price(host_world.gen, 0, "timber")
	theirs.trade("timber", 1)
	assert_true(await play_until(func() -> bool: return theirs.mine["money"] == 1500 - price, 1.0), "the guest paid")
	assert_eq(ours.grid.cargo, {Vector3i(-1, 0, -2): {"good": "timber", "owner": "Guest"}})
	assert_eq(host_world.ledger.mine["money"], 1500, "the host didn't")
	var copy: Ship = client_world.sync.ships[host_world.sync.id_of(ours)]
	assert_true(await play_until(func() -> bool: return copy.grid.cargo == ours.grid.cargo, 1.0), "the guest sees the crate")


func test_the_server_ignores_junk_trades() -> void:
	assert_true(await sail_together(), "the ship arrives")
	await play(0.3)
	var ours: Ship = host_world.ship
	var books: Ledger = host_world.ledger
	var theirs: Ledger = client_world.ledger
	var guest := client.multiplayer.get_unique_id()
	books.trade("grain", 1)  # the host's crate
	var cargo := ours.grid.cargo_list()
	var money: int = books.account_of(guest)["money"]
	for ask: Array in [["gold", 1], ["mail", 1], ["grain", 5], ["grain", "1"], [7, 1], ["grain", -1]]:
		theirs._trade.rpc_id(1, ask[0], ask[1])
		await play(0.12)
	books.account_of(guest)["money"] = 0
	theirs._trade.rpc_id(1, "grain", 1)
	await play(0.12)
	books.account_of(guest)["money"] = money
	client_world.go_ashore()
	var guest_player: PlayerController = client_world.player
	guest_player.crew.position = ours.global_position + Vector3(0, 0, 2000)
	guest_player.crew.velocity = Vector3.ZERO
	await play(0.3)
	theirs._trade.rpc_id(1, "grain", 1)
	await play(0.3)
	assert_eq(ours.grid.cargo_list(), cargo, "the hold didn't change")
	assert_eq(books.account_of(guest)["money"], money, "nor the guest's purse")
	assert_eq(books.mine["money"], 1500 - Economy.price(host_world.gen, 0, "grain"), "nor the host's")
	client_world.come_aboard(client_world.sync.ships[host_world.sync.id_of(ours)], Vector3(0, 1.4, 0))
	await play(0.3)
	theirs.trade("grain", 1)
	assert_true(await play_until(func() -> bool: return ours.grid.cargo.size() == 2, 1.0), "a fair trade goes through")
