class_name WorldSync
extends Node
## Carries a world's traffic between the server and its clients (spec §4.6). One
## lives in each world, as World/Sync, so every world RPC arrives in one place to be
## checked.
##
## The server flies the ships. When a client's world has loaded it asks to enter;
## the server sends every ship (blocks and transform) and from then on sends
## snapshots at 30 Hz. Clients keep frozen copies of the ships and draw them DELAY
## seconds in the past on the server's clock, along SnapshotBuffer curves, so late
## or lost packets don't show.
##
## Each player walks their own crew member and reports where it is in ship space
## at 30 Hz (spec §4.5). The server checks each report, stamps it with its own
## clock and passes it on. Everyone draws everyone else as a CrewAvatar, DELAY
## behind, on their ship as it's drawn.

signal ship_added(ship: Ship)

const SessionScript := preload("res://src/net/session.gd")
const SEND_EVERY := 2  ## Physics ticks between snapshots: 30 Hz at 60 ticks a second.
const DELAY := 0.1     ## Seconds in the past that clients draw what the server sent.
const CLOCK_EASE := 0.1  ## How far a client's clock moves toward each snapshot's time.
const CREW_REACH := 35.0     ## m. Crew reported further than this from their ship's blocks are refused.
const CREW_MAX_SPEED := 50.0 ## m/s. Likewise for crew reported moving faster.

var session: Node
var ships: Dictionary = {}  ## Ship id -> Ship.
var player: PlayerController  ## This machine's player, whose crew it reports. Null when there's none.

var _time := 0.0            ## Seconds of physics since this world began.
var _offset := 0.0          ## Client: the server's clock minus ours.
var _synced := false        ## Client: _offset has been set.
var _tick := 0
var _next_id := 1
var _in_world: Dictionary = {}  ## Server: peers whose world has loaded (peer id -> true).
var _buffers: Dictionary = {}   ## Client: ship id -> SnapshotBuffer.
var _crew: Dictionary = {}      ## Other players' crew: peer id -> {"ship": id, "buffer": SnapshotBuffer, "pitch": float}.
var _avatars: Dictionary = {}   ## Peer id -> CrewAvatar.


func _init(world_session: Node) -> void:
	session = world_session
	name = "Sync"


func _ready() -> void:
	multiplayer.peer_disconnected.connect(func(peer: int) -> void: _in_world.erase(peer))
	if not session.is_server():
		_enter_world.rpc_id(1)


## Seconds since this world began on the server. Clients follow the server's clock.
func now() -> float:
	return _time + _offset


## How peer's crew member is drawn here, or null.
func avatar_of(peer: int) -> CrewAvatar:
	return _avatars.get(peer)


## Server: puts a new ship in the world.
func add_ship(grid: ShipGrid, at: Transform3D) -> Ship:
	# ponytail: ships added after peers have entered aren't sent to them. Stage 4's
	# shipyard spawns ships mid-game and will send them.
	var ship := _add(_next_id, grid, at, true)
	_next_id += 1
	return ship


func _add(id: int, grid: ShipGrid, at: Transform3D, simulated: bool) -> Ship:
	var ship := Ship.new(grid)
	ship.name = "Ship%d" % id
	ship.simulated = simulated
	ship.transform = at
	ships[id] = ship
	get_parent().add_child(ship)
	ship_added.emit(ship)
	return ship


func _physics_process(delta: float) -> void:
	if session.mode == SessionScript.Mode.NONE:
		return  # the session has just ended, and this world goes next
	var sending := _tick % SEND_EVERY == 0
	_tick += 1
	var mine := _my_crew() if sending else []
	if session.is_server():
		# Stamp snapshots before the clock ticks on: they hold the ships as the last
		# physics step left them, which is where they were at _time.
		if sending and not _in_world.is_empty():
			var states := _ship_states()
			for peer: int in _in_world:
				_ships.rpc_id(peer, _time, states)
				if not mine.is_empty():
					_crew_moved.rpc_id(peer, multiplayer.get_unique_id(), mine[0], _time, mine[1], mine[2], mine[3], mine[4])
		_time += delta
		return
	if not mine.is_empty():
		_crew_report.rpc_id(1, mine[0], mine[1], mine[2], mine[3], mine[4])
	_time += delta
	var shown_at := now() - DELAY
	for id: int in _buffers:
		var at: Dictionary = (_buffers[id] as SnapshotBuffer).sample(shown_at)
		(ships[id] as Ship).global_transform = Transform3D(Basis(at["rotation"] as Quaternion), at["position"])


