class_name ShipForces
## The flight model's formulas (spec §4.4), free of nodes so tests and the
## shipyard readouts can use them.


## Air density at altitude as a fraction of the density at the Roil: 1 at 200 m
## and below, thinning above.
static func air_density(altitude: float) -> float:
	if altitude <= Tuning.ROIL_ALTITUDE:
		return 1.0
	return exp(-(altitude - Tuning.ROIL_ALTITUDE) / Tuning.AIR_SCALE_HEIGHT)


## Drag on one zone, in ship axes, from the zone's velocity through the air in ship
## axes. Each axis is separate: -½ × ρ × Cd × area × |v| × v.
static func zone_drag(area: Vector3, air_velocity: Vector3, density: float) -> Vector3:
	return -0.5 * Tuning.AIR_DENSITY * density * Tuning.DRAG_COEFFICIENT * area * air_velocity.abs() * air_velocity


## The hull's sideways lift on one zone, along ship x: moving forward while
## slipping sideways, the hull pushes back against the slip as a keel does, which
## is what lets a ship carve a turn. It needs forward speed, so hovering ships
## still drift with the wind.
static func keel(side_area: float, air_velocity: Vector3, density: float) -> float:
	return -0.5 * Tuning.AIR_DENSITY * density * Tuning.HULL_LIFT * side_area * absf(air_velocity.z) * air_velocity.x


## The speed at which drag on forward_area matches thrust, at altitude.
static func top_speed(thrust: float, forward_area: float, altitude: float) -> float:
	if thrust <= 0.0 or forward_area <= 0.0:
		return 0.0
	return sqrt(thrust / (0.5 * Tuning.AIR_DENSITY * air_density(altitude) * Tuning.DRAG_COEFFICIENT * forward_area))


## Each propeller's share of full thrust: every engine drives two propellers, so
## with more propellers than that they share the power. 0 with no propellers.
static func propeller_power(grid: ShipGrid) -> float:
	var propellers := grid.cells_of("propeller").size()
	if propellers == 0:
		return 0.0
	return minf(1.0, float(grid.cells_of("engine").size() * Tuning.PROPELLERS_PER_ENGINE) / propellers)


## Full-throttle thrust along the bow, in N: each propeller pushes the way it faces,
## so this is negative when they push astern.
static func forward_thrust(grid: ShipGrid) -> float:
	var power := propeller_power(grid)
	var sum := 0.0
	for cell in grid.cells_of("propeller"):
		sum += power * Tuning.PROPELLER_THRUST * Blocks.facing(grid.blocks[cell]["rotation"]).dot(Vector3.FORWARD)
	return sum
