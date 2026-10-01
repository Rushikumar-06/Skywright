extends NetCase
## Manned cannons (spec §3.4, §4.6): E mans a cannon in reach, the aim follows your
## look within the cannon's arc, the left mouse button fires and Q picks the
## ammunition. The server decides who mans a cannon and what it fires.

const AT := Vector3(0, 1900, 7000)  ## Above every island.
const STARBOARD := Vector3i(2, 1, 1)
const PORT := Vector3i(-2, 1, 1)

var world: Node3D
var sync: WorldSync
var ship: Ship
var player: PlayerController


## A solo world with your ship calm and anchored at AT, and you standing by her
## starboard cannon.
func start() -> void:
	world = solo_world()
	await get_tree().process_frame
	sync = world.sync
	ship = world.ship
	ship.calm = true
	ship.anchored = true
	ship.global_position = AT
	player = world.player
	player.crew.position = Vector3(1, 1.4, 1)


## The cannon at cell of on, or null.
static func cannon_at(on: Ship, cell: Vector3i) -> Cannon:
	for cannon in on.cannons:
		if cannon.cell == cell:
			return cannon
	return null


## Fires a shell from cell of from at the world point target.
func shell_at(in_sync: WorldSync, from: Ship, cell: Vector3i, target: Vector3) -> int:
	var muzzle := from.global_transform * Vector3(cell)
	var direction := Projectiles.aim(target - muzzle, Damage.AMMO["shell"]["speed"])
	return in_sync.fire(from, cell, from.global_basis.inverse() * direction, "shell")


func test_the_starter_ship_carries_two_cannons_and_still_floats_level() -> void:
	var grid := StarterShip.build()
	assert_eq(grid.type_at(STARBOARD), "cannon")
	assert_eq(grid.type_at(PORT), "cannon")
	assert_eq(grid.cells_of("cannon").size(), 2, "two cannons")
	assert_true(Blocks.facing(grid.blocks[STARBOARD]["rotation"]).is_equal_approx(Vector3.RIGHT), "starboard faces +X")
	assert_true(Blocks.facing(grid.blocks[PORT]["rotation"]).is_equal_approx(Vector3.LEFT), "port faces -X")
	var stats := ShipStats.of(grid, 880.0)
	assert_near(stats.float_altitude, 881.0, 5.0, "floats near 881 m")
	assert_true(absf(stats.bow_down) < 0.1, "level fore and aft (%.3f°)" % stats.bow_down)
	assert_near(stats.list, 0.0, 0.001, "no list")
	var ship_here := Ship.new(grid)
	add_child(ship_here)
	assert_eq(ship_here.cannons.size(), 2, "the ship has both")
	var facings := ship_here.cannons.map(func(cannon: Cannon) -> Vector3: return cannon.facing().round())
	assert_true(facings.has(Vector3.RIGHT) and facings.has(Vector3.LEFT), "facing +X and -X (%s)" % [facings])


func test_manning_a_cannon_and_firing() -> void:
	await start()
	var cannon := cannon_at(ship, STARBOARD)
	assert_eq(player.prompt(), "Man the cannon")
	await get_tree().process_frame
	assert_eq(world.hud._prompt.text, "E   Man the cannon")
	press(player, "interact")
	assert_true(player.crew.station == cannon, "at the starboard cannon")
	assert_eq(cannon.gunner, player.peer)
	await get_tree().process_frame
	assert_eq(world.hud._prompt.text, "E   Leave the cannon")
	assert_true(world.hud._helm.visible, "the cannon's panel shows")
	var shots: Dictionary = world.projectiles.shots
	press(player, "fire")
	assert_eq(shots.size(), 1, "a shot")
	if shots.size() != 1:
		return
	var shot: Dictionary = shots.values()[0]
	var muzzle := ship.global_transform * (Vector3(STARBOARD) + cannon.direction() * WorldSync.MUZZLE)
	assert_true((shot["origin"] as Vector3).distance_to(muzzle) <= 1.0, "from the muzzle")
	var relative := (shot["velocity"] as Vector3) - ship.point_velocity(shot["origin"])
	var angle := rad_to_deg(relative.angle_to(ship.global_basis * cannon.direction()))
	assert_true(angle <= 5.0, "along the cannon's aim (%.1f° off)" % angle)
	await simulate(3.8)
	press(player, "fire")
	assert_eq(sync._next_shot, 2, "reloading: nothing more within 4 s")
	await simulate(0.3)
	press(player, "fire")
	assert_eq(sync._next_shot, 3, "loaded again after 4 s")


