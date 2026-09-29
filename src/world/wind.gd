class_name Wind
## Wind in m/s at a point and time (spec §4.7). It's a pure function of position and
## time, so every machine agrees on it without sending it. Stage 2 has the
## prevailing wind and gusts; stage 5 adds sky rivers and storm cells.

const PREVAILING := 3.0  ## m/s, circling the Eye counter-clockwise.
const GUSTS := 2.5       ## m/s, the gusts' typical strength.


static func at(position: Vector3, time: float) -> Vector3:
	var around := Vector3(position.z, 0.0, -position.x)  # counter-clockwise seen from above
	var prevailing := around.normalized() * PREVAILING if around.length() > 1.0 else Vector3.ZERO
	var gust := Vector3(
		sin(time * 0.37 + position.z * 0.011) + 0.5 * sin(time * 1.13 + position.x * 0.023),
		0.3 * sin(time * 0.71 + position.x * 0.017),
		sin(time * 0.29 + position.x * 0.013) + 0.5 * sin(time * 0.97 + position.z * 0.019))
	return prevailing + gust * GUSTS
