extends NetCase
## Contracts (spec §3.6): each town's board offers three, drawn when first asked for.
## Taking a delivery loads its mail; it pays when a ship carrying it docks at its town.
## Bounties pay for pirates beaten near you, salvage for stripping her wreck, and
## scouting for getting near the landmark. Three at most; dropping one unloads its mail.

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


func delivery(id := 99, count := 2, town := 1) -> Dictionary:
	var to: String = world.gen.towns[town]["name"]
	var title := "Carry a crate of mail to %s" % to if count == 1 else "Carry %d crates of mail to %s" % [count, to]
	return {"id": id, "kind": "delivery", "title": title, "reward": 240, "target": town, "count": count, "done": 0}


func offer(id: int, kind: String, target: int, count := 1, reward := 100) -> Dictionary:
	return {"id": id, "kind": kind, "title": "%s %d" % [kind, id], "reward": reward, "target": target, "count": count, "done": 0}


## Puts offers on town 0's board, as if drawn.
func post(offers: Array) -> void:
	ledger.ask_board()
	ledger.boards[0] = offers


func mail() -> Array:
	var cells := []
	for cell: Vector3i in ship.grid.cargo:
		if ship.grid.cargo[cell]["good"] == "mail":
			cells.append(cell)
	cells.sort()
	return cells


## Steps you off your ship and puts you, still, at p in the world.
func ashore_at(p: Vector3) -> void:
	if world.ship != null:
		world.go_ashore()
	player.crew.position = p
	player.crew.velocity = Vector3.ZERO
	player.crew.reset_physics_interpolation()


func to_open_sky() -> void:
	ship.anchored = true
	ship.global_position = open_sky(world, 1000.0)


func test_a_board_offers_three_contracts() -> void:
	await start()
	ledger.ask_board()
	var board: Array = ledger.boards[0]
	assert_eq(board.size(), 3)
	for each: Dictionary in board:
		assert_true(each["id"] >= 1 and not (each["title"] as String).is_empty() and each["reward"] > 0, str(each))
	world.open_town()
	var panel: TownPanel = world.town_panel
	panel.show_section("contracts")
	await get_tree().process_frame
	var labels := panel.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text)
	var takes := panel.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == "Take")
	for each: Dictionary in board:
		assert_true(labels.has("%s   %d crowns" % [each["title"], each["reward"]]), "%s listed" % each["title"])
	assert_eq(takes.size(), 3, "each with Take")


func test_taking_a_delivery_loads_its_mail() -> void:
	await start()
	post([delivery()])
	ledger.take_contract(99)
	assert_eq(mail(), [Vector3i(-1, 0, -2), Vector3i(-1, 0, 4)], "two crates of mail")
	assert_eq(ship.grid.cargo[Vector3i(-1, 0, -2)]["owner"], "Ann")
	assert_eq(ledger.mine["contracts"], [delivery()], "the contract is yours")
	assert_eq(world.hud._message.text, "Contract taken: %s." % delivery()["title"])
	assert_eq(ledger.boards[0].size(), 1, "a fresh offer in its place")
	assert_true(ledger.boards[0][0]["id"] != 99)


func test_a_delivery_pays_at_its_town() -> void:
	await start()
	post([delivery()])
	ledger.take_contract(99)
	ship.global_transform = Dock.slipway(world.gen.towns[2]["dock"], 0)
	await simulate(1.5)
	assert_eq(mail().size(), 2, "not at another town")
	assert_eq(ledger.mine["contracts"].size(), 1)
	ship.global_transform = Dock.slipway(world.gen.towns[1]["dock"], 0)
	await simulate(1.5)
	assert_eq(mail(), [], "the mail is delivered")
	assert_eq(ledger.mine["money"], 1740, "and paid for")
	assert_eq(world.hud._message.text, "Contract done: %s. +240 crowns." % delivery()["title"])
	assert_eq(ledger.mine["contracts"], [])


func test_a_bounty_pays_for_pirates_beaten_nearby() -> void:
	await start()
	post([offer(7, "bounty", -1, 2, 500)])
	ledger.take_contract(7)
	to_open_sky()
	var beat := func(offset: Vector3) -> Ship:
		var pirate := sync.add_ship(PirateShip.build(), ship.global_transform.translated(offset), 0, false, 0, true)
		pirate.anchored = true
		sync.damage_ship(pirate, {pirate.grid.cells_of("helm")[0]: 0})
		return pirate
	beat.call(Vector3(2000, 0, 0))
	await get_tree().process_frame
	sync._wear()
	assert_eq(ledger.mine["contracts"][0]["done"], 0, "too far off to count")
	beat.call(Vector3(300, 0, 0))
	await get_tree().process_frame
	sync._wear()
	assert_eq(ledger.mine["contracts"][0]["done"], 1, "one beaten nearby")
	sync._wear()
	assert_eq(ledger.mine["contracts"][0]["done"], 1, "counted once")
	var sunk := sync.add_ship(PirateShip.build(), ship.global_transform.translated(Vector3(-300, 0, 0)), 0, false, 0, true)
	sync.remove_ship(sunk, null, true)
	assert_eq(ledger.mine["contracts"], [], "the second, lost to the Roil, completes it")
	assert_eq(ledger.mine["money"], 2000)


