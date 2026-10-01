extends NetCase
## Clouds in the chunks, fog sheets over the Roil, storm columns and lightning.


## The chunks of region (by their centres) in a square of chunks around the origin.
func chunks_in(region: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for cx in range(-32, 32):
		for cz in range(-32, 32):
			var chunk := Vector2i(cx, cz)
			if WorldGen.region_at(WorldGen.chunk_origin(chunk) + Vector3(128.0, 0.0, 128.0)) == region:
				found.append(chunk)
	return found


func average_clouds(gen: WorldGen, region: int) -> float:
	var chunks := chunks_in(region)
	var total := 0
	for chunk in chunks:
		total += WorldChunk.clouds(gen, chunk).size()
	return float(total) / chunks.size()


func test_clouds_are_the_same_every_time() -> void:
	var gen := WorldGen.new(SEED)
	for chunk in chunks_in(WorldGen.Region.STORMWALL).slice(0, 10) + chunks_in(WorldGen.Region.GALE).slice(0, 10):
		var first := WorldChunk.clouds(gen, chunk)
		assert_eq(first, WorldChunk.clouds(gen, chunk), "chunk %s" % chunk)
		for puff in first:
			assert_true(puff.origin.y > 850.0 and puff.origin.y < 2300.0, "a puff at %.0f m" % puff.origin.y)
	assert_true(average_clouds(gen, WorldGen.Region.STORMWALL) > average_clouds(gen, WorldGen.Region.CALM) + 2.0, "the Stormwall is cloudier than the Calm Reaches")
	assert_true(average_clouds(gen, WorldGen.Region.GALE) > average_clouds(gen, WorldGen.Region.CALM), "and the Gale Expanse")
	assert_eq(average_clouds(gen, WorldGen.Region.EYE), 0.0, "the Eye is clear")


func test_chunks_carry_their_clouds() -> void:
	var gen := WorldGen.new(SEED)
	var chunk := chunks_in(WorldGen.Region.STORMWALL)[0]
	var puffs := WorldChunk.clouds(gen, chunk)
	assert_true(puffs.size() >= 20, "a cloudy chunk (%d puffs)" % puffs.size())
	assert_false(WorldChunk.generate(gen, chunk, false).has("clouds"), "no clouds for a server")
	var node := WorldChunk.build(WorldChunk.generate(gen, chunk, true))
	add_child(node)
	var clouds := node.get_node("Clouds") as MultiMeshInstance3D
	assert_eq(clouds.multimesh.instance_count, puffs.size())
	assert_eq(clouds.visibility_range_end, 3000.0)
	assert_eq(clouds.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_eq(WorldChunk.puff_mesh().get_surface_count(), 1)
	assert_eq((WorldChunk.puff_mesh().surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 240, "one subdivision of an icosahedron")
	var empty := WorldChunk.build(WorldChunk.generate(gen, chunks_in(WorldGen.Region.EYE)[0], true))
	assert_false(empty.has_node("Clouds"), "a clear chunk has no cloud node")
	empty.free()


func test_storm_columns_follow_their_storms() -> void:
	var gen := WorldGen.new(SEED)
	var weather := Weather.new(gen, func() -> float: return 500.0)
	add_child(weather)
	await get_tree().process_frame
	assert_eq(weather.columns.size(), gen.storms.size())
	for i in gen.storms.size():
		var centre := gen.storm_center(i, 500.0)
		assert_near(weather.columns[i].position.x, centre.x, 0.01)
		assert_near(weather.columns[i].position.z, centre.z, 0.01)
		assert_eq(weather.columns[i].multimesh.instance_count, 20)


func test_a_bolt_joins_its_ends() -> void:
	var weather := Weather.new(WorldGen.new(SEED), func() -> float: return 0.0)
	add_child(weather)
	var from := Vector3(100.0, 1800.0, -300.0)
	var to := Vector3(160.0, 200.0, -250.0)
	var bolt := weather.strike(from, to)
	var vertices := bolt.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	assert_true(vertices.size() >= 22 and vertices.size() <= 30, "10 to 14 segments (%d vertices)" % vertices.size())
	assert_true(vertices[0].distance_to(from) < 2.0, "starts at the top")
	assert_true(vertices[vertices.size() - 1].distance_to(to) < 2.0, "ends at the bottom")
	assert_eq(weather.bolts_struck, 1)
	for _frame in 30:  # half a second
		await get_tree().process_frame
	assert_false(is_instance_valid(bolt), "the bolt is gone")


func test_storms_strike() -> void:
	var gen := WorldGen.new(SEED)
	var weather := Weather.new(gen, func() -> float: return 0.0)
	var viewer := Node3D.new()
	add_child(viewer)
	viewer.global_position = gen.storm_center(0, 0.0) + Vector3(0.0, 1000.0, 0.0)
	weather.viewer = viewer
	add_child(weather)
	for _frame in 300:  # five seconds
		await get_tree().process_frame
	assert_true(weather.bolts_struck > 0, "a bolt struck")


func test_weather_copes_without_a_camera() -> void:
	var weather := Weather.new(WorldGen.new(SEED), func() -> float: return 0.0)
	add_child(weather)
	for _frame in 5:
		await get_tree().process_frame
	assert_eq(weather.bolts_struck, 0, "nobody to see them")


func test_the_fog_sheets_follow_the_camera_at_their_heights() -> void:
	var weather := Weather.new(WorldGen.new(SEED), func() -> float: return 0.0)
	var viewer := Node3D.new()
	add_child(viewer)
	viewer.global_position = Vector3(1234.0, 900.0, -4321.0)
	weather.viewer = viewer
	add_child(weather)
	await get_tree().process_frame
	assert_eq(weather.sheets.size(), Weather.SHEETS.size())
	for i in weather.sheets.size():
		assert_eq(weather.sheets[i].global_position, Vector3(1234.0, Weather.SHEETS[i], -4321.0))


func test_a_dedicated_world_has_no_weather() -> void:
	var server := make_session("Server")
	assert_eq(server.host("Server", free_port(), true), OK)
	var world := add_world(server)
	await get_tree().process_frame
	assert_eq(world.find_children("*", "Weather", false, false).size(), 0)
	var solo := solo_world()
	await get_tree().process_frame
	assert_eq(solo.find_children("*", "Weather", false, false).size(), 1, "but a player's world has it")
