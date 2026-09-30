extends Node3D
## The game world: sky, the Roil, the islands made from the session's seed (streamed
## in around every ship), the ten towns with their docks, and the starter ship at the
## first town's first slipway with you aboard. Its Weather (fog sheets, storm columns
## and lightning) is only drawn where someone plays. Its Session is a sibling: the
## Session autoload in the game, or a test's own. The server builds the ships and flies them;
## clients get them through the world's WorldSync. You board the host's ship when you
## arrive, and your own ship whenever one arrives: launch a design and you're at its
## helm, and B brings you back from a test flight. When the ship you're on goes, you
## board its successor, or the ship you came from, or your own, or the host's, and
## with none of those you step off into the air. Stepping off a deck puts you ashore,
## on foot in this world; landing on a deck, or E next to a hull, puts you aboard;
## and falling into the Roil puts you back aboard. A dedicated server's world has no
## player, HUD, pause menu or Weather.

## Where the ship starts: over the Calm Reaches, 7 km from the Eye.
const START := WorldGen.START
const REVEAL_EVERY := 0.5  ## Seconds between looks around, for the map.

var session: Node
var sync: WorldSync
var ship: Ship                 ## The ship you're aboard. Null while ashore.
var left: Ship                 ## The ship you last stepped off, while it's here.
var player: PlayerController   ## You, once the ship has arrived.
var hud: Hud
var towns: Array[Node3D] = []  ## Every town, in WorldGen.towns' order, under the Towns node.
var shipyard: Shipyard         ## Null while closed.
var design: ShipDesign         ## Your design, kept for the whole game.
var gen: WorldGen              ## The world made from the session's seed.
var wind: Wind                 ## Its wind, on the world's clock.
var streamer: WorldStreamer    ## Loads its chunks around every ship and player.
var exploration := Exploration.new()  ## What you have seen of it, on this machine only.
var map: MapView               ## The whole world, hidden until M. Made with the HUD.

var _reveal_left := 0.0        ## Seconds until the next look around.
var _came_from: Ship           ## The ship you were on before this one, while it's still here.

var _sky: WorldSky
var _pause: PanelContainer
var _resume: Button


func _ready() -> void:
	session = get_node("../Session")
	_sky = WorldSky.new()
	add_child(_sky)
	add_child(Roil.new())
	gen = WorldGen.new(session.world_seed)
	wind = Wind.new(gen)
	var town_root := Node3D.new()
	town_root.name = "Towns"
	add_child(town_root)
	for i in gen.towns.size():
		var town := Town.create(gen.towns[i], not session.dedicated)
		town.name = "Town%d" % i
		town_root.add_child(town)
		towns.append(town)
	sync = WorldSync.new(session)
	sync.wind = wind
	sync.ship_added.connect(_on_ship_added)
	sync.ship_removed.connect(_on_ship_removed)
	for town: Dictionary in gen.towns:
		sync.docks.append(town["dock"])
	add_child(sync)
	if not session.dedicated:
		add_child(Weather.new(gen, sync.now))
	if session.is_server():
		sync.add_ship(StarterShip.build(), Dock.slipway(START, 0), 0 if session.dedicated else 1)
	streamer = WorldStreamer.new(gen, not session.dedicated)
	streamer.focus = sync.focus_points
	add_child(streamer)
	if not session.dedicated:
		_build_pause_menu()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	_sky.hour = WorldSky.hour_at(sync.now())
	if hud != null:
		hud.test_flight = on_test_flight()
		hud.at_dock = at_dock()
	_reveal_left -= delta
	if player != null and _reveal_left <= 0.0:
		_reveal_left = REVEAL_EVERY
		exploration.reveal(player.world_position())


## Your place in the roster, which is where you stand when you board: crew board
## at different spots, in the order they joined.
func my_slot() -> int:
	return maxi(0, session.players.keys().find(multiplayer.get_unique_id()))


## The town whose dock p is near, or -1.
func town_at(p: Vector3) -> int:
	for i in gen.towns.size():
		if Dock.near(gen.towns[i]["dock"], p):
			return i
	return -1


## Takes grid for a test flight from your test berth at the nearest town, at its helm.
func test_flight(grid: ShipGrid) -> void:
	_launch(grid, true)


## Launches grid as your ship, at your slipway at the nearest town and at its helm. It
## replaces your old ship, whose crew come too.
func launch(grid: ShipGrid) -> void:
	_launch(grid, false)


func _launch(grid: ShipGrid, test: bool) -> void:
	if not sync.launch(grid, test, _town_here()) and shipyard != null:
		shipyard.say("Wait a moment, then try again.")


## Whether you're aboard your own test flight.
func on_test_flight() -> bool:
	return ship != null and ship.test and ship.captain == multiplayer.get_unique_id()


## Whether your crew member, where the world draws them, is near a town's dock.
func at_dock() -> bool:
	return player != null and town_at(player.world_position()) >= 0


## Puts you aboard target at spot (-1 for your roster slot), with your controls.
func board(target: Ship, spot := -1) -> void:
	come_aboard(target, target.crew_spawn(my_slot() if spot < 0 else spot))


