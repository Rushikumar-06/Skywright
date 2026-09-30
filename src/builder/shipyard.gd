class_name Shipyard
extends CanvasLayer
## The shipyard screen at the dock (spec §3.8): the design in a 3D view you build
## on block by block, the block palette and paint, the design's stats, warnings and
## balance markers, blueprints, and buttons to take her on a test flight or launch
## her. The World opens and closes it (B or Esc) and carries out the requests.

signal test_flight_requested(grid: ShipGrid)
signal launch_requested(grid: ShipGrid)
signal close_requested

const SWATCHES := ["e9dfc9", "c0392b", "2f5d8a", "2e7d4f", "e8a948", "3d3a3f", "7d5a6b", "f2ead8"]
const NO_HELM := "Every ship needs a helm."
const HELP := "Left click place · Right click remove · Right-drag or WASD orbit · Wheel zoom · R turn · T tip"
const DRAG_THRESHOLD := 6.0  ## Pixels a right-drag moves before it orbits instead of removing.
const KEY_ORBIT := 600.0     ## Pixels' worth of orbit a second while W A S D are held.

var design: ShipDesign
var view: BuildView
var stats: ShipStats
var selected := "frame"
var block_rotation := 0  ## The way the selected block faces. (CanvasLayer has its own rotation.)
var blueprint_dir := Blueprint.DIR
var blueprint_name := Blueprint.DEFAULT_NAME

var _altitude := 0.0
var _confirm_path := ""  ## A save asked to replace this file; saving it again does.
var _container: SubViewportContainer
var _palette: Dictionary = {}  ## Block type -> its Button.
var _block_name: Label
var _block_stats: Label
var _block_about: Label
var _stats: Label
var _warnings: Label
var _note: Label
var _test_button: Button
var _launch_button: Button
var _undo_button: Button
var _redo_button: Button
var _mirror_button: Button
var _blueprints: PanelContainer
var _name_edit: LineEdit
var _files: VBoxContainer
var _drag_from := Vector2.ZERO  ## Where the right button went down.
var _dragging := false


func _init(for_design: ShipDesign, at_altitude: float) -> void:
	design = for_design
	_altitude = at_altitude


func _ready() -> void:
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_container.gui_input.connect(_on_view_input)
	add_child(_container)
	view = BuildView.new()
	_container.add_child(view)

	var theme := UiTheme.build()
	add_child(_build_palette(theme))
	add_child(_build_readout(theme))
	add_child(_build_bar(theme))
	design.changed.connect(_refresh)
	select(selected)
	_refresh()


## Picks the block to place.
func select(type: String) -> void:
	selected = type
	for each: String in _palette:
		(_palette[each] as Button).set_pressed_no_signal(each == type)
	var info: Dictionary = Blocks.INFO[type]
	_block_name.text = info["name"]
	_block_stats.text = "%d kg · %d hit points" % [roundi(Tuning.BLOCKS[type]["mass"]), Tuning.BLOCKS[type]["hp"]]
	_block_about.text = info["about"]


## A click at point in the view: left places the selected block, right removes one.
func click(point: Vector2, button: MouseButton) -> void:
	var aimed := view.aim(point, design.grid)
	if button == MOUSE_BUTTON_LEFT and aimed.has("place"):
		design.place(aimed["place"], selected, block_rotation)
	elif button == MOUSE_BUTTON_RIGHT and aimed.has("remove"):
		design.remove(aimed["remove"])


func save_blueprint(ship_name: String) -> void:
	if design.grid.cells_of("helm").is_empty():
		_note.text = NO_HELM
		return
	var clean := Blueprint.clean_name(ship_name)
	var path := Blueprint.path_for(clean, blueprint_dir)
	if FileAccess.file_exists(path) and _confirm_path != path:
		_confirm_path = path
		_note.text = "\"%s\" already exists. Save again to replace it." % clean
		return
	_confirm_path = ""
	var error := Blueprint.save(design.grid, clean, blueprint_dir)
	if error != OK:
		_note.text = "Couldn't save \"%s\" (%s)." % [clean, error_string(error)]
		return
	blueprint_name = clean
	_name_edit.text = clean
	_note.text = "Saved \"%s\"." % clean
	_list_files()


