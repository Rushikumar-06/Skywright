class_name Ledger
extends Node
## The server keeps the books (spec §3.6): every player's account by name (money,
## unlocks, contracts and insurance), and sends each player their own. Clients only
## ask, and the server takes at most one ask from each peer every ASK_EVERY, checked
## against where the asker last said they were. It sits beside the World's Sync, which
## keeps the ships. It sells spares and crates at docks, and keeps each town's contract
## board, drawn when first asked for: deliveries pay when a ship carrying their mail
## docks at their town, bounties for pirates beaten near you, salvage for stripping her
## wreck, and scouting for getting near the landmark.

signal account_changed          ## This machine's player's account changed.
signal told(text: String)       ## A message for this machine's player.
signal board_changed(town: int) ## town's board, as this machine knows it, changed.

const ASK_EVERY := 0.1  ## s. The least time between one peer's asks.
const MAX_TEXT := 200   ## Characters in a message.

var sync: WorldSync
var accounts: Dictionary = {}                ## Server: player name -> account (see Economy.new_account).
var mine: Dictionary = Economy.new_account() ## This machine's player's account, as the server last sent it.
## Town -> its offers (see Economy.draw_contract, with "id"): on the server the boards,
## on a client the ones it was sent.
var boards: Dictionary = {}

var _next_contract := 1

var _asked_at: Dictionary = {}  ## Server: peer id -> sync.now() of their last ask.


func _init(world_sync: WorldSync) -> void:
	sync = world_sync
	name = "Ledger"


func _ready() -> void:
	sync.peer_entered.connect(send_account)
	sync.docked.connect(on_docked)
	if sync.session.is_server() and not sync.session.dedicated:
		send_account(multiplayer.get_unique_id())


## Server: peer's account, by their name, made fresh the first time.
func account_of(peer: int) -> Dictionary:
	var player_name := sync.name_of(peer)
	if not accounts.has(player_name):
		accounts[player_name] = Economy.new_account()
	return accounts[player_name]


## Server: adds amount to peer's money (charges it when negative, never below 0), and
## sends them their account.
func pay(peer: int, amount: int) -> void:
	var account := account_of(peer)
	account["money"] = maxi(0, account["money"] + amount)
	send_account(peer)


## Server: sends peer their account.
func send_account(peer: int) -> void:
	if peer == multiplayer.get_unique_id():
		mine = account_of(peer).duplicate(true)
		account_changed.emit()
	elif sync.in_world(peer):
		_account.rpc_id(peer, account_of(peer))


## Server: a message for peer.
func tell(peer: int, text: String) -> void:
	if peer == multiplayer.get_unique_id():
		told.emit(text)
	elif sync.in_world(peer):
		_say.rpc_id(peer, text)


## This machine's player fills the ship they're aboard with spares, at a dock.
func buy_spares() -> void:
	if sync.session.is_server():
		_buy_spares_for(multiplayer.get_unique_id())
	else:
		_buy_spares.rpc_id(1)


## This machine's player buys (count 1) or sells (count -1) a crate of good at the
## dock they're at, aboard a ship.
func trade(good: String, count: int) -> void:
	if sync.session.is_server():
		_trade_for(multiplayer.get_unique_id(), good, count)
	else:
		_trade.rpc_id(1, good, count)


## This machine's player asks for the board of the town whose dock they're at.
func ask_board() -> void:
	if sync.session.is_server():
		_ask_board_for(multiplayer.get_unique_id())
	else:
		_ask_board.rpc_id(1)


## This machine's player takes offer id from the board where they stand.
func take_contract(id: int) -> void:
	if sync.session.is_server():
		_take_for(multiplayer.get_unique_id(), id)
	else:
		_take.rpc_id(1, id)


## This machine's player drops their contract id, anywhere.
func drop_contract(id: int) -> void:
	if sync.session.is_server():
		_drop_for(multiplayer.get_unique_id(), id)
	else:
		_drop.rpc_id(1, id)