## Places the other players' avatars on their ships, as those are drawn.
func _process(_delta: float) -> void:
	var shown_at := now() + Engine.get_physics_interpolation_fraction() / Engine.physics_ticks_per_second - DELAY
	for peer: int in _avatars:
		var heard: Dictionary = _crew[peer]
		var at := (heard["buffer"] as SnapshotBuffer).sample(shown_at)
		var ship: Ship = ships[heard["ship"]]
		var avatar: CrewAvatar = _avatars[peer]
		avatar.global_transform = ship.get_global_transform_interpolated() * Transform3D(Basis(at["rotation"] as Quaternion), at["position"])
		avatar.look(heard["pitch"])


## This machine's crew member as [ship id, position, velocity, yaw, pitch], or [].
func _my_crew() -> Array:
	if player == null:
		return []
	var crew := player.crew
	var id: Variant = ships.find_key(crew.ship)
	if id == null:
		return []
	return [id, crew.position, crew.velocity, crew.look_yaw, player.look_pitch]


## Records where peer's crew member was at time, and gives them an avatar.
func _hear_crew(peer: int, ship_id: int, time: float, position: Vector3, velocity: Vector3, yaw: float, pitch: float) -> void:
	var heard: Dictionary = _crew.get(peer, {})
	if heard.get("ship") != ship_id:
		heard = {"ship": ship_id, "buffer": SnapshotBuffer.new(), "pitch": 0.0}
		_crew[peer] = heard
	# ponytail: two reports heard in one frame share a time, and the second is
	# dropped. The next comes 33 ms later; stamp on the sender's clock if it shows.
	(heard["buffer"] as SnapshotBuffer).push(time, position, velocity, Quaternion(Vector3.UP, wrapf(yaw, -PI, PI)))
	heard["pitch"] = clampf(pitch, -1.5, 1.5)
	if not _avatars.has(peer):
		var avatar := CrewAvatar.new(session.players[peer]["name"])
		avatar.name = "Crew%d" % peer
		_avatars[peer] = avatar
		get_parent().add_child(avatar)


## Each ship as [id, position, rotation, velocity, spin, throttle, rudder, trim,
## autopilot, target_heading, target_altitude].
func _ship_states() -> Array:
	var states := []
	for id: int in ships:
		var ship: Ship = ships[id]
		var helm := ship.helm
		states.append([id, ship.global_position, ship.global_basis.get_rotation_quaternion(), ship.linear_velocity,
				ship.angular_velocity, ship.throttle, ship.rudder, ship.trim, helm != null and helm.autopilot,
				helm.target_heading if helm else 0.0, helm.target_altitude if helm else 0.0])
	return states


## Client: moves our clock toward the server's, from a time it just sent.
func _hear_clock(server_time: float) -> void:
	var offset := server_time - _time
	# ponytail: packets arrive a little late, by a varying amount, so each only
	# nudges the clock. Estimate the round trip if drawing ever looks behind.
	_offset = lerpf(_offset, offset, CLOCK_EASE) if _synced else offset
	_synced = true


# --- RPCs. Everything received is checked: it came from another machine. ---

## Client -> server: my world has loaded; send me the ships.
@rpc("any_peer", "call_remote", "reliable", 0)
func _enter_world() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not session.is_server() or not session.players.has(peer) or _in_world.has(peer):
		return
	_in_world[peer] = true
	var entries := []
	for id: int in ships:
		var ship: Ship = ships[id]
		entries.append([id, ship.grid.to_blocks(), ship.global_transform])
	_world.rpc_id(peer, _time, entries)


