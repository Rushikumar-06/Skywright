extends TestCase
## The block catalogue and the 24 ways a block can face.


func test_every_block_is_in_the_catalogue() -> void:
	for type: String in Tuning.BLOCKS:
		assert_true(Blocks.INFO.has(type), "%s has catalogue text" % type)
		if not Blocks.INFO.has(type):
			continue
		var info: Dictionary = Blocks.INFO[type]
		assert_false((info["name"] as String).is_empty(), "%s has a name" % type)
		assert_false((info["about"] as String).is_empty(), "%s has an about" % type)
		assert_true(info["group"] in Blocks.GROUPS, "%s is in a known group" % type)
		assert_true(info["material"] in Blocks.MATERIALS, "%s is a known material" % type)
		assert_true(ShipMesh.COLORS.has(type), "%s has a colour" % type)
	for type: String in Blocks.INFO:
		assert_true(Tuning.BLOCKS.has(type), "%s is a real block" % type)


func test_there_are_24_ways_to_face() -> void:
	assert_true(Blocks.basis(0) == Basis.IDENTITY)
	var seen: Array[Basis] = []
	for r in 24:
		var b := Blocks.basis(r)
		for other in seen:
			assert_false(b.is_equal_approx(other), "rotation %d repeats another" % r)
		seen.append(b)
		assert_eq(Blocks.rotation_of(b), r)
	assert_eq(Blocks.rotation_of(Basis.from_scale(Vector3(2, 1, 1))), -1)


func test_turning_points_the_bow_side_to_starboard() -> void:
	assert_true(Blocks.facing(Blocks.turned(0)).is_equal_approx(Vector3.RIGHT))
	for r in 24:
		var t := r
		for i in 4:
			t = Blocks.turned(t)
		assert_eq(t, r)


func test_tipping_points_the_bow_side_down() -> void:
	assert_true(Blocks.facing(Blocks.tipped(0)).is_equal_approx(Vector3.DOWN))
	for r in 24:
		var t := r
		for i in 4:
			t = Blocks.tipped(t)
		assert_eq(t, r)


func test_mirroring_swaps_port_and_starboard() -> void:
	assert_true(Blocks.facing(Blocks.mirrored(Blocks.turned(0))).is_equal_approx(Vector3.LEFT))
	assert_eq(Blocks.mirrored(0), 0)
	for r in 24:
		assert_eq(Blocks.mirrored(Blocks.mirrored(r)), r)


func test_only_shaped_blocks_are_not_cubes() -> void:
	assert_true(Blocks.is_cube("frame"))
	assert_true(Blocks.is_cube("balloon"))
	assert_false(Blocks.is_cube("propeller"))
	assert_false(Blocks.is_cube("ladder"))
