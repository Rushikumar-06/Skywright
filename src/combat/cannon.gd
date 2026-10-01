class_name Cannon
extends Node
## A cannon station (spec §3.4). Its gunner aims it within ARC either side of the
## way its block faces, and from PITCH_MIN to PITCH_MAX, and fires it once it's
## loaded; it then takes RELOAD seconds to load again. A cannon facing straight up
## or down fires along its facing.
##
## The gunner is a player's peer id. The server's cannon decides who mans it; a
## client's copy passes each ask on through asked, and WorldSync sets its gunner
## from the server's answer. Firing goes through fire_asked, for WorldSync.

signal gunner_changed       ## gunner changed.
signal asked(on: bool)      ## A client's copy: someone asked to man it (on) or leave it, for the server.
signal fire_asked           ## The gunner wants to fire now.

const REACH := 1.8        ## m from the cannon's block that it can be manned from.
const ARC := 0.7          ## rad it turns either side of its facing.
const PITCH_MIN := -0.17  ## rad: the lowest it points.
const PITCH_MAX := 0.61   ## rad: the highest.
const RELOAD := 4.0       ## s between shots.

var ship: Ship
var cell: Vector3i        ## Where its block is, in ship space.
## The peer id of the player manning it, or 0 for nobody.
var gunner := 0:
	set(peer):
		if peer != gunner:
			gunner = peer
			gunner_changed.emit()
var aim_yaw := 0.0        ## rad, -ARC to ARC: turned to port of its facing when positive.
var aim_pitch := 0.0      ## rad, PITCH_MIN to PITCH_MAX: raised when positive.
var ammo := "round"       ## A key of Damage.AMMO.
var reload_left := 0.0    ## s until it's loaded.

var _facing: Vector3


func _init(cannon_ship: Ship, cannon_cell: Vector3i) -> void:
	ship = cannon_ship
	cell = cannon_cell
	_facing = Blocks.facing(ship.grid.blocks[cell]["rotation"])


## The way its block faces, in ship space.
func facing() -> Vector3:
	return _facing


## The way it fires, in ship space: its facing's level part turned by aim_yaw about
## the ship's up, then raised by aim_pitch.
func direction() -> Vector3:
	var level := Vector3(_facing.x, 0.0, _facing.z)
	if level.length_squared() < 0.01:
		return _facing
	level = level.normalized().rotated(Vector3.UP, aim_yaw)
	return level * cos(aim_pitch) + Vector3.UP * sin(aim_pitch)


## Aims it along to (in ship space). False, with the aim unchanged, when that's
## outside its limits.
func aim_at(to: Vector3) -> bool:
	if to.length_squared() == 0.0 or not to.is_finite():
		return false
	var d := to.normalized()
	if Vector2(_facing.x, _facing.z).length_squared() < 0.01:
		return d.is_equal_approx(_facing)
	var yaw := wrapf(atan2(-d.x, -d.z) - atan2(-_facing.x, -_facing.z), -PI, PI)
	var pitch := asin(d.y)
	if absf(yaw) > ARC + 0.0001 or pitch < PITCH_MIN - 0.0001 or pitch > PITCH_MAX + 0.0001:
		return false
	aim_yaw = clampf(yaw, -ARC, ARC)
	aim_pitch = clampf(pitch, PITCH_MIN, PITCH_MAX)
	return true


## Mans it for peer, who lets go of any other station of hers. False when someone
## else mans it.
func take(peer: int) -> bool:
	if gunner != 0:
		return gunner == peer
	ship.release(peer)
	gunner = peer
	return true


## Lets go of it, if peer mans it.
func leave(peer: int) -> void:
	if peer != 0 and gunner == peer:
		gunner = 0


## Whether someone standing at where (in ship space) can man it.
func in_reach(where: Vector3, slack := 0.0) -> bool:
	return where.distance_to(Vector3(cell)) <= REACH + slack


## peer asks to man it (on) or leave it. Decided at once on the ship that flies
## here; a client's copy asks the server.
func ask_man(peer: int, on: bool) -> void:
	if not ship.simulated:
		asked.emit(on)
	elif on:
		take(peer)
	else:
		leave(peer)


## peer asks to fire it: fire_asked, when they man it and it's loaded.
func ask_fire(peer: int) -> void:
	if peer != 0 and gunner == peer and reload_left <= 0.0:
		fire_asked.emit()


## Loads the next kind of ammunition, in Damage.AMMO's order.
func next_ammo() -> void:
	var kinds := Damage.AMMO.keys()
	ammo = kinds[(kinds.find(ammo) + 1) % kinds.size()]


func _physics_process(delta: float) -> void:
	reload_left = maxf(0.0, reload_left - delta)
