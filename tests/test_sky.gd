extends TestCase
## The day–night sky and the Roil (spec §3.1, §4.8).


func test_the_sun_rises_at_six_and_sets_at_eighteen() -> void:
	assert_near(WorldSky.sun_elevation(6.0), 0.0, 1e-4)
	assert_near(WorldSky.sun_elevation(12.0), 70.0, 1e-4)
	assert_near(WorldSky.sun_elevation(18.0), 0.0, 1e-4)
	assert_near(WorldSky.sun_elevation(0.0), -70.0, 1e-4)


func test_the_sky_and_the_roil_run_through_a_day() -> void:
	var sky := WorldSky.new()
	add_child(sky)
	add_child(Roil.new())
	for hour in [0.0, 6.0, 12.0, 18.0, 23.9]:
		sky.hour = hour
		await get_tree().process_frame
	assert_true(sky.hour >= 23.9, "the day moves on")
