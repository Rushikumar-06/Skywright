extends NetCase
## Session roles, the join handshake, and the address helpers (spec §4.3, §7).


func test_solo_is_a_server_with_just_you() -> void:
	var solo := make_session("Solo")
	var started := [false]
	solo.started.connect(func() -> void: started[0] = true)
	solo.start_solo("  Ann  ")
	assert_eq(solo.mode, SessionScript.Mode.SOLO)
	assert_true(solo.is_server())
	assert_true(started[0], "started fires")
	assert_eq(solo.players, {1: {"name": "Ann"}})


func test_solo_and_host_pick_a_seed_in_range() -> void:
	var solo := make_session("Solo")
	solo.requested_seed = -1
	solo.start_solo("Ann")
	assert_true(solo.world_seed >= 0 and solo.world_seed <= 0x7fffffff, "solo picks one")
	var host := make_session("Host")
	host.requested_seed = -1
	host.host("Host", free_port())
	assert_true(host.world_seed >= 0 and host.world_seed <= 0x7fffffff, "a host picks one")


func test_a_requested_seed_is_used() -> void:
	var solo := make_session("Solo")
	solo.requested_seed = 123
	solo.start_solo("Ann")
	assert_eq(solo.world_seed, 123)
	var host := make_session("Host")
	host.requested_seed = 0
	host.host("Host", free_port())
	assert_eq(host.world_seed, 0)


func test_solo_sails_straight_away() -> void:
	var solo := make_session("Solo")
	var sailed := [false]
	solo.sailed.connect(func() -> void: sailed[0] = true)
	solo.start_solo("Ann")
	assert_true(solo.sailing)
	assert_true(sailed[0], "sailed fires")


func test_setting_sail_takes_the_crew_to_the_world() -> void:
	var host := make_session("Host")
	var client := make_session("Client")
	assert_true(await host_and_join(host, client), "joined")
	assert_false(host.sailing, "the host waits in the lobby")
	assert_false(client.sailing, "and so does the guest")
	var sailed := [0]
	host.sailed.connect(func() -> void: sailed[0] += 1)
	client.sailed.connect(func() -> void: sailed[0] += 1)
	host.set_sail()
	assert_true(await wait_until(func() -> bool: return sailed[0] == 2, 5.0), "both sail")
	assert_true(host.sailing)
	assert_true(client.sailing)


func test_late_joiners_go_straight_to_the_world() -> void:
	var host := make_session("Host")
	var late := make_session("Late")
	var port := free_port()
	host.host("Ann", port)
	host.set_sail()
	var events: Array[String] = []
	late.started.connect(func() -> void: events.append("started"))
	late.sailed.connect(func() -> void: events.append("sailed"))
	late.join("Bob", "127.0.0.1", port)
	assert_true(await wait_until(func() -> bool: return events.size() == 2, 5.0), "joined and sailed")
	assert_eq(events, ["started", "sailed"] as Array[String])
	assert_true(late.sailing)


func test_a_guest_cannot_set_sail() -> void:
	var host := make_session("Host")
	var client := make_session("Client")
	assert_true(await host_and_join(host, client), "joined")
	client.set_sail()
	allowed_engine_errors = 1  # the host's engine refuses the RPC and logs it
	client._sail.rpc_id(1)  # as a modified client could
	await wait_until(func() -> bool: return false, 0.3)
	assert_false(client.sailing)
	assert_false(host.sailing)


