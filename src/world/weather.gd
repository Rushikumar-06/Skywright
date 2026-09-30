class_name Weather
extends Node3D
## The weather over the Roil (spec §3.1): two fog sheets that follow the camera, a
## dark column of cloud in each storm cell, and lightning, in the storms and under
## the islands. It's only visual: every machine makes its own bolts, and a dedicated
## server has none. Storm columns move with the world clock, so everyone sees them
## in the same places.

const SHEETS := [240.0, 290.0]     ## m: the fog sheets' heights.
const SIZE := 60000.0              ## m across a sheet.
const COLUMN_PUFFS := 20
const COLUMN_FROM := 250.0         ## m: a storm column's foot and top.
const COLUMN_TO := 2000.0
const STORM_RANGE := 3000.0        ## m: storms this near the camera strike.
const STORM_BOLT_TOP := 1800.0     ## m: where a storm's bolts start.
const ROIL_RANGE := 1000.0         ## m: strikes under the islands land this near the camera.
const ROIL_DEPTH := 60.0           ## m under the surface.
const BOLT_WIDTH := 3.0
const BOLT_LIFE := 0.2             ## s a bolt and its light last.
const FOG := Color("9d8ea6")
const BOLT_COLOR := Color("c7d4ff")
const STORM_CLOUD := Color("3a3946")

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec3 fog : source_color = vec3(0.616, 0.557, 0.651);
varying vec3 world_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Long streaks along x, drifting; each sheet's height gives it its own pattern.
	vec2 p = world_position.xz * 0.003 + world_position.y * 0.37;
	float streak = 0.6 * noise(p * vec2(0.5, 3.0) + vec2(TIME * 0.02, 0.0)) + 0.4 * noise(p * vec2(1.3, 7.0) - vec2(TIME * 0.035, 0.0));
	float near_camera = smoothstep(0.0, 30.0, abs(world_position.y - CAMERA_POSITION_WORLD.y));
	float far_away = 1.0 - smoothstep(12000.0, 28000.0, length(world_position.xz - CAMERA_POSITION_WORLD.xz));
	ALBEDO = fog;
	ALPHA = 0.55 * smoothstep(0.3, 0.75, streak) * near_camera * far_away;
}
"""

## Where the viewer is, when set; otherwise the current camera. Tests set it.
var viewer: Node3D
var bolts_struck := 0                              ## Every bolt this node has made.
var columns: Array[MultiMeshInstance3D] = []       ## One per storm, in WorldGen.storms' order.
var sheets: Array[MeshInstance3D] = []

var _gen: WorldGen
var _clock: Callable
var _random := RandomNumberGenerator.new()
var _next_storm: Array[float] = []  ## Seconds to each storm's next bolt, while it's near.
var _next_roil := 0.0
var _bolts: Array[Dictionary] = []  ## {"mesh": MeshInstance3D, "light": OmniLight3D, "age": float}
var _bolt_material: StandardMaterial3D


## clock returns the world's seconds, where storm cells are found.
func _init(world_gen: WorldGen, clock: Callable) -> void:
	name = "Weather"
	_gen = world_gen
	_clock = clock
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_bolt_material = StandardMaterial3D.new()
	_bolt_material.albedo_color = Color.BLACK
	_bolt_material.emission_enabled = true
	_bolt_material.emission = BOLT_COLOR
	_bolt_material.emission_energy_multiplier = 6.0
	_bolt_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_next_roil = _random.randf_range(2.0, 9.0)
	_make_sheets()
	_make_columns()
	_place_columns()


func _process(delta: float) -> void:
	_place_columns()
	_age_bolts(delta)
	var at := _viewer_position()
	if is_nan(at.x):
		return  # nobody to see anything
	for i in sheets.size():
		sheets[i].position = Vector3(at.x, SHEETS[i], at.z)
	for i in _gen.storms.size():
		var storm := _gen.storm_center(i, _clock.call())
		if Vector2(storm.x - at.x, storm.z - at.z).length() > STORM_RANGE:
			continue
		_next_storm[i] -= delta
		if _next_storm[i] <= 0.0:
			_next_storm[i] = _random.randf_range(1.0, 4.0)
			var radius: float = _gen.storms[i]["radius"]
			var top := _random_disc(radius)
			var foot := _random_disc(radius)
			strike(storm + Vector3(top.x, STORM_BOLT_TOP, top.y), storm + Vector3(foot.x, Tuning.ROIL_ALTITUDE, foot.y))
	_next_roil -= delta
	if _next_roil <= 0.0:
		_next_roil = _random.randf_range(2.0, 9.0)
		var spot := _random_disc(ROIL_RANGE)
		var start := Vector3(at.x + spot.x, Tuning.ROIL_ALTITUDE - ROIL_DEPTH, at.z + spot.y)
		var heading := _random.randf() * TAU
		var run := _random.randf_range(200.0, 500.0)
		strike(start, start + Vector3(cos(heading) * run, _random.randf_range(-20.0, 20.0), sin(heading) * run))


## A bolt from from to to, a jagged ribbon facing the viewer, lit by a flickering light
## for BOLT_LIFE seconds. Its vertices are in world space.
func strike(from: Vector3, to: Vector3) -> MeshInstance3D:
	bolts_struck += 1
	var length := maxf(from.distance_to(to), 0.001)
	var along := (to - from) / length
	var middle := (from + to) / 2.0
	var eye := _viewer_position()
	var side := Vector3.ZERO
	if not is_nan(eye.x):
		side = along.cross(eye - middle)
	if side.length_squared() < 1e-6:
		side = along.cross(Vector3.UP if absf(along.y) < 0.99 else Vector3.RIGHT)
	side = side.normalized()
	var segments := _random.randi_range(10, 14)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for k in segments + 1:
		var jitter := 0.0 if k == 0 or k == segments else _random.randf_range(-0.1, 0.1) * length
		var point := from.lerp(to, float(k) / segments) + side * jitter
		vertices.append_array(PackedVector3Array([point - side * BOLT_WIDTH / 2.0, point + side * BOLT_WIDTH / 2.0]))
		normals.append_array(PackedVector3Array([along.cross(side), along.cross(side)]))
		if k > 0:
			indices.append_array(PackedInt32Array([2 * k - 2, 2 * k - 1, 2 * k, 2 * k - 1, 2 * k + 1, 2 * k]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _bolt_material)
	var bolt := MeshInstance3D.new()
	bolt.name = "Bolt"
	bolt.mesh = mesh
	bolt.top_level = true  # its vertices are in world space
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = BOLT_COLOR
	light.omni_range = 900.0
	light.top_level = true
	light.shadow_enabled = false
	add_child(bolt)
	add_child(light)
	light.global_position = middle
	_bolts.append({"mesh": bolt, "light": light, "age": 0.0})
	return bolt


func _age_bolts(delta: float) -> void:
	for bolt in _bolts.duplicate():
		bolt["age"] += delta
		if bolt["age"] >= BOLT_LIFE:
			bolt["mesh"].queue_free()
			bolt["light"].queue_free()
			_bolts.erase(bolt)
		else:
			var lit := _random.randf() > 0.3
			bolt["mesh"].visible = lit
			bolt["light"].light_energy = 8.0 if lit else 0.0


## The viewer's place, or NAN when there's neither a viewer nor a camera.
func _viewer_position() -> Vector3:
	var seen: Node3D = viewer
	if seen == null and is_inside_tree():
		seen = get_viewport().get_camera_3d()
	if seen == null or not seen.is_inside_tree():
		return Vector3.INF * NAN
	return seen.global_position


## A point in a disc of radius around the origin, as x and z.
func _random_disc(radius: float) -> Vector2:
	return Vector2.from_angle(_random.randf() * TAU) * radius * sqrt(_random.randf())


func _make_sheets() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	var shader := Shader.new()
	shader.code = SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("fog", FOG)
	for height: float in SHEETS:
		var sheet := MeshInstance3D.new()
		sheet.name = "Sheet%d" % sheets.size()
		sheet.mesh = plane
		sheet.material_override = material
		sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sheet.position.y = height
		add_child(sheet)
		sheets.append(sheet)


func _make_columns() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = STORM_CLOUD
	material.roughness = 1.0
	for i in _gen.storms.size():
		var radius: float = _gen.storms[i]["radius"]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([_gen.world_seed, i, "column"])
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = WorldChunk.puff_mesh()
		multimesh.instance_count = COLUMN_PUFFS
		for k in COLUMN_PUFFS:
			var width := radius * rng.randf_range(0.9, 1.5)
			var offset := Vector2.from_angle(rng.randf() * TAU) * radius * 0.4 * sqrt(rng.randf())
			var at := Vector3(offset.x, lerpf(COLUMN_FROM, COLUMN_TO, float(k) / (COLUMN_PUFFS - 1)), offset.y)
			var basis := Basis.from_scale(Vector3(width, width * 0.6, width)).rotated(Vector3.UP, rng.randf() * TAU)
			multimesh.set_instance_transform(k, Transform3D(basis, at))
		var column := MultiMeshInstance3D.new()
		column.name = "Storm%d" % i
		column.multimesh = multimesh
		column.material_override = material
		column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(column)
		columns.append(column)
		_next_storm.append(_random.randf_range(1.0, 4.0))


func _place_columns() -> void:
	var now: float = _clock.call()
	for i in columns.size():
		columns[i].position = _gen.storm_center(i, now)
