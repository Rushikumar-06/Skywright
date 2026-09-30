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
	# Task 3 gives each world its own WorldGen; until then, make one from each seed.
	var host_gen := WorldGen.new(host.world_seed)
	var client_gen := WorldGen.new(client.world_seed)
	var under_ship := WorldGen.chunk_of(WorldGen.START)
	for chunk in WorldGen.chunks_near(WorldGen.START, 800.0):
		assert_eq(host_gen.islands_in(chunk), client_gen.islands_in(chunk))
	assert_eq(var_to_str(host_gen.towns), var_to_str(client_gen.towns))
	assert_true(under_ship in WorldGen.chunks_near(WorldGen.START, 800.0))


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
