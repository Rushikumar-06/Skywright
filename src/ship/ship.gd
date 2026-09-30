class_name Ship
extends RigidBody3D
## A ship: one rigid body built from a ShipGrid, flying on the forces of spec §4.4.
## Each physics tick it applies lift, thrust, drag and the rudders' push; the
## engine adds gravity. Its crew walk in its interior, a separate physics world in
## ship space (spec §4.5).

const MAX_SPEED := 400.0  ## m/s. Anything faster is a physics blow-up.
const MAX_SPIN := 20.0    ## rad/s. Likewise.

var grid: ShipGrid
var interior: ShipInterior  ## Where the crew walk.
var helm: Helm              ## The ship's first helm, or null.
var bounds: AABB            ## The box around its blocks, in ship space.
var throttle := 0.0  ## Tuning.THROTTLE_MIN (full astern) to 1 (full ahead).
var rudder := 0.0    ## -1 (hard to port) to 1 (hard to starboard).
var trim := 1.0      ## Balloon trim, Tuning.TRIM_MIN to Tuning.TRIM_MAX.
var calm := false    ## No wind. Flight tests fly in still air.
var captain := 0     ## The peer id of the player whose ship it is, or 0 for nobody's.
var test := false    ## A test flight from the dock.
## False on clients: the ship is then a frozen, kinematic copy that follows the
## server's snapshots (spec §4.6), and no forces act on it. Set before adding it.
var simulated := true

var _balloons: Array[Vector3] = []
var _lift_stones: Array[Vector3] = []
var _propellers: Array[Vector3] = []
var _thrust_axes: Array[Vector3] = []   ## Each propeller's push direction, in ship space.
var _rudders: Array[Vector3] = []
var _rudder_sides: Array[Vector3] = []  ## Each rudder's flat-side normal, in ship space.
var _rudder_chords: Array[Vector3] = [] ## The way air flows along each rudder, in ship space.
var _zones: Array[Dictionary] = []
var _power := 0.0  ## The share of full thrust the engines give each propeller.
var _last_good := Transform3D.IDENTITY


func _init(ship_grid: ShipGrid) -> void:
	grid = ship_grid


func _ready() -> void:
	if not simulated:
		freeze_mode = FREEZE_MODE_KINEMATIC
		freeze = true
	var props := grid.mass_properties()
	mass = props["mass"]
	center_of_mass_mode = CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = props["center"]
	inertia = props["inertia"]
	can_sleep = false
	linear_damp_mode = DAMP_MODE_REPLACE
	angular_damp_mode = DAMP_MODE_REPLACE
	angular_damp = Tuning.ANGULAR_DAMPING
	var boxes := grid.merged_boxes()
	for box in boxes:
		var cube := BoxShape3D.new()
		cube.size = box.size
		var shape := CollisionShape3D.new()
		shape.shape = cube
		shape.position = box.get_center()
		add_child(shape)
	for cell in grid.cells_of("balloon"):
		_balloons.append(Vector3(cell))
	for cell in grid.cells_of("lift_stone"):
		_lift_stones.append(Vector3(cell))
	for cell in grid.cells_of("propeller"):
		_propellers.append(Vector3(cell))
		_thrust_axes.append(Blocks.facing(grid.blocks[cell]["rotation"]))
	for cell in grid.cells_of("rudder"):
		_rudders.append(Vector3(cell))
		var turn := Blocks.basis(grid.blocks[cell]["rotation"])
		_rudder_sides.append(turn * Vector3.RIGHT)
		_rudder_chords.append(turn * Vector3.FORWARD)
	_power = ShipForces.propeller_power(grid)
	_zones = grid.drag_zones()
	bounds = grid.bounds()
	_last_good = global_transform
	add_child(ShipMesh.build(grid))
	interior = ShipInterior.new(boxes)
	add_child(interior)
	var helms := grid.cells_of("helm")
	if not helms.is_empty():
		helm = Helm.new(self, helms[0])
		add_child(helm)


## Spots next to the helm, nearest first, as offsets from the cell just aft of it.
## The last three are in front of it, for a helm with deck only ahead.
const SPAWN_SPOTS: Array[Vector3i] = [
	Vector3i(0, 0, 0), Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1),
	Vector3i(-1, 0, -1), Vector3i(1, 0, -1), Vector3i(-1, 0, 1), Vector3i(1, 0, 1),
	Vector3i(0, 0, -2), Vector3i(-1, 0, -2), Vector3i(1, 0, -2),
]


