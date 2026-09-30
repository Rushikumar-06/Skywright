extends NetCase
## WorldSync (spec §4.6): the server flies the ships and clients draw them 100 ms
## in the past, smoothly, from snapshots.

var host: SessionScript
var client: SessionScript
var host_world: Node3D
var client_world: Node3D


func after_each() -> void:
	for action in ["move_forward", "move_right"]:
		Input.action_release(action)
	super.after_each()


## Host and Guest meet in the lobby, set sail, and each loads a world. True once
## the guest's ship has arrived.
func sail_together() -> bool:
	host = make_session("Host")
	client = make_session("Client")
	if not await host_and_join(host, client):
		return false
	host.set_sail()
	if not await wait_until(func() -> bool: return client.sailing, 5.0):
		return false
	host_world = add_world(host)
	client_world = add_world(client)
	return await wait_until(func() -> bool: return client_world.ship != null, 5.0)


func test_a_joining_client_gets_the_ship() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var ours: Ship = host_world.ship
	var theirs: Ship = client_world.ship
	assert_eq(theirs.grid.blocks.size(), ours.grid.blocks.size())
	assert_eq(theirs.mass, ours.mass)
	assert_true(ours.simulated and not ours.freeze, "the host flies it")
	assert_false(theirs.simulated, "the client doesn't")
	assert_true(theirs.freeze and theirs.freeze_mode == RigidBody3D.FREEZE_MODE_KINEMATIC, "it just follows")
	assert_true(theirs.global_position.distance_to(ours.global_position) < 1.0)
	assert_eq(client_world.player.crew.get_parent(), theirs.interior, "and the guest is aboard")


func test_the_client_sees_the_ship_fly_smoothly() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var ours: Ship = host_world.ship
	var theirs: Ship = client_world.ship
	ours.calm = true
	ours.throttle = 1.0
	ours.linear_velocity = -ours.global_basis.z * 15.0
	var truth := SnapshotBuffer.new()  # where the host's ship was, every tick, on the host's clock
	var errors: Array[float] = []
	var steps: Array[float] = []
	var last := [theirs.global_position]
	await play(3.0, func(tick: int) -> void:
		truth.push(host_world.sync.now(), ours.global_position, ours.linear_velocity, ours.global_basis.get_rotation_quaternion())
		if tick >= 30:  # once the guest's clock and buffer have settled
			var shown_at: float = client_world.sync.now() - WorldSync.DELAY
			errors.append(theirs.global_position.distance_to(truth.sample(shown_at)["position"]))
			steps.append(theirs.global_position.distance_to(last[0]))
		last[0] = theirs.global_position)
	errors.sort()
	steps.sort()
	assert_true(errors[-1] < 0.05, "drawn where the host's ship was (worst %.3f m)" % errors[-1])
	var median := steps[steps.size() / 2]
	assert_true(median > 0.2, "it moved (%.3f m a tick)" % median)
	assert_true(steps[-1] < 2.0 * median, "no jumps: worst step %.3f m, median %.3f m" % [steps[-1], median])


func test_the_client_sees_the_helm_readout() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var ours: Ship = host_world.ship
	var theirs: Ship = client_world.ship
	ours.throttle = 0.5
	ours.helm.set_autopilot(true)
	assert_true(await wait_until(func() -> bool: return theirs.helm.autopilot and theirs.throttle == 0.5, 2.0), "throttle and autopilot come through")
	await play(0.5)
	assert_near(theirs.trim, ours.trim, 0.01, "trim")
	assert_near(theirs.helm.target_altitude, ours.helm.target_altitude, 0.01, "the autopilot's altitude")
	var text := Hud.readout(theirs)
	assert_true(text.contains("50% ahead"), text)
	assert_false(text.contains("Autopilot off"), text)


