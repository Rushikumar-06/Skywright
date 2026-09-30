class_name Ship
extends RigidBody3D
## A ship: one rigid body built from a ShipGrid, flying on the forces of spec §4.4.
## Each physics tick it applies lift, thrust, drag and the rudders' push; the
## engine adds gravity. Its crew walk in its interior, a separate physics world in
## ship space (spec §4.5). Damage takes blocks away (or a repair brings them back),
## and the ship rebuilds itself from what's left, at most once a frame.

signal blocks_changed  ## After each rebuild.

const MAX_SPEED := 400.0  ## m/s. Anything faster is a physics blow-up.
const MAX_SPIN := 20.0    ## rad/s. Likewise.

var grid: ShipGrid
## The ship whole, as she was built: what repairs restore. Set before adding the
## ship; without one she's her grid made whole.
var blueprint: ShipGrid
var spares := 0      ## Spare materials for repairs, 0 to Damage.SPARES_MAX.
var pirate := false
var born := 0.0      ## The server's clock when she was added.
var lost := false    ## The Roil took her.
var interior: ShipInterior  ## Where the crew walk.
var helm: Helm              ## The ship's first helm, or null.
var bounds: AABB            ## The box around its blocks, in ship space.
var throttle := 0.0  ## Tuning.THROTTLE_MIN (full astern) to 1 (full ahead).
var rudder := 0.0    ## -1 (hard to port) to 1 (hard to starboard).
var trim := 1.0      ## Balloon trim, Tuning.TRIM_MIN to Tuning.TRIM_MAX.
var calm := false    ## No wind. Flight tests fly in still air.
## The world's wind. The WorldSync sets it before adding the ship; a ship without
## one makes its own, which counts physics ticks.
var weather: Wind
var captain := 0     ## The peer id of the player whose ship it is, or 0 for nobody's.
var test := false    ## A test flight from the dock.
## False on clients: the ship is then a frozen, kinematic copy that follows the
## server's snapshots (spec §4.6), and no forces act on it. Set before adding it.
var simulated := true
## Held still, whatever the wind: a simulated ship stops dead and freezes. On clients
## it's only a flag, since their copies are frozen anyway. WorldSync's dedicated
## anchoring also freezes a ship while nobody is aboard.
var anchored := false:
	set(value):
		anchored = value
		if simulated:
			if value:
				linear_velocity = Vector3.ZERO
				angular_velocity = Vector3.ZERO
			freeze = value

var _balloons: Array[Vector3] = []
var _lift_stones: Array[Vector3] = []
var _propellers: Array[Vector3] = []
var _thrust_axes: Array[Vector3] = []   ## Each propeller's push direction, in ship space.
var _rudders: Array[Vector3] = []
var _rudder_sides: Array[Vector3] = []  ## Each rudder's flat-side normal, in ship space.
var _rudder_chords: Array[Vector3] = [] ## The way air flows along each rudder, in ship space.
var _sails: Array[Vector3] = []
var _sail_normals: Array[Vector3] = []  ## Each sail's facing, in ship space.
var _zones: Array[Dictionary] = []
var _power := 0.0  ## The share of full thrust the engines give each propeller.
var _last_good := Transform3D.IDENTITY
var _shapes: Array[CollisionShape3D] = []
var _mesh: MeshInstance3D
var _rebuild_pending := false


func _init(ship_grid: ShipGrid) -> void:
	grid = ship_grid


func _ready() -> void:
	if not simulated:
		freeze_mode = FREEZE_MODE_KINEMATIC
		freeze = true
	if weather == null:
		weather = Wind.new()
	can_sleep = false
	linear_damp_mode = DAMP_MODE_REPLACE
	angular_damp_mode = DAMP_MODE_REPLACE
	angular_damp = Tuning.ANGULAR_DAMPING
	if blueprint == null:
		blueprint = grid.whole()
	_last_good = global_transform
	interior = ShipInterior.new()
	rebuild()
	add_child(interior)
	var helms := grid.cells_of("helm")
	if not helms.is_empty():
		helm = Helm.new(self, helms[0])
		add_child(helm)


## Puts hit-point changes (cell -> hit points, 0 for destroyed) into the grid. When
## blocks went or came back she rebuilds, once, at the end of the frame, and this
## returns true.
func damage(changes: Dictionary) -> bool:
	var moved := Damage.apply(grid, changes, blueprint)
	if moved:
		_rebuild_soon()
	return moved


## Moves the blocks at cells, with their hit points, into a new grid with her paint,
## for a piece that breaks away. She rebuilds, once, at the end of the frame.
func take_cells(cells: Array) -> ShipGrid:
	var piece := ShipGrid.new()
	piece.paint = grid.paint.duplicate()
	for cell: Vector3i in cells:
		piece.blocks[cell] = grid.blocks[cell]
		grid.blocks.erase(cell)
	_rebuild_soon()
	return piece


func _rebuild_soon() -> void:
	if not _rebuild_pending:
		_rebuild_pending = true
		rebuild.call_deferred()


