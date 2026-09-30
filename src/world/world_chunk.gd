class_name WorldChunk
extends RefCounted
## One 256 m chunk of the world (spec §4.7). generate() works out its arrays on a
## worker thread; build() turns them into nodes on the main thread: a merged mesh
## for each level of detail, the trees, the waterfalls and one collision body.
## Everything in a chunk is placed relative to its origin (WorldGen.chunk_origin).

const TREES_END := 1200.0  ## m: trees stop being drawn.
const FALLS_END := 1800.0  ## m: waterfalls likewise.
const LOD_MARGIN := 20.0   ## m either side of a level's range where it fades over.
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


## A chunk's arrays, safe to make on any thread: {"chunk", "islands", "faces"} and,
## with visuals, "lods" (per level {"vertices", "normals", "colors"}), "trees" (a
## MultiMesh transform buffer) and "falls" (IslandMesh.waterfall dictionaries).
static func generate(gen: WorldGen, chunk: Vector2i, visuals: bool) -> Dictionary:
	var origin := WorldGen.chunk_origin(chunk)
	var islands := gen.islands_in(chunk)
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
	var data := {"chunk": chunk, "islands": islands, "faces": faces}
	if visuals:
		data.merge({"lods": lods, "trees": trees, "falls": falls})
	return data


## The chunk's nodes from generate()'s arrays, on the main thread. A chunk with no
## islands is an empty Node3D.
static func build(data: Dictionary) -> Node3D:
	var chunk: Vector2i = data["chunk"]
	var node := Node3D.new()
	node.name = "Chunk%d_%d" % [chunk.x, chunk.y]
	node.position = WorldGen.chunk_origin(chunk)
	var faces: PackedVector3Array = data["faces"]
	if faces.is_empty():
		return node
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = false
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	var body := StaticBody3D.new()
	body.add_child(collision)
	node.add_child(body)
	if not data.has("lods"):
		return node

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
	return node


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
		_cone(vertices, colors, 0.0, 2.6, 0.3, 0.22, 5, TRUNK)
		_cone(vertices, colors, 1.8, 5.8, 2.2, 0.0, 6, LEAVES)
		_cone(vertices, colors, 4.2, 8.0, 1.5, 0.0, 6, LEAVES_TOP)
		var normals := PackedVector3Array()
		for t in vertices.size() / 3:
			var normal := (vertices[t * 3 + 2] - vertices[t * 3]).cross(vertices[t * 3 + 1] - vertices[t * 3]).normalized()
			normals.append_array(PackedVector3Array([normal, normal, normal]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		_tree = ArrayMesh.new()
		_tree.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_tree.surface_set_material(0, ground_material())
	return _tree


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


## points, each moved by offset.
static func _moved(points: PackedVector3Array, offset: Vector3) -> PackedVector3Array:
	var moved := PackedVector3Array()
	moved.resize(points.size())
	for i in points.size():
		moved[i] = points[i] + offset
	return moved


## A capped frustum (a cone when top_radius is 0) around the y axis, flat shaded,
## wound clockwise seen from outside as IslandMesh's triangles are.
static func _cone(vertices: PackedVector3Array, colors: PackedColorArray, bottom: float, top: float,
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
