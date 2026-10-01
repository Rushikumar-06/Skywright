extends NetCase
## The Stormwall (spec §3.1, §4.7): an outward wind below its top that only a capable
## ship crosses, by thrust or over the top; no town stands in it; and a test flight
## can't carry you across.

const RING := 2450.0  ## m from the centre that crossing flights start.


## Flies grid at the centre from RING out at angle, at altitude on the autopilot at full
## throttle, for seconds, with an engineer at her first engine when asked: {"closest":
## m she came to the centre, "inside_at": s she was first within 1,500 m, or -1}.
func cross(grid: ShipGrid, angle: float, altitude: float, seconds: float, engineer := false) -> Dictionary:
	var wind := Wind.new(WorldGen.new(NetCase.SEED))
	wind.time = 0.0
	var start := Vector3(cos(angle) * RING, altitude, sin(angle) * RING)
	var flying := Ship.new(grid)
	flying.weather = wind
	flying.transform = Transform3D(Basis.looking_at(-Vector3(start.x, 0, start.z), Vector3.UP), start)
	add_child(flying)
	if engineer:
		flying.set_hands([{"id": 1, "name": "Fenn", "role": "engineer", "post": grid.cells_of("engine")[0], "at": Vector3.ZERO}])
	flying.helm.set_autopilot(true)
	flying.helm.target_altitude = altitude
	flying.throttle = 1.0
	var result := {"closest": INF, "inside_at": -1.0}
	await simulate(seconds, func(tick: int) -> void:
		wind.time = tick / 60.0
		var p := flying.global_position
		flying.helm.target_heading = atan2(p.x, p.z)
		var d := Vector2(p.x, p.z).length()
		result["closest"] = minf(result["closest"], d)
		if d < 1500.0 and result["inside_at"] < 0.0:
			result["inside_at"] = tick / 60.0)
	flying.queue_free()
	return result


func test_the_stormwall_blows_outward() -> void:
	var wind := Wind.new()
	var average := func(p: Vector3) -> Vector3:
		var sum := Vector3.ZERO
		for t in 600:
			sum += wind.at(p, float(t))
		return sum / 600.0
	var core: Vector3 = average.call(Vector3(0, 1000, -1900))
	assert_near(core.z, -22.0, 1.0, "outward")
	assert_near(core.x, -14.0, 1.0, "with the prevailing wind")
	for p in [Vector3(0, 2000, -1900), Vector3(0, 1000, -1450), Vector3(0, 1000, -2350)]:
		assert_true(absf((average.call(p) as Vector3).z) < 1.0, "none at %s" % p)
	assert_eq(Wind.wall_strength(Vector3(0, 1000, -1900)), 1.0)
	assert_eq(Wind.wall_strength(Vector3(0, 1950, -1900)), 0.0)


func test_the_wall_is_smooth() -> void:
	var wind := Wind.new()
	var walks := [[Vector3(1400, 1000, 0), Vector3.RIGHT, 1000], [Vector3(1900, 1500, 0), Vector3.UP, 600]]
	for walk: Array in walks:
		var last := wind.at(walk[0], 50.0)
		for i in range(1, walk[2] + 1):
			var here := wind.at(walk[0] + walk[1] * float(i), 50.0)
			assert_true((here - last).length() <= 3.0, "jumped %.2f m/s at %s" % [(here - last).length(), walk[0] + walk[1] * float(i)])
			last = here


func test_the_starter_ship_cant_cross() -> void:
	for angle in [0.0, 3.9]:
		var flown := await cross(StarterShip.build(), angle, 1100.0, 300.0, true)
		assert_true(flown["closest"] > 1700.0, "at %.1f she came to %.0f m" % [angle, flown["closest"]])


func test_the_wallbreaker_crosses() -> void:
	for angle in [0.6, 3.9]:
		var flown := await cross(Wallbreaker.build(), angle, 1000.0, 240.0)
		assert_true(flown["inside_at"] >= 0.0, "at %.1f she got in (closest %.0f m)" % [angle, flown["closest"]])


func test_a_ship_can_go_over_the_top() -> void:
	var grid := StarterShip.build()
	for x in [-1, 1]:
		for z in range(-1, 3):
			grid.set_block(Vector3i(x, -1, z), "lift_stone")
	var flown := await cross(grid, 0.0, 1900.0, 150.0)
	assert_true(flown["inside_at"] >= 0.0, "over the top (closest %.0f m)" % flown["closest"])


func test_no_town_stands_in_the_stormwall() -> void:
	for world_seed in range(1, 21) + [NetCase.SEED]:
		var gen := WorldGen.new(world_seed)
		assert_eq(gen.towns.size(), 10, "seed %d has ten towns" % world_seed)
		for i in gen.towns.size():
			assert_true(WorldGen.clear_of_the_wall(gen.towns[i]["dock"]), "seed %d town %d" % [world_seed, i])
		if gen.towns.size() < 10:
			continue
		assert_eq(gen.towns[9]["region"], WorldGen.Region.EYE, "seed %d's tenth town" % world_seed)
		var area := Dock.area(gen.towns[9]["dock"])
		for x in [area.position.x, area.end.x]:
			for z in [area.position.z, area.end.z]:
				assert_true(Vector2(x, z).length() >= 800.0, "seed %d: the Eye's town keeps from the heart" % world_seed)
		var reach := ceili((WorldGen.HEART_ISLANDS + WorldGen.MAX_ISLAND_RADIUS) / WorldGen.CHUNK)
		for cx in range(-reach - 1, reach + 1):
			for cz in range(-reach - 1, reach + 1):
				for island: Dictionary in gen.islands_in(Vector2i(cx, cz)):
					if island["site"] == "":
						var gap: float = Vector2(island["at"].x, island["at"].z).length() - island["radius"]
						assert_true(gap >= 450.0, "seed %d: island %s is %.0f m from the heart" % [world_seed, island["id"], gap])


func test_a_test_flight_cant_ferry_you_across() -> void:
	var world := solo_world()
	await get_tree().process_frame
	var own: Ship = world.ship
	world.test_flight(StarterShip.build())
	assert_true(await wait_until(func() -> bool: return world.ship != null and world.ship.test, 1.0), "on a test flight")
	var sync: WorldSync = world.sync
	var trial := sync.id_of(world.ship)
	world.go_ashore()
	assert_true(await wait_until(func() -> bool: return not sync.ships.has(trial) and world.ship == own, 1.0), "back aboard your own ship")
	assert_eq(world.player.crew.get_parent(), own.interior, "standing on her")
	assert_eq(world.hud._message.text, "You stepped off your test flight, so it's over.")
	await simulate(1.1)
	world.abandon_ship()
	var player: PlayerController = world.player
	assert_true(await wait_until(func() -> bool: return world.ship == null and player.crew.is_on_floor(), 5.0), "ashore on the quay")
	await simulate(1.1)
	world.test_flight(StarterShip.build())
	assert_true(await wait_until(func() -> bool: return world.ship != null and world.ship.test, 1.0), "another test flight")
	trial = sync.id_of(world.ship)
	world.go_ashore()
	assert_true(await wait_until(func() -> bool: return not sync.ships.has(trial) and world.ship == null, 1.0), "she's over")
	assert_true(player.world_position().distance_to(Dock.quay_spot(world.gen.towns[0]["dock"])) < 3.0,
			"on the starting town's quay: %s" % player.world_position())
