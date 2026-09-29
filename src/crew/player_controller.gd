class_name PlayerController
extends Node3D
## The local player's eyes and hands. It reads the keyboard and mouse, walks their
## crew member or steers from the helm, and places the camera: first person, or a
## chase view behind the ship while at the helm (spec §3.4).

const MOUSE_TURN := 0.0025     ## Radians per pixel of mouse movement at sensitivity 1.
const REACH := 1.8             ## Metres from a helm's block that you can use it from.
const CHASE_DISTANCE := 40.0   ## Metres from the chase camera to the ship.

var crew: CrewMember
var ship: Ship
var camera: Camera3D
var chase := false             ## The chase view is showing.
var enabled := true            ## Off while a menu is open: keys and mouse do nothing.
var look_pitch := 0.0          ## Radians; positive looks up.

var _avatar: MeshInstance3D
var _chase_yaw := 0.0
var _chase_pitch := -0.3


func _init(player_crew: CrewMember) -> void:
	crew = player_crew
	ship = crew.ship


func _ready() -> void:
	camera = Camera3D.new()
	camera.far = 8000.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	camera.make_current()
	var body := CapsuleMesh.new()
	body.radius = CrewMember.RADIUS
	body.height = CrewMember.HEIGHT
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color("2f4f6f")
	_avatar = MeshInstance3D.new()
	_avatar.mesh = body
	_avatar.material_override = cloth
	_avatar.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_avatar)


## What E does right now, for the HUD, or "" when it does nothing.
func prompt() -> String:
	if crew.station != null:
		return "Leave the helm"
	if _helm_in_reach():
		return "Take the helm"
	return ""


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
		ship.helm.set_autopilot(not ship.helm.autopilot)


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
	# On a ladder, forward and jump climb and descend goes down.
	crew.climb = clampf(Input.get_axis("descend", "jump") * keys + maxf(0.0, -crew.move.y), -1.0, 1.0)


func _process(_delta: float) -> void:
	var ship_place := ship.get_global_transform_interpolated()
	var body := crew.get_global_transform_interpolated().origin
	_avatar.global_transform = ship_place * Transform3D(Basis(Vector3.UP, crew.look_yaw), body)
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
		ship.helm.leave(crew)
		chase = false
	elif _helm_in_reach():
		ship.helm.take(crew)


func _helm_in_reach() -> bool:
	return ship.helm != null and crew.position.distance_to(Vector3(ship.helm.cell)) <= REACH
