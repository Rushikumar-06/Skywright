extends NetCase
## The seed makes the world: the same seed builds the same world on any thread and
## any machine, chunks are quick to make, and the pause menu shows the seed (spec §4.7).


## Forty chunks that have islands, spread over the disc.
func _spread() -> Array[Vector2i]:
	var gen := WorldGen.new(1)
	var chunks: Array[Vector2i] = []
	var k := 0
	while chunks.size() < 40 and k < 4000:
		var chunk := Vector2i(-31 + (k * 13) % 63, -31 + (k * 29) % 63)
		if Vector2(chunk).length() < 30.0 and not gen.islands_in(chunk).is_empty():
			chunks.append(chunk)
		k += 1
	return chunks


## A number that stands for everything the seed made: the sites, every island of the
## disc, and the arrays, trees, waterfalls and clouds of the chunks.
func _digest(seed_value: int, chunks: Array[Vector2i]) -> int:
	var gen := WorldGen.new(seed_value)
	var parts: Array[int] = []
	for what in ["towns", "landmarks", "wrecks", "rivers", "storms"]:
		parts.append(hash(var_to_str(gen.get(what))))
	for cx in range(-33, 33):
		for cz in range(-33, 33):
			parts.append(hash(var_to_str(gen.islands_in(Vector2i(cx, cz)))))
	for chunk in chunks:
		parts.append(hash(var_to_str(WorldChunk.generate(gen, chunk, true))))
	return hash(parts)


func test_the_same_seed_always_builds_the_same_world() -> void:
	var chunks := _spread()
	assert_eq(chunks.size(), 40, "enough chunks with islands")
	var digests: Array[int] = []
	for seed_value in [1, 2, 2026]:
		var first := _digest(seed_value, chunks)
		assert_eq(_digest(seed_value, chunks), first, "seed %d twice" % seed_value)
		digests.append(first)
	assert_true(digests[0] != digests[1] and digests[1] != digests[2] and digests[0] != digests[2], "each seed its own world")


func test_the_same_seed_builds_the_same_chunks_on_worker_threads() -> void:
	var gen := WorldGen.new(7)
	var chunks := _spread().slice(0, 16)
	var here: Array[String] = []
	for chunk in chunks:
		here.append(var_to_str(WorldChunk.generate(gen, chunk, true)))
	var there: Array[String] = []
	there.resize(chunks.size())
	var work := func(i: int) -> void:
		there[i] = var_to_str(WorldChunk.generate(gen, chunks[i], true))
	var task := WorkerThreadPool.add_group_task(work, chunks.size())
	WorkerThreadPool.wait_for_group_task_completion(task)
	for i in chunks.size():
		assert_true(there[i] == here[i], "chunk %s" % chunks[i])


func test_a_wreck_and_a_town_are_the_same_every_time() -> void:
	var boxes: Array[String] = []
	var wrecks: Array[String] = []
	for run in 2:
		var gen := WorldGen.new(5)
		wrecks.append(var_to_str(Sites.wreck_grid(gen.wrecks[0]).blocks))
		var town := Town.create(gen.towns[0], false)
		var shapes: Array[String] = []
		for shape: CollisionShape3D in town.get_node("Buildings").get_children():
			shapes.append("%s %s" % [shape.transform, (shape.shape as BoxShape3D).size])
		boxes.append(str(shapes))
		town.free()
	assert_true(wrecks[0] == wrecks[1], "the wreck's blocks")
	assert_true(boxes[0] == boxes[1], "the town's boxes")
	assert_true(boxes[0].length() > 100, "there are some")


func test_the_wind_is_the_same_on_every_machine() -> void:
	for seed_value in [1, 2, 2026]:
		var a := Wind.new(WorldGen.new(seed_value))
		var b := Wind.new(WorldGen.new(seed_value))
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		for k in 500:
			var p := Vector3(rng.randf_range(-9000.0, 9000.0), rng.randf_range(0.0, 2000.0), rng.randf_range(-9000.0, 9000.0))
			var t := rng.randf_range(0.0, 5000.0)
			assert_eq(a.at(p, t), b.at(p, t), "seed %d at %s, %.0f s" % [seed_value, p, t])


func test_a_chunk_is_quick_to_make() -> void:
	var gen := WorldGen.new(NetCase.SEED)
	var chunks: Array[Vector2i] = []
	for k in 60:
		chunks.append(Vector2i(-28 + (k * 7) % 57, -28 + (k * 11) % 57))
	var slowest_generate := 0
	var slowest_build := 0
	for chunk in chunks:
		var start := Time.get_ticks_usec()
		var data := WorldChunk.generate(gen, chunk, true)
		slowest_generate = maxi(slowest_generate, Time.get_ticks_usec() - start)
		start = Time.get_ticks_usec()
		var node := WorldChunk.build(data)
		add_child(node)
		slowest_build = maxi(slowest_build, Time.get_ticks_usec() - start)
		node.free()
	print("  slowest chunk: generate %.1f ms, build %.1f ms" % [slowest_generate / 1000.0, slowest_build / 1000.0])
	assert_true(slowest_generate < 40000, "generate took %.1f ms" % [slowest_generate / 1000.0])
	assert_true(slowest_build < 6000, "build took %.1f ms" % [slowest_build / 1000.0])


func test_the_pause_menu_shows_the_seed() -> void:
	var world := solo_world()
	await get_tree().process_frame
	var pause := InputEventAction.new()
	pause.action = "pause"
	pause.pressed = true
	world._unhandled_input(pause)
	assert_true(world._pause.visible)
	var captions: Array = world._pause.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text)
	assert_true(captions.has("World seed 20260930"), "captions were %s" % [captions])
