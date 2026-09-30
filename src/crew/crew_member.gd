class_name CrewMember
extends CharacterBody3D
## Someone on foot. Aboard a ship they walk its interior (ship space), where
## gravity is the ship's "down" (spec §4.5), so a tilting deck feels like a slope.
## Ashore (ship null) they walk the main world, in world space, and can glide. Whoever
## controls a crew member sets move, look_yaw, sprint, jump, glide and climb; it
## doesn't read the keyboard itself.

signal left_ship               ## Aboard: no floor for a moment and nothing of the ship below.
signal landed_on(ship: Ship)   ## Ashore: came down on ship's deck.
signal lost                    ## Ashore: fell into the Roil.

const WALK_SPEED := 4.0
const SPRINT_SPEED := 6.5
const JUMP_SPEED := 4.6    ## About 1.1 m high: onto a 1 m block, but not a 2 m deck.
const CLIMB_SPEED := 2.5
const HEIGHT := 1.8
const RADIUS := 0.35
const EYE_HEIGHT := 0.7    ## Above the middle of the body.
const GLIDE_SPEED := 13.0  ## m/s across the ground while gliding.
const GLIDE_SINK := 3.0    ## m/s: the fastest a glide falls.
const FALL_LIMIT := 50.0   ## m/s: the fastest anyone falls.
const GLIDE_AFTER := 0.3   ## s of falling, with glide held, before a glide opens by itself.
const LEAVE_AFTER := 0.2   ## s without floor before you can have left the ship.
const REBOARD_AFTER := 0.5 ## s ashore before landing on a ship puts you aboard.

var ship: Ship               ## Null ashore.
var home: Vector3            ## Where you came aboard.
var move := Vector2.ZERO     ## As Input.get_vector gives it: x to starboard, y aft.
var look_yaw := 0.0          ## Radians, relative to the ship (ashore, the world). 0 faces the bow (north).
var sprint := false
var jump := false            ## Jump on the next tick, if standing.
var glide := false           ## Ashore: glide while in the air (Space held).
var climb := 0.0             ## On a ladder: 1 up, -1 down.
var station: Node = null     ## The station being used. Nobody walks while at one.
var gliding := false         ## Gliding this tick. Read-only.

var _air_time := 0.0         ## s since the floor was last under your feet.
var _pressed_in_air := false ## glide was pressed again after leaving the floor.
var _glide_was := false
var _ashore_time := 0.0
var _left := false           ## left_ship has fired.
var _lost := false           ## lost has fired.


func _init(crew_ship: Ship, at: Vector3) -> void:
	ship = crew_ship
	home = at
	position = at
	collision_layer = 0  # nothing bumps into crew: a ship flying into you doesn't stop
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	add_child(shape)


func _physics_process(delta: float) -> void:
	var gravity := Vector3(0.0, -float(ProjectSettings.get_setting("physics/3d/default_gravity")), 0.0)
	if ship != null:
		gravity = ship.global_basis.transposed() * gravity
	up_direction = -gravity.normalized()
	var wish := Basis(Vector3.UP, look_yaw) * Vector3(move.x, 0.0, move.y).limit_length(1.0) * (SPRINT_SPEED if sprint else WALK_SPEED)
	var rise := climb * CLIMB_SPEED
	if station != null:
		wish = Vector3.ZERO
		rise = 0.0
	var holding_on := ship != null and on_ladder()
	var jumping := false
	_air_time = 0.0 if is_on_floor() or holding_on else _air_time + delta
	if glide and not _glide_was and _air_time > 0.0:
		_pressed_in_air = true
	if not glide or _air_time == 0.0:
		_pressed_in_air = false
	_glide_was = glide
	gliding = ship == null and glide and _air_time > 0.0 and (_air_time >= GLIDE_AFTER or _pressed_in_air)
	if holding_on:
		# Hold on: no gravity, and climb along the ship's up.
		velocity = wish + Vector3.UP * rise
	elif is_on_floor():
		var floor_normal := get_floor_normal()
		velocity = wish - floor_normal * wish.dot(floor_normal)
		if jump and station == null:
			velocity += up_direction * JUMP_SPEED
			jumping = true
	elif ship != null:
		var up := up_direction
		velocity = wish - up * wish.dot(up) + up * velocity.dot(up) + gravity * delta
	else:
		# Ashore in the air you keep going, falling no faster than FALL_LIMIT. A glide
		# eases you toward GLIDE_SPEED where you look, A and D bending the way.
		velocity.y = maxf(velocity.y + gravity.y * delta, -FALL_LIMIT)
		if gliding:
			var aim := Basis(Vector3.UP, look_yaw) * Vector3(move.x, 0.0, -1.0).normalized() * GLIDE_SPEED
			var blend := 1.0 - exp(-2.0 * delta)
			velocity.x = lerpf(velocity.x, aim.x, blend)
			velocity.z = lerpf(velocity.z, aim.z, blend)
			velocity.y = maxf(velocity.y, -GLIDE_SINK)
	jump = false
	var was_on_floor := is_on_floor()
	move_and_slide()
	if was_on_floor and not is_on_floor() and not jumping and not holding_on:
		apply_floor_snap()  # walking "uphill" against a tilted gravity skips Godot's own snap
	if ship != null:
		# Only once nothing of the ship is below you have you left it.
		if not _left and station == null and _air_time >= LEAVE_AFTER and not ship.is_over(ship.global_transform * position):
			_left = true
			left_ship.emit()
		return
	_ashore_time += delta
	if position.y < Tuning.ROIL_ALTITUDE:
		if not _lost:
			_lost = true
			lost.emit()
		return
	if _ashore_time <= REBOARD_AFTER:
		return
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		if hit.get_collider() is Ship and hit.get_normal().y > 0.6:
			landed_on.emit(hit.get_collider() as Ship)
			return


## Whether the middle of the body is in a ladder's cell, from the feet to the waist.
func on_ladder() -> bool:
	var column := Vector2i(roundi(position.x), roundi(position.z))
	for y in range(roundi(position.y - HEIGHT / 2.0), roundi(position.y) + 1):
		if ship.grid.type_at(Vector3i(column.x, y, column.y)) == "ladder":
			return true
	return false
