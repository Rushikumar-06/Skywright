class_name WorldGen
extends RefCounted
## The world made from a seed (spec §3.1, §4.7): a disc of floating islands in five
## regions, from the Calm Reaches at the edge to the Eye at the centre. Everything
## the whole disc needs to know is worked out once, in _init: ten towns, the
## landmarks, the wrecks, the sky rivers and the storm cells. Plain islands are
## worked out per 256 m chunk, on demand, from a seed of the chunk's own, so any
## chunk comes out the same whichever order (or on whichever machine) it's made in.
## Nothing here touches nodes or the global random functions, so it's safe on
## worker threads.
##
## An island is {"id": String, "at": Vector3 (top centre), "radius", "depth": float,
## "seed": int, "trees": float (0 to 1), "waterfall": bool, "flat": bool, "site": String
## ("", "landmark" or "wreck")}. A town is {"name", "dock": Vector3, "region": int,
## "seed": int, "island"}, a landmark {"name", "kind": "spire", "arch" or "ruin", "at",
## "region", "seed", "island"}, a wreck {"at", "region", "seed", "yaw", "roll",
## "island"}, a river {"points": PackedVector3Array, "width", "speed", "box": AABB}
## and a storm cell {"orbit", "angle", "spin" (rad/s), "radius"}.

const RADIUS := 8000.0   ## m: the disc.
const CHUNK := 256.0     ## m: the side of a chunk.
const START := Vector3(0.0, 880.0, 7000.0)  ## Slipway 0 of the starting town.

enum Region { EYE, STORMWALL, GALE, SHATTERED, CALM, RIM }

const REGION_NAMES := ["The Eye", "The Stormwall", "The Gale Expanse", "The Shattered Belt", "The Calm Reaches", "The Rim"]
const REGION_OUTER := [1600.0, 2200.0, 4000.0, 6000.0, 8000.0]  ## m from the centre where each region ends.

const TOWN_ISLAND := Vector3(240.0, -1.5, 160.0)  ## A town island's top centre, from its dock.
const TOWN_RADIUS := 130.0
const TOWN_SPACING := 1500.0
const EXCLUSION_DOCK := 150.0    ## m a town's dock area is grown by to keep others away.
const EXCLUSION_ISLAND := 60.0   ## m a town's island is grown by.
const SITE_GAP := 40.0           ## m of clear air between a plain island and a landmark's or wreck's.
const EDGE := 150.0              ## m sites keep inside their region's edges.
const DARTS := 400

## What each region gets: (towns after the first, landmarks, wrecks), in order.
const TOWN_PLAN := [[Region.CALM, 3], [Region.SHATTERED, 3], [Region.GALE, 2], [Region.STORMWALL, 1]]
const LANDMARK_PLAN := [[Region.CALM, 2], [Region.SHATTERED, 2], [Region.GALE, 2], [Region.STORMWALL, 1], [Region.EYE, 1]]
const WRECK_PLAN := [[Region.CALM, 3], [Region.SHATTERED, 10], [Region.GALE, 5], [Region.STORMWALL, 2]]

const TOWN_NAME_START := ["Ash", "Bright", "Cinder", "Dun", "Ever", "Fair", "Gull", "Harrow", "Iron", "Kestrel",
		"Lark", "Mill", "North", "Oak", "Pike", "Rook", "Salt", "Thorn", "Wind", "Yarrow"]
const TOWN_NAME_END := ["haven", "hold", "mere", "port", "reach", "stead", "wick", "moor", "fall", "ford", "crest", "gate"]
const LANDMARK_NAMES := ["Hollow", "Grey", "Weeping", "Broken", "Sunward", "Lantern", "Iron", "Drowned", "Whistling", "Crowned"]
const LANDMARK_KINDS := ["spire", "arch", "ruin"]
const LANDMARK_SUFFIXES := [" Spire", " Arch", " Ruins"]

## Plain islands by region (indexed by Region): tries per chunk and radius range in m.
const CHUNK_TRIES := [2, 1, 2, 4, 2, 0]
const CHUNK_RADII: Array[Vector2] = [Vector2(40, 120), Vector2(15, 40), Vector2(30, 110), Vector2(15, 60), Vector2(25, 100), Vector2.ZERO]
const MAX_ISLAND_RADIUS := 115.0
const TRY_CHANCE := 0.7

