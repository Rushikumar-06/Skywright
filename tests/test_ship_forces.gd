extends TestCase
## The flight model's formulas (spec §4.4).


func test_air_is_densest_at_the_roil_and_thins_above() -> void:
	assert_eq(ShipForces.air_density(200.0), 1.0)
	assert_eq(ShipForces.air_density(-50.0), 1.0, "no denser below the Roil's top")
	assert_near(ShipForces.air_density(2700.0), exp(-1.0), 1e-6)
	assert_near(ShipForces.air_density(800.0), 0.7866, 1e-4)


func test_drag_opposes_motion_along_each_axis_and_grows_with_speed_squared() -> void:
	var area := Vector3(2, 3, 4)
	var slow := ShipForces.zone_drag(area, Vector3(0, 0, -10), 1.0)
	var fast := ShipForces.zone_drag(area, Vector3(0, 0, -20), 1.0)
	assert_eq(slow.x, 0.0)
	assert_true(slow.z > 0.0, "moving toward -Z, drag pushes toward +Z")
	assert_near(fast.z, slow.z * 4.0, 1e-3)
	assert_near(slow.z, 0.5 * Tuning.AIR_DENSITY * Tuning.DRAG_COEFFICIENT * 4.0 * 100.0, 1e-3)
	var sideways := ShipForces.zone_drag(area, Vector3(-5, 0, 0), 0.5)
	assert_near(sideways.x, 0.5 * Tuning.AIR_DENSITY * 0.5 * Tuning.DRAG_COEFFICIENT * 2.0 * 25.0, 1e-3)


func test_the_keel_pushes_against_sideslip_only_when_moving_forward() -> void:
	assert_eq(ShipForces.keel(10.0, Vector3(3, 0, 0), 1.0), 0.0, "no forward speed, no keel")
	var slipping_right := ShipForces.keel(10.0, Vector3(3, 0, -20), 1.0)
	assert_true(slipping_right < 0.0, "pushes back to port")
	assert_near(ShipForces.keel(10.0, Vector3(3, 0, -40), 1.0), slipping_right * 2.0, 1e-3, "twice as hard at twice the speed")
	assert_near(slipping_right, -0.5 * Tuning.AIR_DENSITY * Tuning.HULL_LIFT * 10.0 * 20.0 * 3.0, 1e-3)


func test_top_speed_is_where_thrust_meets_drag() -> void:
	var speed := ShipForces.top_speed(5000.0, 50.0, 800.0)
	var drag := ShipForces.zone_drag(Vector3(0, 0, 50.0), Vector3(0, 0, -speed), ShipForces.air_density(800.0))
	assert_near(drag.z, 5000.0, 0.01)
	assert_eq(ShipForces.top_speed(0.0, 50.0, 800.0), 0.0)


func test_the_prevailing_wind_circles_the_eye_counter_clockwise() -> void:
	# Gusts come and go; over ten minutes they average out, leaving the prevailing wind.
	var sum := Vector3.ZERO
	for second in 600:
		sum += Wind.at(Vector3(0, 800, 7000), second)  # due south of the Eye
	assert_near((sum / 600.0).x, Wind.PREVAILING, 0.3, "blowing east there")
	assert_near((sum / 600.0).z, 0.0, 0.3)