func load_blueprint(path: String) -> void:
	var read := Blueprint.load_file(path)
	if read.has("problem"):
		_note.text = read["problem"]
		return
	blueprint_name = read["name"]
	_name_edit.text = blueprint_name
	design.replace(read["grid"])
	_note.text = "Loaded \"%s\"." % blueprint_name


func stats_text() -> String:
	return stats.describe()


func warnings_text() -> String:
	return "\n".join(stats.warnings) if not stats.warnings.is_empty() else "No warnings. She should fly."


func note_text() -> String:
	return _note.text


func _unhandled_input(event: InputEvent) -> void:
	var handled := true
	if event.is_action_pressed("turn_block"):
		block_rotation = Blocks.turned(block_rotation)
	elif event.is_action_pressed("tip_block"):
		block_rotation = Blocks.tipped(block_rotation)
	elif event.is_action_pressed("mirror"):
		_toggle_mirror()
	elif event.is_action_pressed("redo"):  # before undo: Ctrl+Shift+Z matches undo's Ctrl+Z too
		design.redo()
	elif event.is_action_pressed("undo"):
		design.undo()
	elif event.is_action_pressed("test_flight"):
		if not _test_button.disabled:
			_request(test_flight_requested)
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var keys := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if keys != Vector2.ZERO:
		view.orbit(keys * KEY_ORBIT * delta)


func _on_view_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				click(button.position, MOUSE_BUTTON_LEFT)
			MOUSE_BUTTON_RIGHT:
				_drag_from = button.position
				_dragging = false
			MOUSE_BUTTON_WHEEL_UP:
				view.zoom(0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				view.zoom(1.1)
	elif button != null and button.button_index == MOUSE_BUTTON_RIGHT and not _dragging:
		click(button.position, MOUSE_BUTTON_RIGHT)
	var motion := event as InputEventMouseMotion
	if motion != null:
		if motion.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_dragging = _dragging or motion.position.distance_to(_drag_from) > DRAG_THRESHOLD
			if _dragging:
				view.orbit(motion.relative)
		_aim_ghost(motion.position)
	elif button != null:
		_aim_ghost(button.position)


func _aim_ghost(point: Vector2) -> void:
	var aimed := view.aim(point, design.grid)
	if aimed.has("place"):
		view.show_ghost(selected, block_rotation, aimed["place"], design.can_place(aimed["place"]))
	else:
		view.hide_ghost()


func _refresh() -> void:
	stats = ShipStats.of(design.grid, _altitude)
	view.show_design(design.grid, stats, design.mirror)
	_stats.text = stats_text()
	_warnings.text = warnings_text()
	_warnings.add_theme_color_override("font_color", UiTheme.WARNING if not stats.warnings.is_empty() else UiTheme.TEXT_DIM)
	var no_helm := design.grid.cells_of("helm").is_empty()
	_test_button.disabled = no_helm
	_launch_button.disabled = no_helm
	if no_helm:
		_note.text = NO_HELM
	elif _note.text == NO_HELM:
		_note.text = ""
	_undo_button.disabled = not design.can_undo()
	_redo_button.disabled = not design.can_redo()
	_mirror_button.text = "Mirror: %s (M)" % ("on" if design.mirror else "off")


func _toggle_mirror() -> void:
	design.mirror = not design.mirror
	_refresh()


func _request(request: Signal) -> void:
	_note.text = "Launching…"
	request.emit(design.grid.copy())


func _list_files() -> void:
	for child in _files.get_children():
		child.queue_free()
	_files.add_child(_small(UiTheme.button("Starter ship", func() -> void: design.replace(StarterShip.build()))))
	for path in Blueprint.list(blueprint_dir):
		_files.add_child(_small(UiTheme.button(path.get_file().trim_suffix(Blueprint.EXTENSION), load_blueprint.bind(path))))


func _open_folder() -> void:
	DirAccess.make_dir_recursive_absolute(blueprint_dir)
	OS.shell_open(ProjectSettings.globalize_path(blueprint_dir))


## The left panel: the blocks by group, the selected block, and paint.
func _build_palette(theme: Theme) -> Control:
	var panel := PanelContainer.new()
	panel.theme = theme
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.custom_minimum_size.x = 340
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	column.add_child(UiTheme.caption("Shipyard"))
	for group: String in Blocks.GROUPS:
		column.add_child(UiTheme.gap(8))
		column.add_child(UiTheme.caption(group))
		for type: String in Blocks.INFO:
			if Blocks.INFO[type]["group"] != group:
				continue
			var b := _small(UiTheme.button("%s   %d kg" % [Blocks.INFO[type]["name"], roundi(Tuning.BLOCKS[type]["mass"])], select.bind(type)))
			b.toggle_mode = true
			_palette[type] = b
			column.add_child(b)
	column.add_child(UiTheme.gap(16))
	_block_name = Label.new()
	column.add_child(_block_name)
	_block_stats = UiTheme.caption("")
	column.add_child(_block_stats)
	_block_about = UiTheme.caption("")
	_block_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_block_about)
	column.add_child(UiTheme.gap(8))
	var paints := HFlowContainer.new()
	for hex: String in SWATCHES:
		var swatch := Button.new()
		swatch.tooltip_text = hex
		swatch.custom_minimum_size = Vector2(28, 28)
		var box := StyleBoxFlat.new()
		box.bg_color = Color(hex)
		box.set_corner_radius_all(4)
		for state in ["normal", "hover", "pressed", "focus"]:
			swatch.add_theme_stylebox_override(state, box)
		swatch.pressed.connect(func() -> void: design.set_paint(selected, Color(hex)))
		paints.add_child(swatch)
	paints.add_child(_small(UiTheme.button("Default", func() -> void: design.set_paint(selected, null))))
	column.add_child(paints)
	return panel


