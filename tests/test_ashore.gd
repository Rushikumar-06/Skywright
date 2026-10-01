extends NetCase
## On foot (spec §4.5): stepping off a deck puts you ashore in the main world, where
## you walk the islands and glide; landing on a deck, or E next to a hull, puts you
## aboard; the Roil sends you back aboard. A pilot can anchor a ship, which holds it
## still, whatever the wind.

var world: Node3D
var ship: Ship
var player: PlayerController


func after_each() -> void:
	for action in ["move_forward", "move_right", "jump"]:
		Input.action_release(action)
	super.after_each()


## A solo world once its islands have streamed in, with its ship calm and, unless
## anchor is off, anchored.
func start(anchor := true) -> bool:
	world = solo_world()
	await get_tree().process_frame
	ship = world.ship
	player = world.player
	ship.calm = true
	ship.anchored = anchor
	return await wait_until(world.streamer.settled, 20.0)


## Steps you off the ship and puts you at p, in the main world, still.
func ashore_at(p: Vector3) -> CrewMember:
	world.go_ashore()
	var crew: CrewMember = player.crew
	crew.position = p
	crew.velocity = Vector3.ZERO
	crew.reset_physics_interpolation()
	return crew


func test_jumping_on_deck_stays_aboard() -> void:
	assert_true(await start(), "settled")
	player.crew.position = Vector3(0, 1.45, 0)
	await simulate(0.5)
	var left := [0]
	player.left_ship.connect(func() -> void: left[0] += 1)
	var highest := [0.0]
	for jump in 3:
		player.crew.jump = true
		await simulate(1.2, func(_tick: int) -> void: highest[0] = maxf(highest[0], player.crew.position.y))
	assert_true(highest[0] > 2.4, "jumped (to %.2f m)" % highest[0])
	assert_eq(left[0], 0, "never left")
	assert_true(world.ship == ship, "still aboard")
	assert_eq(player.crew.get_parent(), ship.interior)


func test_walking_off_the_side_goes_ashore_with_the_ships_speed() -> void:
	assert_true(await start(false), "settled")
	ship.global_position = world.START + Vector3(0, 0, -200)  # clear of the dock
	ship.reset_physics_interpolation()
	ship.linear_velocity = Vector3(10, 0, 0)
	player.crew.position = Vector3(0, 1.45, 0)
	Input.action_press("move_right")
	var speed := [0.0]
	var ashore := await simulate_until(func() -> bool:
		if world.ship != null:
			player.crew.jump = true  # over the rail
			return false
		speed[0] = player.crew.velocity.x
		return true, 3.0)
	assert_true(ashore, "stepped off")
	assert_eq(player.crew.get_parent(), world, "in the main world")
	assert_true(world.left == ship, "off that ship")
	assert_true(speed[0] >= 9.0, "with the ship's speed (%.1f m/s east)" % speed[0])


func test_you_dont_bounce_straight_back_aboard() -> void:
	assert_true(await start(), "settled")
	player.crew.position = Vector3(0, 1.45, 0)
	await simulate(0.3)
	var landed := [0]
	player.landed_on.connect(func(_on: Ship) -> void: landed[0] += 1)
	world.go_ashore()
	var touching := [false]
	await simulate(0.45, func(_tick: int) -> void:
		touching[0] = touching[0] or player.crew.is_on_floor())
	assert_true(touching[0], "standing on her deck")
	assert_eq(landed[0], 0, "but not straight back aboard")
	assert_true(world.ship == null, "still ashore")
	assert_true(await simulate_until(func() -> bool: return world.ship == ship, 0.5), "aboard again after a moment")


## The middle of the top of the plain island nearest the start.
func island_top() -> Vector3:
	var island := {}
	var best := INF
	for chunk in WorldGen.chunks_near(world.START, 2000.0):
		for each: Dictionary in world.gen.islands_in(chunk):
			var gap := Vector2(each["at"].x - world.START.x, each["at"].z - world.START.z).length()
			if each["site"] == "" and gap < best:
				island = each
				best = gap
	assert_false(island.is_empty(), "an island nearby")
	return island["at"] + Vector3(0.0, IslandMesh.height(island, 0.0, 0.0), 0.0)


func test_walking_on_an_island() -> void:
	assert_true(await start(), "settled")
	var spot := island_top()
	var top := spot.y
	var crew := ashore_at(spot + Vector3(0.0, 2.0 + CrewMember.HEIGHT / 2.0, 0.0))
	await simulate(3.0)
	assert_true(crew.is_on_floor(), "standing")
	assert_near(crew.position.y - CrewMember.HEIGHT / 2.0, top, 1.0, "on the island")
	var from := crew.position
	Input.action_press("move_forward")
	await simulate(3.0)
	var walked := Vector2(crew.position.x - from.x, crew.position.z - from.z).length()
	assert_true(walked >= 10.0, "walked %.1f m" % walked)


