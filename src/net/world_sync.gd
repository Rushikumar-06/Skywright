class_name WorldSync
extends Node
## Carries a world's traffic between the server and its clients (spec §4.6). One
## lives in each world, as World/Sync, so every world RPC arrives in one place to be
## checked.
##
## The server flies the ships. When a client's world has loaded it asks to enter;
## the server sends every ship (compressed blocks, paint, transform, pilot, captain,
## test flag, blueprint, pirate flag and spares) and from then on sends snapshots
## at 30 Hz. Clients keep frozen copies of the ships and draw them DELAY seconds in
## the past on the server's clock, along SnapshotBuffer curves, so late or lost
## packets don't show. Ships
## the server adds or removes mid-game are sent to everyone in the world; the
## World moves its player off a ship before it goes.
##
## Damage belongs to the server too. It applies each change to a ship's blocks and
## sends the same changes to everyone, who apply them to their copies; a ship with
## no blocks left is taken away. Pieces cut off from the helm's break away: each big
## enough is added as a wreck, nobody's, and smaller ones vanish. Once a second the
## server wears ships: the Roil grinds the blocks below its surface, a ship below
## LOST_ALTITUDE is lost (everyone hears she was), and wrecks go when they're old,
## too many or far from every player.
##
## Repairs belong to the server too. A player's repair action comes here aimed at a
## block of the ship they're aboard; within reach, it puts out the fires there, or
## else uses one of the ship's spares to heal the block or rebuild a lost one beside
## it. Fires burn once a second as the server wears ships, and docks fill the spares
## of the ships at them; everyone hears what burns and how many spares are left.
##
## Salvage belongs to the server too. A player's E by a world wreck, or by a wreck
## ship, comes here; within reach, a world wreck gives Damage.SALVAGE_SPARES once
## (everyone, late joiners too, learns she's stripped), and a wreck ship gives a
## spare per 10 blocks and is broken up. The spares go to the ship the salvager is
## aboard, else their own, else the home ship; with no room, nothing is taken. The
## salvager hears how many they got.
##
## Pirates belong to the server too. Every RAID_EVERY, a crewed ship away from the
## towns may draw a pirate, by her region's odds and up to its limit; a pirate is a
## ship built from PirateShip with a PirateCaptain aboard, here only, and clients
## see an ordinary ship flagged pirate. Pirates far from every player go when ships
## are worn.
##
## Shots belong to the server too. It fires them and tells everyone the launch, so
## every machine's Projectiles flies the same arc; it decides every hit and tells
## everyone where each shot ended. A shot into a ship damages the blocks it flies
## into (a shell bursts too, and a harpoon ties a rope); a player it hits, or who
## stands in a shell's burst, is knocked down: let go of every station, passed over
## by shots for KNOCKOUT_TIME, and told so. A shell's burst can set wood and cloth
## alight. ponytail: clients apply _blocks_changed
## as it arrives, up to DELAY before they draw the shot arriving; queue changes by
## time if holes opening early shows.
##
## Each player walks their own crew member and reports where it is in ship space
## at 30 Hz (spec §4.5), or in world space with ship id 0 while ashore. The server
## checks each report, stamps it with its own clock and passes it on. Everyone draws
## everyone else as a CrewAvatar, DELAY behind, on their ship as it's drawn.
##
## Stations belong to the server. A client's helm or cannon passes asks on here; the
## server gives the station to the asker only if they last said they were aboard and
## in reach, and tells everyone who holds it. The pilot's keys come here at 30 Hz. A
## gunner's shot comes here with its aim and ammunition, and the server fires it if
## they man that cannon and it's loaded.
##
## A player asks the server to launch a design, as a test flight or as their own
## ship, at most once a second. The server builds it whole at their slipway (or its
## test berth), raised clear of other ships, with them at its helm. There's one of
## each a player: a new test flight replaces the last, and a new ship replaces the
## old one, taking its crew.
##
## When someone leaves the roster, everyone forgets their crew member, and the
## server takes their ships away and frees their stations. A dedicated server
## anchors its ships while nobody is aboard, so they don't drift off in the wind
## for hours. A pilot can anchor a ship too, which holds it still until they weigh
## anchor.

signal ship_added(ship: Ship)
## ship has left ships and is about to be freed. Its crew board successor, if not null.
signal ship_removed(ship: Ship, successor: Ship)
## This machine's player was knocked down by a shot.
signal knocked_out
## This machine's player salvaged: the spares and crowns gained, both 0 for nothing
## left there.
signal salvage_result(spares: int, money: int)
## Server: peer's world has loaded, and they've been sent it.
signal peer_entered(peer: int)
## Client: the server's world has arrived, every ship in it added.
signal world_arrived

const SessionScript := preload("res://src/net/session.gd")
const SEND_EVERY := 2  ## Physics ticks between snapshots: 30 Hz at 60 ticks a second.
const DELAY := 0.1     ## Seconds in the past that clients draw what the server sent.
const CLOCK_EASE := 0.1  ## How far a client's clock moves toward each snapshot's time.
const CREW_REACH := 35.0     ## m. Crew reported further than this from their ship's blocks are refused.
const CREW_MAX_SPEED := 50.0 ## m/s. Likewise for crew reported moving faster.
const ASHORE_REACH := 11000.0  ## m. Crew ashore reported further than this from the centre are refused.
const ASHORE_CEILING := 5000.0 ## m. Likewise above this, or below 0.
const REACH_SLACK := 0.5     ## m. Allowance on the helm's reach for where a client last said it was.
const KEYS_GO_STALE := 0.25  ## s. A remote pilot's keys count as let go when none come for this long.
const LAUNCH_COOLDOWN := 1.0 ## s. The least time between one player's launches.
const CLEARANCE := 2.0       ## m. The least gap between a ship being launched and another ship.
const OBSTACLE_CLEARANCE := 1.0  ## m. Likewise between it and a dock or a town island.
const WEAR_EVERY := 1.0       ## s between the server's wearing of ships.
const WRECK_LIFETIME := 180.0 ## s a wreck lasts.
const MAX_WRECKS := 8         ## The most wrecks at once: the oldest go first.
const FAR := 3000.0           ## m. Wrecks further than this from every player go.
const LOST_ALTITUDE := 0.0    ## m. A ship whose origin sinks below this is lost to the Roil.
const KNOCKOUT_TIME := 5.0    ## s a player hit by a shot is down.
const MUZZLE := 0.8           ## m from a gun's cell to where its shot starts.
const RAID_EVERY := 30.0      ## s between the server's raids.
## By WorldGen.Region (Eye, Stormwall, Gale, Shattered, Calm, rim): the chance a raid
## sends a pirate at a crewed ship there, and the most pirates near her at once.
const RAID_CHANCE := [0.5, 0.5, 0.5, 0.5, 0.25, 0.0]
const RAID_LIMIT := [2, 2, 2, 2, 1, 0]
const RAID_NEAR := 2000.0     ## m. Pirates within this of a ship count toward her region's limit.
const MAX_PIRATES := 4        ## The most pirates in the world at once.
const SAFE := 1200.0          ## m. Ships this near a town's dock aren't raided.
const PIRATE_DISTANCE := 800.0  ## m from her target that a pirate comes in.
const ISLAND_CLEARANCE := 60.0  ## m between a pirate coming in and any island's edge.

var session: Node
var ships: Dictionary = {}  ## Ship id -> Ship.
var rng := RandomNumberGenerator.new()  ## The server's luck: fires catching and spreading. Tests seed it.
var player: PlayerController  ## This machine's player, whose crew it reports. Null when there's none.
var docks: Array[Vector3] = []            ## Where each town's slipway 0 is. Set by the World.
var wind: Wind                            ## The world's wind, which every ship feels. Likewise.
var gen: WorldGen                         ## The world's shape, for where pirates can come in. Likewise.
var sites: Array[Vector3] = []            ## The middle of each world wreck (WorldGen.wrecks' order). Likewise.
var salvaged: Dictionary = {}             ## World wreck index -> true, once she's stripped.
var ledger: Ledger                        ## The world's books. Set by the World.
## The world's shots and ropes. Likewise; the server hears their hits here.
var projectiles: Projectiles:
	set(value):
		projectiles = value
		projectiles.hit.connect(_on_shot_hit)
		projectiles.crew_hit.connect(_on_crew_hit)