func test_the_aim_stays_within_the_cannons_arc() -> void:
	await start()
	var cannon := cannon_at(ship, STARBOARD)
	press(player, "interact")
	player.crew.look_yaw = 0.0  # toward the bow
	player.look_pitch = 0.0
	await simulate(0.05)
	assert_near(cannon.aim_yaw, Cannon.ARC, 0.0001, "as far toward the bow as it turns")
	player.look_pitch = 1.5  # straight up
	await simulate(0.05)
	assert_near(cannon.aim_pitch, Cannon.PITCH_MAX, 0.0001, "as high as it raises")
	var yaw := cannon.aim_yaw
	var pitch := cannon.aim_pitch
	assert_false(cannon.aim_at(Vector3.LEFT), "it can't aim behind itself")
	assert_eq(cannon.aim_yaw, yaw, "the aim is unchanged")
	assert_eq(cannon.aim_pitch, pitch)
	assert_true(cannon.aim_at(Vector3(1, 0.2, 0.3)), "but can aim ahead of itself")
	assert_true(cannon.direction().is_equal_approx(Vector3(1, 0.2, 0.3).normalized()), "and fires that way")


func test_q_changes_the_ammunition() -> void:
	await start()
	var cannon := cannon_at(ship, STARBOARD)
	press(player, "interact")
	var seen: Array[String] = []
	for i in 4:
		press(player, "ammo")
		seen.append(cannon.ammo)
		if i == 0:
			await get_tree().process_frame
			assert_true(world.hud._readout.text.begins_with("Cannon    Chain shot\nReady"), world.hud._readout.text)
	assert_eq(seen, ["chain", "shell", "harpoon", "round"] as Array[String])
	cannon.reload_left = 2.1
	assert_eq(Hud.cannon_readout(cannon), "Cannon    Round shot\nReloading 2.1 s")


func test_a_player_holds_one_station_at_a_time() -> void:
	await start()
	player.crew.position = ship.crew_spawn(0)
	press(player, "interact")
	assert_true(player.crew.station == ship.helm, "at the helm")
	var cannon := ship.cannons[0]
	cannon.ask_man(player.peer, true)
	assert_eq(ship.helm.pilot, 0, "the helm is let go")
	assert_true(player.crew.station == cannon, "you're at the cannon")
	assert_eq(player.prompt(), "Leave the cannon")
	press(player, "interact")
	assert_eq(cannon.gunner, 0, "E leaves the cannon")
	assert_true(player.crew.station == null, "at no station")


func test_a_destroyed_cannon_lets_its_gunner_go() -> void:
	await start()
	press(player, "interact")
	assert_true(player.crew.station == cannon_at(ship, STARBOARD), "at the starboard cannon")
	sync.damage_ship(ship, {STARBOARD: 0})
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(player.crew.station == null, "let go")
	assert_eq(ship.cannons.size(), 1, "one cannon left")
	assert_false(world.hud._helm.visible, "the panel is hidden")


func test_a_knocked_out_gunner_leaves_the_cannon() -> void:
	await start()
	var cannon := cannon_at(ship, STARBOARD)
	press(player, "interact")
	assert_eq(cannon.gunner, player.peer)
	var gunship := sync.add_ship(StarterShip.build(), ship.global_transform.translated(Vector3(150, 0, 0)))
	gunship.calm = true
	gunship.anchored = true
	var knocked := [false]
	sync.knocked_out.connect(func() -> void: knocked[0] = true)
	shell_at(sync, gunship, PORT, player.world_position())
	for tick in 180:
		if knocked[0]:
			break
		await simulate(1.0 / Engine.physics_ticks_per_second)
	assert_true(knocked[0], "knocked down")
	assert_eq(cannon.gunner, 0, "the cannon is let go")
	assert_true(player.crew.station == null, "at no station")


