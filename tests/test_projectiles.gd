extends NetCase
## Shots and ropes (spec §3.5, §4.6): every machine flies a shot from its launch
## data, the server alone decides what it hits, shells knock crew down, harpoons tie
## ships together, and a knocked-down player always comes to somewhere.

const AT := Vector3(0, 1900, 7000)  ## Above every island.

var world: Node3D
var sync: WorldSync
var ship: Ship


## A solo world with your ship calm at AT, anchored unless anchor is off. Afloat,
## she's in open sky at 880 m instead, where she floats, so she doesn't sink.
func start(anchor := true, afloat := false) -> void:
	world = solo_world()
	await get_tree().process_frame
	sync = world.sync
	ship = world.ship
	ship.calm = true
	ship.anchored = anchor
	ship.global_position = open_sky(world, 880.0) if afloat else AT


## A second ship, nobody's, calm, at on's place moved by offset.
func add_target(in_sync: WorldSync, on: Ship, offset: Vector3, grid := StarterShip.build(), anchor := true) -> Ship:
	var target := in_sync.add_ship(grid, on.global_transform.translated(offset))
	target.calm = true
	target.anchored = anchor
	return target


## The ship-space direction that sends ammo from cell of from to the world point
## target, allowing for the muzzle.
func aim_from(from: Ship, cell: Vector3i, target: Vector3, ammo: String) -> Vector3:
	var speed: float = Damage.AMMO[ammo]["speed"]
	var start_at := from.global_transform * Vector3(cell)
	var direction := Projectiles.aim(target - start_at, speed)
	for i in 3:  # the shot leaves from the muzzle, which moves as the aim does
		start_at = from.global_transform * (Vector3(cell) + direction * WorldSync.MUZZLE)
		direction = Projectiles.aim(target - start_at, speed)
	return from.global_basis.inverse() * direction


## Fires ammo from from's cell at the centre of on's cell, and returns the shot's id.
func fire_at(in_sync: WorldSync, from: Ship, cell: Vector3i, on: Ship, target: Vector3i, ammo: String) -> int:
	return in_sync.fire(from, cell, aim_from(from, cell, on.global_transform * Vector3(target), ammo), ammo)


## The cells of on whose hit points differ from the whole starter ship's (and
## extra's), gone ones included.
static func changed(on: Ship, extra := {}) -> Array[Vector3i]:
	var whole := StarterShip.build()
	for cell: Vector3i in extra:
		whole.set_block(cell, extra[cell])
	var found: Array[Vector3i] = []
	for cell: Vector3i in whole.blocks:
		if not on.grid.blocks.has(cell) or on.grid.blocks[cell]["hp"] != whole.blocks[cell]["hp"]:
			found.append(cell)
	return found


## Runs physics a tick at a time until condition holds, for at most seconds.
func simulate_until(condition: Callable, seconds: float) -> bool:
	for tick in roundi(seconds * Engine.physics_ticks_per_second):
		if condition.call():
			return true
		await simulate(1.0 / Engine.physics_ticks_per_second)
	return condition.call()


func test_a_shot_follows_its_arc() -> void:
	var p := Projectiles.position_at(Vector3.ZERO, Vector3(0, 0, -100), 2.0)
	assert_true(p.distance_to(Vector3(0, -19.62, -200)) <= 0.001, "two seconds out (%s)" % p)
	var origin := Vector3(1, 2, 3)
	var velocity := Vector3(30, 40, -10)
	var points := Projectiles.arc(origin, velocity, 4.0, 8)
	assert_eq(points.size(), 9, "steps + 1 points")
	assert_eq(points[0], origin, "from the origin")
	assert_true(points[8].distance_to(Projectiles.position_at(origin, velocity, 4.0)) <= 0.001, "to where it is after the seconds")
	assert_true(points[4].distance_to(Projectiles.position_at(origin, velocity, 2.0)) <= 0.001, "evenly in time")