var _time := 0.0            ## Seconds of physics since this world began.
var _offset := 0.0          ## Client: the server's clock minus ours.
var _synced := false        ## Client: _offset has been set.
var _tick := 0
var _next_id := 1
var _in_world: Dictionary = {}  ## Server: peers whose world has loaded (peer id -> true).
var _buffers: Dictionary = {}   ## Client: ship id -> SnapshotBuffer.
var _crew: Dictionary = {}      ## Other players' crew: peer id -> {"ship": id, "buffer": SnapshotBuffer, "at": Vector3, "pitch": float}.
var _avatars: Dictionary = {}   ## Peer id -> CrewAvatar.
var _keys_heard: Dictionary = {}  ## Server: ship id -> _time its pilot's keys last came.
var _my_launch_at := -INF  ## _time of this machine's last launch.
var _launched_at: Dictionary = {}  ## Server: peer id -> _time of their last launch.
var _next_shot := 1
var _next_rope := 1
var _down: Dictionary = {}  ## Server: peer id -> now() when they're back on their feet.
var _repaired_at: Dictionary = {}  ## Server: peer id -> now() of their last repair.
var _names: Dictionary = {}  ## Peer id -> their name, remembered after they leave.


func _init(world_session: Node) -> void:
	session = world_session
	name = "Sync"


func _ready() -> void:
	session.players_changed.connect(_on_roster_changed)
	ship_added.connect(func(_ship: Ship) -> void: _anchor_if_empty())
	if not session.is_server():
		_enter_world.rpc_id(1)


## Seconds since this world began on the server. Clients follow the server's clock.
func now() -> float:
	return _time + _offset


## Where the world must be loaded around: on the server every ship, everyone
## ashore and this machine's player, on a client this machine's player (nowhere
## until it's here).
func focus_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	if session.is_server():
		for ship: Ship in ships.values():
			points.append(ship.global_position)
		for heard: Dictionary in _crew.values():
			if heard["ship"] == 0:
				points.append(heard["at"])
	if player != null:
		points.append(player.world_position())
	return points


## How peer's crew member is drawn here, or null.
func avatar_of(peer: int) -> CrewAvatar:
	return _avatars.get(peer)


## Server: puts a new ship in the world, captain's (0 for nobody's), with pilot at
## its helm, and tells everyone in the world. As she is now is her blueprint, made
## whole. She carries a full load of spares, unless she's a pirate or a wreck.
func add_ship(grid: ShipGrid, at: Transform3D, captain := 0, test := false, pilot := 0, pirate := false) -> Ship:
	var id := _next_id
	_next_id += 1
	var spares := 0 if pirate or grid.cells_of("helm").is_empty() else Damage.SPARES_MAX
	var ship := _add(id, grid, at, true, captain, test, pilot, grid.whole(), pirate, spares)
	ship_added.emit(ship)
	var entry := _entry(id)
	for peer: int in _in_world:
		_ship_added.rpc_id(peer, _time, entry)
	return ship


## Server: takes ship out of the world, and tells everyone. Its crew board successor.
## lost: the Roil took her.
func remove_ship(ship: Ship, successor: Ship = null, lost := false) -> void:
	var id := id_of(ship)
	if id == 0:
		return
	for peer: int in _in_world:
		_ship_removed.rpc_id(peer, id, id_of(successor), lost)
	_remove(id, successor, lost)


## Server: puts hit-point changes (cell -> hit points, 0 for destroyed) into ship,
## tells everyone in the world, and takes her away if no blocks are left. When blocks
## were destroyed, the pieces no longer joined to her helm's break away: those of
## Damage.DEBRIS blocks or more as wrecks, moving as she moved there, the rest gone.
func damage_ship(ship: Ship, changes: Dictionary) -> void:
	var id := id_of(ship)
	if id == 0 or changes.is_empty():
		return
	var destroyed := changes.keys().any(func(cell: Vector3i) -> bool: return changes[cell] <= 0 and ship.grid.blocks.has(cell))
	ship.damage(changes)
	var sent := changes
	var pieces: Array[ShipGrid] = []
	if destroyed:
		var parts := Damage.split(ship.grid)
		sent = changes.duplicate()
		var debris := {}
		for cell: Vector3i in parts["debris"]:
			debris[cell] = 0
		ship.damage(debris)
		sent.merge(debris, true)
		for cells: Array in parts["wrecks"]:
			for cell: Vector3i in cells:
				sent[cell] = 0  # clients drop them, and get the wreck as a new ship
			pieces.append(ship.take_cells(cells))
	var packed := Damage.pack(sent)
	for peer: int in _in_world:
		_blocks_changed.rpc_id(peer, id, packed)
	for piece in pieces:
		var wreck := add_ship(piece, ship.global_transform)
		wreck.calm = ship.calm
		wreck.linear_velocity = ship.point_velocity(wreck.global_transform * wreck.center_of_mass)
		wreck.angular_velocity = ship.angular_velocity
	if ship.grid.blocks.is_empty():
		remove_ship(ship)


## Server: stows cargo (see ShipGrid.cargo) aboard ship, and tells everyone in the world.
func set_cargo(ship: Ship, cargo: Dictionary) -> void:
	ship.set_cargo(cargo)
	tell_world(&"_cargo", [id_of(ship), ship.grid.cargo_list()])


## ship's id, or 0 if it isn't in this world.
func id_of(ship: Ship) -> int:
	var id: Variant = ships.find_key(ship)
	return id if id != null else 0


## This machine's player launches grid: as a test flight when test, else as their
## own ship in place of the old one, from the dock of town (an index into docks).
## The server decides. False when it's too soon after the last one, which the server
## would ignore.
func launch(grid: ShipGrid, test: bool, town := 0) -> bool:
	if _time - _my_launch_at < LAUNCH_COOLDOWN:
		return false
	_my_launch_at = _time
	if session.is_server():
		_launch_for(multiplayer.get_unique_id(), grid, test, town)
	else:
		_launch.rpc_id(1, grid.to_bytes(), grid.paint_names(), test, town)
	return true


## This machine's player ends their test flight.
func end_test() -> void:
	if session.is_server():
		remove_ship(ship_of(multiplayer.get_unique_id(), true))
	else:
		_end_test.rpc_id(1)


## peer's test flight when test, else their own ship; null when they have none.
func ship_of(peer: int, test: bool) -> Ship:
	for ship: Ship in ships.values():
		if ship.captain == peer and ship.test == test:
			return ship
	return null


## Where peer's test flights start when test, else where their ships are built, at
## town's dock: at the slipway for their place in the roster, after a dedicated
## server's own.
func berth_of(peer: int, test: bool, town := 0) -> Transform3D:
	var index: int = maxi(0, session.players.keys().find(peer)) + (1 if session.dedicated else 0)
	return Dock.test_berth(docks[town], index) if test else Dock.slipway(docks[town], index)


## The ship to board when there's no other reason to pick one: the host's (captain
## 1), else nobody's (a dedicated server's), else anyone's, a test flight last; never
## a wreck or a pirate.
func home_ship() -> Ship:
	var home: Ship = null
	var best := 4
	for ship: Ship in ships.values():
		if ship.is_wreck() or ship.pirate:
			continue
		var rank := 3 if ship.test else 0 if ship.captain == 1 else 1 if ship.captain == 0 else 2
		if rank < best:
			home = ship
			best = rank
	return home


## Server: the ships someone is aboard, by this machine's player or a remote
## player's last report.
func crewed_ships() -> Array[Ship]:
	var crewed: Array[Ship] = []
	if player != null and player.ship != null and id_of(player.ship) != 0:
		crewed.append(player.ship)
	for heard: Dictionary in _crew.values():
		var ship: Ship = ships.get(heard["ship"])
		if ship != null and not crewed.has(ship):
			crewed.append(ship)
	return crewed


