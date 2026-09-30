class_name PlayerController
extends Node3D
## The local player's eyes and hands. It reads the keyboard and mouse, walks their
## crew member (aboard or ashore) or steers from the helm, and places the camera:
## first person, or a chase view behind the ship while at the helm (spec §3.4). What
## your crew member does that moves you between ships and the world, it passes on
## for the World to act on.

signal left_ship               ## You stepped off your ship.
signal landed_on(ship: Ship)   ## Ashore, you came down on ship's deck.
signal lost                    ## Ashore, you fell into the Roil.
signal climbing(ship: Ship)    ## Ashore, E next to ship's hull.

const MOUSE_TURN := 0.0025     ## Radians per pixel of mouse movement at sensitivity 1.
const CHASE_DISTANCE := 40.0   ## Metres from the chase camera to the ship.

var crew: CrewMember
var ship: Ship                 ## Null while ashore.
var camera: Camera3D
var chase := false             ## The chase view is showing.
var enabled := true            ## Off while a menu is open: keys and mouse do nothing.
var look_pitch := 0.0          ## Radians; positive looks up.
var peer := 1                  ## This player's peer id.

var _avatar: CrewAvatar
var _chase_yaw := 0.0
var _chase_pitch := -0.3


func _init(player_crew: CrewMember) -> void:
	crew = player_crew
	ship = crew.ship


func _ready() -> void:
	camera = Camera3D.new()
	camera.far = 3200.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	camera.make_current()
	_avatar = CrewAvatar.new()
	add_child(_avatar)
	peer = multiplayer.get_unique_id()
	board(crew)


## Makes new_crew yours, aboard its ship or ashore: the keys, E and the camera
## follow it, and the crew member you had is no longer heard from.
func board(new_crew: CrewMember) -> void:
	if is_instance_valid(ship) and ship.helm != null and ship.helm.pilot_changed.is_connected(_on_pilot_changed):
		ship.helm.pilot_changed.disconnect(_on_pilot_changed)
	if is_instance_valid(crew) and crew.left_ship.is_connected(left_ship.emit):
		crew.left_ship.disconnect(left_ship.emit)
		crew.landed_on.disconnect(landed_on.emit)
		crew.lost.disconnect(lost.emit)
	crew = new_crew
	ship = crew.ship
	if ship != null and ship.helm != null:
		ship.helm.pilot_changed.connect(_on_pilot_changed)
	crew.left_ship.connect(left_ship.emit)
	crew.landed_on.connect(landed_on.emit)
	crew.lost.connect(lost.emit)
	_on_pilot_changed()
	chase = false


## Where your crew member is in the main world.
func world_position() -> Vector3:
	if not is_instance_valid(crew):
		return camera.global_position
	if ship == null:
		return crew.position
	return ship.global_transform * crew.position if is_instance_valid(ship) else camera.global_position


## What E does right now, for the HUD, or "" when it does nothing.
func prompt() -> String:
	if crew.station != null:
		return "Leave the helm"
	if helm_in_reach() and ship.helm.pilot == 0:
		return "Take the helm"
	if ship == null and crew.is_on_floor() and ship_in_reach() != null:
		return "Climb aboard"
	return ""


## Whether you're standing close enough to the helm to use it.
func helm_in_reach() -> bool:
	return ship != null and ship.helm != null and ship.helm.in_reach(crew.position)


## Ashore: the nearest ship whose box, grown 3 m, holds you, or null.
func ship_in_reach() -> Ship:
	if ship != null:
		return null
	var nearest: Ship = null
	for node in crew.get_parent().get_children():
		var near := node as Ship
		if near != null and (near.global_transform * near.bounds).grow(3.0).has_point(crew.position) \
				and (nearest == null or near.global_position.distance_to(crew.position) < nearest.global_position.distance_to(crew.position)):
			nearest = near
	return nearest


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var turn: Vector2 = (event as InputEventMouseMotion).relative * MOUSE_TURN * Settings.mouse_sensitivity
		if chase:
			_chase_yaw = wrapf(_chase_yaw - turn.x, -PI, PI)
			_chase_pitch = clampf(_chase_pitch - turn.y, -1.3, 0.2)
		else:
			crew.look_yaw = wrapf(crew.look_yaw - turn.x, -PI, PI)
			look_pitch = clampf(look_pitch - turn.y, -1.5, 1.5)
	elif event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("toggle_camera") and crew.station != null:
		chase = not chase
	elif event.is_action_pressed("autopilot") and crew.station != null:
		ship.helm.ask_autopilot(peer, not ship.helm.autopilot)
	elif event.is_action_pressed("anchor") and crew.station != null:
		ship.helm.ask_anchor(peer, not ship.anchored)


func _physics_process(_delta: float) -> void:
	var keys := 1.0 if enabled else 0.0
	if crew.station != null:
		ship.helm.throttle_input = Input.get_axis("move_back", "move_forward") * keys
		ship.helm.rudder_input = Input.get_axis("move_left", "move_right") * keys
		ship.helm.climb_input = Input.get_axis("descend", "jump") * keys
		return
	crew.move = Input.get_vector("move_left", "move_right", "move_forward", "move_back") * keys
	crew.sprint = Input.is_action_pressed("sprint")
	crew.jump = Input.is_action_just_pressed("jump") and enabled
	crew.glide = Input.is_action_pressed("jump") and enabled
	# On a ladder, forward and jump climb and descend goes down.
	crew.climb = clampf(Input.get_axis("descend", "jump") * keys + maxf(0.0, -crew.move.y), -1.0, 1.0)


func _process(_delta: float) -> void:
	var ship_place := ship.get_global_transform_interpolated() if ship != null else Transform3D.IDENTITY
	var body := crew.get_global_transform_interpolated().origin
	_avatar.global_transform = ship_place * Transform3D(Basis(Vector3.UP, crew.look_yaw), body)
	_avatar.look(look_pitch)
	_avatar.visible = chase
	if chase:
		var center := ship_place * ship.center_of_mass
		var bow := -ship_place.basis.z
		var yaw := atan2(-bow.x, -bow.z) + _chase_yaw
		var offset := Basis.from_euler(Vector3(_chase_pitch, yaw, 0.0)) * Vector3(0.0, 0.0, CHASE_DISTANCE)
		camera.global_transform = Transform3D(Basis.IDENTITY, center + offset).looking_at(center)
	else:
		var eye := Transform3D(Basis.from_euler(Vector3(look_pitch, crew.look_yaw, 0.0)), body + Vector3(0.0, CrewMember.EYE_HEIGHT, 0.0))
		camera.global_transform = ship_place * eye


func _interact() -> void:
	if crew.station != null:
		ship.helm.ask_helm(peer, false)
	elif helm_in_reach():
		ship.helm.ask_helm(peer, true)
	elif prompt() == "Climb aboard":
		climbing.emit(ship_in_reach())


## You're at the helm exactly while it says you're its pilot.
func _on_pilot_changed() -> void:
	var at_helm := ship != null and ship.helm != null and ship.helm.pilot == peer
	crew.station = ship.helm if at_helm else null
	if not at_helm:
		chase = false