var world_seed: int
var towns: Array[Dictionary] = []
var landmarks: Array[Dictionary] = []
var wrecks: Array[Dictionary] = []
var rivers: Array[Dictionary] = []
var storms: Array[Dictionary] = []

var _town_rects: Array[Rect2] = []  ## Each town's dock exclusion, from the top.


func _init(seed_value: int) -> void:
	world_seed = seed_value
	_make_towns()
	_make_landmarks()
	_make_wrecks()
	_make_rivers()
	_make_storms()


## The region a point is in, by horizontal distance from the centre.
static func region_at(p: Vector3) -> int:
	var distance := Vector2(p.x, p.z).length()
	for region in 5:
		if distance < REGION_OUTER[region]:
			return region
	return Region.RIM


static func chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))


## A chunk's corner with the lowest x and z, at y 0.
static func chunk_origin(chunk: Vector2i) -> Vector3:
	return Vector3(chunk.x * CHUNK, 0.0, chunk.y * CHUNK)


## The chunks whose square comes within radius of p horizontally, and that lie
## within RADIUS + CHUNK of the centre. The one p is in comes first, then the
## rest, nearest first.
static func chunks_near(p: Vector3, radius: float) -> Array[Vector2i]:
	var home := chunk_of(p)
	var found: Array = []  # [distance, chunk]
	for cx in range(floori((p.x - radius) / CHUNK), floori((p.x + radius) / CHUNK) + 1):
		for cz in range(floori((p.z - radius) / CHUNK), floori((p.z + radius) / CHUNK) + 1):
			var chunk := Vector2i(cx, cz)
			var origin := chunk_origin(chunk)
			var nearest := Vector2(clampf(p.x, origin.x, origin.x + CHUNK), clampf(p.z, origin.z, origin.z + CHUNK))
			var distance := nearest.distance_to(Vector2(p.x, p.z))
			var centre := Vector2(origin.x + CHUNK / 2.0, origin.z + CHUNK / 2.0)
			if distance <= radius and centre.length() <= RADIUS + CHUNK:
				found.append([-1.0 if chunk == home else distance, chunk])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var chunks: Array[Vector2i] = []
	for entry in found:
		chunks.append(entry[1])
	return chunks


## The plain islands of a chunk, then the islands of the landmarks and wrecks
## whose `at` lies in it. Made from the chunk's own seed, so it doesn't matter
## what else has been asked for.
func islands_in(chunk: Vector2i) -> Array[Dictionary]:
	var islands: Array[Dictionary] = []
	var origin := chunk_origin(chunk)
	var region := region_at(origin + Vector3(CHUNK / 2.0, 0.0, CHUNK / 2.0))
	var nearest := Vector2(clampf(0.0, origin.x, origin.x + CHUNK), clampf(0.0, origin.z, origin.z + CHUNK))
	if nearest.length() <= RADIUS and CHUNK_TRIES[region] > 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([world_seed, chunk.x, chunk.y, "islands"])
		var radii := CHUNK_RADII[region]
		var tops := Vector2(300.0, 1700.0) if region == Region.SHATTERED else Vector2(350.0, 1500.0)
		var trees := Vector2(0.1, 0.4) if region == Region.STORMWALL else Vector2(0.2, 1.0)
		for i in CHUNK_TRIES[region] as int:
			# Every draw happens whether or not the try comes to anything, so a
			# refusal never shifts the islands after it.
			var lucky := rng.randf() < TRY_CHANCE
			var radius := minf(rng.randf_range(radii.x, radii.y), MAX_ISLAND_RADIUS)
			var margin := radius + 8.0
			var at := Vector3(
					rng.randf_range(origin.x + margin, origin.x + CHUNK - margin), rng.randf_range(tops.x, tops.y),
					rng.randf_range(origin.z + margin, origin.z + CHUNK - margin))
			var island := _make_island(rng, "%d,%d,%d" % [chunk.x, chunk.y, i], at, radius, trees, "")
			if lucky and _plain_island_fits(island, islands):
				islands.append(island)
	for entry in landmarks + wrecks:
		if chunk_of(entry["at"]) == chunk:
			islands.append(entry["island"])
	return islands


## Where storm cell index is at time seconds: on its orbit, at y 0.
func storm_center(index: int, time: float) -> Vector3:
	var storm := storms[index]
	var angle: float = storm["angle"] + storm["spin"] * time
	return Vector3(cos(angle), 0.0, sin(angle)) * storm["orbit"]


