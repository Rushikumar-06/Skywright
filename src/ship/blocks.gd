class_name Blocks
## The block catalogue (what the shipyard shows players) and the 24 ways a block
## can face. A block's stored rotation is an index 0-23 into Godot's orthogonal
## basis table, the same one GridMap files use; 0 is the identity, facing the bow.

const GROUPS := ["Hull", "Lift", "Power", "Control", "Crew and cargo", "Weapons"]
const MATERIALS := ["wood", "metal", "cloth", "stone"]
## Blocks whose look depends on the way they face; the rest are plain cubes.
const SHAPED := ["propeller", "rudder", "sail", "cannon", "helm", "ladder"]

## Block type -> {"name", "group", "material", "about"}, in palette order.
const INFO := {
	"frame": {"name": "Frame", "group": "Hull", "material": "wood", "about": "Wooden framing: the bones of a ship."},
	"deck": {"name": "Deck plank", "group": "Hull", "material": "wood", "about": "A floor to walk on."},
	"iron": {"name": "Iron plate", "group": "Hull", "material": "metal", "about": "Heavy armour, and good ballast low in the keel."},
	"alloy": {"name": "Alloy plate", "group": "Hull", "material": "metal", "about": "Armour at two-thirds the weight of iron."},
	"balloon": {"name": "Balloon cell", "group": "Lift", "material": "cloth", "about": "900 N of lift in dense air, and less as the air thins higher up."},
	"lift_stone": {"name": "Lift stone", "group": "Lift", "material": "stone", "about": "6,000 N of lift at any height. Heavy."},
	"engine": {"name": "Engine", "group": "Power", "material": "metal", "about": "Drives two propellers at full power."},
	"propeller": {"name": "Propeller", "group": "Power", "material": "wood", "about": "Up to 2,500 N of thrust, the way it faces."},
	"fuel_tank": {"name": "Fuel tank", "group": "Power", "material": "metal", "about": "Holds 200 units of fuel for the engines."},
	"helm": {"name": "Helm", "group": "Control", "material": "wood", "about": "Where the pilot steers. Every ship needs one."},
	"rudder": {"name": "Rudder", "group": "Control", "material": "wood", "about": "Pushes sideways on its flat side as air flows past, which turns the ship."},
	"sail": {"name": "Sail", "group": "Control", "material": "cloth", "about": "Canvas to catch the wind."},
	"ladder": {"name": "Ladder", "group": "Crew and cargo", "material": "wood", "about": "Climb it with W or Space."},
	"bunk": {"name": "Bunk", "group": "Crew and cargo", "material": "wood", "about": "A berth for one of the crew."},
	"cargo_bay": {"name": "Cargo bay", "group": "Crew and cargo", "material": "wood", "about": "Stows crates."},
	"ballast_tank": {"name": "Ballast tank", "group": "Crew and cargo", "material": "metal", "about": "Water to drop in an emergency."},
	"cannon": {"name": "Cannon", "group": "Weapons", "material": "metal", "about": "Fires the way it faces."},
}

static var _bases: Array[Basis] = []


static func _table() -> Array[Basis]:
	if _bases.is_empty():
		var map := GridMap.new()  # Godot's orthogonal index: the table GridMap files use
		for i in 24:
			_bases.append(map.get_basis_with_orthogonal_index(i))
		map.free()
	return _bases


## The turn a rotation stands for, in ship space.
static func basis(rotation: int) -> Basis:
	return _table()[rotation]


## The rotation that stands for b, or -1 when b isn't one of the 24.
static func rotation_of(b: Basis) -> int:
	var table := _table()
	for i in 24:
		if table[i].is_equal_approx(b):
			return i
	return -1


## The way the block's front points, in ship space.
static func facing(rotation: int) -> Vector3:
	return basis(rotation) * Vector3.FORWARD


## A quarter turn clockwise seen from above: the side that faced the bow faces starboard.
static func turned(rotation: int) -> int:
	return rotation_of(Basis(Vector3.UP, -PI / 2) * basis(rotation))


## A quarter turn forward: the side that faced the bow faces down.
static func tipped(rotation: int) -> int:
	return rotation_of(Basis(Vector3.RIGHT, -PI / 2) * basis(rotation))


## Reflected across the keel line, port for starboard.
static func mirrored(rotation: int) -> int:
	var m := Basis.from_scale(Vector3(-1, 1, 1))
	return rotation_of(m * basis(rotation) * m)


static func is_cube(type: String) -> bool:
	return not type in SHAPED
