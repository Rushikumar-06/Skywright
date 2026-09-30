class_name Wind
extends RefCounted
## Wind in m/s at a point and time (spec §4.7): the prevailing wind circling the Eye,
## the rim's push back inward, gusts, sky rivers and storm cells. It's a pure function
## of position, time and the world's seed, so every machine agrees on it without
## sending it. The world sets `time` from its clock every tick.

## Prevailing wind by distance from the Eye: (metres, m/s), joined by straight lines.
const PREVAILING_CURVE: Array[Vector2] = [
	Vector2(0, 3), Vector2(1400, 5), Vector2(1600, 10), Vector2(1900, 14), Vector2(2200, 12),
	Vector2(2400, 12), Vector2(4000, 12), Vector2(6000, 5), Vector2(8000, 2),
]
## The gusts' strength by distance from the Eye: (metres, m/s), likewise.
const GUST_CURVE: Array[Vector2] = [
	Vector2(0, 1.5), Vector2(1400, 2), Vector2(1600, 8), Vector2(1900, 14), Vector2(2200, 6),
	Vector2(2400, 4), Vector2(4000, 4), Vector2(6000, 3), Vector2(8000, 2.5),
]
const DISC_RADIUS := 8000.0  ## m. Beyond it the rim pushes back.
const RIM_WIDTH := 1000.0    ## m. The rim's push is full this far past the disc.
const RIM_PUSH := 15.0       ## m/s at full.
const STORM_GUSTS := 10.0    ## m/s of extra gusts in a storm's core.
const STORM_UPDRAFT := 6.0   ## m/s straight up and down in a storm's core.

## The world's clock in seconds. Below 0, now() counts physics ticks since the game started.
var time := -1.0

var _gen: WorldGen  ## Null: no rivers or storms.


func _init(world_gen: WorldGen = null) -> void:
	_gen = world_gen


## The world's clock: `time`, or physics ticks since the game started while it's unset.
func now() -> float:
	if time >= 0.0:
		return time
	return Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)


## The prevailing wind's speed in m/s at distance metres from the Eye.
static func prevailing_speed(distance: float) -> float:
	return _along(PREVAILING_CURVE, distance)


## The gusts' strength in m/s at distance metres from the Eye.
static func gust_strength(distance: float) -> float:
	return _along(GUST_CURVE, distance)


## The wind at p at time t, in m/s.
func at(p: Vector3, t: float) -> Vector3:
	var flat := Vector3(p.x, 0.0, p.z)
	var distance := flat.length()
	var wind := Vector3.ZERO
	if distance > 1.0:
		wind += Vector3(p.z, 0.0, -p.x) / distance * prevailing_speed(distance)  # counter-clockwise seen from above
	if distance > DISC_RADIUS:
		wind -= flat / distance * RIM_PUSH * clampf((distance - DISC_RADIUS) / RIM_WIDTH, 0.0, 1.0)
	wind += _sines(p, t, 1.0) * gust_strength(distance)
	wind += river_at(p)
	var storm := storm_strength(p, t)
	if storm > 0.0:
		wind += _sines(p, t, 2.0) * (storm * STORM_GUSTS)
		wind.y += storm * STORM_UPDRAFT * sin(t * 0.9 + p.x * 0.01)
	return wind


## The push of the sky rivers at p. Every segment within twice its river's width pulls
## with a weight that is full in the core and fades to nothing at twice the width and
## at the river's two ends; the wind is the weighted segments' sum, no stronger than
## the strongest weight, so it stays smooth at bends, where rivers cross, and where two
## blowing opposite ways overlap (they cancel to calm rather than flip round).
func river_at(p: Vector3) -> Vector3:
	if _gen == null:
		return Vector3.ZERO
	var sum := Vector3.ZERO
	var strongest := 0.0
	for river in _gen.rivers:
		if not (river["box"] as AABB).has_point(p):
			continue
		var points: PackedVector3Array = river["points"]
		var width: float = river["width"]
		var last := points.size() - 2
		for i in points.size() - 1:
			var segment := points[i + 1] - points[i]
			var length_squared := segment.length_squared()
			if length_squared < 0.0001:
				continue  # a river doubling back on the same spot has no direction there
			var u := clampf((p - points[i]).dot(segment) / length_squared, 0.0, 1.0)
			var distance := p.distance_to(points[i] + segment * u)
			if distance >= 2.0 * width:
				continue
			var weight: float = river["speed"] * (1.0 - smoothstep(width, 2.0 * width, distance))
			if i == 0:
				weight *= smoothstep(0.0, 1.0, u)
			if i == last:
				weight *= smoothstep(0.0, 1.0, 1.0 - u)
			sum += segment / sqrt(length_squared) * weight
			strongest = maxf(strongest, weight)
	return sum.limit_length(strongest)


## How much of a storm's strength p is in, 0 to 1: full in the core, fading out
## between 0.6 and 1 times its radius (the strongest storm counts).
func storm_strength(p: Vector3, t: float) -> float:
	var strongest := 0.0
	if _gen == null:
		return strongest
	for i in _gen.storms.size():
		var radius: float = _gen.storms[i]["radius"]
		var centre := _gen.storm_center(i, t)
		var distance := Vector2(p.x - centre.x, p.z - centre.z).length()
		strongest = maxf(strongest, 1.0 - smoothstep(0.6 * radius, radius, distance))
	return strongest


## The gusts' shape at p and t, each axis roughly -1.5 to 1.5; rate says how many
## times faster than the base they vary.
static func _sines(p: Vector3, t: float, rate: float) -> Vector3:
	return Vector3(
		sin((t * 0.37 + p.z * 0.011) * rate) + 0.5 * sin((t * 1.13 + p.x * 0.023) * rate),
		0.3 * sin((t * 0.71 + p.x * 0.017) * rate),
		sin((t * 0.29 + p.x * 0.013) * rate) + 0.5 * sin((t * 0.97 + p.z * 0.019) * rate))


## curve's value at x, joined by straight lines and flat beyond either end.
static func _along(curve: Array[Vector2], x: float) -> float:
	if x <= curve[0].x:
		return curve[0].y
	for i in range(1, curve.size()):
		var a := curve[i - 1]
		var b := curve[i]
		if x <= b.x:
			return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return curve[-1].y