func test_a_dedicated_server_has_no_player_of_its_own() -> void:
	var server := make_session("Server")
	server.max_players = 2
	var sailed := [false]
	server.sailed.connect(func() -> void: sailed[0] = true)
	var port := free_port()
	assert_eq(server.host("Skyport", port, true), OK)
	assert_true(server.dedicated)
	assert_true(server.is_server())
	assert_eq(server.players, {}, "nobody plays on the server itself")
	assert_true(server.sailing and sailed[0], "the world starts at once")
	var ann := make_session("Ann")
	ann.join("Ann", "127.0.0.1", port)
	assert_true(await wait_until(func() -> bool: return ann.sailing, 5.0), "Ann goes straight aboard")
	assert_eq(ann.players.values(), [{"name": "Ann"}], "and is the only player")
	var bob := make_session("Bob")
	bob.join("Bob", "127.0.0.1", port)
	assert_true(await wait_until(func() -> bool: return server.players.size() == 2, 5.0), "Bob too")
	var cy := make_session("Cy")
	var refused := [""]
	cy.ended.connect(func(why: String) -> void: refused[0] = why)
	cy.join("Cy", "127.0.0.1", port)
	assert_true(await wait_until(func() -> bool: return refused[0] != "", 5.0), "Cy is refused")
	assert_eq(refused[0], "The game is full (2 players).")
	var ended := [""]
	ann.ended.connect(func(why: String) -> void: ended[0] = why)
	server.leave()
	assert_true(await wait_until(func() -> bool: return ended[0] != "", 5.0), "stopping the server tells its players")
	assert_eq(ended[0], "The host ended the game.")


func test_client_joins_and_both_sides_share_the_roster() -> void:
	var host := make_session("Host")
	var client := make_session("Client")
	var started := [false]
	client.started.connect(func() -> void: started[0] = true)
	assert_true(await host_and_join(host, client), "roster reaches both sides")
	assert_true(started[0], "client's started fires once accepted")
	assert_eq(client.mode, SessionScript.Mode.CLIENT)
	assert_false(client.is_server())
	assert_true(host.is_server())
	var guest_id := client.multiplayer.get_unique_id()
	assert_eq(host.players.get(guest_id), {"name": "Guest"})
	assert_eq(client.players.get(1), {"name": "Host"})


func test_host_cleans_joiner_names() -> void:
	var host := make_session("Host")
	var client := make_session("Client")
	var port := free_port()
	host.host("Host", port)
	client.join("Guest", "127.0.0.1", port)
	client._pending_name = "  Ann\nBob" + "x".repeat(5000)  # raw, as a modified client could send it
	assert_true(await wait_until(func() -> bool: return host.players.size() == 2, 5.0), "joined")
	assert_eq(host.players.get(client.multiplayer.get_unique_id()), {"name": "Ann Bob" + "x".repeat(17)})


func test_the_protocol_is_version_5() -> void:
	assert_eq(SessionScript.PROTOCOL_VERSION, 5, "stage 6: damage")


func test_version_check_survives_new_rpcs() -> void:
	# A later version adds RPCs to Session; an old client must still get the
	# version message, not silence.
	var newer := GDScript.new()
	newer.source_code = "extends \"res://src/net/session.gd\"\n\n\n@rpc(\"any_peer\")\nfunc _aaa_added_later() -> void:\n\tpass\n"
	newer.reload()
	var host := make_session("Host", newer)
	host.protocol_version = SessionScript.PROTOCOL_VERSION + 1
	var client := make_session("Client")
	var port := free_port()
	host.host("Host", port)
	var reason := [""]
	client.ended.connect(func(why: String) -> void: reason[0] = why)
	client.join("Guest", "127.0.0.1", port)
	assert_true(await wait_until(func() -> bool: return reason[0] != "", 5.0), "client is told why")
	assert_eq(reason[0], "This game is version %d; you have version %d." % [SessionScript.PROTOCOL_VERSION + 1, SessionScript.PROTOCOL_VERSION])


func test_a_peer_that_never_introduces_itself_is_dropped() -> void:
	var host := make_session("Host")
	var port := free_port()
	host.host("Host", port)
	(host.multiplayer as SceneMultiplayer).auth_timeout = 0.5
	var silent := make_branch("Silent")  # connects over ENet but never says who it is
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", port)
	silent.multiplayer.multiplayer_peer = peer
	var dropped := [false]
	silent.multiplayer.server_disconnected.connect(func() -> void: dropped[0] = true)
	assert_true(await wait_until(func() -> bool: return dropped[0], 3.0), "the host drops it")
	assert_eq(host.players.size(), 1)


