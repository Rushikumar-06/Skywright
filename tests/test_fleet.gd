extends NetCase
## Ships coming and going mid-game (spec §3.8): the dock and its slipways, ships the
## server adds and removes while everyone plays, and who boards which.


func test_the_dock_has_slipways_and_a_reach() -> void:
	var world := solo_world()
	await get_tree().process_frame
	var start: Vector3 = world.START
	assert_eq(Dock.slipway(start, 0), Transform3D(Basis.IDENTITY, start), "slipway 0 is where the starter ship is")
	assert_eq(Dock.slipway(start, 2).origin, start + Vector3(120, 0, 0), "slipway 2 is 120 m to starboard")
	assert_eq(Dock.test_berth(start, 2), Transform3D(Basis.IDENTITY, start + Vector3(120, 0, -90)), "its test berth 90 m ahead")
	var quay := start + Vector3(240, -1.5, 37)
	assert_true(Dock.near(start, quay), "on the quay")
	assert_true(Dock.near(start, start + Vector3(510 + 140, -1.5, 37)), "140 m off its end")
	assert_false(Dock.near(start, quay + Vector3(2000, 0, 0)), "2 km away")
	assert_true(world.towns[0].is_inside_tree(), "the world has its first town's dock")
	assert_eq(world.sync.docks[0], start, "which is where the slipways are")
	var obstacles := Dock.obstacles(start)
	for i in Dock.SLIPWAYS:
		var pier := AABB(start + Vector3(i * Dock.SPACING, 0, 0) + Dock.PIER.position, Dock.PIER.size)
		assert_true(obstacles.has(pier), "the obstacles have a pier beside slipway %d" % i)
	assert_true(obstacles.has(AABB(start + Dock.QUAY.position, Dock.QUAY.size)), "and the quay")
	var island: AABB = obstacles[-1]
	assert_true(island.has_point(start + WorldGen.TOWN_ISLAND + Vector3(0, 30, 0)), "and the town island, up over its beacon")
	assert_true(island.has_point(start + WorldGen.TOWN_ISLAND + Vector3(0, -100, 0)), "down through its rock")
	assert_false(island.has_point(start + WorldGen.TOWN_ISLAND + Vector3(0, 45, 0)), "but not far above it")
	for mesh: MeshInstance3D in world.towns[0].find_children("*", "MeshInstance3D", true, false):
		if mesh.name == "Waterfall":
			continue  # it hangs far below its island, in the open air
		var box := mesh.global_transform * mesh.get_aabb()
		assert_true(obstacles.any(func(obstacle: AABB) -> bool: return obstacle.grow(0.01).encloses(box)), "the obstacles cover %s" % box)


func test_a_ship_added_mid_game_reaches_everyone() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var guest := client.multiplayer.get_unique_id()
	var grid := StarterShip.build()
	grid.paint = {"deck": Color("c0392b"), "balloon": Color("2e86c1")}
	var ours: Ship = host_world.sync.add_ship(grid, Dock.slipway(host_world.START, 1), guest, true)
	var id: int = host_world.sync.id_of(ours)
	assert_true(await wait_until(func() -> bool: return client_world.sync.ships.has(id), 2.0), "the guest gets it")
	var theirs: Ship = client_world.sync.ships[id]
	assert_eq(theirs.grid.blocks.size(), grid.blocks.size(), "every block")
	assert_eq(theirs.grid.paint_names(), {"deck": "c0392b", "balloon": "2e86c1"}, "the paint")
	assert_eq(theirs.captain, guest, "the captain")
	assert_true(theirs.test, "a test flight")
	assert_true(theirs.freeze and theirs.freeze_mode == RigidBody3D.FREEZE_MODE_KINEMATIC, "it just follows")
	assert_true(theirs.global_position.distance_to(ours.global_position) < 1.0, "where the host has it")
	assert_eq(client_world.ship, theirs, "as its captain, the guest boards it")
	assert_eq(client_world.player.crew.get_parent(), theirs.interior)
	assert_eq(host_world.ship, host_world.sync.ships[1], "the host stays aboard the starter")


func test_removing_a_ship_moves_its_crew_to_the_successor() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var guest := client.multiplayer.get_unique_id()
	var sync: WorldSync = host_world.sync
	var starter: Ship = host_world.ship
	var starter_id := sync.id_of(starter)
	var b := sync.add_ship(StarterShip.build(), Dock.slipway(host_world.START, 1))
	var b_id := sync.id_of(b)
	assert_true(await wait_until(func() -> bool: return client_world.sync.ships.has(b_id), 2.0), "the guest has B")
	assert_true(await play_until(func() -> bool: return sync.avatar_of(guest) != null, 2.0), "the host sees the guest")
	# A crew report for the starter, still on its way when the starter goes.
	client_world.sync._crew_report.rpc_id(1, starter_id, Vector3(0, 1.45, 0), Vector3.ZERO, 0.0, 0.0)
	sync.remove_ship(starter, b)
	assert_eq(host_world.ship, b, "the host boards B")
	assert_eq(host_world.player.crew.get_parent(), b.interior)
	assert_eq(host_world.player.ship, b)
	assert_false(sync.ships.has(starter_id), "the starter is gone")
	assert_true(sync.avatar_of(guest) == null, "and the guest's avatar with it")
	assert_true(await wait_until(func() -> bool: return client_world.ship == client_world.sync.ships.get(b_id), 2.0), "the guest boards B")
	assert_eq(client_world.player.crew.get_parent(), (client_world.ship as Ship).interior)
	assert_false(client_world.sync.ships.has(starter_id), "the starter is gone for the guest too")
	assert_true(await play_until(func() -> bool: return sync.avatar_of(guest) != null and sync._crew[guest]["ship"] == b_id, 1.0),
			"the guest reappears on the host, on B")
	await play(0.2)
	assert_false(is_instance_valid(starter), "freed")


