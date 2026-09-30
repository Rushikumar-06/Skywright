class_name Exploration
extends RefCounted
## What you have seen of the world: a grid of 128 m cells over the whole disc, marked
## as you fly past. It lives on this machine only.

const CELL := 128.0     ## m: the side of a cell.
const SIZE := 128       ## Cells across, covering -8,192 to 8,192 m.
const SIGHT := 1200.0   ## m: a cell whose centre is this close, sideways, is seen.
const HALF := CELL * SIZE / 2.0

var image := Image.create(SIZE, SIZE, false, Image.FORMAT_L8)  ## 255 where seen.
var revision := 0  ## Counts every reveal that saw something new, so a map knows to redraw.
var _count := 0


## Marks every cell within sight of p as seen. True if any was new.
func reveal(p: Vector3) -> bool:
	var found := false
	var low := _cell(Vector2(p.x - SIGHT, p.z - SIGHT))
	var high := _cell(Vector2(p.x + SIGHT, p.z + SIGHT))
	for j in range(maxi(low.y, 0), mini(high.y, SIZE - 1) + 1):
		for i in range(maxi(low.x, 0), mini(high.x, SIZE - 1) + 1):
			var centre := Vector2(-HALF + (i + 0.5) * CELL, -HALF + (j + 0.5) * CELL)
			if centre.distance_to(Vector2(p.x, p.z)) <= SIGHT and image.get_pixel(i, j).r == 0.0:
				image.set_pixel(i, j, Color.WHITE)
				_count += 1
				found = true
	if found:
		revision += 1
	return found


## Whether p's cell has been seen. Outside the grid, never.
func seen(p: Vector3) -> bool:
	var cell := _cell(Vector2(p.x, p.z))
	return cell.x >= 0 and cell.y >= 0 and cell.x < SIZE and cell.y < SIZE and image.get_pixel(cell.x, cell.y).r > 0.0


## The share of all cells seen, 0 to 1.
func seen_fraction() -> float:
	return float(_count) / (SIZE * SIZE)


func _cell(flat: Vector2) -> Vector2i:
	return Vector2i(floori((flat.x + HALF) / CELL), floori((flat.y + HALF) / CELL))
