extends NetCase
## WorldSync (spec §4.6): the server flies the ships and clients draw them 100 ms
## in the past, smoothly, from snapshots.

var host: SessionScript
var client: SessionScript
var host_world: Node3D
var client_world: Node3D


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