func test_a_late_joiner_boards_the_ship_where_it_is() -> void:
	host = make_session("Host")
	var port := free_port()
	host.host("Ann", port)
	host.set_sail()
	host_world = add_world(host)
	await get_tree().process_frame
	var ours: Ship = host_world.ship
	ours.throttle = 1.0
	await simulate(20.0)
	var late := make_session("Late")
	late.join("Bob", "127.0.0.1", port)
	assert_true(await wait_until(func() -> bool: return late.sailing, 5.0), "straight to the world")
	var late_world := add_world(late)
	assert_true(await wait_until(func() -> bool: return late_world.ship != null, 5.0), "the ship arrives")
	await play(1.0)
	var theirs: Ship = late_world.ship
	assert_true(ours.global_position.distance_to(host_world.START) > 30.0, "the host flew off (%.0f m)" % ours.global_position.distance_to(host_world.START))
	var allowed := ours.linear_velocity.length() * (WorldSync.DELAY + 0.1) + 0.5
	var apart := theirs.global_position.distance_to(ours.global_position)
	assert_true(apart < allowed, "the late joiner sees her where she is (%.2f m apart, %.2f allowed)" % [apart, allowed])
	var crew: CrewMember = late_world.player.crew
	assert_eq(crew.get_parent(), theirs.interior, "and stands aboard her")
	assert_true(crew.is_on_floor(), "on her deck")


func test_everyone_sees_the_same_time_of_day() -> void:
	host = make_session("Host")
	var port := free_port()
	host.host("Ann", port)
	host.set_sail()
	host_world = add_world(host)
	await get_tree().process_frame
	host_world.sync._time = WorldSky.DAY_LENGTH / 2.0  # half a day on: 22:00
	client = make_session("Client")
	client.join("Bob", "127.0.0.1", port)
	assert_true(await wait_until(func() -> bool: return client.sailing, 5.0), "joined")
	client_world = add_world(client)
	assert_true(await wait_until(func() -> bool: return client_world.ship != null, 5.0), "the ship arrives")
	await play(0.5)
	assert_near(client_world.sync.now(), host_world.sync.now(), 0.1, "one clock")
	assert_near(host_world._sky.hour, 22.0, 0.05, "the host's sky")
	assert_near(client_world._sky.hour, host_world._sky.hour, 0.01, "the same sky")


func test_crew_walk_where_everyone_sees_them() -> void:
	assert_true(await sail_together(), "the ship arrives")
	host_world.ship.calm = true
	var client_id := client.multiplayer.get_unique_id()
	# The guest walks forward along the main deck while the host stands still.
	var walker: CrewMember = client_world.player.crew
	walker.position = Vector3(0, 1.45, 2)
	host_world.player.enabled = false
	Input.action_press("move_forward")
	await play(1.0)
	Input.action_release("move_forward")
	await play(0.3)  # others see you WorldSync.DELAY behind
	assert_true(walker.position.z < -1.0, "the guest walked (to z %.2f)" % walker.position.z)
	var seen := _in_ship_space(host_world, host_world.sync.avatar_of(client_id))
	assert_true(seen.distance_to(walker.position) < 0.15, "the host sees the guest at %s, really at %s" % [seen, walker.position])

	# And the other way round.
	var host_walker: CrewMember = host_world.player.crew
	host_walker.position = Vector3(1, 1.45, 2)
	host_world.player.enabled = true
	client_world.player.enabled = false
	Input.action_press("move_forward")
	await play(1.0)
	Input.action_release("move_forward")
	await play(0.3)
	assert_true(host_walker.position.z < -1.0, "the host walked (to z %.2f)" % host_walker.position.z)
	seen = _in_ship_space(client_world, client_world.sync.avatar_of(1))
	assert_true(seen.distance_to(host_walker.position) < 0.15, "the guest sees the host at %s, really at %s" % [seen, host_walker.position])


func test_players_board_at_different_spots() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var ours: CrewMember = host_world.player.crew
	var theirs: CrewMember = client_world.player.crew
	assert_eq(ours.home, host_world.ship.crew_spawn(0), "the host takes the first spot")
	assert_eq(theirs.home, client_world.ship.crew_spawn(1), "the guest the next")