func test_host_refuses_a_different_version() -> void:
	var host := make_session("Host")
	var client := make_session("Client")
	var port := free_port()
	host.host("Host", port)
	client.protocol_version = SessionScript.PROTOCOL_VERSION + 1
	var reason := [""]
	client.ended.connect(func(why: String) -> void: reason[0] = why)
	client.join("Guest", "127.0.0.1", port)
	assert_true(await wait_until(func() -> bool: return reason[0] != "", 5.0), "client is told why")
	assert_eq(reason[0], "This game is version %d; you have version %d." % [SessionScript.PROTOCOL_VERSION, SessionScript.PROTOCOL_VERSION + 1])
	assert_eq(client.mode, SessionScript.Mode.NONE)
	assert_eq(host.players.size(), 1)


func test_host_refuses_when_full() -> void:
	var host := make_session("Host")
	var guest := make_session("Guest")
	var late := make_session("Late")
	host.max_players = 2
	assert_true(await host_and_join(host, guest), "the first guest fills it")
	var reason := [""]
	late.ended.connect(func(why: String) -> void: reason[0] = why)
	late.join("Late", "127.0.0.1", host.port)
	assert_true(await wait_until(func() -> bool: return reason[0] != "", 5.0), "the late joiner is told why")
	assert_eq(reason[0], "The game is full (2 players).")
	assert_eq(host.players.size(), 2)


func test_host_drops_a_player_who_leaves() -> void:
	var host := make_session("Host")
	var client := make_session("Client")
	assert_true(await host_and_join(host, client), "joined")
	var reason := ["unset"]
	client.ended.connect(func(why: String) -> void: reason[0] = why)
	client.leave()
	assert_eq(reason[0], "", "leaving on purpose has no reason")
	assert_eq(client.mode, SessionScript.Mode.NONE)
	assert_eq(client.players, {})
	assert_true(await wait_until(func() -> bool: return host.players.size() == 1, 5.0), "host drops the guest")


func test_guests_leaving_together_are_both_dropped_cleanly() -> void:
	# Both goodbyes arrive in one poll. Telling the others about the first must not
	# send to the second, whose connection is already gone.
	var host := make_session("Host")
	var ann := make_session("Ann")
	var bob := make_session("Bob")
	var port := free_port()
	host.host("Host", port)
	ann.join("Ann", "127.0.0.1", port)
	bob.join("Bob", "127.0.0.1", port)
	assert_true(await wait_until(func() -> bool: return host.players.size() == 3, 5.0), "all aboard")
	await wait_until(func() -> bool: return false, 0.2)
	ann.leave()
	bob.leave()
	assert_true(await wait_until(func() -> bool: return host.players.size() == 1, 5.0), "both are dropped")
	await wait_until(func() -> bool: return false, 0.2)


func test_client_is_told_when_the_host_quits() -> void:
	var host := make_session("Host")
	var client := make_session("Client")
	assert_true(await host_and_join(host, client), "joined")
	var reason := [""]
	client.ended.connect(func(why: String) -> void: reason[0] = why)
	host.leave()
	assert_true(await wait_until(func() -> bool: return reason[0] != "", 5.0), "client notices")
	assert_eq(reason[0], "The host ended the game.")


func test_client_is_told_when_the_connection_drops() -> void:
	var host := make_session("Host")
	var client := make_session("Client")
	assert_true(await host_and_join(host, client), "joined")
	var reason := [""]
	client.ended.connect(func(why: String) -> void: reason[0] = why)
	host.multiplayer.multiplayer_peer.close()  # the host vanishes without a goodbye
	assert_true(await wait_until(func() -> bool: return reason[0] != "", 5.0), "client notices")
	assert_eq(reason[0], "Lost the connection to the host.")


func test_a_client_notices_a_host_that_goes_silent() -> void:
	# A host that crashes or is killed says no goodbye. Freeze the host by polling
	# only the client, and the client should give up after drop_after seconds.
	var host := make_session("Host")
	var client := make_session("Client")
	client.drop_after = 1.0
	assert_true(await host_and_join(host, client), "joined")
	var reason := [""]
	client.ended.connect(func(why: String) -> void: reason[0] = why)
	get_tree().multiplayer_poll = false
	var gave_up := await wait_until(func() -> bool:
		client.multiplayer.poll()
		return reason[0] != "", 4.0)
	get_tree().multiplayer_poll = true
	assert_true(gave_up, "the client gives up on a silent host")
	assert_eq(reason[0], "Lost the connection to the host.")


