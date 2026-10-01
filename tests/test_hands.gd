extends NetCase
## Hired hands (spec §3.4): hired at a town's dock, a bunk each. Gunners man a cannon
## and fire at pirates, repairers put out fires and then mend with the ship's spares,
## and engineers drive her engine harder. They go down with their ship and move to
## the ship that replaces theirs.

const START := Vector3(0, 877, 7000)
const STARBOARD := Vector3i(2, 1, 1)
const PORT := Vector3i(-2, 1, 1)

var world: Node3D
var sync: WorldSync
var ledger: Ledger
var ship: Ship
var player: PlayerController


## A solo world, your ship at the first town's slipway 0, with the server's luck seeded.
func start() -> void:
	world = solo_world()
	await get_tree().process_frame
	sync = world.sync
	sync.rng.seed = 1
	ledger = world.ledger
	ship = world.ship
	player = world.player


func to_open_sky() -> void:
	ship.anchored = true
	ship.global_position = open_sky(world, 1000.0)


func hand(on: Ship, id: int, role: String, post := Vector3i.ZERO, hand_name := "Fenn") -> Dictionary:
	var at := on.crew_spawn(0) if role == "repairer" else on.spot_near(post)
	return {"id": id, "name": hand_name, "role": role, "post": post, "at": at}


func cannon_at(on: Ship, cell: Vector3i) -> Cannon:
	for cannon in on.cannons:
		if cannon.cell == cell:
			return cannon
	return null


func brains(on: Ship) -> Array:
	return on.get_children().filter(func(child: Node) -> bool: return child is CrewHand)


func hp(cell: Vector3i) -> int:
	return ship.grid.blocks[cell]["hp"] if ship.grid.blocks.has(cell) else 0


func test_hiring_a_hand_needs_a_bunk_and_a_post() -> void:
	await start()
	ledger.hire("gunner")
	assert_eq(ship.hands.size(), 1)
	var gunner: Dictionary = ship.hands[0]
	assert_eq(gunner["role"], "gunner")
	assert_eq(gunner["post"], PORT, "the port cannon, first in cell order")
	assert_eq(cannon_at(ship, PORT).gunner, gunner["id"], "which he mans")
	assert_true(gunner["id"] < 0)
	assert_eq(ledger.mine["money"], 1350)
	assert_eq(world.hud._message.text, "%s the gunner joins the crew." % gunner["name"])
	ledger.hire("engineer")
	assert_eq(ship.hands.size(), 2)
	assert_eq(ship.hands[1]["post"], Vector3i(0, -1, -5), "at the engine")
	ledger.hire("repairer")
	assert_eq(world.hud._message.text, "She has no free bunk.")
	assert_eq(ship.hands.size(), 2)
	assert_eq(ledger.mine["money"], 1150)


func test_a_gunner_fires_at_pirates_abeam() -> void:
	await start()
	to_open_sky()
	sync.set_hands(ship, [hand(ship, -1, "gunner", STARBOARD)])
	var cannon := cannon_at(ship, STARBOARD)
	assert_eq(cannon.gunner, -1, "he mans the starboard cannon")
	var pirate := sync.add_ship(PirateShip.build(), ship.global_transform.translated(Vector3(300, 0, 0)), 0, false, 0, true)
	pirate.anchored = true
	var blocks := pirate.grid.blocks.size()
	assert_true(await wait_until(func() -> bool: return cannon.reload_left > 0.0, 5.0), "he fires")
	assert_true(await wait_until(func() -> bool: return pirate.grid.blocks.size() < blocks, 8.0), "and hits her")
	var brain: CrewHand = brains(ship)[0]
	for each: Ship in sync.ships.values():
		if each != ship:
			sync.remove_ship(each)
	var astern := sync.add_ship(PirateShip.build(), ship.global_transform.translated(Vector3(0, 0, 300)), 0, false, 0, true)
	astern.anchored = true
	var shots := brain.shots
	await simulate(10.0)
	assert_eq(brain.shots, shots, "a pirate astern is out of his arc")
	sync.remove_ship(astern)
	var friend := sync.add_ship(StarterShip.build(), ship.global_transform.translated(Vector3(300, 0, 0)))
	friend.anchored = true
	await simulate(10.0)
	assert_eq(brain.shots, shots, "he fires at nothing but pirates")


