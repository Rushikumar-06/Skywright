class_name Damage
## The rules of damage, node-free so both server and tests can run them: shots,
## blasts, fire, repairs, the Roil, and splitting a ship into pieces. Changes are
## dictionaries of cell -> new hit points (0 for destroyed), in ship space.

## The keys' order is the ammunition index on the wire.
const AMMO := {
	"round": {"name": "Round shot", "speed": 120.0, "damage": 160.0, "reach": 4, "cloth": 1.0, "blast": 0.0, "blast_damage": 0.0},
	"chain": {"name": "Chain shot", "speed": 90.0, "damage": 60.0, "reach": 8, "cloth": 4.0, "blast": 0.0, "blast_damage": 0.0},
	"shell": {"name": "Shell", "speed": 100.0, "damage": 40.0, "reach": 1, "cloth": 1.0, "blast": 3.0, "blast_damage": 90.0},
	"harpoon": {"name": "Harpoon", "speed": 80.0, "damage": 20.0, "reach": 1, "cloth": 1.0, "blast": 0.0, "blast_damage": 0.0},
}
const CLOTH := ["balloon", "sail"]
const FLAMMABLE := ["wood", "cloth"]  ## Materials.
const NOT_REBUILT := ["helm", "cannon"]
const DEBRIS := 4  ## Pieces smaller than this vanish.
const BYTES_PER_CHANGE := 5

const FIRE_DAMAGE := 5
const FIRE_SPREAD := 0.1
const FIRE_TIME := 30.0
const FIRE_CHANCE := 0.25

const REPAIR_STEP := 25
const REPAIR_EVERY := 0.25
const REPAIR_REACH := 6.0  ## A boathook's reach: the envelope can be patched from the deck.
const SPARES_MAX := 40

const ROIL_DAMAGE := 10

const SALVAGE_SPARES := 12
const SALVAGE_REACH := 4.0
const SITE_REACH := 14.0

const _FACES: Array[Vector3i] = [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i.BACK, Vector3i.FORWARD]


## The hit points a shot leaves on the blocks it passes through.
static func shot(grid: ShipGrid, from: Vector3, direction: Vector3, ammo: String) -> Dictionary:
	var changes := {}
	if not AMMO.has(ammo):
		return changes
	var spec: Dictionary = AMMO[ammo]
	var budget: float = spec["damage"]
	for hit: Dictionary in grid.cells_along(from, direction, 200.0, spec["reach"]):
		var cell: Vector3i = hit["cell"]
		var block: Dictionary = grid.blocks[cell]
		var factor: float = spec["cloth"] if block["type"] in CLOTH else 1.0
		var dealt := minf(budget * factor, block["hp"])
		changes[cell] = maxi(0, block["hp"] - roundi(dealt))
		budget -= dealt / factor
		if budget <= 0.01:
			break
	return changes


## Every block whose centre is within radius of center loses damage, less the
## further out it is. Blocks that lose nothing are left out.
static func blast(grid: ShipGrid, center: Vector3, radius: float, damage: float) -> Dictionary:
	var changes := {}
	for cell: Vector3i in grid.blocks:
		var d := center.distance_to(Vector3(cell))
		if d >= radius:
			continue
		var lost := roundi(damage * (1.0 - d / radius))
		if lost > 0:
			changes[cell] = maxi(0, grid.blocks[cell]["hp"] - lost)
	return changes


## Puts changes into the grid. A positive change for an empty cell restores the
## blueprint's block there, when it has one. True when a block was destroyed or restored.
static func apply(grid: ShipGrid, changes: Dictionary, blueprint: ShipGrid = null) -> bool:
	var moved := false
	for cell: Vector3i in changes:
		var hp: int = changes[cell]
		if hp <= 0:
			moved = grid.blocks.erase(cell) or moved
		elif grid.blocks.has(cell):
			grid.blocks[cell]["hp"] = mini(hp, Tuning.BLOCKS[grid.blocks[cell]["type"]]["hp"])
		elif blueprint != null and blueprint.blocks.has(cell):
			var original: Dictionary = blueprint.blocks[cell]
			grid.set_block(cell, original["type"], original["rotation"])
			grid.blocks[cell]["hp"] = mini(hp, grid.blocks[cell]["hp"])
			moved = true
	return moved


## The ship's pieces, joined through faces: {"keep": Array[Vector3i], "wrecks": Array
## of Array[Vector3i], "debris": Array[Vector3i]}. The keep is the largest piece with
## a helm (the largest when none has one); ties go to the smallest cell.
static func split(grid: ShipGrid) -> Dictionary:
	var cells := grid.blocks.keys()
	cells.sort()
	var seen := {}
	var pieces: Array[Array] = []
	for start: Vector3i in cells:
		if seen.has(start):
			continue
		var piece: Array[Vector3i] = []
		var queue: Array[Vector3i] = [start]
		seen[start] = true
		while not queue.is_empty():
			var cell: Vector3i = queue.pop_back()
			piece.append(cell)
			for face in _FACES:
				var next := cell + face
				if grid.blocks.has(next) and not seen.has(next):
					seen[next] = true
					queue.append(next)
		piece.sort()
		pieces.append(piece)
	# Pieces are in order of their smallest cell, since cells were walked in order.
	var keep := -1
	for with_helm in [true, false]:
		for i in pieces.size():
			var has_helm := false
			for cell: Vector3i in pieces[i]:
				has_helm = has_helm or grid.blocks[cell]["type"] == "helm"
			if (has_helm or not with_helm) and (keep < 0 or pieces[i].size() > pieces[keep].size()):
				keep = i
		if keep >= 0:
			break
	var result := {"keep": [] as Array[Vector3i], "wrecks": [], "debris": [] as Array[Vector3i]}
	for i in pieces.size():
		if i == keep:
			result["keep"] = pieces[i]
		elif pieces[i].size() >= DEBRIS:
			result["wrecks"].append(pieces[i])
		else:
			result["debris"].append_array(pieces[i])
	return result