## Server: ship docked at town. Every delivery to town whose mail she carries is done.
func on_docked(ship: Ship, town: int) -> void:
	var cargo := ship.grid.cargo.duplicate(true)
	for player_name: String in accounts:
		for contract: Dictionary in (accounts[player_name]["contracts"] as Array).duplicate():
			if contract["kind"] != "delivery" or contract["target"] != town:
				continue
			var carried := _mail_of(cargo, player_name)
			if carried.size() < contract["count"]:
				continue
			for i in contract["count"]:
				cargo.erase(carried[i])
			_complete(player_name, contract)
	if cargo != ship.grid.cargo:
		sync.set_cargo(ship, cargo)


## Server: peer stripped world wreck site, completing their salvage contract for her.
func on_salvaged(peer: int, site: int) -> void:
	var player_name := sync.name_of(peer)
	for contract: Dictionary in (account_of(peer)["contracts"] as Array).duplicate():
		if contract["kind"] == "salvage" and contract["target"] == site:
			_complete(player_name, contract)


## Server: a pirate was beaten at at. It counts toward the bounties of everyone within
## Economy.BOUNTY_REACH.
func pirate_beaten(at: Vector3) -> void:
	for peer: int in _players_near(at, Economy.BOUNTY_REACH):
		var counted := false
		for contract: Dictionary in (account_of(peer)["contracts"] as Array).duplicate():
			if contract["kind"] != "bounty":
				continue
			contract["done"] += 1
			counted = true
			if contract["done"] >= contract["count"]:
				_complete(sync.name_of(peer), contract)
		if counted:
			send_account(peer)


## Server: each player within Economy.SCOUT_REACH of a landmark they're scouting has
## scouted it.
func check_scouts() -> void:
	for peer: int in _players_near(Vector3.ZERO, INF):
		var at: Vector3 = sync.world_position_of(peer)
		for contract: Dictionary in (account_of(peer)["contracts"] as Array).duplicate():
			if contract["kind"] == "scout" and contract["target"] < sync.gen.landmarks.size() \
					and at.distance_to(sync.gen.landmarks[contract["target"]]["at"]) <= Economy.SCOUT_REACH:
				_complete(sync.name_of(peer), contract)


## Server: whether to hear peer's ask now. This machine's player is always heard.
func _may_ask(peer: int) -> bool:
	if peer == multiplayer.get_unique_id():
		return true
	if not sync.in_world(peer) or sync.now() - _asked_at.get(peer, -INF) < ASK_EVERY:
		return false
	_asked_at[peer] = sync.now()
	return true


## Server: the ship peer is aboard, when she's at a town's dock and not a test flight
## or a pirate; else null.
func _docked_ship(peer: int) -> Ship:
	var ship := sync.aboard(peer)
	if ship == null or ship.test or ship.pirate or sync.town_at(ship.global_position) < 0:
		return null
	return ship


func _buy_spares_for(peer: int) -> void:
	var ship := _docked_ship(peer)
	if ship == null:
		tell(peer, "Buy spares at a town's dock, aboard a ship.")
		return
	var room := Damage.SPARES_MAX - ship.spares
	if room <= 0:
		tell(peer, "Her spares are full.")
		return
	var count := mini(room, account_of(peer)["money"] / Economy.SPARE_PRICE)
	if count <= 0:
		tell(peer, "You can't afford a spare (%d crowns)." % Economy.SPARE_PRICE)
		return
	ship.spares += count
	sync.tell_world(&"_spares", [sync.id_of(ship), ship.spares])
	pay(peer, -count * Economy.SPARE_PRICE)
	tell(peer, "Bought %d spares for %d crowns." % [count, count * Economy.SPARE_PRICE])


