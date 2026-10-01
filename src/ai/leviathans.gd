class_name Leviathans
extends Node
## The world's leviathans (spec §3.5), named "Leviathans" beside the Sync and the
## Ledger. The server spawns them where its region table says (Campaign.REGIONS),
## thinks for them, takes far ones away and pays for the slain; it tells every
## machine, and clients draw them WorldSync.DELAY behind, as they draw ships.

const SEND_EVERY := 6       ## Physics ticks between snapshots: 10 Hz at 60 ticks a second.
const ROAM_EVERY := 30.0    ## s between the server's roams.
const NEAR := 2000.0        ## m. Leviathans within this of a ship count toward her region's limit.
const MAX := 4              ## The most roaming leviathans in the world at once.
const DISTANCE := 900.0     ## m from a ship that a roaming leviathan comes in.

var sync: WorldSync
var beasts: Dictionary = {}  ## id -> Leviathan.

var _visuals: bool
var _next_id := 1
var _tick := 0
var _buffers: Dictionary = {}  ## Client: id -> SnapshotBuffer.


func _init(world_sync: WorldSync, with_visuals: bool) -> void:
	name = "Leviathans"
	sync = world_sync
	_visuals = with_visuals


func _ready() -> void:
	sync.peer_entered.connect(_on_peer_entered)


## Server: a leviathan of kind at at, facing facing (as Ship.heading() counts), and
## everyone in the world is told.
func spawn(kind: String, at: Vector3, facing: float) -> Leviathan:
	var id := _next_id
	_next_id += 1
	var beast := _add(id, kind, at, facing, true)
	_tell_all(&"_beast_added", [sync.now(), _entry(id)])
	return beast


## Server: takes beast away, and tells everyone.
func remove(beast: Leviathan) -> void:
	var id: Variant = beasts.find_key(beast)
	if id == null:
		return
	_forget(id)
	_tell_all(&"_beast_removed", [id])


## Server: a shot of ammo from ship by hit beast. A leviathan slain pays the players
## near it.
func shot(beast: Leviathan, ammo: String, by: Ship) -> void:
	if beast.mood == "slain":
		return
	beast.hurt(Leviathan.damage_of(ammo), by)
	_tell_all(&"_beast_hurt", [beasts.find_key(beast), beast.hp])
	if beast.mood == "slain" and sync.ledger != null:
		sync.ledger.reward_near(beast.global_position, Economy.LEVIATHAN_REWARD,
				"The leviathan falls. +%d crowns." % Economy.LEVIATHAN_REWARD)


## Server, every ROAM_EVERY when the session has leviathans: for each crewed ship (not
## a pirate, wreck or test flight) in a region with leviathans, while fewer than its
## limit are within NEAR of her and fewer than MAX roam the world, one may come in,
## DISTANCE away at a random angle, at her height (kept between Leviathan.LOW and HIGH),
## swimming across her path.
func _roam() -> void:
	if not sync.session.is_server() or not sync.session.leviathans:
		return
	for ship in sync.crewed_ships():
		if ship.pirate or ship.is_wreck() or ship.test:
			continue
		var here := ship.global_position
		var odds: Dictionary = Campaign.of(here)
		var roaming := _roaming()
		var near := roaming.filter(func(beast: Leviathan) -> bool: return beast.global_position.distance_to(here) <= NEAR)
		if near.size() >= odds["leviathans"] or roaming.size() >= MAX:
			continue
		if sync.rng.randf() < odds["spawn"]:
			var angle := sync.rng.randf() * TAU
			var at := here + Vector3(cos(angle), 0.0, sin(angle)) * DISTANCE
			at.y = clampf(here.y, Leviathan.LOW, Leviathan.HIGH)
			spawn("leviathan", at, wrapf(ship.heading() + PI / 2.0, -PI, PI))


## Server, every second: a leviathan further than WorldSync.FAR from every player goes.
func _upkeep() -> void:
	var players := sync.player_positions()
	for beast: Leviathan in beasts.values():
		if players.all(func(at: Vector3) -> bool: return at.distance_to(beast.global_position) > WorldSync.FAR):
			remove(beast)


## The roaming leviathans (not the Warden), alive.
func _roaming() -> Array:
	return beasts.values().filter(func(beast: Leviathan) -> bool: return beast.kind == "leviathan" and beast.mood != "slain")


