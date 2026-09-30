class_name Dock
## The placeholder dock until towns arrive in stage 5: a stone quay on an island,
## with a slipway for each player in a row to starboard of the first, and a test
## berth ahead of each. Ships at a slipway face the bow (-Z). Within REACH of it
## counts as at the dock.

const SPACING := 60.0                    ## m between slipways.
const SLIPWAYS := 9                      ## One for each player, and one more for a dedicated server's ship.
const TEST_OFFSET := Vector3(0, 0, -90)  ## From a slipway to its test berth.
const REACH := 150.0                     ## m from the dock's area that count as at the dock.
const QUAY := AABB(Vector3(-30, -6.5, 30), Vector3(540, 5, 14))  ## Its top is 1.5 m below the deck of a ship at a slipway.
const ISLAND_AT := Vector3(240, -8, 110)
const ISLAND_RADIUS := 70.0


## The quay and the island under it, for slipway 0 at at.
static func create(at: Vector3) -> StaticBody3D:
	var dock := StaticBody3D.new()
	dock.name = "Dock"
	dock.position = at
	var stone := BoxMesh.new()
	stone.size = QUAY.size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("8d8578")
	material.roughness = 0.95
	var quay := MeshInstance3D.new()
	quay.mesh = stone
	quay.material_override = material
	quay.position = QUAY.get_center()
	dock.add_child(quay)
	var box := BoxShape3D.new()
	box.size = QUAY.size
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = QUAY.get_center()
	dock.add_child(shape)
	dock.add_child(Island.create(ISLAND_AT, ISLAND_RADIUS))
	return dock


## Where a ship at slipway index stands, for a dock at at.
static func slipway(at: Vector3, index: int) -> Transform3D:
	return Transform3D(Basis.IDENTITY, at + Vector3(index * SPACING, 0, 0))


## Where a test flight from slipway index starts.
static func test_berth(at: Vector3, index: int) -> Transform3D:
	return slipway(at, index).translated(TEST_OFFSET)


## Every slipway, every test berth and the quay.
static func area(at: Vector3) -> AABB:
	return AABB(at + Vector3(-30, -60, -100), Vector3(540, 120, 144))


## What ships mustn't be put inside: the quay and the island.
static func obstacles(at: Vector3) -> Array[AABB]:
	# The island's cap reaches 1.02 radii out and 0.06 radii up, and its rock
	# hangs 1.5 radii down (see Island.create).
	var island := AABB(at + ISLAND_AT + Vector3(-1.02, -1.5, -1.02) * ISLAND_RADIUS, Vector3(2.04, 1.56, 2.04) * ISLAND_RADIUS)
	return [AABB(at + QUAY.position, QUAY.size), island]


## Whether where is near enough to the dock at at to use it.
static func near(at: Vector3, where: Vector3) -> bool:
	return area(at).grow(REACH).has_point(where)
