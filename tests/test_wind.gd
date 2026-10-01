extends TestCase
## The wind field (spec §4.7): prevailing wind by distance from the Eye, the rim's push
## inward, gusts, sky rivers and storm cells, and sails that catch it.


## Steady air from the west, whatever the place or time.
class SteadyWind extends Wind:
	func at(_p: Vector3, _t: float) -> Vector3:
		return Vector3(10, 0, 0)


## A world's wind with the rivers and storms the test doesn't want taken out.
func _wind_with(seed_value: int, rivers: Array[Dictionary], storms: Array[Dictionary]) -> Wind:
	var gen := WorldGen.new(seed_value)
	gen.rivers = rivers
	gen.storms = storms
	return Wind.new(gen)


func _middle_of(river: Dictionary) -> Vector3:
	var points: PackedVector3Array = river["points"]
	return (points[9] + points[10]) / 2.0


func _direction_of(river: Dictionary) -> Vector3:
	var points: PackedVector3Array = river["points"]
	return (points[10] - points[9]).normalized()


func _across(river: Dictionary) -> Vector3:
	return _direction_of(river).cross(Vector3.UP).normalized()


func test_the_prevailing_wind_rises_toward_the_gale() -> void:
	# Gusts come and go; over ten minutes they average out, leaving the prevailing wind.
	var wind := Wind.new()
	var east := Vector3.ZERO
	var west := Vector3.ZERO
	for second in 600:
		east += wind.at(Vector3(0, 800, 7000), second)  # due south of the Eye
		west += wind.at(Vector3(0, 800, -3000), second)
	assert_near((east / 600.0).x, Wind.prevailing_speed(7000.0), 0.3, "blowing east there")
	assert_near((east / 600.0).z, 0.0, 0.3)
	assert_near((west / 600.0).x, -12.0, 0.5, "the Gale Expanse blows west on the north side")


func test_the_rim_pushes_you_back() -> void:
	var wind := Wind.new()
	var sum := Vector3.ZERO
	for second in 600:
		sum += wind.at(Vector3(0, 800, 9500), second)
	assert_true((sum / 600.0).z < -10.0, "blowing inward (z %.1f)" % (sum / 600.0).z)


func test_the_wind_is_finite_and_continuous_everywhere() -> void:
	var gen := WorldGen.new(7)
	var wind := Wind.new(gen)
	var river: Dictionary = gen.rivers[0]
	var spots: Array[Vector3] = [Vector3(0, 800, 0), Vector3(8000, 0, 0), (river["points"] as PackedVector3Array)[0]]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for _n in 2000:
		var angle := rng.randf() * TAU
		var distance := rng.randf() * 10000.0
		spots.append(Vector3(cos(angle) * distance, rng.randf_range(-100.0, 2000.0), sin(angle) * distance))
	for spot in spots:
		for t in [0.0, 123.4]:
			assert_true(wind.at(spot, t).is_finite(), "finite at %s" % spot)
	# One-metre steps through the middle of a river, the edge of a storm and the Stormwall.
	var storm_at := gen.storm_center(0, 50.0) + Vector3(0, 800, 0)  # where it is when we sample
	var radius: float = gen.storms[0]["radius"]
	var walks := {
		"river": [_middle_of(river) - _across(river) * 100.0, _across(river)],
		"storm": [storm_at + Vector3(radius * 0.8 - 100.0, 0, 0), Vector3.RIGHT],
		"Stormwall": [Vector3(1600, 800, 0), Vector3.RIGHT],
	}
	for what: String in walks:
		var start: Vector3 = walks[what][0]
		var step: Vector3 = walks[what][1]
		var last := wind.at(start, 50.0)
		var crossed := what != "storm"
		for i in range(1, 201):
			var here := wind.at(start + step * float(i), 50.0)
			var strength := wind.storm_strength(start + step * float(i), 50.0)
			crossed = crossed or (strength > 0.05 and strength < 0.95)
			assert_true((here - last).length() <= 3.0, "%s: jumped %.2f m/s at step %d" % [what, (here - last).length(), i])
			last = here
		assert_true(crossed, "%s: the walk really crossed the storm's fade" % what)


