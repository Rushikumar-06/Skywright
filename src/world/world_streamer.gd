class_name WorldStreamer
extends Node3D
## Loads the world's chunks around its focus points and frees them again once
## they're far behind (spec §4.7). Chunks are generated on WorkerThreadPool and
## added a few a frame, within a time budget, nearest first. It runs in _process,
## which on a dedicated server keeps pace with the physics.

const LOAD_RADIUS := 2500.0    ## m: chunks this near a focus point are loaded.
const UNLOAD_RADIUS := 2800.0  ## m: chunks further than this from every focus point are freed.
const BUDGET_USEC := 3000      ## Time a frame may spend adding chunks (at least one is added).
const MAX_JOBS := 8            ## Chunks generating, or generated and waiting to be added, at once.
const REPLAN_EVERY := 0.25     ## s between working out what's wanted.

var gen: WorldGen
var visuals := true    ## Meshes, trees and waterfalls, or only collision.
var focus: Callable    ## Returns Array[Vector3]: where the world must be loaded around.
var chunks: Dictionary = {}  ## Vector2i -> Node3D, the loaded chunks.

var _wanted: Dictionary = {}       ## Chunk -> distance to the nearest focus point, from the last replan.
var _order: Array[Vector2i] = []   ## _wanted's chunks, nearest first.
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


## Whether every wanted chunk is loaded.
func settled() -> bool:
	return pending() == 0


## Works out which chunks are wanted now, frees the far ones and starts generating.
func replan() -> void:
	_since_plan = 0.0
	var points: Array[Vector3] = []
	if focus.is_valid():
		points = focus.call()
	_wanted = {}
	for p in points:
		for chunk in WorldGen.chunks_near(p, LOAD_RADIUS):
			_wanted[chunk] = minf(_wanted.get(chunk, INF), _distance(chunk, p))
	_order.assign(_wanted.keys())
	_order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _wanted[a] < _wanted[b])
	for chunk: Vector2i in chunks.keys():
		var near := false
		for p in points:
			near = near or _distance(chunk, p) <= UNLOAD_RADIUS
		if not near:
			(chunks[chunk] as Node3D).queue_free()
			chunks.erase(chunk)
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


## The horizontal distance from p to chunk's square.
static func _distance(chunk: Vector2i, p: Vector3) -> float:
	var origin := WorldGen.chunk_origin(chunk)
	var nearest := Vector2(clampf(p.x, origin.x, origin.x + WorldGen.CHUNK), clampf(p.z, origin.z, origin.z + WorldGen.CHUNK))
	return nearest.distance_to(Vector2(p.x, p.z))
