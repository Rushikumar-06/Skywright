extends TestCase
## The seeded world: regions, towns, landmarks, wrecks, rivers, storms and the
## islands of each chunk (spec §3.1, §4.7).


## Every chunk of the disc's islands, as {Vector2i: Array[Dictionary]}.
func _disc(gen: WorldGen) -> Dictionary:
	var all := {}
	for cx in range(-33, 33):
		for cz in range(-33, 33):
			var chunk := Vector2i(cx, cz)
			all[chunk] = gen.islands_in(chunk)
	return all


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func test_regions_by_distance_from_the_eye() -> void:
	assert_eq(WorldGen.region_at(Vector3(0, 900, 0)), WorldGen.Region.EYE)
	assert_eq(WorldGen.region_at(Vector3(0, 0, 1599)), WorldGen.Region.EYE)
	assert_eq(WorldGen.region_at(Vector3(1600, 0, 0)), WorldGen.Region.STORMWALL)
	assert_eq(WorldGen.region_at(Vector3(0, 0, -3000)), WorldGen.Region.GALE)
	assert_eq(WorldGen.region_at(Vector3(4500, 0, 0)), WorldGen.Region.SHATTERED)
	assert_eq(WorldGen.region_at(Vector3(0, 0, 7000)), WorldGen.Region.CALM)
	assert_eq(WorldGen.region_at(Vector3(9000, 0, 0)), WorldGen.Region.RIM)


func test_chunk_maths() -> void:
	assert_eq(WorldGen.chunk_of(Vector3(-0.5, 0, 256)), Vector2i(-1, 1))
	assert_eq(WorldGen.chunk_origin(Vector2i(-2, 3)), Vector3(-512, 0, 768))
	assert_eq(WorldGen.START, Vector3(0.0, 880.0, 7000.0))


func test_the_same_seed_builds_the_same_world() -> void:
	var a := WorldGen.new(42)
	var b := WorldGen.new(42)
	var c := WorldGen.new(43)
	for what in ["towns", "landmarks", "wrecks", "rivers", "storms"]:
		assert_eq(var_to_str(a.get(what)), var_to_str(b.get(what)), what)
	assert_true(var_to_str(a.towns) != var_to_str(c.towns), "another seed, other towns")
	var differs := false
	for k in 50:
		var chunk := Vector2i(-25 + k, -20 + k)
		assert_eq(a.islands_in(chunk), b.islands_in(chunk))
		differs = differs or a.islands_in(chunk) != c.islands_in(chunk)
	assert_true(differs, "another seed, other islands")


func test_chunks_dont_depend_on_the_order_they_are_made_in() -> void:
	var gen := WorldGen.new(5)
	var before := gen.islands_in(Vector2i(10, 20))
	for k in 30:
		gen.islands_in(Vector2i(k - 15, k))
	assert_eq(gen.islands_in(Vector2i(10, 20)), before)
	assert_eq(WorldGen.new(5).islands_in(Vector2i(10, 20)), before)


func test_ten_towns_in_their_regions() -> void:
	var expected := [WorldGen.Region.CALM, WorldGen.Region.CALM, WorldGen.Region.CALM, WorldGen.Region.CALM,
			WorldGen.Region.SHATTERED, WorldGen.Region.SHATTERED, WorldGen.Region.SHATTERED,
			WorldGen.Region.GALE, WorldGen.Region.GALE, WorldGen.Region.STORMWALL]
	for world_seed in range(1, 21):
		var gen := WorldGen.new(world_seed)
		assert_eq(gen.towns.size(), 10, "seed %d has ten towns" % world_seed)
		if gen.towns.size() != 10:
			continue
		assert_eq(gen.towns[0]["dock"], WorldGen.START)
		var names := {}
		for i in 10:
			var town := gen.towns[i]
			assert_eq(town["region"], expected[i], "seed %d town %d" % [world_seed, i])
			assert_eq(WorldGen.region_at(town["dock"]), expected[i])
			assert_true(not (town["name"] as String).is_empty())
			names[town["name"]] = true
			var island: Dictionary = town["island"]
			assert_eq(island["at"], town["dock"] + WorldGen.TOWN_ISLAND)
			assert_true(_flat(Vector3.ZERO, island["at"]) + island["radius"] <= WorldGen.RADIUS, "island in the disc")
			for j in i:
				assert_true(_flat(town["dock"], gen.towns[j]["dock"]) >= 1500.0, "towns %d and %d apart" % [i, j])
		assert_eq(names.size(), 10, "names are unique")


