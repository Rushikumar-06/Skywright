extends TestCase
## Session roles, the join handshake, and the address helpers (spec §4.3, §7).

const SessionScript := preload("res://src/net/session.gd")

var _branches: Array[Node] = []


func after_each() -> void:
	for branch in _branches:
		var session := branch.get_node_or_null("Session") as SessionScript
		if session:
			session.leave()
		else:
			branch.multiplayer.multiplayer_peer.close()
		get_tree().set_multiplayer(null, branch.get_path())


## A branch with its own MultiplayerAPI, so several peers can run in one process.
func make_branch(branch_name: String) -> Node:
	var branch := Node.new()
	branch.name = branch_name
	add_child(branch)
	get_tree().set_multiplayer(SceneMultiplayer.new(), branch.get_path())
	_branches.append(branch)
	return branch


## A Session under its own branch. script lets a test use a changed Session.
func make_session(branch_name: String, script: GDScript = SessionScript) -> SessionScript:
	var branch := make_branch(branch_name)
	var session: SessionScript = script.new()
	session.name = "Session"
	session.log_enabled = false
	branch.add_child(session)
	return session


func free_port() -> int:
	return 30000 + randi() % 20000


## Hosts on a fresh port, joins it, and waits until both sides have the full roster.
func host_and_join(host: SessionScript, client: SessionScript, guest_name := "Guest") -> bool:
	var port := free_port()
	if host.host("Host", port) != OK or client.join(guest_name, "127.0.0.1", port) != OK:
		return false
	return await wait_until(func() -> bool: return client.players.size() == 2 and host.players.size() == 2, 5.0)


func test_solo_is_a_server_with_just_you() -> void:
	var solo := make_session("Solo")
	var started := [false]
	solo.started.connect(func() -> void: started[0] = true)
	solo.start_solo("  Ann  ")
	assert_eq(solo.mode, SessionScript.Mode.SOLO)
	assert_true(solo.is_server())
	assert_true(started[0], "started fires")
	assert_eq(solo.players, {1: {"name": "Ann"}})


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
	assert_true(reason[0].contains("version 2") and reason[0].contains("version 1"), reason[0])


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
	assert_true(reason[0].contains("version 1") and reason[0].contains("version 2"), reason[0])
	assert_eq(client.mode, SessionScript.Mode.NONE)
	assert_eq(host.players.size(), 1)


func test_host_refuses_when_full() -> void:
	var host := make_session("Host")
	var client := make_session("Client")
	host.max_players = 1
	var port := free_port()
	host.host("Host", port)
	var reason := [""]
	client.ended.connect(func(why: String) -> void: reason[0] = why)
	client.join("Guest", "127.0.0.1", port)
	assert_true(await wait_until(func() -> bool: return reason[0] != "", 5.0), "client is told why")
	assert_eq(reason[0], "The game is full.")


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


func test_lan_addresses() -> void:
	var all := PackedStringArray(["127.0.0.1", "192.168.0.102", "::1", "fe80::1", "10.1.2.3", "172.20.0.5", "172.40.0.1", "8.8.8.8"])
	assert_eq(SessionScript.lan_addresses(all), PackedStringArray(["192.168.0.102", "10.1.2.3", "172.20.0.5"]))
	assert_eq(SessionScript.lan_addresses(PackedStringArray()), PackedStringArray())
