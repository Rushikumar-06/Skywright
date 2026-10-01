extends NetCase
## Damage over the network (spec §4.6): the server decides, and every machine
## applies the same changes to its copy of the ship.


func test_losing_the_helm_lets_the_pilot_go() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var ours: Ship = host_world.ship
	var theirs: Ship = client_world.ship
	ours.anchored = true
	await play(0.2)  # where the guest stands reaches the host
	press(client_world.player, "interact")
	assert_true(await wait_until(func() -> bool: return client_world.player.crew.station == theirs.helm, 2.0), "the guest takes the helm")
	host_world.sync.damage_ship(ours, {ours.helm.cell: 0})
	assert_true(await play_until(func() -> bool: return ours.helm == null and theirs.helm == null, 1.0), "the helm is gone on both machines")
	assert_true(ours.is_wreck() and theirs.is_wreck(), "a wreck on both")
	assert_eq(client_world.player.crew.station, null, "the guest is let go")
	await get_tree().process_frame
	assert_false(client_world.hud._helm.visible, "and sees no helm panel")
	assert_false(ours.anchored, "a wreck drifts")


func test_damage_reaches_the_guest() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var ours: Ship = host_world.ship
	var theirs: Ship = client_world.ship
	var gone: Array[Vector3i] = [Vector3i(2, 1, 0), Vector3i(-2, 1, 0), Vector3i(0, 0, -6)]
	var hit := Vector3i(1, 0, 1)
	var changes := {hit: 10}
	for cell in gone:
		changes[cell] = 0
	host_world.sync.damage_ship(ours, changes)
	assert_true(await play_until(func() -> bool: return theirs.grid.blocks[hit]["hp"] == 10, 1.0), "the hit reaches the guest")
	for cell in gone:
		assert_false(theirs.grid.blocks.has(cell), "%s is gone" % cell)
	await get_tree().process_frame
	assert_eq(theirs.mass, ours.mass, "and her mass is the host's")


func test_a_late_joiner_gets_the_damage_and_the_blueprint() -> void:
	host = make_session("Host")
	var port := free_port()
	host.host("Ann", port)
	host.set_sail()
	host_world = add_world(host)
	await get_tree().process_frame
	var ours: Ship = host_world.ship
	host_world.sync.damage_ship(ours, {Vector3i(2, 1, 0): 0, Vector3i(1, 0, 1): 10})
	var late := make_session("Late")
	late.join("Bob", "127.0.0.1", port)
	assert_true(await wait_until(func() -> bool: return late.sailing, 5.0), "straight to the world")
	var late_world := add_world(late)
	assert_true(await wait_until(func() -> bool: return late_world.ship != null, 5.0), "the ship arrives")
	var theirs: Ship = late_world.ship
	assert_eq(theirs.grid.blocks, ours.grid.blocks, "damaged as the host's is")
	assert_eq(theirs.blueprint.blocks, StarterShip.build().blocks, "with the whole starter ship for a blueprint")


func test_a_junk_change_list_is_refused() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var sync: WorldSync = client_world.sync
	var ship: Ship = client_world.ship
	var id := sync.id_of(ship)
	var before: Dictionary = ship.grid.blocks.duplicate(true)
	var too_many := PackedByteArray()
	too_many.resize(2 + 4001 * Damage.BYTES_PER_CHANGE)
	too_many.encode_u16(0, 4001)
	var far_out := Damage.pack({Vector3i(0, 0, 1): 0})
	far_out[2] = 100 - ShipGrid.MIN_CELL
	sync._blocks_changed(99, Damage.pack({Vector3i(0, 0, 1): 0}))
	sync._blocks_changed(str(id), Damage.pack({Vector3i(0, 0, 1): 0}))
	sync._blocks_changed(id, PackedByteArray([1, 2, 3]))
	sync._blocks_changed(id, too_many)
	sync._blocks_changed(id, far_out)
	sync._blocks_changed(id, {Vector3i(0, 0, 1): 0})
	await get_tree().process_frame
	assert_eq(ship.grid.blocks, before, "nothing changed")
