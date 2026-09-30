class_name IslandMesh
extends RefCounted
## A floating island's shape, worked out from its description (see WorldGen for the
## dictionary): a grassy top with hills, a rocky underside that narrows to a point,
## tree spots and an optional waterfall. Everything is in the island's own space,
## with the origin at the middle of its top. All static and free of nodes, so it's
## safe on worker threads; it never changes the island it's given.

## Angles, rings on the top and rings on the underside for each level of detail.
const LODS := [[32, 6, 8], [16, 3, 4], [8, 1, 2]]
## Where each level of detail stops being drawn, in m (the next starts there).
const LOD_END := [800.0, 1800.0, 3000.0]

const GRASS := Color("6e8d4c")
const TOWN_GRASS := Color("7f9a5a")
const EARTH := Color("7b6146")
const ROCK_TOP := Color("6b5a50")
const ROCK_BOTTOM := Color("534740")
const ROCK_TIP := Color("3b322d")

const MAX_TREES := 120
const TREE_GAP := 5.0  ## m between trunks.


## The outline's distance from the centre at angle: 0.85 to 1.0 of the radius, or
## 0.93 to 1.0 for a flat island.
static func rim(island: Dictionary, angle: float) -> float:
	return _rim(_noise(island), island, angle)


## The top's height above the island's centre at local (x, z): nothing on a flat
## island, else hills of up to 0.08 of the radius that fall away to nothing at the rim.
static func height(island: Dictionary, x: float, z: float) -> float:
	if island["flat"]:
		return 0.0
	var noise := _noise(island)
	var t := minf(Vector2(x, z).length() / _rim(noise, island, atan2(z, x)), 1.0)
	return _hill(island, _hill_noise(noise, x, z), t)


## The triangles of a level of detail as {"vertices", "normals", "colors"}: three
## vertices to a triangle, each triangle with one normal and one colour. Triangles
## wind clockwise seen from outside, the side Godot draws, and each normal comes
## from that winding.
static func arrays(island: Dictionary, lod: int) -> Dictionary:
	var noise := _noise(island)
	var setup: Array = LODS[lod]
	var angles: int = setup[0]
	var rings: int = setup[1]
	var under: int = setup[2]
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()

	# The top: ring 0 is the centre, ring `rings` the rim. Each vertex's noise, made
	# once, gives both its height and how light its grass is.
	var edge := PackedFloat32Array()
	for k in angles:
		edge.append(_rim(noise, island, TAU * k / angles))
	var top: Array[PackedVector3Array] = []
	var tints: Array[PackedFloat32Array] = []
	for j in rings + 1:
		var ring := PackedVector3Array()
		var tint := PackedFloat32Array()
		for k in 1 if j == 0 else angles:
			var a := TAU * k / angles
			var d: float = 0.0 if j == 0 else edge[k] * j / rings
			var x := cos(a) * d
			var z := sin(a) * d
			var n := _hill_noise(noise, x, z)
			ring.append(Vector3(x, _hill(island, n, float(j) / rings), z))
			tint.append(n)
		top.append(ring)
		tints.append(tint)
	for j in range(1, rings + 1):
		var rim_band: bool = j == rings and rings > 1 and not island["flat"]
		for k in angles:
			var k1 := (k + 1) % angles
			var inner := top[j - 1]
			var outer := top[j]
			if j == 1:
				_top_triangle(vertices, colors, island, rim_band, [inner[0], outer[k], outer[k1]], [tints[0][0], tints[1][k], tints[1][k1]])
			else:
				var ti := tints[j - 1]
				var to := tints[j]
				_top_triangle(vertices, colors, island, rim_band, [inner[k], outer[k], outer[k1]], [ti[k], to[k], to[k1]])
				_top_triangle(vertices, colors, island, rim_band, [inner[k], outer[k1], inner[k1]], [ti[k], to[k1], ti[k1]])

	# The underside: ring 0 is the rim itself (the very same points), the last ring
	# the tip. The rings between shrink and are pushed in or out by noise.
	var depth: float = island["depth"]
	var below: Array[PackedVector3Array] = [top[rings]]
	for j in range(1, under):
		var shrink := pow(1.0 - float(j) / under, 0.8)
		var ring := PackedVector3Array()
		for k in angles:
			var rim_point := top[rings][k]
			var y := -depth * j / under
			var p := Vector3(rim_point.x * shrink, y, rim_point.z * shrink)
			var push := 1.0 + 0.12 * clampf(noise.get_noise_3d(p.x * 3.0, y * 3.0, p.z * 3.0), -1.0, 1.0)
			ring.append(Vector3(p.x * push, y, p.z * push))
		below.append(ring)
	var tip := Vector3(0.0, -depth, 0.0)
	for j in under - 1:
		var color := ROCK_TOP.lerp(ROCK_BOTTOM, (j + 0.5) / maxf(under - 1.0, 1.0))
		for k in angles:
			var k1 := (k + 1) % angles
			var upper := below[j]
			var lower := below[j + 1]
			_triangle(vertices, colors, upper[k], lower[k], lower[k1], color)
			_triangle(vertices, colors, upper[k], lower[k1], upper[k1], color)
	for k in angles:
		_triangle(vertices, colors, tip, below[under - 1][(k + 1) % angles], below[under - 1][k], ROCK_TIP)
	var normals := PackedVector3Array()
	for t in vertices.size() / 3:
		var normal := (vertices[t * 3 + 2] - vertices[t * 3]).cross(vertices[t * 3 + 1] - vertices[t * 3]).normalized()
		normals.append_array(PackedVector3Array([normal, normal, normal]))
	return {"vertices": vertices, "normals": normals, "colors": colors}


