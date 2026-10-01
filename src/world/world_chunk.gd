class_name WorldChunk
extends RefCounted
## One 256 m chunk of the world (spec §4.7). generate() works out its arrays on a
## worker thread; build() turns them into nodes on the main thread: a merged mesh
## for each level of detail, the trees, the waterfalls and one collision body.
## Everything in a chunk is placed relative to its origin (WorldGen.chunk_origin).

const TREES_END := 1200.0  ## m: trees stop being drawn.
const FALLS_END := 1800.0  ## m: waterfalls likewise.
const LOD_MARGIN := 20.0   ## m either side of a level's range where it fades over.
const CLOUDS_END := 3000.0 ## m: clouds stop being drawn.
const CLOUD_CLUSTERS := [Vector2i(0, 0), Vector2i(4, 6), Vector2i(1, 3), Vector2i(0, 2), Vector2i(0, 1), Vector2i(0, 0)]  ## Per region (Region's order): the fewest and most clusters in a chunk.
const FALL_OUT := 1.0      ## m the water starts outside the rim, so it never hides in the rock.

const TRUNK := Color("5a4230")
const LEAVES := Color("3f6b35")
const LEAVES_TOP := Color("4d7d3e")

const WATER_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_never;

void fragment() {
	float streak = 0.5 + 0.5 * sin(UV.x * 37.0 + 3.0 * sin(UV.x * 11.0));
	float flow = fract(UV.y * 5.0 - TIME * 1.2 + 0.4 * streak);
	ALBEDO = mix(vec3(0.72, 0.85, 1.0), vec3(1.0), smoothstep(0.55, 1.0, flow) * streak);
	ROUGHNESS = 0.3;
	ALPHA = 0.8 * (1.0 - UV.y) * (0.55 + 0.45 * streak);
}
"""

static var _ground: StandardMaterial3D
static var _tree: ArrayMesh
static var _water: ShaderMaterial
static var _fall_quad: QuadMesh
static var _puff: ArrayMesh
static var _cloud: StandardMaterial3D


## A chunk's arrays, safe to make on any thread: {"chunk", "islands", "faces", "wrecks",
## "landmarks"} (the sites in the chunk) and, with visuals, "lods" (per level
## {"vertices", "normals", "colors"}), "trees" (a MultiMesh transform buffer) and
## "falls" (IslandMesh.waterfall dictionaries) and "clouds" (clouds()' puffs).
static func generate(gen: WorldGen, chunk: Vector2i, visuals: bool) -> Dictionary:
	var islands := gen.islands_in(chunk)
	var data := arrays_of(islands, WorldGen.chunk_origin(chunk), visuals)
	data.merge({"chunk": chunk, "islands": islands, "wrecks": _in_chunk(gen.wrecks, chunk), "landmarks": _in_chunk(gen.landmarks, chunk)})
	if visuals:
		data["clouds"] = clouds(gen, chunk)
	return data


## The cloud puffs of a chunk, in its own space, from a seed of the chunk's own. Clusters
## of 5 to 12 puffs, each 20 to 60 m wide and 0.5 to 0.7 of that high,
## spread 80 m around a point 900 to 2,200 m up. The Stormwall has the most clusters
## and the Eye none. Safe on any thread.
static func clouds(gen: WorldGen, chunk: Vector2i) -> Array[Transform3D]:
	var puffs: Array[Transform3D] = []
	var origin := WorldGen.chunk_origin(chunk)
	var counts: Vector2i = CLOUD_CLUSTERS[WorldGen.region_at(origin + Vector3(WorldGen.CHUNK / 2.0, 0.0, WorldGen.CHUNK / 2.0))]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([gen.world_seed, chunk.x, chunk.y, "clouds"])
	for _cluster in rng.randi_range(counts.x, counts.y):
		var middle := Vector3(rng.randf() * WorldGen.CHUNK, rng.randf_range(900.0, 2200.0), rng.randf() * WorldGen.CHUNK)
		for _puff_number in rng.randi_range(5, 12):
			var width := rng.randf_range(20.0, 60.0)
			var scale := Vector3(width, width * rng.randf_range(0.5, 0.7), width)
			var at := middle + Vector3(rng.randf_range(-80.0, 80.0), rng.randf_range(-30.0, 30.0), rng.randf_range(-80.0, 80.0))
			puffs.append(Transform3D(Basis.from_scale(scale).rotated(Vector3.UP, rng.randf() * TAU), at))
	return puffs


## The nodes for one island on its own, at its place in the world with its own
## space: what build() makes of a chunk, for the town islands.
static func island_node(island: Dictionary, visuals: bool) -> Node3D:
	var node := Node3D.new()
	node.name = "Island"
	node.position = island["at"]
	fill(node, arrays_of([island], island["at"], visuals))
	return node


## The arrays of islands, in the space whose origin is origin: {"faces"} and, with
## visuals, "lods", "trees" and "falls" as generate() describes them.
static func arrays_of(islands: Array[Dictionary], origin: Vector3, visuals: bool) -> Dictionary:
	var faces := PackedVector3Array()
	var lods: Array[Dictionary] = []
	for lod in IslandMesh.LODS.size():
		lods.append({"vertices": PackedVector3Array(), "normals": PackedVector3Array(), "colors": PackedColorArray()})
	var trees := PackedFloat32Array()
	var falls: Array[Dictionary] = []
	for island in islands:
		var offset: Vector3 = island["at"] - origin
		var finest := IslandMesh.arrays(island, 0)
		faces.append_array(_moved(finest["vertices"], offset))
		if not visuals:
			continue
		for lod in lods.size():
			var arrays := finest if lod == 0 else IslandMesh.arrays(island, lod)
			lods[lod]["vertices"].append_array(_moved(arrays["vertices"], offset))
			lods[lod]["normals"].append_array(arrays["normals"])
			lods[lod]["colors"].append_array(arrays["colors"])
		for tree in IslandMesh.trees(island):
			var b := tree.basis
			var o := tree.origin + offset
			trees.append_array(PackedFloat32Array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z]))
		var fall := IslandMesh.waterfall(island)
		if not fall.is_empty():
			fall["from"] += offset
			falls.append(fall)
	var data := {"faces": faces}
	if visuals:
		data.merge({"lods": lods, "trees": trees, "falls": falls})
	return data


## The chunk's nodes from generate()'s arrays, on the main thread: the islands, and
## any wreck or landmark standing on them. A chunk with no islands is an empty Node3D.
static func build(data: Dictionary) -> Node3D:
	var chunk: Vector2i = data["chunk"]
	var origin := WorldGen.chunk_origin(chunk)
	var node := Node3D.new()
	node.name = "Chunk%d_%d" % [chunk.x, chunk.y]
	node.position = origin
	fill(node, data)
	var visuals := data.has("lods")
	if data.has("clouds") and not (data["clouds"] as Array).is_empty():
		node.add_child(_cloud_node(data["clouds"]))
	var sites: Array[Node3D] = []
	for wreck: Dictionary in data["wrecks"]:
		sites.append(Sites.create_wreck(wreck, visuals))
	for landmark: Dictionary in data["landmarks"]:
		sites.append(Sites.create_landmark(landmark, visuals))
	for site in sites:
		site.position -= origin  # they're made in the world's space
		node.add_child(site)
	return node


static func _cloud_node(puffs: Array[Transform3D]) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = puff_mesh()
	multimesh.instance_count = puffs.size()
	for i in puffs.size():
		multimesh.set_instance_transform(i, puffs[i])
	var node := MultiMeshInstance3D.new()
	node.name = "Clouds"
	node.multimesh = multimesh
	node.visibility_range_end = CLOUDS_END
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Adds the collision body for arrays_of's faces to node, and with its visuals the
## levels of detail, trees and waterfalls.
static func fill(node: Node3D, data: Dictionary) -> void:
	var faces: PackedVector3Array = data["faces"]
	if faces.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = false
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	var body := StaticBody3D.new()
	body.add_child(collision)
	node.add_child(body)
	if not data.has("lods"):
		return

	var lods: Array[Dictionary] = data["lods"]
	for lod in lods.size():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = lods[lod]["vertices"]
		arrays[Mesh.ARRAY_NORMAL] = lods[lod]["normals"]
		arrays[Mesh.ARRAY_COLOR] = lods[lod]["colors"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, ground_material())
		var instance := MeshInstance3D.new()
		instance.name = "Lod%d" % lod
		instance.mesh = mesh
		instance.visibility_range_begin = 0.0 if lod == 0 else IslandMesh.LOD_END[lod - 1]
		instance.visibility_range_end = IslandMesh.LOD_END[lod]
		instance.visibility_range_begin_margin = LOD_MARGIN
		instance.visibility_range_end_margin = LOD_MARGIN
		node.add_child(instance)

	var trees: PackedFloat32Array = data["trees"]
	if not trees.is_empty():
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = tree_mesh()
		multimesh.instance_count = trees.size() / 12
		multimesh.buffer = trees
		var forest := MultiMeshInstance3D.new()
		forest.name = "Trees"
		forest.multimesh = multimesh
		forest.visibility_range_end = TREES_END
		node.add_child(forest)

	for fall: Dictionary in data["falls"]:
		var out: Vector3 = fall["out"]
		var drop: float = fall["drop"]
		var top: Vector3 = fall["from"] + out * FALL_OUT
		var water := MeshInstance3D.new()
		water.name = "Waterfall"
		water.mesh = _quad()
		water.material_override = water_material()
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The unit quad faces out from the island, stretched to the fall's width and drop.
		var basis := Basis(Vector3.UP.cross(out) * float(fall["width"]), Vector3.UP * drop, out)
		water.transform = Transform3D(basis, top - Vector3(0.0, drop / 2.0, 0.0))
		water.visibility_range_end = FALLS_END
		node.add_child(water)


## The islands' material: their vertex colours, matte.
static func ground_material() -> StandardMaterial3D:
	if _ground == null:
		_ground = StandardMaterial3D.new()
		_ground.vertex_color_use_as_albedo = true
		_ground.roughness = 1.0
	return _ground


## A small low-poly tree, 8 m tall at scale 1: a five-sided trunk and two cones of
## leaves, vertex coloured.
static func tree_mesh() -> ArrayMesh:
	if _tree == null:
		var vertices := PackedVector3Array()
		var colors := PackedColorArray()
		cone(vertices, colors, 0.0, 2.6, 0.3, 0.22, 5, TRUNK)
		cone(vertices, colors, 1.8, 5.8, 2.2, 0.0, 6, LEAVES)
		cone(vertices, colors, 4.2, 8.0, 1.5, 0.0, 6, LEAVES_TOP)
		_tree = flat_mesh(vertices, colors)
	return _tree


## A low-poly cloud puff, one metre across: an icosahedron cut once (80 triangles),
## flat shaded, made once.
static func puff_mesh() -> ArrayMesh:
	if _puff == null:
		var t := (1.0 + sqrt(5.0)) / 2.0
		var corners: Array[Vector3] = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
				Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
				Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
		var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
				[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		for face: Array in faces:
			var a: Vector3 = corners[face[0]].normalized() * 0.5
			var b: Vector3 = corners[face[1]].normalized() * 0.5
			var c: Vector3 = corners[face[2]].normalized() * 0.5
			var ab := ((a + b) / 2.0).normalized() * 0.5
			var bc := ((b + c) / 2.0).normalized() * 0.5
			var ca := ((c + a) / 2.0).normalized() * 0.5
			for triangle: Array in [[a, ab, ca], [ab, b, bc], [ca, bc, c], [ab, bc, ca]]:
				var p: Vector3 = triangle[0]
				var q: Vector3 = triangle[1]
				var r: Vector3 = triangle[2]
				var outward := (r - p).cross(q - p)  # where p, q, r faces
				if outward.dot(p + q + r) < 0.0:
					var swap := q
					q = r
					r = swap
					outward = -outward
				vertices.append_array(PackedVector3Array([p, q, r]))
				var normal := outward.normalized()
				normals.append_array(PackedVector3Array([normal, normal, normal]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		_puff = ArrayMesh.new()
		_puff.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_puff.surface_set_material(0, cloud_material())
	return _puff


## The clouds' material: white, matte, with a little rim light; no vertex colours.
static func cloud_material() -> StandardMaterial3D:
	if _cloud == null:
		_cloud = StandardMaterial3D.new()
		_cloud.albedo_color = Color.WHITE
		_cloud.roughness = 1.0
		_cloud.rim_enabled = true
		_cloud.rim = 0.3
		_cloud.vertex_color_use_as_albedo = false
	return _cloud


## The waterfalls' material: translucent white-blue streaks pouring down, fading
## out toward the bottom, seen from both sides.
static func water_material() -> ShaderMaterial:
	if _water == null:
		var shader := Shader.new()
		shader.code = WATER_SHADER
		_water = ShaderMaterial.new()
		_water.shader = shader
	return _water


static func _quad() -> QuadMesh:
	if _fall_quad == null:
		_fall_quad = QuadMesh.new()
	return _fall_quad


## Triangles in the islands' style (three vertices each, wound clockwise seen from
## outside) as a flat-shaded mesh with the ground material.
static func flat_mesh(vertices: PackedVector3Array, colors: PackedColorArray) -> ArrayMesh:
	var normals := PackedVector3Array()
	for t in vertices.size() / 3:
		var normal := (vertices[t * 3 + 2] - vertices[t * 3]).cross(vertices[t * 3 + 1] - vertices[t * 3]).normalized()
		normals.append_array(PackedVector3Array([normal, normal, normal]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, ground_material())
	return mesh


## Adds a box, size across and its centre at where's origin, as triangles.
static func add_box(vertices: PackedVector3Array, colors: PackedColorArray, where: Transform3D, size: Vector3, color: Color) -> void:
	var h := size / 2.0
	var corners: Array[Vector3] = []
	for i in 8:
		corners.append(where * Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	for face: Array in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 2, 6, 4], [1, 5, 7, 3], [0, 4, 5, 1], [2, 3, 7, 6]]:
		_convex_quad(vertices, colors, [corners[face[0]], corners[face[1]], corners[face[2]], corners[face[3]]], where.origin, color)


## Adds a gable roof standing on where's origin: size.x by size.z at its foot, with a
## ridge along z at height size.y. It has no floor.
static func add_prism(vertices: PackedVector3Array, colors: PackedColorArray, where: Transform3D, size: Vector3, color: Color) -> void:
	var hx := size.x / 2.0
	var hz := size.z / 2.0
	var a := where * Vector3(-hx, 0.0, -hz)
	var b := where * Vector3(hx, 0.0, -hz)
	var c := where * Vector3(hx, 0.0, hz)
	var d := where * Vector3(-hx, 0.0, hz)
	var ridge_front := where * Vector3(0.0, size.y, -hz)
	var ridge_back := where * Vector3(0.0, size.y, hz)
	var inside := where * Vector3(0.0, size.y / 3.0, 0.0)
	_convex_quad(vertices, colors, [a, d, ridge_back, ridge_front], inside, color)
	_convex_quad(vertices, colors, [b, c, ridge_back, ridge_front], inside, color)
	_convex_triangle(vertices, colors, a, b, ridge_front, inside, color)
	_convex_triangle(vertices, colors, d, c, ridge_back, inside, color)


## points, each moved by offset.
static func _moved(points: PackedVector3Array, offset: Vector3) -> PackedVector3Array:
	var moved := PackedVector3Array()
	moved.resize(points.size())
	for i in points.size():
		moved[i] = points[i] + offset
	return moved


## A triangle of a convex shape around inside, wound to face away from it.
static func _convex_triangle(vertices: PackedVector3Array, colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, inside: Vector3, color: Color) -> void:
	var facing := (c - a).cross(b - a)  # where the winding a, b, c faces
	if facing.dot(a - inside) < 0.0:
		vertices.append_array(PackedVector3Array([a, c, b]))
	else:
		vertices.append_array(PackedVector3Array([a, b, c]))
	colors.append_array(PackedColorArray([color, color, color]))


static func _convex_quad(vertices: PackedVector3Array, colors: PackedColorArray, corners: Array, inside: Vector3, color: Color) -> void:
	_convex_triangle(vertices, colors, corners[0], corners[1], corners[2], inside, color)
	_convex_triangle(vertices, colors, corners[0], corners[2], corners[3], inside, color)


## A capped frustum (a cone when top_radius is 0) around the y axis, flat shaded,
## wound clockwise seen from outside as IslandMesh's triangles are.
static func cone(vertices: PackedVector3Array, colors: PackedColorArray, bottom: float, top: float,
		bottom_radius: float, top_radius: float, sides: int, color: Color) -> void:
	var lower := PackedVector3Array()
	var upper := PackedVector3Array()
	for k in sides:
		var a := TAU * k / sides
		lower.append(Vector3(cos(a) * bottom_radius, bottom, sin(a) * bottom_radius))
		upper.append(Vector3(cos(a) * top_radius, top, sin(a) * top_radius))
	var apex := Vector3(0.0, top, 0.0)
	var base := Vector3(0.0, bottom, 0.0)
	for k in sides:
		var k1 := (k + 1) % sides
		var corners := [upper[k], lower[k], lower[k1]]
		if top_radius > 0.0:
			corners.append_array([upper[k], lower[k1], upper[k1], apex, upper[k], upper[k1]])
		else:
			corners[0] = apex
		corners.append_array([base, lower[k1], lower[k]])
		for corner: Vector3 in corners:
			vertices.append(corner)
			colors.append(color)


## The entries (wrecks or landmarks) whose place is in chunk.
static func _in_chunk(entries: Array[Dictionary], chunk: Vector2i) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry in entries:
		if WorldGen.chunk_of(entry["at"]) == chunk:
			found.append(entry)
	return found
