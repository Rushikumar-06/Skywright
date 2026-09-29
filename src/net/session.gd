extends Node
## This game's network role: in the menus, solo, hosting, or connected to a host.
## Every game runs a server. Solo is a server with no network, so solo and online
## play share one code path. The host owns the roster and checks each joiner's
## version before accepting them. Game RPCs added later must ignore senders that
## aren't in players.

signal started                  ## Solo began, hosting began, or the host accepted us.
signal ended(reason: String)    ## The session stopped. reason is "" when the player chose to leave.
signal players_changed          ## players changed.

enum Mode { NONE, SOLO, HOST, CLIENT }

const PROTOCOL_VERSION := 1
const DEFAULT_PORT := 24650
const MAX_PLAYERS := 8
const SettingsScript := preload("res://src/core/settings.gd")

var mode := Mode.NONE
var players: Dictionary = {}              ## peer id (int) -> {"name": String}
var port := DEFAULT_PORT                  ## The port being hosted on or joined.
var max_players := MAX_PLAYERS            ## Host included. Tests lower it to fill a game.
var protocol_version := PROTOCOL_VERSION  ## Tests change it to act as an out-of-date client.
var connect_timeout := 8.0                ## Seconds a client waits to be accepted.
var log_enabled := true                   ## Prints "[session] ..." lines; tests turn it off.

var _accepted := false
var _pending_name := ""
var _timeout: Timer


func _ready() -> void:
	_timeout = Timer.new()
	_timeout.one_shot = true
	_timeout.timeout.connect(_on_timeout)
	add_child(_timeout)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_server() -> bool:
	return mode == Mode.SOLO or mode == Mode.HOST


## Starts a solo game: a server with no network, with you as peer 1.
func start_solo(player_name: String) -> void:
	_reset()
	mode = Mode.SOLO
	_set_players({1: {"name": SettingsScript.clean_name(player_name)}})
	_log("started solo")
	started.emit()


## Starts hosting on host_port. Returns OK, or ERR_CANT_CREATE when the port is taken.
func host(player_name: String, host_port := DEFAULT_PORT) -> Error:
	_reset()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(host_port, max_players)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	port = host_port
	_set_players({1: {"name": SettingsScript.clean_name(player_name)}})
	_log("hosting on port %d" % port)
	started.emit()
	return OK


## Starts connecting to a host. started fires once the host accepts us. ended fires
## if it refuses, can't be reached, or doesn't answer within connect_timeout seconds.
func join(player_name: String, address: String, join_port := DEFAULT_PORT) -> Error:
	_reset()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, join_port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	port = join_port
	_pending_name = SettingsScript.clean_name(player_name)
	_timeout.start(connect_timeout)
	_log("connecting to %s:%d" % [address, join_port])
	return OK


## Leaves the session. Emits ended("") if one was running. A host with guests
## tells them first, so they see "The host ended the game." instead of a dropped
## connection.
func leave() -> void:
	if mode == Mode.NONE:
		return
	var say_goodbye := mode == Mode.HOST and players.size() > 1 \
			and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	if say_goodbye:
		_ending.rpc()
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).host.flush()
	_end("", say_goodbye)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		leave()  # closing the window says goodbye too


## Turns "host", "host:port" or "[ipv6]:port" into {"host": String, "port": int},
## or {} when the text isn't a usable address.
static func parse_address(text: String) -> Dictionary:
	var trimmed := text.strip_edges()
	var host_part := trimmed
	var port_part := ""
	if trimmed.begins_with("["):
		var close := trimmed.find("]")
		if close < 0:
			return {}
		host_part = trimmed.substr(1, close - 1)
		var rest := trimmed.substr(close + 1)
		if rest.begins_with(":"):
			port_part = rest.substr(1)
			if port_part.is_empty():
				return {}
		elif not rest.is_empty():
			return {}
	elif trimmed.count(":") == 1:
		host_part = trimmed.get_slice(":", 0)
		port_part = trimmed.get_slice(":", 1)
		if port_part.is_empty():
			return {}
	var chosen_port := DEFAULT_PORT
	if not port_part.is_empty():
		if not port_part.is_valid_int():
			return {}
		chosen_port = port_part.to_int()
		if chosen_port < 1 or chosen_port > 65535:
			return {}
	if host_part.is_empty() or host_part.contains(" ") or host_part.contains("/"):
		return {}
	return {"host": host_part, "port": chosen_port}