func test_the_wind_is_continuous_through_a_rivers_bend() -> void:
	var gen := WorldGen.new(7)
	var wind := Wind.new(gen)
	for river in gen.rivers:
		var points: PackedVector3Array = river["points"]
		for joint in [3, 10, 16]:
			var bend := points[joint]
			var across := (points[joint + 1] - points[joint - 1]).cross(Vector3.UP).normalized()
			var last := wind.river_at(bend - across * 100.0)
			for i in range(-99, 101):
				var here := wind.river_at(bend + across * float(i))
				assert_true((here - last).length() <= 3.0, "jumped %.2f m/s at %d m from joint %d" % [(here - last).length(), i, joint])
				last = here


func test_the_wind_is_continuous_where_opposite_rivers_meet() -> void:
	# Where two rivers blowing opposite ways overlap, the pushes cancel between their
	# cores; the wind must pass through calm there, not flip round in a metre.
	var walks := 0
	for seed_value in range(1, 21):
		var gen := WorldGen.new(seed_value)
		var wind := Wind.new(gen)
		for a in gen.rivers.size():
			for b in range(a + 1, gen.rivers.size()):
				var along_a: PackedVector3Array = gen.rivers[a]["points"]
				var along_b: PackedVector3Array = gen.rivers[b]["points"]
				var reach := 2.0 * minf(gen.rivers[a]["width"], gen.rivers[b]["width"])
				for i in along_a.size() - 1:
					var p := (along_a[i] + along_a[i + 1]) / 2.0
					for j in along_b.size() - 1:
						if (along_a[i + 1] - along_a[i]).normalized().dot((along_b[j + 1] - along_b[j]).normalized()) > -0.7:
							continue
						var q := Geometry3D.get_closest_point_to_segment(p, along_b[j], along_b[j + 1])
						if p.distance_to(q) >= reach:
							continue
						walks += 1
						var steps := ceili(p.distance_to(q))
						var last := wind.river_at(p)
						for step in range(1, steps + 1):
							var here := wind.river_at(p.lerp(q, float(step) / steps))
							assert_true((here - last).length() <= 3.0, "seed %d, rivers %d and %d: jumped %.1f m/s in a metre" % [seed_value, a, b, (here - last).length()])
							last = here
	assert_true(walks > 0, "some rivers overlap going opposite ways")


func test_a_river_is_strong_in_its_core() -> void:
	var gen := WorldGen.new(7)
	var river: Dictionary = gen.rivers[0]
	var wind := _wind_with(7, [river] as Array[Dictionary], [] as Array[Dictionary])
	var middle := _middle_of(river)
	var push := wind.river_at(middle)
	assert_true((push - _direction_of(river) * float(river["speed"])).length() < 1.0, "%s, not %.1f along %s" % [push, river["speed"], _direction_of(river)])
	var outside := middle + _across(river) * (2.0 * float(river["width"]) + 1.0)
	assert_eq(wind.river_at(outside), Vector3.ZERO, "nothing beyond twice the width")


func test_a_river_fades_smoothly_at_its_edge_and_ends() -> void:
	var gen := WorldGen.new(7)
	for river in gen.rivers:
		var wind := _wind_with(7, [river] as Array[Dictionary], [] as Array[Dictionary])
		var points: PackedVector3Array = river["points"]
		var last_direction := (points[-1] - points[-2]).normalized()
		assert_eq(wind.river_at(points[-1] + last_direction * 500.0), Vector3.ZERO, "nothing past the end")
		assert_eq(wind.river_at(points[0]), Vector3.ZERO, "nothing at the very start")
		var width: float = river["width"]
		var from := _middle_of(river) + _across(river) * width
		var last := wind.river_at(from)
		for i in range(1, int(width) + 2):
			var here := wind.river_at(from + _across(river) * float(i))
			assert_true((here - last).length() <= 1.0, "jumped %.2f m/s at %d m" % [(here - last).length(), i])
			last = here


