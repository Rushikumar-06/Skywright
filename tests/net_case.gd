class_name NetCase
extends TestCase
## Base for tests with several players in one process. Each player gets a branch:
## a SubViewport with its own MultiplayerAPI and its own 3D world, so their
## sessions talk over real ENet and their worlds don't share physics.

const SessionScript := preload("res://src/net/session.gd")
const WORLD_SCENE := "res://src/world/world.tscn"
const SEED := 20260930  ## Every test world's seed, so tests don't depend on luck.

var host: SessionScript           ## Set by sail_together, like the three below.
var client: SessionScript
var host_world: Node3D
var client_world: Node3D

var _branches: Array[Node] = []


func after_each() -> void:
	for branch in _branches:
		var session := branch.get_node_or_null("Session") as SessionScript
		if session:
			session.leave()
		else:
			branch.multiplayer.multiplayer_peer.close()
		get_tree().set_multiplayer(null, branch.get_path())


## A branch with its own MultiplayerAPI and 3D world, so several peers can run in one process.
func make_branch(branch_name: String) -> Node:
	var branch := SubViewport.new()
	branch.name = branch_name
	branch.own_world_3d = true
	branch.size = Vector2i(2, 2)
	branch.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(branch)
	get_tree().set_multiplayer(SceneMultiplayer.new(), branch.get_path())
	_branches.append(branch)
	return branch


## A Session under its own branch. script lets a test use a changed Session.
func make_session(branch_name: String, script: GDScript = SessionScript) -> SessionScript:
	var branch := make_branch(branch_name)
	var session: SessionScript = script.new()
	session.name = "Session"
	session.log_enabled = false
	session.requested_seed = SEED
	session.discovery_port = free_port()  # each its own, so tests never answer each other's queries
	branch.add_child(session)
	return session


## A random port below the ephemeral range (32768 and up on Linux, 49152 on
## Windows), where other programs' UDP sockets could already hold it.
func free_port() -> int:
	return 20000 + randi() % 10000


## Hosts on a fresh port, joins it, and waits until both sides have the full roster.
func host_and_join(host: SessionScript, client: SessionScript, guest_name := "Guest") -> bool:
	var port := free_port()
	if host.host("Host", port) != OK or client.join(guest_name, "127.0.0.1", port) != OK:
		return false
	return await wait_until(func() -> bool: return client.players.size() == 2 and host.players.size() == 2, 5.0)


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


## A world for session, next to it in its branch, as Game loads one next to the
## Session autoload.
func add_world(session: SessionScript) -> Node3D:
	var world: Node3D = (load(WORLD_SCENE) as PackedScene).instantiate()
	session.get_parent().add_child(world)
	return world


## A solo game's world: the starter ship with Ann aboard.
func solo_world() -> Node3D:
	var session := make_session("Solo")
	session.start_solo("Ann")
	return add_world(session)


## Frees world's streamer (at the end of the frame), so no islands load, and
## returns open sky at altitude: the first of (1000 k, altitude, 7000 - 1000 k) and
## (-1000 k, altitude, 7000 - 1000 k), k = 1 to 6, at least 1,500 m from every
## town's dock.
func open_sky(world: Node3D, altitude: float) -> Vector3:
	world.streamer.queue_free()
	world.streamer = null
	for k in range(1, 7):
		for side in [1, -1]:
			var spot := Vector3(side * 1000.0 * k, altitude, 7000.0 - 1000.0 * k)
			if world.gen.towns.all(func(town: Dictionary) -> bool: return (town["dock"] as Vector3).distance_to(spot) >= 1500.0):
				return spot
	assert_true(false, "open sky near the start")
	return Vector3(0, altitude, 0)


## Runs seconds of physics ticks in real time, calling each_tick(tick) ahead of
## each tick when given. Under --fixed-fps frames otherwise run as fast as they
## can, and a game in another process, or ENet's own timers, wouldn't keep pace.
## Use it as: await play(...)
func play(seconds: float, each_tick := Callable()) -> void:
	var start := Time.get_ticks_usec()
	for tick in roundi(seconds * Engine.physics_ticks_per_second):
		if each_tick.is_valid():
			each_tick.call(tick)
		await get_tree().physics_frame
		_keep_pace(start, tick + 1)


## Like wait_until, but ticking in real time as play() does. Use it as: await play_until(...)
func play_until(condition: Callable, timeout: float) -> bool:
	var start := Time.get_ticks_usec()
	var tick := 0
	while not condition.call():
		if Time.get_ticks_usec() - start > timeout * 1000000.0:
			return false
		await get_tree().physics_frame
		tick += 1
		_keep_pace(start, tick)
	return true


## Presses action for player, as a key press would.
func press(player: PlayerController, action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	player._unhandled_input(event)


## Waits until ticks physics ticks' worth of real time has passed since start.
func _keep_pace(start: int, ticks: int) -> void:
	var ahead := start + int(ticks * 1000000.0 / Engine.physics_ticks_per_second) - Time.get_ticks_usec()
	if ahead > 0:
		OS.delay_usec(ahead)
