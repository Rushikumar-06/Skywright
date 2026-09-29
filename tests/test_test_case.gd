extends TestCase
## The assert helpers themselves, so a broken helper can't hide failures.


func test_assert_eq_fails_on_different_values_or_types() -> void:
	var probe := TestCase.new()
	probe.assert_eq(1, 2)
	probe.assert_eq(1, 1.0, "int and float differ")
	probe.assert_eq({"a": 1}, {"a": 1})
	assert_eq(probe.failures.size(), 2)
	probe.free()


func test_assert_near_fails_on_nan() -> void:
	var probe := TestCase.new()
	probe.assert_near(NAN, 0.0, 1.0)
	probe.assert_near(0.5, 0.0, 1.0)
	assert_eq(probe.failures.size(), 1)
	probe.free()


func test_wait_until_waits_frame_by_frame() -> void:
	var calls := [0]
	var third_call := func() -> bool:
		calls[0] += 1
		return calls[0] >= 3
	assert_true(await wait_until(third_call, 1.0))
	assert_eq(calls[0], 3)


func test_wait_until_gives_up_after_the_timeout() -> void:
	assert_false(await wait_until(func() -> bool: return false, 0.1))


func test_simulate_runs_that_many_physics_ticks() -> void:
	var start := Engine.get_physics_frames()
	await simulate(0.5)
	assert_eq(Engine.get_physics_frames() - start, 30)
