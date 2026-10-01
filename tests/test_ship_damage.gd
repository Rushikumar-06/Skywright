extends TestCase
## Ships taking damage (spec §3.3, §4.4): blocks go, the ship rebuilds from what's
## left, once a frame, and flies on it.

const START := Vector3(0, 877, 7000)


## A ship from grid, in still air at START plus offset.
func launch(grid: ShipGrid, offset := Vector3.ZERO) -> Ship:
	var ship := Ship.new(grid)
	ship.calm = true
	ship.position = START + offset
	add_child(ship)
	return ship


## What a ray straight down from point, in ship space, hits first, in ship space.
func hit_below(ship: Ship, point: Vector3) -> Dictionary:
	var from := ship.global_transform * point
	var ray := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 5.0)
	var hit := ship.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		hit["position"] = ship.global_transform.affine_inverse() * (hit["position"] as Vector3)
	return hit


func mesh_of(ship: Ship) -> MeshInstance3D:
	return ship.find_children("*", "MeshInstance3D", false, false)[0]


func test_a_destroyed_block_is_gone_from_the_ship() -> void:
	var ship := launch(StarterShip.build())
	ship.anchored = true
	var mass := ship.mass
	assert_true(ship.damage({Vector3i(0, 0, 1): 0}), "a block went")
	await get_tree().process_frame
	await get_tree().physics_frame
	assert_eq(ship.grid.type_at(Vector3i(0, 0, 1)), "", "the cell is gone")
	assert_near(ship.mass, mass - 40.0, 0.001, "and its 40 kg")
	var boxes := ship.grid.merged_boxes().size()
	assert_eq(ship.find_children("*", "CollisionShape3D", false, false).size(), boxes, "the body's shapes")
	assert_eq(ship.interior.find_children("*", "CollisionShape3D", true, false).size(), boxes, "the interior's")
	var hole := hit_below(ship, Vector3(0, 1.4, 1))
	var deck := hit_below(ship, Vector3(1, 1.4, 1))
	assert_eq(hole.get("collider"), ship, "the ray through the hole hits the ship")
	assert_eq(deck.get("collider"), ship, "and through its neighbour")
	if not hole.is_empty() and not deck.is_empty():
		assert_near((deck["position"] as Vector3).y - (hole["position"] as Vector3).y, 1.0, 0.01, "the keel, 1 m below the deck")


func test_a_hole_in_the_deck_drops_you_through() -> void:
	var ship := launch(StarterShip.build())
	ship.anchored = true
	var crew := CrewMember.new(ship, Vector3(0, 1.4, 1))
	ship.interior.add_child(crew)
	await simulate(0.3)
	assert_true(crew.is_on_floor(), "standing on the deck")
	var changes := {}
	for x in range(-1, 2):
		for z in range(0, 3):
			changes[Vector3i(x, 0, z)] = 0
			changes[Vector3i(x, -1, z)] = 0
	ship.damage(changes)
	var fell := [false]
	await simulate(1.0, func(_tick: int) -> void: fell[0] = fell[0] or crew.position.y < 0.0)
	assert_true(fell[0], "fell through (at y %.2f)" % crew.position.y)