## Whether a disc of radius at `at` (y ignored) overlaps any town's dock area or
## island, each with its keep-out margin.
func in_town_exclusion(at: Vector3, radius: float) -> bool:
	var flat := Vector2(at.x, at.z)
	for i in towns.size():
		var rect := _town_rects[i]
		var nearest := Vector2(clampf(flat.x, rect.position.x, rect.end.x), clampf(flat.y, rect.position.y, rect.end.y))
		if nearest.distance_to(flat) < radius:
			return true
		var island: Dictionary = towns[i]["island"]
		if _flat(at, island["at"]) < radius + island["radius"] + EXCLUSION_ISLAND:
			return true
	return false


## A town's name: two parts joined ("Gullhaven"), redrawn until no town has it.
func name_town(rng: RandomNumberGenerator) -> String:
	while true:
		var town_name: String = TOWN_NAME_START[rng.randi_range(0, TOWN_NAME_START.size() - 1)] + TOWN_NAME_END[rng.randi_range(0, TOWN_NAME_END.size() - 1)]
		var taken := false
		for town in towns:
			taken = taken or town["name"] == town_name
		if not taken:
			return town_name
	return ""


func _rng(purpose: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, purpose])
	return rng


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _inside_disc(at: Vector3, radius: float) -> bool:
	return Vector2(at.x, at.z).length() + radius <= RADIUS


## Whether at is at least distance (horizontally) from every entry's `key` point.
static func _far_from(at: Vector3, distance: float, entries: Array[Dictionary], key: String) -> bool:
	for entry in entries:
		if _flat(at, entry[key]) < distance:
			return false
	return true


## Throws up to DARTS darts into a region's ring (uniform by area, EDGE inside its
## edges) at altitudes alt and radii radii, and returns {"at", "radius"} for the
## first one fits(at, radius) accepts, or {} when none does.
func _dart(rng: RandomNumberGenerator, region: int, alt: Vector2, radii: Vector2, fits: Callable) -> Dictionary:
	var inner: float = 0.0 if region == Region.EYE else REGION_OUTER[region - 1] + EDGE
	var outer: float = REGION_OUTER[region] - EDGE
	for _dart_number in DARTS:
		var distance := sqrt(lerpf(inner * inner, outer * outer, rng.randf()))
		var angle := rng.randf() * TAU
		var at := Vector3(cos(angle) * distance, rng.randf_range(alt.x, alt.y), sin(angle) * distance)
		var radius := rng.randf_range(radii.x, radii.y)
		if fits.call(at, radius):
			return {"at": at, "radius": radius}
	return {}


## An island's depth, trees, waterfall and seed, drawn in that order.
func _make_island(rng: RandomNumberGenerator, id: String, at: Vector3, radius: float, trees: Vector2, site: String) -> Dictionary:
	var depth := radius * rng.randf_range(1.0, 1.6)
	var tree_cover := rng.randf_range(trees.x, trees.y)
	var waterfall_roll := rng.randf() < 0.35
	return {"id": id, "at": at, "radius": radius, "depth": depth, "seed": rng.randi(), "trees": tree_cover,
			"waterfall": radius >= 35.0 and waterfall_roll, "flat": false, "site": site}


func _plain_island_fits(island: Dictionary, earlier: Array[Dictionary]) -> bool:
	var at: Vector3 = island["at"]
	var radius: float = island["radius"]
	if not _inside_disc(at, radius) or in_town_exclusion(at, radius):
		return false
	for other in earlier:
		if other["site"] != "":
			continue
		var reach: float = radius + other["radius"]
		if _flat(at, other["at"]) - reach < 20.0 and absf(at.y - other["at"].y) < reach * 1.3:
			return false
	for site in landmarks + wrecks:
		var other: Dictionary = site["island"]
		if _flat(at, other["at"]) < radius + other["radius"] + SITE_GAP:
			return false
	return true


func _make_towns() -> void:
	var rng := _rng("towns")
	_add_town(rng, START, Region.CALM)
	for step: Array in TOWN_PLAN:
		for _n in step[1] as int:
			var spot := _dart(rng, step[0], Vector2(500.0, 1300.0), Vector2(TOWN_RADIUS, TOWN_RADIUS), _town_fits)
			if not spot.is_empty():
				_add_town(rng, spot["at"], step[0])


func _town_fits(dock: Vector3, _radius: float) -> bool:
	return _far_from(dock, TOWN_SPACING, towns, "dock") and _inside_disc(dock + TOWN_ISLAND, TOWN_RADIUS)


