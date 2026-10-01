extends NetCase
## Saving and loading a game (spec §3.8, §4.10): the host's World captures every
## ship (but pirates, nobody's wrecks and test flights), every account, the clock, the
## stripped wrecks and the host's map; loading puts them back. It autosaves every five
## minutes and on docking, and a captain who leaves finds their ship waiting.

var dir := ""


func after_each() -> void:
	super()
	if not dir.is_empty():
		remove_tree(dir)
	SaveGame.dir = "user://saves"


func fresh() -> void:
	dir = "user://test_saves_%d" % randi()
	SaveGame.dir = dir


static func remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		remove_tree(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


## A solo game as player_name, from slot when given.
func solo(player_name := "Ann", slot := "") -> Node3D:
	var session := make_session("Solo%d" % randi())
	if not slot.is_empty():
		SaveGame.prepare(session, slot)
	session.start_solo(player_name)
	var world := add_world(session)
	await get_tree().process_frame
	return world


## Leaves world's game, as Leave game does, and frees its world.
func leave(world: Node3D) -> void:
	world.session.leave()
	world.queue_free()
	await get_tree().process_frame


func cannon_at(on: Ship, cell: Vector3i) -> Cannon:
	for cannon in on.cannons:
		if cannon.cell == cell:
			return cannon
	return null


func test_a_solo_game_saves_and_loads() -> void:
	fresh()
	var world := await solo()
	world.session.save_slot = "1"
	var sync: WorldSync = world.sync
	var ship: Ship = world.ship
	ship.anchored = true
	ship.global_position = open_sky(world, 1000.0)
	ship.global_basis = Basis(Vector3.UP, 0.4)
	sync.damage_ship(ship, {Vector3i(0, 0, 1): 10, Vector3i(-2, 0, 2): 0})
	sync.set_cargo(ship, {Vector3i(-1, 0, -2): {"good": "grain", "owner": "Ann"}, Vector3i(1, 0, 4): {"good": "tools", "owner": "Ann"}})
	ship.spares = 12
	sync.set_hands(ship, [{"id": -1, "name": "Fenn", "role": "gunner", "post": Vector3i(2, 1, 1), "at": ship.spot_near(Vector3i(2, 1, 1))}])
	var ledger: Ledger = world.ledger
	ledger.account_of(1)["money"] = 900
	ledger.account_of(1)["contracts"] = [{"id": 3, "kind": "scout", "title": "Scout it", "reward": 180, "target": 0, "count": 1, "done": 0}]
	sync.salvaged[2] = true
	sync.set_clock(sync.now() + 30.0)
	var blocks := ship.grid.to_blocks()
	var place := ship.global_transform
	var cargo := ship.grid.cargo_list()
	var clock := sync.now()
	world.exploration.reveal(world.START)  # where you've been, and where you are
	world.exploration.reveal(ship.global_position)
	var seen: PackedByteArray = world.exploration.image.get_data()
	assert_eq(world.save_game(), OK)
	await leave(world)
	world = await solo("Ann", "1")
	sync = world.sync
	ship = world.ship
	assert_true(ship != null, "your ship is back, with you aboard")
	if ship == null:
		return
	assert_eq(ship.grid.to_blocks(), blocks, "her blocks and hit points")
	assert_true(ship.global_position.distance_to(place.origin) < 0.01, "where she was")
	assert_true(ship.global_basis.get_rotation_quaternion().angle_to(place.basis.get_rotation_quaternion()) < 0.01, "facing as she was")
	assert_eq(ship.grid.cargo_list(), cargo, "her crates")
	assert_eq(ship.spares, 12)
	assert_eq(ship.hands.size(), 1, "her gunner")
	assert_eq(cannon_at(ship, Vector3i(2, 1, 1)).gunner, ship.hands[0]["id"], "at his post")
	assert_eq(world.ledger.mine["money"], 900)
	assert_eq(world.ledger.mine["contracts"].size(), 1, "your contract")
	assert_true(sync.salvaged.has(2), "the stripped wreck")
	assert_near(sync.now(), clock, 0.5, "the clock")
	var now_seen: PackedByteArray = world.exploration.image.get_data()
	var kept := range(seen.size()).all(func(i: int) -> bool: return seen[i] == 0 or now_seen[i] > 0)
	assert_true(kept and seen.count(255) > 0, "your map, every cell you'd seen")


func test_autosaves_every_five_minutes_and_on_docking() -> void:
	fresh()
	var world := await solo()
	world.session.save_slot = "1"
	var autos := SaveGame.autosave_paths("1")
	world._since_save = 299.0
	await simulate(1.5)
	assert_true(FileAccess.file_exists(autos[0].path_join("world.json")), "five minutes on, an autosave")
	var ship: Ship = world.ship
	ship.global_transform = Dock.slipway(world.gen.towns[1]["dock"], 0)
	await simulate(1.5)
	assert_false(FileAccess.file_exists(autos[1].path_join("world.json")), "docking soon after doesn't save again")
	world._since_save = 31.0
	ship.global_transform = Dock.slipway(world.gen.towns[0]["dock"], 0)
	await simulate(1.5)
	assert_true(FileAccess.file_exists(autos[1].path_join("world.json")), "docking later does")


func test_a_loaded_game_without_your_ship_starts_on_the_quay() -> void:
	fresh()
	var save := {"world": {"seed": NetCase.SEED, "time": 10.0, "salvaged": [], "exploration": "", "host": "Ann", "saved": 100.0},
			"ships": [], "players": {}}
	assert_eq(SaveGame.write(SaveGame.slot_path("1"), save), OK)
	var world := await solo("Ann", "1")
	var player: PlayerController = world.player
	assert_true(player != null, "you're here")
	if player == null:
		return
	var quay := Dock.quay_spot(world.START)
	assert_true(await wait_until(func() -> bool: return player.ship == null and player.crew.is_on_floor() \
			and player.world_position().distance_to(quay) < 3.0, 3.0), "standing on the starting town's quay")


func test_the_host_keeps_their_progress_under_a_new_name() -> void:
	fresh()
	var world := await solo("Ann")
	world.session.save_slot = "1"
	world.ledger.account_of(1)["money"] = 900
	assert_eq(world.save_game(), OK)
	await leave(world)
	world = await solo("Anna", "1")
	assert_true(world.ship != null and world.ship.captain == 1, "her ship is Anna's")
	assert_eq(world.ledger.mine["money"], 900, "and so is her purse")


func test_a_leavers_ship_waits_for_them() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var host_sync: WorldSync = host_world.sync
	var guest := client.multiplayer.get_unique_id()
	client_world.launch(StarterShip.build())
	assert_true(await play_until(func() -> bool: return host_sync.ship_of(guest, false) != null and client_world.ship != null \
			and client_world.ship.captain == guest, 3.0), "the guest's own ship")
	await play(0.3)
	(client_world.ledger as Ledger).trade("grain", 1)
	var theirs := host_sync.ship_of(guest, false)
	assert_true(await play_until(func() -> bool: return theirs.grid.cargo.size() == 1, 2.0), "with a crate")
	var blocks := theirs.grid.to_blocks()
	var place := theirs.global_transform
	var money: int = host_world.ledger.account_of(guest)["money"]
	client.leave()
	assert_true(await play_until(func() -> bool: return host_sync.ship_of(guest, false) == null, 3.0), "her captain gone, she leaves too")
	assert_true(host_sync.stored.has("Guest"), "and waits in the save")
	assert_eq(host_sync.stored["Guest"]["cargo"].size(), 1, "with her crate")
	var captured: Dictionary = host_world.capture()
	assert_true(captured["ships"].any(func(record: Dictionary) -> bool: return record["captain"] == "Guest"), "a save has her")
	var again := make_session("Again")
	again.join("Guest", "127.0.0.1", host.port)
	assert_true(await play_until(func() -> bool: return again.sailing, 5.0), "the guest is back")
	var again_world := add_world(again)
	assert_true(await play_until(func() -> bool:
		var back: Ship = again_world.ship
		return back != null and back.captain == again.multiplayer.get_unique_id(), 5.0), "aboard their own ship again")
	var back := host_sync.ship_of(again.multiplayer.get_unique_id(), false)
	assert_eq(back.grid.to_blocks(), blocks, "the same ship")
	assert_eq(back.grid.cargo.size(), 1, "and crate")
	assert_true(back.global_position.distance_to(place.origin) < 1.0, "where she was")
	assert_false(host_sync.stored.has("Guest"))
	assert_true(await play_until(func() -> bool: return again_world.ledger.mine["money"] == money, 2.0), "their purse as it was")


func test_contracts_taken_after_loading_have_new_ids() -> void:
	fresh()
	var world := await solo()
	world.session.save_slot = "1"
	world.ledger.account_of(1)["contracts"] = [{"id": 2, "kind": "bounty", "title": "Sink a pirate", "reward": 250, "target": -1, "count": 1, "done": 0}]
	assert_eq(world.save_game(), OK)
	await leave(world)
	world = await solo("Ann", "1")
	var ledger: Ledger = world.ledger
	ledger.ask_board()
	for offer: Dictionary in ledger.boards[0]:
		assert_true(offer["id"] > 2, "offer %d isn't one you hold" % offer["id"])
	ledger.take_contract(ledger.boards[0][0]["id"])
	var ids: Array = ledger.mine["contracts"].map(func(each: Dictionary) -> int: return each["id"])
	assert_eq(ids.size(), 2)
	assert_true(ids[0] != ids[1], "two contracts, two ids: %s" % [ids])


func test_a_failed_autosave_waits_for_the_next_one() -> void:
	fresh()
	allowed_engine_errors = 1  # the one failed attempt logs that it couldn't make the folder
	var blocker := FileAccess.open(dir, FileAccess.WRITE)  # a file where the saves folder should be
	blocker.close()
	var world := await solo()
	world.session.save_slot = "1"
	world._since_save = 299.0
	await simulate(1.5)
	assert_true((world.hud._message.text as String).begins_with("Couldn't autosave ("), world.hud._message.text)
	assert_true(world._since_save < 5.0, "it tries again in five minutes, not every frame (%.1f s)" % world._since_save)
	DirAccess.remove_absolute(dir)
