class_name Ledger
extends Node
## The server keeps the books (spec §3.6): every player's account by name (money,
## unlocks, contracts and insurance), and sends each player their own. Clients only
## ask, and the server takes at most one ask from each peer every ASK_EVERY, checked
## against where the asker last said they were. It sits beside the World's Sync, which
## keeps the ships.

signal account_changed          ## This machine's player's account changed.
signal told(text: String)       ## A message for this machine's player.

const ASK_EVERY := 0.1  ## s. The least time between one peer's asks.
const MAX_TEXT := 200   ## Characters in a message.

var sync: WorldSync
var accounts: Dictionary = {}                ## Server: player name -> account (see Economy.new_account).
var mine: Dictionary = Economy.new_account() ## This machine's player's account, as the server last sent it.

var _asked_at: Dictionary = {}  ## Server: peer id -> sync.now() of their last ask.


func _init(world_sync: WorldSync) -> void:
	sync = world_sync
	name = "Ledger"


func _ready() -> void:
	sync.peer_entered.connect(send_account)
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


## Client -> server: fill the ship I'm aboard with spares.
@rpc("any_peer", "call_remote", "reliable", 0)
func _buy_spares() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if sync.session.is_server() and _may_ask(peer):
		_buy_spares_for(peer)
