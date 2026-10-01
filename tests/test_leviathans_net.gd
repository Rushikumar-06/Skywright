extends NetCase
## Leviathans roam the Gale Expanse (spec §3.5): the server sends one in now and then
## by a crewed ship there, keeps drifting ones in the Gale, takes far ones away, and
## every machine sees them. Hired gunners fire at angry ones, never at calm ones.

const GALE := Vector3(0, 1000, -3000)

var world: Node3D
var sync: WorldSync
var ship: Ship
var beasts: Leviathans


## A solo world, your ship anchored in open sky.
func start() -> void:
	world = solo_world()
	await get_tree().process_frame
	sync = world.sync
	ship = world.ship
	beasts = world.leviathans
	sync.rng.seed = 1
	ship.anchored = true
	ship.global_position = open_sky(world, 1000.0)


func count_of(kind: String) -> int:
	return beasts.beasts.values().filter(func(beast: Leviathan) -> bool: return beast.kind == kind).size()


func test_leviathans_roam_the_gale() -> void:
	await start()
	world.session.leviathans = true
	ship.global_position = GALE
	var seen := []
	for i in 20:
		var before := beasts.beasts.size()
		beasts._roam()
		for id: int in beasts.beasts:
			if not seen.has(id):
				seen.append(id)
				var flat := (beasts.beasts[id] as Leviathan).global_position - ship.global_position
				assert_near(Vector2(flat.x, flat.z).length(), Leviathans.DISTANCE, 1.0, "first seen 900 m off")
		assert_true(beasts.beasts.size() - before <= 1)
	assert_eq(beasts.beasts.size(), 2, "the Gale Expanse's limit")
	var gale := beasts.beasts.duplicate()
	ship.global_transform = Dock.slipway(world.gen.towns[0]["dock"], 0)
	var at_dock := beasts.beasts.size()
	for i in 20:
		beasts._roam()
	assert_eq(beasts.beasts.size(), at_dock, "none come in the Calm Reaches")
	ship.global_position = GALE
	world.session.leviathans = false
	for i in 20:
		beasts._roam()
	assert_eq(beasts.beasts.size(), at_dock, "none with leviathans off")
	ship.global_position = GALE + Vector3(4500, 0, 0)  # beyond WorldSync.FAR of both, whichever side they came
	assert_true(await simulate_until(func() -> bool: return gale.keys().all(func(id: int) -> bool: return not beasts.beasts.has(id)), 1.1),
			"far from everyone, they go")


func test_a_drifting_leviathan_keeps_to_the_gale() -> void:
	await start()
	ship.global_position = Vector3(1500, 1000, 3800)
	var beast := beasts.spawn("leviathan", Vector3(0, 1000, 4200), PI)  # swimming outward
	assert_true(await simulate_until(func() -> bool: return Vector2(beast.global_position.x, beast.global_position.z).length() < 4000.0, 120.0),
			"back in the Gale: %.0f m out" % Vector2(beast.global_position.x, beast.global_position.z).length())


func test_gunners_fire_at_angry_leviathans() -> void:
	await start()
	var post := Vector3i(2, 1, 1)
	sync.set_hands(ship, [{"id": -1, "name": "Fenn", "role": "gunner", "post": post, "at": ship.spot_near(post)}])
	var cannon: Cannon = ship.cannons.filter(func(each: Cannon) -> bool: return each.cell == post)[0]
	var beast := beasts.spawn("leviathan", ship.global_position + Vector3(300, 0, 0), 0.0)
	beast.held = true
	await simulate(10.0)
	assert_eq(cannon.reload_left, 0.0, "he leaves a calm one alone")
	assert_eq(beast.hp, 2000)
	beast.hurt(0, ship)
	assert_true(await simulate_until(func() -> bool: return cannon.reload_left > 0.0, 8.0), "he fires at an angry one")
	assert_true(await simulate_until(func() -> bool: return beast.hp < 2000, 15.0), "and hits it")


func test_guests_see_leviathans() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var host_sync: WorldSync = host_world.sync
	var ours: Ship = host_world.ship
	var theirs: Leviathans = client_world.leviathans
	var beast: Leviathan = (host_world.leviathans as Leviathans).spawn("leviathan", ours.global_position + Vector3(300, 0, 0), 0.0)
	var id: int = host_world.leviathans.beasts.find_key(beast)
	assert_true(await play_until(func() -> bool: return theirs.beasts.has(id), 1.0), "the guest has it")
	var copy: Leviathan = theirs.beasts[id]
	assert_eq(copy.kind, "leviathan")
	assert_false(copy.simulated, "drawn, not thought for")
	var trail := []
	await play(1.0, func(_tick: int) -> void: trail.append([host_sync.now(), beast.global_position]))
	var shown_at: float = client_world.sync.now() - WorldSync.DELAY
	var then: Array = trail.reduce(func(best: Array, each: Array) -> Array:
		return each if absf(each[0] - shown_at) < absf(best[0] - shown_at) else best)
	assert_true(copy.global_position.distance_to(then[1]) < 10.0, "drawn where the host had it: %.1f m" % copy.global_position.distance_to(then[1]))
	(host_world.leviathans as Leviathans).shot(beast, "round", ours)
	assert_true(await play_until(func() -> bool: return copy.hp == beast.hp, 1.0), "the same hit points")
	var late := make_session("Late")
	late.join("Cy", "127.0.0.1", host.port)
	assert_true(await play_until(func() -> bool: return late.sailing, 5.0), "Cy joins")
	var late_world := add_world(late)
	assert_true(await play_until(func() -> bool: return (late_world.leviathans as Leviathans).beasts.has(id), 2.0), "a late joiner has it")
	(host_world.leviathans as Leviathans).remove(beast)
	assert_true(await play_until(func() -> bool: return not theirs.beasts.has(id), 1.0), "and its removal")


func test_junk_beast_messages_are_refused() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var beast: Leviathan = (host_world.leviathans as Leviathans).spawn("leviathan", host_world.ship.global_position + Vector3(300, 0, 0), 0.0)
	var theirs: Leviathans = client_world.leviathans
	assert_true(await play_until(func() -> bool: return theirs.beasts.size() == 1, 1.0), "the guest has it")
	var id: int = theirs.beasts.keys()[0]
	var copy: Leviathan = theirs.beasts[id]
	var at := Vector3(0, 1000, 0)
	var now: float = client_world.sync.now()
	for entry: Array in [[50, "dragon", at, Vector3.ZERO, 0.0, 100, 0], [51, "leviathan", Vector3(NAN, 0, 0), Vector3.ZERO, 0.0, 100, 0],
			[52, "leviathan", at, Vector3.ZERO, 0.0, -1, 0], [53, "leviathan", at, Vector3.ZERO, 0.0, 99999, 0],
			[id, "leviathan", at, Vector3.ZERO, 0.0, 100, 0]]:
		theirs._beast_added(now, entry)
	theirs._beasts(now, "beasts")
	theirs._beasts(now, [[id, at, Vector3.ZERO]])
	theirs._beasts(now, [[99, at, Vector3.ZERO, 0.0, 0]])
	theirs._beast_hurt(id, 99999)
	theirs._beast_hurt(99, 100)
	await play(0.2)
	assert_eq(theirs.beasts.keys(), [id], "nothing added")
	assert_eq(copy.hp, beast.hp, "nothing changed")
	assert_true(copy.global_position.distance_to(at) > 100.0, "nor moved")