## Puts you aboard target at local (in its space), standing still, with your controls.
func come_aboard(target: Ship, local: Vector3) -> void:
	var crew := CrewMember.new(target, local)
	target.interior.add_child(crew)
	if player == null:
		player = PlayerController.new(crew)
		add_child(player)
		sync.player = player
		player.left_ship.connect(go_ashore)
		player.landed_on.connect(func(on: Ship) -> void: come_aboard(on, on.to_local(player.crew.global_position)))
		player.climbing.connect(board)
		player.lost.connect(rescue)
		hud = Hud.new(player, session)
		hud.wind = wind
		hud.gen = gen
		hud.exploration = exploration
		add_child(hud)
		map = MapView.new(gen, exploration, sync, _you)
		map.visible = false
		hud.add_child(map)
		map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		var from := ship if ship != null else left
		var here := sync.id_of(from) != 0  # a ship on its way out can't be gone back to
		if ship != null and here and player.crew.station != null:
			ship.helm.ask_helm(player.peer, false)  # or nobody else could take her helm until you left
		if not on_test_flight():  # from a second test flight, B still goes back where the first came from
			_came_from = from if here else null
		_swap_crew(crew)
	ship = target


## Steps you off your ship into this world, where you are, keeping the ship's
## velocity there and the way you face.
func go_ashore() -> void:
	var from := ship
	var old := player.crew
	var point := from.global_transform * old.position
	var crew := CrewMember.new(null, point)
	crew.velocity = (from.point_velocity(point) + from.global_basis * old.velocity).limit_length(CrewMember.FALL_LIMIT)
	var facing := from.global_basis * (Basis(Vector3.UP, old.look_yaw) * Vector3.FORWARD)
	crew.look_yaw = atan2(-facing.x, -facing.z)
	add_child(crew)
	if sync.id_of(from) != 0 and old.station != null:
		from.helm.ask_helm(player.peer, false)
	left = from
	ship = null
	_swap_crew(crew)


## Out of the Roil: aboard the ship you left, else your own, else the host's.
func rescue() -> void:
	for next: Ship in [left, sync.ship_of(multiplayer.get_unique_id(), false), sync.home_ship()]:
		if next != null and sync.id_of(next) != 0:
			board(next)
			hud.show_message("The Roil nearly took you. Back aboard!")
			return


## Opens the shipyard on your design, when you're at a dock or dock_only is off.
func open_shipyard(dock_only := true) -> void:
	if shipyard != null or player == null:
		return
	if dock_only and not at_dock():
		hud.show_message("The shipyard is at the dock.")
		return
	if design == null:
		design = ShipDesign.new(ship.grid if ship != null else StarterShip.build())
	shipyard = Shipyard.new(design, (gen.towns[_town_here()]["dock"] as Vector3).y)
	shipyard.layer = 3
	shipyard.test_flight_requested.connect(test_flight)
	shipyard.launch_requested.connect(launch)
	shipyard.close_requested.connect(close_shipyard)
	add_child(shipyard)
	player.enabled = false
	hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_viewport().disable_3d = true


## Closes the shipyard, keeping the design, and gives you back the controls.
func close_shipyard() -> void:
	if shipyard == null:
		return
	shipyard.queue_free()
	shipyard = null
	player.enabled = true
	hud.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_viewport().disable_3d = false


## Gives your controls to crew, and lets the crew member you had go.
func _swap_crew(crew: CrewMember) -> void:
	var old := player.crew
	player.board(crew)
	old.queue_free()


## The town you're at, or the first when you're not at one.
func _town_here() -> int:
	return maxi(0, town_at(player.world_position())) if player != null else 0


func _on_ship_added(added: Ship) -> void:
	if session.dedicated:
		return
	if added.captain == multiplayer.get_unique_id():
		board(added, 0)
		close_shipyard()  # your test flight or new ship is ready
	elif player == null and added == sync.home_ship():
		board(added)


func _on_ship_removed(removed: Ship, successor: Ship) -> void:
	if _came_from == removed:
		_came_from = null
	if left == removed:
		left = null
	if ship != removed:
		return
	for next: Ship in [successor, _came_from, sync.ship_of(multiplayer.get_unique_id(), false), sync.home_ship()]:
		if next != null:
			board(next)
			if removed.test and removed.captain == multiplayer.get_unique_id() and not _pause.visible:
				open_shipyard(false)  # back from a test flight
			return
	go_ashore()  # nowhere to go: into the air where she was
	left = null


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_viewport().disable_3d = false  # the session can end with the shipyard open


func _unhandled_input(event: InputEvent) -> void:
	if _pause == null:
		return
	if event.is_action_pressed("pause"):
		if shipyard != null:
			close_shipyard()
		elif map != null and map.visible:
			_toggle_map()
		else:
			_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map") and shipyard == null and not _pause.visible and map != null:
		_toggle_map()  # M is the shipyard's mirror key too
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("shipyard") and not _pause.visible:
		if shipyard != null:
			close_shipyard()
		elif on_test_flight():
			sync.end_test()
		else:
			open_shipyard()
		get_viewport().set_input_as_handled()


func _toggle_map() -> void:
	map.visible = not map.visible
	hud.map_open = map.visible


## Where you are and which way you face, for the map: your ship's heading aboard,
## the way you look ashore.
func _you() -> Array:
	var facing := -player.camera.global_basis.z
	var heading := ship.heading() if ship != null else atan2(-facing.x, -facing.z)
	return [player.world_position(), heading]


func _build_pause_menu() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	var center := CenterContainer.new()
	center.theme = UiTheme.build()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	_pause = PanelContainer.new()
	_pause.visible = false
	center.add_child(_pause)
	var column := VBoxContainer.new()
	_pause.add_child(column)
	_resume = UiTheme.button("Resume", _toggle_pause)
	column.add_child(_resume)
	column.add_child(UiTheme.button("Leave game", session.leave))


func _toggle_pause() -> void:
	_pause.visible = not _pause.visible
	if player != null:
		player.enabled = not _pause.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _pause.visible else Input.MOUSE_MODE_CAPTURED
	if _pause.visible:
		_resume.grab_focus()