## Server: where every player is in the world, aboard or ashore (in the air too):
## this machine's player where they are, and the others at their ship, or where they
## last said they were ashore.
func player_positions() -> Array[Vector3]:
	var points: Array[Vector3] = []
	if player != null:
		points.append(player.world_position())
	for heard: Dictionary in _crew.values():
		if heard["ship"] == 0:
			points.append(heard["at"])
		elif ships.has(heard["ship"]):
			points.append((ships[heard["ship"]] as Ship).global_position)
	return points


## Server: fires ammo from ship's cell along direction (ship space, a unit vector),
## tells everyone, and returns the shot's id (0 when it can't). The shot keeps the
## ship's motion there.
func fire(ship: Ship, cell: Vector3i, direction: Vector3, ammo: String) -> int:
	var ship_id := id_of(ship)
	if not session.is_server() or ship_id == 0 or not Damage.AMMO.has(ammo) or projectiles == null:
		return 0
	var origin := ship.global_transform * (Vector3(cell) + direction * MUZZLE)
	var velocity := ship.point_velocity(origin) + ship.global_basis * direction * float(Damage.AMMO[ammo]["speed"])
	var id := _next_shot
	_next_shot += 1
	projectiles.launch(id, ammo, origin, velocity, now(), ship_id)
	projectiles.shots[id]["cell"] = cell
	tell_world(&"_fired", [id, Damage.AMMO.keys().find(ammo), origin, velocity, now(), ship_id])
	return id


## Server: fires cannon of ship as it's aimed and loaded, and starts its reload.
## Returns the shot's id, or 0 while it's reloading or when it can't fire.
func fire_cannon(ship: Ship, cannon: Cannon) -> int:
	if not session.is_server() or cannon.reload_left > 0.0 or ship.grid.type_at(cannon.cell) != "cannon":
		return 0
	cannon.reload_left = Cannon.RELOAD
	return fire(ship, cannon.cell, cannon.direction(), cannon.ammo)


## This machine's player's repair action, aimed at cell of ship (which they're
## aboard). The server decides.
func repair(ship: Ship, cell: Vector3i) -> void:
	if session.is_server():
		_repair_for(multiplayer.get_unique_id(), ship, cell)
	elif id_of(ship) != 0:
		_repair.rpc_id(1, id_of(ship), cell)


## Server: peer's repair action at cell of ship. They must be aboard her, within
## reach of it, and not have repaired in the last Damage.REPAIR_EVERY. It puts out the
## fires around cell, free; with none, it uses a spare to heal or rebuild a block.
func _repair_for(peer: int, ship: Ship, cell: Vector3i) -> void:
	var id := id_of(ship)
	var standing: Variant = null  # where they are in her space
	if peer == multiplayer.get_unique_id():
		if player != null and player.ship == ship:
			standing = player.crew.position
	elif _crew.has(peer) and _crew[peer]["ship"] == id:
		standing = _crew[peer]["at"]
	if id == 0 or standing == null:
		return
	if (standing as Vector3).distance_to(Vector3(cell)) > Damage.REPAIR_REACH + CrewMember.EYE_HEIGHT + REACH_SLACK:
		return
	if now() - _repaired_at.get(peer, -INF) < Damage.REPAIR_EVERY - 0.05:
		return
	_repaired_at[peer] = now()
	if Damage.put_out(ship.fires, cell):
		_send_fires(ship)
		return
	if ship.spares < 1:
		return
	var changes := Damage.repair(ship.grid, ship.blueprint, cell)
	if changes.is_empty():
		return
	ship.spares -= 1
	damage_ship(ship, changes)
	tell_world(&"_spares", [id, ship.spares])


## Server: draws ship's fires here, and tells everyone in the world what's burning.
func _send_fires(ship: Ship) -> void:
	var cells := ship.fires.keys()
	cells.sort()
	ship.show_fires(cells)
	tell_world(&"_fires", [id_of(ship), _fire_bytes(ship)])


## What ship has burning, as the network carries it: 3 bytes a cell.
static func _fire_bytes(ship: Ship) -> PackedByteArray:
	var bytes := PackedByteArray()
	for cell in ship.burning:
		bytes.append_array([cell.x + 64, cell.y + 64, cell.z + 64])
	return bytes


## Server: where everyone not knocked down is in the world: peer id -> this
## machine's player where they are, and the others where they last said they were.
func crew_positions() -> Dictionary:
	var found := {}
	if player != null:
		found[multiplayer.get_unique_id()] = player.world_position()
	for peer: int in _crew:
		var heard: Dictionary = _crew[peer]
		if heard["ship"] == 0:
			found[peer] = heard["at"]
		elif ships.has(heard["ship"]):
			found[peer] = (ships[heard["ship"]] as Ship).global_transform * (heard["at"] as Vector3)
	for peer: int in found.keys():
		if _down.get(peer, -INF) > now():
			found.erase(peer)
	return found


## This machine's player salvages world wreck index (into sites). The server decides.
func salvage_site(index: int) -> void:
	if session.is_server():
		_salvage_for(multiplayer.get_unique_id(), "site", index)
	else:
		_salvage.rpc_id(1, "site", index)


## This machine's player breaks up wreck for spares. The server decides.
func salvage_ship(wreck: Ship) -> void:
	if session.is_server():
		_salvage_for(multiplayer.get_unique_id(), "ship", id_of(wreck))
	else:
		_salvage.rpc_id(1, "ship", id_of(wreck))


## Server: peer salvages world wreck index (kind "site") or wreck ship index (kind
## "ship"), if they last said they were in reach of her. Anything else is ignored.
func _salvage_for(peer: int, kind: String, index: int) -> void:
	var where: Variant = world_position_of(peer)
	if where == null:
		return
	var at: Vector3 = where
	var spares := 0
	var money := 0
	var wreck: Ship = null
	if kind == "site":
		if index < 0 or index >= sites.size() or at.distance_to(sites[index]) > Damage.SITE_REACH + REACH_SLACK:
			return
		if not salvaged.has(index):
			spares = Damage.SALVAGE_SPARES
			money = Economy.SALVAGE_MONEY
	elif kind == "ship":
		wreck = ships.get(index)
		if wreck == null or not wreck.is_wreck() or wreck.captain != 0 \
				or not (wreck.global_transform * wreck.bounds).grow(Damage.SALVAGE_REACH + REACH_SLACK).has_point(at):
			return
		spares = ceili(wreck.grid.blocks.size() / 10.0)
		money = wreck.grid.blocks.size() * Economy.SCRAP_MONEY
	else:
		return
	var gained := 0
	if money > 0:
		var to := _salvage_goes_to(peer)
		gained = clampi(Damage.SPARES_MAX - to.spares, 0, spares) if to != null else 0
		if gained > 0:
			to.spares += gained
			tell_world(&"_spares", [id_of(to), to.spares])
		if wreck != null:
			remove_ship(wreck)
		else:
			salvaged[index] = true
			tell_world(&"_salvaged", [index])
		if ledger != null:
			ledger.pay(peer, money)
	if peer == multiplayer.get_unique_id():
		salvage_result.emit(gained, money)
	else:
		_salvage_result.rpc_id(peer, gained, money)


## peer's name: from the roster, or as it was when they left ("" for nobody known).
func name_of(peer: int) -> String:
	if session.players.has(peer):
		_names[peer] = session.players[peer]["name"]
	return _names.get(peer, "")


## Whether peer is this machine's player, or (server) a peer whose world has loaded.
func in_world(peer: int) -> bool:
	return (peer == multiplayer.get_unique_id() and player != null) or _in_world.has(peer)


## The town whose dock p is near, or -1.
func town_at(p: Vector3) -> int:
	for i in docks.size():
		if Dock.near(docks[i], p):
			return i
	return -1


## Server: the ship peer is aboard (as they last said), or null.
func aboard(peer: int) -> Ship:
	var ship: Ship = null
	if peer == multiplayer.get_unique_id():
		ship = player.ship if player != null else null
	elif _crew.has(peer):
		ship = ships.get(_crew[peer]["ship"])
	return ship if id_of(ship) != 0 else null


