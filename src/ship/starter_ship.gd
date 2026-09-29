class_name StarterShip
## The ship every captain starts with: a 5 × 13 m deck on an iron-ballasted keel,
## a raised helm deck at the stern with ladders up to it, a balloon envelope on
## four posts, and one engine driving two propellers. -Z is the bow. It floats
## level at about 880 m.

const ENVELOPE_FROM := -4
const ENVELOPE_TO := 6
const IRON_FROM := -1
const IRON_TO := 2


static func build() -> ShipGrid:
	var grid := ShipGrid.new()
	# Main deck, narrowing at the bow, on a keel. The engine sits in the bilge and
	# the middle of the keel is iron, which keeps her level.
	for z in range(-5, 7):
		for x in range(-2, 3):
			grid.set_block(Vector3i(x, 0, z), "deck")
		grid.set_block(Vector3i(0, -1, z), "iron" if z >= IRON_FROM and z <= IRON_TO else "frame")
	grid.set_block(Vector3i(0, -1, -5), "engine")
	for x in range(-1, 2):
		grid.set_block(Vector3i(x, 0, -6), "deck")
	# Rails.
	for z in range(-5, 4):
		grid.set_block(Vector3i(-2, 1, z), "deck")
		grid.set_block(Vector3i(2, 1, z), "deck")
	for x in range(-1, 2):
		grid.set_block(Vector3i(x, 1, -6), "deck")
	# The helm deck over the stern, 2 m up: planks on a front wall and side walls,
	# with rails and the helm at its front edge.
	for z in range(4, 7):
		for x in range(-2, 3):
			grid.set_block(Vector3i(x, 2, z), "deck")
		grid.set_block(Vector3i(-2, 1, z), "frame")
		grid.set_block(Vector3i(2, 1, z), "frame")
		grid.set_block(Vector3i(-2, 3, z), "deck")
		grid.set_block(Vector3i(2, 3, z), "deck")
	for x in range(-1, 2):
		grid.set_block(Vector3i(x, 1, 4), "frame")
		grid.set_block(Vector3i(x, 3, 6), "deck")
	grid.set_block(Vector3i(0, 3, 4), "helm")
	# Ladders up the front of the helm deck, either side of the helm, reaching 1 m
	# above it so you can step off.
	for y in range(1, 4):
		grid.set_block(Vector3i(-1, y, 3), "ladder")
		grid.set_block(Vector3i(1, y, 3), "ladder")
	# Propellers and rudders behind the stern.
	grid.set_block(Vector3i(-2, 1, 7), "propeller")
	grid.set_block(Vector3i(2, 1, 7), "propeller")
	grid.set_block(Vector3i(0, 1, 7), "rudder")
	grid.set_block(Vector3i(0, 2, 7), "rudder")
	# Four posts up to the envelope: at the bow end of the main deck, and at the
	# back corners of the helm deck, clear of the helmsman's view.
	for y in range(2, 8):
		grid.set_block(Vector3i(-2, y, -4), "frame")
		grid.set_block(Vector3i(2, y, -4), "frame")
	for y in range(3, 8):
		grid.set_block(Vector3i(-2, y, 6), "frame")
		grid.set_block(Vector3i(2, y, 6), "frame")
	# The envelope: 3 m tall and 5 m wide at its middle, running the ship's length.
	for z in range(ENVELOPE_FROM, ENVELOPE_TO + 1):
		for x in range(-1, 2):
			grid.set_block(Vector3i(x, 8, z), "balloon")
			grid.set_block(Vector3i(x, 10, z), "balloon")
		for x in range(-2, 3):
			grid.set_block(Vector3i(x, 9, z), "balloon")
	for z in [ENVELOPE_FROM - 1, ENVELOPE_TO + 1]:
		for x in range(-1, 2):
			grid.set_block(Vector3i(x, 9, z), "balloon")
	return grid
