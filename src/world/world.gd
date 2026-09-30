extends Node3D
## The game world: sky, the Roil, the islands made from the session's seed (streamed
## in around every ship), the dock, and the starter ship at its first slipway with
## you aboard. Its Session is a sibling: the Session autoload in the game, or a
## test's own. The server builds the ships and flies them; clients get them through
## the world's WorldSync. You board the host's ship when you arrive, and your own
## ship whenever one arrives: launch a design and you're at its helm, and B brings
## you back from a test flight. When the ship you're on goes, you board its
## successor, or the ship you came from, or your own, or the host's. A dedicated
## server's world has no player, HUD or pause menu.

## Where the ship starts: over the Calm Reaches, 7 km from the Eye.
const START := WorldGen.START

var session: Node
var sync: WorldSync
var ship: Ship                 ## The ship you're aboard.
var player: PlayerController   ## You, once the ship has arrived.
var hud: Hud
var dock: StaticBody3D
var shipyard: Shipyard         ## Null while closed.
var design: ShipDesign         ## Your design, kept for the whole game.
var gen: WorldGen              ## The world made from the session's seed.
var wind: Wind                 ## Its wind, on the world's clock.
var streamer: WorldStreamer    ## Loads its chunks around every ship and player.

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
	dock = Dock.create(START)
	add_child(dock)
	sync = WorldSync.new(session)
	sync.wind = wind
	sync.ship_added.connect(_on_ship_added)
	sync.ship_removed.connect(_on_ship_removed)
	for index in Dock.SLIPWAYS:
		sync.berths.append(Dock.slipway(START, index))
		sync.test_berths.append(Dock.test_berth(START, index))
	sync.obstacles = Dock.obstacles(START)
	add_child(sync)
	if session.is_server():
		sync.add_ship(StarterShip.build(), Dock.slipway(START, 0), 0 if session.dedicated else 1)
	streamer = WorldStreamer.new(gen, not session.dedicated)
	streamer.focus = sync.focus_points
	add_child(streamer)
	if not session.dedicated:
		_build_pause_menu()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	_sky.hour = WorldSky.hour_at(sync.now())
	if hud != null:
		hud.test_flight = on_test_flight()
		hud.at_dock = at_dock()


## Your place in the roster, which is where you stand when you board: crew board
## at different spots, in the order they joined.
func my_slot() -> int:
	return maxi(0, session.players.keys().find(multiplayer.get_unique_id()))


## Takes grid for a test flight from your test berth, at its helm.
func test_flight(grid: ShipGrid) -> void:
	_launch(grid, true)


## Launches grid as your ship, at your slipway and at its helm. It replaces your old
## ship, whose crew come too.
func launch(grid: ShipGrid) -> void:
	_launch(grid, false)


func _launch(grid: ShipGrid, test: bool) -> void:
	if not sync.launch(grid, test) and shipyard != null:
		shipyard.say("Wait a moment, then try again.")


## Whether you're aboard your own test flight.
func on_test_flight() -> bool:
	return ship != null and ship.test and ship.captain == multiplayer.get_unique_id()


## Whether your crew member, where the world draws them, is near the dock.
func at_dock() -> bool:
	return player != null and Dock.near(START, ship.global_transform * player.crew.position)


## Puts you aboard target at spot (-1 for your roster slot), with your controls.
func board(target: Ship, spot := -1) -> void:
	var crew := CrewMember.new(target, target.crew_spawn(my_slot() if spot < 0 else spot))
	target.interior.add_child(crew)
	if player == null:
		player = PlayerController.new(crew)
		add_child(player)
		sync.player = player
		hud = Hud.new(player, session)
		hud.wind = wind
		add_child(hud)
	else:
		var here := sync.id_of(ship) != 0  # a ship on its way out can't be gone back to
		if here and player.crew.station != null:
			ship.helm.ask_helm(player.peer, false)  # or nobody else could take her helm until you left
		if not on_test_flight():  # from a second test flight, B still goes back where the first came from
			_came_from = ship if here else null
		var old_crew := player.crew
		player.board(crew)
		old_crew.queue_free()
	ship = target


## Opens the shipyard on your design, when you're at the dock or dock_only is off.
func open_shipyard(dock_only := true) -> void:
	if shipyard != null or player == null:
		return
	if dock_only and not at_dock():
		hud.show_message("The shipyard is at the dock.")
		return
	if design == null:
		design = ShipDesign.new(ship.grid)
	shipyard = Shipyard.new(design, START.y)
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
	if ship != removed:
		return
	for next: Ship in [successor, _came_from, sync.ship_of(multiplayer.get_unique_id(), false), sync.home_ship()]:
		if next != null:
			board(next)
			if removed.test and removed.captain == multiplayer.get_unique_id() and not _pause.visible:
				open_shipyard(false)  # back from a test flight
			return


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_viewport().disable_3d = false  # the session can end with the shipyard open


func _unhandled_input(event: InputEvent) -> void:
	if _pause == null:
		return
	if event.is_action_pressed("pause"):
		if shipyard != null:
			close_shipyard()
		else:
			_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("shipyard") and not _pause.visible:
		if shipyard != null:
			close_shipyard()
		elif on_test_flight():
			sync.end_test()
		else:
			open_shipyard()
		get_viewport().set_input_as_handled()


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