func test_damage_changes_how_she_flies() -> void:
	var holed := launch(StarterShip.build())
	var holed_twin := launch(StarterShip.build(), Vector3(200, 0, 0))
	var lopsided := launch(StarterShip.build(), Vector3(400, 0, 0))
	var lopsided_twin := launch(StarterShip.build(), Vector3(600, 0, 0))
	var dead := launch(StarterShip.build(), Vector3(800, 0, 0))
	var dead_twin := launch(StarterShip.build(), Vector3(1000, 0, 0))
	var balloons := {}
	for z in range(-4, 6):
		for x in [-1, 1]:
			balloons[Vector3i(x, 10, z)] = 0
	assert_eq(balloons.size(), 20)
	holed.damage(balloons)
	lopsided.damage({Vector3i(-2, 1, 7): 0})
	dead.damage({Vector3i(0, -1, -5): 0})
	await get_tree().process_frame
	assert_eq(dead.max_thrust(), 0.0, "no engine, no thrust")
	for ship: Ship in [lopsided, lopsided_twin, dead, dead_twin]:
		ship.throttle = 1.0
	var headings := [lopsided.heading(), lopsided_twin.heading()]
	await simulate(20.0)
	var turned := absf(rad_to_deg(wrapf(lopsided.heading() - headings[0], -PI, PI)))
	var twin_turned := absf(rad_to_deg(wrapf(lopsided_twin.heading() - headings[1], -PI, PI)))
	assert_true(turned > 10.0, "one propeller turns her (%.1f°)" % turned)
	assert_true(twin_turned < 1.0, "two keep her straight (%.1f°)" % twin_turned)
	# 300 kg lighter without her engine, she rises: it's her way through the air that's gone.
	var way := Vector2(dead.linear_velocity.x, dead.linear_velocity.z).length()
	var twin_way := Vector2(dead_twin.linear_velocity.x, dead_twin.linear_velocity.z).length()
	assert_true(way < 1.0, "no engine, no way on (%.2f m/s)" % way)
	assert_true(twin_way > 5.0, "unlike her twin (%.2f m/s)" % twin_way)
	await simulate(10.0)
	var lower := holed_twin.global_position.y - holed.global_position.y
	assert_true(lower >= 20.0, "20 balloons gone, she sinks (%.1f m below her twin)" % lower)


func test_many_hits_in_one_frame_rebuild_once() -> void:
	var ship := launch(StarterShip.build())
	var rebuilds := [0]
	ship.blocks_changed.connect(func() -> void: rebuilds[0] += 1)
	for x in range(-2, 3):
		assert_true(ship.damage({Vector3i(x, 0, -3): 0}), "hit %d" % x)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(rebuilds[0], 1, "one rebuild for five hits")


func test_hit_points_alone_dont_rebuild() -> void:
	var ship := launch(StarterShip.build())
	var mesh := mesh_of(ship)
	var rebuilds := [0]
	ship.blocks_changed.connect(func() -> void: rebuilds[0] += 1)
	assert_false(ship.damage({Vector3i(0, 0, 1): 10}), "no block went")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(ship.grid.blocks[Vector3i(0, 0, 1)]["hp"], 10, "the hit points changed")
	assert_eq(rebuilds[0], 0, "no rebuild")
	assert_true(is_same(mesh_of(ship), mesh), "the same mesh")


## The median time of ten rebuilds, in ms.
func rebuild_time(ship: Ship) -> float:
	var times: Array[float] = []
	for i in 10:
		var start := Time.get_ticks_usec()
		ship.rebuild()
		times.append((Time.get_ticks_usec() - start) / 1000.0)
	times.sort()
	return times[5]


func test_rebuilding_a_hit_ship_is_quick() -> void:
	var starter := launch(StarterShip.build())
	var wide_grid := StarterShip.build()
	for x in range(3, 13):
		for side in [-1, 1]:
			for z in range(-5, 7):
				if wide_grid.blocks.size() < 500:
					wide_grid.set_block(Vector3i(x * side, 0, z), "deck")
					wide_grid.set_block(Vector3i(x * side, -1, z), "iron")
	assert_eq(wide_grid.blocks.size(), 501)
	var wide := launch(wide_grid, Vector3(200, 0, 0))
	var small := rebuild_time(starter)
	var big := rebuild_time(wide)
	assert_true(small < 15.0, "the starter ship in %.1f ms" % small)
	assert_true(big < 25.0, "500 blocks in %.1f ms" % big)


func test_a_ship_without_her_helm_loses_power() -> void:
	var ship := launch(StarterShip.build())
	ship.helm.set_autopilot(true)
	ship.throttle = 1.0
	await simulate(0.5)
	ship.rudder = 0.6  # as the autopilot would leave it mid-turn
	ship.damage({ship.helm.cell: 0})
	await get_tree().process_frame
	assert_true(ship.is_wreck(), "a wreck")
	assert_eq(ship.throttle, 0.0, "her engines stop")
	assert_eq(ship.rudder, 0.0, "and her rudder centres")
