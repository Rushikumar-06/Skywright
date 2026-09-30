extends NetCase
## LAN discovery (spec §4.6): browsers ask on the discovery port once a second, and
## hosts answer with their game's details. Every answer is untrusted.

var _sockets: Array[PacketPeerUDP] = []


func after_each() -> void:
	super.after_each()
	for socket in _sockets:
		socket.close()


## A browser asking on discovery_port, in the tree.
func make_browser(discovery_port: int) -> LanBrowser:
	var browser := LanBrowser.new(discovery_port)
	add_child(browser)
	return browser


## A plain UDP socket that sends to port on this machine.
func make_socket(to_port: int) -> PacketPeerUDP:
	var socket := PacketPeerUDP.new()
	socket.bind(0)
	socket.set_dest_address("127.0.0.1", to_port)
	_sockets.append(socket)
	return socket


func answer_bytes(info: Variant) -> PackedByteArray:
	var packet := "SKYWRIGHT!".to_ascii_buffer()
	packet.append_array(var_to_bytes(info))
	return packet


func game_info(overrides := {}) -> Dictionary:
	var info := {"id": 7, "name": "Ann's game", "players": 1, "max": 8, "version": SessionScript.PROTOCOL_VERSION, "port": 24650}
	info.merge(overrides, true)
	return info


func test_a_browser_finds_a_host() -> void:
	var host := make_session("Host")
	host.discovery_port = free_port()
	var port := free_port()
	assert_eq(host.host("Ann", port), OK)
	var browser := make_browser(host.discovery_port)
	assert_true(await wait_until(func() -> bool: return browser.games.size() == 1, 3.0), "found it")
	var game: Dictionary = browser.games.values()[0]
	assert_eq(game["name"], "Ann's game")
	assert_eq(game["players"], 1)
	assert_eq(game["max"], SessionScript.MAX_PLAYERS)
	assert_eq(game["version"], SessionScript.PROTOCOL_VERSION)
	assert_eq(game["port"], port)
	assert_false((game["address"] as String).is_empty(), "and where it is")


func test_hosting_answers_with_the_crew_count() -> void:
	var host := make_session("Host")
	var guest := make_session("Guest")
	host.discovery_port = free_port()
	var browser := make_browser(host.discovery_port)
	assert_true(await host_and_join(host, guest), "joined")
	assert_true(await wait_until(func() -> bool:
		return browser.games.size() == 1 and browser.games.values()[0]["players"] == 2, 3.0), "2/8 once a guest is aboard")
	guest.leave()
	assert_true(await wait_until(func() -> bool: return browser.games.values()[0]["players"] == 1, 3.0), "1/8 once they leave")


func test_the_browser_ignores_junk() -> void:
	var good := answer_bytes(game_info())
	var oversized := good.duplicate()
	oversized.resize(LanBeacon.QUERY_SIZE + 1)  # a good answer, padded past the query size
	assert_eq(LanBrowser.read_answer(good)["name"], "Ann's game", "a good answer is read")
	var junk: Array[PackedByteArray] = [
		PackedByteArray(),
		"SKYWRIGHT".to_ascii_buffer(),
		"SKYWRONG!!".to_ascii_buffer() + var_to_bytes(game_info()),
		answer_bytes([1, 2, 3]),
		answer_bytes("Ann's game"),
		answer_bytes(game_info({"id": "7"})),
		answer_bytes(game_info({"name": 42})),
		answer_bytes(game_info({"players": 1.5})),
		answer_bytes(game_info({"players": -1})),
		answer_bytes(game_info({"max": 0})),
		answer_bytes(game_info({"version": null})),
		answer_bytes(game_info({"port": 0})),
		answer_bytes(game_info({"port": 70000})),
		answer_bytes(game_info({"port": "24650"})),
		oversized,
	]
	for packet in junk:
		assert_eq(LanBrowser.read_answer(packet), {}, "refused: %s" % packet.slice(0, 40).get_string_from_ascii())
	assert_eq(LanBrowser.read_answer(answer_bytes(game_info({"name": "  Ann '\ns game  "})))["name"], "Ann ' s game", "names are cleaned")

	# The same junk, sent to a live browser, adds nothing to its list.
	var browser := make_browser(free_port())
	await get_tree().process_frame
	var socket := make_socket(browser._udp.get_local_port())
	for packet in junk:
		socket.put_packet(packet)
	socket.put_packet(answer_bytes(game_info({"id": 9})))
	assert_true(await wait_until(func() -> bool: return browser.games.has(9), 2.0), "the good one gets through")
	assert_eq(browser.games.keys(), [9])


func test_answers_are_never_bigger_than_queries() -> void:
	var host := make_session("Host")
	host.discovery_port = free_port()
	assert_eq(host.host("Ann", free_port()), OK)
	await get_tree().process_frame
	var asker := make_socket(host.discovery_port)
	asker.put_packet("SKYWRIGHT?".to_ascii_buffer())
	await wait_until(func() -> bool: return asker.get_available_packet_count() > 0, 0.5)
	assert_eq(asker.get_available_packet_count(), 0, "a short query gets no answer")
	asker.put_packet(LanBeacon.query())
	assert_eq(LanBeacon.query().size(), LanBeacon.QUERY_SIZE)
	assert_true(await wait_until(func() -> bool: return asker.get_available_packet_count() > 0, 2.0), "a full one does")
	var answer := asker.get_packet()
	assert_true(answer.size() <= LanBeacon.QUERY_SIZE, "%d bytes" % answer.size())
	assert_eq(LanBrowser.read_answer(answer)["name"], "Ann's game")


func test_games_that_stop_answering_drop_off_the_list() -> void:
	var host := make_session("Host")
	host.discovery_port = free_port()
	host.host("Ann", free_port())
	var browser := make_browser(host.discovery_port)
	browser.forget_after = 1.5
	assert_true(await wait_until(func() -> bool: return browser.games.size() == 1, 3.0), "found it")
	var changes := [0]
	browser.changed.connect(func() -> void: changes[0] += 1)
	host.leave()
	assert_true(await wait_until(func() -> bool: return browser.games.is_empty(), 4.0), "forgotten")
	assert_true(changes[0] > 0, "and the list was told")


func test_two_hosts_on_one_machine_both_host() -> void:
	# Only one program can listen on the discovery port, so the second host can't
	# be found on the network. It still hosts, and can be joined by address.
	var first := make_session("First")
	var second := make_session("Second")
	var discovery := free_port()
	first.discovery_port = discovery
	second.discovery_port = discovery
	assert_eq(first.host("Ann", free_port()), OK)
	assert_eq(second.host("Bob", free_port()), OK)
	var browser := make_browser(discovery)
	assert_true(await wait_until(func() -> bool: return browser.games.size() == 1, 3.0), "the first is found")


func test_hosting_again_straight_after_leaving_is_found() -> void:
	var host := make_session("Host")
	host.host("Ann", free_port())
	host.leave()
	host.host("Bob", free_port())
	var browser := make_browser(host.discovery_port)
	assert_true(await wait_until(func() -> bool: return browser.games.size() == 1, 3.0), "found")
	assert_eq(browser.games.values()[0]["name"], "Bob's game")
