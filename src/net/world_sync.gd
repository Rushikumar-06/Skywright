class_name WorldSync
extends Node
## Carries a world's traffic between the server and its clients (spec §4.6). One
## lives in each world, as World/Sync, so every world RPC arrives in one place to be
## checked.
##
## The server flies the ships. When a client's world has loaded it asks to enter;
## the server sends every ship (compressed blocks, paint, transform, pilot, captain
## and test flag) and from then on sends snapshots at 30 Hz. Clients keep frozen
## copies of the ships and draw them DELAY seconds in the past on the server's
## clock, along SnapshotBuffer curves, so late or lost packets don't show. Ships
## the server adds or removes mid-game are sent to everyone in the world; the
## World moves its player off a ship before it goes.
##
## Each player walks their own crew member and reports where it is in ship space
## at 30 Hz (spec §4.5). The server checks each report, stamps it with its own
## clock and passes it on. Everyone draws everyone else as a CrewAvatar, DELAY
## behind, on their ship as it's drawn.
##
## Stations belong to the server. A client's helm passes asks on here; the server
## takes the helm for the asker only if they last said they were aboard and in
## reach, and tells everyone who has it. The pilot's keys come here at 30 Hz.
##
## When someone leaves the roster, everyone forgets their crew member, and the
## server frees their stations. A dedicated server anchors its ships while nobody
## is aboard, so they don't drift off in the wind for hours.

signal ship_added(ship: Ship)
## ship has left ships and is about to be freed. Its crew board successor, if not null.
signal ship_removed(ship: Ship, successor: Ship)

const SessionScript := preload("res://src/net/session.gd")
const SEND_EVERY := 2  ## Physics ticks between snapshots: 30 Hz at 60 ticks a second.
const DELAY := 0.1     ## Seconds in the past that clients draw what the server sent.
const CLOCK_EASE := 0.1  ## How far a client's clock moves toward each snapshot's time.
const CREW_REACH := 35.0     ## m. Crew reported further than this from their ship's blocks are refused.
const CREW_MAX_SPEED := 50.0 ## m/s. Likewise for crew reported moving faster.
const REACH_SLACK := 0.5     ## m. Allowance on the helm's reach for where a client last said it was.
const KEYS_GO_STALE := 0.25  ## s. A remote pilot's keys count as let go when none come for this long.

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
var _crew: Dictionary = {}      ## Other players' crew: peer id -> {"ship": id, "buffer": SnapshotBuffer, "at": Vector3, "pitch": float}.
var _avatars: Dictionary = {}   ## Peer id -> CrewAvatar.
var _keys_heard: Dictionary = {}  ## Server: ship id -> _time its pilot's keys last came.


func _init(world_session: Node) -> void:
	session = world_session
	name = "Sync"


func _ready() -> void:
	session.players_changed.connect(_on_roster_changed)
	ship_added.connect(func(_ship: Ship) -> void: _anchor_if_empty())
	if not session.is_server():
		_enter_world.rpc_id(1)


## Seconds since this world began on the server. Clients follow the server's clock.
func now() -> float:
	return _time + _offset


## How peer's crew member is drawn here, or null.
func avatar_of(peer: int) -> CrewAvatar:
	return _avatars.get(peer)


## Server: puts a new ship in the world, captain's (0 for nobody's), with pilot at
## its helm, and tells everyone in the world.
func add_ship(grid: ShipGrid, at: Transform3D, captain := 0, test := false, pilot := 0) -> Ship:
	var id := _next_id
	_next_id += 1
	var ship := _add(id, grid, at, true, captain, test, pilot)
	ship_added.emit(ship)
	var entry := _entry(id)
	for peer: int in _in_world:
		_ship_added.rpc_id(peer, _time, entry)
	return ship


## Server: takes ship out of the world, and tells everyone. Its crew board successor.
func remove_ship(ship: Ship, successor: Ship = null) -> void:
	var id := id_of(ship)
	if id == 0:
		return
	for peer: int in _in_world:
		_ship_removed.rpc_id(peer, id, id_of(successor))
	_remove(id, successor)


## ship's id, or 0 if it isn't in this world.
func id_of(ship: Ship) -> int:
	var id: Variant = ships.find_key(ship)
	return id if id != null else 0


## The ship to board when there's no other reason to pick one: the host's (captain
## 1), else nobody's (a dedicated server's), else anyone's, a test flight last.
func home_ship() -> Ship:
	var home: Ship = null
	var best := 4
	for ship: Ship in ships.values():
		var rank := 3 if ship.test else 0 if ship.captain == 1 else 1 if ship.captain == 0 else 2
		if rank < best:
			home = ship
			best = rank
	return home


## Adds a ship. The pilot is set before the helm's signals are connected, so it
## doesn't go out as a change.
func _add(id: int, grid: ShipGrid, at: Transform3D, simulated: bool, captain: int, test: bool, pilot: int) -> Ship:
	var ship := Ship.new(grid)
	ship.name = "Ship%d" % id
	ship.simulated = simulated
	ship.transform = at
	ship.captain = captain
	ship.test = test
	ships[id] = ship
	get_parent().add_child(ship)
	if ship.helm != null:
		ship.helm.pilot = pilot
		ship.helm.asked.connect(_on_asked.bind(id))
		ship.helm.pilot_changed.connect(_on_pilot_changed.bind(id))
	return ship


