class_name PirateCaptain
extends Node
## A pirate ship's captain (spec §3.5), on the server only, as a child of her ship.
## Twice a second it picks a target, the nearest ship in sight that isn't a pirate,
## a wreck or a test flight, keeping one it has until it gets away, and flies her
## through the helm's autopilot: patrolling in a slow circle with no target,
## chasing one that's far, and circling one that's close with her guns abeam. She
## steers against the wind's drift, so she goes where she means to.
## Every loaded cannon that can bear on the target, leading it, fires through the
## same server call players use, so only the side facing it fires: broadsides. A
## pirate whose helm is shot away is a wreck, and her captain is gone.

const SIGHT := 900.0          ## m. Ships further off aren't seen.
const GIVE_UP := 1500.0       ## m. A target further off than this got away.
const CLOSE := 500.0          ## m. Nearer than this she circles; further, she chases.
const ORBIT := 260.0          ## m. The circle's bias: she bends in beyond it and out inside it.
const INWARD := 0.8           ## How hard she bends toward the orbit.
const FIRE_RANGE := 600.0     ## m. Her guns fire at targets nearer than this.
const THINK_EVERY := 0.5      ## s between decisions.
const MIN_ALTITUDE := 400.0   ## m. She won't follow a target lower,
const MAX_ALTITUDE := 1800.0  ## or higher.
const PATROL_THROTTLE := 0.3
const CHASE_THROTTLE := 1.0
const CIRCLE_THROTTLE := 0.7
const PATROL_TURN := 0.05     ## rad her heading turns each think on patrol.
const MAX_CRAB := 0.6         ## rad she steers off her heading against the wind's drift, at most,
const CRAB_SPEED := 5.0       ## once she's moving faster than this, in m/s.
const VOLLEY := ["round", "round", "chain"]  ## The ammunition she fires, in turn.

var target: Ship
var state := "patrol"         ## "patrol", "chase" or "circle".
var shots := 0                ## Shots fired, for the volley's turn.

var _sync: WorldSync
var _ship: Ship
var _home_altitude := 0.0     ## Where she patrols: the height she came in at.
var _think_left := 0.0


func _init(world_sync: WorldSync) -> void:
	_sync = world_sync
	name = "Captain"


func _ready() -> void:
	_ship = get_parent()
	_home_altitude = _ship.global_position.y
	if _ship.helm != null:
		_ship.helm.set_autopilot(true)


func _physics_process(delta: float) -> void:
	_think_left -= delta
	if _think_left > 0.0:
		return
	_think_left = THINK_EVERY
	think()


## One decision: whom to chase, how to fly, and what to fire.
func think() -> void:
	if _ship.is_wreck():
		queue_free()
		return
	_pick_target()
	var helm := _ship.helm
	if target == null:
		state = "patrol"
		helm.target_heading = wrapf(helm.target_heading + PATROL_TURN, -PI, PI)
		helm.target_altitude = _home_altitude
		_ship.throttle = PATROL_THROTTLE
		return
	var to := target.global_position - _ship.global_position
	to.y = 0.0
	var d := to.length()
	to = to / d if d > 0.0 else Vector3.FORWARD
	var wish := to
	if d > CLOSE:
		state = "chase"
		_ship.throttle = CHASE_THROTTLE
	else:
		state = "circle"
		_ship.throttle = CIRCLE_THROTTLE
		wish = (to.cross(Vector3.UP) + to * clampf((d - ORBIT) / ORBIT, -1.0, 1.0) * INWARD).normalized()
	helm.target_heading = wrapf(atan2(-wish.x, -wish.z) + _crab(), -PI, PI)
	helm.target_altitude = clampf(target.global_position.y, MIN_ALTITUDE, MAX_ALTITUDE)
	if d < FIRE_RANGE:
		_fire()


## The angle the wind carries her off her heading: steering her bow off by it makes
## her go where she's wished to. Capped at MAX_CRAB; nothing below CRAB_SPEED.
func _crab() -> float:
	var v := Vector2(_ship.linear_velocity.x, _ship.linear_velocity.z)
	if v.length() < CRAB_SPEED:
		return 0.0
	return clampf(wrapf(_ship.heading() - atan2(-v.x, -v.y), -PI, PI), -MAX_CRAB, MAX_CRAB)


## Keeps the target while it's here, whole and not too far; else takes the nearest
## ship in sight, or none.
func _pick_target() -> void:
	if _fair_game(target) and _distance(target) <= GIVE_UP:
		return
	target = null
	var best := SIGHT
	for other: Ship in _sync.ships.values():
		if _fair_game(other) and _distance(other) <= best:
			target = other
			best = _distance(other)


func _fair_game(other: Ship) -> bool:
	return other != null and is_instance_valid(other) and _sync.id_of(other) != 0 and not other.pirate \
			and not other.is_wreck() and not other.test


func _distance(other: Ship) -> float:
	var to := other.global_position - _ship.global_position
	return Vector2(to.x, to.z).length()


## Fires every loaded cannon that can bear on the target, leading it.
func _fire() -> void:
	var ammo: String = VOLLEY[shots % VOLLEY.size()]
	if target.grid.cells_of("balloon").is_empty():
		ammo = "round"
	for cannon in _ship.cannons:
		if fire_at(_sync, _ship, cannon, target, ammo):
			shots += 1


## Fires ship's cannon at target with ammo, leading her, when it's loaded and can
## bear. Whether it fired. It aims at her centre of mass, or at aim_cell (in her space)
## when given. Hired gunners aim with it too.
static func fire_at(world_sync: WorldSync, ship: Ship, cannon: Cannon, target: Ship, ammo: String, aim_cell: Variant = null) -> bool:
	if cannon.reload_left > 0.0:
		return false
	var speed: float = Damage.AMMO[ammo]["speed"]
	var aim_point := target.global_transform * (Vector3(aim_cell as Vector3i) if aim_cell is Vector3i else target.center_of_mass)
	var muzzle := ship.global_transform * (Vector3(cannon.cell) + cannon.facing() * WorldSync.MUZZLE)
	var drift := target.linear_velocity - ship.point_velocity(muzzle)
	var w := Vector3.ZERO
	var t := muzzle.distance_to(aim_point) / speed
	for i in 2:  # where the target will be when the shot gets there, twice refined
		var offset := aim_point + drift * t - muzzle
		w = Projectiles.aim(offset, speed)
		var level := Vector2(w.x, w.z).length()
		if level <= 0.0:
			break
		t = Vector2(offset.x, offset.z).length() / (speed * level)
	if w == Vector3.ZERO or not cannon.aim_at(ship.global_basis.inverse() * w):
		return false
	cannon.ammo = ammo
	return world_sync.fire_cannon(ship, cannon) != 0