func test_the_server_ignores_crew_reports_that_make_no_sense() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var client_id := client.multiplayer.get_unique_id()
	await play(0.3)
	client_world.sync.player = null  # the guest stops reporting, so only junk arrives
	await play(0.2)
	var heard: SnapshotBuffer = host_world.sync._crew[client_id]["buffer"]
	var before: Vector3 = heard._samples[-1]["position"]
	var send := func(args: Array) -> void: client_world.sync._crew_report.rpc_id.callv([1] + args)
	var here := Vector3(0, 1.45, 0)
	send.call([1, Vector3(NAN, 0, 0), Vector3.ZERO, 0.0, 0.0])
	send.call([1, Vector3(0, 0, 100), Vector3.ZERO, 0.0, 0.0])
	send.call([1, here, Vector3(500, 0, 0), 0.0, 0.0])
	send.call([1, here, Vector3.ZERO, INF, 0.0])
	send.call([99, here, Vector3.ZERO, 0.0, 0.0])
	send.call(["1", here, Vector3.ZERO, 0.0, 0.0])
	send.call([1, "here", Vector3.ZERO, 0.0, 0.0])
	await play(0.3)
	assert_eq(heard._samples[-1]["position"], before, "none of that was taken")
	host_world.sync._in_world.erase(client_id)  # as if the guest's world hadn't loaded
	send.call([1, here, Vector3.ZERO, 0.0, 0.0])
	await play(0.3)
	assert_eq(heard._samples[-1]["position"], before, "nor a report from outside the world")
	host_world.sync._in_world[client_id] = true
	send.call([1, here, Vector3.ZERO, 0.0, 0.0])
	assert_true(await wait_until(func() -> bool: return heard._samples[-1]["position"] == here, 2.0), "a sensible report is taken")


func _in_ship_space(world: Node3D, avatar: CrewAvatar) -> Vector3:
	assert_true(avatar != null, "there's an avatar")
	if avatar == null:
		return Vector3.INF
	return world.ship.global_transform.affine_inverse() * avatar.global_position


func test_one_pilot_at_a_time_and_a_clean_handover() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var client_id := client.multiplayer.get_unique_id()
	var ours: Ship = host_world.ship
	var theirs: Ship = client_world.ship
	await play(0.2)  # where the guest stands reaches the host
	press(client_world.player, "interact")
	assert_true(await wait_until(func() -> bool: return client_world.player.crew.station == theirs.helm, 2.0), "the guest takes the helm")
	assert_eq(ours.helm.pilot, client_id)
	press(host_world.player, "interact")
	assert_eq(ours.helm.pilot, client_id, "the host is refused")
	assert_eq(host_world.player.crew.station, null)
	await get_tree().process_frame
	assert_eq(host_world.hud._prompt.text, "Guest is at the helm")

	host_world.player.enabled = false  # the keys below are the guest's
	Input.action_press("move_forward")
	Input.action_press("move_right")
	assert_true(await wait_until(func() -> bool: return ours.throttle > 0.2 and ours.rudder == 1.0, 2.0), "the guest's keys steer the host's ship")
	Input.action_release("move_forward")
	Input.action_release("move_right")
	press(client_world.player, "interact")
	assert_true(await wait_until(func() -> bool: return ours.helm.pilot == 0, 2.0), "the guest lets go")
	assert_eq(ours.rudder, 0.0, "the rudder centres")
	assert_true(ours.throttle > 0.2, "the throttle stays")
	assert_eq(client_world.player.crew.station, null)

	host_world.player.enabled = true
	press(host_world.player, "interact")
	assert_eq(ours.helm.pilot, 1, "the host takes over")
	assert_true(await wait_until(func() -> bool: return theirs.helm.pilot == 1, 2.0), "and the guest hears so")
	await get_tree().process_frame
	assert_eq(client_world.hud._prompt.text, "Host is at the helm")


func test_two_players_asking_at_once_get_one_pilot() -> void:
	host = make_session("Host")
	var ann := make_session("Ann")
	var bob := make_session("Bob")
	var port := free_port()
	host.host("Host", port)
	ann.join("Ann", "127.0.0.1", port)
	bob.join("Bob", "127.0.0.1", port)
	assert_true(await wait_until(func() -> bool: return ann.players.size() == 3 and bob.players.size() == 3, 5.0), "all aboard")
	host.set_sail()
	assert_true(await wait_until(func() -> bool: return ann.sailing and bob.sailing, 5.0), "set sail")
	host_world = add_world(host)
	var ann_world := add_world(ann)
	var bob_world := add_world(bob)
	assert_true(await wait_until(func() -> bool: return ann_world.ship != null and bob_world.ship != null, 5.0), "the ship arrives")
	await play(0.2)
	press(ann_world.player, "interact")
	press(bob_world.player, "interact")
	await play(0.3)  # both asked; the server decided and everyone heard
	var pilot: int = host_world.ship.helm.pilot
	assert_true(pilot == ann.multiplayer.get_unique_id() or pilot == bob.multiplayer.get_unique_id(), "one of them has it")
	assert_eq(ann_world.ship.helm.pilot, pilot, "Ann knows who")
	assert_eq(bob_world.ship.helm.pilot, pilot, "Bob knows who")
	var at_helm := [ann_world, bob_world].filter(func(world: Node3D) -> bool: return world.player.crew.station != null)
	assert_eq(at_helm.size(), 1, "exactly one is at the helm")


