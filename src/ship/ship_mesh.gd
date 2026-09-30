class_name ShipMesh
## Draws a ship's blocks as one low-poly mesh with a surface per material (wood,
## metal, cloth, stone), coloured by block type or the ship's paint (spec §3.9).
## Faces between neighbouring cube blocks are left out. Propellers, rudders, sails,
## cannons, helms and ladders are drawn as shaped boxes turned the way they face,
## and the balloon cells merge into one rounded cloth envelope.
# ponytail: one mesh for the whole ship. Split it into 16³ sections (spec §4.4) when damage (stage 6) rebuilds it on every hit.

## How far an envelope corner is pulled in for each extra face that meets there.
const ROUNDING := 0.22
## Envelope cloth on every other row along the ship is this much darker: gores.
const GORE_SHADE := 0.94

const COLORS := {
	"frame": Color("8a5a3b"),
	"deck": Color("b98a5e"),
	"iron": Color("5b6068"),
	"alloy": Color("a7b1bb"),
	"balloon": Color("e9dfc9"),
	"lift_stone": Color("7fd3c5"),
	"engine": Color("3d3a3f"),
	"propeller": Color("b48a3c"),
	"rudder": Color("9b3f2f"),
	"sail": Color("f2ead8"),
	"fuel_tank": Color("6b4f2d"),
	"ballast_tank": Color("4d6b7a"),
	"helm": Color("c9a25a"),
	"cannon": Color("2f3033"),
	"cargo_bay": Color("8f7550"),
	"bunk": Color("7d5a6b"),
	"ladder": Color("c79a64"),
}

const _FACES := [
	[Vector3i(1, 0, 0), Vector3(0.5, -0.5, -0.5), Vector3(0, 1, 0), Vector3(0, 0, 1)],
	[Vector3i(-1, 0, 0), Vector3(-0.5, -0.5, 0.5), Vector3(0, 1, 0), Vector3(0, 0, -1)],
	[Vector3i(0, 1, 0), Vector3(-0.5, 0.5, -0.5), Vector3(0, 0, 1), Vector3(1, 0, 0)],
	[Vector3i(0, -1, 0), Vector3(-0.5, -0.5, 0.5), Vector3(0, 0, -1), Vector3(1, 0, 0)],
	[Vector3i(0, 0, 1), Vector3(0.5, -0.5, 0.5), Vector3(0, 1, 0), Vector3(-1, 0, 0)],
	[Vector3i(0, 0, -1), Vector3(-0.5, -0.5, -0.5), Vector3(0, 1, 0), Vector3(1, 0, 0)],
]


static func build(grid: ShipGrid) -> MeshInstance3D:
	var tools := {}
	for material: String in Blocks.MATERIALS:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[material] = st
	var envelope: Array = []  # [cell, face] of every drawn balloon face
	for cell: Vector3i in grid.blocks:
		var type: String = grid.blocks[cell]["type"]
		var st: SurfaceTool = tools[Blocks.INFO[type]["material"]]
		st.set_color(color_of(grid, type))
		if not Blocks.is_cube(type):
			_add_shaped(st, type, Vector3(cell), Blocks.basis(grid.blocks[cell]["rotation"]))
			continue
		for face: Array in _FACES:
			var neighbour := grid.type_at(cell + (face[0] as Vector3i))
			if neighbour != "" and Blocks.is_cube(neighbour):
				continue
			if type == "balloon":
				envelope.append([cell, face])
			else:
				_add_quad(st, Vector3(cell) + (face[1] as Vector3), face[2], face[3], Vector3(face[0] as Vector3i))
	_add_envelope(tools["cloth"], grid, envelope)
	var mesh := ArrayMesh.new()
	var materials: Array[StandardMaterial3D] = []
	for material: String in Blocks.MATERIALS:
		var before := mesh.get_surface_count()
		(tools[material] as SurfaceTool).commit(mesh)
		if mesh.get_surface_count() > before:
			materials.append(_material(material))
	for i in materials.size():
		mesh.surface_set_material(i, materials[i])
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	return mesh_instance


## The paint for type, or else its stock colour.
static func color_of(grid: ShipGrid, type: String) -> Color:
	return grid.paint.get(type, COLORS[type])