func test_islands_keep_clear_of_towns_and_each_other() -> void:
	var gen := WorldGen.new(7)
	var chunks := {}
	for town in gen.towns:
		for chunk in WorldGen.chunks_near(town["dock"], 3000.0):
			chunks[chunk] = true
	for k in 200:
		chunks[WorldGen.chunk_of(Vector3(cos(0.7), 0, sin(0.7)) * k * 40.0)] = true
	var sites: Array[Dictionary] = []
	for entry in gen.landmarks + gen.wrecks:
		sites.append(entry["island"])
	var checked := 0
	for chunk: Vector2i in chunks:
		var islands := gen.islands_in(chunk)
		for i in islands.size():
			var a := islands[i]
			checked += 1
			assert_true(_flat(Vector3.ZERO, a["at"]) + a["radius"] <= WorldGen.RADIUS, "in the disc")
			assert_true(a["at"].y >= 300.0 and a["at"].y <= 1800.0, "at a flyable height")
			assert_false(gen.in_town_exclusion(a["at"], a["radius"]), "clear of towns")
			for j in i:
				var b := islands[j]
				if a["site"] != "" or b["site"] != "":
					continue
				var gap: float = _flat(a["at"], b["at"]) - a["radius"] - b["radius"]
				var close_in_height: bool = absf(a["at"].y - b["at"].y) < (a["radius"] + b["radius"]) * 1.3
				assert_false(gap < 20.0 and close_in_height, "islands overlap in %s" % chunk)
			if a["site"] == "":
				for site in sites:
					assert_true(_flat(a["at"], site["at"]) >= a["radius"] + site["radius"] + 40.0, "clear of sites")
	assert_true(checked > 100, "looked at %d islands" % checked)


func test_the_shattered_belt_is_densest() -> void:
	var gen := WorldGen.new(7)
	var islands := [0, 0, 0, 0, 0, 0]
	var chunks := [0, 0, 0, 0, 0, 0]
	var total := 0
	var disc := _disc(gen)
	for chunk: Vector2i in disc:
		var region := WorldGen.region_at(WorldGen.chunk_origin(chunk) + Vector3(128, 0, 128))
		chunks[region] += 1
		islands[region] += (disc[chunk] as Array).size()
		total += (disc[chunk] as Array).size()
	var density := func(region: int) -> float: return float(islands[region]) / maxf(chunks[region], 1)
	for region in [WorldGen.Region.EYE, WorldGen.Region.STORMWALL, WorldGen.Region.GALE, WorldGen.Region.CALM]:
		assert_true(density.call(WorldGen.Region.SHATTERED) > density.call(region), "denser than %s" % WorldGen.REGION_NAMES[region])
	assert_true(total >= 2000 and total <= 8000, "%d islands in the disc" % total)


