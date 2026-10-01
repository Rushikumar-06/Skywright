extends NetCase
## Storms (spec §3.5, §4.8): lightning strikes the highest block of a ship in rough air
## and may set the blocks around it alight, turbulence rocks ships, and the fog closes
## in. The server strikes; every machine sees the bolt.

const AT := Vector3(0, 880, 7000)


## Air with no wind and a roughness of its own.
class RoughAir extends Wind:
	var rough := 1.0

	func at(_p: Vector3, _t: float) -> Vector3:
		return Vector3.ZERO

	func roughness(_p: Vector3, _t: float) -> float:
		return rough


func plain(rough: float, calm := false) -> Ship:
	var air := RoughAir.new()
	air.rough = rough
	var rocked := Ship.new(StarterShip.build())
	rocked.weather = air
	rocked.calm = calm
	rocked.position = AT
	add_child(rocked)
	return rocked


## The most she rolled and pitched, in degrees, over seconds.
func lean(rocked: Ship, seconds: float) -> Vector2:
	var most := [Vector2.ZERO]
	await simulate(seconds, func(_tick: int) -> void:
		var b := rocked.global_basis
		var now := Vector2(absf(rad_to_deg(asin(-b.x.y))), absf(rad_to_deg(asin(-b.z.y))))
		most[0] = Vector2(maxf(most[0].x, now.x), maxf(most[0].y, now.y)))
	return most[0]


func strikes_of(sync: WorldSync) -> Array:
	var seen := []
	sync.struck.connect(func(on: Ship, cell: Vector3i) -> void: seen.append([on, cell]))
	return seen


func weather_of(world: Node3D) -> Weather:
	return world.find_children("*", "Weather", false, false)[0]


func test_turbulence_rocks_a_ship_in_rough_air() -> void:
	var rocked := plain(1.0)
	var most: Vector2 = await lean(rocked, 60.0)
	assert_true(most.x > 1.5 and most.y > 3.0, "rolled %.1f°, pitched %.1f°" % [most.x, most.y])
	rocked.queue_free()
	var still := plain(0.0)
	most = await lean(still, 60.0)
	assert_true(most.x < 0.3 and most.y < 0.3, "still air: %.2f°, %.2f°" % [most.x, most.y])


func test_calm_flight_tests_feel_no_turbulence() -> void:
	var most: Vector2 = await lean(plain(1.0, true), 60.0)
	assert_true(most.x < 0.3 and most.y < 0.3, "%.2f°, %.2f°" % [most.x, most.y])


func test_lightning_strikes_the_highest_block() -> void:
	var world := solo_world()
	await get_tree().process_frame
	var sync: WorldSync = world.sync
	var ship: Ship = world.ship
	ship.anchored = true
	ship.global_basis = Basis.IDENTITY
	var before := ship.grid.to_blocks()
	var seen := strikes_of(sync)
	var cell := sync.strike(ship)
	assert_eq(cell, Vector3i(-1, 10, -4))
	assert_false(ship.grid.blocks.has(cell), "destroyed")
	var next := {Vector3i(0, 10, -4): true, Vector3i(-1, 9, -4): true, Vector3i(-1, 10, -3): true}
	for block: Array in before:
		var at := Vector3i(block[0], block[1], block[2])
		if at == cell:
			continue
		var hp: int = ship.grid.blocks[at]["hp"]
		assert_eq(hp, 20 if next.has(at) else block[5], "%s" % at)
	assert_eq(seen, [[ship, cell]])


func test_a_strike_can_start_a_fire() -> void:
	var world := solo_world()
	await get_tree().process_frame
	var sync: WorldSync = world.sync
	var ship: Ship = world.ship
	ship.anchored = true
	sync.rng.seed = 1
	for i in 10:
		sync.strike(ship)
	assert_false(ship.fires.is_empty(), "a fire caught")


func test_storms_strike_only_in_rough_air() -> void:
	var world := solo_world()
	await get_tree().process_frame
	var sync: WorldSync = world.sync
	var ship: Ship = world.ship
	world.session.lightning = true
	sync.rng.seed = 1
	ship.anchored = true
	open_sky(world, 1000.0)
	var seen := strikes_of(sync)
	ship.global_position = Vector3(0, 1000, -1900)
	for i in 300:
		sync._strike_storms()
	assert_true(seen.size() >= 5 and seen.size() <= 30, "%d strikes in the wall" % seen.size())
	seen.clear()
	ship.global_position = Vector3(0, 1950, -1900)
	for i in 300:
		sync._strike_storms()
	assert_eq(seen.size(), 0, "above the wall")
	ship.global_transform = Dock.slipway(world.gen.towns[0]["dock"], 0)
	for i in 300:
		sync._strike_storms()
	assert_eq(seen.size(), 0, "at the dock")
	ship.global_position = Vector3(0, 1000, -1900)
	world.session.lightning = false
	for i in 60:
		sync._wear()
	assert_eq(seen.size(), 0, "with lightning off")


func test_the_fog_closes_in_inside_a_storm() -> void:
	var world := solo_world()
	await get_tree().process_frame
	var ship: Ship = world.ship
	var sky: WorldSky = world._sky
	ship.anchored = true
	open_sky(world, 1000.0)
	var home := ship.global_transform
	var fog := func(begin: float, end: float) -> bool:
		return sky._environment.fog_depth_begin <= begin and sky._environment.fog_depth_end <= end
	ship.global_position = Vector3(0, 1000, -1900)
	assert_true(await wait_until(fog.bind(100.0, 450.0), 0.2),
			"%.0f to %.0f m" % [sky._environment.fog_depth_begin, sky._environment.fog_depth_end])
	ship.global_transform = home
	assert_true(await wait_until(func() -> bool: return sky._environment.fog_depth_end == 2600.0, 0.2), "clear at the dock")
	assert_eq(sky._environment.fog_depth_begin, 900.0)


func test_guests_see_lightning() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var ours: Ship = host_world.ship
	var copy: Ship = client_world.sync.ships[host_world.sync.id_of(ours)]
	var seen := strikes_of(client_world.sync)
	var bolts := weather_of(client_world).bolts_struck
	var cell: Vector3i = host_world.sync.strike(ours)
	assert_true(await play_until(func() -> bool: return seen.size() == 1, 1.0), "the guest heard it")
	assert_eq(seen[0], [copy, cell])
	assert_true(weather_of(client_world).bolts_struck > bolts, "and saw the bolt")
	assert_true(await play_until(func() -> bool: return not copy.grid.blocks.has(cell), 1.0), "its copy lost the cell")


func test_a_junk_strike_is_ignored() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var theirs: WorldSync = client_world.sync
	var id: int = host_world.sync.id_of(host_world.ship)
	var seen := strikes_of(theirs)
	var bolts := weather_of(client_world).bolts_struck
	theirs._strike(999, Vector3i(0, 10, 0))
	theirs._strike(id, Vector3i(100, 0, 0))
	theirs._strike(id, "top")
	theirs._strike("1", Vector3i(0, 10, 0))
	await play(0.1)
	assert_eq(seen.size(), 0)
	assert_eq(weather_of(client_world).bolts_struck, bolts)
