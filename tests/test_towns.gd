extends NetCase
## Ten towns with docks and shipyards, and the wrecks and landmarks on their own
## islands (spec §3.1, §3.8).


## Presses B in world, as a key press would.
func press_b(world: Node3D) -> void:
	var event := InputEventAction.new()
	event.action = "shipyard"
	event.pressed = true
	world._unhandled_input(event)


## Puts the ship at town's slipway 0, and you with it.
func move_to_town(world: Node3D, town: int) -> Vector3:
	var dock: Vector3 = world.gen.towns[town]["dock"]
	var ship: Ship = world.ship
	ship.global_transform = Dock.slipway(dock, 0)
	ship.reset_physics_interpolation()
	return dock


## The highest thing a ray finds going down through (x, z), from 10 m above the top to 10 m below.
func top_at(world: Node3D, top: float, x: float, z: float) -> float:
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, top + 10.0, z), Vector3(x, top - 10.0, z))
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	return NAN if hit.is_empty() else hit["position"].y


func test_ten_towns_stand_in_the_world() -> void:
	var world := solo_world()
	await get_tree().process_frame
	var towns: Node = world.get_node("Towns")
	assert_eq(towns.get_child_count(), 10, "ten towns")
	assert_eq(world.towns.size(), 10)
	for i in world.gen.towns.size():
		var town: Node3D = world.towns[i]
		assert_eq(str(town.name), "Town%d" % i)
		assert_eq(town.get_parent(), towns)
		assert_eq(town.position, world.gen.towns[i]["dock"], "at its dock")
		var signs := town.find_children("*", "Label3D", true, false)
		assert_eq(signs.size(), 1, "a sign")
		if not signs.is_empty():
			var sign: Label3D = signs[0]
			assert_eq(sign.text, world.gen.towns[i]["name"])
			assert_eq(sign.font_size, 96)
			assert_eq(sign.visibility_range_end, 600.0)
			assert_eq(sign.billboard, BaseMaterial3D.BILLBOARD_ENABLED)
	assert_eq(world.gen.towns[0]["dock"], world.START, "town 0's dock is the start")
	assert_eq(world.town_at(world.START), 0)
	assert_eq(world.town_at(Vector3.ZERO), -1)
	assert_eq(world.town_at(world.gen.towns[4]["dock"] + Vector3(200, 0, 10)), 4)


func test_a_town_has_houses_a_beacon_and_piers() -> void:
	var gen := WorldGen.new(NetCase.SEED)
	var town := Town.create(gen.towns[1], true)
	add_child(town)
	var dock: Vector3 = gen.towns[1]["dock"]
	var houses := town.get_node("Buildings")
	var shapes: Array[Node] = houses.find_children("*", "CollisionShape3D", false, false)
	assert_true(shapes.size() >= 7, "at least 6 houses and the beacon (%d)" % shapes.size())
	var obstacles := Dock.obstacles(dock)
	for i in Dock.SLIPWAYS:
		var pier := AABB(dock + Vector3(i * Dock.SPACING, 0, 0) + Dock.PIER.position, Dock.PIER.size)
		assert_true(obstacles.has(pier), "a pier beside slipway %d" % i)
	var keep_out: Array[AABB] = [Dock.area(dock)]
	keep_out.append_array(obstacles.slice(0, -1))  # the quay and the piers; the last is the island
	for shape: CollisionShape3D in shapes:
		var box := shape.global_transform * AABB(-(shape.shape as BoxShape3D).size / 2.0, (shape.shape as BoxShape3D).size)
		for area in keep_out:
			assert_false(box.intersects(area), "%s stays clear of %s" % [box, area])
		assert_true(obstacles[-1].encloses(box), "and stands on the island")
	assert_true(town.find_children("*", "MeshInstance3D", true, false).size() >= 4, "drawn")
	var lit := false
	for mesh: MeshInstance3D in town.find_children("*", "MeshInstance3D", true, false):
		var material := mesh.material_override as StandardMaterial3D
		if material != null and material.emission_enabled:
			lit = true
			assert_eq(material.emission, Color("ffd27a"))
			assert_eq(material.emission_energy_multiplier, 3.0)
	assert_true(lit, "a lit beacon")
	var dark := Town.create(gen.towns[1], false)
	assert_true(dark.find_children("*", "VisualInstance3D", true, false).is_empty(), "nothing to draw without visuals")
	assert_true(dark.find_children("*", "Label3D", true, false).is_empty(), "or write")
	assert_false(dark.find_children("*", "CollisionShape3D", true, false).is_empty(), "but it collides")
	dark.free()
	town.free()


