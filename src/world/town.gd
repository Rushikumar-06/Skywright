class_name Town
## A town: its dock (the quay and a pier beside every slipway), its flat island with
## houses and a beacon tower, and a sign with its name. WorldGen makes the data; the
## World builds all ten when it loads, so they're always there. A Town node stands
## at its dock's slipway 0, like the Dock inside it.

const GRID := 22.0                ## m between the middles of house plots.
const HOUSE_SHARE := 0.75         ## Of the island's radius, how far out plots go.
const BEHIND_QUAY := 30.0         ## m of clear ground between the quay's back edge and the houses.
const HOUSE_TAKEN := 0.55         ## Chance a plot has a house.
const ROOF := 3.0                 ## m: a roof's height.
const WALLS: Array[Color] = [Color("e9dfc9"), Color("d9b77e"), Color("c98f7a"), Color("a9bfcf"), Color("f2ead8")]
const ROOFS: Array[Color] = [Color("a4553b"), Color("5b6068"), Color("7d5a6b")]
const BEACON := Vector3(5.0, 28.0, 5.0)  ## The tower.
const BEACON_LAMP := 3.0          ## m: the lit cube on top.
const BEACON_COLOR := Color("ffd27a")
const SIGN_HEIGHT := 6.0          ## m above the quay.
const SIGN_RANGE := 600.0


## The town as a Node3D at its dock, drawn when visuals and always collided.
static func create(town: Dictionary, visuals: bool) -> Node3D:
	var node := Node3D.new()
	node.position = town["dock"]
	node.add_child(Dock.create(Vector3.ZERO, visuals))
	var island := WorldChunk.island_node(town["island"], visuals)
	island.position = WorldGen.TOWN_ISLAND
	node.add_child(island)

	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var buildings := StaticBody3D.new()
	buildings.name = "Buildings"
	node.add_child(buildings)
	var rng := RandomNumberGenerator.new()
	rng.seed = town["seed"]
	var plots := int(WorldGen.TOWN_RADIUS * HOUSE_SHARE / GRID) + 1
	for i in range(-plots, plots):
		for j in range(-plots, plots):
			var plot := Vector2(i + 0.5, j + 0.5) * GRID
			var behind := WorldGen.TOWN_ISLAND.z + plot.y - Dock.QUAY.end.z
			if plot.length() > WorldGen.TOWN_RADIUS * HOUSE_SHARE or behind <= BEHIND_QUAY:
				continue
			if rng.randf() >= HOUSE_TAKEN:
				continue
			var size := Vector3(rng.randf_range(6.0, 10.0), rng.randf_range(4.0, 7.0), rng.randf_range(6.0, 10.0))
			var turn := Basis(Vector3.UP, rng.randi_range(0, 3) * PI / 2.0)
			var wall: Color = WALLS[rng.randi_range(0, WALLS.size() - 1)]
			var roof: Color = ROOFS[rng.randi_range(0, ROOFS.size() - 1)]
			var foot := WorldGen.TOWN_ISLAND + Vector3(plot.x, 0.0, plot.y)
			var walls := Transform3D(turn, foot + Vector3(0.0, size.y / 2.0, 0.0))
			WorldChunk.add_box(vertices, colors, walls, size, wall)
			WorldChunk.add_prism(vertices, colors, Transform3D(turn, foot + Vector3(0.0, size.y, 0.0)), Vector3(size.x, ROOF, size.z), roof)
			_add_shape(buildings, "House", walls, size)
	var tower := Transform3D(Basis.IDENTITY, WorldGen.TOWN_ISLAND + Vector3(0.0, BEACON.y / 2.0, 0.0))
	WorldChunk.add_box(vertices, colors, tower, BEACON, Sites.STONE)
	_add_shape(buildings, "Beacon", tower, BEACON)
	var lamp := Transform3D(Basis.IDENTITY, WorldGen.TOWN_ISLAND + Vector3(0.0, BEACON.y + BEACON_LAMP / 2.0, 0.0))
	_add_shape(buildings, "Lamp", lamp, Vector3.ONE * BEACON_LAMP)
	if visuals:
		var houses := MeshInstance3D.new()
		houses.name = "Houses"
		houses.mesh = WorldChunk.flat_mesh(vertices, colors)
		houses.visibility_range_end = IslandMesh.LOD_END[2]
		node.add_child(houses)
		var light := StandardMaterial3D.new()
		light.albedo_color = BEACON_COLOR
		light.emission_enabled = true
		light.emission = BEACON_COLOR
		light.emission_energy_multiplier = 3.0
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE * BEACON_LAMP
		var lit := MeshInstance3D.new()
		lit.name = "Lamp"
		lit.mesh = cube
		lit.material_override = light
		lit.transform = lamp
		node.add_child(lit)
		var sign := Label3D.new()
		sign.name = "Sign"
		sign.text = town["name"]
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sign.font_size = 96
		sign.pixel_size = 0.05
		sign.visibility_range_end = SIGN_RANGE
		sign.position = Vector3(0.0, Dock.QUAY.end.y + SIGN_HEIGHT, Dock.QUAY.get_center().z)
		node.add_child(sign)
	return node


static func _add_shape(body: StaticBody3D, shape_name: String, where: Transform3D, size: Vector3) -> void:
	var box := BoxShape3D.new()
	box.size = size
	var shape := CollisionShape3D.new()
	shape.name = shape_name
	shape.shape = box
	shape.transform = where
	body.add_child(shape)
