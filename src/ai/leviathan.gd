class_name Leviathan
extends AnimatableBody3D
## A sky leviathan (spec §3.5): a creature, not a block ship. One body with hit points
## on a collision layer of its own, so shots hit it and ships pass through it. On the
## server it drifts, grows curious about ships and paces them without harm, and once
## shot rams whoever shot it until it calms down or they get away. Clients draw the
## server's copy and never think for it.

const LAYER := 1 << 4  ## Collision layer 5. Its mask is empty.
## The wire sends the kind's name.
const KINDS := {
	"leviathan": {"length": 36.0, "radius": 4.0, "hp": 2000, "cruise": 8.0, "charge": 24.0, "turn": 0.35,
			"ram_radius": 3.0, "ram_damage": 120.0},
	"warden": {"length": 72.0, "radius": 8.0, "hp": 6000, "cruise": 12.0, "charge": 26.0, "turn": 0.25,
			"ram_radius": 5.0, "ram_damage": 180.0},
}
const MOODS := ["drift", "curious", "angry", "slain"]

const THINK_EVERY := 0.5
const ACCEL := 4.0          ## m/s² its speed eases toward what it wants.
const CLIMB := 6.0          ## m/s it climbs or sinks at most.
const LOW := 600.0          ## m: the heights it drifts between.
const HIGH := 1600.0
const SIGHT := 600.0        ## m. Ships nearer than this make it curious.
const BESIDE := 120.0       ## m off a ship's side that a curious one paces her.
const CURIOUS_TIME := 60.0  ## s it stays curious about one ship...
const BORED_TIME := 90.0    ## ...then it's bored of her for this long.
const CALM_AFTER := 45.0    ## s after its last hurt that it calms down.
const GIVE_UP := 1500.0     ## m. A target further off got away.
const RAM_REACH := 3.0      ## m from her box that its head rams her.
const RAM_PUSH := 3.0       ## m/s a ram shoves a ship.
const BACK_OFF := 6.0       ## s it swims away after a ram before charging again.
const SINK := 15.0          ## m/s a slain one sinks.
const SLAIN_TIME := 25.0    ## s a slain one is kept before it's taken away.
const HEIGHT_EVERY := 30.0  ## s between a drifting one's new wished heights.
const GALE_RING := 3100.0   ## m from the centre that a drifting leviathan heads for, outside the Gale.

const COLORS := {"leviathan": Color("55626f"), "warden": Color("3b2f3a")}
const EYE_CALM := Color("e8f0ff")
const EYE_ANGRY := Color("ff5a3a")
const SEGMENTS := [0.6, 0.85, 1.0, 1.0, 0.95, 0.85, 0.7, 0.5, 0.35]  ## Of its radius, head to tail.

var kind: String
var hp: int
var mood := "drift"
var target: Ship
var velocity := Vector3.ZERO
var heading := 0.0     ## As Ship.heading() counts: 0 swims along -Z, growing to port.
var simulated := true  ## False on clients: it never thinks there.
var held := false      ## It doesn't move: for tests.

var _sync: WorldSync
var _spec: Dictionary
var _speed := 0.0
var _wish_heading := 0.0
var _wish_speed := 0.0
var _wish_height := 1000.0
var _think_left := 0.0
var _hurt_at := -INF
var _slain_at := -INF
var _backing_off := 0.0  ## s left of swimming away after a ram.
var _curious_since := -INF
var _curious_of: Ship
var _bored: Dictionary = {}  ## Ship -> the clock when it's no longer bored of her.
var _next_height_at := -INF
var _segments: Array[MeshInstance3D] = []
var _eye_material: StandardMaterial3D


func _init(world_sync: WorldSync, beast_kind: String, with_visuals: bool) -> void:
	_sync = world_sync
	kind = beast_kind
	_spec = KINDS[kind]
	hp = _spec["hp"]
	collision_layer = LAYER
	collision_mask = 0
	var capsule := CapsuleShape3D.new()
	capsule.radius = _spec["radius"]
	capsule.height = _spec["length"]
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.rotation.x = PI / 2.0  # along its length, z
	add_child(shape)
	if with_visuals:
		_build_look()