## Server: a buy goes in the first free bay, owned by the buyer; a sale takes the
## seller's own crate of good, first in cell order. The town whose dock she's at is the
## market. Junk is ignored.
func _trade_for(peer: int, good: String, count: int) -> void:
	if (count != 1 and count != -1) or not Economy.GOODS.has(good):
		return
	var good_name: String = Economy.GOODS[good]["name"]
	if Economy.GOODS[good]["price"] == 0:
		tell(peer, "%s isn't for sale." % good_name)
		return
	var ship := _docked_ship(peer)
	if ship == null:
		tell(peer, "Trade at a town's dock, aboard a ship.")
		return
	var town := sync.town_at(ship.global_position)
	var cargo := ship.grid.cargo.duplicate(true)
	var owner := sync.name_of(peer)
	if count == 1:
		var free := ship.grid.free_bays()
		var price := Economy.price(sync.gen, town, good)
		if free.is_empty():
			tell(peer, "Her hold is full.")
		elif account_of(peer)["money"] < price:
			tell(peer, "You can't afford %s (%d crowns)." % [good_name, price])
		else:
			cargo[free[0]] = {"good": good, "owner": owner}
			sync.set_cargo(ship, cargo)
			pay(peer, -price)
		return
	var cells := cargo.keys()
	cells.sort()
	for cell: Vector3i in cells:
		if cargo[cell]["good"] == good and cargo[cell]["owner"] == owner:
			cargo.erase(cell)
			sync.set_cargo(ship, cargo)
			pay(peer, Economy.sell_price(sync.gen, town, good))
			return
	tell(peer, "You have no %s aboard." % good_name)


## Server: the board of town, drawn the first time.
func _board_of(town: int) -> Array:
	if not boards.has(town):
		var offers := []
		for i in Economy.BOARD_SIZE:
			offers.append(_draw(town))
		boards[town] = offers
	return boards[town]


func _draw(town: int) -> Dictionary:
	var contract := Economy.draw_contract(sync.gen, town, sync.salvaged, sync.rng)
	contract["id"] = _next_contract
	_next_contract += 1
	return contract


## Server: the town whose dock peer last said they were at, or -1.
func _town_of(peer: int) -> int:
	var at: Variant = sync.world_position_of(peer)
	return sync.town_at(at) if at != null else -1


func _ask_board_for(peer: int) -> void:
	var town := _town_of(peer)
	if town < 0:
		return
	_send_board(peer, town)


func _send_board(peer: int, town: int) -> void:
	var board := _board_of(town)
	if peer == multiplayer.get_unique_id():
		board_changed.emit(town)
	elif sync.in_world(peer):
		_board.rpc_id(peer, town, board)


func _take_for(peer: int, id: int) -> void:
	var town := _town_of(peer)
	if town < 0:
		tell(peer, "Take contracts at a town's board.")
		return
	var board := _board_of(town)
	var index := board.find_custom(func(each: Dictionary) -> bool: return each["id"] == id)
	if index < 0:
		tell(peer, "That contract is gone.")
		return
	var account := account_of(peer)
	if account["contracts"].size() >= Economy.MAX_CONTRACTS:
		tell(peer, "You have three contracts already.")
		return
	var contract: Dictionary = board[index].duplicate()
	if contract["kind"] == "delivery":
		var ship := _docked_ship(peer)
		var free: Array[Vector3i] = []
		if ship != null:
			free = ship.grid.free_bays()
		if free.size() < contract["count"]:
			tell(peer, "Your hold has room for %d crates." % free.size())
			return
		var cargo := ship.grid.cargo.duplicate(true)
		for i in contract["count"]:
			cargo[free[i]] = {"good": "mail", "owner": sync.name_of(peer)}
		sync.set_cargo(ship, cargo)
	contract["done"] = 0
	account["contracts"].append(contract)
	board[index] = _draw(town)
	send_account(peer)
	_send_board(peer, town)
	tell(peer, "Contract taken: %s." % contract["title"])


func _drop_for(peer: int, id: int) -> void:
	var account := account_of(peer)
	var index: int = account["contracts"].find_custom(func(each: Dictionary) -> bool: return each["id"] == id)
	if index < 0:
		return
	var contract: Dictionary = account["contracts"].pop_at(index)
	if contract["kind"] == "delivery":
		var left: int = contract["count"]
		for ship: Ship in sync.ships.values():
			var cargo := ship.grid.cargo.duplicate(true)
			for cell: Vector3i in _mail_of(cargo, sync.name_of(peer)):
				if left > 0:
					cargo.erase(cell)
					left -= 1
			if cargo != ship.grid.cargo:
				sync.set_cargo(ship, cargo)
	send_account(peer)
	tell(peer, "Contract dropped: %s." % contract["title"])


