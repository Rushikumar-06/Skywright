class_name LanBeacon
extends Node
## Makes a hosted game findable on the local network (spec §4.6). Browsers
## broadcast a query to DISCOVERY_PORT, and the beacon answers each one with the
## game's details. Only one program per machine can listen on a port, so the
## second game hosted on a machine can't be found this way, only joined by address.
##
## A query is QUERY_MAGIC padded with zeros to QUERY_SIZE bytes. An answer is
## ANSWER_MAGIC followed by var_to_bytes(info). An answer is never bigger than the
## query it answers, so a beacon can't be used to multiply someone's traffic.

const DISCOVERY_PORT := 24651
const QUERY_SIZE := 256
const QUERY_MAGIC := "SKYWRIGHT?"
const ANSWER_MAGIC := "SKYWRIGHT!"

## What to answer with: {"id", "name", "players", "max", "version", "port"}.
var info: Dictionary = {}

var _port: int
var _udp := PacketPeerUDP.new()


func _init(port := DISCOVERY_PORT) -> void:
	_port = port


func _ready() -> void:
	_udp.bind(_port)  # fails quietly when another game on this machine has the port


func _exit_tree() -> void:
	_udp.close()


static func query() -> PackedByteArray:
	var packet := QUERY_MAGIC.to_ascii_buffer()
	packet.resize(QUERY_SIZE)
	return packet


static func answer(game: Dictionary) -> PackedByteArray:
	var packet := ANSWER_MAGIC.to_ascii_buffer()
	packet.append_array(var_to_bytes(game))
	return packet


func _process(_delta: float) -> void:
	while _udp.get_available_packet_count() > 0:
		var packet := _udp.get_packet()
		if packet.size() < QUERY_SIZE or packet.slice(0, QUERY_MAGIC.length()).get_string_from_ascii() != QUERY_MAGIC:
			continue
		var reply := answer(info)
		if reply.size() > packet.size():
			continue
		_udp.set_dest_address(_udp.get_packet_ip(), _udp.get_packet_port())
		_udp.put_packet(reply)
