extends TestCase
## What ships look like: a surface per material, shaped blocks, the rounded envelope, paint.


func test_ship_faces_wind_the_way_godot_draws_them() -> void:
	# Godot culls faces that wind the other way, which would draw the ship inside out.
	var box := winding(BoxMesh.new(), 0)
	assert_true(box != 0, "a box winds one way")
	var grids: Array[ShipGrid] = [StarterShip.build()]
	for type: String in Blocks.INFO:
		for rotation in [0, 5, 14]:
			var one := ShipGrid.new()
			one.set_block(Vector3i.ZERO, type, rotation)
			grids.append(one)
	for grid in grids:
		var drawn := ShipMesh.build(grid)
		for surface in drawn.mesh.get_surface_count():
			assert_eq(winding(drawn.mesh, surface), box)
		drawn.free()


func test_one_surface_per_material() -> void:
	var grid := StarterShip.build()
	var drawn := ShipMesh.build(grid)
	assert_eq(drawn.mesh.get_surface_count(), 3)
	drawn.free()
	grid.set_block(Vector3i(0, 3, 0), "lift_stone")
	drawn = ShipMesh.build(grid)
	assert_eq(drawn.mesh.get_surface_count(), 4)
	var stone := drawn.mesh.surface_get_material(3) as StandardMaterial3D
	assert_true(stone.emission_enabled, "lift stone glows")
	drawn.free()


func test_faces_between_cubes_are_left_out() -> void:
	var grid := ShipGrid.new()
	grid.set_block(Vector3i.ZERO, "frame")
	grid.set_block(Vector3i(1, 0, 0), "frame")
	var drawn := ShipMesh.build(grid)
	assert_eq(_points(drawn).size(), 60)
	drawn.free()
	grid.set_block(Vector3i(1, 0, 0), "propeller")
	drawn = ShipMesh.build(grid)
	# The frame keeps all 6 faces (36 points); the propeller adds its own.
	assert_true(_points(drawn).size() > 36 + 36, "the frame's face beside the propeller is drawn")
	drawn.free()


func test_a_propeller_is_drawn_the_way_it_faces() -> void:
	var grid := ShipGrid.new()
	grid.set_block(Vector3i.ZERO, "propeller", 0)
	var drawn := ShipMesh.build(grid)
	assert_true(_blade_z(drawn) < -0.2, "blades at the bow side")
	drawn.free()
	grid.set_block(Vector3i.ZERO, "propeller", Blocks.turned(Blocks.turned(0)))
	drawn = ShipMesh.build(grid)
	assert_true(_blade_z(drawn) > 0.2, "blades at the stern side")
	drawn.free()


func test_the_envelope_is_rounded_cloth() -> void:
	var grid := ShipGrid.new()
	for x in 3:
		for y in 2:
			for z in 3:
				grid.set_block(Vector3i(x, y, z), "balloon")
	var drawn := ShipMesh.build(grid)
	assert_eq(drawn.mesh.get_surface_count(), 1)
	var arrays := drawn.mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var off_lattice := false
	var flat_top := false
	var diagonal := false
	for i in points.size():
		var p := points[i]
		if not (p * 2.0).is_equal_approx((p * 2.0).round()):
			off_lattice = true
		# The middle of the top face: over the centre column.
		if is_equal_approx(p.y, 1.5) and is_equal_approx(p.x, 0.5) and is_equal_approx(p.z, 0.5) and normals[i].distance_to(Vector3.UP) < 0.01:
			flat_top = true
		if absf(normals[i].y) > 0.1 and absf(normals[i].y) < 0.9:
			diagonal = true
	assert_true(off_lattice, "edges are pulled in")
	assert_true(flat_top, "the middle of the top stays flat")
	assert_true(diagonal, "edges have diagonal normals")
	drawn.free()


func test_paint_colours_every_block_of_a_type() -> void:
	var grid := ShipGrid.new()
	for x in 3:
		grid.set_block(Vector3i(x, 0, 0), "deck")
	grid.paint = {"deck": Color("2f5d8a")}
	var drawn := ShipMesh.build(grid)
	var colors: PackedColorArray = drawn.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	assert_true(colors.size() > 0, "has colours")
	for c in colors:
		assert_eq(c, Color("2f5d8a"))
	drawn.free()
	assert_eq(ShipMesh.color_of(ShipGrid.new(), "deck"), ShipMesh.COLORS["deck"])


func _points(drawn: MeshInstance3D) -> PackedVector3Array:
	return drawn.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


## The z of the blade tips (the points far out to the side).
func _blade_z(drawn: MeshInstance3D) -> float:
	for p in _points(drawn):
		if absf(p.x) > 0.4 or absf(p.y) > 0.4:
			return p.z
	return 0.0


## +1 or -1: which way every triangle of a surface turns about its normal, or 0 when they disagree.
func winding(mesh: Mesh, surface: int) -> int:
	var arrays := mesh.surface_get_arrays(surface)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var order: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if order.is_empty():
		order = PackedInt32Array(range(points.size()))
	var turns := {}
	for i in range(0, order.size(), 3):
		var a := points[order[i]]
		var turn := (points[order[i + 1]] - a).cross(points[order[i + 2]] - a).dot(normals[order[i]])
		turns[signi(roundi(signf(turn)))] = true
	return turns.keys()[0] if turns.size() == 1 else 0