## The right panel: stats, warnings, the marker legend, and the blueprints.
func _build_readout(theme: Theme) -> Control:
	var right := VBoxContainer.new()
	right.theme = theme
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.offset_right = -24
	right.offset_top = 24
	var panel := PanelContainer.new()
	right.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	_stats = Label.new()
	_stats.add_theme_font_override("font", Hud.monospace())
	column.add_child(_stats)
	column.add_child(UiTheme.gap(8))
	_warnings = Label.new()
	column.add_child(_warnings)
	column.add_child(UiTheme.gap(8))
	var legend := HBoxContainer.new()
	for entry: Array in [[BuildView.MASS_COLOR, "● Weight (centre of mass)"], [BuildView.LIFT_COLOR, "● Lift (centre of lift)"]]:
		var label := Label.new()
		label.text = entry[1]
		label.add_theme_color_override("font_color", entry[0])
		label.add_theme_font_size_override("font_size", 16)
		legend.add_child(label)
	column.add_child(legend)

	_blueprints = PanelContainer.new()
	_blueprints.visible = false
	right.add_child(_blueprints)
	var files := VBoxContainer.new()
	_blueprints.add_child(files)
	var row := HBoxContainer.new()
	_name_edit = LineEdit.new()
	_name_edit.text = blueprint_name
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(save_blueprint)
	row.add_child(_name_edit)
	row.add_child(_small(UiTheme.button("Save", func() -> void: save_blueprint(_name_edit.text))))
	files.add_child(row)
	_files = VBoxContainer.new()
	files.add_child(_files)
	files.add_child(_small(UiTheme.button("Open folder", _open_folder)))
	return right


## The bottom bar: the actions, the controls, and the note.
func _build_bar(theme: Theme) -> Control:
	var panel := PanelContainer.new()
	panel.theme = theme
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -24
	var column := VBoxContainer.new()
	panel.add_child(column)
	var buttons := HBoxContainer.new()
	_test_button = _small(UiTheme.button("Test flight (F)", _request.bind(test_flight_requested)))
	_launch_button = _small(UiTheme.button("Launch", _request.bind(launch_requested)))
	_undo_button = _small(UiTheme.button("Undo", design.undo))
	_redo_button = _small(UiTheme.button("Redo", design.redo))
	_mirror_button = _small(UiTheme.button("Mirror: off (M)", _toggle_mirror))
	var toggle_files := func() -> void:
		_blueprints.visible = not _blueprints.visible
		if _blueprints.visible:
			_list_files()
	for b: Button in [_test_button, _launch_button, _undo_button, _redo_button, _mirror_button,
			_small(UiTheme.button("Blueprints", toggle_files)), _small(UiTheme.button("Close (B)", close_requested.emit))]:
		buttons.add_child(b)
	column.add_child(buttons)
	column.add_child(UiTheme.caption(HELP))
	_note = Label.new()
	_note.add_theme_color_override("font_color", UiTheme.ACCENT)
	column.add_child(_note)
	return panel


static func _small(b: Button) -> Button:
	b.add_theme_font_size_override("font_size", 18)
	return b