func test_landmarks_and_wrecks_have_their_own_islands() -> void:
	var gen := WorldGen.new(7)
	assert_eq(gen.landmarks.size(), 8)
	assert_eq(gen.wrecks.size(), 20)
	var regions := {}
	for entry in gen.landmarks:
		regions[entry["region"]] = int(regions.get(entry["region"], 0)) + 1
		assert_eq(WorldGen.region_at(entry["at"]), entry["region"])
		assert_eq(entry["island"]["site"], "landmark")
		assert_eq(entry["island"]["at"], entry["at"])
	assert_eq(regions, {WorldGen.Region.CALM: 2, WorldGen.Region.SHATTERED: 2, WorldGen.Region.GALE: 2, WorldGen.Region.STORMWALL: 1, WorldGen.Region.EYE: 1})
	regions = {}
	for entry in gen.wrecks:
		regions[entry["region"]] = int(regions.get(entry["region"], 0)) + 1
		assert_eq(WorldGen.region_at(entry["at"]), entry["region"])
		assert_eq(entry["island"]["site"], "wreck")
	assert_eq(regions, {WorldGen.Region.CALM: 3, WorldGen.Region.SHATTERED: 10, WorldGen.Region.GALE: 5, WorldGen.Region.STORMWALL: 2})
	var names := {}
	for entry in gen.landmarks:
		names[entry["name"]] = true
	assert_eq(names.size(), 8, "landmark names are unique")
	var seen := {}
	var disc := _disc(gen)
	for chunk: Vector2i in disc:
		for island: Dictionary in disc[chunk]:
			if island["site"] != "":
				seen[island["at"]] = int(seen.get(island["at"], 0)) + 1
				assert_eq(WorldGen.chunk_of(island["at"]), chunk)
	for entry in gen.landmarks + gen.wrecks:
		assert_eq(seen.get(entry["at"], 0), 1, "one island at %s" % entry["at"])
	assert_eq(seen.size(), 28)


func test_rivers_and_storms() -> void:
	var gen := WorldGen.new(11)
	assert_true(gen.rivers.size() >= 6 and gen.rivers.size() <= 10)
	for river in gen.rivers:
		var points: PackedVector3Array = river["points"]
		assert_eq(points.size(), 20)
		for point in points:
			var d := _flat(Vector3.ZERO, point)
			assert_true(d >= 1000.0 - 0.01 and d <= 7900.0 + 0.01, "river point %.0f m out" % d)
			assert_true((river["box"] as AABB).has_point(point))
		assert_true(river["width"] >= 60.0 and river["width"] <= 120.0)
		assert_true(river["speed"] >= 20.0 and river["speed"] <= 35.0)
	assert_true(gen.storms.size() >= 6 and gen.storms.size() <= 10)
	for i in gen.storms.size():
		var storm := gen.storms[i]
		assert_near(_flat(Vector3.ZERO, gen.storm_center(i, 0.0)), storm["orbit"], 0.01)
		var now := gen.storm_center(i, 0.0)
		var later := gen.storm_center(i, 100.0)
		assert_near(_flat(Vector3.ZERO, later), storm["orbit"], 0.01, "stays on its orbit")
		assert_true(angle_difference(atan2(now.z, now.x), atan2(later.z, later.x)) < 0.0, "counter-clockwise from above: its angle decreases")


func test_prevailing_wind_speed_by_distance() -> void:
	for pair in [[0.0, 3.0], [1400.0, 5.0], [1600.0, 10.0], [1900.0, 14.0], [2200.0, 12.0], [2400.0, 12.0], [4000.0, 12.0], [6000.0, 5.0], [8000.0, 2.0]]:
		assert_near(Wind.prevailing_speed(pair[0]), pair[1], 0.0001, "at %.0f m" % pair[0])
	assert_near(Wind.prevailing_speed(700.0), 4.0, 0.0001)
	assert_near(Wind.prevailing_speed(1750.0), 12.0, 0.0001)
	assert_near(Wind.prevailing_speed(-50.0), 3.0, 0.0001)
	assert_near(Wind.prevailing_speed(9500.0), 2.0, 0.0001)


func test_chunks_near_lists_the_nearest_first() -> void:
	var near := WorldGen.chunks_near(WorldGen.START, 2500.0)
	assert_true(near.size() >= 200 and near.size() <= 330, "%d chunks" % near.size())
	assert_eq(near[0], WorldGen.chunk_of(WorldGen.START))
	var last := -1.0
	for chunk in near:
		var origin := WorldGen.chunk_origin(chunk)
		var nearest := Vector2(clampf(WorldGen.START.x, origin.x, origin.x + WorldGen.CHUNK), clampf(WorldGen.START.z, origin.z, origin.z + WorldGen.CHUNK))
		var d := nearest.distance_to(Vector2(WorldGen.START.x, WorldGen.START.z))
		assert_true(d <= 2500.0)
		assert_true(d >= last, "distances never decrease")
		last = d
