class_name Wind
## Wind in m/s at a point and time (spec §4.7). It's a pure function of position and
## time, so every machine agrees on it without sending it. Stage 2 has the
## prevailing wind and gusts; stage 5 adds sky rivers and storm cells.

const PREVAILING := 3.0  ## m/s, circling the Eye counter-clockwise.
const GUSTS := 2.5       ## m/s, the gusts' typical strength.
## The prevailing wind's speed by distance from the Eye: (metres, m/s), joined by straight lines.
const PREVAILING_CURVE: Array[Vector2] = [
	Vector2(0, 3), Vector2(1400, 5), Vector2(1600, 10), Vector2(1900, 14), Vector2(2200, 12),
	Vector2(2400, 12), Vector2(4000, 12), Vector2(6000, 5), Vector2(8000, 2),
]


## The prevailing wind's speed in m/s at distance metres from the Eye, flat beyond
## either end of PREVAILING_CURVE.
static func prevailing_speed(distance: float) -> float:
	if distance <= PREVAILING_CURVE[0].x:
		return PREVAILING_CURVE[0].y
	for i in range(1, PREVAILING_CURVE.size()):
		var a := PREVAILING_CURVE[i - 1]
		var b := PREVAILING_CURVE[i]
		if distance <= b.x:
			return lerpf(a.y, b.y, (distance - a.x) / (b.x - a.x))
	return PREVAILING_CURVE[-1].y


static func at(position: Vector3, time: float) -> Vector3:
	var around := Vector3(position.z, 0.0, -position.x)  # counter-clockwise seen from above
	var prevailing := around.normalized() * PREVAILING if around.length() > 1.0 else Vector3.ZERO
	var gust := Vector3(
		sin(time * 0.37 + position.z * 0.011) + 0.5 * sin(time * 1.13 + position.x * 0.023),
		0.3 * sin(time * 0.71 + position.x * 0.017),
		sin(time * 0.29 + position.x * 0.013) + 0.5 * sin(time * 0.97 + position.z * 0.019))
	return prevailing + gust * GUSTS