func test_aim_finds_the_low_arc() -> void:
	for offset: Vector3 in [Vector3(300, 20, 0), Vector3(0, -50, 400), Vector3(150, 0, 150), Vector3(0, -50, 0)]:
		var direction := Projectiles.aim(offset, 120.0)
		assert_near(direction.length(), 1.0, 0.001, "a unit direction to %s" % offset)
		var points := Projectiles.arc(Vector3.ZERO, direction * 120.0, 10.0, 20000)
		var nearest := INF
		for point in points:
			nearest = minf(nearest, point.distance_to(offset))
		assert_true(nearest <= 0.5, "the arc passes %s (%.2f m off)" % [offset, nearest])
		var elevation := rad_to_deg(asin(clampf(direction.y, -1.0, 1.0)))
		assert_true(elevation < 45.0, "the low arc to %s (%.1f°)" % [offset, elevation])
	assert_eq(Projectiles.aim(Vector3(3000, 0, 0), 120.0), Vector3.ZERO, "out of reach")
	assert_eq(Projectiles.aim(Vector3(0, -50, 0), 120.0), Vector3.DOWN, "straight down")


func test_a_shot_hits_the_block_it_flies_into() -> void:
	await start()
	var target := add_target(sync, ship, Vector3(150, 0, 0))
	var id := fire_at(sync, ship, Vector3i(2, 1, 1), target, Vector3i(-2, 0, 0), "round")
	assert_eq(id, 1, "the first shot")
	assert_true(await simulate_until(func() -> bool: return not target.grid.blocks.has(Vector3i(-2, 0, 0)), 3.0), "the block it flew into is gone")
	var cells := changed(target)
	assert_false(cells.is_empty(), "the target was hit")
	assert_true(cells.all(func(cell: Vector3i) -> bool: return cell.x <= 0 and cell.y == 0), "only the deck it flew along (%s)" % [cells])
	assert_true(changed(ship).is_empty(), "the firing ship is untouched")
	assert_false(world.projectiles.shots.has(id), "the shot ended")


func test_a_cannon_never_hits_its_own_ship() -> void:
	await start()
	var id := sync.fire(ship, Vector3i(0, 0, 0), Vector3.UP, "round")
	await simulate(1.0)
	assert_true(world.projectiles.shots.has(id), "it flies up through the envelope")
	await simulate(19.5)
	assert_true(changed(ship).is_empty(), "every block at full hit points (%s)" % [changed(ship)])
	assert_false(world.projectiles.shots.has(id), "and the shot is gone")


func test_chain_shot_tears_the_envelope() -> void:
	await start()
	var target := add_target(sync, ship, Vector3(150, 0, 0))
	fire_at(sync, ship, Vector3i(2, 1, 1), target, Vector3i(-2, 9, 0), "chain")
	await simulate(3.0)
	var cells := changed(target)
	var torn := cells.filter(func(cell: Vector3i) -> bool: return not target.grid.blocks.has(cell) and StarterShip.build().type_at(cell) == "balloon")
	assert_true(torn.size() >= 3, "balloon cells torn away (%s)" % [torn])
	assert_eq(cells.size(), torn.size(), "and nothing else hurt (%s)" % [cells])


func test_a_shell_bursts_and_knocks_down_crew() -> void:
	await start()
	var grid := StarterShip.build()
	var bunk := Vector3i(1, 1, -3)
	grid.set_block(bunk, "bunk")
	var target := add_target(sync, ship, Vector3(150, 0, 0), grid)
	world.board(target)
	await simulate(0.3)
	var knocks := [0]
	sync.knocked_out.connect(func() -> void: knocks[0] += 1)
	var you: Vector3 = world.player.crew.position
	var aimed := Vector3i(-2, 3, 5)
	assert_near(Vector3(aimed).distance_to(you - Vector3(0, 0.45, 0)), 2.0, 0.1, "aimed at the rail 2 m from you")
	fire_at(sync, ship, Vector3i(2, 1, 1), target, aimed, "shell")
	assert_true(await simulate_until(func() -> bool: return knocks[0] == 1, 3.0), "knocked down")
	var knocked_at := sync.now()
	var cells := changed(target, {bunk: "bunk"})
	assert_true(cells.size() >= 3, "blocks around the burst lost hit points (%s)" % [cells])
	assert_true(cells.has(aimed), "the one it hit among them")
	assert_false(world.player.enabled, "your controls stop")
	assert_eq(world.hud._message.text, "You're hit! Back on your feet in 5 s.")
	assert_false(sync.crew_positions().has(world.multiplayer.get_unique_id()), "you're down on the server")
	var second := sync.fire(ship, Vector3i(2, 1, 1), aim_from(ship, Vector3i(2, 1, 1), world.player.world_position(), "shell"), "shell")
	assert_true(await simulate_until(func() -> bool: return not world.projectiles.shots.has(second), 3.0), "a second shell flies through you")
	assert_eq(knocks[0], 1, "and doesn't knock you down again")
	await simulate(knocked_at + 4.5 - sync.now())
	assert_false(world.player.enabled, "still down after 4.5 s")
	await simulate(1.0)
	assert_true(world.ship == target, "back aboard the ship you were on")
	assert_true(world.player.enabled, "with your controls")
	var crew: CrewMember = world.player.crew
	assert_true(crew.is_on_floor(), "standing")
	assert_true(Vector2(crew.position.x - bunk.x, crew.position.z - bunk.z).length() <= 0.2, "on the bunk (%s)" % crew.position)
	assert_near(crew.position.y, bunk.y + 1.4, 0.1, "on top of it")


