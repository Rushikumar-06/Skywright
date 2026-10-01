extends NetCase
## Pirates (spec §3.5): ships built from the same blocks and flying on the same
## physics, with AI captains that chase, circle and fire broadsides. The server
## sends them against crewed ships away from towns, and clears them away when
## everyone is far off.

const PIRATE_RED := Color("d9534f")

var world: Node3D
var sync: WorldSync
var ship: Ship


## A solo world with pirates off and your ship anchored in open sky at 1,000 m.
func start() -> void:
	world = solo_world()
	await get_tree().process_frame
	sync = world.sync
	ship = world.ship
	ship.anchored = true
	ship.global_position = open_sky(world, 1000.0)
	sync.rng.seed = 1


## Shots stop doing harm, so a test of how pirates fly isn't ended by her wrecking
## you; test_a_pirate_fires_broadsides covers the hits.
func harmless_shots() -> void:
	world.projectiles.hit.disconnect(sync._on_shot_hit)


static func captain_of(pirate: Ship) -> PirateCaptain:
	for child in pirate.get_children():
		if child is PirateCaptain:
			return child
	return null


static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func pirates() -> Array[Ship]:
	var found: Array[Ship] = []
	for each: Ship in sync.ships.values():
		if each.pirate:
			found.append(each)
	return found


func test_the_pirate_ship_flies() -> void:
	var grid := PirateShip.build()
	var stats := ShipStats.of(grid, 960.0)
	assert_true(stats.float_altitude >= 900.0 and stats.float_altitude <= 1050.0, "floats at %.0f m" % stats.float_altitude)
	assert_true(absf(stats.list) < 0.5, "list %.2f°" % stats.list)
	assert_true(absf(stats.bow_down) < 1.0, "bow down %.2f°" % stats.bow_down)
	assert_true(stats.top_speed > 15.0, "top speed %.1f m/s" % stats.top_speed)
	assert_eq(stats.warnings, PackedStringArray(), "no warnings")
	var facings := grid.cells_of("cannon").map(func(cell: Vector3i) -> Vector3: return Blocks.facing(grid.blocks[cell]["rotation"]).round())
	assert_eq(facings.count(Vector3.RIGHT), 2, "two cannons to starboard")
	assert_eq(facings.count(Vector3.LEFT), 2, "two to port")
	var pirate := Ship.new(grid)
	pirate.calm = true
	pirate.position = Vector3(0, stats.float_altitude, 7000)
	add_child(pirate)
	var worst := [0.0, 0.0]
	await simulate(60.0, func(_tick: int) -> void:
		worst[0] = maxf(worst[0], absf(pirate.global_position.y - stats.float_altitude))
		worst[1] = maxf(worst[1], absf(rad_to_deg(asin(clampf(-pirate.global_basis.z.y, -1.0, 1.0))))))
	assert_true(worst[0] < 30.0, "holds her height (off by %.1f m at worst)" % worst[0])
	assert_true(worst[1] < 1.5, "and her pitch (%.2f° at worst)" % worst[1])


func test_a_pirate_chases_and_circles() -> void:
	await start()
	harmless_shots()
	var pirate := sync.spawn_pirate(ship)
	assert_true(pirate != null, "a pirate comes")
	if pirate == null:
		return
	assert_near(flat(pirate.global_position - ship.global_position).length(), WorldSync.PIRATE_DISTANCE, 1.0, "800 m off")
	var captain := captain_of(pirate)
	assert_true(captain != null, "with a captain")
	var circled := [false]
	await simulate(90.0, func(_tick: int) -> void: circled[0] = circled[0] or captain.state == "circle")
	assert_true(circled[0], "it closed in and circled")
	var span := [INF, 0.0, 0.0]
	await simulate(30.0, func(_tick: int) -> void:
		var d := flat(pirate.global_position - ship.global_position).length()
		span[0] = minf(span[0], d)
		span[1] = maxf(span[1], d)
		span[2] = maxf(span[2], absf(pirate.global_position.y - ship.global_position.y)))
	assert_true(span[0] >= 150.0 and span[1] <= 500.0, "circling between %.0f and %.0f m" % [span[0], span[1]])
	assert_true(span[2] <= 40.0, "at your height (off by %.0f m at worst)" % span[2])


func test_a_pirate_fires_broadsides() -> void:
	await start()
	var pirate := sync.spawn_pirate(ship)
	var shots: Dictionary = world.projectiles.shots
	var seen := {}
	var wrong := []
	await simulate(120.0, func(_tick: int) -> void:
		for id: int in shots:
			var shot: Dictionary = shots[id]
			if seen.has(id) or shot["ship"] != sync.id_of(pirate):
				continue
			seen[id] = true
			var facing := flat(pirate.global_basis * Blocks.facing(pirate.grid.blocks[shot["cell"]]["rotation"]))
			var to_you := flat(ship.global_position - pirate.global_position)
			if rad_to_deg(facing.angle_to(to_you)) > 50.0:
				wrong.append(shot["cell"]))
	assert_true(seen.size() >= 4, "it fired %d shots" % seen.size())
	assert_eq(wrong, [], "every one from the side facing you")
	assert_true(ship.condition() < 1.0, "and hit you (hull %.0f%%)" % (ship.condition() * 100.0))