## The private IPv4 addresses among addresses: the ones friends on the same
## network can reach.
static func lan_addresses(addresses: PackedStringArray) -> PackedStringArray:
	var lan: PackedStringArray = []
	for address in addresses:
		if address.begins_with("192.168.") or address.begins_with("10."):
			lan.append(address)
		elif address.begins_with("172."):
			var second := address.get_slice(".", 1).to_int()
			if second >= 16 and second <= 31:
				lan.append(address)
	return lan


func _on_connected_to_server() -> void:
	if mode == Mode.CLIENT:
		_hello.rpc_id(1, protocol_version, _pending_name)


func _on_connection_failed() -> void:
	if mode == Mode.CLIENT:
		_end("Couldn't reach the host.")


func _on_server_disconnected() -> void:
	if mode == Mode.CLIENT:
		_end("Lost the connection to the host." if _accepted else "The host closed the connection.")


func _on_peer_disconnected(id: int) -> void:
	if mode == Mode.HOST and players.has(id):
		var roster := players.duplicate(true)
		roster.erase(id)
		_set_players(roster)
		_roster.rpc(players)
		_log("peer %d left" % id)


func _on_timeout() -> void:
	if mode == Mode.CLIENT and not _accepted:
		_end("The host didn't answer.")


@rpc("any_peer", "call_remote", "reliable")
func _hello(version: int, player_name: String) -> void:
	if mode != Mode.HOST:
		return
	var id := multiplayer.get_remote_sender_id()
	var refusal := ""
	if version != PROTOCOL_VERSION:
		refusal = "The host is on version %d and you're on version %d. Both need the same version." % [PROTOCOL_VERSION, version]
	elif players.size() >= max_players:
		refusal = "The game is full."
	if not refusal.is_empty():
		_refused.rpc_id(id, refusal)
		# Disconnect once the refusal has gone out; a plain disconnect would drop it.
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(id).peer_disconnect_later()
		_log("refused peer %d: %s" % [id, refusal])
		return
	var roster := players.duplicate(true)
	roster[id] = {"name": SettingsScript.clean_name(player_name)}
	_set_players(roster)
	_welcome.rpc_id(id, players)
	_roster.rpc(players)
	_log("peer %d joined as %s" % [id, roster[id]["name"]])


@rpc("authority", "call_remote", "reliable")
func _welcome(roster: Dictionary) -> void:
	if mode != Mode.CLIENT or _accepted:
		return
	_accepted = true
	_timeout.stop()
	_set_players(roster)
	_log("joined; crew: %s" % ", ".join(_names()))
	started.emit()


@rpc("authority", "call_remote", "reliable")
func _refused(reason: String) -> void:
	if mode == Mode.CLIENT:
		_end(reason)


@rpc("authority", "call_remote", "reliable")
func _roster(roster: Dictionary) -> void:
	if mode == Mode.CLIENT and _accepted:
		_set_players(roster)


@rpc("authority", "call_remote", "reliable")
func _ending() -> void:
	if mode == Mode.CLIENT:
		_end("The host ended the game.")


func _end(reason: String, linger := false) -> void:
	_reset(linger)
	_log("ended" if reason.is_empty() else "ended: " + reason)
	ended.emit(reason)


## Drops any connection and returns to NONE without emitting ended. Mode changes
## first, so disconnect signals fired while closing are ignored. With linger, the
## old socket stays open briefly so a goodbye just sent isn't cut off: ENet drops
## packets that arrive in the same update as a disconnect.
func _reset(linger := false) -> void:
	_timeout.stop()
	mode = Mode.NONE
	_accepted = false
	var old_peer := multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if old_peer != null and not old_peer is OfflineMultiplayerPeer:
		if linger:
			# The lambda keeps the peer alive until then; a bound Callable wouldn't.
			get_tree().create_timer(0.25).timeout.connect(func() -> void: old_peer.close())
		else:
			old_peer.close()
	if not players.is_empty():
		_set_players({})


func _set_players(roster: Dictionary) -> void:
	players = roster
	players_changed.emit()


func _names() -> PackedStringArray:
	var names: PackedStringArray = []
	for id: int in players:
		names.append(players[id]["name"])
	return names


func _log(message: String) -> void:
	if log_enabled:
		print("[session] ", message)