func _ready() -> void:
	_wish_heading = heading
	_wish_height = global_position.y
	_speed = _spec["cruise"]
	global_basis = Basis(Vector3.UP, heading)


## The way it swims, flat.
func forward() -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))


## Its head, in the world: its middle plus half its length forward.
func head() -> Vector3:
	return global_position + forward() * float(_spec["length"]) / 2.0


## Server: it takes damage, from by. At 0 it's slain; otherwise it's angry at by.
func hurt(damage: int, by: Ship) -> void:
	if mood == "slain":
		return
	hp = maxi(0, hp - damage)
	if hp == 0:
		mood = "slain"
		target = null
		_slain_at = _sync.now()
		return
	mood = "angry"
	_hurt_at = _sync.now()
	if _usable(by):
		target = by


## Rounded damage a shot of ammo does to it: its hit and its burst.
static func damage_of(ammo: String) -> int:
	return roundi(Damage.AMMO[ammo]["damage"] + Damage.AMMO[ammo]["blast_damage"])


## Server: whether it's been slain long enough, or sunk far enough, to go.
func gone() -> bool:
	return mood == "slain" and (global_position.y < Tuning.ROIL_ALTITUDE or _sync.now() - _slain_at >= SLAIN_TIME)


func _physics_process(delta: float) -> void:
	if not simulated:
		return
	if mood == "slain":
		velocity = Vector3(0.0, -SINK, 0.0)
		global_position += velocity * delta
		return
	_think_left -= delta
	if _think_left <= 0.0:
		_think_left = THINK_EVERY
		_think()
	if held:
		velocity = Vector3.ZERO
		return
	_backing_off = maxf(0.0, _backing_off - delta)
	heading = rotate_toward(heading, _wish_heading, float(_spec["turn"]) * delta)
	_speed = move_toward(_speed, _wish_speed, ACCEL * delta)
	var climb := clampf((_wish_height - global_position.y) * 0.2, -CLIMB, CLIMB)
	velocity = forward() * _speed + Vector3(0.0, climb, 0.0)
	global_transform = Transform3D(Basis(Vector3.UP, heading), global_position + velocity * delta)
	if mood == "angry" and _backing_off <= 0.0 and _usable(target):
		var box := (target.global_transform * target.bounds).grow(RAM_REACH)
		if box.has_point(head()):
			_sync.ram(target, head(), _spec["ram_radius"], _spec["ram_damage"], forward() * RAM_PUSH)
			_backing_off = BACK_OFF
			_wish_heading = heading  # straight on, away
			_wish_speed = _spec["cruise"]


func _process(_delta: float) -> void:
	if _segments.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0
	var radius: float = _spec["radius"]
	for i in _segments.size():
		_segments[i].position.x = sin(2.0 * t - 0.7 * i) * radius * 0.3 * i / _segments.size()
	_eye_material.albedo_color = EYE_ANGRY if mood == "angry" else EYE_CALM
	_eye_material.emission = _eye_material.albedo_color


func _think() -> void:
	var now := _sync.now()
	if mood == "angry":
		var calm := now - _hurt_at >= CALM_AFTER
		if not calm and _usable(target) and target.global_position.distance_to(global_position) <= GIVE_UP:
			_charge()
			return
		if _usable(target):
			_bored[target] = now + BORED_TIME  # it's had enough of her
		mood = "drift"
		target = null
	var seen := _nearest_ship(now)
	if seen != null and (mood != "curious" or seen != _curious_of):
		mood = "curious"
		_curious_of = seen
		_curious_since = now
	if mood == "curious":
		if not _usable(_curious_of) or now - _curious_since >= CURIOUS_TIME \
				or _curious_of.global_position.distance_to(global_position) > SIGHT:
			if _usable(_curious_of):
				_bored[_curious_of] = now + BORED_TIME
			mood = "drift"
			_curious_of = null
		else:
			_pace(_curious_of)
			return
	_drift(now)


## Charges at where its target will be, at her height.
func _charge() -> void:
	if _backing_off > 0.0:
		return
	var charge: float = _spec["charge"]
	var to := target.global_position
	var ahead := to + target.linear_velocity * (to.distance_to(global_position) / charge)
	_wish_heading = _heading_to(ahead)
	_wish_speed = charge
	_wish_height = to.y


