class_name SnapshotBuffer
extends RefCounted
## Snapshots of one moving thing, timed on the server's clock, for drawing it a
## little in the past (spec §4.6). Between two snapshots it follows a Hermite
## curve, which passes through both with the velocities they carried, so motion
## stays smooth through turns. Past the newest it carries on at the newest
## velocity and spin for at most EXTRAPOLATE seconds, then waits.

const EXTRAPOLATE := 0.25  ## Seconds of dead reckoning when snapshots are late.
const KEEP := 1.0          ## Seconds of snapshots kept behind the newest.

## Oldest first: {"time", "position", "velocity", "rotation", "spin"}.
var _samples: Array[Dictionary] = []


## Adds a snapshot. One no newer than the newest (late or out of order) is ignored.
func push(time: float, position: Vector3, velocity: Vector3, rotation: Quaternion, spin := Vector3.ZERO) -> void:
	if not _samples.is_empty() and time <= _samples[-1]["time"]:
		return
	_samples.append({"time": time, "position": position, "velocity": velocity, "rotation": rotation, "spin": spin})
	while _samples.size() > 1 and _samples[1]["time"] <= time - KEEP:
		_samples.pop_front()


func is_empty() -> bool:
	return _samples.is_empty()


## Where it was at time: {"position": Vector3, "velocity": Vector3, "rotation": Quaternion}.
## Before the oldest snapshot, the oldest. {} when there are none.
func sample(time: float) -> Dictionary:
	if _samples.is_empty():
		return {}
	var first := _samples[0]
	if time <= first["time"]:
		return {"position": first["position"], "velocity": first["velocity"], "rotation": first["rotation"]}
	var last := _samples[-1]
	if time >= last["time"]:
		var ahead := minf(time - last["time"], EXTRAPOLATE)
		var spin: Vector3 = last["spin"]
		var rotation: Quaternion = last["rotation"]
		if not spin.is_zero_approx():
			rotation = (Quaternion(spin.normalized(), spin.length() * ahead) * rotation).normalized()
		return {"position": last["position"] + last["velocity"] * ahead, "velocity": last["velocity"], "rotation": rotation}
	var i := _samples.size() - 2
	while _samples[i]["time"] > time:
		i -= 1
	var a := _samples[i]
	var b := _samples[i + 1]
	var dt: float = b["time"] - a["time"]
	var s: float = (time - a["time"]) / dt
	var s2 := s * s
	var s3 := s2 * s
	var p0: Vector3 = a["position"]
	var p1: Vector3 = b["position"]
	var m0: Vector3 = a["velocity"] * dt
	var m1: Vector3 = b["velocity"] * dt
	var position := p0 * (2.0 * s3 - 3.0 * s2 + 1.0) + m0 * (s3 - 2.0 * s2 + s) + p1 * (-2.0 * s3 + 3.0 * s2) + m1 * (s3 - s2)
	var slope := p0 * (6.0 * s2 - 6.0 * s) + m0 * (3.0 * s2 - 4.0 * s + 1.0) + p1 * (-6.0 * s2 + 6.0 * s) + m1 * (3.0 * s2 - 2.0 * s)
	var rotation := (a["rotation"] as Quaternion).slerp(b["rotation"], s)
	return {"position": position, "velocity": slope / dt, "rotation": rotation}
