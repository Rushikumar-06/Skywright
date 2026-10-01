class_name Leviathans
extends Node
## The world's leviathans (spec §3.5), named "Leviathans" beside the Sync and the
## Ledger. The server spawns them, thinks for them and pays for the slain.

var sync: WorldSync
var beasts: Dictionary = {}  ## id -> Leviathan.

var _visuals: bool
var _next_id := 1


func _init(world_sync: WorldSync, with_visuals: bool) -> void:
	name = "Leviathans"
	sync = world_sync
	_visuals = with_visuals


## Server: a leviathan of kind at at, facing facing (as Ship.heading() counts).
func spawn(kind: String, at: Vector3, facing: float) -> Leviathan:
	var beast := Leviathan.new(sync, kind, _visuals)
	beast.name = "Leviathan%d" % _next_id
	beast.position = at
	beast.heading = facing
	beasts[_next_id] = beast
	_next_id += 1
	add_child(beast)
	return beast


## Server: takes beast away.
func remove(beast: Leviathan) -> void:
	var id: Variant = beasts.find_key(beast)
	if id == null:
		return
	beasts.erase(id)
	beast.queue_free()


## Server: a shot of ammo from ship by hit beast. A leviathan slain pays the players
## near it.
func shot(beast: Leviathan, ammo: String, by: Ship) -> void:
	if beast.mood == "slain":
		return
	beast.hurt(Leviathan.damage_of(ammo), by)
	if beast.mood == "slain" and sync.ledger != null:
		sync.ledger.reward_near(beast.global_position, Economy.LEVIATHAN_REWARD,
				"The leviathan falls. +%d crowns." % Economy.LEVIATHAN_REWARD)


func _physics_process(_delta: float) -> void:
	if not sync.session.is_server():
		return
	for beast: Leviathan in beasts.values():
		if beast.gone():
			remove(beast)
