class_name WorldStreamer
extends Node3D
## Loads the world's chunks around its focus points and frees them again once
## they're far behind (spec §4.7). Chunks are generated on WorkerThreadPool and
## added a few a frame, within a time budget, nearest first; far chunks are freed
## a few a frame, within what's left of it. It runs in _process, which on a
## dedicated server keeps pace with the physics.

const LOAD_RADIUS := 2500.0    ## m: chunks this near a focus point are loaded.
const UNLOAD_RADIUS := 2800.0  ## m: chunks further than this from every focus point are freed.
const BUDGET_USEC := 3000      ## Time a frame may spend adding and freeing chunks (at least one of each).
const MAX_JOBS := 8            ## Chunks generating, or generated and waiting to be added, at once.
const REPLAN_EVERY := 0.25     ## s between working out what's wanted.
const MERGE := 64.0            ## m: focus points this close together count as one (the first), which moves the edge at most this far.
const RING := 64.0             ## m: wanted chunks are loaded in rings this wide, nearest first.

var gen: WorldGen
var visuals := true    ## Meshes, trees and waterfalls, or only collision.
var focus: Callable    ## Returns Array[Vector3]: where the world must be loaded around.
var chunks: Dictionary = {}  ## Vector2i -> Node3D, the loaded chunks.

var _wanted: Dictionary = {}       ## Chunk -> distance to the nearest focus point (0 if loaded), from the last replan.
var _order: Array[Vector2i] = []   ## _wanted's chunks that weren't loaded at the last replan, nearest first.
var _freeing: Dictionary = {}      ## Vector2i -> Node3D: far chunks waiting to be freed.
var _jobs: Dictionary = {}         ## Chunk -> task id, until its result is added or dropped.
var _collect: Array[int] = []      ## Task ids whose results are used, to wait for.
var _done: Array[Dictionary] = []  ## Finished results, pushed by workers under _lock.
var _lock := Mutex.new()
var _since_plan := 0.0


func _init(world_gen: WorldGen, with_visuals: bool) -> void:
	gen = world_gen
	visuals = with_visuals
	name = "Streamer"


func _ready() -> void:
	replan()


## Chunks wanted but not added yet.
func pending() -> int:
	var count := 0
	for chunk: Vector2i in _wanted:
		if not chunks.has(chunk):
			count += 1
	return count


## Whether every wanted chunk is loaded and every far one freed.
func settled() -> bool:
	return pending() == 0 and _freeing.is_empty()