func test_a_client_out_of_reach_cant_take_the_helm() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var client_id := client.multiplayer.get_unique_id()
	var walker: CrewMember = client_world.player.crew
	walker.position = Vector3(0, 1.45, -2)  # down on the main deck
	await play(0.3)  # the host hears where the guest is
	assert_eq(client_world.player.prompt(), "", "nothing in reach")
	client_world.ship.helm.ask_helm(client_id, true)  # as a modified client could
	await play(0.3)
	assert_eq(host_world.ship.helm.pilot, 0, "refused")
	walker.position = client_world.ship.crew_spawn(1)
	await play(0.3)
	client_world.ship.helm.ask_helm(client_id, true)
	assert_true(await wait_until(func() -> bool: return host_world.ship.helm.pilot == client_id, 2.0), "back in reach, it's granted")


func test_helm_keys_from_anyone_but_the_pilot_are_ignored() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var client_id := client.multiplayer.get_unique_id()
	var ours: Ship = host_world.ship
	var keys := func(throttle: Variant, rudder: Variant, climb: Variant) -> void:
		client_world.sync._helm_keys.rpc_id(1, 1, throttle, rudder, climb)
	press(host_world.player, "interact")
	keys.call(1.0, 1.0, 1.0)
	await play(0.3)
	assert_eq(ours.throttle, 0.0, "a guest can't steer from the host's helm")

	press(host_world.player, "interact")
	press(client_world.player, "interact")
	assert_true(await wait_until(func() -> bool: return ours.helm.pilot == client_id, 2.0), "the guest takes the helm")
	client_world.sync.player = null  # from here, only the keys below are sent
	await play(0.1)
	keys.call(NAN, 0.0, 0.0)
	keys.call("full", 0.0, 0.0)
	await play(0.3)
	assert_eq(ours.helm.throttle_input, 0.0, "junk keys are ignored")
	keys.call(5.0, -7.0, 0.5)
	assert_true(await wait_until(func() -> bool: return ours.helm.throttle_input == 1.0, 2.0), "the pilot's keys are taken")
	assert_eq(ours.helm.rudder_input, -1.0, "clamped")
	assert_eq(ours.helm.climb_input, 0.5)


func test_the_autopilot_answers_only_the_pilot() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var client_id := client.multiplayer.get_unique_id()
	var ours: Ship = host_world.ship
	client_world.ship.helm.ask_autopilot(client_id, true)
	await play(0.3)
	assert_false(ours.helm.autopilot, "not the pilot, so no")
	press(client_world.player, "interact")
	assert_true(await wait_until(func() -> bool: return client_world.player.crew.station != null, 2.0), "the guest takes the helm")
	press(client_world.player, "autopilot")
	assert_true(await wait_until(func() -> bool: return ours.helm.autopilot, 2.0), "the pilot switches it on")
	assert_true(await wait_until(func() -> bool: return client_world.ship.helm.autopilot, 2.0), "and sees it on")
	ours.helm.ask_autopilot(1, false)
	assert_true(ours.helm.autopilot, "the host isn't the pilot, so it stays on")


func test_a_pilot_who_drops_frees_the_helm() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var client_id := client.multiplayer.get_unique_id()
	var ours: Ship = host_world.ship
	await play(0.2)
	press(client_world.player, "interact")
	assert_true(await wait_until(func() -> bool: return ours.helm.pilot == client_id, 2.0), "the guest takes the helm")
	host_world.player.enabled = false
	Input.action_press("move_right")
	assert_true(await wait_until(func() -> bool: return ours.rudder == 1.0, 2.0), "hard to starboard")
	assert_true(host_world.sync.avatar_of(client_id) != null, "the host sees the guest")
	client.leave()  # mid-turn
	assert_true(await wait_until(func() -> bool: return ours.helm.pilot == 0, 2.0), "the helm is freed")
	assert_eq(ours.rudder, 0.0, "the rudder centres")
	assert_eq(ours.helm.rudder_input, 0.0, "and stays centred")
	assert_true(host_world.sync.avatar_of(client_id) == null, "the guest is gone from the deck")
	host_world.player.enabled = true
	press(host_world.player, "interact")
	assert_eq(ours.helm.pilot, 1, "and anyone else can take the helm")