func _add_town(rng: RandomNumberGenerator, dock: Vector3, region: int) -> void:
	var town_name := name_town(rng)
	var town_seed := rng.randi()
	var island := {"id": "town-%d" % towns.size(), "at": dock + TOWN_ISLAND, "radius": TOWN_RADIUS, "depth": TOWN_RADIUS * 1.3,
			"seed": rng.randi(), "trees": 0.25, "waterfall": true, "flat": true, "site": ""}
	towns.append({"name": town_name, "dock": dock, "region": region, "seed": town_seed, "island": island})
	var area := Dock.area(dock).grow(EXCLUSION_DOCK)
	_town_rects.append(Rect2(Vector2(area.position.x, area.position.z), Vector2(area.size.x, area.size.z)))


func _make_landmarks() -> void:
	var rng := _rng("landmarks")
	for step: Array in LANDMARK_PLAN:
		for _n in step[1] as int:
			var spot := _dart(rng, step[0], Vector2(450.0, 1400.0), Vector2(40.0, 70.0), _landmark_fits)
			if spot.is_empty():
				continue
			var i := landmarks.size()
			var at: Vector3 = spot["at"]
			var kind := i % LANDMARK_KINDS.size()
			landmarks.append({"name": LANDMARK_NAMES[i] + LANDMARK_SUFFIXES[kind], "kind": LANDMARK_KINDS[kind], "at": at,
					"region": step[0], "seed": rng.randi(),
					"island": _make_island(rng, "landmark-%d" % i, at, spot["radius"], Vector2(0.2, 1.0), "landmark")})


func _landmark_fits(at: Vector3, radius: float) -> bool:
	return _inside_disc(at, radius) and not in_town_exclusion(at, radius) \
			and _far_from(at, 800.0, towns, "dock") and _far_from(at, 800.0, landmarks, "at")


func _make_wrecks() -> void:
	var rng := _rng("wrecks")
	for step: Array in WRECK_PLAN:
		for _n in step[1] as int:
			var spot := _dart(rng, step[0], Vector2(350.0, 1500.0), Vector2(25.0, 45.0), _wreck_fits)
			if spot.is_empty():
				continue
			var at: Vector3 = spot["at"]
			var wreck_seed := rng.randi()
			var yaw := rng.randf() * TAU
			var roll := rng.randf_range(0.15, 0.45)
			wrecks.append({"at": at, "region": step[0], "seed": wreck_seed, "yaw": yaw, "roll": roll,
					"island": _make_island(rng, "wreck-%d" % wrecks.size(), at, spot["radius"], Vector2(0.2, 1.0), "wreck")})


func _wreck_fits(at: Vector3, radius: float) -> bool:
	return _inside_disc(at, radius) and not in_town_exclusion(at, radius) and _far_from(at, 300.0, towns, "dock") \
			and _far_from(at, 300.0, landmarks, "at") and _far_from(at, 300.0, wrecks, "at")


func _make_rivers() -> void:
	var rng := _rng("rivers")
	for _n in rng.randi_range(6, 10):
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(2500.0, 7500.0)
		var direction := 1.0 if rng.randf() < 0.5 else -1.0
		var altitude := rng.randf_range(600.0, 1400.0)
		var phase := rng.randf() * TAU
		var width := rng.randf_range(60.0, 120.0)
		var speed := rng.randf_range(20.0, 35.0)
		var points := PackedVector3Array()
		for k in 20:
			if k > 0:
				angle += direction * 450.0 / distance
				distance = clampf(distance + rng.randf_range(-150.0, 150.0), 1000.0, 7900.0)
			points.append(Vector3(cos(angle) * distance, altitude + 250.0 * sin(k * 0.5 + phase), sin(angle) * distance))
		var box := AABB(points[0], Vector3.ZERO)
		for point in points:
			box = box.expand(point)
		rivers.append({"points": points, "width": width, "speed": speed, "box": box.grow(2.0 * width)})


func _make_storms() -> void:
	var rng := _rng("storms")
	for _n in rng.randi_range(6, 10):
		var orbit := rng.randf_range(2400.0, 3800.0)
		storms.append({"orbit": orbit, "angle": rng.randf() * TAU, "spin": -Wind.prevailing_speed(orbit) / orbit,
				"radius": rng.randf_range(150.0, 400.0)})
