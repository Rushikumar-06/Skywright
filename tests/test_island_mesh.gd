extends TestCase
## Islands shaped from their seeds: outline, hills, flat-shaded triangles for
## three levels of detail, tree spots and waterfalls (spec §3.1).


func _island(overrides := {}) -> Dictionary:
	var island := {"id": "t", "at": Vector3(10.0, 500.0, -20.0), "radius": 100.0, "depth": 140.0, "seed": 123456,
			"trees": 0.8, "waterfall": true, "flat": false, "site": ""}
	island.merge(overrides, true)
	return island


func _key(v: Vector3) -> Vector3i:
	return Vector3i((v * 100.0).round())


func test_an_island_is_the_same_every_time() -> void:
	var island := _island()
	var first := IslandMesh.arrays(island, 0)
	assert_eq(IslandMesh.arrays(island, 0), first)
	assert_eq(IslandMesh.arrays(island.duplicate(true), 0), first)
	assert_true(IslandMesh.arrays(_island({"seed": 99}), 0) != first, "another seed, another island")
	assert_eq(IslandMesh.trees(island), IslandMesh.trees(island.duplicate(true)))
	assert_eq(IslandMesh.waterfall(island), IslandMesh.waterfall(island.duplicate(true)))


func test_detail_falls_with_distance() -> void:
	var island := _island()
	var counts: Array[int] = []
	for lod in IslandMesh.LODS.size():
		var arrays := IslandMesh.arrays(island, lod)
		var vertices: PackedVector3Array = arrays["vertices"]
		assert_eq(vertices.size() % 3, 0)
		assert_eq((arrays["normals"] as PackedVector3Array).size(), vertices.size())
		assert_eq((arrays["colors"] as PackedColorArray).size(), vertices.size())
		counts.append(vertices.size() / 3)
	assert_true(counts[0] > counts[1] and counts[1] > counts[2] and counts[2] > 0, "detail falls: %s" % [counts])
	var setup: Array = IslandMesh.LODS[0]
	assert_eq(counts[0], (setup[0] as int) * (2 * (setup[1] as int) - 1) + (setup[0] as int) * (2 * (setup[2] as int) - 1))
	assert_eq(IslandMesh.LOD_END.size(), IslandMesh.LODS.size())


func test_the_mesh_is_closed_and_faces_out() -> void:
	for island in [_island(), _island({"seed": 7, "radius": 40.0, "depth": 50.0}), _island({"seed": 8, "flat": true})]:
		for lod in IslandMesh.LODS.size():
			var arrays := IslandMesh.arrays(island, lod)
			var vertices: PackedVector3Array = arrays["vertices"]
			var normals: PackedVector3Array = arrays["normals"]
			var edges := {}
			assert_true(vertices.size() > 0, "there are triangles")
			for t in vertices.size() / 3:
				var a := vertices[t * 3]
				var b := vertices[t * 3 + 1]
				var c := vertices[t * 3 + 2]
				for pair in [[a, b], [b, c], [c, a]]:
					var ka := _key(pair[0])
					var kb := _key(pair[1])
					var edge := [ka, kb] if str(ka) < str(kb) else [kb, ka]
					edges[edge] = int(edges.get(edge, 0)) + 1
				# Godot draws the side a triangle winds clockwise on.
				var normal := (c - a).cross(b - a).normalized()
				assert_true(normal.dot(normals[t * 3]) > 0.999, "normal follows the winding")
				var centroid := (a + b + c) / 3.0
				if centroid.y >= 0.0:
					assert_true(normal.y > 0.0, "a top face looks up")
				else:
					assert_true(normal.y < 0.3, "an underside face doesn't look up")
			var loose := 0
			for edge in edges:
				loose += 1 if edges[edge] != 2 else 0
			assert_eq(loose, 0, "every edge is shared by two triangles (lod %d)" % lod)