func test_a_repairer_puts_out_fires_then_mends() -> void:
	await start()
	to_open_sky()
	ship.spares = 40
	sync.set_hands(ship, [hand(ship, -1, "repairer")])
	var burning := Vector3i(0, 0, -4)
	var damaged := Vector3i(2, 0, -1)
	var lost := Vector3i(-2, 0, 0)
	ship.fires[burning] = 0.0
	sync.damage_ship(ship, {damaged: 20, lost: 0})
	var spares_when_out := [-1]
	assert_true(await wait_until(func() -> bool:
		if ship.fires.is_empty() and spares_when_out[0] < 0:
			spares_when_out[0] = ship.spares
		return ship.fires.is_empty(), 10.0), "the fire's out")
	assert_eq(spares_when_out[0], 40, "putting out fires takes no spares")
	assert_true(await wait_until(func() -> bool: return hp(damaged) == 80 and hp(lost) == 80, 40.0),
			"the damaged plank is whole (%d) and the lost one back (%d)" % [hp(damaged), hp(lost)])
	assert_true(ship.spares <= 40 - 7, "a spare a mend (%d left)" % ship.spares)
	ship.spares = 0
	sync.damage_ship(ship, {damaged: 20})
	ship.fires[Vector3i(0, 0, 5)] = 0.0
	assert_true(await wait_until(func() -> bool: return ship.fires.is_empty(), 10.0), "with no spares a fire still goes out")
	await simulate(2.0)
	assert_eq(hp(damaged), 20, "but nothing is healed")


func test_an_engineer_makes_her_faster() -> void:
	var tended := Ship.new(StarterShip.build())
	var plain := Ship.new(StarterShip.build())
	for each: Ship in [tended, plain]:
		each.calm = true
		each.position = START + (Vector3(300, 0, 0) if each == plain else Vector3.ZERO)
		add_child(each)
		each.throttle = 1.0
	tended.set_hands([{"id": -1, "name": "Fenn", "role": "engineer", "post": Vector3i(0, -1, -5), "at": Vector3(0, 0.45, -5)}])
	assert_eq(tended.tended_engines(), 1)
	await simulate(90.0)
	var faster := tended.linear_velocity.length() / plain.linear_velocity.length()
	assert_true(faster >= 1.08, "%.1f%% faster" % ((faster - 1.0) * 100.0))
	tended.damage({Vector3i(0, -1, -5): 0})
	await get_tree().process_frame
	assert_eq(tended.tended_engines(), 0, "no engine left to tend")


func test_hands_go_down_with_their_ship() -> void:
	await start()
	to_open_sky()
	sync.set_hands(ship, [hand(ship, -1, "gunner", PORT), hand(ship, -2, "repairer", Vector3i.ZERO, "Marta")])
	var minds := brains(ship).map(func(brain: Node) -> WeakRef: return weakref(brain))
	assert_eq(minds.size(), 2, "a gunner's and a repairer's")
	ship.global_position.y = -5.0
	sync._wear()
	assert_eq(sync.id_of(ship), 0, "she's lost")
	await get_tree().process_frame
	for mind: WeakRef in minds:
		assert_eq(mind.get_ref(), null, "and her hands with her")


func test_hands_move_to_the_ship_that_replaces_theirs() -> void:
	await start()
	sync.set_hands(ship, [hand(ship, -1, "gunner", STARBOARD), hand(ship, -2, "repairer", Vector3i.ZERO, "Marta")])
	var old := ship
	world.launch(StarterShip.build())
	assert_true(await wait_until(func() -> bool: return world.ship != old, 1.0), "launched")
	var next: Ship = world.ship
	assert_eq(next.hands.map(func(each: Dictionary) -> int: return each["id"]), [-1, -2], "both aboard")
	assert_eq(next.hands[0]["post"], PORT, "the gunner at her first free cannon")
	assert_eq(cannon_at(next, PORT).gunner, -1)
	assert_eq(brains(next).size(), 2)
	await simulate(1.1)
	var one_bunk := StarterShip.build()
	one_bunk.set_block(Vector3i(0, -1, 3), "frame")
	world.launch(one_bunk)
	assert_true(await wait_until(func() -> bool: return world.ship != next, 1.0), "launched again")
	assert_eq((world.ship as Ship).hands.size(), 1, "one bunk, one hand")
	assert_eq(world.hud._message.text, "Marta stays ashore: she has no room for a repairer.")


