extends TestCase
## SnapshotBuffer (spec §4.6): Hermite curves through timed snapshots, and capped
## dead reckoning past the newest.

const EPSILON := 1e-4


func buffer_with(samples: Array) -> SnapshotBuffer:
	var buffer := SnapshotBuffer.new()
	for s: Array in samples:
		buffer.push(s[0], s[1], s[2], s[3] if s.size() > 3 else Quaternion.IDENTITY, s[4] if s.size() > 4 else Vector3.ZERO)
	return buffer


func assert_vec(actual: Vector3, expected: Vector3, message := "") -> void:
	assert_true(actual.is_equal_approx(expected) or actual.distance_to(expected) < EPSILON, "%s: expected %s, got %s" % [message, expected, actual])


func test_an_empty_buffer_says_so() -> void:
	var buffer := SnapshotBuffer.new()
	assert_true(buffer.is_empty())
	buffer.push(1.0, Vector3.ZERO, Vector3.ZERO, Quaternion.IDENTITY)
	assert_false(buffer.is_empty())


func test_samples_hit_the_snapshots_exactly() -> void:
	var turned := Quaternion(Vector3.UP, 0.5)
	var buffer := buffer_with([
		[1.0, Vector3(1, 2, 3), Vector3(4, 0, 0)],
		[1.1, Vector3(1.5, 2, 3), Vector3(5, 0, 0), turned],
	])
	var at := buffer.sample(1.1)
	assert_vec(at["position"], Vector3(1.5, 2, 3), "position")
	assert_vec(at["velocity"], Vector3(5, 0, 0), "velocity")
	assert_true((at["rotation"] as Quaternion).is_equal_approx(turned), "rotation")
	assert_vec(buffer.sample(1.0)["position"], Vector3(1, 2, 3), "the first")


func test_steady_motion_interpolates_exactly() -> void:
	var v := Vector3(3, -1, 2)
	var buffer := buffer_with([[0.0, Vector3.ZERO, v], [0.1, v * 0.1, v], [0.2, v * 0.2, v]])
	for t in [0.0, 0.025, 0.05, 0.1, 0.13, 0.2]:
		var at := buffer.sample(t)
		assert_vec(at["position"], v * t, "position at %s" % t)
		assert_vec(at["velocity"], v, "velocity at %s" % t)


func test_a_curve_follows_its_velocities() -> void:
	# From rest to rest over 1 m: a Hermite curve eases in and out, so it's halfway
	# at the midpoint but still at the start's speed at the ends.
	var buffer := buffer_with([[0.0, Vector3.ZERO, Vector3.ZERO], [1.0, Vector3(1, 0, 0), Vector3.ZERO]])
	assert_vec(buffer.sample(0.5)["position"], Vector3(0.5, 0, 0), "halfway")
	assert_vec(buffer.sample(0.5)["velocity"], Vector3(1.5, 0, 0), "fastest in the middle")
	assert_true(buffer.sample(0.25)["position"].x < 0.25, "slow to start")
	# Moving fast at both ends bulges past the straight line: p = (p0 + p1) / 2 + (v0 - v1) dt / 8.
	var swerve := buffer_with([[0.0, Vector3.ZERO, Vector3(0, 0, 4)], [1.0, Vector3(1, 0, 0), Vector3(0, 0, -4)]])
	assert_vec(swerve.sample(0.5)["position"], Vector3(0.5, 0, 1.0), "the midpoint")


func test_rotations_slerp() -> void:
	var buffer := buffer_with([
		[0.0, Vector3.ZERO, Vector3.ZERO, Quaternion.IDENTITY],
		[1.0, Vector3.ZERO, Vector3.ZERO, Quaternion(Vector3.UP, 1.0)],
	])
	assert_true((buffer.sample(0.25)["rotation"] as Quaternion).is_equal_approx(Quaternion(Vector3.UP, 0.25)))


func test_extrapolation_stops_after_a_quarter_second_and_spins() -> void:
	var spin := Vector3(0, 2, 0)
	var buffer := buffer_with([[0.0, Vector3.ZERO, Vector3(10, 0, 0), Quaternion.IDENTITY, spin]])
	var at := buffer.sample(0.1)
	assert_vec(at["position"], Vector3(1, 0, 0), "carries on at its velocity")
	assert_true((at["rotation"] as Quaternion).is_equal_approx(Quaternion(Vector3.UP, 0.2)), "and spins")
	var late := buffer.sample(5.0)
	assert_vec(late["position"], Vector3(10 * SnapshotBuffer.EXTRAPOLATE, 0, 0), "then stops")
	assert_true((late["rotation"] as Quaternion).is_equal_approx(Quaternion(Vector3.UP, 2 * SnapshotBuffer.EXTRAPOLATE)))
	assert_vec(late["velocity"], Vector3(10, 0, 0), "still saying how it was moving")


func test_before_the_first_sample_the_first_is_given() -> void:
	var buffer := buffer_with([[1.0, Vector3(1, 1, 1), Vector3(9, 0, 0)], [1.1, Vector3(2, 1, 1), Vector3(9, 0, 0)]])
	assert_vec(buffer.sample(0.0)["position"], Vector3(1, 1, 1))


func test_late_and_out_of_order_samples_are_ignored() -> void:
	var buffer := buffer_with([[1.0, Vector3.ZERO, Vector3.ZERO], [1.2, Vector3(2, 0, 0), Vector3.ZERO]])
	buffer.push(1.1, Vector3(100, 0, 0), Vector3.ZERO, Quaternion.IDENTITY)
	buffer.push(1.2, Vector3(100, 0, 0), Vector3.ZERO, Quaternion.IDENTITY)
	assert_vec(buffer.sample(1.1)["position"], Vector3(1, 0, 0), "the curve is untouched")
	assert_vec(buffer.sample(1.2)["position"], Vector3(2, 0, 0))


func test_old_samples_are_dropped() -> void:
	var buffer := SnapshotBuffer.new()
	for i in 300:
		buffer.push(i / 30.0, Vector3(i, 0, 0), Vector3(30, 0, 0), Quaternion.IDENTITY)
	assert_true(buffer._samples.size() <= ceili(SnapshotBuffer.KEEP * 30.0) + 2, "%d kept" % buffer._samples.size())
	assert_vec(buffer.sample(299 / 30.0 - 0.5)["position"], Vector3(299 - 15, 0, 0), "recent ones still work")
