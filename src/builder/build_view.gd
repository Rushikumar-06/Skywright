class_name BuildView
extends SubViewport
## The shipyard's 3D view, in a world of its own: the design under a clear sky on a
## grid of lines, the block about to be placed as a ghost, the centres of mass and
## lift as markers that show through the hull, and a camera orbiting the design.

const MASS_COLOR := Color("e8a948")
const LIFT_COLOR := Color("7fd3f5")
const GRID_MARGIN := 6.0      ## m the grid reaches past the design.
const FOCUS_EASE := 6.0       ## 1/s: how fast the camera's focus follows the design.
const MIN_DISTANCE := 6.0
const MAX_DISTANCE := 160.0
const ORBIT_SPEED := 0.006    ## Radians per pixel dragged.

var camera: Camera3D
var yaw := 0.7
var pitch := -0.5
var distance := 36.0
var focus := Vector3.ZERO
var ship_mesh: MeshInstance3D  ## The design as drawn.

var _target := Vector3.ZERO    ## Where focus is easing to: the design's centre.
var _grid_lines: MeshInstance3D
var _mirror_plane: MeshInstance3D
var _ghost: MeshInstance3D
var _ghost_kind := []          ## [type, rotation] the ghost was built for.
var _invalid: StandardMaterial3D
var _mass_marker: Node3D
var _lift_marker: Node3D
var _marker_line: MeshInstance3D