## Server: where peer last was in the world, or null when they're nowhere.
func world_position_of(peer: int) -> Variant:
	if peer == multiplayer.get_unique_id():
		return player.world_position() if player != null else null
	if not _crew.has(peer):
		return null
	var heard: Dictionary = _crew[peer]
	if heard["ship"] == 0:
		return heard["at"]
	return (ships[heard["ship"]] as Ship).global_transform * (heard["at"] as Vector3) if ships.has(heard["ship"]) else null


## Server: the ship peer's salvage goes to: the one they're aboard if she isn't a
## wreck, else their own, else the home ship; or null.
func _salvage_goes_to(peer: int) -> Ship:
	var on := aboard(peer)
	if on != null and not on.is_wreck():
		return on
	var own := ship_of(peer, false)
	return own if own != null else home_ship()


## Server: a pirate comes in PIRATE_DISTANCE from near, at her height (kept between
## PirateCaptain.MIN_ALTITUDE and 1,600 m), facing her, from the first of 8 ways round
## (from a random one) clear of every island. Returns the pirate, or null when no
## way is clear.
func spawn_pirate(near: Ship) -> Ship:
	if not session.is_server():
		return null
	var from := rng.randf() * TAU
	for i in 8:
		var angle := from + i * TAU / 8.0
		var spot := near.global_position + Vector3(cos(angle), 0.0, sin(angle)) * PIRATE_DISTANCE
		spot.y = clampf(near.global_position.y, PirateCaptain.MIN_ALTITUDE, 1600.0)
		if not _clear_of_islands(spot):
			continue
		var facing := Basis.looking_at(Vector3(near.global_position.x - spot.x, 0.0, near.global_position.z - spot.z))
		var pirate := add_ship(PirateShip.build(), Transform3D(facing, spot), 0, false, 0, true)
		pirate.add_child(PirateCaptain.new(self))
		return pirate
	return null


## Whether spot is ISLAND_CLEARANCE clear of every island near it, towns' too.
func _clear_of_islands(spot: Vector3) -> bool:
	if gen == null:
		return true
	var islands: Array[Dictionary] = []
	var center := WorldGen.chunk_of(spot)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			islands.append_array(gen.islands_in(center + Vector2i(dx, dz)))
	for town: Dictionary in gen.towns:
		islands.append(town["island"])
	return islands.all(func(island: Dictionary) -> bool:
		var to := spot - (island["at"] as Vector3)
		return Vector2(to.x, to.z).length() >= island["radius"] + ISLAND_CLEARANCE)


## Server, every RAID_EVERY when the session has pirates: each crewed ship (not a
## pirate, wreck or test flight) more than SAFE from every dock may draw a pirate, by
## her region's RAID_CHANCE, while fewer than its RAID_LIMIT are within RAID_NEAR of
## her and fewer than MAX_PIRATES are about.
func _raid() -> void:
	if not session.is_server() or not session.pirates:
		return
	for ship in crewed_ships():
		if ship.pirate or ship.is_wreck() or ship.test:
			continue
		var here := ship.global_position
		if docks.any(func(dock: Vector3) -> bool: return dock.distance_to(here) <= SAFE):
			continue
		var region := WorldGen.region_at(here)
		var raiders := ships.values().filter(func(other: Ship) -> bool: return other.pirate and not other.is_wreck())
		var near := raiders.filter(func(other: Ship) -> bool: return other.global_position.distance_to(here) <= RAID_NEAR)
		if near.size() >= RAID_LIMIT[region] or raiders.size() >= MAX_PIRATES:
			continue
		if rng.randf() < RAID_CHANCE[region]:
			spawn_pirate(ship)


## Server: calls method with args on every client in the world.
func tell_world(method: StringName, args: Array) -> void:
	for peer: int in _in_world:
		rpc_id.callv([peer, method] + args)


## Server: shot hit collider at point, flying along direction. A ship loses the
## blocks it flew into (a shell then bursts among them, and a harpoon whose block
## held ties a rope from the gun to it). Anything else just ends it.
func _on_shot_hit(shot: Dictionary, collider: Object, point: Vector3, direction: Vector3) -> void:
	var ammo: String = shot["ammo"]
	var spec: Dictionary = Damage.AMMO[ammo]
	var target := collider as Ship
	if target != null and id_of(target) != 0:
		var p := target.global_transform.affine_inverse() * point
		var d := (target.global_basis.inverse() * direction).normalized()
		var first := target.grid.cells_along(p - d * 0.01, d)
		damage_ship(target, Damage.shot(target.grid, p - d * 0.01, d, ammo))
		if spec["blast"] > 0.0:
			var burst := Damage.blast(target.grid, p, spec["blast"], spec["blast_damage"])
			damage_ship(target, burst)
			if id_of(target) != 0:
				var lit := target.fires.size()
				Damage.ignite(target.grid, target.fires, burst.keys(), rng)
				if target.fires.size() != lit:
					_send_fires(target)
		var shooter: Ship = ships.get(shot["ship"])
		if ammo == "harpoon" and not first.is_empty() and shooter != null and id_of(target) != 0 \
				and target.grid.blocks.has(first[0]["cell"]):
			var cell: Vector3i = first[0]["cell"]
			var from := shooter.global_transform * Vector3(shot["cell"])
			var length := maxf(Projectiles.TETHER_MIN, from.distance_to(target.global_transform * Vector3(cell)))
			var rope := _next_rope
			_next_rope += 1
			projectiles.tie(rope, shooter, shot["cell"], target, cell, length)
			tell_world(&"_tether", [rope, shot["ship"], shot["cell"], id_of(target), cell, length])
	_burst_on_crew(shot, point)
	tell_world(&"_hit", [shot["id"], point, shot["ends"]])


## Server: shot hit peer's crew member at point.
func _on_crew_hit(shot: Dictionary, peer: int, point: Vector3) -> void:
	_knock_out(peer)
	_burst_on_crew(shot, point)
	tell_world(&"_hit", [shot["id"], point, shot["ends"]])


## Server: a shell bursting at point knocks down everyone within its blast.
func _burst_on_crew(shot: Dictionary, point: Vector3) -> void:
	var blast: float = Damage.AMMO[shot["ammo"]]["blast"]
	if blast <= 0.0:
		return
	var crew := crew_positions()
	for peer: int in crew:
		if (crew[peer] as Vector3).distance_to(point) <= blast:
			_knock_out(peer)


## Server: peer is knocked down: they let go of every station, shots pass them by
## for KNOCKOUT_TIME, and they're told.
func _knock_out(peer: int) -> void:
	_down[peer] = now() + KNOCKOUT_TIME
	for ship: Ship in ships.values():
		ship.release(peer)
	if peer == multiplayer.get_unique_id():
		knocked_out.emit()
	elif _in_world.has(peer):
		_knocked_out.rpc_id(peer)


## Server, every WEAR_EVERY: the Roil wears every ship's blocks below its surface,
## and a ship whose origin is below LOST_ALTITUDE is lost. Then each ship's fires burn
## for a second, ships at a town's dock (not pirates or wrecks) get their spares
## filled, and wrecks (nobody's, without a helm) go when older than WRECK_LIFETIME or
## further than FAR from every player (all of them when there are no players), then
## the oldest while there are more than MAX_WRECKS. Pirates far from every player go too.
func _wear() -> void:
	for ship: Ship in ships.values():
		if id_of(ship) == 0:
			continue
		damage_ship(ship, Damage.roil(ship.grid, ship.global_transform))
		if id_of(ship) != 0 and ship.global_position.y < LOST_ALTITUDE:
			remove_ship(ship, null, true)
	for ship: Ship in ships.values():
		if ship.fires.is_empty() or id_of(ship) == 0:
			continue
		damage_ship(ship, Damage.burn(ship.grid, ship.fires, rng))
		var cells: Array[Vector3i] = []
		cells.assign(ship.fires.keys())
		cells.sort()
		if id_of(ship) != 0 and cells != ship.burning:
			_send_fires(ship)
	var players := player_positions()
	var wrecks: Array[Ship] = []
	for ship: Ship in ships.values():
		var far := players.all(func(at: Vector3) -> bool: return at.distance_to(ship.global_position) > FAR)
		if ship.pirate and not ship.is_wreck() and far:
			remove_ship(ship)
			continue
		if not ship.is_wreck() or ship.captain != 0:
			continue
		if now() - ship.born > WRECK_LIFETIME or far:
			remove_ship(ship)
		else:
			wrecks.append(ship)
	wrecks.sort_custom(func(a: Ship, b: Ship) -> bool: return a.born < b.born or (a.born == b.born and id_of(a) < id_of(b)))
	for i in wrecks.size() - MAX_WRECKS:
		remove_ship(wrecks[i])