## Where crew come aboard, in ship space. Slot 0 stands just aft of the helm; later
## slots stand on the free spots around it, and share them when there are more
## crew than spots (crew don't collide with each other).
func crew_spawn(slot := 0) -> Vector3:
	var aft := helm.cell + Vector3i(0, 0, 1)
	var free: Array[Vector3i] = []
	for offset in SPAWN_SPOTS:
		var cell := aft + offset
		var below := grid.type_at(cell + Vector3i.DOWN)
		if grid.type_at(cell) == "" and grid.type_at(cell + Vector3i.UP) == "" and below != "" and below != "ladder":
			free.append(cell)
	var spot := free[slot % free.size()] if not free.is_empty() else aft
	return Vector3(spot) + Vector3(0.0, 0.45, 0.0)


## Full-throttle thrust in N.
func max_thrust() -> float:
	return ShipForces.forward_thrust(grid)


## The trim at which lift equals weight at altitude (it may fall outside the trim limits).
func trim_to_float_at(altitude: float) -> float:
	var weight := mass * float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	var balloon_lift := _balloons.size() * Tuning.BALLOON_LIFT * ShipForces.air_density(altitude)
	if balloon_lift <= 0.0:
		return Tuning.TRIM_MAX
	return (weight - _lift_stones.size() * Tuning.LIFT_STONE_LIFT) / balloon_lift


## Compass heading in radians: 0 when the bow points along -Z, growing as she turns to port.
func heading() -> float:
	var bow := -global_basis.z
	return atan2(-bow.x, -bow.z)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not simulated:
		return
	if not _sane(state):
		push_warning("Ship %s blew up (speed %.0f m/s, spin %.1f rad/s); restoring its last good position." % [name, state.linear_velocity.length(), state.angular_velocity.length()])
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		# Move the node, not the state: after this call the engine pushes the node's
		# transform to the physics server whenever it differs from the state's, and a
		# NaN never equals itself. Anything that teleports a ship should do the same.
		global_transform = _last_good
		reset_physics_interpolation()
		return
	_last_good = state.transform
	var basis := state.transform.basis
	var altitude := state.transform.origin.y
	# The wind's clock is physics ticks since the game started; stage 3 uses the host's.
	var wind := Vector3.ZERO if calm else Wind.at(state.transform.origin, Engine.get_physics_frames() / float(Engine.physics_ticks_per_second))

	# Lift: every balloon and lift stone pulls straight up, so together they act as
	# one force at their lift-weighted centre.
	var lift := 0.0
	var lift_moment := Vector3.ZERO
	for cell in _balloons:
		var offset := basis * cell
		var force := Tuning.BALLOON_LIFT * ShipForces.air_density(altitude + offset.y) * trim
		lift += force
		lift_moment += offset * force
	for cell in _lift_stones:
		var offset := basis * cell
		lift += Tuning.LIFT_STONE_LIFT
		lift_moment += offset * Tuning.LIFT_STONE_LIFT
	if lift > 0.0:
		state.apply_force(Vector3(0.0, lift, 0.0), lift_moment / lift)

	# Thrust: each propeller pushes the way it faces.
	for i in _propellers.size():
		state.apply_force(basis * _thrust_axes[i] * (throttle * _power * Tuning.PROPELLER_THRUST), basis * _propellers[i])

	# Drag and the keel's push on each zone, from its own velocity through the air.
	var to_ship := basis.transposed()
	for zone in _zones:
		var offset := basis * (zone["center"] as Vector3)
		var air := to_ship * (state.get_velocity_at_local_position(offset) - wind)
		var density := ShipForces.air_density(altitude + offset.y)
		var force := ShipForces.zone_drag(zone["area"], air, density)
		force.x += ShipForces.keel(zone["area"].x, air, density)
		state.apply_force(basis * force, offset)

	# Rudders push the stern sideways, harder the faster air flows past them.
	# Each pushes along its flat side, and feels the air flowing along its chord.
	for i in _rudders.size():
		var offset := basis * _rudders[i]
		var flow := (basis * _rudder_chords[i]).dot(state.get_velocity_at_local_position(offset) - wind)
		var push := Tuning.RUDDER_FORCE * ShipForces.air_density(altitude + offset.y) * flow * absf(flow) * rudder
		state.apply_force(-(basis * _rudder_sides[i]) * push, offset)


func _sane(state: PhysicsDirectBodyState3D) -> bool:
	return state.transform.is_finite() and state.linear_velocity.is_finite() and state.angular_velocity.is_finite() \
			and state.linear_velocity.length() <= MAX_SPEED and state.angular_velocity.length() <= MAX_SPIN