func test_storms_drift_and_blow() -> void:
	var gen := WorldGen.new(7)
	var storm: Dictionary = gen.storms[0]
	var radius: float = storm["radius"]
	var wind := _wind_with(7, [] as Array[Dictionary], [storm] as Array[Dictionary])
	var calm := Wind.new()
	var strongest := 0.0
	for second in 60:
		var centre := gen.storm_center(0, second) + Vector3(0, 800, 0)
		assert_near(wind.storm_strength(centre, second), 1.0, 0.001, "full strength at its centre")
		strongest = maxf(strongest, (wind.at(centre, second) - calm.at(centre, second)).length())
	assert_true(strongest >= 8.0, "gusts of %.1f m/s in the centre" % strongest)
	var old_centre := gen.storm_center(0, 0.0) + Vector3(0, 800, 0)
	var moved := old_centre.distance_to(gen.storm_center(0, 300.0) + Vector3(0, 800, 0))
	assert_true(moved > radius, "it drifted %.0f m (radius %.0f m)" % [moved, radius])
	assert_eq(wind.storm_strength(old_centre, 300.0), 0.0, "calm where it was")
	assert_eq(wind.at(old_centre, 300.0), calm.at(old_centre, 300.0))


func test_the_same_seed_gives_the_same_wind() -> void:
	var a := Wind.new(WorldGen.new(9))
	var b := Wind.new(WorldGen.new(9))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for _n in 100:
		var spot := Vector3(rng.randf_range(-8000, 8000), rng.randf_range(200, 1800), rng.randf_range(-8000, 8000))
		var t := rng.randf() * 1000.0
		assert_eq(a.at(spot, t), b.at(spot, t))


func test_sails_catch_the_wind() -> void:
	var sailed_grid := StarterShip.build()
	var bow_grid := StarterShip.build()
	for z in range(0, 4):
		sailed_grid.set_block(Vector3i(2, 1, z), "sail", Blocks.turned(0))  # faces starboard: +X
		bow_grid.set_block(Vector3i(2, 1, z), "sail", 0)  # faces the bow
	var plain := _fly(StarterShip.build(), 0.0)
	var sailed := _fly(sailed_grid, 200.0)
	var bow := _fly(bow_grid, 400.0)
	await simulate(20.0)
	var plain_east := plain.global_position.x
	var sailed_east := sailed.global_position.x - 200.0
	var bow_east := bow.global_position.x - 400.0
	assert_true(plain_east > 0.0, "the wind pushes the plain ship east (%.1f m)" % plain_east)
	assert_true(sailed_east > plain_east * 1.2, "sails gain at least 20%% (%.1f m against %.1f m)" % [sailed_east, plain_east])
	assert_true(absf(bow_east - plain_east) < plain_east * 0.1, "sails facing the bow gain nothing (%.1f m against %.1f m)" % [bow_east, plain_east])


func _fly(grid: ShipGrid, x: float) -> Ship:
	var ship := Ship.new(grid)
	ship.weather = SteadyWind.new()
	ship.position = Vector3(x, 880, 7000)
	add_child(ship)
	return ship


func test_the_air_is_rough_in_storms_and_the_wall() -> void:
	var walled := _wind_with(7, [], [])
	assert_eq(walled.roughness(Vector3(0, 1000, -1900), 0.0), 1.0, "in the wall, below its top")
	assert_eq(walled.roughness(Vector3(0, 1950, -1900), 0.0), 0.0, "above it")
	var gen := WorldGen.new(7)
	var stormy := Wind.new(gen)
	var core := gen.storm_center(0, 50.0) + Vector3(0, 800, 0)
	assert_eq(stormy.roughness(core, 50.0), stormy.storm_strength(core, 50.0))
	assert_eq(stormy.roughness(core, 50.0), 1.0, "a storm's core")