## Rebuilds everything that comes from the blocks, now: mass, shapes, the parts
## that fly her, the mesh and the interior's hull. A lost helm lets its pilot go,
## and she drifts, a wreck.
func rebuild() -> void:
	_rebuild_pending = false
	if grid.blocks.is_empty() or not is_inside_tree():
		return  # she's on her way out
	var props := grid.mass_properties()
	mass = props["mass"]
	center_of_mass_mode = CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = props["center"]
	inertia = props["inertia"]
	for shape in _shapes:
		shape.free()
	_shapes.clear()
	var boxes := grid.merged_boxes()
	for box in boxes:
		var cube := BoxShape3D.new()
		cube.size = box.size
		var shape := CollisionShape3D.new()
		shape.shape = cube
		shape.position = box.get_center()
		add_child(shape)
		_shapes.append(shape)
	for list: Array in [_balloons, _lift_stones, _propellers, _thrust_axes, _rudders, _rudder_sides, _rudder_chords, _sails, _sail_normals]:
		list.clear()
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
	for cell in grid.cells_of("sail"):
		_sails.append(Vector3(cell))
		_sail_normals.append(Blocks.facing(grid.blocks[cell]["rotation"]))
	_power = ShipForces.propeller_power(grid)
	_zones = grid.drag_zones()
	bounds = grid.bounds()
	if _mesh != null:
		_mesh.free()
	_mesh = ShipMesh.build(grid)
	add_child(_mesh)
	interior.reshape(boxes)
	if helm != null and grid.type_at(helm.cell) != "helm":
		helm.autopilot = false
		helm.leave(helm.pilot)
		helm.queue_free()
		helm = null
		anchored = false
	blocks_changed.emit()


## Whether she has lost her helm, so nobody can steer her.
func is_wreck() -> bool:
	return helm == null


## Lets peer go from any station they hold on her: the helm.
func release(peer: int) -> void:
	if helm != null:
		helm.leave(peer)


## Where crew come to after being knocked down, in ship space: standing on her
## first bunk (sorted) with room above it, else where slot 0 comes aboard.
func respawn_spot() -> Vector3:
	var bunks := grid.cells_of("bunk")
	bunks.sort()
	for bunk in bunks:
		if grid.type_at(bunk + Vector3i.UP) == "" and grid.type_at(bunk + Vector3i.UP * 2) == "":
			return Vector3(bunk + Vector3i.UP) + Vector3(0.0, 0.45, 0.0)
	return crew_spawn(0)


## Her hit points over her blueprint's, 0 to 1.
func condition() -> float:
	var full := 0
	for block: Dictionary in blueprint.blocks.values():
		full += Tuning.BLOCKS[block["type"]]["hp"]
	var left := 0
	for block: Dictionary in grid.blocks.values():
		left += block["hp"]
	return clampf(float(left) / full, 0.0, 1.0) if full > 0 else 0.0


## Spots next to the helm, nearest first, as offsets from the cell just aft of it.
## The last three are in front of it, for a helm with deck only ahead.
const SPAWN_SPOTS: Array[Vector3i] = [
	Vector3i(0, 0, 0), Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1),
	Vector3i(-1, 0, -1), Vector3i(1, 0, -1), Vector3i(-1, 0, 1), Vector3i(1, 0, 1),
	Vector3i(0, 0, -2), Vector3i(-1, 0, -2), Vector3i(1, 0, -2),
]


## Where crew come aboard, in ship space. Slot 0 stands just aft of the helm; later
## slots stand on the free spots around it, and share them when there are more
## crew than spots (crew don't collide with each other). A wreck has no helm, so
## everyone stands on top of her, near her middle.
func crew_spawn(slot := 0) -> Vector3:
	if helm == null:
		return Vector3(_spot_on_top()) + Vector3(0.0, 0.45, 0.0)
	var aft := helm.cell + Vector3i(0, 0, 1)
	var free: Array[Vector3i] = []
	for offset in SPAWN_SPOTS:
		var cell := aft + offset
		var below := grid.type_at(cell + Vector3i.DOWN)
		if grid.type_at(cell) == "" and grid.type_at(cell + Vector3i.UP) == "" and below != "" and below != "ladder":
			free.append(cell)
	var spot := free[slot % free.size()] if not free.is_empty() else aft
	return Vector3(spot) + Vector3(0.0, 0.45, 0.0)


## The empty cell over the highest block, with room to stand, in the column nearest
## the middle of her box. Ties go to the smallest cell.
func _spot_on_top() -> Vector3i:
	var middle := bounds.get_center()
	var best := Vector3i.ZERO
	var best_rank := INF
	for cell: Vector3i in grid.blocks:
		var above := cell + Vector3i.UP
		if grid.type_at(cell) == "ladder" or grid.blocks.has(above) or grid.blocks.has(above + Vector3i.UP):
			continue
		var rank := Vector2(cell.x - middle.x, cell.z - middle.z).length_squared()
		if rank < best_rank or (rank == best_rank and (above.y > best.y or (above.y == best.y and above < best))):
			best = above
			best_rank = rank
	return best


## Whether this ship is the first thing straight below world_point, within its own
## size and 2 m. Only valid during physics processing.
func is_over(world_point: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(world_point, world_point + Vector3.DOWN * (bounds.size.length() + 2.0))
	return get_world_3d().direct_space_state.intersect_ray(ray).get("collider") == self


## The velocity of the ship's body at world_point.
func point_velocity(world_point: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(world_point - global_transform * center_of_mass)


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
	var wind := Vector3.ZERO if calm else weather.at(state.transform.origin, weather.now())

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

	# Sails push along their normal, whichever face the wind hits, by the wind across them.
	for i in _sails.size():
		var offset := basis * _sails[i]
		var normal := basis * _sail_normals[i]
		var flow := (wind - state.get_velocity_at_local_position(offset)).dot(normal)
		var density := ShipForces.air_density(altitude + offset.y)
		var push := 0.5 * Tuning.AIR_DENSITY * density * Tuning.SAIL_COEFFICIENT * Tuning.SAIL_AREA * flow * absf(flow)
		state.apply_force(normal * push, offset)


func _sane(state: PhysicsDirectBodyState3D) -> bool:
	return state.transform.is_finite() and state.linear_velocity.is_finite() and state.angular_velocity.is_finite() \
			and state.linear_velocity.length() <= MAX_SPEED and state.angular_velocity.length() <= MAX_SPIN