func test_a_ship_removed_with_no_successor_sends_you_back() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var sync: WorldSync = host_world.sync
	var starter: Ship = host_world.ship
	var b := sync.add_ship(StarterShip.build(), Dock.slipway(host_world.START, 1))
	host_world.board(b)
	assert_eq(host_world.ship, b, "the host boards B")
	var b_id := sync.id_of(b)
	assert_true(await wait_until(func() -> bool: return client_world.sync.ships.has(b_id), 2.0), "the guest has B")
	sync.remove_ship(b)
	assert_eq(host_world.ship, starter, "and is back aboard the starter")
	assert_eq(host_world.player.crew.get_parent(), starter.interior)
	await play(0.3)
	assert_false(client_world.sync.ships.has(b_id), "B is gone for the guest")
	assert_eq(client_world.player.crew.get_parent(), (client_world.ship as Ship).interior, "who stayed aboard the starter")


func test_a_late_joiner_boards_the_hosts_ship() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var sync: WorldSync = host_world.sync
	var starter: Ship = host_world.ship
	sync.add_ship(StarterShip.build(), Dock.slipway(host_world.START, 1), client.multiplayer.get_unique_id())
	var flagship := sync.add_ship(StarterShip.build(), Dock.slipway(host_world.START, 2), 1)
	sync.remove_ship(starter, flagship)
	var late := make_session("Late")
	late.join("Cy", "127.0.0.1", host.port)
	assert_true(await wait_until(func() -> bool: return late.sailing, 5.0), "Cy joins")
	var late_world := add_world(late)
	assert_true(await wait_until(func() -> bool: return late_world.ship != null, 5.0), "and boards")
	assert_eq(late_world.sync.ships.size(), 2, "the guest's ship and the host's")
	assert_eq(late_world.sync.id_of(late_world.ship), sync.id_of(flagship), "the host's ship, not the guest's")
	assert_eq(late_world.player.crew.get_parent(), (late_world.ship as Ship).interior)


func test_the_client_skips_ships_that_make_no_sense() -> void:
	assert_true(SessionScript.PROTOCOL_VERSION >= 3, "entries of 7 fields came with protocol 3")
	assert_true(await sail_together(), "the ship arrives")
	var sync: WorldSync = host_world.sync
	var guest := client.multiplayer.get_unique_id()
	var blocks := StarterShip.build().to_bytes()
	var at := Transform3D(Basis.IDENTITY, host_world.START + Vector3(60, 0, 0))
	var junk := [
		"ship", [50], [51, blocks, {}, at, 0, 0], ["52", blocks, {}, at, 0, 0, false],
		[53, PackedByteArray([1, 2, 3]), {}, at, 0, 0, false], [54, StarterShip.build().to_blocks(), {}, at, 0, 0, false],
		[55, blocks, {"deck": "nope"}, at, 0, 0, false], [56, blocks, [], at, 0, 0, false],
		[57, blocks, {}, Transform3D(Basis.IDENTITY, Vector3(NAN, 0, 0)), 0, 0, false], [58, blocks, {}, "here", 0, 0, false],
		[59, blocks, {}, at, "1", 0, false], [60, blocks, {}, at, 0, 0.5, false], [61, blocks, {}, at, 0, 0, "yes"],
		[62, blocks, {}, Transform3D(Basis(Vector3.RIGHT, Vector3.RIGHT, Vector3.BACK), at.origin), 0, 0, false],
		[0, blocks, {}, at, 0, 0, false], [1, blocks, {}, at, 0, 0, false],
	]
	for entry: Variant in junk:
		sync._ship_added.rpc_id(guest, sync.now(), entry)
	sync._ship_added.rpc_id(guest, "now", [63, blocks, {}, at, 0, 0, false])
	sync._world.rpc_id(guest, sync.now(), junk)
	sync._ship_removed.rpc_id(guest, "1", 0)
	sync._ship_removed.rpc_id(guest, 1, "0")
	sync._ship_removed.rpc_id(guest, 99, 0)
	await play(0.3)
	assert_eq(client_world.sync.ships.keys(), [1], "none of that was taken")
	sync._ship_added.rpc_id(guest, sync.now(), [70, blocks, {"deck": "c0392b"}, at, 0, 0, false])
	assert_true(await wait_until(func() -> bool: return client_world.sync.ships.has(70), 2.0), "a sensible ship is")