func _init() -> void:
	own_world_3d = true
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color("3d6fb6")
	sky.sky_horizon_color = Color("a9c7e8")
	sky.ground_bottom_color = Color("2b3440")
	sky.ground_horizon_color = Color("a9c7e8")
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	environment.sky.sky_material = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation = Vector3(-0.9, 0.6, 0.0)
	add_child(sun)
	camera = Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.far = 1000.0
	add_child(camera)
	ship_mesh = MeshInstance3D.new()
	add_child(ship_mesh)
	_grid_lines = MeshInstance3D.new()
	add_child(_grid_lines)
	_mirror_plane = MeshInstance3D.new()
	_mirror_plane.mesh = QuadMesh.new()
	_mirror_plane.rotation.y = PI / 2  # facing across the keel line
	_mirror_plane.material_override = _unshaded(Color(UiTheme.ACCENT, 0.07), false)
	(_mirror_plane.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(_mirror_plane)
	_invalid = _unshaded(Color(1.0, 0.15, 0.1, 0.6), false)
	_mass_marker = _marker(MASS_COLOR, "Weight")
	_lift_marker = _marker(LIFT_COLOR, "Lift")
	_marker_line = MeshInstance3D.new()
	_marker_line.material_override = _unshaded(Color.WHITE, true)
	add_child(_marker_line)
	_place_camera()


func _process(delta: float) -> void:
	focus = focus.lerp(_target, 1.0 - exp(-FOCUS_EASE * delta))
	_place_camera()


## Draws grid with its markers and the grid lines around it, and the mirror plane when mirror.
func show_design(grid: ShipGrid, stats: ShipStats, mirror: bool) -> void:
	var fresh := ShipMesh.build(grid)
	ship_mesh.mesh = fresh.mesh
	fresh.free()
	var bounds := grid.bounds().grow(GRID_MARGIN)
	_target = grid.bounds().get_center()
	_grid_lines.mesh = _lines_for(bounds)
	_mirror_plane.visible = mirror
	_mirror_plane.position = Vector3(0.0, bounds.get_center().y, bounds.get_center().z)
	(_mirror_plane.mesh as QuadMesh).size = Vector2(bounds.size.z, bounds.size.y)
	var has_lift := stats.lift > 0.0
	_mass_marker.visible = stats.blocks > 0
	_mass_marker.position = stats.center_of_mass
	_lift_marker.visible = has_lift
	_lift_marker.position = stats.center_of_lift
	_marker_line.visible = has_lift and stats.blocks > 0
	var line := ImmediateMesh.new()
	line.surface_begin(Mesh.PRIMITIVE_LINES)
	line.surface_add_vertex(stats.center_of_mass)
	line.surface_add_vertex(stats.center_of_lift)
	line.surface_end()
	_marker_line.mesh = line


## Shows a see-through type turned by rotation at cell, tinted red where it can't go.
func show_ghost(type: String, rotation: int, cell: Vector3i, valid: bool) -> void:
	if _ghost_kind != [type, rotation]:
		if _ghost != null:
			_ghost.free()
		var one := ShipGrid.new()
		one.set_block(Vector3i.ZERO, type, rotation)
		_ghost = ShipMesh.build(one)
		_ghost.transparency = 0.5
		add_child(_ghost)
		_ghost_kind = [type, rotation]
	_ghost.visible = true
	_ghost.position = Vector3(cell)
	_ghost.material_overlay = null if valid else _invalid


func hide_ghost() -> void:
	if _ghost != null:
		_ghost.visible = false


## Where a click at point (in this view's pixels) would place and remove:
## {"place": Vector3i, "remove": Vector3i} over a block, {"place": Vector3i} over the
## grid plane, and {} pointing at the sky.
func aim(point: Vector2, grid: ShipGrid) -> Dictionary:
	var from := camera.project_ray_origin(point)
	var direction := camera.project_ray_normal(point)
	var hit := grid.raycast(from, direction, MAX_DISTANCE * 2.0)
	if not hit.is_empty():
		return {"place": (hit["cell"] as Vector3i) + (hit["normal"] as Vector3i), "remove": hit["cell"]}
	if direction.y >= 0.0:
		return {}
	var along := (-0.5 - from.y) / direction.y
	if along > MAX_DISTANCE * 2.0:  # a near-flat ray lands out of the grid's reach
		return {}
	var on_plane := from + direction * along
	return {"place": Vector3i(roundi(on_plane.x), 0, roundi(on_plane.z))}


## Orbits the camera by a drag of by pixels.
func orbit(by: Vector2) -> void:
	yaw -= by.x * ORBIT_SPEED
	pitch = clampf(pitch - by.y * ORBIT_SPEED, -1.5, 0.3)
	_place_camera()


func zoom(factor: float) -> void:
	distance = clampf(distance * factor, MIN_DISTANCE, MAX_DISTANCE)
	_place_camera()


## Puts the camera at from looking at at, as orbit angles, so it stays there.
func look_from(from: Vector3, at: Vector3) -> void:
	var offset := from - at
	distance = maxf(offset.length(), 0.01)
	pitch = asin(clampf(-offset.y / distance, -1.0, 1.0))
	yaw = atan2(offset.x, offset.z)
	focus = at
	_target = at
	_place_camera()


## The camera from the orbit angles: built from them, never looking_at, so looking
## straight down works.
func _place_camera() -> void:
	var b := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	camera.transform = Transform3D(b, focus + b.z * distance)


## The floor grid at y = -0.5 on cell edges across bounds, with the keel line (x = 0) in the accent colour.
func _lines_for(bounds: AABB) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var low := Vector2i(floori(bounds.position.x), floori(bounds.position.z))
	var high := Vector2i(ceili(bounds.end.x), ceili(bounds.end.z))
	st.set_color(Color(1, 1, 1, 0.25))
	for x in range(low.x, high.x + 1):
		st.add_vertex(Vector3(x + 0.5, -0.5, low.y + 0.5))
		st.add_vertex(Vector3(x + 0.5, -0.5, high.y + 0.5))
	for z in range(low.y, high.y + 1):
		st.add_vertex(Vector3(low.x + 0.5, -0.5, z + 0.5))
		st.add_vertex(Vector3(high.x + 0.5, -0.5, z + 0.5))
	st.set_color(UiTheme.ACCENT)
	st.add_vertex(Vector3(0, -0.49, low.y + 0.5))
	st.add_vertex(Vector3(0, -0.49, high.y + 0.5))
	var mesh := st.commit()
	var material := _unshaded(Color.WHITE, false)
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_set_material(0, material)
	return mesh


## A sphere of radius 0.35 labelled text, drawn over everything.
func _marker(color: Color, text: String) -> Node3D:
	var sphere := SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	var marker := MeshInstance3D.new()
	marker.mesh = sphere
	marker.material_override = _unshaded(color, true)
	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.no_depth_test = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 0.8
	label.fixed_size = true  # the same size on screen however far the camera is
	label.pixel_size = 0.0012
	label.outline_size = 8
	marker.add_child(label)
	marker.visible = false
	add_child(marker)
	return marker


static func _unshaded(color: Color, on_top: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = on_top
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
