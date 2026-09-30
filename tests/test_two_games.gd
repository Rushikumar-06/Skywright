extends NetCase
## Stage 3's finish line (spec §5, §6): two players crew one ship flown by a
## dedicated server running in a process of its own.

var _server: Dictionary = {}  ## What OS.execute_with_pipe gave for the server.
var _said := ""               ## Everything the server has printed.


func after_each() -> void:
	Input.action_release("move_forward")
	super.after_each()
	if _server.has("pid"):
		OS.kill(_server["pid"])


## Starts a headless dedicated server on port and waits until it's under way.
func start_server(port: int) -> bool:
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--", "--server", "--port=%d" % port]
	_server = OS.execute_with_pipe(OS.get_executable_path(), args, false)
	if _server.is_empty():
		return false
	return await wait_until(func() -> bool: return _heard().contains("[session] set sail"), 20.0)


## What the server has printed so far, on stdout and stderr.
func _heard() -> String:
	for pipe in ["stdio", "stderr"]:
		_said += (_server[pipe] as FileAccess).get_buffer(65536).get_string_from_utf8()
	return _said


func test_two_players_share_a_ship_on_a_dedicated_server() -> void:
	var port := free_port()
	assert_true(await start_server(port), "the server starts:\n" + _said)
	var ann := make_session("Ann")
	var bob := make_session("Bob")
	ann.join("Ann", "127.0.0.1", port)
	bob.join("Bob", "127.0.0.1", port)
	assert_true(await play_until(func() -> bool:
		return ann.sailing and bob.sailing and ann.players.size() == 2 and bob.players.size() == 2, 10.0), "both join")
	var ann_world := add_world(ann)
	var bob_world := add_world(bob)
	assert_true(await play_until(func() -> bool: return ann_world.ship != null and bob_world.ship != null, 10.0), "the ship arrives")
	await play(0.5)
	var ann_id := ann.multiplayer.get_unique_id()
	var bob_id := bob.multiplayer.get_unique_id()
	assert_true(ann_world.sync.avatar_of(bob_id) != null and bob_world.sync.avatar_of(ann_id) != null, "they see each other")

	press(ann_world.player, "interact")
	assert_true(await play_until(func() -> bool: return ann_world.player.crew.station != null, 3.0), "Ann takes the helm")
	press(bob_world.player, "interact")
	await play(0.5)
	assert_eq(bob_world.player.crew.station, null, "Bob is refused")
	assert_eq(bob_world.ship.helm.pilot, ann_id, "and knows Ann has it")

	bob_world.player.enabled = false  # W below is Ann's
	var ship: Ship = ann_world.ship
	var from := ship.global_position
	var bow := -ship.global_basis.z
	Input.action_press("move_forward")
	await play(2.0)
	Input.action_release("move_forward")
	await play(4.0)
	assert_true(ship.throttle > 0.9, "Ann opened the throttle (%.2f)" % ship.throttle)
	var ahead := (ship.global_position - from).dot(bow)
	assert_true(ahead > 2.0, "the ship flew forward (%.1f m)" % ahead)
	var apart := ship.global_position.distance_to((bob_world.ship as Ship).global_position)
	assert_true(apart < 0.5, "Ann and Bob see her in the same place (%.2f m apart)" % apart)
	var bob_seen := ship.global_transform.affine_inverse() * (ann_world.sync.avatar_of(bob_id) as CrewAvatar).global_position
	assert_true(bob_seen.distance_to(bob_world.player.crew.position) < 0.5, "Ann sees Bob where he stands")

	press(ann_world.player, "interact")
	assert_true(await play_until(func() -> bool: return bob_world.ship.helm.pilot == 0, 3.0), "Ann lets go")
	bob_world.player.enabled = true
	press(bob_world.player, "interact")
	assert_true(await play_until(func() -> bool: return bob_world.player.crew.station != null, 3.0), "Bob takes the helm")
	assert_true(await play_until(func() -> bool: return ann_world.ship.helm.pilot == bob_id, 3.0), "and Ann hears so")
	ann.leave()
	bob.leave()
	await play(0.3)
	assert_false(_heard().contains("ERROR"), "the server logged no errors:\n" + _said)
