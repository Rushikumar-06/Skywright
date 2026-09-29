class_name ShipInterior
extends SubViewport
## A ship's interior (spec §4.5): a physics world of its own, in ship space, where
## its crew walk. It holds a still copy of the ship's collision boxes, so however
## the ship moves, the deck under the crew doesn't. Nothing here is drawn.


func _init(boxes: Array[AABB]) -> void:
	own_world_3d = true
	size = Vector2i(2, 2)
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	var hull := StaticBody3D.new()
	for box in boxes:
		var cube := BoxShape3D.new()
		cube.size = box.size
		var shape := CollisionShape3D.new()
		shape.shape = cube
		shape.position = box.get_center()
		hull.add_child(shape)
	add_child(hull)
