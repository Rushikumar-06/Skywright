class_name PlayerController
extends Node3D
## The local player's eyes and hands. It reads the keyboard and mouse, walks their
## crew member (aboard or ashore), steers from the helm or aims and fires a cannon,
## and places the camera: first person, or a chase view behind the ship while at the
## helm (spec §3.4). At a cannon it draws the arc its shot would fly. Holding R
## aboard, away from any station, repairs the block you look at. What
## your crew member does that moves you between ships and the world, it passes on
## for the World to act on.

signal left_ship               ## You stepped off your ship.
signal landed_on(ship: Ship)   ## Ashore, you came down on ship's deck.
signal lost                    ## Ashore, you fell into the Roil.
signal climbing(ship: Ship)    ## Ashore, E next to ship's hull.
signal repairing(cell: Vector3i)  ## A repair action at cell of your ship, every Damage.REPAIR_EVERY while R is held.

const MOUSE_TURN := 0.0025     ## Radians per pixel of mouse movement at sensitivity 1.
const CHASE_DISTANCE := 40.0   ## Metres from the chase camera to the ship.
const AIM_SECONDS := 8.0       ## The aim line shows this much of a shot's flight,
const AIM_STEPS := 48          ## in this many steps.

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
var _aim_line: MeshInstance3D
var _repair_left := 0.0        ## s until the next repair action while R is held.


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
	_aim_line = MeshInstance3D.new()
	_aim_line.mesh = ImmediateMesh.new()
	_aim_line.top_level = true
	_aim_line.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # redrawn every frame
	var chalk := StandardMaterial3D.new()
	chalk.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	chalk.albedo_color = Color(1.0, 1.0, 1.0, 0.6)
	chalk.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aim_line.material_override = chalk
	add_child(_aim_line)
	peer = multiplayer.get_unique_id()
	board(crew)


## Makes new_crew yours, aboard its ship or ashore: the keys, E and the camera
## follow it, and the crew member you had is no longer heard from.
func board(new_crew: CrewMember) -> void:
	if is_instance_valid(ship):
		for station: Node in _stations_of(ship):
			if _changes_of(station).is_connected(_on_station_changed):
				_changes_of(station).disconnect(_on_station_changed)
	if is_instance_valid(crew) and crew.left_ship.is_connected(left_ship.emit):
		crew.left_ship.disconnect(left_ship.emit)
		crew.landed_on.disconnect(landed_on.emit)
		crew.lost.disconnect(lost.emit)
	crew = new_crew
	ship = crew.ship
	if ship != null:
		for station: Node in _stations_of(ship):
			_changes_of(station).connect(_on_station_changed)
	crew.left_ship.connect(left_ship.emit)
	crew.landed_on.connect(landed_on.emit)
	crew.lost.connect(lost.emit)
	_on_station_changed()
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
	if crew.station is Cannon:
		return "Leave the cannon"
	if crew.station != null:
		return "Leave the helm"
	var near := station_in_reach()
	if near is Helm and (near as Helm).pilot == 0:
		return "Take the helm"
	if near is Cannon and (near as Cannon).gunner == 0:
		return "Man the cannon"
	if ship == null and crew.is_on_floor() and ship_in_reach() != null:
		return "Climb aboard"
	return ""


## Whether you're standing close enough to the helm to use it.
func helm_in_reach() -> bool:
	return ship != null and ship.helm != null and ship.helm.in_reach(crew.position)


## The station of your ship (her helm or a cannon) nearest you in reach, or null.
func station_in_reach() -> Node:
	return ship.station_near(crew.position) if ship != null else null


## Asks to let go of the station you hold, if any.
func leave_station() -> void:
	if crew.station is Helm:
		(crew.station as Helm).ask_helm(peer, false)
	elif crew.station is Cannon:
		(crew.station as Cannon).ask_man(peer, false)


## The block of your ship you look at, within Damage.REPAIR_REACH of your eye, as
## {"cell": Vector3i}; {} when there's none, or you're ashore.
func aimed_block() -> Dictionary:
	if ship == null:
		return {}
	var eye := crew.position + Vector3(0.0, CrewMember.EYE_HEIGHT, 0.0)
	var look := Basis.from_euler(Vector3(look_pitch, crew.look_yaw, 0.0)) * Vector3.FORWARD
	var hit := ship.grid.raycast(eye, look, Damage.REPAIR_REACH)
	return {"cell": hit["cell"]} if not hit.is_empty() else {}


## What holding R does right now, for the HUD, or "" when it does nothing.
func repair_prompt() -> String:
	if ship == null or crew.station != null:
		return ""
	var aimed := aimed_block()
	if aimed.is_empty():
		return ""
	var cell: Vector3i = aimed["cell"]
	if ship.burning.any(func(fire: Vector3i) -> bool: return Damage.beside(fire, cell)):
		return "Hold R   Put out the fire"
	var fix := Damage.repair(ship.grid, ship.blueprint, cell)
	if fix.is_empty():
		return ""
	if ship.spares < 1:
		return "No spares left: refill at a town's dock"
	if fix.has(cell):
		return "Hold R   Repair  %d/%d" % [ship.grid.blocks[cell]["hp"], Tuning.BLOCKS[ship.grid.blocks[cell]["type"]]["hp"]]
	return "Hold R   Rebuild"


