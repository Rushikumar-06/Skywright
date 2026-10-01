class_name Wallbreaker
## The Wallwright's twin-engine design, given by a log (spec §3.7): the starter ship
## with a second engine, four propellers, a taller envelope and four fuel tanks, made
## to push through the Stormwall.


static func build() -> ShipGrid:
	var grid := StarterShip.build()
	grid.set_block(Vector3i(0, -1, 1), "engine")
	grid.set_block(Vector3i(-2, 2, 7), "propeller")
	grid.set_block(Vector3i(2, 2, 7), "propeller")
	for z in range(StarterShip.ENVELOPE_FROM, StarterShip.ENVELOPE_TO + 1):
		grid.set_block(Vector3i(0, 11, z), "balloon")
	grid.set_block(Vector3i(0, -1, -2), "fuel_tank")
	grid.set_block(Vector3i(0, -1, -4), "fuel_tank")
	grid.paint = {"balloon": Color("2f5d8a")}
	return grid