func test_dismissing_a_hand() -> void:
	await start()
	ledger.hire("gunner")
	var gunner: Dictionary = ship.hands[0]
	ledger.dismiss(gunner["id"])
	assert_eq(ship.hands, [])
	assert_eq(cannon_at(ship, PORT).gunner, 0, "his cannon is free")
	assert_eq(world.hud._message.text, "%s leaves the crew." % gunner["name"])
	assert_eq(brains(ship), [])


func test_guests_see_the_hands() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var books: Ledger = host_world.ledger
	var ours: Ship = host_world.ship
	books.hire("gunner")
	books.hire("repairer")
	assert_eq(ours.hands.size(), 2)
	var copy: Ship = client_world.sync.ships[host_world.sync.id_of(ours)]
	assert_true(await play_until(func() -> bool: return copy.hands.size() == 2, 1.0), "the guest's copy has them")
	assert_eq(copy.hands.map(func(each: Dictionary) -> String: return each["name"]), ours.hands.map(func(each: Dictionary) -> String: return each["name"]))
	var tags := copy.find_children("*", "Label3D", true, false).map(func(tag: Label3D) -> String: return tag.text)
	for each: Dictionary in ours.hands:
		assert_true(tags.has(each["name"]), "%s is drawn, named" % each["name"])
	var repairer: Dictionary = ours.hands[1]
	var from: Vector3 = repairer["at"]
	host_world.sync.damage_ship(ours, {Vector3i(0, 0, -5): 20})
	assert_true(await play_until(func() -> bool: return (repairer["at"] as Vector3).distance_to(from) > 2.0, 3.0), "the repairer walks")
	assert_true(await play_until(func() -> bool: return (copy.hands[1]["at"] as Vector3).distance_to(repairer["at"]) < 1.0, 1.0),
			"and the guest sees where he is")


func test_the_server_ignores_junk_hiring() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var books: Ledger = host_world.ledger
	var theirs: Ledger = client_world.ledger
	var ours: Ship = host_world.ship
	var guest := client.multiplayer.get_unique_id()
	books.hire("gunner")
	var hands := ours.hands.duplicate(true)
	var money: int = books.account_of(guest)["money"]
	for ask: Variant in ["captain", 3]:
		theirs._hire.rpc_id(1, ask)
		await play(0.12)
	books.account_of(guest)["money"] = 0
	theirs._hire.rpc_id(1, "repairer")
	await play(0.12)
	books.account_of(guest)["money"] = money
	theirs._dismiss.rpc_id(1, -99)
	await play(0.12)
	client_world.go_ashore()
	var guest_player: PlayerController = client_world.player
	guest_player.crew.position = ours.global_position + Vector3(0, 0, 3000)
	guest_player.crew.velocity = Vector3.ZERO
	await play(0.3)
	theirs._hire.rpc_id(1, "repairer")
	await play(0.12)
	theirs._dismiss.rpc_id(1, hands[0]["id"])
	await play(0.3)
	assert_eq(ours.hands, hands, "her hands are as they were")
	assert_eq(books.account_of(guest)["money"], money, "and the guest's purse")


func test_an_engineer_takes_an() -> void:
	await start()
	ledger.account_of(1)["money"] = 0
	ledger.hire("engineer")
	assert_eq(world.hud._message.text, "You can't afford an engineer (200 crowns).")
	world.open_town()
	(world.town_panel as TownPanel).show_section("crew")
	var texts := (world.town_panel as TownPanel).find_children("*", "Button", true, false).map(func(b: Button) -> String: return b.text)
	assert_true(texts.has("Hire an engineer   200 crowns"), str(texts))
	assert_true(texts.has("Hire a gunner   150 crowns"), str(texts))
