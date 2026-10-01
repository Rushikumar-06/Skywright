extends NetCase
## Repairs, spares and fires (spec §3.4, §3.5): holding R aimed at a block heals it,
## or rebuilds a lost block beside it from the blueprint, or puts out a fire, once
## every Damage.REPAIR_EVERY. Repairs use spares, which any town's dock fills. Shells
## start fires, which burn and spread through wood until someone puts them out.

const PLANK := Vector3i(0, 0, 1)      ## A deck plank in the middle of the deck.
const STARBOARD := Vector3i(2, 1, 1)  ## The starboard cannon.
const AT := Vector3(0, 1900, 7000)    ## Above every island.

var world: Node3D
var sync: WorldSync
var ship: Ship
var player: PlayerController


func after_each() -> void:
	Input.action_release("repair")
	super()


## A solo world with your ship calm and anchored: in open sky, 3 km and more from
## every dock, unless at_dock.
func start(at_dock := false) -> void:
	world = solo_world()
	await get_tree().process_frame
	sync = world.sync
	ship = world.ship
	ship.calm = true
	ship.anchored = true
	if not at_dock:
		ship.global_position = open_sky(world, 1000.0)
	player = world.player


## Stands you on top of cell (ship space), looking straight down at it.
func stand_over(cell: Vector3i) -> void:
	player.crew.position = Vector3(cell) + Vector3(0, 1.4, 0)
	player.crew.look_yaw = 0.0
	player.look_pitch = -PI / 2.0


## One repair action at what you aim at, as holding R gives, then the wait before the next.
func repair_once() -> void:
	var aimed := player.aimed_block()
	assert_false(aimed.is_empty(), "aimed at a block")
	if not aimed.is_empty():
		player.repairing.emit(aimed["cell"])
	await simulate(Damage.REPAIR_EVERY)


func hp(cell: Vector3i, of: Ship = null) -> int:
	var on := of if of != null else ship
	return on.grid.blocks[cell]["hp"] if on.grid.blocks.has(cell) else -1


## Fires a shell from cell of from at the world point target.
func shell_at(in_sync: WorldSync, from: Ship, cell: Vector3i, target: Vector3) -> int:
	var muzzle := from.global_transform * Vector3(cell)
	var direction := Projectiles.aim(target - muzzle, Damage.AMMO["shell"]["speed"])
	return in_sync.fire(from, cell, from.global_basis.inverse() * direction, "shell")


func test_repairing_heals_a_block_and_uses_a_spare() -> void:
	await start()
	sync.damage_ship(ship, {PLANK: 20})
	stand_over(PLANK)
	assert_eq(player.aimed_block(), {"cell": PLANK}, "looking at the plank")
	var seen: Array[int] = []
	Input.action_press("repair")
	await simulate(1.1, func(_tick: int) -> void:
		if seen.is_empty() or seen[-1] != hp(PLANK):
			seen.append(hp(PLANK)))
	assert_eq(seen.slice(1), [45, 70, 80] as Array[int], "healed in steps")
	assert_eq(ship.spares, Damage.SPARES_MAX - 3, "three spares used")
	await simulate(1.0)
	assert_eq(ship.spares, Damage.SPARES_MAX - 3, "holding on at a whole plank uses no more")


func test_rebuilding_lost_blocks_from_the_blueprint() -> void:
	await start()
	var neighbour := PLANK + Vector3i.RIGHT
	var rotation: int = ship.blueprint.blocks[PLANK]["rotation"]
	sync.damage_ship(ship, {PLANK: 0})
	await get_tree().process_frame
	assert_eq(ship.grid.type_at(PLANK), "", "the plank is gone")
	stand_over(neighbour)
	await repair_once()
	assert_eq(ship.grid.type_at(PLANK), "deck", "it comes back")
	assert_eq(ship.grid.blocks[PLANK]["rotation"], rotation, "turned as the blueprint has it")
	assert_eq(hp(PLANK), Damage.REPAIR_STEP, "at 25")
	stand_over(PLANK)
	for i in 3:
		await repair_once()
	assert_eq(hp(PLANK), 80, "and heals whole")


