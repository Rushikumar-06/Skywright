class_name LanBrowser
extends Node
## Lists the games on the local network (spec §4.6). Once a second it broadcasts a
## LanBeacon query, and it keeps every well-formed answer. A game that stops
## answering drops off after forget_after seconds. Answers come from anyone on the
## network, so each one is checked, and names are cleaned.

signal changed  ## games changed.

const ASK_EVERY := 1.0  ## Seconds between queries.
const SettingsScript := preload("res://src/core/settings.gd")

## Game id -> {"address", "port", "name", "players", "max", "version"}.
var games: Dictionary = {}
var forget_after := 3.5  ## Seconds without an answer before a game is dropped.

var _port: int
var _udp := PacketPeerUDP.new()
var _heard: Dictionary = {}  ## Game id -> Time.get_ticks_msec() of its last answer.
var _ask_in := 0.0


func _init(port := LanBeacon.DISCOVERY_PORT) -> void:
	_port = port


func _ready() -> void:
	_udp.set_broadcast_enabled(true)
	_udp.bind(0)


func _exit_tree() -> void:
	_udp.close()


## The game an answer describes, as {"id", "name", "players", "max", "version",
## "port"}, or {} when the packet isn't a well-formed answer.
static func read_answer(packet: PackedByteArray) -> Dictionary:
	var magic := LanBeacon.ANSWER_MAGIC
	if packet.size() <= magic.length() or packet.size() > LanBeacon.QUERY_SIZE:
		return {}
	if packet.slice(0, magic.length()).get_string_from_ascii() != magic:
		return {}
	var game: Variant = bytes_to_var(packet.slice(magic.length()))
	if not game is Dictionary:
		return {}
	for key in ["id", "players", "max", "version", "port"]:
		if not game.get(key) is int:
			return {}
	if not game.get("name") is String:
		return {}
	if game["players"] < 0 or game["max"] < 1 or game["port"] < 1 or game["port"] > 65535:
		return {}
	return {
		"id": game["id"], "name": SettingsScript.clean_name(game["name"]), "players": game["players"],
		"max": game["max"], "version": game["version"], "port": game["port"],
	}


func _process(delta: float) -> void:
	_ask_in -= delta
	if _ask_in <= 0.0:
		_ask_in = ASK_EVERY
		# Ask this machine directly too, so games here show up with no network at all.
		for address in ["255.255.255.255", "127.0.0.1"]:
			_udp.set_dest_address(address, _port)
			_udp.put_packet(LanBeacon.query())
	var now := Time.get_ticks_msec()
	var dirty := false
	while _udp.get_available_packet_count() > 0:
		var game := read_answer(_udp.get_packet())
		if game.is_empty():
			continue
		var id: int = game["id"]
		game.erase("id")
		# Keep the first address a game answered from: a game on this machine answers
		# on every interface, and any of them works.
		game["address"] = games[id]["address"] if games.has(id) else _udp.get_packet_ip()
		if games.get(id) != game:
			games[id] = game
			dirty = true
		_heard[id] = now
	for id: int in games.keys():
		if now - _heard[id] > forget_after * 1000.0:
			games.erase(id)
			_heard.erase(id)
			dirty = true
	if dirty:
		changed.emit()
