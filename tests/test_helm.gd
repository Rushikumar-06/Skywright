extends TestCase
## The helm: one pilot at a time (players by peer id), throttle and trim that stay
## set, a rudder that centres, and an autopilot that holds course (spec §3.4).

var ship: Ship
var crew: CrewMember


func _ready() -> void:
	ship = Ship.new(StarterShip.build())
	ship.calm = true
	ship.position = Vector3(0, 877, 7000)
	add_child(ship)
	crew = CrewMember.new(ship, ship.crew_spawn())
	ship.interior.add_child(crew)


func test_crew_come_aboard_just_aft_of_the_helm() -> void:
	assert_eq(ship.helm.cell, ship.grid.cells_of("helm")[0])
	assert_eq(ship.crew_spawn(), Vector3(0, 3.45, 5))
	await simulate(0.5)
	assert_true(crew.is_on_floor(), "standing on the helm deck")
	assert_eq(crew.station, null)


func test_crew_board_at_free_spots_around_the_helm() -> void:
	var spots: Array[Vector3] = []
	for slot in 5:
		spots.append(ship.crew_spawn(slot))
	assert_eq(spots[0], ship.crew_spawn(), "slot 0 is just aft of the helm")
	for slot in 5:
		for other in slot:
			assert_true(spots[slot] != spots[other], "slots %d and %d differ" % [other, slot])
		if slot > 0:  # the fixture's crew member already stands at slot 0
			ship.interior.add_child(CrewMember.new(ship, spots[slot]))
		assert_true(spots[slot].distance_to(Vector3(ship.helm.cell)) < 1.8, "slot %d is in reach of the helm" % slot)
	await simulate(0.5)
	for member in ship.interior.get_children():
		if member is CrewMember:
			assert_true(member.is_on_floor(), "standing at %s" % member.home)
			assert_true(member.position.distance_to(member.home) < 0.1, "and staying put")
	assert_eq(ship.crew_spawn(5), spots[0], "more crew than spots share them")


func test_one_pilot_at_a_time() -> void:
	var changes := [0]
	ship.helm.pilot_changed.connect(func() -> void: changes[0] += 1)
	assert_eq(ship.helm.pilot, 0, "nobody at first")
	assert_true(ship.helm.take(1))
	assert_eq(ship.helm.pilot, 1)
	assert_false(ship.helm.take(2), "taken")
	ship.helm.leave(2)
	assert_eq(ship.helm.pilot, 1, "only the pilot can let go")
	ship.helm.leave(1)
	assert_eq(ship.helm.pilot, 0)
	assert_eq(changes[0], 2, "pilot_changed for each change")


func test_the_server_decides_at_once_and_a_client_asks_it() -> void:
	var asked: Array = []
	ship.helm.asked.connect(func(what: String, on: bool) -> void: asked.append([what, on]))
	ship.helm.ask_helm(1, true)
	assert_eq(ship.helm.pilot, 1, "a ship flown here answers at once")
	ship.helm.ask_autopilot(2, true)
	assert_false(ship.helm.autopilot, "only the pilot sets the autopilot")
	ship.helm.ask_autopilot(1, true)
	assert_true(ship.helm.autopilot)
	ship.helm.ask_helm(1, false)
	assert_eq(ship.helm.pilot, 0)
	assert_eq(asked, [], "nothing to send")

	var copy := Ship.new(StarterShip.build())
	copy.simulated = false
	add_child(copy)
	var sent: Array = []
	copy.helm.asked.connect(func(what: String, on: bool) -> void: sent.append([what, on]))
	copy.helm.ask_helm(2, true)
	copy.helm.ask_autopilot(2, true)
	assert_eq(sent, [["helm", true], ["autopilot", true]], "a client's copy asks the server")
	assert_eq(copy.helm.pilot, 0, "and waits for its answer")
	assert_false(copy.helm.autopilot)


func test_reach() -> void:
	var at := Vector3(ship.helm.cell)
	assert_true(ship.helm.in_reach(at + Vector3(0, 0, Helm.REACH - 0.01)))
	assert_false(ship.helm.in_reach(at + Vector3(0, 0, Helm.REACH + 0.1)))
	assert_true(ship.helm.in_reach(at + Vector3(0, 0, Helm.REACH + 0.1), 0.5), "with some slack")


func test_throttle_and_trim_stay_set_and_the_rudder_centres() -> void:
	ship.helm.take(1)
	ship.helm.throttle_input = 1.0
	ship.helm.rudder_input = -1.0
	ship.helm.climb_input = 1.0
	await simulate(1.0)
	assert_near(ship.throttle, Tuning.THROTTLE_RATE, 0.02, "half throttle after a second")
	assert_eq(ship.rudder, -1.0)
	assert_near(ship.trim, 1.0 + Tuning.TRIM_RATE, 0.002)
	await simulate(3.0)
	assert_eq(ship.throttle, 1.0, "full ahead at most")
	assert_eq(ship.trim, Tuning.TRIM_MAX)
	ship.helm.leave(1)
	await simulate(0.1)
	assert_eq(ship.throttle, 1.0, "throttle stays")
	assert_eq(ship.trim, Tuning.TRIM_MAX, "trim stays")
	assert_eq(ship.rudder, 0.0, "rudder centres")


func test_an_empty_helm_leaves_the_controls_alone() -> void:
	ship.rudder = 0.5
	ship.trim = 0.9
	await simulate(0.5)
	assert_eq(ship.rudder, 0.5)
	assert_eq(ship.trim, 0.9)


func test_the_autopilot_holds_course_through_gusts_and_follows_a_new_one() -> void:
	ship.calm = false
	ship.throttle = 1.0
	ship.helm.set_autopilot(true)
	await simulate(60.0)
	assert_near(rad_to_deg(wrapf(ship.heading() - ship.helm.target_heading, -PI, PI)), 0.0, 3.0, "holds heading")
	assert_near(ship.global_position.y, ship.helm.target_altitude, 10.0, "holds altitude")
	ship.helm.target_heading = wrapf(ship.helm.target_heading - PI / 2.0, -PI, PI)
	ship.helm.target_altitude += 50.0
	await simulate(60.0)
	assert_near(rad_to_deg(wrapf(ship.heading() - ship.helm.target_heading, -PI, PI)), 0.0, 3.0, "turned 90°")
	assert_near(ship.global_position.y, ship.helm.target_altitude, 10.0, "climbed 50 m")


func test_the_autopilot_keeps_flying_when_the_pilot_leaves() -> void:
	ship.helm.take(1)
	ship.helm.set_autopilot(true)
	ship.helm.leave(1)
	ship.helm.target_heading = wrapf(ship.helm.target_heading + 0.5, -PI, PI)
	ship.throttle = 1.0
	await simulate(20.0)
	assert_true(absf(ship.rudder) > 0.0 or absf(wrapf(ship.heading() - ship.helm.target_heading, -PI, PI)) < 0.05, "still steering")