func test_the_top_matches_its_height_function() -> void:
	var island := _island()
	var faces := IslandMesh.collision_faces(island)
	assert_eq(faces, IslandMesh.arrays(island, 0)["vertices"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var highest := 0.0
	for i in 30:
		var angle := rng.randf() * TAU
		var p := Vector2(cos(angle), sin(angle)) * 100.0 * 0.8 * sqrt(rng.randf())
		var top := -INF
		for t in faces.size() / 3:
			var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(p.x, 1000.0, p.y), Vector3.DOWN, faces[t * 3], faces[t * 3 + 1], faces[t * 3 + 2])
			if hit != null:
				top = maxf(top, (hit as Vector3).y)
		var expected := IslandMesh.height(island, p.x, p.y)
		highest = maxf(highest, expected)
		assert_near(top, expected, 0.5, "the top at %s" % p)
	assert_true(highest > 1.0, "there are hills")
	assert_true(highest <= 0.08 * 100.0, "hills stay under 0.08 of the radius")


func test_the_outline_stays_within_its_range() -> void:
	var lowest := 2.0
	var highest := 0.0
	for k in 200:
		var angle := TAU * k / 200.0
		var ratio := IslandMesh.rim(_island(), angle) / 100.0
		lowest = minf(lowest, ratio)
		highest = maxf(highest, ratio)
		var flat_ratio := IslandMesh.rim(_island({"flat": true}), angle) / 100.0
		assert_true(flat_ratio >= 0.93 - 1e-4 and flat_ratio <= 1.0 + 1e-4, "a town's outline is rounder")
	assert_true(lowest >= 0.85 - 1e-4 and highest <= 1.0 + 1e-4, "outline %f to %f" % [lowest, highest])
	assert_true(highest - lowest > 0.03, "the outline wanders")


func test_town_islands_are_flat() -> void:
	var island := _island({"flat": true})
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	for i in 50:
		assert_eq(IslandMesh.height(island, rng.randf_range(-100, 100), rng.randf_range(-100, 100)), 0.0)
	var vertices: PackedVector3Array = IslandMesh.arrays(island, 0)["vertices"]
	var colors: PackedColorArray = IslandMesh.arrays(island, 0)["colors"]
	var above := 0
	for v in vertices:
		above += 1 if v.y > 0.0 else 0
	assert_eq(above, 0, "no vertex rises above the top")
	assert_true(colors.has(Color("7f9a5a")), "a town's top is its own green")


func test_trees_stand_on_the_top() -> void:
	for island in [_island(), _island({"flat": true, "seed": 3}), _island({"radius": 20.0, "seed": 4})]:
		var trees := IslandMesh.trees(island)
		var radius: float = island["radius"]
		assert_true(trees.size() > 0 and trees.size() <= 120, "some trees, not too many: %d" % trees.size())
		for i in trees.size():
			var at := trees[i].origin
			var angle := atan2(at.z, at.x)
			assert_true(Vector2(at.x, at.z).length() <= IslandMesh.rim(island, angle), "inside the rim")
			assert_near(at.y, IslandMesh.height(island, at.x, at.z), 0.5, "on the top")
			var scale := trees[i].basis.get_scale()
			assert_true(scale.x >= 0.7 - 1e-4 and scale.x <= 1.4 + 1e-4, "scaled 0.7 to 1.4")
			for j in i:
				var apart := Vector2(at.x - trees[j].origin.x, at.z - trees[j].origin.z).length()
				assert_true(apart >= 5.0, "%.2f m apart on radius %.0f" % [apart, radius])
	assert_eq(IslandMesh.trees(_island({"trees": 0.0})).size(), 0)
	assert_true(IslandMesh.trees(_island({"radius": 400.0, "trees": 1.0})).size() <= 120, "at most 120")


func test_a_waterfall_pours_off_the_rim() -> void:
	var island := _island()
	var fall := IslandMesh.waterfall(island)
	var from: Vector3 = fall["from"]
	assert_near(Vector2(from.x, from.z).length(), IslandMesh.rim(island, atan2(from.z, from.x)), 0.5)
	assert_near(from.y, IslandMesh.height(island, from.x, from.z), 0.5)
	var out: Vector3 = fall["out"]
	assert_eq(out.y, 0.0)
	assert_near(out.length(), 1.0, 1e-4)
	assert_true(out.dot(Vector3(from.x, 0.0, from.z).normalized()) > 0.99, "away from the centre")
	assert_true(fall["width"] >= 4.0 and fall["width"] <= 8.0, "4 to 8 m wide")
	assert_near(fall["drop"], 140.0 + 150.0, 1e-3)
	assert_eq(IslandMesh.waterfall(_island({"waterfall": false})), {})


func test_islands_are_fast_enough() -> void:
	var start := Time.get_ticks_usec()
	for k in 20:
		IslandMesh.arrays(_island({"seed": k}), 0)
	var msec := (Time.get_ticks_usec() - start) / 1000.0
	print("20 islands of radius 100 at level 0: %.1f ms" % msec)
	assert_true(msec < 60.0, "20 islands took %.1f ms" % msec)
