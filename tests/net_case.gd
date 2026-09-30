class_name NetCase
extends TestCase
## Base for tests with several players in one process. Each player gets a branch:
## a SubViewport with its own MultiplayerAPI and its own 3D world, so their
## sessions talk over real ENet and their worlds don't share physics.

const SessionScript := preload("res://src/net/session.gd")
const WORLD_SCENE := "res://src/world/world.tscn"

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


## Runs seconds of physics ticks in real time, calling each_tick(tick) ahead of
## each tick when given. Under --fixed-fps frames otherwise run as fast as they
## can, and a game in another process, or ENet's own timers, wouldn't keep pace.
## Use it as: await play(...)
func play(seconds: float, each_tick := Callable()) -> void:
	var start := Time.get_ticks_usec()
	var tick_usec := 1000000.0 / Engine.physics_ticks_per_second
	for tick in roundi(seconds * Engine.physics_ticks_per_second):
		if each_tick.is_valid():
			each_tick.call(tick)
		await get_tree().physics_frame
		var ahead := int(start + (tick + 1) * tick_usec) - Time.get_ticks_usec()
		if ahead > 0:
			OS.delay_usec(ahead)
