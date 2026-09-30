extends TestCase
## Project settings the design depends on (spec §4.1).


func test_physics_is_jolt_at_60_ticks_with_interpolation() -> void:
	assert_eq(ProjectSettings.get_setting("physics/3d/physics_engine"), "Jolt Physics")
	assert_eq(ProjectSettings.get_setting("physics/3d/default_gravity"), 9.81)
	assert_eq(ProjectSettings.get_setting("physics/common/physics_ticks_per_second"), 60)
	assert_eq(ProjectSettings.get_setting("physics/common/physics_interpolation"), true)


func test_renderer_is_forward_plus() -> void:
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"), "forward_plus")


func test_input_actions_have_their_default_keys() -> void:
	var expected := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"descend": [KEY_CTRL, KEY_C],
		"sprint": [KEY_SHIFT],
		"interact": [KEY_E],
		"toggle_camera": [KEY_V],
		"autopilot": [KEY_H],
		"anchor": [KEY_G],
		"pause": [KEY_ESCAPE],
		"shipyard": [KEY_B],
		"turn_block": [KEY_R],
		"tip_block": [KEY_T],
		"mirror": [KEY_M],
		"map": [KEY_M],
		"undo": [KEY_Z],
		"redo": [KEY_Y, KEY_Z],
		"test_flight": [KEY_F],
	}
	for action: String in expected:
		assert_true(InputMap.has_action(action), "%s exists" % action)
		if not InputMap.has_action(action):
			continue
		var keys := []
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				keys.append((event as InputEventKey).physical_keycode)
		for key: int in expected[action]:
			assert_true(keys.has(key), "%s is bound to %s" % [action, OS.get_keycode_string(key)])


func test_undo_and_redo_take_ctrl() -> void:
	var expected := {"undo": [[KEY_Z, false]], "redo": [[KEY_Y, false], [KEY_Z, true]]}  # [key, shift]
	for action: String in expected:
		var found := []
		for event in InputMap.action_get_events(action) if InputMap.has_action(action) else []:
			var k := event as InputEventKey
			if k != null and k.ctrl_pressed:
				found.append([k.physical_keycode, k.shift_pressed])
		for combo: Array in expected[action]:
			assert_true(found.has(combo), "%s is bound to Ctrl+%s%s" % [action, "Shift+" if combo[1] else "", OS.get_keycode_string(combo[0])])


func test_every_script_compiles() -> void:
	for path in _scripts_under("res://src"):
		var script := load(path) as Script
		assert_true(script != null and script.can_instantiate(), "%s compiles" % path)


func _scripts_under(dir: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			found.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_scripts_under(dir.path_join(sub)))
	return found