func test_everyone_drops_the_avatar_of_someone_who_leaves() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var late := make_session("Late")
	late.join("Cy", "127.0.0.1", host.port)
	assert_true(await wait_until(func() -> bool: return late.sailing, 5.0), "Cy joins")
	var late_world := add_world(late)
	var late_id := late.multiplayer.get_unique_id()
	assert_true(await wait_until(func() -> bool: return client_world.sync.avatar_of(late_id) != null, 3.0), "the guest sees Cy")
	late.leave()
	assert_true(await wait_until(func() -> bool: return client_world.sync.avatar_of(late_id) == null, 3.0), "and then doesn't")
	assert_true(late_world.player != null)


func test_the_hud_says_who_comes_and_goes() -> void:
	host = make_session("Host")
	var port := free_port()
	host.host("Host", port)
	host.set_sail()
	host_world = add_world(host)
	await get_tree().process_frame
	var message: Label = host_world.hud._message
	client = make_session("Client")
	client.join("Guest", "127.0.0.1", port)
	assert_true(await wait_until(func() -> bool: return message.visible and message.text == "Guest came aboard.", 3.0), "a joiner is announced")
	client.leave()
	assert_true(await wait_until(func() -> bool: return message.visible and message.text == "Guest left.", 3.0), "and a leaver: %s" % message.text)


func test_a_dedicated_world_has_a_ship_and_nobody_aboard() -> void:
	host = make_session("Server")
	var port := free_port()
	host.host("Skyport", port, true)
	host_world = add_world(host)
	await get_tree().process_frame
	var ship: Ship = host_world.ship
	assert_true(ship != null and ship.simulated, "the server flies a ship")
	assert_true(host_world.player == null and host_world.hud == null, "but nobody plays here")
	assert_true(ship.freeze, "anchored while nobody's aboard")
	var anchored_at := ship.global_position
	await play(0.5)
	assert_true(ship.global_position.distance_to(anchored_at) < 0.01, "and she stays put")

	client = make_session("Client")
	client.join("Guest", "127.0.0.1", port)
	assert_true(await wait_until(func() -> bool: return client.sailing, 5.0), "a guest joins")
	client_world = add_world(client)
	assert_true(await wait_until(func() -> bool: return client_world.ship != null, 5.0), "and gets the ship")
	assert_eq(client_world.player.crew.home, client_world.ship.crew_spawn(0), "the first spot is theirs")
	assert_false(ship.freeze, "under way with someone aboard")
	ship.throttle = 1.0
	ship.helm.set_autopilot(true)
	await play(0.3)
	client.leave()
	assert_true(await wait_until(func() -> bool: return ship.freeze, 3.0), "anchored again when they leave")
	assert_eq(ship.throttle, 0.0)
	assert_false(ship.helm.autopilot)


func test_a_pilot_and_a_guest_leaving_together_are_dropped_cleanly() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var late := make_session("Late")
	late.join("Cy", "127.0.0.1", host.port)
	assert_true(await wait_until(func() -> bool: return late.sailing, 5.0), "Cy joins")
	var late_world := add_world(late)
	assert_true(await wait_until(func() -> bool: return late_world.ship != null, 5.0), "and boards")
	await play(0.2)
	var client_id := client.multiplayer.get_unique_id()
	press(client_world.player, "interact")
	assert_true(await wait_until(func() -> bool: return host_world.ship.helm.pilot == client_id, 2.0), "the guest takes the helm")
	client.leave()  # the pilot first, so freeing the helm has Cy to tell
	late.leave()
	assert_true(await wait_until(func() -> bool: return host_world.ship.helm.pilot == 0 and host.players.size() == 1, 3.0), "both gone, the helm freed")
	await play(0.2)