func test_rehosting_straight_after_leaving_works() -> void:
	var host := make_session("Host")
	var client := make_session("Client")
	assert_true(await host_and_join(host, client), "joined")
	var port := host.port
	host.leave()  # says goodbye, and would keep the old socket open a moment for it
	assert_eq(host.host("Host", port), OK, "the port is free again at once")


func test_joining_an_unknown_host_name_fails_straight_away() -> void:
	var client := make_session("Client")
	assert_eq(client.join("Guest", "no-such-host.invalid", free_port()), ERR_CANT_RESOLVE)
	assert_eq(client.mode, SessionScript.Mode.NONE)


func test_join_gives_up_when_nobody_answers() -> void:
	var client := make_session("Client")
	client.connect_timeout = 0.5
	var reason := [""]
	client.ended.connect(func(why: String) -> void: reason[0] = why)
	assert_eq(client.join("Guest", "127.0.0.1", free_port()), OK)
	assert_true(await wait_until(func() -> bool: return reason[0] != "", 3.0), "gives up")
	assert_eq(reason[0], "The host didn't answer.")
	assert_eq(client.mode, SessionScript.Mode.NONE)


func test_leaving_while_connecting_cancels_cleanly() -> void:
	var client := make_session("Client")
	client.connect_timeout = 0.3
	var reasons: Array[String] = []
	client.ended.connect(func(why: String) -> void: reasons.append(why))
	client.join("Guest", "127.0.0.1", free_port())
	client.leave()
	await wait_until(func() -> bool: return false, 0.6)  # outlast the timeout
	assert_eq(reasons, [""] as Array[String])


func test_hosting_on_a_busy_port_fails_cleanly() -> void:
	allowed_engine_errors = 2  # ENet reports the failed bind.
	var first := make_session("First")
	var second := make_session("Second")
	var port := free_port()
	assert_eq(first.host("Ann", port), OK)
	assert_eq(second.host("Bob", port), ERR_CANT_CREATE)
	assert_eq(second.mode, SessionScript.Mode.NONE)


func test_parse_address_reads_hosts_and_ports() -> void:
	assert_eq(SessionScript.parse_address("192.168.0.5"), {"host": "192.168.0.5", "port": 24650})
	assert_eq(SessionScript.parse_address("  example.com:3000 "), {"host": "example.com", "port": 3000})
	assert_eq(SessionScript.parse_address("[::1]:5000"), {"host": "::1", "port": 5000})
	assert_eq(SessionScript.parse_address("::1"), {"host": "::1", "port": 24650})


func test_parse_address_refuses_junk() -> void:
	for junk in ["", "   ", "10.0.0.1:", "10.0.0.1:99999", "10.0.0.1:0", "10.0.0.1:abc", "http://10.0.0.1", "my host", "[::1"]:
		assert_eq(SessionScript.parse_address(junk), {}, "'%s' is refused" % junk)


func test_lan_addresses_by_interface_put_real_networks_first() -> void:
	# The shape IP.get_local_interfaces() returns. Docker and libvirt bridges are
	# only reachable from this machine, so they go last.
	var interfaces: Array = [
		{"name": "lo", "addresses": ["127.0.0.1", "::1"]},
		{"name": "docker0", "addresses": ["172.17.0.1"]},
		{"name": "wlp2s0", "addresses": ["192.168.29.20", "fe80::1"]},
		{"name": "virbr0", "addresses": ["192.168.122.1"]},
	]
	assert_eq(SessionScript.lan_addresses_by_interface(interfaces), PackedStringArray(["192.168.29.20", "172.17.0.1", "192.168.122.1"]))
	assert_eq(SessionScript.lan_addresses_by_interface([]), PackedStringArray())


func test_lan_addresses() -> void:
	var all := PackedStringArray(["127.0.0.1", "192.168.0.102", "::1", "fe80::1", "10.1.2.3", "172.20.0.5", "172.40.0.1", "8.8.8.8"])
	assert_eq(SessionScript.lan_addresses(all), PackedStringArray(["192.168.0.102", "10.1.2.3", "172.20.0.5"]))
	assert_eq(SessionScript.lan_addresses(PackedStringArray()), PackedStringArray())
