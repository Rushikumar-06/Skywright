extends NetCase
## The world streams in chunks around each ship: collision always, and three levels
## of detail, trees and waterfalls wherever there's someone to see them.


## The horizontal distance from p to chunk's square.
static func distance_to(chunk: Vector2i, p: Vector3) -> float:
	var origin := WorldGen.chunk_origin(chunk)
	var nearest := Vector2(clampf(p.x, origin.x, origin.x + WorldGen.CHUNK), clampf(p.z, origin.z, origin.z + WorldGen.CHUNK))
	return nearest.distance_to(Vector2(p.x, p.z))


func settle(world: Node3D) -> bool:
	var streamer: WorldStreamer = world.streamer
	return await wait_until(streamer.settled, 20.0)


func test_the_world_streams_in_around_the_ship() -> void:
	var world := solo_world()
	assert_true(await settle(world), "settled")
	var streamer: WorldStreamer = world.streamer
	var at: Vector3 = world.ship.global_position
	for chunk in WorldGen.chunks_near(at, WorldStreamer.LOAD_RADIUS):
		assert_true(streamer.chunks.has(chunk), "chunk %s is loaded" % chunk)
	var with_islands := 0
	for chunk: Vector2i in streamer.chunks:
		assert_true(distance_to(chunk, at) <= WorldStreamer.UNLOAD_RADIUS, "chunk %s is near" % chunk)
		var node: Node3D = streamer.chunks[chunk]
		assert_eq(node.position, WorldGen.chunk_origin(chunk))
		if world.gen.islands_in(chunk).is_empty():
			continue
		with_islands += 1
		assert_eq(node.find_children("*", "StaticBody3D", false, false).size(), 1, "one body")
		var meshes := node.find_children("Lod*", "MeshInstance3D", false, false)
		assert_eq(meshes.size(), 3, "three levels of detail")
		for lod in meshes.size():
			var mesh: MeshInstance3D = meshes[lod]
			assert_eq(mesh.visibility_range_begin, 0.0 if lod == 0 else IslandMesh.LOD_END[lod - 1])
			assert_eq(mesh.visibility_range_end, IslandMesh.LOD_END[lod])
			assert_eq(mesh.visibility_range_begin_margin, 20.0)
			assert_eq(mesh.visibility_range_end_margin, 20.0)
	assert_true(with_islands > 20, "islands about (%d chunks with some)" % with_islands)


func test_chunks_far_away_are_freed_and_come_back_the_same() -> void:
	var world := solo_world()
	assert_true(await settle(world), "settled")
	var streamer: WorldStreamer = world.streamer
	var ship: Ship = world.ship
	var home := WorldGen.chunk_of(_nearest_island(world.gen, world.START)["at"])
	var before := _faces(streamer.chunks[home])
	var old: Array = streamer.chunks.keys()
	var old_node: Node3D = streamer.chunks[home]
	ship.global_position = world.START + Vector3(3000.0, 0.0, 0.0)  # east, away from that island
	ship.reset_physics_interpolation()
	streamer.replan()
	assert_true(await settle(world), "settled after the move")
	assert_false(is_instance_valid(old_node), "the old chunk is freed")
	for chunk: Vector2i in old:
		if distance_to(chunk, ship.global_position) > WorldStreamer.UNLOAD_RADIUS:
			assert_false(streamer.chunks.has(chunk), "chunk %s is gone" % chunk)
	for chunk in WorldGen.chunks_near(ship.global_position, WorldStreamer.LOAD_RADIUS):
		assert_true(streamer.chunks.has(chunk), "chunk %s is loaded" % chunk)
	ship.global_position = world.START
	ship.reset_physics_interpolation()
	streamer.replan()
	assert_true(await settle(world), "settled after coming back")
	assert_eq(_faces(streamer.chunks[home]), before, "the same collision")
	assert_false(before.is_empty(), "there was some")


func test_a_fast_ship_never_outruns_the_collision() -> void:
	var world := solo_world()
	assert_true(await settle(world), "settled")
	var streamer: WorldStreamer = world.streamer
	var ship: Ship = world.ship
	ship.calm = true
	ship.global_position.y = 1600.0  # over the islands in the way
	ship.reset_physics_interpolation()
	var missing: Array[String] = []
	await simulate(60.0, func(tick: int) -> void:
		ship.linear_velocity = Vector3(-60.0, 0.0, 0.0)
		if tick % 30 == 0:
			var home := WorldGen.chunk_of(ship.global_position)
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					if not streamer.chunks.has(home + Vector2i(dx, dz)):
						missing.append("%s at tick %d" % [home + Vector2i(dx, dz), tick]))
	assert_true(ship.global_position.x < -3000.0, "flew 3 km (to x %.0f)" % ship.global_position.x)
	assert_eq(missing, [] as Array[String], "the chunks around the ship were always there")


func test_islands_are_solid() -> void:
	var world := solo_world()
	assert_true(await settle(world), "settled")
	var nearest := _nearest_island(world.gen, world.START)
	var at: Vector3 = nearest["at"]
	var top := at.y + IslandMesh.height(nearest, 0.0, 0.0)
	var query := PhysicsRayQueryParameters3D.create(at + Vector3(0.0, 100.0, 0.0), at - Vector3(0.0, 100.0, 0.0))
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	assert_false(hit.is_empty(), "the ray hits")
	if not hit.is_empty():
		assert_near(hit["position"].y, top, 1.0, "on the top")


func test_freeing_the_world_mid_generation_is_clean() -> void:
	var world := solo_world()
	world.streamer.replan()
	await get_tree().process_frame
	assert_true(world.streamer.pending() > 0, "still generating")
	world.get_parent().remove_child(world)
	world.free()
	await get_tree().process_frame
	await get_tree().process_frame


func test_a_dedicated_server_loads_collision_only() -> void:
	var server := make_session("Server")
	assert_eq(server.host("Server", free_port(), true), OK)
	var world := add_world(server)
	assert_true(await settle(world), "settled")
	var streamer: WorldStreamer = world.streamer
	var bodies := 0
	for node: Node3D in streamer.chunks.values():
		bodies += node.find_children("*", "StaticBody3D", false, false).size()
		assert_eq(node.find_children("*", "MeshInstance3D", true, false).size(), 0, "no meshes")
		assert_eq(node.find_children("*", "MultiMeshInstance3D", true, false).size(), 0, "no trees")
	assert_true(bodies > 20, "collision (%d bodies)" % bodies)


## The generated island nearest p, within 1 km.
func _nearest_island(gen: WorldGen, p: Vector3) -> Dictionary:
	var nearest := {}
	for chunk in WorldGen.chunks_near(p, 1000.0):
		for island in gen.islands_in(chunk):
			if nearest.is_empty() or (island["at"] as Vector3).distance_to(p) < (nearest["at"] as Vector3).distance_to(p):
				nearest = island
	assert_false(nearest.is_empty(), "an island near %s" % p)
	return nearest


func _faces(chunk: Node3D) -> PackedVector3Array:
	var body: StaticBody3D = chunk.find_children("*", "StaticBody3D", false, false)[0]
	return ((body.get_child(0) as CollisionShape3D).shape as ConcavePolygonShape3D).get_faces()
