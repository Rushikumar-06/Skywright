extends NetCase
## The world's seed travels with the handshake, so a guest makes the host's world.


func test_the_seed_travels_with_the_handshake() -> void:
	host = make_session("Host")
	client = make_session("Client")
	assert_true(await host_and_join(host, client), "joined")
	assert_eq(host.world_seed, NetCase.SEED)
	assert_eq(client.world_seed, NetCase.SEED)


func test_host_and_guest_generate_the_same_chunks() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var host_gen: WorldGen = host_world.gen
	var client_gen: WorldGen = client_world.gen
	for chunk in WorldGen.chunks_near(WorldGen.START, 800.0):
		assert_eq(host_gen.islands_in(chunk), client_gen.islands_in(chunk))
	assert_eq(var_to_str(host_gen.towns), var_to_str(client_gen.towns))
	# The chunk under the guest's ship, once each world has loaded it, collides alike.
	var under_ship := WorldGen.chunk_of(client_world.ship.global_position)
	var loaded := func() -> bool:
		return host_world.streamer.chunks.has(under_ship) and client_world.streamer.chunks.has(under_ship)
	assert_true(await wait_until(loaded, 20.0), "both worlds load it")
	assert_eq(_faces(host_world, under_ship), _faces(client_world, under_ship))


func test_a_junk_seed_is_refused() -> void:
	var lying := GDScript.new()
	lying.source_code = "extends \"res://src/net/session.gd\"\n\n\nfunc _seed_for_welcome() -> Variant:\n\treturn -5\n"
	lying.reload()
	var host := make_session("Host", lying)
	var client := make_session("Client")
	var port := free_port()
	host.host("Host", port)
	var reason := [""]
	client.ended.connect(func(why: String) -> void: reason[0] = why)
	client.join("Guest", "127.0.0.1", port)
	assert_true(await wait_until(func() -> bool: return reason[0] != "", 5.0), "the client ends")
	assert_eq(reason[0], "The host sent a world this game can't make.")


## The collision faces of a world's chunk, or none when it has no islands.
func _faces(world: Node3D, chunk: Vector2i) -> PackedVector3Array:
	var bodies: Array[Node] = (world.streamer.chunks[chunk] as Node3D).find_children("*", "StaticBody3D", false, false)
	if bodies.is_empty():
		return PackedVector3Array()
	return ((bodies[0].get_child(0) as CollisionShape3D).shape as ConcavePolygonShape3D).get_faces()