func test_gliding_goes_far_and_falls_slowly() -> void:
	assert_true(await start(), "settled")
	var from := Vector3(0, 1200, 8500)  # beyond the rim, where nothing floats
	var crew := ashore_at(from)
	crew.look_yaw = 0.0  # north
	Input.action_press("jump")
	await simulate(10.0)
	assert_true(from.y - crew.position.y < 40.0, "fell %.1f m" % (from.y - crew.position.y))
	assert_true(from.z - crew.position.z >= 100.0, "went %.1f m north" % (from.z - crew.position.z))

	Input.action_release("jump")
	from = Vector3(300, 1200, 8500)
	crew.position = from
	crew.velocity = Vector3.ZERO
	crew.reset_physics_interpolation()
	var fastest := [0.0]
	await simulate(10.0, func(_tick: int) -> void:
		fastest[0] = maxf(fastest[0], -crew.velocity.y))
	assert_true(from.y - crew.position.y >= 250.0, "without gliding, fell %.1f m" % (from.y - crew.position.y))
	assert_true(fastest[0] <= CrewMember.FALL_LIMIT + 0.01, "no faster than %.0f m/s (%.1f)" % [CrewMember.FALL_LIMIT, fastest[0]])


func test_an_ordinary_jump_ashore_doesnt_glide() -> void:
	# Space held from the jump: the glide may only open once you're falling.
	assert_true(await start(), "settled")
	var crew := ashore_at(island_top() + Vector3(0.0, 1.0 + CrewMember.HEIGHT / 2.0, 0.0))
	await simulate(2.0)
	assert_true(crew.is_on_floor(), "standing")
	var from := crew.position
	Input.action_press("jump")
	crew.jump = true
	var seen := {"rose": false, "glided rising": false, "prompt rising": false, "landed": false}
	var hud: Hud = world.hud
	await simulate(3.0, func(_tick: int) -> void:
		if crew.velocity.y > 0.0 and not crew.is_on_floor():
			seen["rose"] = true
			seen["glided rising"] = seen["glided rising"] or crew.gliding
			seen["prompt rising"] = seen["prompt rising"] or hud._prompt.text == "Hold Space   Glide"
		if seen["rose"] and crew.is_on_floor():
			seen["landed"] = true)
	assert_true(seen["rose"], "jumped")
	assert_false(seen["glided rising"], "no glide on the way up")
	assert_false(seen["prompt rising"], "and no glide prompt either")
	assert_true(seen["landed"], "came down again")
	var travelled := Vector2(crew.position.x - from.x, crew.position.z - from.z).length()
	assert_true(travelled < 2.0, "no lunge forward (%.1f m)" % travelled)


func test_falling_fast_stays_within_what_the_server_takes() -> void:
	assert_true(await start(), "settled")
	var crew := ashore_at(Vector3(0, 1200, 8500))  # beyond the rim, where nothing floats
	crew.velocity = Vector3(20, 0, 0)  # as off a ship at 20 m/s
	var fastest := [0.0]
	await simulate(10.0, func(_tick: int) -> void:
		fastest[0] = maxf(fastest[0], crew.velocity.length()))
	assert_true(fastest[0] <= CrewMember.FALL_LIMIT + 0.01, "no faster than %.0f m/s (%.1f)" % [CrewMember.FALL_LIMIT, fastest[0]])
	assert_true(WorldSync.crew_speed_ok(crew.velocity), "so the server keeps taking your reports (%.4f m/s)" % crew.velocity.length())


func test_landing_on_a_deck_boards_that_ship() -> void:
	assert_true(await start(), "settled")
	var other: Ship = world.sync.add_ship(StarterShip.build(), Dock.slipway(world.START, 1))
	other.calm = true
	other.anchored = true
	ashore_at(other.global_transform * Vector3(0, 1.45 + 5.0, 0))
	assert_true(await simulate_until(func() -> bool: return world.ship == other, 3.0), "landed and came aboard")
	assert_eq(player.crew.get_parent(), other.interior)
	await simulate(0.3)
	assert_true(player.crew.is_on_floor(), "standing on her deck")
	assert_near(player.crew.position.y, 1.4, 0.1, "on the main deck")


func test_climbing_aboard_from_the_pier() -> void:
	assert_true(await start(), "settled")
	var dock: Vector3 = world.gen.towns[0]["dock"]
	ashore_at(dock + Vector3(5.0, -1.5 + CrewMember.HEIGHT / 2.0 + 0.05, 0))
	await simulate(0.3)
	assert_true(player.crew.is_on_floor(), "standing on the pier")
	await get_tree().process_frame
	assert_eq(world.hud._prompt.text, "E   Climb aboard")
	press(player, "interact")
	assert_true(world.ship == ship, "aboard")
	assert_eq(player.crew.get_parent(), ship.interior)
	assert_eq(player.crew.position, ship.crew_spawn(world.my_slot()))


func test_the_roil_sends_you_back_aboard() -> void:
	assert_true(await start(), "settled")
	ashore_at(Vector3(world.START.x + 20.0, 190.0, world.START.z))
	await simulate(0.1)
	assert_true(world.ship == ship, "back aboard the ship you left")
	assert_eq(player.crew.get_parent(), ship.interior)
	var message: Label = world.hud._message
	assert_true(message.visible and message.text == "The Roil nearly took you. Back aboard!", message.text)


