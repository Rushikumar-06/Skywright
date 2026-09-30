class_name ShipInterior
extends SubViewport
## A ship's interior (spec §4.5): a physics world of its own, in ship space, where
## its crew walk. It holds a still copy of the ship's collision boxes, so however
## the ship moves, the deck under the crew doesn't. Nothing here is drawn.

var _hull := StaticBody3D.new()


func _init() -> void:
	own_world_3d = true
	size = Vector2i(2, 2)
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_hull)


## Replaces the hull's boxes. The crew stay where they are, and fall if the deck
## under them has gone.
func reshape(boxes: Array[AABB]) -> void:
	for shape in _hull.get_children():
		shape.free()
	for box in boxes:
		var cube := BoxShape3D.new()
		cube.size = box.size
		var shape := CollisionShape3D.new()
		shape.shape = cube
		shape.position = box.get_center()
		_hull.add_child(shape)
