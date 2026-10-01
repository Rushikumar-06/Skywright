class_name CrewHand
extends Node
## A hired hand's brain, on the server, a child of his ship (spec §3.4). A gunner
## fires the cannon he mans at the nearest pirate in range, through the pirate
## captain's own aiming. A repairer puts out her fires, then mends her with her
## spares, through the same server path as a player's repair, walking to each job.
## Engineers need no brain: their ship drives her engines harder.
## ponytail: gunners only shoot pirates and repairers ignore shots; hands are never hit
## or knocked down, and wait for boarding (stage 9) to fight.

const THINK_EVERY := 0.5   ## s between a gunner's looks for a pirate.
const WALK := 4.0          ## m/s a repairer walks, straight through anything.
const SEARCH_EVERY := 1.0  ## s between a repairer's looks for work.
const TELL_EVERY := 0.5    ## s between telling everyone where a walking repairer is.
const MAX_HANDS := 64      ## The most hands a ship's list may hold.

var hand: Dictionary  ## His entry in his ship's hands.
var job: Variant      ## A repairer's cell to work at, or null.
var shots := 0        ## A gunner's shots fired.

var _sync: WorldSync
var _think_left := 0.0
var _search_left := 0.0
var _work_left := 0.0
var _tell_left := 0.0


func _init(world_sync: WorldSync, hand_entry: Dictionary) -> void:
	_sync = world_sync
	hand = hand_entry
	name = "Hand%d" % -int(hand["id"])


func _physics_process(delta: float) -> void:
	var ship := get_parent() as Ship
	if ship == null or _sync.id_of(ship) == 0:
		return
	match hand["role"]:
		"gunner":
			_think_left -= delta
			if _think_left <= 0.0:
				_think_left = THINK_EVERY
				_gun(ship)
		"repairer":
			_repair(ship, delta)


func _gun(ship: Ship) -> void:
	var cannon: Cannon = null
	for each in ship.cannons:
		if each.cell == hand["post"] and each.gunner == hand["id"]:
			cannon = each
	if cannon == null:
		return
	var target: Ship = null
	var nearest := PirateCaptain.FIRE_RANGE
	for other: Ship in _sync.ships.values():
		var d := other.global_position.distance_to(ship.global_position)
		if other.pirate and not other.is_wreck() and d < nearest:
			target = other
			nearest = d
	if target == null:
		return
	var ammo: String = PirateCaptain.VOLLEY[shots % PirateCaptain.VOLLEY.size()]
	if target.grid.cells_of("balloon").is_empty():
		ammo = "round"
	if PirateCaptain.fire_at(_sync, ship, cannon, target, ammo, _solid_middle(target)):
		shots += 1


## The block of target nearest her centre of mass: a ship's centre of mass can be in
## the open air between her deck and her envelope, where a shot passes through.
static func _solid_middle(target: Ship) -> Vector3i:
	var best := Vector3i.ZERO
	var best_distance := INF
	for cell: Vector3i in target.grid.blocks:
		var d := Vector3(cell).distance_squared_to(target.center_of_mass)
		if d < best_distance or (d == best_distance and cell < best):
			best = cell
			best_distance = d
	return best


func _repair(ship: Ship, delta: float) -> void:
	_search_left -= delta
	if job == null and _search_left <= 0.0:
		_search_left = SEARCH_EVERY
		job = Damage.next_job(ship.grid, ship.blueprint, ship.fires.keys(), hand["at"], ship.spares > 0)
	if job == null:
		return
	var at: Vector3 = hand["at"]
	var to := Vector3(job as Vector3i)
	if at.distance_to(to) > Damage.REPAIR_REACH:
		hand["at"] = at.move_toward(to, WALK * delta)
		_tell_left -= delta
		if _tell_left <= 0.0:
			_tell_left = TELL_EVERY
			_sync.tell_hands(ship)
		return
	_work_left -= delta
	if _work_left <= 0.0:
		_work_left = Damage.REPAIR_EVERY
		if not _sync.mend(ship, job):
			job = null


## Hands from the network or a save, [[id, name, role, post, at], …], as entries
## (see Ship.hands), or null when they make no sense for a ship of grid.
static func read_hands(data: Variant, grid: ShipGrid) -> Variant:
	if not data is Array or data.size() > MAX_HANDS:
		return null
	var room := grid.bounds().grow(WorldSync.CREW_REACH)
	var found: Array[Dictionary] = []
	for entry: Variant in data:
		if not entry is Array or entry.size() != 5:
			return null
		var id: Variant = entry[0]
		var hand_name: Variant = entry[1]
		var role: Variant = entry[2]
		var post: Variant = entry[3]
		var at: Variant = entry[4]
		if not id is int or id >= 0 or not hand_name is String or hand_name.is_empty() or hand_name.length() > ShipGrid.MAX_NAME \
				or not role is String or not Economy.HANDS.has(role) or not post is Vector3i or not ShipGrid.in_area(post) \
				or not at is Vector3 or not (at as Vector3).is_finite() or not room.has_point(at):
			return null
		found.append({"id": id, "name": hand_name, "role": role, "post": post, "at": at})
	return found


## ship's hands as the network carries them (see read_hands).
static func hand_list(ship: Ship) -> Array:
	return ship.hands.map(func(hand: Dictionary) -> Array: return [hand["id"], hand["name"], hand["role"], hand["post"], hand["at"]])