## The faces to collide with: the finest level of detail's triangles.
static func collision_faces(island: Dictionary) -> PackedVector3Array:
	return arrays(island, 0)["vertices"]


## Where trees stand: as many as the island's cover asks for (at most 120), inside
## 0.8 of the rim and 5 m apart, each on the top, turned and scaled 0.7 to 1.4.
static func trees(island: Dictionary) -> Array[Transform3D]:
	var found: Array[Transform3D] = []
	var noise := _noise(island)
	var radius: float = island["radius"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([island["seed"], "trees"])
	var wanted := mini(roundi(island["trees"] * radius * radius / 180.0), MAX_TREES)
	var spots: Array[Vector2] = []
	var tries := 0
	while spots.size() < wanted and tries < wanted * 20:
		tries += 1
		var a := rng.randf() * TAU
		var t := 0.8 * sqrt(rng.randf())
		var d := t * _rim(noise, island, a)
		var spot := Vector2(cos(a), sin(a)) * d
		var yaw := rng.randf() * TAU
		var size := rng.randf_range(0.7, 1.4)
		var crowded := false
		for other in spots:
			crowded = crowded or other.distance_squared_to(spot) < TREE_GAP * TREE_GAP
		if not crowded:
			spots.append(spot)
			var y := _hill(island, _hill_noise(noise, spot.x, spot.y), t) if not island["flat"] else 0.0
			found.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), Vector3(spot.x, y, spot.y)))
	return found


## Where water pours over the rim, as {"from": a point on the rim, "out": the
## horizontal way away from the centre, "width", "drop"}, or {} for none.
static func waterfall(island: Dictionary) -> Dictionary:
	if not island["waterfall"]:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([island["seed"], "waterfall"])
	var angle := rng.randf() * TAU
	var out := Vector3(cos(angle), 0.0, sin(angle))
	var from := out * rim(island, angle)
	from.y = height(island, from.x, from.z)
	return {"from": from, "out": out, "width": rng.randf_range(4.0, 8.0), "drop": float(island["depth"]) + 150.0}


static func _noise(island: Dictionary) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = island["seed"]
	noise.frequency = 1.0 / float(island["radius"])
	return noise


## The outline samples a circle of radius 2 in the noise's own units, so it comes
## back to where it started.
static func _rim(noise: FastNoiseLite, island: Dictionary, angle: float) -> float:
	var radius: float = island["radius"]
	var n := noise.get_noise_2d(cos(angle) * 2.0 * radius, sin(angle) * 2.0 * radius)
	return radius * lerpf(0.93 if island["flat"] else 0.85, 1.0, clampf(0.5 + 0.7 * n, 0.0, 1.0))


## The noise behind the hills and the grass tint: half the noise's own frequency, so
## the hills are broad enough for the mesh's triangles to follow.
static func _hill_noise(noise: FastNoiseLite, x: float, z: float) -> float:
	return noise.get_noise_2d(x * 0.5, z * 0.5)


## The top's height from the noise n at a point t of the way to the rim.
static func _hill(island: Dictionary, n: float, t: float) -> float:
	if island["flat"]:
		return 0.0
	return 0.08 * float(island["radius"]) * clampf(0.5 + 0.5 * n, 0.0, 1.0) * (1.0 - t * t)


## A top triangle (clockwise from above), coloured by the average noise of its corners.
static func _top_triangle(vertices: PackedVector3Array, colors: PackedColorArray, island: Dictionary, on_rim: bool, corners: Array, noises: Array) -> void:
	var color := TOWN_GRASS
	if not island["flat"]:
		var n: float = (noises[0] + noises[1] + noises[2]) / 3.0
		color = EARTH if on_rim else GRASS * (1.0 + 0.08 * clampf(n, -1.0, 1.0))
		color.a = 1.0
	_triangle(vertices, colors, corners[0], corners[1], corners[2], color)


## Adds one flat-coloured triangle.
static func _triangle(vertices: PackedVector3Array, colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	vertices.append_array(PackedVector3Array([a, b, c]))
	colors.append_array(PackedColorArray([color, color, color]))