func test_a_harpoon_ties_two_ships() -> void:
	await start(false, true)  # or both would sink under the harpoon
	var target := add_target(sync, ship, Vector3(64, 0, 0), StarterShip.build(), false)
	var id := fire_at(sync, ship, Vector3i(2, 1, 1), target, Vector3i(-2, 1, 1), "harpoon")
	assert_true(await simulate_until(func() -> bool: return not world.projectiles.shots.has(id), 2.0), "the harpoon lands")
	var ropes: Dictionary = world.projectiles.ropes
	assert_eq(ropes.size(), 1, "a rope")
	if ropes.is_empty():
		return
	var rope: Dictionary = ropes.values()[0]
	assert_true(rope["a"] == ship and rope["b"] == target, "from the firing ship to the target")
	assert_eq(rope["a_cell"], Vector3i(2, 1, 1), "from the cell it was fired from")
	assert_true(target.grid.blocks.has(rope["b_cell"]) and rope["b_cell"].x == -2, "to the block it hit, on her near side (%s)" % rope["b_cell"])
	var length: float = rope["length"]
	assert_near(length, 60.0, 2.0, "as long as they were apart")
	target.linear_velocity += Vector3(5, 0, 0)
	await simulate(3.0)
	var apart := (ship.global_transform * Vector3(2, 1, 1)).distance_to(target.global_transform * Vector3(-2, 1, 1))
	assert_true(apart <= 1.3 * length, "the rope holds her (%.1f m apart)" % apart)
	assert_false(ropes.is_empty(), "still tied")
	await simulate(43.0)
	assert_true(ropes.is_empty(), "the rope goes after 45 s")


func test_recover_always_finds_somewhere() -> void:
	await start()
	for each: Ship in sync.ships.values():
		sync.remove_ship(each)
	await get_tree().process_frame
	var here: Vector3 = world.player.world_position()
	var nearest: Vector3 = world.gen.towns[0]["dock"]
	for town: Dictionary in world.gen.towns:
		if (town["dock"] as Vector3).distance_to(here) < nearest.distance_to(here):
			nearest = town["dock"]
	assert_eq(world.recover(null), null, "no ship to go to")
	assert_eq(world.ship, null, "ashore")
	var crew: CrewMember = world.player.crew
	assert_true(await simulate_until(func() -> bool: return crew.is_on_floor(), 2.0), "standing")
	assert_true(crew.position.distance_to(Dock.quay_spot(nearest)) <= 0.3, "on the quay of the nearest town (%s)" % crew.position)


func test_every_machine_draws_the_same_arc() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var ours: Ship = host_world.ship
	ours.anchored = true
	var id: int = host_world.sync.fire(ours, Vector3i(2, 1, 1), Vector3(1, 0.3, 0).normalized(), "round")
	var guest: Projectiles = client_world.projectiles
	var guest_sync: WorldSync = client_world.sync
	assert_true(await play_until(func() -> bool: return guest.shots.has(id), 1.0), "the guest has the shot")
	var sent: Dictionary = host_world.projectiles.shots[id]
	var shot: Dictionary = guest.shots[id]
	for key: String in ["ammo", "origin", "velocity", "time", "ship"]:
		assert_eq(shot[key], sent[key], "the host's %s" % key)
	assert_true(await play_until(func() -> bool: return guest_sync.now() - WorldSync.DELAY - shot["time"] > 0.2, 1.0), "drawn a while")
	guest._physics_process(0.0)
	var drawn := Projectiles.position_at(shot["origin"], shot["velocity"], guest_sync.now() - WorldSync.DELAY - shot["time"])
	var node: Node3D = shot["node"]
	assert_true(node.visible, "drawn")
	assert_true(node.global_position.distance_to(drawn) <= 0.01, "where the arc is, DELAY behind (%.3f m off)" % node.global_position.distance_to(drawn))