## Swims for the point BESIDE off ship's nearer side, keeping pace with her.
func _pace(ship: Ship) -> void:
	var side := Vector3(ship.global_basis.x.x, 0.0, ship.global_basis.x.z).normalized()
	if side.dot(global_position - ship.global_position) < 0.0:
		side = -side
	var spot := ship.global_position + side * BESIDE
	var her_speed := Vector2(ship.linear_velocity.x, ship.linear_velocity.z).length()
	_wish_heading = _heading_to(spot)
	_wish_speed = minf(her_speed + global_position.distance_to(spot) / 5.0, 0.6 * float(_spec["charge"]))
	_wish_height = ship.global_position.y


## Wanders at cruise; a leviathan outside the Gale Expanse heads back for it.
func _drift(now: float) -> void:
	_wish_speed = _spec["cruise"]
	_wish_heading = wrapf(_wish_heading + _sync.rng.randf_range(-0.2, 0.2), -PI, PI)
	var flat := Vector3(global_position.x, 0.0, global_position.z)
	if kind == "leviathan" and WorldGen.region_at(flat) != WorldGen.Region.GALE and flat.length() > 1.0:
		_wish_heading = _heading_to(flat.normalized() * GALE_RING + Vector3(0.0, global_position.y, 0.0))
	if now >= _next_height_at:
		_next_height_at = now + HEIGHT_EVERY
		_wish_height = _sync.rng.randf_range(LOW, HIGH)


## The nearest ship within SIGHT that isn't a pirate, a wreck or a test flight, and
## that it isn't bored of; or null.
func _nearest_ship(now: float) -> Ship:
	var best: Ship = null
	var best_distance := SIGHT
	for ship: Ship in _sync.ships.values():
		if ship.pirate or ship.test or ship.is_wreck() or _bored.get(ship, -INF) > now:
			continue
		var d := ship.global_position.distance_to(global_position)
		if d <= best_distance:
			best = ship
			best_distance = d
	return best


func _heading_to(p: Vector3) -> float:
	var to := p - global_position
	return atan2(-to.x, -to.z)


## Whether ship is a ship still in the world and not a wreck.
func _usable(ship: Ship) -> bool:
	return is_instance_valid(ship) and _sync.id_of(ship) != 0 and not ship.is_wreck()


## Nine sphere segments along its length, two fins and two eyes. ponytail: one
## MeshInstance3D a segment (about 12 draw calls a beast) and a hitbox that doesn't
## follow the swimming; one skinned mesh if many beasts cost frames.
func _build_look() -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = COLORS[kind]
	skin.roughness = 0.9
	var length: float = _spec["length"]
	var radius: float = _spec["radius"]
	for i in SEGMENTS.size():
		var sphere := SphereMesh.new()
		sphere.radius = radius * SEGMENTS[i]
		sphere.height = radius * SEGMENTS[i] * 2.0
		sphere.radial_segments = 12
		sphere.rings = 6
		sphere.material = skin
		var segment := MeshInstance3D.new()
		segment.mesh = sphere
		segment.position.z = -length / 2.0 + length * (i + 0.5) / SEGMENTS.size()
		add_child(segment)
		_segments.append(segment)
	for side in [-1.0, 1.0]:
		var fin := MeshInstance3D.new()
		var flat := BoxMesh.new()
		flat.size = Vector3(radius * 2.5, radius * 0.15, radius * 1.2)
		flat.material = skin
		fin.mesh = flat
		fin.position = Vector3(side * radius * 1.5, 0.0, _segments[1].position.z)
		add_child(fin)
	_eye_material = StandardMaterial3D.new()
	_eye_material.albedo_color = EYE_CALM
	_eye_material.emission_enabled = true
	_eye_material.emission = EYE_CALM
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = radius * 0.12
		ball.height = radius * 0.24
		ball.material = _eye_material
		eye.mesh = ball
		eye.position = Vector3(side * radius * 0.3, radius * 0.2, -radius * 0.45)  # on the head segment
		_segments[0].add_child(eye)