func test_patching_the_envelope() -> void:
	await start()
	var whole := ship.trim_to_float_at(880.0)
	var holes: Array[Vector3i] = [Vector3i(2, 9, -1), Vector3i(2, 9, 0), Vector3i(2, 9, 1)]
	var changes := {}
	for cell in holes:
		changes[cell] = 0
	sync.damage_ship(ship, changes)
	await get_tree().process_frame
	assert_true(ship.trim_to_float_at(880.0) > whole, "she needs more trim with holes in her envelope")
	player.crew.position = Vector3(1, 1.4, 0)
	player.look_pitch = PI / 2.0  # straight up, at (1, 8, 0), 5.4 m away
	assert_eq(player.aimed_block(), {"cell": Vector3i(1, 8, 0)}, "looking at the envelope's underside")
	await repair_once()
	assert_eq(ship.grid.type_at(Vector3i(2, 9, 0)), "balloon", "the nearest hole first")
	assert_eq(ship.grid.type_at(Vector3i(2, 9, -1)), "", "one at a time")
	await repair_once()
	assert_eq(ship.grid.type_at(Vector3i(2, 9, -1)), "balloon", "then the next, in cell order")
	await repair_once()
	assert_eq(ship.grid.type_at(Vector3i(2, 9, 1)), "balloon", "then the last")
	await get_tree().process_frame
	assert_near(ship.trim_to_float_at(880.0), whole, 0.0001, "she floats as she did")


func test_helms_and_cannons_need_a_shipyard() -> void:
	await start()
	var plank := Vector3i(1, 0, 0)
	sync.damage_ship(ship, {STARBOARD: 0, plank: 0})
	await get_tree().process_frame
	stand_over(Vector3i(1, 0, 1))  # the deck plank by both, touching the cannon at an edge
	for i in 4:
		await repair_once()
	assert_eq(ship.grid.type_at(plank), "deck", "the plank comes back")
	assert_eq(ship.grid.type_at(STARBOARD), "", "the cannon stays lost")
	assert_eq(ship.spares, Damage.SPARES_MAX - 1, "and only the plank used a spare")


func test_out_of_spares() -> void:
	await start()
	ship.spares = 0
	sync.damage_ship(ship, {PLANK: 20})
	stand_over(PLANK)
	await get_tree().process_frame
	assert_eq(world.hud._prompt.text, "No spares left: refill at a town's dock")
	await repair_once()
	assert_eq(hp(PLANK), 20, "nothing changes")
	ship.spares = 1
	await repair_once()
	assert_eq(hp(PLANK), 45, "with a spare it heals")
	assert_eq(ship.spares, 0)


func test_the_prompts_say_what_r_does() -> void:
	await start()
	stand_over(PLANK)
	await get_tree().process_frame
	assert_eq(world.hud._prompt.text, "", "nothing to do at a whole plank")
	sync.damage_ship(ship, {PLANK: 20})
	await get_tree().process_frame
	assert_eq(world.hud._prompt.text, "Hold R   Repair  20/80")
	sync.damage_ship(ship, {PLANK: 80, PLANK + Vector3i.RIGHT: 0})
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(world.hud._prompt.text, "Hold R   Rebuild")
	ship.fires[PLANK + Vector3i.LEFT] = 0.0
	ship.show_fires([PLANK + Vector3i.LEFT])
	await get_tree().process_frame
	assert_eq(world.hud._prompt.text, "Hold R   Put out the fire")


func test_spares_refill_at_a_dock() -> void:
	await start(true)
	ship.spares = 5
	await simulate(1.5)
	assert_eq(ship.spares, Damage.SPARES_MAX, "full at the dock")
	ship.global_position = open_sky(world, 1000.0)
	ship.spares = 5
	await simulate(1.5)
	assert_eq(ship.spares, 5, "not 3 km away")