static func _material(kind: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	match kind:
		"wood":
			material.roughness = 0.9
		"metal":
			material.metallic = 0.7
			material.roughness = 0.45
		"cloth":
			material.roughness = 1.0
		"stone":
			material.roughness = 0.6
			material.emission_enabled = true
			material.emission = Color("7fd3c5")
			material.emission_energy_multiplier = 0.6
	return material


## The balloon faces as one rounded envelope: each corner is pulled in along the
## average of the faces that meet there, so edges bevel and corners round.
# ponytail: the envelope's inner (concave) edges are pulled in too, which creases them. Push concave corners out instead if L-shaped envelopes look wrong.
static func _add_envelope(st: SurfaceTool, grid: ShipGrid, faces: Array) -> void:
	var meeting := {}  # corner key -> distinct face normals there
	for entry: Array in faces:
		var face: Array = entry[1]
		for point in _quad_corners(Vector3(entry[0] as Vector3i) + (face[1] as Vector3), face[2], face[3]):
			var key := Vector3i((point * 2.0).round())
			var normals: Array = meeting.get_or_add(key, [])
			if not (face[0] as Vector3i) in normals:
				normals.append(face[0])
	var paint := color_of(grid, "balloon")
	for entry: Array in faces:
		var cell: Vector3i = entry[0]
		var face: Array = entry[1]
		var c := Vector3(cell) + (face[1] as Vector3)
		var u: Vector3 = face[2]
		var v: Vector3 = face[3]
		st.set_color(paint * GORE_SHADE if posmod(cell.z, 2) == 1 else paint)
		for point: Vector3 in [c, c + u + v, c + u, c, c + v, c + u + v]:
			var normals: Array = meeting[Vector3i((point * 2.0).round())]
			var sum := Vector3.ZERO
			for n: Vector3i in normals:
				sum += Vector3(n)
			var normal := sum.normalized()
			st.set_normal(normal)
			st.add_vertex(point - normal * ROUNDING * (normals.size() - 1))


static func _quad_corners(corner: Vector3, u: Vector3, v: Vector3) -> Array[Vector3]:
	return [corner, corner + u, corner + v, corner + u + v]


## A quad from corner along edges u and v (a right-handed pair around normal). Its
## triangles run clockwise seen from outside, the side Godot draws.
static func _add_quad(st: SurfaceTool, corner: Vector3, u: Vector3, v: Vector3, normal: Vector3) -> void:
	st.set_normal(normal)
	for point in [corner, corner + u + v, corner + u, corner, corner + v, corner + u + v]:
		st.add_vertex(point)


## A box of size around center, turned by basis about the block's own centre at
## block_center: center is in the block's own space.
static func _add_box(st: SurfaceTool, block_center: Vector3, center: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	for face: Array in _FACES:
		_add_quad(st, block_center + basis * (center + (face[1] as Vector3) * size), basis * ((face[2] as Vector3) * size), basis * ((face[3] as Vector3) * size), basis * Vector3(face[0] as Vector3i))


## A shaped block (forward is -Z, up is +Y) as boxes, turned by b.
static func _add_shaped(st: SurfaceTool, type: String, at: Vector3, b: Basis) -> void:
	var boxes: Array = []  # [center, size]
	match type:
		"propeller":
			boxes = [[Vector3(0, 0, 0.15), Vector3(0.3, 0.3, 0.5)], [Vector3(0, 0, -0.2), Vector3(1.0, 0.16, 0.06)], [Vector3(0, 0, -0.2), Vector3(0.16, 1.0, 0.06)]]
		"rudder":
			boxes = [[Vector3.ZERO, Vector3(0.16, 1.0, 1.0)]]
		"sail":
			boxes = [[Vector3.ZERO, Vector3(1.0, 1.0, 0.08)]]
		"cannon":
			boxes = [[Vector3(0, -0.3, 0.05), Vector3(0.8, 0.35, 0.8)], [Vector3(0, 0.05, -0.25), Vector3(0.3, 0.3, 1.0)]]
		"helm":
			boxes = [[Vector3(0, -0.05, 0.2), Vector3(0.2, 0.9, 0.2)], [Vector3(0, 0.2, 0.05), Vector3(0.9, 0.08, 0.08)], [Vector3(0, 0.2, 0.05), Vector3(0.08, 0.9, 0.08)]]
			for y in [0.62, -0.22]:
				boxes.append([Vector3(0, y, 0.05), Vector3(0.9, 0.08, 0.08)])
			for x in [0.42, -0.42]:
				boxes.append([Vector3(x, 0.2, 0.05), Vector3(0.08, 0.9, 0.08)])
		"ladder":
			for x in [-0.4, 0.4]:
				boxes.append([Vector3(x, 0, 0), Vector3(0.08, 1.0, 0.08)])
			for y in [-0.3, 0.0, 0.3]:
				boxes.append([Vector3(0, y, 0), Vector3(0.8, 0.06, 0.06)])
	for box: Array in boxes:
		_add_box(st, at, box[0], box[1], b)
