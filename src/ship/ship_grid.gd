class_name ShipGrid
extends RefCounted
## A ship's blocks on a 1 m grid (spec §4.4). Cell (x, y, z) is the 1 m cube centred
## on (x, y, z) in ship space, where -Z is the bow, +X starboard and +Y up.

const ZONE_SIZE := 4       ## Drag zones are ZONE_SIZE cells on a side.
const MAX_BLOCKS := 4000   ## Spec §3.3.
const MIN_CELL := -64      ## Every coordinate is in MIN_CELL…MAX_CELL (spec §4.10).
const MAX_CELL := 63
const BYTES_PER_BLOCK := 7  ## In to_bytes' body.

## Vector3i -> {"type": String, "rotation": int (0–23), "hp": int}
var blocks: Dictionary = {}
## Block type -> Color: every block of that type is drawn in it.
var paint: Dictionary = {}


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


## The box around every block, in ship space.
func bounds() -> AABB:
	var box := AABB()
	for cell: Vector3i in blocks:
		var cube := AABB(Vector3(cell) - Vector3(0.5, 0.5, 0.5), Vector3.ONE)
		box = cube if box.size == Vector3.ZERO else box.merge(cube)
	return box


## The blocks as plain data for sending: [[x, y, z, type, rotation, hp], …].
func to_blocks() -> Array:
	var data := []
	for cell: Vector3i in blocks:
		var block: Dictionary = blocks[cell]
		data.append([cell.x, cell.y, cell.z, block["type"], block["rotation"], block["hp"]])
	return data


## A grid from to_blocks() data, or null if it isn't a valid ship; see read_blocks.
static func from_blocks(data: Variant, needs_helm := true) -> ShipGrid:
	return read_blocks(data, needs_helm).get("grid")


## Checks block data that may come from another machine or a shared file, and
## returns {"grid": ShipGrid} or {"problem": String} naming the first thing wrong.
## Entries are [x, y, z, type, rotation] at full hit points, or with hit points as a
## sixth item. Numbers may be ints or whole floats (JSON has only floats). Without
## needs_helm, a wreck will do.
static func read_blocks(data: Variant, needs_helm := true) -> Dictionary:
	if not data is Array or data.is_empty():
		return {"problem": "The ship has no blocks."}
	if data.size() > MAX_BLOCKS:
		return {"problem": "The ship has %d blocks; the most a ship can have is %d." % [data.size(), MAX_BLOCKS]}
	var grid := ShipGrid.new()
	var n := 0
	for block: Variant in data:
		n += 1
		if not block is Array or block.size() < 5 or block.size() > 6 or not block[3] is String:
			return {"problem": "Block %d isn't written as [x, y, z, type, rotation]." % n}
		var numbers: Array[int] = []
		for i in [0, 1, 2, 4, 5]:
			if i >= block.size():
				continue
			var value: Variant = block[i]
			if value is float and is_finite(value) and value == floorf(value) and absf(value) < 1e9:
				value = int(value)
			if not value is int:
				return {"problem": "Block %d has a number that isn't a whole number." % n}
			numbers.append(value)
		var cell := Vector3i(numbers[0], numbers[1], numbers[2])
		if cell.clamp(Vector3i.ONE * MIN_CELL, Vector3i.ONE * MAX_CELL) != cell:
			return {"problem": "Block %d is outside the build area (%d to %d)." % [n, MIN_CELL, MAX_CELL]}
		var type: String = block[3]
		if not Tuning.BLOCKS.has(type):
			return {"problem": "Block %d is an unknown type, \"%s\"." % [n, type.left(24)]}
		if numbers[3] < 0 or numbers[3] > 23:
			return {"problem": "Block %d has rotation %d; rotations go from 0 to 23." % [n, numbers[3]]}
		var full: int = Tuning.BLOCKS[type]["hp"]
		var hp: int = numbers[4] if numbers.size() > 4 else full
		if hp < 1 or hp > full:
			return {"problem": "Block %d has %d hit points; a %s has 1 to %d." % [n, hp, type, full]}
		if grid.blocks.has(cell):
			return {"problem": "Block %d is in the same place as another block." % n}
		grid.blocks[cell] = {"type": type, "rotation": numbers[3], "hp": hp}
	if needs_helm and grid.cells_of("helm").is_empty():
		return {"problem": "Every ship needs a helm."}
	return {"grid": grid}


## Whether cell is inside the build area.
static func in_area(cell: Vector3i) -> bool:
	return cell.clamp(Vector3i.ONE * MIN_CELL, Vector3i.ONE * MAX_CELL) == cell


## The first block a ray enters (ladders included) as {"cell": Vector3i, "normal":
## Vector3i}, the normal being the face it came through, or {} when nothing is hit
## within max_distance. A voxel walk, so no physics is needed.
func raycast(from: Vector3, direction: Vector3, max_distance := 200.0) -> Dictionary:
	var hits := cells_along(from, direction, max_distance, 1)
	return hits[0] if not hits.is_empty() else {}