## Changes as bytes: a u16 count, then per change (cells sorted) x + 64, y + 64,
## z + 64 and the hit points as a u16.
static func pack(changes: Dictionary) -> PackedByteArray:
	var cells := changes.keys()
	cells.sort()
	var data := PackedByteArray()
	data.resize(2 + cells.size() * BYTES_PER_CHANGE)
	data.encode_u16(0, cells.size())
	var at := 2
	for cell: Vector3i in cells:
		data[at] = cell.x - ShipGrid.MIN_CELL
		data[at + 1] = cell.y - ShipGrid.MIN_CELL
		data[at + 2] = cell.z - ShipGrid.MIN_CELL
		data.encode_u16(at + 3, changes[cell])
		at += BYTES_PER_CHANGE
	return data


## Changes from pack() bytes, or null if they aren't valid: the bytes may come from another machine.
static func unpack(data: Variant) -> Variant:
	if not data is PackedByteArray or data.size() < 2:
		return null
	var count: int = data.decode_u16(0)
	if count < 1 or count > ShipGrid.MAX_BLOCKS or data.size() != 2 + count * BYTES_PER_CHANGE:
		return null
	var changes := {}
	for at in range(2, data.size(), BYTES_PER_CHANGE):
		var cell := Vector3i(data[at], data[at + 1], data[at + 2]) + Vector3i.ONE * ShipGrid.MIN_CELL
		if not ShipGrid.in_area(cell):
			return null
		changes[cell] = data.decode_u16(at + 3)
	return changes


static func flammable(type: String) -> bool:
	return Blocks.INFO[type]["material"] in FLAMMABLE


## Sets each flammable block among cells alight with FIRE_CHANCE.
static func ignite(grid: ShipGrid, fires: Dictionary, cells: Array, rng: RandomNumberGenerator) -> void:
	var sorted := cells.duplicate()
	sorted.sort()
	for cell: Vector3i in sorted:
		if grid.blocks.has(cell) and flammable(grid.blocks[cell]["type"]) and rng.randf() < FIRE_CHANCE:
			if not fires.has(cell):
				fires[cell] = 0.0


## One second of fire. Returns the hit-point changes; the caller applies them.
static func burn(grid: ShipGrid, fires: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var changes := {}
	var started := {}
	var cells := fires.keys()
	cells.sort()
	for cell: Vector3i in cells:
		if not grid.blocks.has(cell):
			fires.erase(cell)
			continue
		changes[cell] = maxi(0, grid.blocks[cell]["hp"] - FIRE_DAMAGE)
		fires[cell] += 1.0
		if fires[cell] >= FIRE_TIME:
			fires.erase(cell)
		for face in _FACES:
			var next := cell + face
			if grid.blocks.has(next) and flammable(grid.blocks[next]["type"]) and not fires.has(next) and not started.has(next) \
					and rng.randf() < FIRE_SPREAD:
				started[next] = 0.0
	fires.merge(started)
	return changes


## Puts out every fire within one cell (each axis) of cell. True if there were any.
static func put_out(fires: Dictionary, cell: Vector3i) -> bool:
	var any := false
	for fire: Vector3i in fires.keys():
		if maxi(maxi(absi(fire.x - cell.x), absi(fire.y - cell.y)), absi(fire.z - cell.z)) <= 1:
			fires.erase(fire)
			any = true
	return any


## One repair action aimed at cell: heal a damaged block, else rebuild the nearest
## lost block around it that the blueprint has. {} when there is nothing to do.
static func repair(grid: ShipGrid, blueprint: ShipGrid, cell: Vector3i) -> Dictionary:
	if grid.blocks.has(cell):
		var block: Dictionary = grid.blocks[cell]
		var full: int = Tuning.BLOCKS[block["type"]]["hp"]
		if block["hp"] < full:
			return {cell: mini(block["hp"] + REPAIR_STEP, full)}
	var best := Vector3i.ZERO
	var best_rank := 99
	for x in range(-1, 2):
		for y in range(-1, 2):
			for z in range(-1, 2):
				var next := cell + Vector3i(x, y, z)
				var rank := absi(x) + absi(y) + absi(z)  # faces 1, edges 2, corners 3
				if rank == 0 or grid.blocks.has(next) or not blueprint.blocks.has(next) or blueprint.blocks[next]["type"] in NOT_REBUILT:
					continue
				if rank < best_rank or (rank == best_rank and next < best):
					best = next
					best_rank = rank
	if best_rank == 99:
		return {}
	return {best: mini(REPAIR_STEP, Tuning.BLOCKS[blueprint.blocks[best]["type"]]["hp"])}


## The Roil wears every block below Tuning.ROIL_ALTITUDE once placed by place.
static func roil(grid: ShipGrid, place: Transform3D) -> Dictionary:
	var changes := {}
	for cell: Vector3i in grid.blocks:
		if (place * Vector3(cell)).y < Tuning.ROIL_ALTITUDE:
			changes[cell] = maxi(0, grid.blocks[cell]["hp"] - ROIL_DAMAGE)
	return changes