## Adds a ship. The pilot is set before the helm's signals are connected, so it
## doesn't go out as a change.
func _add(id: int, grid: ShipGrid, at: Transform3D, simulated: bool, captain: int, test: bool, pilot: int,
		blueprint: ShipGrid, pirate: bool, spares: int) -> Ship:
	var ship := Ship.new(grid)
	ship.name = "Ship%d" % id
	ship.simulated = simulated
	ship.transform = at
	ship.captain = captain
	ship.test = test
	ship.weather = wind
	ship.blueprint = blueprint
	ship.pirate = pirate
	ship.spares = spares
	ship.born = now()
	ships[id] = ship
	get_parent().add_child(ship)
	if ship.helm != null:
		ship.helm.pilot = pilot
		ship.helm.asked.connect(_on_asked.bind(id))
		ship.helm.pilot_changed.connect(_on_pilot_changed.bind(id))
	for cannon in ship.cannons:
		cannon.asked.connect(_on_cannon_asked.bind(id, cannon.cell))
		cannon.gunner_changed.connect(_on_gunner_changed.bind(id, cannon))
		cannon.fire_asked.connect(_on_fire_asked.bind(id, cannon))
	return ship


## Takes ship id out of the world, with everyone's crew on it, after the World has
## moved its player off. lost: the Roil took her.
func _remove(id: int, successor: Ship, lost := false) -> void:
	var ship: Ship = ships[id]
	ship.lost = lost
	ships.erase(id)
	_buffers.erase(id)
	_keys_heard.erase(id)
	for peer: int in _crew.keys():
		if _crew[peer]["ship"] == id:
			_forget_crew(peer)
	ship_removed.emit(ship, successor if id_of(successor) != 0 else null)
	get_parent().remove_child(ship)
	ship.queue_free()


## Server: builds grid for peer, whole, at their berth in town with them at its helm.
## It replaces their test flight, and their own ship too unless it's a test flight.
func _launch_for(peer: int, grid: ShipGrid, test: bool, town: int) -> void:
	if _time - _launched_at.get(peer, -INF) < LAUNCH_COOLDOWN:
		return
	_launched_at[peer] = _time
	var built := ShipDesign.new(grid).grid  # new ships are built whole
	var trial := ship_of(peer, true)
	var own := ship_of(peer, false)
	# A test flight leaves your own ship where it is, so keep clear of it.
	var at := _clear_spot(built, berth_of(peer, test, town), [trial] if test else [trial, own], town)
	var ship := add_ship(built, at, peer, test, peer)
	if trial != null:
		remove_ship(trial, ship)
	if own != null and not test:
		remove_ship(own, ship)


## at, raised until grid's box there is OBSTACLE_CLEARANCE clear of town's dock and
## island, and CLEARANCE clear of every ship but those in ignoring. After 20 spots it
## settles for the last.
func _clear_spot(grid: ShipGrid, at: Transform3D, ignoring: Array, town: int) -> Transform3D:
	var fixed := Dock.obstacles(docks[town])
	var ships: Array[AABB] = []
	for ship: Ship in self.ships.values():
		if not ignoring.has(ship):
			ships.append(ship.global_transform * ship.bounds)
	for _spot in 19:
		var box := at * grid.bounds()
		var near := box.grow(CLEARANCE)
		if not fixed.any(func(other: AABB) -> bool: return box.grow(OBSTACLE_CLEARANCE).intersects(other)) \
				and not ships.any(func(other: AABB) -> bool: return near.intersects(other)):
			break
		at = at.translated(Vector3(0.0, box.size.y + CLEARANCE, 0.0))
	return at


## A ship as the network carries it: [id, blocks, paint, transform, pilot, captain,
## test, blueprint, pirate, spares, cargo].
func _entry(id: int) -> Array:
	var ship: Ship = ships[id]
	return [id, ship.grid.to_bytes(), ship.grid.paint_names(), ship.global_transform,
			ship.helm.pilot if ship.helm else 0, ship.captain, ship.test, ship.blueprint.to_bytes(), ship.pirate, ship.spares,
			ship.grid.cargo_list()]


## Forgets everyone no longer on the roster, and frees the stations they held.
func _on_roster_changed() -> void:
	for peer: int in session.players:
		name_of(peer)  # remember it, for after they leave
	for peer: int in _in_world.keys():
		if not session.players.has(peer):
			_in_world.erase(peer)
	for peer: int in _crew.keys():
		if not session.players.has(peer):
			_forget_crew(peer)
	# Taking ships away and freeing stations tell everyone, so wait for the end of
	# the frame: others may have left in the same poll, and their connections are
	# already gone.
	_let_leavers_go.call_deferred()
	_anchor_if_empty()


## Stops drawing peer's crew member.
func _forget_crew(peer: int) -> void:
	_crew.erase(peer)
	if _avatars.has(peer):
		(_avatars[peer] as CrewAvatar).queue_free()
		_avatars.erase(peer)


## Server: takes away the ships of anyone no longer on the roster, and frees the
## stations they held.
func _let_leavers_go() -> void:
	if not session.is_server():
		return
	for ship: Ship in ships.values():
		if ship.captain != 0 and not session.players.has(ship.captain):
			remove_ship(ship)
			continue
		if ship.helm != null and ship.helm.pilot != 0 and not session.players.has(ship.helm.pilot):
			ship.helm.leave(ship.helm.pilot)
		for cannon in ship.cannons:
			if cannon.gunner != 0 and not session.players.has(cannon.gunner):
				cannon.leave(cannon.gunner)


## Server: holds every ship still, engines stopped, while nobody is aboard, and
## never lets go of an anchored one.
func _anchor_if_empty() -> void:
	if not session.is_server():
		return
	var anchor: bool = session.players.is_empty()
	for ship: Ship in ships.values():
		if anchor and not ship.freeze:
			ship.linear_velocity = Vector3.ZERO
			ship.angular_velocity = Vector3.ZERO
		if anchor:
			ship.throttle = 0.0
			ship.rudder = 0.0
			if ship.helm != null:
				ship.helm.autopilot = false
		ship.freeze = anchor or ship.anchored


## Client: a helm here was asked for something; the server decides.
func _on_asked(what: String, on: bool, id: int) -> void:
	_request.rpc_id(1, id, what, on)


## Server: tell everyone who has the helm now.
func _on_pilot_changed(id: int) -> void:
	if session.is_server():
		for peer: int in _in_world:
			_pilot.rpc_id(peer, id, (ships[id] as Ship).helm.pilot)


## Client: a cannon here was asked to be manned or left; the server decides.
func _on_cannon_asked(on: bool, id: int, cell: Vector3i) -> void:
	_man.rpc_id(1, id, cell, on)


## Server: tell everyone who mans cannon of ship id now.
func _on_gunner_changed(id: int, cannon: Cannon) -> void:
	if session.is_server():
		tell_world(&"_gunner", [id, cannon.cell, cannon.gunner])


## This machine's player fires cannon of ship id: the server fires it; a client
## sends the aim and ammunition to the server, and starts its own reload for the HUD.
func _on_fire_asked(id: int, cannon: Cannon) -> void:
	if session.is_server():
		fire_cannon(ships[id], cannon)
		return
	_fire.rpc_id(1, id, cannon.cell, cannon.aim_yaw, cannon.aim_pitch, Damage.AMMO.keys().find(cannon.ammo))
	cannon.reload_left = Cannon.RELOAD