## Works out which chunks are wanted now (WorldGen.chunks_near's for each focus point),
## queues the far ones for freeing and starts generating.
func replan() -> void:
	_since_plan = 0.0
	var points: Array[Vector3] = []
	if focus.is_valid():
		for p: Vector3 in focus.call():
			var near := false
			for q in points:
				near = near or q.distance_to(p) < MERGE
			if not near:
				points.append(p)
	# One pass over each point's circle of chunks, a row at a time: the chunks within
	# LOAD_RADIUS (and the disc) are wanted, the rest within UNLOAD_RADIUS are kept.
	_wanted = {}
	var keep := {}
	var missing: Array[Vector2i] = []  # wanted and not loaded
	var size := WorldGen.CHUNK
	var disc_squared := (WorldGen.RADIUS + size) ** 2  # chunks_near's limit on a chunk's centre
	for p in points:
		for cz in range(floori((p.z - UNLOAD_RADIUS) / size), floori((p.z + UNLOAD_RADIUS) / size) + 1):
			var z0 := cz * size
			var dz := maxf(0.0, maxf(z0 - p.z, p.z - z0 - size))
			var reach := sqrt(maxf(0.0, UNLOAD_RADIUS ** 2 - dz * dz))
			var first := floori((p.x - reach) / size)
			var last := floori((p.x + reach) / size)
			var load_first := last + 1  # none, unless the row comes within LOAD_RADIUS
			var load_last := last
			if dz <= LOAD_RADIUS:
				var load_reach := sqrt(LOAD_RADIUS ** 2 - dz * dz)
				load_first = floori((p.x - load_reach) / size)
				load_last = floori((p.x + load_reach) / size)
				var disc := sqrt(maxf(0.0, disc_squared - (z0 + size / 2.0) ** 2))
				for cx in range(maxi(load_first, ceili((-disc - size / 2.0) / size)), mini(load_last, floori((disc - size / 2.0) / size)) + 1):
					var chunk := Vector2i(cx, cz)
					if chunks.has(chunk):
						_wanted[chunk] = 0.0  # loaded: how near no longer matters
						continue
					if not _wanted.has(chunk):
						missing.append(chunk)
					var dx := maxf(0.0, maxf(cx * size - p.x, p.x - cx * size - size))
					_wanted[chunk] = minf(_wanted.get(chunk, INF), sqrt(dx * dx + dz * dz))
			for cx in range(first, load_first):
				keep[Vector2i(cx, cz)] = true
			for cx in range(load_last + 1, last + 1):
				keep[Vector2i(cx, cz)] = true
	for chunk: Vector2i in _freeing.keys():
		if _wanted.has(chunk) or keep.has(chunk):  # near again before it was freed: keep it
			chunks[chunk] = _freeing[chunk]
			_freeing.erase(chunk)
	for chunk: Vector2i in chunks.keys():
		if not _wanted.has(chunk) and not keep.has(chunk):
			_freeing[chunk] = chunks[chunk]
			chunks.erase(chunk)
	# Nearest first, a ring at a time, with no sorting.
	var rings: Array[Array] = []
	for i in ceili(LOAD_RADIUS / RING) + 1:
		rings.append([])
	for chunk in missing:
		if not chunks.has(chunk):
			rings[int(_wanted[chunk] / RING)].append(chunk)
	_order.clear()
	for ring in rings:
		for chunk: Vector2i in ring:
			_order.append(chunk)
	_start_jobs()


func _process(delta: float) -> void:
	_since_plan += delta
	if _since_plan >= REPLAN_EVERY:
		replan()
	_lock.lock()
	var results := _done
	_done = []
	_lock.unlock()
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _wanted.get(a["chunk"], INF) < _wanted.get(b["chunk"], INF))
	var start := Time.get_ticks_usec()
	var added := 0
	for data in results:
		var chunk: Vector2i = data["chunk"]
		var wanted := _wanted.has(chunk) and not chunks.has(chunk)
		if wanted and added > 0 and Time.get_ticks_usec() - start > BUDGET_USEC:
			_lock.lock()
			_done.append(data)  # next frame
			_lock.unlock()
			continue
		if wanted:
			var node := WorldChunk.build(data)
			add_child(node)
			chunks[chunk] = node
			added += 1
		_collect.append(_jobs[chunk])
		_jobs.erase(chunk)
	# Far chunks go with what's left of the budget, at least one a frame.
	var freed := 0
	for chunk: Vector2i in _freeing.keys():
		if freed > 0 and Time.get_ticks_usec() - start > BUDGET_USEC:
			break
		(_freeing[chunk] as Node3D).free()
		_freeing.erase(chunk)
		freed += 1
	# The tasks whose results were used have pushed them and are ending, if not ended.
	for id in _collect.duplicate():
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			_collect.erase(id)
	_start_jobs()


func _exit_tree() -> void:
	# No worker may touch this node once it's gone.
	for id: int in _jobs.values() + _collect:
		WorkerThreadPool.wait_for_task_completion(id)
	_jobs.clear()
	_collect.clear()
	_done.clear()


## Starts generating the nearest wanted chunks that aren't loaded or on their way.
func _start_jobs() -> void:
	for chunk in _order:
		if _jobs.size() >= MAX_JOBS:
			return
		if not chunks.has(chunk) and not _jobs.has(chunk):
			_jobs[chunk] = WorkerThreadPool.add_task(_generate.bind(gen, chunk, visuals), false, "Chunk")


## On a worker thread: generates chunk and hands it over.
func _generate(world_gen: WorldGen, chunk: Vector2i, with_visuals: bool) -> void:
	var data := WorldChunk.generate(world_gen, chunk, with_visuals)
	_lock.lock()
	_done.append(data)
	_lock.unlock()