func test_hits_reach_the_guest() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var ours: Ship = host_world.ship
	ours.anchored = true
	var target := add_target(host_world.sync, ours, Vector3(-150, 0, 0))
	var id: int = host_world.sync.id_of(target)
	var guest: Projectiles = client_world.projectiles
	var guest_sync: WorldSync = client_world.sync
	assert_true(await play_until(func() -> bool: return guest_sync.ships.has(id), 1.0), "the guest has the target")
	var shot := fire_at(host_world.sync, ours, Vector3i(-2, 1, 1), target, Vector3i(2, 0, 0), "round")
	assert_true(await play_until(func() -> bool: return not host_world.projectiles.shots.has(shot), 3.0), "it hits on the host")
	var ends := [INF]
	var gone := await play_until(func() -> bool:
		if guest.shots.has(shot):
			ends[0] = guest.shots[shot]["ends"]
			return false
		return true, 1.0)
	assert_true(gone, "the guest's shot is gone within 1 s")
	assert_true(ends[0] < INF and guest_sync.now() - WorldSync.DELAY >= ends[0] - 0.02, "once it was drawn arriving")
	assert_true(await play_until(func() -> bool: return (guest_sync.ships[id] as Ship).grid.blocks == target.grid.blocks, 1.0), "the guest's copy has the host's hit points")
	assert_false(changed(target).is_empty(), "which a hit changed")


func test_the_guest_can_be_knocked_down() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var host_sync: WorldSync = host_world.sync
	var ours: Ship = host_world.ship
	ours.anchored = true
	var gunship := add_target(host_sync, ours, Vector3(-150, 0, 0))
	var guest_id: int = client.multiplayer.get_unique_id()
	var knocked := [false]
	client_world.sync.knocked_out.connect(func() -> void: knocked[0] = true)
	await play(0.5)  # where the guest stands reaches the host
	var guest_at: Vector3 = host_sync.crew_positions()[guest_id]
	var burst := ours.global_transform * Vector3(-2.5, 3, 5)
	assert_true(guest_at.distance_to(burst) < 2.0, "the guest stands beside the port rail (%.2f m)" % guest_at.distance_to(burst))
	fire_at(host_sync, gunship, Vector3i(2, 1, 1), ours, Vector3i(-2, 3, 5), "shell")
	assert_true(await play_until(func() -> bool: return knocked[0], 3.0), "the guest's world hears they're knocked down")
	assert_false(host_sync.crew_positions().has(guest_id), "the host leaves them out")
	await play(4.5)
	assert_false(host_sync.crew_positions().has(guest_id), "for 5 s")
	await play(1.0)
	assert_true(host_sync.crew_positions().has(guest_id), "then counts them again")


func test_ropes_reach_the_guest() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var host_sync: WorldSync = host_world.sync
	var ours: Ship = host_world.ship
	ours.anchored = true
	var target := add_target(host_sync, ours, Vector3(-64, 0, 0))
	var guest: Projectiles = client_world.projectiles
	assert_true(await play_until(func() -> bool: return client_world.sync.ships.has(host_sync.id_of(target)), 1.0), "the guest has the target")
	fire_at(host_sync, ours, Vector3i(-2, 1, 1), target, Vector3i(2, 1, 1), "harpoon")
	assert_true(await play_until(func() -> bool: return host_world.projectiles.ropes.size() == 1, 2.0), "a rope on the host")
	assert_true(await play_until(func() -> bool: return guest.ropes.size() == 1, 1.0), "and on the guest within 1 s")
	if guest.ropes.size() == 1:
		var rope: Dictionary = guest.ropes.values()[0]
		assert_true(rope["a"] == client_world.ship, "from the guest's copy of the firing ship")
		assert_eq(rope["b_cell"], Vector3i(2, 1, 1), "to the block it hit")
		assert_near(rope["length"], host_world.projectiles.ropes.values()[0]["length"], 0.001, "as long as the host's")
	host_sync.remove_ship(target)
	assert_true(await play_until(func() -> bool: return host_world.projectiles.ropes.is_empty(), 1.0), "the host's rope goes with the ship")
	assert_true(await play_until(func() -> bool: return guest.ropes.is_empty(), 1.0), "and so does the guest's")