## The cannon at cell of ship ship_id, or null. Either may have come from another machine.
func _cannon_at(ship_id: Variant, cell: Variant) -> Cannon:
	if not ship_id is int or not ships.has(ship_id) or not cell is Vector3i:
		return null
	for cannon in (ships[ship_id] as Ship).cannons:
		if cannon.cell == cell:
			return cannon
	return null


func _physics_process(delta: float) -> void:
	if session.mode == SessionScript.Mode.NONE:
		return  # the session has just ended, and this world goes next
	if wind != null:
		wind.time = now()  # before the ships fly, so storms are where everyone sees them
	var sending := _tick % SEND_EVERY == 0
	_tick += 1
	var mine := _my_crew() if sending else []
	if session.is_server():
		# Stamp snapshots before the clock ticks on: they hold the ships as the last
		# physics step left them, which is where they were at _time.
		_let_go_of_stale_keys()
		if _tick % roundi(WEAR_EVERY * Engine.physics_ticks_per_second) == 0:
			_wear()
		if _tick % roundi(RAID_EVERY * Engine.physics_ticks_per_second) == 0:
			_raid()
		if sending and not _in_world.is_empty():
			var states := _ship_states()
			for peer: int in _in_world:
				_ships.rpc_id(peer, _time, states)
				if not mine.is_empty():
					_crew_moved.rpc_id(peer, multiplayer.get_unique_id(), mine[0], _time, mine[1], mine[2], mine[3], mine[4])
		_time += delta
		return
	if not mine.is_empty():
		_crew_report.rpc_id(1, mine[0], mine[1], mine[2], mine[3], mine[4])
		var helm := player.ship.helm if player.ship != null else null
		if helm != null and helm.pilot == multiplayer.get_unique_id():
			_helm_keys.rpc_id(1, mine[0], helm.throttle_input, helm.rudder_input, helm.climb_input)
	_time += delta
	var shown_at := now() - DELAY
	for id: int in _buffers:
		var at: Dictionary = (_buffers[id] as SnapshotBuffer).sample(shown_at)
		(ships[id] as Ship).global_transform = Transform3D(Basis(at["rotation"] as Quaternion), at["position"])


## Server: a remote pilot whose keys stop coming (a hung game, dead Wi-Fi) has let
## go of them. Their connection only counts as lost after Session.DROP_AFTER, and
## until then their last keys would keep steering.
func _let_go_of_stale_keys() -> void:
	for id: int in ships:
		var helm := (ships[id] as Ship).helm
		if helm == null or helm.pilot == 0 or helm.pilot == multiplayer.get_unique_id():
			continue
		if _time - _keys_heard.get(id, -INF) > KEYS_GO_STALE:
			helm.throttle_input = 0.0
			helm.rudder_input = 0.0
			helm.climb_input = 0.0


## Places the other players' avatars on their ships, as those are drawn, or in the
## world while they're ashore.
func _process(_delta: float) -> void:
	var shown_at := now() + Engine.get_physics_interpolation_fraction() / Engine.physics_ticks_per_second - DELAY
	for peer: int in _avatars:
		var heard: Dictionary = _crew[peer]
		var at := (heard["buffer"] as SnapshotBuffer).sample(shown_at)
		var place := Transform3D.IDENTITY if heard["ship"] == 0 else (ships[heard["ship"]] as Ship).get_global_transform_interpolated()
		var avatar: CrewAvatar = _avatars[peer]
		avatar.global_transform = place * Transform3D(Basis(at["rotation"] as Quaternion), at["position"])
		avatar.look(heard["pitch"])


## This machine's crew member as [ship id, position, velocity, yaw, pitch] (ship id
## 0 and world space ashore), or [].
func _my_crew() -> Array:
	if player == null:
		return []
	var crew := player.crew
	if crew.ship == null:
		return [0, crew.position, crew.velocity, crew.look_yaw, player.look_pitch]
	var id := id_of(crew.ship)
	if id == 0:
		return []
	return [id, crew.position, crew.velocity, crew.look_yaw, player.look_pitch]


## Records where peer's crew member was at time, and gives them an avatar.
func _hear_crew(peer: int, ship_id: int, time: float, position: Vector3, velocity: Vector3, yaw: float, pitch: float) -> void:
	var heard: Dictionary = _crew.get(peer, {})
	if heard.get("ship") != ship_id:
		heard = {"ship": ship_id, "buffer": SnapshotBuffer.new(), "at": position, "pitch": 0.0}
		_crew[peer] = heard
	# ponytail: two reports heard in one frame share a time, and the second is
	# dropped. The next comes 33 ms later; stamp on the sender's clock if it shows.
	(heard["buffer"] as SnapshotBuffer).push(time, position, velocity, Quaternion(Vector3.UP, wrapf(yaw, -PI, PI)))
	heard["at"] = position
	heard["pitch"] = clampf(pitch, -1.5, 1.5)
	if not _avatars.has(peer):
		var avatar := CrewAvatar.new(session.players[peer]["name"])
		avatar.name = "Crew%d" % peer
		_avatars[peer] = avatar
		get_parent().add_child(avatar)


## Each ship as [id, position, rotation, velocity, spin, throttle, rudder, trim,
## autopilot, target_heading, target_altitude, anchored].
func _ship_states() -> Array:
	var states := []
	for id: int in ships:
		var ship: Ship = ships[id]
		var helm := ship.helm
		states.append([id, ship.global_position, ship.global_basis.get_rotation_quaternion(), ship.linear_velocity,
				ship.angular_velocity, ship.throttle, ship.rudder, ship.trim, helm != null and helm.autopilot,
				helm.target_heading if helm else 0.0, helm.target_altitude if helm else 0.0, ship.anchored])
	return states


## Client: moves our clock toward the server's, from a time it just sent.
func _hear_clock(server_time: float) -> void:
	var offset := server_time - _time
	# ponytail: packets arrive a little late, by a varying amount, so each only
	# nudges the clock. Estimate the round trip if drawing ever looks behind.
	_offset = lerpf(_offset, offset, CLOCK_EASE) if _synced else offset
	_synced = true


# --- RPCs. Everything received is checked: it came from another machine. ---

## Client -> server: my world has loaded; send me the ships.
@rpc("any_peer", "call_remote", "reliable", 0)
func _enter_world() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not session.is_server() or not session.players.has(peer) or _in_world.has(peer):
		return
	_in_world[peer] = true
	_world.rpc_id(peer, _time, ships.keys().map(_entry), salvaged.keys())
	for id: int in ships:
		var ship: Ship = ships[id]
		for cannon in ship.cannons:
			if cannon.gunner != 0:
				_gunner.rpc_id(peer, id, cannon.cell, cannon.gunner)
		if not ship.burning.is_empty():
			_fires.rpc_id(peer, id, _fire_bytes(ship))
	peer_entered.emit(peer)


## Server -> client: the server's clock, every ship, as entries (see _entry), and the
## world wrecks already stripped. Every ship is added before ship_added fires for
## any, so home_ship() is right.
@rpc("authority", "call_remote", "reliable", 0)
func _world(time: Variant, entries: Variant, stripped: Variant) -> void:
	if session.is_server() or not _is_time(time) or not entries is Array or not stripped is Array:
		return
	_hear_clock(time)
	for index: Variant in stripped:
		if index is int and index >= 0 and index < sites.size():
			salvaged[index] = true
	var added: Array[Ship] = []
	for entry: Variant in entries:
		var ship := _add_entry(entry, time)
		if ship != null:
			added.append(ship)
	for ship in added:
		ship_added.emit(ship)
	world_arrived.emit()


## Server -> clients: a ship added mid-game, as an entry (see _entry), at time.
@rpc("authority", "call_remote", "reliable", 0)
func _ship_added(time: Variant, entry: Variant) -> void:
	if session.is_server() or not _is_time(time):
		return
	var ship := _add_entry(entry, time)
	if ship != null:
		ship_added.emit(ship)


