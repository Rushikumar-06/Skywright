class_name ShipMesh
## Draws a ship's blocks as one low-poly mesh coloured by block type (spec §3.9).
## Faces between neighbouring solid blocks are left out, and ladders are drawn as
## rails and rungs so they read as something you can walk into.
# ponytail: one mesh for the whole ship. Split it into 16³ sections (spec §4.4) when damage (stage 6) rebuilds it on every hit.

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
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell: Vector3i in grid.blocks:
		var type: String = grid.blocks[cell]["type"]
		if type == "ladder":
			_add_ladder(st, Vector3(cell))
			continue
		st.set_color(COLORS[type])
		for face: Array in _FACES:
			var neighbour := grid.type_at(cell + (face[0] as Vector3i))
			if neighbour != "" and neighbour != "ladder":
				continue
			_add_quad(st, Vector3(cell) + (face[1] as Vector3), face[2], face[3], Vector3(face[0] as Vector3i))
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.9
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	mesh_instance.material_override = material
	return mesh_instance


## A quad from corner along edges u and v (a right-handed pair around normal).
static func _add_quad(st: SurfaceTool, corner: Vector3, u: Vector3, v: Vector3, normal: Vector3) -> void:
	st.set_normal(normal)
	for point in [corner, corner + u, corner + u + v, corner, corner + u + v, corner + v]:
		st.add_vertex(point)


static func _add_box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	for face: Array in _FACES:
		_add_quad(st, center + (face[1] as Vector3) * size, (face[2] as Vector3) * size, (face[3] as Vector3) * size, Vector3(face[0] as Vector3i))


static func _add_ladder(st: SurfaceTool, center: Vector3) -> void:
	st.set_color(COLORS["ladder"])
	for x in [-0.4, 0.4]:
		_add_box(st, center + Vector3(x, 0, 0), Vector3(0.08, 1.0, 0.08))
	for y in [-0.3, 0.0, 0.3]:
		_add_box(st, center + Vector3(0, y, 0), Vector3(0.8, 0.06, 0.06))