## Takes ship id out of the world, with everyone's crew on it, after the World has
## moved its player off.
func _remove(id: int, successor: Ship) -> void:
	var ship: Ship = ships[id]
	ships.erase(id)
	_buffers.erase(id)
	_keys_heard.erase(id)
	for peer: int in _crew.keys():
		if _crew[peer]["ship"] == id:
			_forget_crew(peer)
	ship_removed.emit(ship, successor if id_of(successor) != 0 else null)
	get_parent().remove_child(ship)
	ship.queue_free()


## A ship as the network carries it: [id, blocks, paint, transform, pilot, captain, test].
func _entry(id: int) -> Array:
	var ship: Ship = ships[id]
	return [id, ship.grid.to_bytes(), ship.grid.paint_names(), ship.global_transform,
			ship.helm.pilot if ship.helm else 0, ship.captain, ship.test]


## Forgets everyone no longer on the roster, and frees the stations they held.
func _on_roster_changed() -> void:
	for peer: int in _in_world.keys():
		if not session.players.has(peer):
			_in_world.erase(peer)
	for peer: int in _crew.keys():
		if not session.players.has(peer):
			_forget_crew(peer)
	# Freeing stations tells everyone, so wait for the end of the frame: others may
	# have left in the same poll, and their connections are already gone.
	_free_stations.call_deferred()
	_anchor_if_empty()


## Stops drawing peer's crew member.
func _forget_crew(peer: int) -> void:
	_crew.erase(peer)
	if _avatars.has(peer):
		(_avatars[peer] as CrewAvatar).queue_free()
		_avatars.erase(peer)


## Server: frees the stations of anyone no longer on the roster.
func _free_stations() -> void:
	if not session.is_server():
		return
	for ship: Ship in ships.values():
		if ship.helm != null and ship.helm.pilot != 0 and not session.players.has(ship.helm.pilot):
			ship.helm.leave(ship.helm.pilot)


## Server: holds every ship still, engines stopped, while nobody is aboard.
func _anchor_if_empty() -> void:
	if not session.is_server():
		return
	var anchor: bool = session.players.is_empty()
	for ship: Ship in ships.values():
		if anchor and not ship.freeze:
			ship.throttle = 0.0
			ship.rudder = 0.0
			if ship.helm != null:
				ship.helm.autopilot = false
			ship.linear_velocity = Vector3.ZERO
			ship.angular_velocity = Vector3.ZERO
		ship.freeze = anchor


## Client: a helm here was asked for something; the server decides.
func _on_asked(what: String, on: bool, id: int) -> void:
	_request.rpc_id(1, id, what, on)


## Server: tell everyone who has the helm now.
func _on_pilot_changed(id: int) -> void:
	if session.is_server():
		for peer: int in _in_world:
			_pilot.rpc_id(peer, id, (ships[id] as Ship).helm.pilot)


func _physics_process(delta: float) -> void:
	if session.mode == SessionScript.Mode.NONE:
		return  # the session has just ended, and this world goes next
	var sending := _tick % SEND_EVERY == 0
	_tick += 1
	var mine := _my_crew() if sending else []
	if session.is_server():
		# Stamp snapshots before the clock ticks on: they hold the ships as the last
		# physics step left them, which is where they were at _time.
		_let_go_of_stale_keys()
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
		var helm := player.ship.helm
		if helm != null and helm.pilot == multiplayer.get_unique_id():
			_helm_keys.rpc_id(1, mine[0], helm.throttle_input, helm.rudder_input, helm.climb_input)
	_time += delta
	var shown_at := now() - DELAY
	for id: int in _buffers:
		var at: Dictionary = (_buffers[id] as SnapshotBuffer).sample(shown_at)
		(ships[id] as Ship).global_transform = Transform3D(Basis(at["rotation"] as Quaternion), at["position"])


## Server: a remote pilot whose keys stop coming (a hung game, dead Wi-Fi) has let
## go of them. Their connection only counts as lost after Session.DROP_AFTER, and
## until then their last keys would keep steering.
func _let_go_of_stale_keys() -> void:
	for id: int in ships:
		var helm := (ships[id] as Ship).helm
		if helm == null or helm.pilot == 0 or helm.pilot == multiplayer.get_unique_id():
			continue
		if _time - _keys_heard.get(id, -INF) > KEYS_GO_STALE:
			helm.throttle_input = 0.0
			helm.rudder_input = 0.0
			helm.climb_input = 0.0


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
	var id := id_of(crew.ship)
	if id == 0:
		return []
	return [id, crew.position, crew.velocity, crew.look_yaw, player.look_pitch]