func test_you_can_walk_from_a_pier_to_the_town() -> void:
	var world := solo_world()
	await get_tree().process_frame
	await get_tree().physics_frame
	var dock: Vector3 = world.gen.towns[0]["dock"]
	var top := dock.y - 1.5
	var points: Array[Vector2] = []
	for z in range(-10, 31, 2):  # down the pier
		points.append(Vector2(dock.x + 6.0, dock.z + z))
	for x in range(6, 241, 6):  # along the quay
		points.append(Vector2(dock.x + x, dock.z + 37.0))
	for z in range(37, 65, 3):  # onto the island and 20 m in
		points.append(Vector2(dock.x + 240.0, dock.z + z))
	for point in points:
		assert_near(top_at(world, top, point.x, point.y), top, 0.1, "solid ground at %s" % point)


func test_the_shipyard_opens_at_any_towns_dock() -> void:
	var world := solo_world()
	await get_tree().process_frame
	var dock := move_to_town(world, 3)
	assert_true(dock.y != world.START.y, "town 3 is at another height")
	assert_eq(world.town_at(world.ship.global_transform * world.player.crew.position), 3, "you're at its dock")
	press_b(world)
	assert_true(world.shipyard != null, "the shipyard opens")
	if world.shipyard != null:
		assert_eq((world.shipyard as Shipyard).stats.altitude, dock.y, "at that dock's altitude")
	world.close_shipyard()
	world.ship.global_position = Vector3(0.0, 900.0, 0.0)  # the Eye, where there are no towns
	world.ship.reset_physics_interpolation()
	press_b(world)
	assert_true(world.shipyard == null, "not away from the towns")


func test_launching_at_another_town_uses_its_slipways() -> void:
	var world := solo_world()
	await get_tree().process_frame
	var dock := move_to_town(world, 3)
	var old: Ship = world.ship
	world.launch(StarterShip.build())
	assert_true(world.ship != old, "a new ship")
	assert_eq(world.ship.global_transform, Dock.slipway(dock, 0), "at its slipway, not raised")
	var at: Vector3 = world.ship.global_position
	assert_eq(world.town_at(at), 3)
	# A test flight goes from the same town's berth.
	await play(1.1)
	world.test_flight(StarterShip.build())
	assert_near((world.ship.global_position - Dock.test_berth(dock, 0).origin).length(), 0.0, 40.0, "the test berth there")
	assert_eq(world.town_at(world.ship.global_position), 3)


func test_a_wide_ship_is_raised_clear_of_the_piers() -> void:
	var world := solo_world()
	await get_tree().process_frame
	var dock := move_to_town(world, 2)
	var grid := StarterShip.build()
	for x in [-4, -3, 3, 4]:
		grid.set_block(Vector3i(x, -2, 0), "frame")  # 9 m across and deep enough to reach down beside the piers
	world.launch(grid)
	var ship: Ship = world.ship
	var box := ship.global_transform * ship.bounds
	assert_true(box.position.y > dock.y - 1.5, "lifted off the slipway")
	for obstacle in Dock.obstacles(dock):
		assert_false(box.intersects(obstacle), "not inside %s" % obstacle)