## Server -> clients: ship id is gone, lost to the Roil or not. Its crew board ship
## successor (0 for none).
@rpc("authority", "call_remote", "reliable", 0)
func _ship_removed(id: Variant, successor: Variant, lost: Variant) -> void:
	if session.is_server() or not id is int or not successor is int or not lost is bool or not ships.has(id):
		return
	_remove(id, ships.get(successor), lost)


## Client: adds the ship an entry describes, drawn from time on, or returns null
## when the entry makes no sense.
func _add_entry(entry: Variant, time: float) -> Ship:
	if not entry is Array or entry.size() != 11 or not entry[0] is int or entry[0] < 1 or ships.has(entry[0]):
		return null
	if not entry[3] is Transform3D or not (entry[3] as Transform3D).is_finite():
		return null
	var at: Transform3D = (entry[3] as Transform3D).orthonormalized()
	if not is_equal_approx(at.basis.determinant(), 1.0):
		return null  # squashed flat or mirrored: not a way to face
	if not entry[4] is int or not entry[5] is int or not entry[6] is bool or not entry[8] is bool:
		return null
	if not entry[9] is int or entry[9] < 0 or entry[9] > Damage.SPARES_MAX:
		return null
	var grid := ShipGrid.from_bytes(entry[1], false)  # wrecks have no helm
	var paint: Variant = ShipGrid.read_paint(entry[2])
	var blueprint := ShipGrid.from_bytes(entry[7], false)
	var cargo: Variant = ShipGrid.read_cargo(entry[10], grid) if grid != null else null
	if grid == null or paint == null or blueprint == null or cargo == null:
		push_warning("The host sent ship %d with blocks, paint or cargo that don't make a ship; leaving it out." % entry[0])
		return null
	grid.cargo = cargo
	grid.paint = paint
	blueprint.paint = paint
	var buffer := SnapshotBuffer.new()
	buffer.push(time, at.origin, Vector3.ZERO, at.basis.get_rotation_quaternion())
	_buffers[entry[0]] = buffer
	return _add(entry[0], grid, at, false, entry[5], entry[6], entry[4], blueprint, entry[8], entry[9])


## Server -> clients: hit-point changes to ship id (Damage.pack bytes: 0 is
## destroyed, and a change for an empty cell restores the blueprint's block).
@rpc("authority", "call_remote", "reliable", 0)
func _blocks_changed(id: Variant, changes: Variant) -> void:
	if session.is_server() or not id is int or not ships.has(id):
		return
	var unpacked: Variant = Damage.unpack(changes)
	if unpacked != null:
		(ships[id] as Ship).damage(unpacked)


## Server -> clients: shot id of ammo (an index into Damage.AMMO's keys) left origin
## at velocity at server time time, fired from ship ship_id.
@rpc("authority", "call_remote", "reliable", 0)
func _fired(id: Variant, ammo: Variant, origin: Variant, velocity: Variant, time: Variant, ship_id: Variant) -> void:
	if session.is_server() or projectiles == null or not id is int or not ammo is int or ammo < 0 or ammo >= Damage.AMMO.size():
		return
	if not _is_point(origin) or not _is_point(velocity) or not _is_time(time) or not ship_id is int:
		return
	projectiles.launch(id, Damage.AMMO.keys()[ammo], origin, velocity, time, ship_id)


## Server -> clients: shot id ended at point at server time time.
@rpc("authority", "call_remote", "reliable", 0)
func _hit(id: Variant, point: Variant, time: Variant) -> void:
	if not session.is_server() and projectiles != null and id is int and _is_point(point) and _is_time(time):
		projectiles.land(id, point, time)


## Server -> clients: rope id ties a_cell of ship a_id to b_cell of ship b_id, length long.
@rpc("authority", "call_remote", "reliable", 0)
func _tether(id: Variant, a_id: Variant, a_cell: Variant, b_id: Variant, b_cell: Variant, length: Variant) -> void:
	if session.is_server() or projectiles == null or not id is int or not a_id is int or not b_id is int or a_id == b_id:
		return
	if not ships.has(a_id) or not ships.has(b_id) or not _is_cell(a_cell) or not _is_cell(b_cell):
		return
	if not length is float or not is_finite(length) or length <= 0.0:
		return
	projectiles.tie(id, ships[a_id], a_cell, ships[b_id], b_cell, length)


## Server -> clients: rope id is gone.
@rpc("authority", "call_remote", "reliable", 0)
func _untether(id: Variant) -> void:
	if not session.is_server() and projectiles != null and id is int:
		projectiles.untie(id)


## Server -> the one client hit: you're knocked down.
@rpc("authority", "call_remote", "reliable", 0)
func _knocked_out() -> void:
	if not session.is_server():
		knocked_out.emit()


## Server -> clients: every cell of ship id that's burning, 3 bytes each (x + 64,
## y + 64, z + 64).
@rpc("authority", "call_remote", "reliable", 0)
func _fires(id: Variant, cells: Variant) -> void:
	if session.is_server() or not id is int or not ships.has(id) or not cells is PackedByteArray:
		return
	var bytes: PackedByteArray = cells
	if bytes.size() % 3 != 0 or bytes.size() / 3 > ShipGrid.MAX_BLOCKS:
		return
	var burning: Array[Vector3i] = []
	for i in range(0, bytes.size(), 3):
		var cell := Vector3i(bytes[i] - 64, bytes[i + 1] - 64, bytes[i + 2] - 64)
		if not ShipGrid.in_area(cell):
			return
		burning.append(cell)
	(ships[id] as Ship).show_fires(burning)


## Server -> clients: ship id has count spares now.
@rpc("authority", "call_remote", "reliable", 0)
func _spares(id: Variant, count: Variant) -> void:
	if not session.is_server() and id is int and ships.has(id) and count is int and count >= 0 and count <= Damage.SPARES_MAX:
		(ships[id] as Ship).spares = count


## Server -> clients: every crate aboard ship id (see ShipGrid.cargo_list).
@rpc("authority", "call_remote", "reliable", 0)
func _cargo(id: Variant, cargo: Variant) -> void:
	if session.is_server() or not id is int or not ships.has(id):
		return
	var ship: Ship = ships[id]
	var stowed: Variant = ShipGrid.read_cargo(cargo, ship.grid)
	if stowed != null:
		ship.set_cargo(stowed)


## Server -> clients: world wreck index is stripped.
@rpc("authority", "call_remote", "reliable", 0)
func _salvaged(index: Variant) -> void:
	if not session.is_server() and index is int and index >= 0 and index < sites.size():
		salvaged[index] = true


## Server -> the salvager: the spares and crowns gained, both 0 for nothing left there.
@rpc("authority", "call_remote", "reliable", 0)
func _salvage_result(spares: Variant, money: Variant) -> void:
	if not session.is_server() and spares is int and spares >= 0 and spares <= Damage.SPARES_MAX and money is int and money >= 0:
		salvage_result.emit(spares, money)


## Server -> clients: a snapshot of every ship (see _ship_states), at time.
@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _ships(time: Variant, states: Variant) -> void:
	if session.is_server() or not _is_time(time) or not states is Array:
		return
	_hear_clock(time)
	for state: Variant in states:
		if not _is_ship_state(state) or not ships.has(state[0]):
			continue
		(_buffers[state[0]] as SnapshotBuffer).push(time, state[1], state[3], state[2], state[4])
		var ship: Ship = ships[state[0]]
		ship.throttle = state[5]
		ship.rudder = state[6]
		ship.trim = state[7]
		ship.anchored = state[11]
		if ship.helm != null:
			ship.helm.autopilot = state[8]
			ship.helm.target_heading = state[9]
			ship.helm.target_altitude = state[10]


## Client -> server: where my crew member is, in ship ship_id's space, or in the
## world when ship_id is 0 (ashore).
@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _crew_report(ship_id: Variant, position: Variant, velocity: Variant, yaw: Variant, pitch: Variant) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not session.is_server() or not _in_world.has(peer) or not _is_crew_state(ship_id, position, velocity, yaw, pitch):
		return
	if not crew_speed_ok(velocity):
		return
	var p: Vector3 = position
	if ship_id == 0:
		if Vector2(p.x, p.z).length() > ASHORE_REACH or p.y < 0.0 or p.y > ASHORE_CEILING:
			return
	elif not (ships[ship_id] as Ship).bounds.grow(CREW_REACH).has_point(p):
		return
	_hear_crew(peer, ship_id, _time, position, velocity, yaw, pitch)
	for other: int in _in_world:
		if other != peer:
			_crew_moved.rpc_id(other, peer, ship_id, _time, position, velocity, yaw, pitch)


