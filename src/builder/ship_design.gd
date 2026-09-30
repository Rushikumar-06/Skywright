class_name ShipDesign
extends RefCounted
## A ship being designed in the shipyard: its blocks, mirror mode, and undo and redo.
## An edit is an array of changes [cell, before, after], where before and after are
## block dictionaries or null (empty).

## Once per edit, undo, redo, replace or paint.
signal changed

var grid: ShipGrid
var mirror := false

var _undo: Array[Array] = []
var _redo: Array[Array] = []


## Designs a copy of from at full hit points, keeping its paint; empty when null.
func _init(from: ShipGrid = null) -> void:
	grid = ShipGrid.new()
	if from != null:
		_load(from)


## The cell across the keel line.
static func mirror_of(cell: Vector3i) -> Vector3i:
	return Vector3i(-cell.x, cell.y, cell.z)


## Whether a block can go at cell: in the area, empty, and the ship not full.
func can_place(cell: Vector3i) -> bool:
	return ShipGrid.in_area(cell) and not grid.blocks.has(cell) and grid.blocks.size() < ShipGrid.MAX_BLOCKS


## Places a block, and its mirror image when mirror is on. Never overwrites.
func place(cell: Vector3i, type: String, rotation := 0) -> bool:
	var edit: Array = []
	var placed := 0
	var targets: Array = [[cell, rotation]]
	if mirror and cell.x != 0:
		targets.append([mirror_of(cell), Blocks.mirrored(rotation)])
	for target: Array in targets:
		var at: Vector3i = target[0]
		if ShipGrid.in_area(at) and not grid.blocks.has(at) and grid.blocks.size() + placed < ShipGrid.MAX_BLOCKS:
			var block := {"type": type, "rotation": target[1], "hp": Tuning.BLOCKS[type]["hp"]}
			edit.append([at, null, block])
			placed += 1
	return _apply(edit)


## Removes the block at cell, and its mirror image when mirror is on.
func remove(cell: Vector3i) -> bool:
	var edit: Array = []
	for at: Vector3i in [cell, mirror_of(cell)] if mirror and cell.x != 0 else [cell]:
		if grid.blocks.has(at):
			edit.append([at, grid.blocks[at], null])
	return _apply(edit)


## Swaps in the blocks and paint of with, at full hit points, as one undoable edit.
## Undoing brings the blocks back; paint isn't undoable.
func replace(with: ShipGrid) -> void:
	var fresh := ShipDesign.new(with).grid
	var edit: Array = []
	for cell: Vector3i in grid.blocks:
		if not fresh.blocks.has(cell) or fresh.blocks[cell] != grid.blocks[cell]:
			edit.append([cell, grid.blocks[cell], fresh.blocks.get(cell)])
	for cell: Vector3i in fresh.blocks:
		if not grid.blocks.has(cell):
			edit.append([cell, null, fresh.blocks[cell]])
	grid.paint = fresh.paint
	if not _apply(edit):
		changed.emit()  # The paint may still have changed.


## Paints every block of type in color (a Color), or back to its own colour (null).
## Can't be undone.
func set_paint(type: String, color: Variant) -> void:
	if color == null:
		grid.paint.erase(type)
	else:
		grid.paint[type] = color
	changed.emit()


func undo() -> bool:
	return _step(_undo, _redo, 1)


func redo() -> bool:
	return _step(_redo, _undo, 2)


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func _load(from: ShipGrid) -> void:
	for cell: Vector3i in from.blocks:
		grid.set_block(cell, from.blocks[cell]["type"], from.blocks[cell]["rotation"])
	grid.paint = from.paint.duplicate()


## Records and applies an edit; false (and nothing recorded) when it's empty.
func _apply(edit: Array) -> bool:
	if edit.is_empty():
		return false
	_undo.append(edit)
	_redo.clear()
	_write(edit, 2)
	return true


## Moves the newest edit of from to onto, applying its before (index 1) or after (2).
func _step(from: Array[Array], onto: Array[Array], side: int) -> bool:
	if from.is_empty():
		return false
	var edit: Array = from.pop_back()
	onto.append(edit)
	_write(edit, side)
	return true


func _write(edit: Array, side: int) -> void:
	for change: Array in edit:
		if change[side] == null:
			grid.blocks.erase(change[0])
		else:
			grid.blocks[change[0]] = (change[side] as Dictionary).duplicate()
	changed.emit()
