extends NetCase
## Salvage (spec §3.5): E by a world wreck strips her of Economy.SALVAGE_MONEY crowns
## and Damage.SALVAGE_SPARES spares, once (the world remembers), and E by a broken-off
## wreck breaks her up for one spare per 10 blocks and a crown a block. The spares go to
## the ship you're aboard, else your own, else the home ship, as many as fit. The
## server checks you're in reach.

var world: Node3D
var sync: WorldSync
var ship: Ship
var player: PlayerController


## A solo world with your ship anchored in open sky, far from every dock, with 10 spares.
func start() -> void:
	world = solo_world()
	await get_tree().process_frame
	sync = world.sync
	ship = world.ship
	ship.anchored = true
	ship.global_position = open_sky(world, 1000.0)
	ship.spares = 10
	player = world.player


## Steps you off your ship and puts you, still, at p in the world.
func ashore_at(p: Vector3) -> void:
	world.go_ashore()
	player.crew.position = p
	player.crew.velocity = Vector3.ZERO
	player.crew.reset_physics_interpolation()


## A small wreck, nobody's: a 3 × 3 deck with no helm, held still at at.
func small_wreck(in_sync: WorldSync, at: Vector3) -> Ship:
	var grid := ShipGrid.new()
	for x in range(-1, 2):
		for z in range(-1, 2):
			grid.set_block(Vector3i(x, 0, z), "deck")
	var wreck := in_sync.add_ship(grid, Transform3D(Basis.IDENTITY, at))
	wreck.anchored = true
	return wreck


func test_salvaging_a_wreck_site() -> void:
	await start()
	ashore_at(Sites.wreck_center(world.gen.wrecks[0]))
	await get_tree().process_frame
	assert_eq(world.salvage_in_reach(), ["site", 0])
	assert_eq(world.hud._prompt.text, "E   Salvage")
	press(player, "interact")
	assert_eq(ship.spares, 22, "12 spares to your ship")
	assert_eq(world.hud._message.text, "Salvaged 150 crowns and 12 spares.")
	assert_true(sync.salvaged.has(0), "the wreck is stripped")
	sync.salvage_site(0)  # as a second salvager would, at the same moment
	assert_eq(world.hud._message.text, "Nothing left to salvage here.")
	assert_eq(ship.spares, 22, "nothing more")
	await get_tree().process_frame
	assert_true(world.salvage_in_reach().is_empty(), "nothing in reach")
	assert_true(world.hud._prompt.text != "E   Salvage", "and no prompt (%s)" % world.hud._prompt.text)


func test_salvaging_a_broken_off_section() -> void:
	await start()
	var cut := {}
	for cell: Vector3i in ship.grid.blocks:
		if cell.z == -3:
			cut[cell] = 0
	sync.damage_ship(ship, cut)
	var wrecks := sync.ships.values().filter(func(each: Ship) -> bool: return each.is_wreck() and each.captain == 0)
	assert_eq(wrecks.size(), 1, "the bow broke off")
	if wrecks.size() != 1:
		return
	var bow: Ship = wrecks[0]
	bow.anchored = true
	var blocks := bow.grid.blocks.size()
	world.come_aboard(bow, bow.crew_spawn())
	assert_eq(world.salvage_in_reach(), ["ship", bow])
	press(player, "interact")
	assert_eq(ship.spares, 10 + ceili(blocks / 10.0), "her blocks' worth of spares to your ship")
	assert_eq(sync.id_of(bow), 0, "and she's broken up")


func test_salvage_goes_to_the_ship_you_are_aboard() -> void:
	await start()
	var other := sync.add_ship(StarterShip.build(), ship.global_transform.translated(Vector3(60, 0, 0)))
	other.anchored = true
	other.spares = 0
	world.come_aboard(other, Vector3(0, 1.4, 0))  # mid-deck, away from her helm and guns
	var wreck := small_wreck(sync, player.world_position() + Vector3(0, 4, 0))
	assert_eq(world.salvage_in_reach(), ["ship", wreck])
	press(player, "interact")
	assert_eq(other.spares, 1, "the spare goes to the ship you're aboard")
	assert_eq(ship.spares, 10, "not your own")


func test_a_full_ship_still_takes_the_crowns() -> void:
	await start()
	ship.spares = Damage.SPARES_MAX - 2
	ashore_at(Sites.wreck_center(world.gen.wrecks[0]))
	press(player, "interact")
	assert_eq(world.hud._message.text, "Salvaged 150 crowns and 2 spares.")
	assert_eq(ship.spares, Damage.SPARES_MAX, "as many spares as fit")
	assert_true(sync.salvaged.has(0), "the wreck is stripped all the same")


func test_the_world_remembers_what_was_salvaged() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var ours: Ship = host_world.ship
	ours.anchored = true
	ours.global_position = open_sky(host_world, 1000.0)
	ours.spares = 10
	var guest: PlayerController = client_world.player
	client_world.go_ashore()
	guest.crew.position = Sites.wreck_center(client_world.gen.wrecks[0])
	guest.crew.velocity = Vector3.ZERO
	await play(0.3)  # where the guest is reaches the host
	press(guest, "interact")
	var guest_sync: WorldSync = client_world.sync
	assert_true(await play_until(func() -> bool: return host_world.sync.salvaged.has(0) and guest_sync.salvaged.has(0), 1.0), "both know site 0 is stripped")
	assert_eq(ours.spares, 22, "the spares went to the home ship")
	assert_eq(client_world.hud._message.text, "Salvaged 150 crowns and 12 spares.")
	assert_eq(client_world.ledger.mine["money"], 1650, "the crowns went to the guest")
	await play(0.1)
	assert_true(client_world.hud._prompt.text != "E   Salvage", "the guest's prompt is gone")
	var late := make_session("Late")
	late.join("Bob", "127.0.0.1", host.port)
	assert_true(await play_until(func() -> bool: return late.sailing, 5.0), "a late joiner")
	var late_world := add_world(late)
	assert_true(await play_until(func() -> bool: return late_world.ship != null, 5.0), "gets the world")
	assert_true(late_world.sync.salvaged.has(0), "with site 0 stripped")


func test_the_server_ignores_salvage_from_afar() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var host_sync: WorldSync = host_world.sync
	var ours: Ship = host_world.ship
	ours.anchored = true
	ours.global_position = open_sky(host_world, 1000.0)
	ours.spares = 10
	var far_wreck := small_wreck(host_sync, ours.global_position + Vector3(0, 0, 900))
	await play(0.3)
	var count := host_sync.ships.size()
	var guest_sync: WorldSync = client_world.sync
	for ask: Array in [["site", 0], ["site", 99], ["site", -1], ["ship", 12345], ["ship", host_sync.id_of(ours)],
			["ship", host_sync.id_of(far_wreck)], ["junk", 0], ["site", "0"], [3, 0]]:
		guest_sync._salvage.rpc_id(1, ask[0], ask[1])
	await play(0.3)
	assert_true(host_sync.salvaged.is_empty(), "no site stripped")
	assert_eq(host_sync.ships.size(), count, "no ship broken up")
	assert_eq(ours.spares, 10, "no spares gained")