func test_the_server_ignores_launches_at_junk_towns() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var sync: WorldSync = client_world.sync
	var before: int = host_world.sync.ships.size()
	var blocks := StarterShip.build().to_bytes()
	for town: Variant in [99, -1, "0", 1.5, 10]:
		sync._launch.rpc_id(1, blocks, {}, false, town)
	await play(0.5)
	assert_eq(host_world.sync.ships.size(), before, "no ship was added")
	sync._launch.rpc_id(1, blocks, {}, false, 2)
	assert_true(await play_until(func() -> bool: return host_world.sync.ships.size() > before, 2.0), "a sensible town is served, so junk didn't use up the cooldown")
	var guest: Ship = host_world.sync.ship_of(client.multiplayer.get_unique_id(), false)
	assert_eq(host_world.town_at(guest.global_position), 2, "at town 2")


func test_wrecks_and_landmarks_are_built_where_the_world_says() -> void:
	var gen := WorldGen.new(NetCase.SEED)
	var wreck := {}
	for w in gen.wrecks:
		if w["region"] == WorldGen.Region.SHATTERED:
			wreck = w
			break
	assert_false(wreck.is_empty(), "a wreck in the Shattered Belt")
	var chunk := WorldGen.chunk_of(wreck["at"])
	var node := WorldChunk.build(WorldChunk.generate(gen, chunk, true))
	var found := node.find_children("Wreck*", "Node3D", false, false)
	assert_false(found.is_empty(), "the chunk has a wreck")
	if not found.is_empty():
		var meshes := found[0].find_children("*", "MeshInstance3D", true, false)
		assert_true(not meshes.is_empty() and (meshes[0] as MeshInstance3D).mesh != null, "drawn")
		var bodies := found[0].find_children("*", "StaticBody3D", true, false)
		assert_eq(bodies.size(), 1, "one body")
		var boxes := 0
		for shape: CollisionShape3D in found[0].find_children("*", "CollisionShape3D", true, false):
			boxes += 1 if shape.shape is BoxShape3D else 0
		assert_true(boxes >= 20, "%d boxes" % boxes)
		var top: Vector3 = wreck["at"] - WorldGen.chunk_origin(chunk)
		assert_true((found[0] as Node3D).position.distance_to(top) < 10.0, "on its island")
	node.free()
	var first := Sites.wreck_grid(wreck)
	var second := Sites.wreck_grid(wreck)
	assert_eq(first.blocks, second.blocks, "the same wreck every time")
	assert_true(first.cells_of("balloon").is_empty(), "no balloons")
	assert_true(first.blocks.size() < StarterShip.build().blocks.size(), "some blocks gone")
	assert_true(first.blocks.size() > 60, "but not all")

	var landmark: Dictionary = gen.landmarks[0]
	var landmark_chunk := WorldGen.chunk_of(landmark["at"])
	var landmark_node := WorldChunk.build(WorldChunk.generate(gen, landmark_chunk, true))
	var built := landmark_node.find_children("Landmark*", "Node3D", false, false)
	assert_false(built.is_empty(), "the chunk has a landmark")
	if not built.is_empty():
		var labels := built[0].find_children("*", "Label3D", true, false)
		assert_eq(labels.size(), 1)
		if not labels.is_empty():
			assert_eq((labels[0] as Label3D).text, landmark["name"])
			assert_eq((labels[0] as Label3D).visibility_range_end, 400.0)
		assert_false(built[0].find_children("*", "MeshInstance3D", true, false).is_empty(), "drawn")
		assert_false(built[0].find_children("*", "CollisionShape3D", true, false).is_empty(), "solid")
	landmark_node.free()
	# Every kind stands and is solid, drawn or not.
	for kind in WorldGen.LANDMARK_KINDS:
		for visuals in [true, false]:
			var piece := Sites.create_landmark({"name": "X", "kind": kind, "at": Vector3.ZERO, "seed": 7, "island": gen.landmarks[0]["island"]}, visuals)
			assert_false(piece.find_children("*", "CollisionShape3D", true, false).is_empty(), "%s is solid" % kind)
			assert_eq(piece.find_children("*", "MeshInstance3D", true, false).is_empty(), not visuals, "%s drawn when asked" % kind)
			piece.free()