func _physics_process(_delta: float) -> void:
	if sync.session.mode == WorldSync.SessionScript.Mode.NONE:
		return
	if not sync.session.is_server():
		var shown_at := sync.now() - WorldSync.DELAY
		for id: int in _buffers:
			var at: Dictionary = (_buffers[id] as SnapshotBuffer).sample(shown_at)
			var beast: Leviathan = beasts[id]
			beast.global_transform = Transform3D(Basis(at["rotation"] as Quaternion), at["position"])
			beast.velocity = at["velocity"]
		return
	_tick += 1
	var ticks := Engine.physics_ticks_per_second
	for beast: Leviathan in beasts.values():
		if beast.gone():
			remove(beast)
	if _tick % ticks == 0:
		_upkeep()
	if _tick % roundi(ROAM_EVERY * ticks) == 0:
		_roam()
	if _tick % SEND_EVERY == 0 and not beasts.is_empty():
		var states := beasts.keys().map(func(id: int) -> Array:
			var beast: Leviathan = beasts[id]
			return [id, beast.global_position, beast.velocity, beast.heading, Leviathan.MOODS.find(beast.mood)])
		for peer in sync.peers_in_world():
			_beasts.rpc_id(peer, sync.now(), states)


## A leviathan as the network carries it: [id, kind, position, velocity, heading, hp, mood].
func _entry(id: int) -> Array:
	var beast: Leviathan = beasts[id]
	return [id, beast.kind, beast.global_position, beast.velocity, beast.heading, beast.hp, Leviathan.MOODS.find(beast.mood)]


func _add(id: int, kind: String, at: Vector3, facing: float, simulated: bool) -> Leviathan:
	var beast := Leviathan.new(sync, kind, _visuals)
	beast.name = "Leviathan%d" % id
	beast.simulated = simulated
	beast.position = at
	beast.heading = facing
	beasts[id] = beast
	add_child(beast)
	return beast


func _forget(id: int) -> void:
	var beast: Leviathan = beasts[id]
	beasts.erase(id)
	_buffers.erase(id)
	beast.queue_free()


func _tell_all(method: StringName, args: Array) -> void:
	for peer in sync.peers_in_world():
		rpc_id.callv([peer, method] + args)


## Server: a late joiner hears of every leviathan, after the world.
func _on_peer_entered(peer: int) -> void:
	for id: int in beasts:
		_beast_added.rpc_id(peer, sync.now(), _entry(id))


static func _is_finite_point(value: Variant) -> bool:
	return value is Vector3 and (value as Vector3).is_finite()


static func _is_angle(value: Variant) -> bool:
	return value is float and is_finite(value)


static func _is_mood(value: Variant) -> bool:
	return value is int and value >= 0 and value < Leviathan.MOODS.size()


## Server -> clients: a leviathan came, as an entry (see _entry), at time.
@rpc("authority", "call_remote", "reliable", 0)
func _beast_added(time: Variant, entry: Variant) -> void:
	if sync.session.is_server() or not sync._is_time(time) or not entry is Array or entry.size() != 7:
		return
	var id: Variant = entry[0]
	var kind: Variant = entry[1]
	if not id is int or beasts.has(id) or not kind is String or not Leviathan.KINDS.has(kind):
		return
	if not _is_finite_point(entry[2]) or not _is_finite_point(entry[3]) or not _is_angle(entry[4]) or not _is_mood(entry[6]):
		return
	if not entry[5] is int or entry[5] < 0 or entry[5] > Leviathan.KINDS[kind]["hp"]:
		return
	var beast := _add(id, kind, entry[2], entry[4], false)
	beast.hp = entry[5]
	beast.mood = Leviathan.MOODS[entry[6]]
	var buffer := SnapshotBuffer.new()
	buffer.push(time, entry[2], entry[3], Quaternion(Vector3.UP, entry[4]))
	_buffers[id] = buffer


## Server -> clients: leviathan id is gone.
@rpc("authority", "call_remote", "reliable", 0)
func _beast_removed(id: Variant) -> void:
	if not sync.session.is_server() and id is int and beasts.has(id):
		_forget(id)


## Server -> clients: every leviathan as [id, position, velocity, heading, mood], at time.
@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _beasts(time: Variant, states: Variant) -> void:
	if sync.session.is_server() or not sync._is_time(time) or not states is Array:
		return
	for state: Variant in states:
		if not state is Array or state.size() != 5 or not state[0] is int or not _buffers.has(state[0]):
			continue
		if not _is_finite_point(state[1]) or not _is_finite_point(state[2]) or not _is_angle(state[3]) or not _is_mood(state[4]):
			continue
		(_buffers[state[0]] as SnapshotBuffer).push(time, state[1], state[2], Quaternion(Vector3.UP, state[3]))
		var beast: Leviathan = beasts[state[0]]
		beast.heading = state[3]
		beast.mood = Leviathan.MOODS[state[4]]


## Server -> clients: leviathan id has hp hit points now.
@rpc("authority", "call_remote", "reliable", 0)
func _beast_hurt(id: Variant, hp: Variant) -> void:
	if sync.session.is_server() or not id is int or not beasts.has(id) or not hp is int:
		return
	var beast: Leviathan = beasts[id]
	if hp >= 0 and hp <= Leviathan.KINDS[beast.kind]["hp"]:
		beast.hp = hp
