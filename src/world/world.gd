extends Node3D
## The game world: sky, the Roil, a few placeholder islands, the dock, and the
## starter ship at its first slipway with you aboard. Its Session is a sibling: the
## Session autoload in the game, or a test's own. The server builds the ships and
## flies them; clients get them through the world's WorldSync. You board the host's
## ship when you arrive, and your own ship whenever one arrives. When the ship
## you're on goes, you board its successor, or the ship you came from, or the
## host's. A dedicated server's world has no player, HUD or pause menu.

## Where the ship starts: over the Calm Reaches, 7 km from the Eye.
const START := Vector3(0.0, 880.0, 7000.0)
## Placeholder islands: [offset from START, radius].
const ISLANDS := [
	[Vector3(-160, -40, -520), 60.0], [Vector3(380, 30, -1100), 110.0], [Vector3(-620, -110, -1500), 90.0],
	[Vector3(120, -150, -300), 34.0], [Vector3(900, -60, -200), 80.0], [Vector3(-1000, 20, -600), 120.0],
	[Vector3(-300, 80, 700), 70.0], [Vector3(600, -20, 900), 95.0],
]

var session: Node
var sync: WorldSync
var ship: Ship                 ## The ship you're aboard.
var player: PlayerController   ## You, once the ship has arrived.
var hud: Hud
var dock: StaticBody3D

var _came_from: Ship           ## The ship you were on before this one, while it's still here.

var _sky: WorldSky
var _pause: PanelContainer
var _resume: Button


func _ready() -> void:
	session = get_node("../Session")
	_sky = WorldSky.new()
	add_child(_sky)
	add_child(Roil.new())
	for island: Array in ISLANDS:
		add_child(Island.create(START + island[0], island[1]))
	dock = Dock.create(START)
	add_child(dock)
	sync = WorldSync.new(session)
	sync.ship_added.connect(_on_ship_added)
	sync.ship_removed.connect(_on_ship_removed)
	add_child(sync)
	if session.is_server():
		sync.add_ship(StarterShip.build(), Dock.slipway(START, 0), 0 if session.dedicated else 1)
	if not session.dedicated:
		_build_pause_menu()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	_sky.hour = WorldSky.hour_at(sync.now())


## Your place in the roster, which is where you stand when you board: crew board
## at different spots, in the order they joined.
func my_slot() -> int:
	return maxi(0, session.players.keys().find(multiplayer.get_unique_id()))


## Puts you aboard target at spot (-1 for your roster slot), with your controls.
func board(target: Ship, spot := -1) -> void:
	var crew := CrewMember.new(target, target.crew_spawn(my_slot() if spot < 0 else spot))
	target.interior.add_child(crew)
	if player == null:
		player = PlayerController.new(crew)
		add_child(player)
		sync.player = player
		hud = Hud.new(player, session)
		add_child(hud)
	else:
		_came_from = ship if sync.id_of(ship) != 0 else null  # a ship on its way out can't be gone back to
		var old_crew := player.crew
		player.board(crew)
		old_crew.queue_free()
	ship = target


func _on_ship_added(added: Ship) -> void:
	if session.dedicated:
		return
	if added.captain == multiplayer.get_unique_id():
		board(added, 0)
	elif player == null and added == sync.home_ship():
		board(added)


func _on_ship_removed(removed: Ship, successor: Ship) -> void:
	if _came_from == removed:
		_came_from = null
	if ship != removed:
		return
	for next: Ship in [successor, _came_from, sync.home_ship()]:
		if next != null:
			board(next)
			return


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and _pause != null:
		_toggle_pause()
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