func test_a_new_ship_arriving_while_ashore_boards_you() -> void:
	assert_true(await start(), "settled")
	ashore_at(world.gen.towns[0]["dock"] + Vector3(5.0, -1.5 + CrewMember.HEIGHT / 2.0 + 0.05, 0))
	await simulate(0.2)
	world.launch(StarterShip.build())
	assert_true(await simulate_until(func() -> bool: return world.ship != null, 1.0), "the new ship arrives")
	var new_ship: Ship = world.ship
	assert_true(new_ship != ship, "a new ship")
	assert_eq(player.crew.station, new_ship.helm, "at her helm")
	assert_true(world.left == null, "the old one is gone")


func test_an_anchored_ship_stays_put_in_a_storm() -> void:
	assert_true(await start(), "settled")
	ship.calm = false
	var centre: Vector3 = world.gen.storm_center(0, world.sync.now()) + Vector3(0, 877, 0)
	assert_true(world.wind.storm_strength(centre, world.sync.now()) > 0.9, "in the storm")
	ship.global_position = centre
	ship.reset_physics_interpolation()
	var at: Transform3D = ship.global_transform
	await simulate(20.0)
	assert_true(ship.global_position.distance_to(at.origin) < 0.01, "held still (moved %.2f m)" % ship.global_position.distance_to(at.origin))
	assert_true(ship.global_basis.is_equal_approx(at.basis), "and didn't turn")
	ship.anchored = false
	await simulate(5.0)
	assert_true(ship.global_position.distance_to(at.origin) > 1.0, "weighing anchor, the storm takes her (%.2f m)" % ship.global_position.distance_to(at.origin))


func test_only_the_pilot_anchors() -> void:
	assert_true(await start(false), "settled")
	ship.helm.ask_anchor(1, true)
	assert_false(ship.anchored, "not at the helm, so no")
	press(player, "interact")
	assert_eq(player.crew.station, ship.helm, "at the helm")
	press(player, "anchor")
	assert_true(ship.anchored and ship.freeze, "G drops anchor")
	assert_true(ship.linear_velocity == Vector3.ZERO and ship.angular_velocity == Vector3.ZERO, "and holds her still")
	ship.helm.ask_anchor(2, false)
	assert_true(ship.anchored, "someone else can't weigh it")
	await get_tree().process_frame
	assert_true(world.hud._readout.text.ends_with("\nAnchored"), world.hud._readout.text)
	press(player, "anchor")
	assert_false(ship.anchored or ship.freeze, "G again weighs anchor")


func test_a_guest_ashore_is_seen_where_they_are() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var guest := client.multiplayer.get_unique_id()
	await play(0.2)
	client_world.go_ashore()
	var crew: CrewMember = client_world.player.crew
	var dock: Vector3 = client_world.gen.towns[0]["dock"]
	crew.position = dock + Vector3(5.0, -1.5 + CrewMember.HEIGHT / 2.0 + 0.05, 0)
	crew.velocity = Vector3.ZERO
	crew.reset_physics_interpolation()
	assert_true(await play_until(func() -> bool:
		var seen: CrewAvatar = host_world.sync.avatar_of(guest)
		return seen != null and seen.global_position.distance_to(crew.global_position) < 2.0, 1.0), "the host sees the guest on the pier")
	assert_eq(host_world.sync._crew[guest]["ship"], 0, "ashore")

	client_world.sync.player = null  # the guest stops reporting, so only junk arrives
	await play(0.2)
	var heard: SnapshotBuffer = host_world.sync._crew[guest]["buffer"]
	var before: Vector3 = heard._samples[-1]["position"]
	var send := func(args: Array) -> void: client_world.sync._crew_report.rpc_id.callv([1] + args)
	send.call([0, Vector3(20000, 800, 0), Vector3.ZERO, 0.0, 0.0])
	send.call([0, before, Vector3(80, 0, 0), 0.0, 0.0])
	send.call([0, Vector3(before.x, -10, before.z), Vector3.ZERO, 0.0, 0.0])
	await play(0.3)
	assert_eq(heard._samples[-1]["position"], before, "none of that was taken")
	var there := before + Vector3(0, 0, -3)
	send.call([0, there, Vector3.ZERO, 0.0, 0.0])
	assert_true(await play_until(func() -> bool: return heard._samples[-1]["position"] == there, 1.0), "a sensible report is taken")


func test_anchoring_reaches_the_guest() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var ours: Ship = host_world.ship
	ours.helm.take(1)
	ours.helm.ask_anchor(1, true)
	assert_true(ours.anchored, "the host anchors")
	assert_true(await play_until(func() -> bool: return (client_world.ship as Ship).anchored, 1.0), "and the guest sees it")
	var client_id := client.multiplayer.get_unique_id()
	client_world.ship.helm.ask_anchor(client_id, false)
	await play(0.3)
	assert_true(ours.anchored, "the guest isn't the pilot")
