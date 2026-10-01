class_name Dock
## A town's dock: a stone quay along the front of its island, a slipway for each
## player in a row to starboard of the first with a finger pier beside each, and a
## test berth ahead of each. Ships at a slipway face the bow (-Z). Within REACH of
## it counts as at the dock.

const SPACING := 60.0                    ## m between slipways.
const SLIPWAYS := 9                      ## One for each player, and one more for a dedicated server's ship.
const TEST_OFFSET := Vector3(0, 0, -90)  ## From a slipway to its test berth.
const REACH := 150.0                     ## m from the dock's area that count as at the dock.
const QUAY := AABB(Vector3(-30, -6.5, 30), Vector3(540, 5, 14))  ## Its top is 1.5 m below the deck of a ship at a slipway.
const PIER := AABB(Vector3(4, -6.5, -12), Vector3(4, 5, 42))  ## Beside slipway 0, from the quay forward. Its top is the quay's.
const ROCK_REACH := 1.12                 ## Of the town island's radius, how far its underside rings reach out (see IslandMesh.arrays).
const ABOVE_TOWN := 40.0                 ## m over the town island's top that obstacles reach: the houses and the beacon.


## The quay and a pier beside every slipway, for slipway 0 at at, drawn when visuals
## and always collided.
static func create(at: Vector3, visuals := true) -> StaticBody3D:
	var dock := StaticBody3D.new()
	dock.name = "Dock"
	dock.position = at
	var slide := PhysicsMaterial.new()  # a ship blown against a pier slides along it
	slide.friction = 0.0
	slide.bounce = 0.0
	dock.physics_material_override = slide
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("8d8578")
	material.roughness = 0.95
	var parts: Array[AABB] = [QUAY]
	for index in SLIPWAYS:
		parts.append(AABB(PIER.position + Vector3(index * SPACING, 0, 0), PIER.size))
	for part in parts:
		if visuals:
			var stone := BoxMesh.new()
			stone.size = part.size
			var block := MeshInstance3D.new()
			block.mesh = stone
			block.material_override = material
			block.position = part.get_center()
			dock.add_child(block)
		var box := BoxShape3D.new()
		box.size = part.size
		var shape := CollisionShape3D.new()
		shape.shape = box
		shape.position = part.get_center()
		dock.add_child(shape)
	return dock


## Where a ship at slipway index stands, for a dock at at.
static func slipway(at: Vector3, index: int) -> Transform3D:
	return Transform3D(Basis.IDENTITY, at + Vector3(index * SPACING, 0, 0))


## Where a test flight from slipway index starts.
static func test_berth(at: Vector3, index: int) -> Transform3D:
	return slipway(at, index).translated(TEST_OFFSET)


## Where someone stands on the quay behind slipway 0, for a dock at at.
static func quay_spot(at: Vector3) -> Vector3:
	return at + Vector3(0, -0.5, 37)


## Every slipway, every test berth and the quay.
static func area(at: Vector3) -> AABB:
	return AABB(at + Vector3(-30, -60, -100), Vector3(540, 120, 144))


## What ships mustn't be put inside: the quay, the piers (in that order) and the
## town island (out to where its rock reaches), from its rock up to over its beacon.
static func obstacles(at: Vector3) -> Array[AABB]:
	var found: Array[AABB] = [AABB(at + QUAY.position, QUAY.size)]
	for index in SLIPWAYS:
		found.append(AABB(at + PIER.position + Vector3(index * SPACING, 0, 0), PIER.size))
	var radius := WorldGen.TOWN_RADIUS * ROCK_REACH
	var depth := WorldGen.TOWN_RADIUS * WorldGen.TOWN_DEPTH
	var top := at + WorldGen.TOWN_ISLAND
	found.append(AABB(top + Vector3(-radius, -depth, -radius), Vector3(2.0 * radius, depth + ABOVE_TOWN, 2.0 * radius)))
	return found


## Whether where is near enough to the dock at at to use it.
static func near(at: Vector3, where: Vector3) -> bool:
	return area(at).grow(REACH).has_point(where)