## Records where peer's crew member was at time, and gives them an avatar.
func _hear_crew(peer: int, ship_id: int, time: float, position: Vector3, velocity: Vector3, yaw: float, pitch: float) -> void:
	var heard: Dictionary = _crew.get(peer, {})
	if heard.get("ship") != ship_id:
		heard = {"ship": ship_id, "buffer": SnapshotBuffer.new(), "at": position, "pitch": 0.0}
		_crew[peer] = heard
	# ponytail: two reports heard in one frame share a time, and the second is
	# dropped. The next comes 33 ms later; stamp on the sender's clock if it shows.
	(heard["buffer"] as SnapshotBuffer).push(time, position, velocity, Quaternion(Vector3.UP, wrapf(yaw, -PI, PI)))
	heard["at"] = position
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
	_world.rpc_id(peer, _time, ships.keys().map(_entry))


## Server -> client: the server's clock and every ship, as entries (see _entry).
## Every ship is added before ship_added fires for any, so home_ship() is right.
@rpc("authority", "call_remote", "reliable", 0)
func _world(time: Variant, entries: Variant) -> void:
	if session.is_server() or not _is_time(time) or not entries is Array:
		return
	_hear_clock(time)
	var added: Array[Ship] = []
	for entry: Variant in entries:
		var ship := _add_entry(entry, time)
		if ship != null:
			added.append(ship)
	for ship in added:
		ship_added.emit(ship)


## Server -> clients: a ship added mid-game, as an entry (see _entry), at time.
@rpc("authority", "call_remote", "reliable", 0)
func _ship_added(time: Variant, entry: Variant) -> void:
	if session.is_server() or not _is_time(time):
		return
	var ship := _add_entry(entry, time)
	if ship != null:
		ship_added.emit(ship)


## Server -> clients: ship id is gone. Its crew board ship successor (0 for none).
@rpc("authority", "call_remote", "reliable", 0)
func _ship_removed(id: Variant, successor: Variant) -> void:
	if session.is_server() or not id is int or not successor is int or not ships.has(id):
		return
	_remove(id, ships.get(successor))


## Client: adds the ship an entry describes, drawn from time on, or returns null
## when the entry makes no sense.
func _add_entry(entry: Variant, time: float) -> Ship:
	if not entry is Array or entry.size() != 7 or not entry[0] is int or entry[0] < 1 or ships.has(entry[0]):
		return null
	if not entry[3] is Transform3D or not (entry[3] as Transform3D).is_finite():
		return null
	var at: Transform3D = (entry[3] as Transform3D).orthonormalized()
	if not is_equal_approx(at.basis.determinant(), 1.0):
		return null  # squashed flat or mirrored: not a way to face
	if not entry[4] is int or not entry[5] is int or not entry[6] is bool:
		return null
	var grid := ShipGrid.from_bytes(entry[1])
	var paint: Variant = ShipGrid.read_paint(entry[2])
	if grid == null or paint == null:
		push_warning("The host sent ship %d with blocks or paint that don't make a ship; leaving it out." % entry[0])
		return null
	grid.paint = paint
	var buffer := SnapshotBuffer.new()
	buffer.push(time, at.origin, Vector3.ZERO, at.basis.get_rotation_quaternion())
	_buffers[entry[0]] = buffer
	return _add(entry[0], grid, at, false, entry[5], entry[6], entry[4])


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


## Client -> server: peer asks for "helm" or "autopilot" on ship ship_id, on or off.
@rpc("any_peer", "call_remote", "reliable", 0)
func _request(ship_id: Variant, what: Variant, on: Variant) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not session.is_server() or not _in_world.has(peer) or not ship_id is int or not ships.has(ship_id) or not on is bool:
		return
	var helm: Helm = (ships[ship_id] as Ship).helm
	if helm == null:
		return
	if what is String and what == "helm":
		if not on:
			helm.leave(peer)
		elif _crew.has(peer) and _crew[peer]["ship"] == ship_id and helm.in_reach(_crew[peer]["at"], REACH_SLACK):
			helm.take(peer)
	elif what is String and what == "autopilot":
		helm.ask_autopilot(peer, on)


## Client -> server: the pilot's keys at the helm of ship ship_id, each -1 to 1.
@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _helm_keys(ship_id: Variant, throttle: Variant, rudder: Variant, climb: Variant) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not session.is_server() or not ship_id is int or not ships.has(ship_id):
		return
	var helm: Helm = (ships[ship_id] as Ship).helm
	if helm == null or helm.pilot != peer:
		return
	for key: Variant in [throttle, rudder, climb]:
		if not key is float or not is_finite(key):
			return
	_keys_heard[ship_id] = _time
	helm.throttle_input = clampf(throttle, -1.0, 1.0)
	helm.rudder_input = clampf(rudder, -1.0, 1.0)
	helm.climb_input = clampf(climb, -1.0, 1.0)


## Server -> clients: peer (0 for nobody) now has the helm of ship ship_id.
@rpc("authority", "call_remote", "reliable", 0)
func _pilot(ship_id: Variant, peer: Variant) -> void:
	if session.is_server() or not ship_id is int or not ships.has(ship_id) or not peer is int:
		return
	var helm: Helm = (ships[ship_id] as Ship).helm
	if helm != null:
		helm.pilot = peer


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