func test_a_pirate_without_a_helm_gives_up() -> void:
	await start()
	var pirate := sync.spawn_pirate(ship)
	await simulate(1.0)
	sync.damage_ship(pirate, {pirate.helm.cell: 0})
	await simulate(1.0)
	assert_true(captain_of(pirate) == null, "the captain is gone")
	var before := sync._next_shot
	await simulate(30.0)
	assert_eq(sync._next_shot, before, "and nothing more is fired")


func test_a_pirate_turns_on_whoever_is_nearest() -> void:
	await start()
	harmless_shots()
	var pirate := sync.spawn_pirate(ship)
	pirate.anchored = true  # placed by hand below
	var start_at := ship.global_position + Vector3(-2000, 0, 0)
	pirate.global_position = start_at
	var near := ship
	near.global_position = start_at + Vector3(700, 0, 0)
	var far := sync.add_ship(StarterShip.build(), Transform3D(Basis.IDENTITY, start_at + Vector3(1200, 0, 0)))
	far.anchored = true
	pirate.anchored = false
	var captain := captain_of(pirate)
	await simulate(1.0)
	assert_true(captain.target == near, "it chases the nearer")
	assert_true(await wait_until(func() -> bool: return captain.state == "circle", 90.0), "and closes in")
	near.global_position += Vector3(-2500, 0, 0)
	await simulate(1.0)
	assert_true(captain.target == far, "then turns on the other")


func test_pirates_raid_away_from_towns() -> void:
	world = solo_world()
	await get_tree().process_frame
	sync = world.sync
	ship = world.ship
	ship.anchored = true
	world.session.pirates = true
	sync.rng.seed = 1
	for i in 40:
		sync._raid()
	assert_eq(pirates().size(), 0, "none at the dock")
	ship.global_position = open_sky(world, 1000.0)
	var region := WorldGen.region_at(ship.global_position)
	for i in 40:
		sync._raid()
	assert_eq(pirates().size(), WorldSync.RAID_LIMIT[region], "%s's limit" % WorldGen.REGION_NAMES[region])
	for pirate in pirates():
		var at := pirate.global_position
		var center := WorldGen.chunk_of(at)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for island: Dictionary in world.gen.islands_in(center + Vector2i(dx, dz)):
					var gap := flat(at - (island["at"] as Vector3)).length()
					assert_true(gap >= island["radius"] + WorldSync.ISLAND_CLEARANCE, "clear of island %s (%.0f m)" % [island["id"], gap])


func test_pirates_stay_home_when_raids_are_off() -> void:
	await start()
	for i in 40:
		sync._raid()
	assert_eq(pirates().size(), 0, "no raids in a game without pirates")


func test_pirates_leave_when_far() -> void:
	await start()
	var pirate := sync.spawn_pirate(ship)
	await simulate(0.5)
	sync._wear()
	assert_true(sync.id_of(pirate) != 0, "a pirate nearby stays")
	pirate.global_position = ship.global_position + Vector3(3500, 0, 0)
	sync._wear()
	assert_eq(sync.id_of(pirate), 0, "one 3.5 km off goes")


func test_wrecks_are_pirate_ships() -> void:
	var gen := WorldGen.new(SEED)
	var pirate := PirateShip.build()
	for w in gen.wrecks.slice(0, 5):
		var grid := Sites.wreck_grid(w)
		assert_true(grid.cells_of("balloon").is_empty(), "no balloons")
		assert_eq(var_to_str(grid.blocks), var_to_str(Sites.wreck_grid(w).blocks), "the same every time")
		for cell: Vector3i in grid.blocks:
			assert_eq(grid.type_at(cell), pirate.type_at(cell), "a pirate's block at %s" % cell)


func test_the_guest_sees_pirates() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var host_sync: WorldSync = host_world.sync
	var ours: Ship = host_world.ship
	ours.anchored = true
	var pirate := host_sync.spawn_pirate(ours)
	assert_true(pirate != null and captain_of(pirate) != null, "the host's pirate has a captain")
	var id := host_sync.id_of(pirate)
	var guest_sync: WorldSync = client_world.sync
	assert_true(await play_until(func() -> bool: return guest_sync.ships.has(id), 1.0), "the guest gets it")
	var theirs: Ship = guest_sync.ships.get(id)
	if theirs == null:
		return
	assert_true(theirs.pirate, "as a pirate")
	assert_true(captain_of(theirs) == null, "with no captain there")
	assert_eq(MapView.ship_color(theirs), PIRATE_RED, "red on the map")
	assert_true(MapView.ship_color(client_world.ship) != PIRATE_RED, "unlike your own")