## Server: pays player_name contract's reward, takes it off their books, and tells them.
func _complete(player_name: String, contract: Dictionary) -> void:
	var account: Dictionary = accounts[player_name]
	account["contracts"].erase(contract)
	account["money"] += contract["reward"]
	var peer := _peer_named(player_name)
	if peer != 0:
		send_account(peer)
		tell(peer, "Contract done: %s. +%d crowns." % [contract["title"], contract["reward"]])


## The cells of player_name's mail crates in cargo, in cell order.
static func _mail_of(cargo: Dictionary, player_name: String) -> Array:
	var cells := cargo.keys().filter(func(cell: Vector3i) -> bool:
		return cargo[cell]["good"] == "mail" and cargo[cell]["owner"] == player_name)
	cells.sort()
	return cells


## Server: the peer here named player_name, or 0.
func _peer_named(player_name: String) -> int:
	for peer: int in _players_near(Vector3.ZERO, INF, false):
		if sync.name_of(peer) == player_name:
			return peer
	return 0


## Server: the players in the world within reach of at (where they last said they were).
func _players_near(at: Vector3, reach: float, placed := true) -> Array[int]:
	var found: Array[int] = []
	var peers: Array = sync.session.players.keys()
	for peer: int in peers:
		if not sync.in_world(peer):
			continue
		var where: Variant = sync.world_position_of(peer)
		if not placed or (where != null and (where as Vector3).distance_to(at) <= reach):
			found.append(peer)
	return found


## Server -> its owner: their account.
@rpc("authority", "call_remote", "reliable", 0)
func _account(account: Variant) -> void:
	if sync.session.is_server():
		return
	var clean: Variant = Economy.read_account(account)
	if clean != null:
		mine = clean
		account_changed.emit()


## Server -> one player: a message.
@rpc("authority", "call_remote", "reliable", 0)
func _say(text: Variant) -> void:
	if not sync.session.is_server() and text is String and text.length() <= MAX_TEXT:
		told.emit(text)


## Client -> server: buy (1) or sell (-1) a crate of good where I am.
@rpc("any_peer", "call_remote", "reliable", 0)
func _trade(good: Variant, count: Variant) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if sync.session.is_server() and good is String and count is int and _may_ask(peer):
		_trade_for(peer, good, count)


## Server -> a player at town's dock: its offers.
@rpc("authority", "call_remote", "reliable", 0)
func _board(town: Variant, offers: Variant) -> void:
	if sync.session.is_server() or not town is int or town < 0 or town >= sync.gen.towns.size() \
			or not offers is Array or offers.size() > Economy.BOARD_SIZE:
		return
	var clean := []
	for entry: Variant in offers:
		var contract: Variant = Economy.read_contract(entry)
		if contract == null:
			return
		clean.append(contract)
	boards[town] = clean
	board_changed.emit(town)


## Client -> server: the board of the town I'm at.
@rpc("any_peer", "call_remote", "reliable", 0)
func _ask_board() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if sync.session.is_server() and _may_ask(peer):
		_ask_board_for(peer)


## Client -> server: take offer id from the board where I stand.
@rpc("any_peer", "call_remote", "reliable", 0)
func _take(id: Variant) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if sync.session.is_server() and id is int and _may_ask(peer):
		_take_for(peer, id)


## Client -> server: drop my contract id.
@rpc("any_peer", "call_remote", "reliable", 0)
func _drop(id: Variant) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if sync.session.is_server() and id is int and _may_ask(peer):
		_drop_for(peer, id)


## Client -> server: fill the ship I'm aboard with spares.
@rpc("any_peer", "call_remote", "reliable", 0)
func _buy_spares() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if sync.session.is_server() and _may_ask(peer):
		_buy_spares_for(peer)
