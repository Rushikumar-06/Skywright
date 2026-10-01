class_name PirateShip
## The pirates' ship: the starter ship's hull armed with four cannons, two a side,
## a ridge of extra balloon cells along the envelope's top to carry their weight,
## and dark paint. Every pirate flies this design (spec §3.5); wrecks in the world
## are these too, broken.

const CANNONS: Array[Vector3i] = [Vector3i(2, 1, -1), Vector3i(2, 1, 2), Vector3i(-2, 1, -1), Vector3i(-2, 1, 2)]
const RIDGE := Vector2i(-4, 6)  ## z from and to of the balloon ridge at y 11, x 0.


static func build() -> ShipGrid:
	var grid := StarterShip.build()
	for side: int in [1, -1]:
		grid.set_block(Vector3i(2 * side, 1, 1), "deck")  # the starter ship's cannon goes back to rail
	for cell in CANNONS:
		var facing := Blocks.turned(0) if cell.x > 0 else Blocks.rotation_of(Basis(Vector3.UP, PI / 2))
		grid.set_block(cell, "cannon", facing)
	for z in range(RIDGE.x, RIDGE.y + 1):
		grid.set_block(Vector3i(0, 11, z), "balloon")
	grid.paint = {"balloon": Color("5a2a2a"), "deck": Color("5b4636"), "frame": Color("3b2a20")}
	return grid
