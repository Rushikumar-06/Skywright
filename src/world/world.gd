extends Node3D
## The game world: sky, the Roil, a few placeholder islands, and the starter ship
## with you aboard. In stage 2 every copy of the game flies its own ship; stage 3
## shares one between the crew.

## Where the ship starts: over the Calm Reaches, 7 km from the Eye.
const START := Vector3(0.0, 880.0, 7000.0)
## Placeholder islands: [offset from START, radius].
const ISLANDS := [
	[Vector3(-160, -40, -520), 60.0], [Vector3(380, 30, -1100), 110.0], [Vector3(-620, -110, -1500), 90.0],
	[Vector3(120, -150, -300), 34.0], [Vector3(900, -60, -200), 80.0], [Vector3(-1000, 20, -600), 120.0],
	[Vector3(-300, 80, 700), 70.0], [Vector3(600, -20, 900), 95.0],
]

var ship: Ship
var player: PlayerController
var hud: Hud

var _pause: PanelContainer
var _resume: Button


func _ready() -> void:
	add_child(WorldSky.new())
	add_child(Roil.new())
	for island: Array in ISLANDS:
		add_child(Island.create(START + island[0], island[1]))
	ship = Ship.new(StarterShip.build())
	ship.position = START
	add_child(ship)
	var crew := CrewMember.new(ship, ship.crew_spawn())
	ship.interior.add_child(crew)
	player = PlayerController.new(crew)
	add_child(player)
	hud = Hud.new(player)
	add_child(hud)
	_build_pause_menu()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
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
	column.add_child(UiTheme.button("Leave game", Session.leave))


func _toggle_pause() -> void:
	_pause.visible = not _pause.visible
	player.enabled = not _pause.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _pause.visible else Input.MOUSE_MODE_CAPTURED
	if _pause.visible:
		_resume.grab_focus()