## Ashore: the nearest ship whose box, grown 3 m, holds you, or null. Never a wreck.
func ship_in_reach() -> Ship:
	if ship != null:
		return null
	var nearest: Ship = null
	for node in crew.get_parent().get_children():
		var near := node as Ship
		if near != null and not near.is_wreck() and (near.global_transform * near.bounds).grow(3.0).has_point(crew.position) \
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
	elif event.is_action_pressed("toggle_camera") and crew.station is Helm:
		chase = not chase
	elif event.is_action_pressed("autopilot") and crew.station is Helm:
		ship.helm.ask_autopilot(peer, not ship.helm.autopilot)
	elif event.is_action_pressed("anchor") and crew.station is Helm:
		ship.helm.ask_anchor(peer, not ship.anchored)
	elif event.is_action_pressed("fire") and crew.station is Cannon:
		(crew.station as Cannon).ask_fire(peer)
	elif event.is_action_pressed("ammo") and crew.station is Cannon:
		(crew.station as Cannon).next_ammo()


func _physics_process(delta: float) -> void:
	var keys := 1.0 if enabled else 0.0
	if crew.station is Cannon:
		# The aim follows your look, within the cannon's limits.
		var cannon := crew.station as Cannon
		var facing := cannon.facing()
		cannon.aim_yaw = clampf(wrapf(crew.look_yaw - atan2(-facing.x, -facing.z), -PI, PI), -Cannon.ARC, Cannon.ARC)
		cannon.aim_pitch = clampf(look_pitch, Cannon.PITCH_MIN, Cannon.PITCH_MAX)
		return
	if crew.station != null:
		ship.helm.throttle_input = Input.get_axis("move_back", "move_forward") * keys
		ship.helm.rudder_input = Input.get_axis("move_left", "move_right") * keys
		ship.helm.climb_input = Input.get_axis("descend", "jump") * keys
		return
	_hold_repair(delta)
	crew.move = Input.get_vector("move_left", "move_right", "move_forward", "move_back") * keys
	crew.sprint = Input.is_action_pressed("sprint")
	crew.jump = Input.is_action_just_pressed("jump") and enabled
	crew.glide = Input.is_action_pressed("jump") and enabled
	# On a ladder, forward and jump climb and descend goes down.
	crew.climb = clampf(Input.get_axis("descend", "jump") * keys + maxf(0.0, -crew.move.y), -1.0, 1.0)


## While R is held aboard, a repair action at the block you look at at once, then
## every Damage.REPAIR_EVERY.
func _hold_repair(delta: float) -> void:
	if not enabled or ship == null or not Input.is_action_pressed("repair"):
		_repair_left = 0.0
		return
	_repair_left -= delta
	if _repair_left > 0.0:
		return
	_repair_left = Damage.REPAIR_EVERY
	var aimed := aimed_block()
	if not aimed.is_empty():
		repairing.emit(aimed["cell"])


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
	_draw_aim(ship_place)


## At a cannon, draws the arc its shot would fly from its muzzle, with the ship
## where she's drawn. ponytail: a client's copy of a ship has no velocity, so there
## the line leaves out her motion; pass the snapshot's velocity if that shows.
func _draw_aim(ship_place: Transform3D) -> void:
	var lines := _aim_line.mesh as ImmediateMesh
	lines.clear_surfaces()
	var cannon := crew.station as Cannon
	_aim_line.visible = cannon != null and not chase
	if not _aim_line.visible:
		return
	var direction := cannon.direction()
	var origin := ship_place * (Vector3(cannon.cell) + direction * WorldSync.MUZZLE)
	var velocity := ship.point_velocity(origin) + ship_place.basis * direction * float(Damage.AMMO[cannon.ammo]["speed"])
	lines.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in Projectiles.arc(origin, velocity, AIM_SECONDS, AIM_STEPS):
		lines.surface_add_vertex(point)
	lines.surface_end()


func _interact() -> void:
	var near := station_in_reach()
	if crew.station != null:
		leave_station()
	elif near is Helm:
		(near as Helm).ask_helm(peer, true)
	elif near is Cannon:
		(near as Cannon).ask_man(peer, true)
	elif prompt() == "Climb aboard":
		climbing.emit(ship_in_reach())


## You're at the helm while it says you're its pilot, else at the cannon that says
## you man it, else at no station.
func _on_station_changed() -> void:
	var at: Node = null
	if ship != null:
		for station: Node in _stations_of(ship):
			if (station is Helm and (station as Helm).pilot == peer) or (station is Cannon and (station as Cannon).gunner == peer):
				at = station
				break
	crew.station = at
	if not at is Helm:
		chase = false


## ship's helm, first, and her cannons.
static func _stations_of(of: Ship) -> Array[Node]:
	var stations: Array[Node] = []
	if of.helm != null:
		stations.append(of.helm)
	stations.append_array(of.cannons)
	return stations


## The signal a station gives when who holds it changes.
static func _changes_of(station: Node) -> Signal:
	return (station as Helm).pilot_changed if station is Helm else (station as Cannon).gunner_changed