## The first count blocks a ray enters (ladders included), in order, each as
## {"cell": Vector3i, "normal": Vector3i}, the normal being the face it came through.
func cells_along(from: Vector3, direction: Vector3, max_distance := 200.0, count := 1) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var dir := direction.normalized()
	var p := from + Vector3(0.5, 0.5, 0.5)  # cell c now spans [c, c + 1)
	var cell := Vector3i(floori(p.x), floori(p.y), floori(p.z))
	var step := Vector3i.ZERO
	var t_max := Vector3(INF, INF, INF)
	var t_delta := Vector3(INF, INF, INF)
	for axis in 3:
		if dir[axis] > 0.0:
			step[axis] = 1
			t_max[axis] = (cell[axis] + 1 - p[axis]) / dir[axis]
			t_delta[axis] = 1.0 / dir[axis]
		elif dir[axis] < 0.0:
			step[axis] = -1
			t_max[axis] = (cell[axis] - p[axis]) / dir[axis]
			t_delta[axis] = -1.0 / dir[axis]
	var normal := Vector3i.ZERO
	var t := 0.0
	while t <= max_distance and found.size() < count:
		if blocks.has(cell):
			found.append({"cell": cell, "normal": normal})
		var axis := t_max.min_axis_index()
		t = t_max[axis]
		cell[axis] += step[axis]
		t_max[axis] += t_delta[axis]
		normal = Vector3i.ZERO
		normal[axis] = -step[axis]
	return found


## The blocks packed for the network: bytes 0-1 are the block count (u16), the rest
## is the zstd-compressed body of BYTES_PER_BLOCK bytes a block: x + 64, y + 64,
## z + 64, the type's index in Tuning.BLOCKS' key order, the rotation, and the hit
## points (u16). Reordering Tuning.BLOCKS changes this format.
func to_bytes() -> PackedByteArray:
	var types := Tuning.BLOCKS.keys()
	var body := PackedByteArray()
	body.resize(blocks.size() * BYTES_PER_BLOCK)
	var at := 0
	for cell: Vector3i in blocks:
		var block: Dictionary = blocks[cell]
		body[at] = cell.x - MIN_CELL
		body[at + 1] = cell.y - MIN_CELL
		body[at + 2] = cell.z - MIN_CELL
		body[at + 3] = types.find(block["type"])
		body[at + 4] = block["rotation"]
		body.encode_u16(at + 5, block["hp"])
		at += BYTES_PER_BLOCK
	var data := PackedByteArray([0, 0])
	data.encode_u16(0, blocks.size())
	data.append_array(body.compress(FileAccess.COMPRESSION_ZSTD))
	return data


## A grid from to_bytes() data, or null if it isn't valid. Nothing is assumed: the
## bytes may come from another machine. Without needs_helm, a wreck will do.
static func from_bytes(data: Variant, needs_helm := true) -> ShipGrid:
	if not data is PackedByteArray or data.size() < 3:
		return null
	var count: int = data.decode_u16(0)
	if count < 1 or count > MAX_BLOCKS:
		return null
	var size := count * BYTES_PER_BLOCK
	# Junk or a wrong size decompresses to nothing, so check the length.
	var body: PackedByteArray = data.slice(2).decompress(size, FileAccess.COMPRESSION_ZSTD)
	if body.size() != size:
		return null
	var types := Tuning.BLOCKS.keys()
	var list := []
	for at in range(0, size, BYTES_PER_BLOCK):
		if body[at + 3] >= types.size():
			return null
		list.append([body[at] + MIN_CELL, body[at + 1] + MIN_CELL, body[at + 2] + MIN_CELL, types[body[at + 3]], body[at + 4], body.decode_u16(at + 5)])
	return from_blocks(list, needs_helm)


## Paint as plain text for sending or saving: type -> "rrggbb".
func paint_names() -> Dictionary:
	var names := {}
	for type: String in paint:
		names[type] = (paint[type] as Color).to_html(false)
	return names


## Paint from paint_names() data (or a blueprint's "paint"): a Dictionary of type ->
## Color, or null when it isn't valid.
static func read_paint(data: Variant) -> Variant:
	if not data is Dictionary or data.size() > Tuning.BLOCKS.size():
		return null
	var colours := {}
	for type: Variant in data:
		var value: Variant = data[type]
		if not type is String or not Tuning.BLOCKS.has(type) or not value is String or not Color.html_is_valid(value):
			return null
		colours[type] = Color(value)
	return colours


## An independent copy, with hit points and paint.
func copy() -> ShipGrid:
	var other := ShipGrid.new()
	for cell: Vector3i in blocks:
		other.blocks[cell] = (blocks[cell] as Dictionary).duplicate()
	other.paint = paint.duplicate()
	return other


## An independent copy with every block at full hit points, and paint.
func whole() -> ShipGrid:
	var other := copy()
	for cell: Vector3i in other.blocks:
		other.blocks[cell]["hp"] = Tuning.BLOCKS[other.blocks[cell]["type"]]["hp"]
	return other


func _mass(cell: Vector3i) -> float:
	return Tuning.BLOCKS[blocks[cell]["type"]]["mass"]


static func _all_in(cells: Dictionary, from: Vector3i, size: Vector3i) -> bool:
	for x in size.x:
		for y in size.y:
			for z in size.z:
				if not cells.has(from + Vector3i(x, y, z)):
					return false
	return true
