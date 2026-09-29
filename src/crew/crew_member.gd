class_name CrewMember
extends CharacterBody3D
## Someone aboard a ship, walking in its interior (ship space). Gravity is the
## ship's "down" (spec §4.5), so a tilting deck feels like a slope. Whoever
## controls a crew member sets move, look_yaw, sprint, jump and climb; it doesn't
## read the keyboard itself.

signal fell_overboard

const WALK_SPEED := 4.0
const SPRINT_SPEED := 6.5
const JUMP_SPEED := 4.6    ## About 1.1 m high: onto a 1 m block, but not a 2 m deck.
const CLIMB_SPEED := 2.5
const HEIGHT := 1.8
const RADIUS := 0.35
const EYE_HEIGHT := 0.7    ## Above the middle of the body.
const OVERBOARD := 30.0    ## Metres below the ship's lowest block that count as lost.

var ship: Ship
var home: Vector3            ## Where to come back aboard after falling overboard.
var move := Vector2.ZERO     ## As Input.get_vector gives it: x to starboard, y aft.
var look_yaw := 0.0          ## Radians, relative to the ship. 0 faces the bow.
var sprint := false
var jump := false            ## Jump on the next tick, if standing.
var climb := 0.0             ## On a ladder: 1 up, -1 down.
var station: Node = null     ## The station being used. Nobody walks while at one.

var _lowest := 0.0


func _init(crew_ship: Ship, at: Vector3) -> void:
	ship = crew_ship
	home = at
	position = at
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	add_child(shape)
	_lowest = INF
	for cell: Vector3i in ship.grid.blocks:
		_lowest = minf(_lowest, cell.y - 0.5)


func _physics_process(delta: float) -> void:
	var gravity := ship.global_basis.transposed() * Vector3(0.0, -float(ProjectSettings.get_setting("physics/3d/default_gravity")), 0.0)
	up_direction = -gravity.normalized()
	var wish := Basis(Vector3.UP, look_yaw) * Vector3(move.x, 0.0, move.y).limit_length(1.0) * (SPRINT_SPEED if sprint else WALK_SPEED)
	if station != null:
		wish = Vector3.ZERO
	var holding_on := on_ladder()
	var jumping := false
	if holding_on:
		# Hold on: no gravity, and climb along the ship's up.
		velocity = wish + Vector3.UP * climb * CLIMB_SPEED
	elif is_on_floor():
		var floor_normal := get_floor_normal()
		velocity = wish - floor_normal * wish.dot(floor_normal)
		if jump and station == null:
			velocity += up_direction * JUMP_SPEED
			jumping = true
	else:
		var up := up_direction
		velocity = wish - up * wish.dot(up) + up * velocity.dot(up) + gravity * delta
	jump = false
	var was_on_floor := is_on_floor()
	move_and_slide()
	if was_on_floor and not is_on_floor() and not jumping and not holding_on:
		apply_floor_snap()  # walking "uphill" against a tilted gravity skips Godot's own snap
	if position.y < _lowest - OVERBOARD:
		position = home
		velocity = Vector3.ZERO
		reset_physics_interpolation()
		fell_overboard.emit()


## Whether the middle of the body is in a ladder's cell, from the feet to the waist.
func on_ladder() -> bool:
	var column := Vector2i(roundi(position.x), roundi(position.z))
	for y in range(roundi(position.y - HEIGHT / 2.0), roundi(position.y) + 1):
		if ship.grid.type_at(Vector3i(column.x, y, column.y)) == "ladder":
			return true
	return false
