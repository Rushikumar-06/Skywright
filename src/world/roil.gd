class_name Roil
extends Node3D
## The Roil: the storm sea under the islands, its top at 200 m (spec §3.1, §4.7).
## A dark, churning surface that follows the camera so it never ends, with
## lightning flashing underneath.

const SIZE := 60000.0  ## m across the drawn surface, so its edge hides in the haze.

const SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform float flash = 0.0;
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

float clouds(vec2 p) {
	float sum = 0.0;
	float weight = 0.5;
	for (int i = 0; i < 5; i++) {
		sum += weight * noise(p);
		p *= 2.03;
		weight *= 0.5;
	}
	return sum;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz * 0.004;
	float churn = 0.6 * clouds(p + vec2(TIME * 0.02, TIME * 0.013)) + 0.4 * clouds(p * 2.7 - vec2(TIME * 0.035, 0.0));
	ALBEDO = mix(vec3(0.02, 0.018, 0.035), vec3(0.2, 0.17, 0.26), churn * churn);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = vec3(0.55, 0.6, 1.0) * flash * churn * 2.0;
}
"""

var _surface: MeshInstance3D
var _material: ShaderMaterial
var _lightning: OmniLight3D
var _next_flash := 3.0
var _flash_left := 0.0
var _random := RandomNumberGenerator.new()


func _ready() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	var shader := Shader.new()
	shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_surface = MeshInstance3D.new()
	_surface.mesh = plane
	_surface.material_override = _material
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_surface.position.y = Tuning.ROIL_ALTITUDE
	_surface.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_surface)
	_lightning = OmniLight3D.new()
	_lightning.light_color = Color("c7d4ff")
	_lightning.omni_range = 900.0
	_lightning.light_energy = 0.0
	_lightning.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_lightning)


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var at := camera.global_position
		_surface.global_position = Vector3(at.x, Tuning.ROIL_ALTITUDE, at.z)
	_next_flash -= delta
	if _next_flash <= 0.0:
		_next_flash = _random.randf_range(2.0, 9.0)
		_flash_left = _random.randf_range(0.08, 0.25)
		var around := _surface.global_position
		_lightning.global_position = around + Vector3(_random.randf_range(-700.0, 700.0), -60.0, _random.randf_range(-700.0, 700.0))
	_flash_left -= delta
	var flash := 1.0 if _flash_left > 0.0 and _random.randf() > 0.3 else 0.0
	_lightning.light_energy = 8.0 * flash
	_material.set_shader_parameter("flash", flash)
