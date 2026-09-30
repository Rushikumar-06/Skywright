class_name CrewAvatar
extends Node3D
## How a crew member looks: a body, a visor that turns and tilts with where they
## look, and, for other players, their name above them. It's only drawn: it never
## collides with anything.

const CLOTH := Color("2f4f6f")
const VISOR := Color("e8a948")

var _head: Node3D


func _init(label := "") -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # placed every frame
	var body := CapsuleMesh.new()
	body.radius = CrewMember.RADIUS
	body.height = CrewMember.HEIGHT
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = CLOTH
	var body_mesh := MeshInstance3D.new()
	body_mesh.mesh = body
	body_mesh.material_override = cloth
	add_child(body_mesh)
	_head = Node3D.new()
	_head.position.y = CrewMember.EYE_HEIGHT
	add_child(_head)
	var visor := BoxMesh.new()
	visor.size = Vector3(0.4, 0.12, 0.12)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = VISOR
	var visor_mesh := MeshInstance3D.new()
	visor_mesh.mesh = visor
	visor_mesh.material_override = glass
	visor_mesh.position.z = -CrewMember.RADIUS + 0.04  # at the front of the face, which looks along -Z
	_head.add_child(visor_mesh)
	if not label.is_empty():
		var tag := Label3D.new()
		tag.text = label
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.pixel_size = 0.004
		tag.font_size = 48
		tag.outline_size = 12
		tag.position.y = CrewMember.HEIGHT / 2.0 + 0.35
		add_child(tag)


## Tilts the visor up (positive) or down, in radians.
func look(pitch: float) -> void:
	_head.rotation.x = pitch
