class_name ShipGrid
extends RefCounted
## A ship's blocks on a 1 m grid (spec §4.4). Cell (x, y, z) is the 1 m cube centred
## on (x, y, z) in ship space, where -Z is the bow, +X starboard and +Y up.

const ZONE_SIZE := 4  ## Drag zones are ZONE_SIZE cells on a side.

## Vector3i -> {"type": String, "rotation": int (0–23), "hp": int}
var blocks: Dictionary = {}


## Places a block, replacing any already there, at full hit points.
func set_block(cell: Vector3i, type: String, rotation := 0) -> void:
	blocks[cell] = {"type": type, "rotation": rotation, "hp": Tuning.BLOCKS[type]["hp"]}


## The block type at cell, or "" when it's empty.
func type_at(cell: Vector3i) -> String:
	return blocks[cell]["type"] if blocks.has(cell) else ""


func cells_of(type: String) -> Array[Vector3i]:
	var found: Array[Vector3i] = []
	for cell: Vector3i in blocks:
		if blocks[cell]["type"] == type:
			found.append(cell)
	return found


## Total mass, the mass-weighted centre, and the diagonal of the inertia tensor
## about that centre, treating each block as a solid 1 m cube:
## {"mass": float, "center": Vector3, "inertia": Vector3}
func mass_properties() -> Dictionary:
	var mass := 0.0
	var moment := Vector3.ZERO
	for cell: Vector3i in blocks:
		var m := _mass(cell)
		mass += m
		moment += Vector3(cell) * m
	var center := moment / mass if mass > 0.0 else Vector3.ZERO
	var inertia := Vector3.ZERO
	for cell: Vector3i in blocks:
		var m := _mass(cell)
		var r := Vector3(cell) - center
		# A cube's own inertia (m/6 about each axis) plus its mass at distance r.
		inertia += Vector3(r.y * r.y + r.z * r.z, r.x * r.x + r.z * r.z, r.x * r.x + r.y * r.y) * m + Vector3.ONE * (m / 6.0)
	return {"mass": mass, "center": center, "inertia": inertia}


## The solid cells (everything but ladders) merged greedily into boxes, in ship
## space. Fewer boxes mean fewer shapes and no seams to catch feet on flat decks.
func merged_boxes() -> Array[AABB]:
	var left := {}
	for cell: Vector3i in blocks:
		if blocks[cell]["type"] != "ladder":
			left[cell] = true
	var starts := left.keys()
	starts.sort()
	var boxes: Array[AABB] = []
	for start: Vector3i in starts:
		if not left.has(start):
			continue
		var size := Vector3i.ONE
		while left.has(start + Vector3i(size.x, 0, 0)):
			size.x += 1
		while _all_in(left, start + Vector3i(0, size.y, 0), Vector3i(size.x, 1, 1)):
			size.y += 1
		while _all_in(left, start + Vector3i(0, 0, size.z), Vector3i(size.x, size.y, 1)):
			size.z += 1
		for x in size.x:
			for y in size.y:
				for z in size.z:
					left.erase(start + Vector3i(x, y, z))
		boxes.append(AABB(Vector3(start) - Vector3(0.5, 0.5, 0.5), Vector3(size)))
	return boxes


## The blocks grouped into ZONE_SIZE-cell zones for drag (spec §4.4). Each zone has
## its centre (the mean of its cells) and its area along each ship axis: half its
## exposed faces facing that way, which for a convex zone is its outline seen along
## that axis. [{"center": Vector3, "area": Vector3}]
func drag_zones() -> Array[Dictionary]:
	var sums := {}
	var counts := {}
	var areas := {}
	for cell: Vector3i in blocks:
		var zone := Vector3i(floori(cell.x / float(ZONE_SIZE)), floori(cell.y / float(ZONE_SIZE)), floori(cell.z / float(ZONE_SIZE)))
		sums[zone] = sums.get(zone, Vector3.ZERO) + Vector3(cell)
		counts[zone] = counts.get(zone, 0) + 1
		var area: Vector3 = areas.get(zone, Vector3.ZERO)
		for axis in 3:
			for side in [-1, 1]:
				var neighbour := cell
				neighbour[axis] += side
				if not blocks.has(neighbour):
					area[axis] += 0.5
		areas[zone] = area
	var zones: Array[Dictionary] = []
	for zone: Vector3i in sums:
		zones.append({"center": sums[zone] / counts[zone], "area": areas[zone]})
	return zones


func _mass(cell: Vector3i) -> float:
	return Tuning.BLOCKS[blocks[cell]["type"]]["mass"]


static func _all_in(cells: Dictionary, from: Vector3i, size: Vector3i) -> bool:
	for x in size.x:
		for y in size.y:
			for z in size.z:
				if not cells.has(from + Vector3i(x, y, z)):
					return false
	return true