func test_fire_spreads_and_can_be_put_out() -> void:
	await start()
	sync.rng.seed = 1
	ship.fires[PLANK] = 0.0
	for i in 3:
		sync._wear()
	assert_eq(hp(PLANK), 80 - 3 * Damage.FIRE_DAMAGE, "15 down after 3 s")
	assert_true(ship.fires.size() >= 1 and ship.fires.has(PLANK), "still burning (%d fires)" % ship.fires.size())
	assert_eq(ship.burning.size(), ship.fires.size(), "and drawn")
	stand_over(PLANK)
	await repair_once()
	for fire: Vector3i in ship.fires:
		assert_true(maxi(maxi(absi(fire.x - PLANK.x), absi(fire.y - PLANK.y)), absi(fire.z - PLANK.z)) > 1, "%s is out" % fire)
	assert_eq(hp(PLANK), 65, "putting it out heals nothing")
	assert_eq(ship.spares, Damage.SPARES_MAX, "and costs nothing")
	await repair_once()
	assert_eq(hp(PLANK), 80, "the next repair heals it")


func test_a_shell_can_start_a_fire() -> void:
	await start()
	sync.rng.seed = 1
	ship.global_position = AT
	var target := sync.add_ship(StarterShip.build(), ship.global_transform.translated(Vector3(150, 0, 0)))
	target.calm = true
	target.anchored = true
	for i in 5:
		shell_at(sync, ship, STARBOARD, target.global_transform * Vector3(-1, 0.5, -1 + i))
	await simulate(4.0)
	assert_false(target.fires.is_empty(), "something on her is burning")
	assert_eq(target.burning.size(), target.fires.size(), "and it's drawn")


func test_the_server_ignores_repairs_out_of_reach() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var host_sync: WorldSync = host_world.sync
	var guest_sync: WorldSync = client_world.sync
	var ours: Ship = host_world.ship
	ours.anchored = true
	ours.global_position = open_sky(host_world, 1000.0)
	var other := host_sync.add_ship(StarterShip.build(), ours.global_transform.translated(Vector3(40, 0, 0)))
	other.anchored = true
	var id := host_sync.id_of(ours)
	var near := Vector3i(-1, 0, 1)
	var far := Vector3i(0, 10, 6)  # the envelope's top at the stern, 10 m off
	host_sync.damage_ship(ours, {near: 20, far: 10})
	host_sync.damage_ship(other, {near: 20})
	var guest: PlayerController = client_world.player
	guest.crew.position = Vector3(-1, 1.4, 1)
	await play(0.3)  # where the guest stands reaches the host
	guest_sync._repair.rpc_id(1, id, far)
	guest_sync._repair.rpc_id(1, host_sync.id_of(other), near)
	await play(0.3)
	assert_eq(hp(far, ours), 10, "too far to reach")
	assert_eq(hp(near, other), 20, "not the ship they're aboard")
	guest_sync._repair.rpc_id(1, id, near)
	guest_sync._repair.rpc_id(1, id, near)
	await play(0.3)
	assert_eq(hp(near, ours), 45, "one repair, not two within 0.1 s")
	assert_eq(ours.spares, Damage.SPARES_MAX - 1, "one spare")


func test_fires_and_spares_reach_the_guest() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var host_sync: WorldSync = host_world.sync
	var ours: Ship = host_world.ship
	var theirs: Ship = client_world.ship
	ours.anchored = true
	ours.global_position = open_sky(host_world, 1000.0)
	ours.fires[PLANK] = 0.0
	var fix := Vector3i(1, 0, -4)
	host_sync.damage_ship(ours, {fix: 20})
	host_world.player.crew.position = Vector3(1, 1.4, -4)
	host_sync.repair(ours, fix)
	assert_eq(ours.spares, Damage.SPARES_MAX - 1, "the host's repair used a spare")
	assert_true(await play_until(func() -> bool: return theirs.spares == ours.spares and not theirs.burning.is_empty() \
			and theirs.burning == ours.burning, 1.5), "the guest has the fires and spares within 1.5 s")