## Server -> clients: where peer's crew member was at time, in ship ship_id's space
## (the world's for 0).
@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _crew_moved(peer: Variant, ship_id: Variant, time: Variant, position: Variant, velocity: Variant, yaw: Variant, pitch: Variant) -> void:
	if session.is_server() or not peer is int or peer == multiplayer.get_unique_id() or not session.players.has(peer):
		return
	if not _is_time(time) or not _is_crew_state(ship_id, position, velocity, yaw, pitch):
		return
	_hear_crew(peer, ship_id, time, position, velocity, yaw, pitch)


## Client -> server: peer asks for "helm", "autopilot" or "anchor" on ship ship_id,
## on or off.
@rpc("any_peer", "call_remote", "reliable", 0)
func _request(ship_id: Variant, what: Variant, on: Variant) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not session.is_server() or not _in_world.has(peer) or not ship_id is int or not ships.has(ship_id) or not on is bool:
		return
	var helm: Helm = (ships[ship_id] as Ship).helm
	if helm == null:
		return
	if what is String and what == "helm":
		if not on:
			helm.leave(peer)
		elif _crew.has(peer) and _crew[peer]["ship"] == ship_id and helm.in_reach(_crew[peer]["at"], REACH_SLACK):
			helm.take(peer)
	elif what is String and what == "autopilot":
		helm.ask_autopilot(peer, on)
	elif what is String and what == "anchor":
		helm.ask_anchor(peer, on)


## Client -> server: launch these blocks with this paint, as a test flight or not,
## from the dock of town (an index into WorldGen.towns). Junk is refused before it
## counts as the sender's launch for the second.
@rpc("any_peer", "call_remote", "reliable", 0)
func _launch(blocks: Variant, paint: Variant, test: Variant, town: Variant) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not session.is_server() or not _in_world.has(peer) or not test is bool:
		return
	if not town is int or town < 0 or town >= docks.size():
		return
	var grid := ShipGrid.from_bytes(blocks)
	var colours: Variant = ShipGrid.read_paint(paint)
	if grid == null or colours == null:
		return
	grid.paint = colours
	_launch_for(peer, grid, test, town)


## Client -> server: end my test flight.
@rpc("any_peer", "call_remote", "reliable", 0)
func _end_test() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if session.is_server() and _in_world.has(peer):
		remove_ship(ship_of(peer, true))


## Client -> server: the pilot's keys at the helm of ship ship_id, each -1 to 1.
@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _helm_keys(ship_id: Variant, throttle: Variant, rudder: Variant, climb: Variant) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not session.is_server() or not ship_id is int or not ships.has(ship_id):
		return
	var helm: Helm = (ships[ship_id] as Ship).helm
	if helm == null or helm.pilot != peer:
		return
	for key: Variant in [throttle, rudder, climb]:
		if not key is float or not is_finite(key):
			return
	_keys_heard[ship_id] = _time
	helm.throttle_input = clampf(throttle, -1.0, 1.0)
	helm.rudder_input = clampf(rudder, -1.0, 1.0)
	helm.climb_input = clampf(climb, -1.0, 1.0)


## Server -> clients: peer (0 for nobody) now has the helm of ship ship_id.
@rpc("authority", "call_remote", "reliable", 0)
func _pilot(ship_id: Variant, peer: Variant) -> void:
	if session.is_server() or not ship_id is int or not ships.has(ship_id) or not peer is int:
		return
	var helm: Helm = (ships[ship_id] as Ship).helm
	if helm != null:
		helm.pilot = peer


## Client -> server: man (on) or leave the cannon at cell of ship ship_id.
@rpc("any_peer", "call_remote", "reliable", 0)
func _man(ship_id: Variant, cell: Variant, on: Variant) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var cannon := _cannon_at(ship_id, cell)
	if not session.is_server() or not _in_world.has(peer) or cannon == null or not on is bool:
		return
	if not on:
		cannon.leave(peer)
	elif _crew.has(peer) and _crew[peer]["ship"] == ship_id and cannon.in_reach(_crew[peer]["at"], REACH_SLACK):
		cannon.take(peer)


## Server -> clients: peer (0 for nobody) now mans the cannon at cell of ship ship_id.
@rpc("authority", "call_remote", "reliable", 0)
func _gunner(ship_id: Variant, cell: Variant, peer: Variant) -> void:
	var cannon := _cannon_at(ship_id, cell)
	if not session.is_server() and cannon != null and peer is int:
		cannon.gunner = peer


## Client -> server: fire the cannon at cell of ship ship_id, aimed yaw and pitch,
## with ammo (an index into Damage.AMMO's keys). Only its gunner may, once it's loaded.
@rpc("any_peer", "call_remote", "reliable", 0)
func _fire(ship_id: Variant, cell: Variant, yaw: Variant, pitch: Variant, ammo: Variant) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var cannon := _cannon_at(ship_id, cell)
	if not session.is_server() or cannon == null or cannon.gunner != peer or cannon.reload_left > 0.0:
		return
	if not yaw is float or not is_finite(yaw) or not pitch is float or not is_finite(pitch):
		return
	if not ammo is int or ammo < 0 or ammo >= Damage.AMMO.size():
		return
	cannon.aim_yaw = clampf(yaw, -Cannon.ARC, Cannon.ARC)
	cannon.aim_pitch = clampf(pitch, Cannon.PITCH_MIN, Cannon.PITCH_MAX)
	cannon.ammo = Damage.AMMO.keys()[ammo]
	fire_cannon(ships[ship_id], cannon)


## Client -> server: salvage world wreck index (kind "site") or wreck ship index
## (kind "ship").
@rpc("any_peer", "call_remote", "reliable", 0)
func _salvage(kind: Variant, index: Variant) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if session.is_server() and _in_world.has(peer) and kind is String and index is int:
		_salvage_for(peer, kind, index)


## Client -> server: one repair action aimed at cell of ship ship_id.
@rpc("any_peer", "call_remote", "reliable", 0)
func _repair(ship_id: Variant, cell: Variant) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if session.is_server() and _in_world.has(peer) and ship_id is int and ships.has(ship_id) and _is_cell(cell):
		_repair_for(peer, ships[ship_id], cell)


func _is_crew_state(ship_id: Variant, position: Variant, velocity: Variant, yaw: Variant, pitch: Variant) -> bool:
	return ship_id is int and (ship_id == 0 or ships.has(ship_id)) and position is Vector3 and (position as Vector3).is_finite() \
			and velocity is Vector3 and (velocity as Vector3).is_finite() \
			and yaw is float and is_finite(yaw) and pitch is float and is_finite(pitch)


## Whether a crew report's velocity is no faster than CREW_MAX_SPEED, allowing for
## float rounding: crew capped at exactly that speed must still be taken.
static func crew_speed_ok(velocity: Vector3) -> bool:
	return velocity.length() <= CREW_MAX_SPEED + 0.01


static func _is_time(value: Variant) -> bool:
	return value is float and is_finite(value)


static func _is_point(value: Variant) -> bool:
	return value is Vector3 and (value as Vector3).is_finite()


static func _is_cell(value: Variant) -> bool:
	return value is Vector3i and ShipGrid.in_area(value)


static func _is_ship_state(state: Variant) -> bool:
	if not state is Array or state.size() != 12 or not state[0] is int or not state[8] is bool or not state[11] is bool:
		return false
	for i in [1, 3, 4]:
		if not state[i] is Vector3 or not (state[i] as Vector3).is_finite():
			return false
	if not state[2] is Quaternion or not (state[2] as Quaternion).is_normalized():
		return false
	for i in [5, 6, 7, 9, 10]:
		if not state[i] is float or not is_finite(state[i]):
			return false
	return true
