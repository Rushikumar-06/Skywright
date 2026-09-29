class_name Island
## A placeholder floating island until the world stage generates real ones: a
## grassy cap on a tapering rock. Ships collide with it.


static func create(at: Vector3, radius: float) -> StaticBody3D:
	var island := StaticBody3D.new()
	island.position = at
	var rock_mesh := CylinderMesh.new()
	rock_mesh.top_radius = radius
	rock_mesh.bottom_radius = radius * 0.12
	rock_mesh.height = radius * 1.5
	rock_mesh.radial_segments = 9
	rock_mesh.rings = 1
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = radius * 1.02
	cap_mesh.bottom_radius = radius
	cap_mesh.height = radius * 0.12
	cap_mesh.radial_segments = 9
	for part: Array in [[rock_mesh, Color("5d4d47"), -radius * 0.75], [cap_mesh, Color("6e8d4c"), 0.0]]:
		var mesh: CylinderMesh = part[0]
		var material := StandardMaterial3D.new()
		material.albedo_color = part[1]
		material.roughness = 0.95
		var body := MeshInstance3D.new()
		body.mesh = mesh
		body.material_override = material
		body.position.y = part[2]
		island.add_child(body)
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_convex_shape()
		shape.position.y = part[2]
		island.add_child(shape)
	return island
