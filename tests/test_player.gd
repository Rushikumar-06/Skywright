extends TestCase
## The local player's keys: E takes and leaves the helm, V switches to the chase
## view there, H switches the autopilot, and the movement keys steer.

var player: PlayerController


func _ready() -> void:
	var ship := Ship.new(StarterShip.build())
	ship.calm = true
	ship.position = Vector3(0, 877, 7000)
	add_child(ship)
	var crew := CrewMember.new(ship, ship.crew_spawn())
	ship.interior.add_child(crew)
	player = PlayerController.new(crew)
	add_child(player)


func after_each() -> void:
	for action in ["move_forward", "move_right", "jump"]:
		Input.action_release(action)


func press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	player._unhandled_input(event)


func test_e_takes_the_helm_in_reach_and_lets_go_again() -> void:
	assert_eq(player.prompt(), "Take the helm")
	press("interact")
	assert_eq(player.crew.station, player.ship.helm)
	assert_eq(player.prompt(), "Leave the helm")
	press("toggle_camera")
	assert_true(player.chase)
	press("interact")
	assert_eq(player.crew.station, null)
	assert_false(player.chase, "leaving the helm ends the chase view")


func test_e_does_nothing_out_of_reach() -> void:
	player.crew.position = Vector3(0, 1.45, -4)  # down on the main deck
	assert_eq(player.prompt(), "")
	press("interact")
	assert_eq(player.crew.station, null)


func test_the_chase_view_and_autopilot_are_only_at_the_helm() -> void:
	press("toggle_camera")
	press("autopilot")
	assert_false(player.chase)
	assert_false(player.ship.helm.autopilot)
	press("interact")
	press("autopilot")
	assert_true(player.ship.helm.autopilot)
	press("autopilot")
	assert_false(player.ship.helm.autopilot)


func test_movement_keys_steer_from_the_helm() -> void:
	press("interact")
	Input.action_press("move_forward")
	Input.action_press("move_right")
	Input.action_press("jump")
	await simulate(1.0)
	assert_near(player.ship.throttle, Tuning.THROTTLE_RATE, 0.02, "W opens the throttle")
	assert_eq(player.ship.rudder, 1.0, "D is starboard rudder")
	assert_near(player.ship.trim, 1.0 + Tuning.TRIM_RATE, 0.002, "Space climbs")
	assert_eq(player.crew.move, Vector2.ZERO, "and nobody walks off")


func test_controls_stop_while_a_menu_is_open() -> void:
	press("interact")
	Input.action_press("move_forward")
	player.enabled = false
	press("interact")
	press("toggle_camera")
	await simulate(0.5)
	assert_eq(player.crew.station, player.ship.helm, "E does nothing")
	assert_false(player.chase, "nor V")
	assert_eq(player.ship.throttle, 0.0, "and held keys don't steer")