func test_the_guest_mans_a_cannon_and_fires() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var ours: Ship = host_world.ship
	var theirs: Ship = client_world.ship
	ours.anchored = true
	var guest: PlayerController = client_world.player
	guest.crew.position = Vector3(-1, 1.4, 1)
	await play(0.3)  # where the guest stands reaches the host
	assert_eq(guest.prompt(), "Man the cannon")
	press(guest, "interact")
	var host_cannon := cannon_at(ours, PORT)
	var guest_cannon := cannon_at(theirs, PORT)
	assert_true(await play_until(func() -> bool: return host_cannon.gunner == guest.peer, 1.0), "the host has the guest at the cannon within 1 s")
	assert_true(await play_until(func() -> bool: return guest.crew.station == guest_cannon, 1.0), "and the guest hears so")
	press(guest, "ammo")
	press(guest, "fire")
	assert_true(guest_cannon.reload_left > 0.0, "the guest's cannon shows it reloading")
	var host_shots: Dictionary = host_world.projectiles.shots
	var guest_shots: Dictionary = client_world.projectiles.shots
	assert_true(await play_until(func() -> bool: return host_shots.size() == 1 and guest_shots.size() == 1, 1.0), "both machines have the shot")
	if host_shots.size() == 1 and guest_shots.size() == 1:
		assert_eq(host_shots.values()[0]["ammo"], "chain", "chain shot on the host")
		assert_eq(guest_shots.values()[0]["ammo"], "chain", "and on the guest")
	assert_true(host_cannon.reload_left > 0.0, "the host's cannon is reloading")


func test_the_server_ignores_fire_from_someone_not_at_the_cannon() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var ours: Ship = host_world.ship
	ours.anchored = true
	var host_sync: WorldSync = host_world.sync
	var guest_sync: WorldSync = client_world.sync
	var id := host_sync.id_of(ours)
	var guest: PlayerController = client_world.player
	host_world.player.crew.position = Vector3(1, 1.4, 1)
	press(host_world.player, "interact")
	assert_eq(cannon_at(ours, STARBOARD).gunner, 1, "the host mans the starboard cannon")
	guest.crew.position = Vector3(1, 11.4, 6)  # on top of the envelope
	await play(0.3)
	var far: float = (host_sync._crew[guest.peer]["at"] as Vector3).distance_to(Vector3(PORT))
	assert_true(far > 10.0, "the guest is %.1f m from the port cannon" % far)
	guest_sync._man.rpc_id(1, id, PORT, true)
	await play(0.3)
	assert_eq(cannon_at(ours, PORT).gunner, 0, "manning from there is refused")

	guest_sync._fire.rpc_id(1, id, STARBOARD, 0.0, 0.0, 0)  # the host's cannon
	guest_sync._fire.rpc_id(1, id, PORT, 0.0, 0.0, 0)       # nobody's
	await play(0.3)
	assert_eq(host_sync._next_shot, 1, "nothing fired")

	guest.crew.position = Vector3(-1, 1.4, 1)
	await play(0.3)
	press(guest, "interact")
	assert_true(await play_until(func() -> bool: return cannon_at(ours, PORT).gunner == guest.peer, 1.0), "the guest mans the port cannon")
	guest_sync._fire.rpc_id(1, id, PORT, NAN, 0.0, 0)
	guest_sync._fire.rpc_id(1, id, PORT, 0.0, 0.0, 9)
	await play(0.3)
	assert_eq(host_sync._next_shot, 1, "nothing fired for a NaN aim or unknown ammunition")
	guest_sync._fire.rpc_id(1, id, PORT, 0.2, 0.1, 1)
	guest_sync._fire.rpc_id(1, id, PORT, 0.2, 0.1, 1)
	await play(0.3)
	assert_eq(host_sync._next_shot, 2, "the one legal shot, and none while reloading")


func test_a_knocked_out_pilot_is_let_go_on_host_and_guest() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var host_sync: WorldSync = host_world.sync
	var ours: Ship = host_world.ship
	var theirs: Ship = client_world.ship
	ours.anchored = true
	var guest: PlayerController = client_world.player
	await play(0.2)  # where the guest stands reaches the host
	press(guest, "interact")
	assert_true(await play_until(func() -> bool: return guest.crew.station == theirs.helm, 2.0), "the guest takes the helm")
	var gunship := host_sync.add_ship(StarterShip.build(), ours.global_transform.translated(Vector3(-150, 0, 0)))
	gunship.calm = true
	gunship.anchored = true
	var guest_at: Vector3 = host_sync.crew_positions()[guest.peer]
	shell_at(host_sync, gunship, STARBOARD, guest_at)
	assert_true(await play_until(func() -> bool: return ours.helm.pilot == 0, 3.0), "the host lets the guest go")
	assert_true(await play_until(func() -> bool: return theirs.helm.pilot == 0 and guest.crew.station == null, 1.0), "and the guest hears so")