## Server -> client: the server's clock and every ship, as [id, blocks, transform].
@rpc("authority", "call_remote", "reliable", 0)
func _world(time: Variant, entries: Variant) -> void:
	if session.is_server() or not _is_time(time) or not entries is Array:
		return
	_hear_clock(time)
	for entry: Variant in entries:
		if not entry is Array or entry.size() != 3 or not entry[0] is int or ships.has(entry[0]):
			continue
		if not entry[2] is Transform3D or not (entry[2] as Transform3D).is_finite():
			continue
		var grid := ShipGrid.from_blocks(entry[1])
		if grid == null:
			push_warning("The host sent ship %d with blocks that don't make a ship; leaving it out." % entry[0])
			continue
		var at: Transform3D = (entry[2] as Transform3D).orthonormalized()
		var buffer := SnapshotBuffer.new()
		buffer.push(time, at.origin, Vector3.ZERO, at.basis.get_rotation_quaternion())
		_buffers[entry[0]] = buffer
		_add(entry[0], grid, at, false)


## Server -> clients: a snapshot of every ship (see _ship_states), at time.
@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _ships(time: Variant, states: Variant) -> void:
	if session.is_server() or not _is_time(time) or not states is Array:
		return
	_hear_clock(time)
	for state: Variant in states:
		if not _is_ship_state(state) or not ships.has(state[0]):
			continue
		(_buffers[state[0]] as SnapshotBuffer).push(time, state[1], state[3], state[2], state[4])
		var ship: Ship = ships[state[0]]
		ship.throttle = state[5]
		ship.rudder = state[6]
		ship.trim = state[7]
		if ship.helm != null:
			ship.helm.autopilot = state[8]
			ship.helm.target_heading = state[9]
			ship.helm.target_altitude = state[10]


## Client -> server: where my crew member is, in ship ship_id's space.
@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _crew_report(ship_id: Variant, position: Variant, velocity: Variant, yaw: Variant, pitch: Variant) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not session.is_server() or not _in_world.has(peer) or not _is_crew_state(ship_id, position, velocity, yaw, pitch):
		return
	var ship: Ship = ships[ship_id]
	if (velocity as Vector3).length() > CREW_MAX_SPEED or not ship.bounds.grow(CREW_REACH).has_point(position):
		return
	_hear_crew(peer, ship_id, _time, position, velocity, yaw, pitch)
	for other: int in _in_world:
		if other != peer:
			_crew_moved.rpc_id(other, peer, ship_id, _time, position, velocity, yaw, pitch)


## Server -> clients: where peer's crew member was at time, in ship ship_id's space.
@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _crew_moved(peer: Variant, ship_id: Variant, time: Variant, position: Variant, velocity: Variant, yaw: Variant, pitch: Variant) -> void:
	if session.is_server() or not peer is int or peer == multiplayer.get_unique_id() or not session.players.has(peer):
		return
	if not _is_time(time) or not _is_crew_state(ship_id, position, velocity, yaw, pitch):
		return
	_hear_crew(peer, ship_id, time, position, velocity, yaw, pitch)


func _is_crew_state(ship_id: Variant, position: Variant, velocity: Variant, yaw: Variant, pitch: Variant) -> bool:
	return ship_id is int and ships.has(ship_id) and position is Vector3 and (position as Vector3).is_finite() \
			and velocity is Vector3 and (velocity as Vector3).is_finite() \
			and yaw is float and is_finite(yaw) and pitch is float and is_finite(pitch)


static func _is_time(value: Variant) -> bool:
	return value is float and is_finite(value)


static func _is_ship_state(state: Variant) -> bool:
	if not state is Array or state.size() != 11 or not state[0] is int or not state[8] is bool:
		return false
	for i in [1, 3, 4]:
		if not state[i] is Vector3 or not (state[i] as Vector3).is_finite():
			return false
	if not state[2] is Quaternion or not (state[2] as Quaternion).is_normalized():
		return false
	for i in [5, 6, 7, 9, 10]:
		if not state[i] is float or not is_finite(state[i]):
			return false
	return true