func test_a_salvage_contract_pays_when_you_strip_her() -> void:
	await start()
	post([offer(8, "salvage", 0, 1, 300)])
	ledger.take_contract(8)
	to_open_sky()
	ashore_at(Sites.wreck_center(world.gen.wrecks[1]))
	press(player, "interact")
	assert_true(sync.salvaged.has(1))
	assert_eq(ledger.mine["contracts"].size(), 1, "another wreck doesn't count")
	ashore_at(Sites.wreck_center(world.gen.wrecks[0]))
	press(player, "interact")
	assert_eq(ledger.mine["contracts"], [], "done")
	assert_eq(ledger.mine["money"], 1500 + 2 * Economy.SALVAGE_MONEY + 300)


func test_scouting_pays_when_you_get_there() -> void:
	await start()
	post([offer(9, "scout", 0, 1, 180)])
	ledger.take_contract(9)
	to_open_sky()
	var mark: Vector3 = world.gen.landmarks[0]["at"]
	ashore_at(mark + Vector3(500, 0, 0))
	sync._wear()
	assert_eq(ledger.mine["contracts"].size(), 1, "not near enough")
	ashore_at(mark + Vector3(350, 0, 0))
	sync._wear()
	assert_eq(ledger.mine["contracts"], [], "scouted")
	assert_eq(ledger.mine["money"], 1680)
	assert_eq(world.hud._message.text, "Contract done: scout 9. +180 crowns.")


func test_three_contracts_at_most() -> void:
	await start()
	post([offer(1, "bounty", -1), offer(2, "bounty", -1), offer(3, "bounty", -1), offer(4, "bounty", -1)])
	for id in [1, 2, 3, 4]:
		ledger.take_contract(id)
	assert_eq(world.hud._message.text, "You have three contracts already.")
	assert_eq(ledger.mine["contracts"].size(), 3)


func test_dropping_a_delivery_unloads_its_mail() -> void:
	await start()
	post([delivery()])
	ledger.take_contract(99)
	ledger.drop_contract(99)
	assert_eq(mail(), [], "the mail is unloaded")
	assert_eq(ledger.mine["contracts"], [])
	assert_eq(world.hud._message.text, "Contract dropped: Carry 2 crates of mail to %s." % world.gen.towns[1]["name"])


func test_a_delivery_needs_room() -> void:
	await start()
	var grain := {}
	for cell in ship.grid.cells_of("cargo_bay"):
		grain[cell] = {"good": "grain", "owner": "Ann"}
	sync.set_cargo(ship, grain)
	post([delivery()])
	ledger.take_contract(99)
	assert_eq(world.hud._message.text, "Your hold has room for 0 crates.")
	assert_eq(ledger.mine["contracts"], [])
	assert_eq(ledger.boards[0], [delivery()], "still on the board")


func test_a_guest_takes_and_completes_a_contract() -> void:
	assert_true(await sail_together(), "the ship arrives")
	await play(0.3)  # where the guest is reaches the host
	var books: Ledger = host_world.ledger
	var theirs: Ledger = client_world.ledger
	books.boards[0] = [{"id": 50, "kind": "scout", "title": "Scout it", "reward": 180, "target": 0, "count": 1, "done": 0}]
	theirs.take_contract(50)
	assert_true(await play_until(func() -> bool: return theirs.mine["contracts"].size() == 1, 1.0), "the guest has it")
	assert_eq(books.accounts["Guest"]["contracts"][0]["id"], 50, "and the host's books say so")
	var said := [""]
	theirs.told.connect(func(text: String) -> void: said[0] = text)
	client_world.go_ashore()
	var guest: PlayerController = client_world.player
	guest.crew.position = (host_world.gen.landmarks[0]["at"] as Vector3) + Vector3(300, 0, 0)
	guest.crew.velocity = Vector3.ZERO
	assert_true(await play_until(func() -> bool: return theirs.mine["money"] == 1680, 2.0), "they're paid")
	assert_eq(said[0], "Contract done: Scout it. +180 crowns.")


func test_the_server_ignores_junk_contract_asks() -> void:
	assert_true(await sail_together(), "the ship arrives")
	await play(0.3)
	var books: Ledger = host_world.ledger
	var theirs: Ledger = client_world.ledger
	var guest := client.multiplayer.get_unique_id()
	books.boards[0] = [offer(60, "bounty", -1), offer(61, "bounty", -1)]
	books.boards[3] = [offer(77, "bounty", -1)]
	books.take_contract(61)  # the host's
	var before := var_to_str([books.boards, books.accounts])
	for ask: Variant in [12345, 77, "60", 60.0]:
		theirs._take.rpc_id(1, ask)
		await play(0.12)
	theirs._drop.rpc_id(1, 61)
	await play(0.12)
	assert_eq(var_to_str([books.boards, books.accounts]), before, "unknown, elsewhere, junk, or the host's: nothing changes")
	books.account_of(guest)["contracts"] = [offer(1, "bounty", -1), offer(2, "bounty", -1), offer(3, "bounty", -1)]
	before = var_to_str([books.boards, books.accounts])
	theirs._take.rpc_id(1, 60)
	await play(0.12)
	assert_eq(var_to_str([books.boards, books.accounts]), before, "not a fourth")
	books.account_of(guest)["contracts"] = []
	client_world.go_ashore()
	var guest_player: PlayerController = client_world.player
	guest_player.crew.position = host_world.ship.global_position + Vector3(0, 0, 3000)
	guest_player.crew.velocity = Vector3.ZERO
	await play(0.3)
	before = var_to_str([books.boards, books.accounts])
	theirs._take.rpc_id(1, 60)
	await play(0.3)
	assert_eq(var_to_str([books.boards, books.accounts]), before, "not from 3 km out")
	assert_eq(books.mine["contracts"].size(), 1, "the host keeps theirs")
