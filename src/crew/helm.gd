class_name Helm
extends Node
## The helm station (spec §3.4). Whoever holds it steers: throttle and trim stay
## where they're set, and the rudder follows A and D and centres when let go. The
## autopilot holds the heading and altitude it was switched on at (A, D, climb and
## descend move those targets instead), so a solo player can leave the helm. An
## empty helm with the autopilot off leaves the controls alone.

var ship: Ship
var cell: Vector3i               ## Where the helm block is, in ship space.
var pilot: CrewMember = null     ## Who is at the helm, if anyone.
var throttle_input := 0.0        ## -1 to 1: S to W, held this tick.
var rudder_input := 0.0          ## -1 to 1: A to D.
var climb_input := 0.0           ## -1 to 1: descend to climb.
var autopilot := false
var target_heading := 0.0
var target_altitude := 0.0


func _init(helm_ship: Ship, helm_cell: Vector3i) -> void:
	ship = helm_ship
	cell = helm_cell


## Puts crew at the helm. Returns false when someone else has it.
func take(crew: CrewMember) -> bool:
	if pilot != null:
		return false
	pilot = crew
	crew.station = self
	return true


## Lets go of the helm. The rudder centres; throttle and trim stay as they are.
func leave(crew: CrewMember) -> void:
	if pilot != crew:
		return
	pilot = null
	crew.station = null
	throttle_input = 0.0
	rudder_input = 0.0
	climb_input = 0.0
	if not autopilot:
		ship.rudder = 0.0


## Switches the autopilot on, holding the present heading and altitude, or off.
func set_autopilot(on: bool) -> void:
	autopilot = on
	target_heading = ship.heading()
	target_altitude = ship.global_position.y


func _physics_process(delta: float) -> void:
	if pilot == null and not autopilot:
		return
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
