class_name Helm
extends Node
## The helm station (spec §3.4). Whoever holds it steers: throttle and trim stay
## where they're set, and the rudder follows A and D and centres when let go. The
## autopilot holds the heading and altitude it was switched on at (A, D, climb and
## descend move those targets instead), so a solo player can leave the helm. An
## empty helm with the autopilot off leaves the controls alone.
##
## The pilot is a player's peer id. The server's helm decides who gets it; a
## client's copy passes each ask on through asked, and WorldSync sets its pilot
## from the server's answer.

signal pilot_changed                   ## pilot changed.
signal asked(what: String, on: bool)   ## A client's copy: "helm" or "autopilot" was asked for, for the server.

const REACH := 1.8  ## Metres from the helm's block that it can be used from.

var ship: Ship
var cell: Vector3i               ## Where the helm block is, in ship space.
## The peer id of the player at the helm, or 0 for nobody.
var pilot := 0:
	set(peer):
		if peer != pilot:
			pilot = peer
			pilot_changed.emit()
var throttle_input := 0.0        ## -1 to 1: S to W, held this tick.
var rudder_input := 0.0          ## -1 to 1: A to D.
var climb_input := 0.0           ## -1 to 1: descend to climb.
var autopilot := false
var target_heading := 0.0
var target_altitude := 0.0


func _init(helm_ship: Ship, helm_cell: Vector3i) -> void:
	ship = helm_ship
	cell = helm_cell


## Puts peer at the helm. Returns false when someone else has it.
func take(peer: int) -> bool:
	if pilot != 0:
		return false
	pilot = peer
	return true


## Lets go of the helm, if peer has it. The rudder centres; throttle and trim stay.
func leave(peer: int) -> void:
	if peer == 0 or pilot != peer:
		return
	pilot = 0
	throttle_input = 0.0
	rudder_input = 0.0
	climb_input = 0.0
	if not autopilot:
		ship.rudder = 0.0


## peer asks to take the helm (on) or leave it. Decided at once on the ship that
## flies here; a client's copy asks the server.
func ask_helm(peer: int, on: bool) -> void:
	if not ship.simulated:
		asked.emit("helm", on)
	elif on:
		take(peer)
	else:
		leave(peer)


## peer asks to switch the autopilot on or off. Only the pilot may.
func ask_autopilot(peer: int, on: bool) -> void:
	if not ship.simulated:
		asked.emit("autopilot", on)
	elif pilot == peer:
		set_autopilot(on)


## Whether someone standing at where (in ship space) can use the helm.
func in_reach(where: Vector3, slack := 0.0) -> bool:
	return where.distance_to(Vector3(cell)) <= REACH + slack


## Switches the autopilot on, holding the present heading and altitude, or off.
func set_autopilot(on: bool) -> void:
	autopilot = on
	target_heading = ship.heading()
	target_altitude = ship.global_position.y


func _physics_process(delta: float) -> void:
	if not ship.simulated or (pilot == 0 and not autopilot):
		return  # a client's copy of a ship is steered on the server
	ship.throttle = clampf(ship.throttle + throttle_input * Tuning.THROTTLE_RATE * delta, Tuning.THROTTLE_MIN, 1.0)
	if not autopilot:
		ship.rudder = rudder_input
		ship.trim = clampf(ship.trim + climb_input * Tuning.TRIM_RATE * delta, Tuning.TRIM_MIN, Tuning.TRIM_MAX)
		return
	target_heading = wrapf(target_heading - rudder_input * Tuning.AUTOPILOT_TURN_RATE * delta, -PI, PI)
	target_altitude += climb_input * Tuning.AUTOPILOT_CLIMB_RATE * delta
	# Heading is counter-clockwise, and a positive rudder turns clockwise.
	var off_course := wrapf(target_heading - ship.heading(), -PI, PI)
	ship.rudder = clampf(-Tuning.AUTOPILOT_HEADING_GAIN * off_course + Tuning.AUTOPILOT_YAW_DAMPING * ship.angular_velocity.y, -1.0, 1.0)
	var off_altitude := target_altitude - ship.global_position.y
	ship.trim = clampf(ship.trim_to_float_at(target_altitude) + Tuning.AUTOPILOT_ALTITUDE_GAIN * off_altitude \
			- Tuning.AUTOPILOT_CLIMB_DAMPING * ship.linear_velocity.y, Tuning.TRIM_MIN, Tuning.TRIM_MAX)
