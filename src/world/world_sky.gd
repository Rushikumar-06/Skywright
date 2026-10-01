class_name WorldSky
extends Node3D
## The sky over the world (spec §3.1, §4.8): a sun and a moon crossing it once a
## day, sky colours that follow the sun, and haze toward the horizon.

const DAY_LENGTH := 1200.0  ## Real seconds in a whole day.
const START_HOUR := 10.0    ## The hour when a world begins.

const DAY_TOP := Color("2f63a8")
const DAY_HORIZON := Color("b7d0ea")
const DUSK_HORIZON := Color("e7a974")
const NIGHT_TOP := Color("04070f")
const NIGHT_HORIZON := Color("16203a")

var hour := START_HOUR  ## Time of day, 0 to 24. The world sets it from its clock.
var storm := 0.0        ## 0 to 1: how rough the air is at the camera. The world sets it.

const STORM_FOG := Color("4a4656")

var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _sky: ProceduralSkyMaterial
var _environment: Environment


## The hour of the day seconds after a world began.
static func hour_at(seconds: float) -> float:
	return fposmod(START_HOUR + seconds * 24.0 / DAY_LENGTH, 24.0)


## The sun's height above the horizon in degrees at a time of day: it rises at 6,
## is highest at noon and sets at 18.
static func sun_elevation(at_hour: float) -> float:
	return 70.0 * sin((at_hour - 6.0) / 24.0 * TAU)


func _ready() -> void:
	_sky = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = _sky
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	_environment.glow_enabled = true
	_environment.fog_enabled = true
	_environment.fog_mode = Environment.FOG_MODE_DEPTH
	_environment.fog_depth_begin = 900.0
	_environment.fog_depth_end = 2600.0
	_environment.fog_sky_affect = 0.0
	var world_environment := WorldEnvironment.new()
	world_environment.environment = _environment
	add_child(world_environment)

	_sun = DirectionalLight3D.new()
	_sun.light_color = Color("fff1dc")
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_max_distance = 300.0
	add_child(_sun)
	_moon = DirectionalLight3D.new()
	_moon.light_color = Color("9fb4e0")
	_moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	_moon.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	add_child(_moon)
	_apply()


func _process(_delta: float) -> void:
	_apply()


func _apply() -> void:
	var elevation := sun_elevation(hour)
	# The sun rises in the east (+X), passes south (+Z) and sets in the west.
	_sun.rotation_degrees = Vector3(-elevation, 90.0 - 15.0 * (hour - 6.0), 0.0)
	var day := smoothstep(-8.0, 12.0, elevation)
	var glow := clampf(1.0 - absf(elevation - 2.0) / 14.0, 0.0, 1.0)
	_sun.light_energy = 1.4 * day
	_sun.shadow_enabled = elevation > 0.0
	_moon.light_energy = 0.4 * (1.0 - day)
	_sky.sky_top_color = NIGHT_TOP.lerp(DAY_TOP, day)
	_sky.sky_horizon_color = NIGHT_HORIZON.lerp(DAY_HORIZON, day).lerp(DUSK_HORIZON, glow * 0.6)
	_sky.ground_horizon_color = _sky.sky_horizon_color
	_sky.ground_bottom_color = _sky.sky_horizon_color
	# Inside a storm or the Stormwall the fog closes in.
	_environment.fog_depth_begin = lerpf(900.0, 30.0, storm)
	_environment.fog_depth_end = lerpf(2600.0, 400.0, storm)
	_environment.fog_light_color = _sky.sky_horizon_color.lerp(STORM_FOG, storm)
