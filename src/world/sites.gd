class_name Sites
## The wrecks and landmarks the world puts on their own islands (WorldGen makes the
## data). Each is made in world space, with its origin where it stands, and is solid
## whether or not visuals are asked for.

const STONE := Color("8d8578")
const WRECK_LOSS := 0.35        ## Chance each block of a wreck is gone.
const WRECK_SINK := 1.0         ## m its lowest block is sunk into the island.
const BURY := 2.0               ## m a landmark's feet are sunk into the ground.
const SPIRE_HEIGHT := Vector2(60.0, 110.0)
const SPIRE_FOOT := 6.0         ## m from the middle to a corner at its foot.
const SPIRE_TIP := 1.0          ## Likewise at the top.
const SPIRE_SEGMENT := 20.0     ## m of height to a collision box.
const ARCH_PILLAR := Vector3(8.0, 40.0, 8.0)
const ARCH_GAP := 30.0          ## m between pillar centres.
const ARCH_LINTEL := Vector3(46.0, 8.0, 8.0)
const RUIN_COLUMNS := 8
const RUIN_RADIUS := 24.0
const RUIN_HEIGHT := Vector2(6.0, 18.0)
const RUIN_SLAB := 30.0         ## m radius of the round floor.
const RUIN_SLAB_DEPTH := 4.0    ## m thick,
const RUIN_SLAB_ABOVE := 1.0    ## m of it above the ground.
const LABEL_ABOVE := 10.0
const LABEL_RANGE := 400.0


## The wreck's ship: the starter ship with its balloons gone and each other block
## lost with WRECK_LOSS, drawn from the wreck's own seed, visiting the cells in
## order so it comes out the same everywhere.
static func wreck_grid(wreck: Dictionary) -> ShipGrid:
	var grid := StarterShip.build()
	for cell in grid.cells_of("balloon"):
		grid.blocks.erase(cell)
	var rng := RandomNumberGenerator.new()
	rng.seed = wreck["seed"]
	var cells := grid.blocks.keys()
	cells.sort()
	for cell: Vector3i in cells:
		if rng.randf() < WRECK_LOSS:
			grid.blocks.erase(cell)
	return grid


## The wreck resting on its island: its lowest block WRECK_SINK into the top at the
## island's centre, turned by its yaw and rolled by its roll.
static func create_wreck(wreck: Dictionary, visuals: bool) -> Node3D:
	var grid := wreck_grid(wreck)
	var node := Node3D.new()
	node.name = "Wreck"
	var lowest := INF
	for cell: Vector3i in grid.blocks:
		lowest = minf(lowest, cell.y - 0.5)
	var basis := Basis(Vector3.UP, wreck["yaw"]) * Basis(Vector3.BACK, wreck["roll"])
	var rest: Vector3 = wreck["at"] + Vector3(0.0, IslandMesh.height(wreck["island"], 0.0, 0.0) - WRECK_SINK, 0.0)
	node.transform = Transform3D(basis, rest - basis * Vector3(0.0, lowest, 0.0))
	var body := StaticBody3D.new()
	node.add_child(body)
	for box in grid.merged_boxes():
		_add_shape(body, Transform3D(Basis.IDENTITY, box.get_center()), box.size)
	if visuals:
		node.add_child(ShipMesh.build(grid))
	return node


## The landmark on its island, on the ground at the island's centre, in stone, with
## its name floating above it.
static func create_landmark(landmark: Dictionary, visuals: bool) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = landmark["seed"]
	var node := Node3D.new()
	node.name = "Landmark"
	node.position = landmark["at"]
	node.rotation.y = rng.randf() * TAU
	var body := StaticBody3D.new()
	node.add_child(body)
	var ground: float = IslandMesh.height(landmark["island"], 0.0, 0.0)
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var top := ground
	match landmark["kind"]:
		"arch":
			for side in [-1.0, 1.0]:
				var pillar := Transform3D(Basis.IDENTITY, Vector3(side * ARCH_GAP / 2.0, ground - BURY + ARCH_PILLAR.y / 2.0, 0.0))
				_add_piece(body, vertices, colors, pillar, ARCH_PILLAR)
			top = ground - BURY + ARCH_PILLAR.y + ARCH_LINTEL.y
			_add_piece(body, vertices, colors, Transform3D(Basis.IDENTITY, Vector3(0.0, top - ARCH_LINTEL.y / 2.0, 0.0)), ARCH_LINTEL)
		"ruin":
			var floor_top := ground + RUIN_SLAB_ABOVE
			WorldChunk.cone(vertices, colors, floor_top - RUIN_SLAB_DEPTH, floor_top, RUIN_SLAB, RUIN_SLAB, 16, STONE)
			var slab := CylinderShape3D.new()
			slab.radius = RUIN_SLAB
			slab.height = RUIN_SLAB_DEPTH
			var slab_shape := CollisionShape3D.new()
			slab_shape.shape = slab
			slab_shape.position.y = floor_top - RUIN_SLAB_DEPTH / 2.0
			body.add_child(slab_shape)
			top = floor_top
			for k in RUIN_COLUMNS:
				var a := TAU * k / RUIN_COLUMNS
				var height := rng.randf_range(RUIN_HEIGHT.x, RUIN_HEIGHT.y)
				var column := Transform3D(Basis.IDENTITY, Vector3(cos(a) * RUIN_RADIUS, floor_top + height / 2.0, sin(a) * RUIN_RADIUS))
				_add_piece(body, vertices, colors, column, Vector3(3.0, height, 3.0))
				top = maxf(top, floor_top + height)
		_:
			var height := rng.randf_range(SPIRE_HEIGHT.x, SPIRE_HEIGHT.y)
			var foot := ground - BURY
			WorldChunk.cone(vertices, colors, foot, foot + height, SPIRE_FOOT, SPIRE_TIP, 4, STONE)
			# Its corners point along the axes' diagonals, so its boxes turn a quarter.
			for k in ceili(height / SPIRE_SEGMENT):
				var from := k * SPIRE_SEGMENT
				var to := minf(from + SPIRE_SEGMENT, height)
				var radius := lerpf(SPIRE_FOOT, SPIRE_TIP, (from + to) / 2.0 / height)
				var side := radius * sqrt(2.0)
				_add_shape(body, Transform3D(Basis(Vector3.UP, PI / 4.0), Vector3(0.0, foot + (from + to) / 2.0, 0.0)), Vector3(side, to - from, side))
			top = foot + height
	if visuals:
		var stone := MeshInstance3D.new()
		stone.mesh = WorldChunk.flat_mesh(vertices, colors)
		node.add_child(stone)
		var label := Label3D.new()
		label.text = landmark["name"]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 96
		label.pixel_size = 0.08
		label.visibility_range_end = LABEL_RANGE
		label.position.y = top + LABEL_ABOVE
		node.add_child(label)
	return node


## A box of stone: collided in body, and drawn in the arrays.
static func _add_piece(body: StaticBody3D, vertices: PackedVector3Array, colors: PackedColorArray, where: Transform3D, size: Vector3) -> void:
	_add_shape(body, where, size)
	WorldChunk.add_box(vertices, colors, where, size, STONE)


static func _add_shape(body: StaticBody3D, where: Transform3D, size: Vector3) -> void:
	var box := BoxShape3D.new()
	box.size = size
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.transform = where
	body.add_child(shape)
