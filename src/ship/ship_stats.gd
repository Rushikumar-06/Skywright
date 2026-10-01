class_name ShipStats
extends RefCounted
## What a design will do, worked out from its blocks without flying it: weight, lift,
## where she floats, thrust, speed, balance, and what's wrong with her. The shipyard
## shows these. The balance maths assume the lift settles straight above the weight.

const LEAN_WARNING := 2.0  ## Degrees of list or trim past which the shipyard warns.

var altitude := 0.0
var blocks := 0
var mass := 0.0                ## kg
var weight := 0.0              ## N
var lift := 0.0                ## N at altitude and trim 1
var float_altitude := 0.0      ## m where lift equals weight at trim 1; INF: climbs forever, -INF: sinks
var ceiling := 0.0             ## m where lift equals weight at full trim
var thrust := 0.0              ## N along the bow at full throttle
var top_speed := 0.0           ## m/s at altitude
var fuel := 0.0                ## units her tanks hold
var fuel_range := 0.0          ## m at full throttle on full tanks
var climb_rate := 0.0          ## m/s at full trim; negative sinks
var center_of_mass := Vector3.ZERO
var center_of_lift := Vector3.ZERO
var list := 0.0                ## degrees; positive leans to starboard
var bow_down := 0.0            ## degrees; positive is bow down
var warnings := PackedStringArray()


static func of(grid: ShipGrid, at_altitude: float) -> ShipStats:
	var s := ShipStats.new()
	s.altitude = at_altitude
	s.blocks = grid.blocks.size()
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	var props := grid.mass_properties()
	s.mass = props["mass"]
	s.center_of_mass = props["center"]
	s.weight = s.mass * gravity
	var density := ShipForces.air_density(at_altitude)
	var balloons := grid.cells_of("balloon")
	var stones := grid.cells_of("lift_stone")
	var balloon_lift := balloons.size() * Tuning.BALLOON_LIFT
	var stone_lift := stones.size() * Tuning.LIFT_STONE_LIFT
	s.lift = stone_lift + balloon_lift * density
	s.float_altitude = _float_height(s.weight, stone_lift, balloon_lift)
	s.ceiling = _float_height(s.weight, stone_lift, balloon_lift * Tuning.TRIM_MAX)
	s.thrust = ShipForces.forward_thrust(grid)
	var forward_area := 0.0
	var up_area := 0.0
	for zone in grid.drag_zones():
		forward_area += zone["area"].z
		up_area += zone["area"].y
	s.top_speed = ShipForces.top_speed(s.thrust, forward_area, at_altitude)
	s.fuel = grid.cells_of("fuel_tank").size() * Tuning.FUEL_PER_TANK
	var engines := grid.cells_of("engine").size()
	if engines > 0:
		s.fuel_range = s.fuel / (engines * Tuning.ENGINE_BURN) * s.top_speed
	if up_area > 0.0:
		var net := stone_lift + Tuning.TRIM_MAX * balloon_lift * density - s.weight
		s.climb_rate = signf(net) * sqrt(absf(net) / (0.5 * Tuning.AIR_DENSITY * density * Tuning.DRAG_COEFFICIENT * up_area))
	if s.lift > 0.0:
		var sum := Vector3.ZERO
		for cell in balloons:
			sum += Vector3(cell) * Tuning.BALLOON_LIFT * density
		for cell in stones:
			sum += Vector3(cell) * Tuning.LIFT_STONE_LIFT
		s.center_of_lift = sum / s.lift
		var com := s.center_of_mass
		var col := s.center_of_lift
		s.list = rad_to_deg(atan2(com.x - col.x, col.y - com.y))
		s.bow_down = rad_to_deg(atan2(col.z - com.z, col.y - com.y))
	s._find_warnings(grid)
	return s


## The readout the shipyard shows, one stat a line.
func describe() -> String:
	return "\n".join([
		"Blocks     %d of %d" % [blocks, ShipGrid.MAX_BLOCKS],
		"Weight     %.1f t" % (mass / 1000.0),
		"Lift       %.1f kN at %d m" % [lift / 1000.0, roundi(altitude)],
		"Floats at  " + _height_text(float_altitude),
		"Ceiling    " + _height_text(ceiling),
		"Thrust     %.1f kN" % (thrust / 1000.0),
		"Top speed  %d m/s" % roundi(top_speed),
		"Fuel       %d units, %.1f km at full throttle" % [roundi(fuel), fuel_range / 1000.0],
		"Climb      %+.1f m/s at full trim" % climb_rate,
	])


## The height where air density equals ratio: INF with no air needed, -INF for
## more than the Roil's air.
static func _height_where(ratio: float) -> float:
	if ratio <= 0.0:
		return INF
	if ratio > 1.0:
		return -INF
	return Tuning.ROIL_ALTITUDE - Tuning.AIR_SCALE_HEIGHT * log(ratio)


static func _float_height(weight: float, stone_lift: float, balloon_lift: float) -> float:
	if stone_lift > 0.0 and stone_lift >= weight:
		return INF
	if balloon_lift == 0.0:
		return -INF
	return _height_where((weight - stone_lift) / balloon_lift)


static func _height_text(height: float) -> String:
	if height == INF:
		return "climbs forever"
	if height == -INF:
		return "sinks into the Roil"
	return "%d m" % roundi(height)


func _find_warnings(grid: ShipGrid) -> void:
	if not ShipGrid.helm_problem(grid).is_empty():
		warnings.append(ShipGrid.helm_problem(grid))
	if not grid.cells_of("helm").is_empty():
		var loose: int = blocks - Damage.split(grid)["keep"].size()
		if loose > 0:
			warnings.append("%d blocks aren't joined to the helm: they'll fall away when she's hit." % loose)
	if blocks == 0:
		return
	if ceiling == -INF:
		warnings.append("Too heavy to fly: she sinks into the Roil.")
	elif ceiling < altitude:
		warnings.append("Too heavy to hold %d m: she can climb no higher than %d m." % [roundi(altitude), roundi(ceiling)])
	elif float_altitude == INF:
		warnings.append("Too much lift: her lift stones alone carry her, so she'll climb forever.")
	if lift > 0.0:
		if center_of_lift.y <= center_of_mass.y:
			warnings.append("Top-heavy: her lift is below her weight, so she'll roll over.")
		else:
			if absf(list) >= LEAN_WARNING:
				warnings.append("Lists %d° to %s." % [roundi(absf(list)), "starboard" if list > 0.0 else "port"])
			if absf(bow_down) >= LEAN_WARNING:
				warnings.append("Down by the %s %d°." % ["bow" if bow_down > 0.0 else "stern", roundi(absf(bow_down))])
	if grid.cells_of("propeller").is_empty():
		warnings.append("No propellers: she can only drift.")
	elif grid.cells_of("engine").is_empty():
		warnings.append("No engine: her propellers won't turn.")
	elif thrust <= 0.0:
		warnings.append("None of her propellers push her forward.")
	if not grid.cells_of("engine").is_empty() and fuel <= 0.0:
		warnings.append("No fuel tank: her engines won't run.")
	if grid.cells_of("rudder").is_empty():
		warnings.append("No rudder: she can't steer.")
