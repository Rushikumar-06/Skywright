extends NetCase
## Business on two machines (spec §3.6, §3.8): a hosted game saves and loads with its
## guest's ship, crates, purse and contracts; two players trade at one dock, each with
## their own crates and purse; and a dedicated server keeps its world in its slot.

var dir := ""


func before() -> void:
	dir = "user://test_saves_%d" % randi()
	SaveGame.dir = dir


func after_each() -> void:
	super()
	remove_tree(dir)
	SaveGame.dir = "user://saves"


static func remove_tree(path: String) -> void:
	if path.is_empty() or not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		remove_tree(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


## Guest's own ship launched from the dock they're at, once the server has her.
func launch_own(server_world: Node3D, guest_world: Node3D, guest: SessionScript) -> Ship:
	guest_world.launch(StarterShip.build())
	var peer := guest.multiplayer.get_unique_id()
	var sync: WorldSync = server_world.sync
	await play_until(func() -> bool: return sync.ship_of(peer, false) != null and guest_world.ship != null \
			and guest_world.ship.captain == peer, 3.0)
	(server_world.ledger as Ledger).pay(peer, 200)  # her full tanks left them 20 crowns: enough to trade again
	await play(0.3)  # where the guest stands now reaches the server
	return sync.ship_of(peer, false)


func cannon_at(on: Ship, cell: Vector3i) -> Cannon:
	for cannon in on.cannons:
		if cannon.cell == cell:
			return cannon
	return null


func test_a_hosted_game_saves_and_loads_with_its_guest() -> void:
	before()
	assert_true(await sail_together(), "the ship arrives")
	host.save_slot = "1"
	var theirs := await launch_own(host_world, client_world, client)
	assert_true(theirs != null, "the guest's own ship")
	(client_world.ledger as Ledger).trade("grain", 1)
	var books: Ledger = host_world.ledger
	books.boards[0] = [{"id": 40, "kind": "bounty", "title": "Sink a pirate", "reward": 250, "target": -1, "count": 1, "done": 0}]
	await play(0.12)
	(client_world.ledger as Ledger).take_contract(40)
	var ours: Ship = host_world.ship
	books.trade("tools", 1)
	books.hire("gunner")
	assert_true(await play_until(func() -> bool: return theirs.grid.cargo.size() == 1 and books.accounts["Guest"]["contracts"].size() == 1, 2.0),
			"the guest's crate and contract")
	var our_blocks := ours.grid.to_blocks()
	var their_blocks := theirs.grid.to_blocks()
	var guest_money: int = books.accounts["Guest"]["money"]
	var host_money: int = books.mine["money"]
	assert_eq(host_world.save_game(), OK)
	client.leave()
	host.leave()
	await play(0.3)
	host = make_session("Host2")
	SaveGame.prepare(host, "1")
	var port := free_port()
	assert_eq(host.host("Host", port), OK)
	host.set_sail()
	host_world = add_world(host)
	await play(0.1)
	client = make_session("Client2")
	client.join("Guest", "127.0.0.1", port)
	assert_true(await play_until(func() -> bool: return client.sailing, 5.0), "the guest is back")
	client_world = add_world(client)
	var guest := client.multiplayer.get_unique_id()
	var sync: WorldSync = host_world.sync
	assert_true(await play_until(func() -> bool: return sync.ship_of(guest, false) != null and client_world.ship != null \
			and client_world.ship.captain == guest, 5.0), "aboard their own ship again")
	ours = host_world.ship
	theirs = sync.ship_of(guest, false)
	assert_eq(ours.grid.to_blocks(), our_blocks, "the host's ship")
	assert_eq(theirs.grid.to_blocks(), their_blocks, "the guest's")
	assert_eq(ours.grid.cargo.values().map(func(crate: Dictionary) -> String: return crate["good"]), ["tools"], "the host's crate")
	assert_eq(theirs.grid.cargo.values().map(func(crate: Dictionary) -> String: return crate["good"]), ["grain"], "the guest's")
	assert_eq(host_world.ledger.mine["money"], host_money, "the host's purse")
	var their_ledger: Ledger = client_world.ledger
	assert_true(await play_until(func() -> bool: return their_ledger.mine["money"] == guest_money \
			and their_ledger.mine["contracts"].size() == 1, 2.0), "the guest's purse and contract")
	assert_eq(ours.hands.size(), 1, "the gunner")
	assert_eq(cannon_at(ours, ours.hands[0]["post"]).gunner, ours.hands[0]["id"], "at his cannon")


func test_two_players_trade_at_one_dock() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var ours: Ship = host_world.ship
	var books: Ledger = host_world.ledger
	var theirs: Ledger = client_world.ledger
	var price := Economy.price(host_world.gen, 0, "grain")
	books.trade("grain", 1)
	theirs.trade("grain", 1)
	assert_true(await play_until(func() -> bool: return ours.grid.cargo.size() == 2, 2.0), "two crates in her hold")
	var copy: Ship = client_world.sync.ships[host_world.sync.id_of(ours)]
	assert_true(await play_until(func() -> bool: return copy.grid.cargo.size() == 2, 1.0), "the guest sees both")
	host_world.open_town()
	client_world.open_town()
	var rows := [(host_world.town_panel as TownPanel), (client_world.town_panel as TownPanel)]
	for panel: TownPanel in rows:
		assert_true(await play_until(func() -> bool: return (panel.market_rows["grain"] as Label).text.ends_with("aboard 1"), 1.0),
				"each sees one crate of their own")
	assert_eq(books.mine["money"], 1500 - price)
	assert_true(await play_until(func() -> bool: return theirs.mine["money"] == 1500 - price, 1.0))
	books.trade("grain", -1)
	await play(0.2)
	assert_eq(ours.grid.cargo.values().map(func(crate: Dictionary) -> String: return crate["owner"]), ["Guest"], "the host sold their own")
	books.trade("grain", -1)
	await play(0.2)
	assert_eq(ours.grid.cargo.size(), 1, "and can't sell the guest's")
	theirs.trade("grain", -1)
	assert_true(await play_until(func() -> bool: return ours.grid.cargo.is_empty(), 1.0), "the guest sells theirs")
	var sale := Economy.sell_price(host_world.gen, 0, "grain")
	assert_eq(books.mine["money"], 1500 - price + sale, "each purse moved only for its owner")
	assert_true(await play_until(func() -> bool: return theirs.mine["money"] == 1500 - price + sale, 1.0))


func test_a_dedicated_server_keeps_its_world() -> void:
	before()
	host = make_session("Server")
	host.save_slot = "server"
	var port := free_port()
	host.host("Skyport", port, true)
	host_world = add_world(host)
	await play(0.1)
	client = make_session("Client")
	client.join("Guest", "127.0.0.1", port)
	assert_true(await play_until(func() -> bool: return client.sailing, 5.0), "a guest joins")
	client_world = add_world(client)
	assert_true(await play_until(func() -> bool: return client_world.ship != null, 5.0), "and boards")
	assert_true(await heard(host_world, client))
	var theirs := await launch_own(host_world, client_world, client)
	assert_true(theirs != null, "their own ship")
	(client_world.ledger as Ledger).trade("timber", 1)
	assert_true(await play_until(func() -> bool: return theirs.grid.cargo.size() == 1, 2.0), "with a crate")
	var blocks := theirs.grid.to_blocks()
	assert_eq(host_world.save_game(true), OK)
	client.leave()
	host.leave()
	await play(0.3)
	host = make_session("Server2")
	SaveGame.prepare(host, "server")
	port = free_port()
	host.host("Skyport", port, true)
	host_world = add_world(host)
	await play(0.1)
	var sync: WorldSync = host_world.sync
	assert_eq(sync.ships.size(), 1, "the server's own ship")
	assert_eq((sync.ships.values()[0] as Ship).captain, 0, "nobody's again")
	client = make_session("Client2")
	client.join("Guest", "127.0.0.1", port)
	assert_true(await play_until(func() -> bool: return client.sailing, 5.0), "the guest is back")
	client_world = add_world(client)
	var guest := client.multiplayer.get_unique_id()
	assert_true(await play_until(func() -> bool: return sync.ship_of(guest, false) != null, 5.0), "their ship is back")
	assert_eq(sync.ship_of(guest, false).grid.to_blocks(), blocks)
	assert_eq(sync.ship_of(guest, false).grid.cargo.size(), 1, "with her crate")
