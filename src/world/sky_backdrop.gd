class_name SkyBackdrop
extends Node3D
## A slow drift through golden-hour sky above the storm, behind the menus.

const DRIFT := 0.02  ## Camera yaw in radians per second.

var _camera: Camera3D
var _yaw := 0.0


func _ready() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("27497a")
	sky_material.sky_horizon_color = Color("e7b98c")
	sky_material.ground_horizon_color = Color("7a6479")
	sky_material.ground_bottom_color = Color("1b1828")
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color("9d8ea6")
	env.fog_density = 0.00035
	env.fog_sky_affect = 0.15
	env.fog_height = 300.0
	env.fog_height_density = 0.004
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-10.0, 150.0, 0.0)
	sun.light_color = Color("ffd6a3")
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)

	for spec: Array in [[Vector3(-220, 760, -900), 70.0], [Vector3(340, 820, -1400), 110.0],
			[Vector3(-640, 690, -1800), 90.0], [Vector3(130, 745, -520), 34.0],
			[Vector3(900, 700, 300), 80.0], [Vector3(-1100, 780, 700), 120.0]]:
		add_child(Island.create(spec[0], spec[1]))

	_camera = Camera3D.new()
	_camera.position = Vector3(0, 800, 0)
	_camera.far = 6000.0
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)
	_camera.make_current()


func _process(delta: float) -> void:
	_yaw += DRIFT * delta
	_camera.rotation = Vector3(deg_to_rad(-4.0), _yaw, 0.0)
