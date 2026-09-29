# Stage 1: Foundations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Godot 4.7.2 project for Skywright that opens to a main menu on this laptop's GPU. From the menu you can play solo, host, join and leave between two copies of the game, and every test runs headless with one command.

**Architecture:**
- Three autoloads carry the foundations:
  - `Settings` holds player settings and persists them.
  - `Session` holds the network role: solo, host or client. It also runs the join handshake over ENet.
  - `Game` handles scene flow between the menu and the world, and applies launch options.
- The UI is built in code from small scripts, with a shared theme and a sky backdrop.
- A custom headless test runner runs GDScript tests. A test fails when an assert fails, or when the engine logs more errors during it than the test allows.

**Tech Stack:** Godot 4.7.2 (standard build, installed at `~/.local/bin/godot`), statically typed GDScript, Jolt Physics, ENet (built in), and bash for `run_tests.sh`.

**Spec:** `docs/superpowers/specs/2026-09-29-skywright-design.md`

## Global Constraints

- Godot 4.7.2 standard build, GDScript with static types everywhere, and no addons or other dependencies.
- `physics/3d/physics_engine="Jolt Physics"`, 60 physics ticks per second, physics interpolation on, and the Forward+ renderer.
- One unit is one metre.
- Networking constants:
  - UDP port 24650.
  - Up to 8 players, host included.
  - `PROTOCOL_VERSION := 1`.
  - Clients give up after 8 s without being accepted.
- Player names are trimmed and control characters become spaces. Names are capped at 24 characters, and an empty name becomes `"Captain"`.
- Settings are saved in `user://settings.cfg`.
- Player-facing messages use the spec §7 wording:
  - "The host ended the game."
  - "The host didn't answer."
  - "Lost the connection to the host."
  - "The game is full."
  - "Port 24650 is already in use. Is another game running?"
  - The version-mismatch message names both versions.
- Folders are created only when a task needs them.
- Commit messages never include a `Co-Authored-By` line (user rule).

## Review Focus

1. **A mistyped address** (a trailing `:`, `http://…`, spaces, a port over 65535) is refused with an example of a valid address and never crashes. Test: `test_parse_address_refuses_junk` in Task 4.
2. **Hosting while another copy already holds port 24650** fails cleanly: `host()` returns `ERR_CANT_CREATE`, the mode stays `NONE`, and the menu shows the port message. Test: `test_hosting_on_a_busy_port_fails_cleanly` in Task 4.
3. **Pressing Back while connecting** cancels once. It emits `ended("")` and no later "didn't answer" message arrives. Test: `test_leaving_while_connecting_cancels_cleanly` in Task 4.
4. **A joiner's name arrives blank, overlong or with newlines**, and the host cleans it before anyone sees it. Test: `test_host_cleans_joiner_names` in Task 4.
5. **Hosting on a machine with no LAN address**: the HUD says which port to use and doesn't crash on an empty list. Test: `test_lan_addresses` (empty case) in Task 4.

---

## File structure

| File | Responsibility |
|---|---|
| `project.godot` | Engine settings, autoloads, main scene, input map |
| `run_tests.sh` | Import the project, then run the test runner. `./run_tests.sh [filter]` |
| `tests/test_case.gd` | `TestCase` base class: asserts, `wait_until`, `after_each`, `allowed_engine_errors` |
| `tests/run_tests.gd` | Finds and runs `test_*` methods and counts engine errors. Exits 0 or 1. |
| `tests/test_test_case.gd` | Tests for the assert helpers |
| `tests/test_project.gd` | Tests for project settings, the input map, and every script compiling |
| `src/core/settings.gd` | `Settings` autoload: load, clean, save and apply player settings |
| `tests/test_settings.gd` | Settings tests |
| `src/net/session.gd` | `Session` autoload: modes, host, join, leave, handshake, roster, address helpers |
| `tests/test_session.gd` | Session tests (in-process ENet loopback) |
| `src/core/launch_options.gd` | `LaunchOptions`: parses `-- --host/--join/--name/--port` |
| `tests/test_launch_options.gd` | Launch option tests |
| `src/core/game.gd` | `Game` autoload: scene flow, menu message, launch options |
| `src/ui/ui_theme.gd` | `UiTheme`: the shared Theme plus label and button helpers |
| `src/world/sky_backdrop.gd` | `SkyBackdrop`: sky, sun, fog, placeholder islands, drifting camera |
| `src/ui/settings_panel.gd` | `SettingsPanel`: the settings form |
| `src/ui/main_menu.gd`, `.tscn` | Main menu |
| `src/world/world.gd`, `.tscn` | World placeholder: backdrop, session HUD, pause menu |
| `tests/test_scenes.gd` | The menu and world scenes build without engine errors |
| `README.md` | What it is, how to run, test and play online, and the project layout |

---

### Task 1: Test runner

**Files:**
- Create: `project.godot`, `run_tests.sh`, `tests/test_case.gd`, `tests/run_tests.gd`, `tests/test_test_case.gd`

**Interfaces:**
- Produces:
  - `class_name TestCase extends Node`, with:
    - `failures: PackedStringArray`
    - `allowed_engine_errors: int`
    - `after_each() -> void`
    - `assert_true(value: bool, message := "")`
    - `assert_false(value: bool, message := "")`
    - `assert_eq(actual: Variant, expected: Variant, message := "")`
    - `assert_near(actual: float, expected: float, tolerance: float, message := "")`
    - `wait_until(condition: Callable, timeout: float) -> bool`, a coroutine you `await`
  - `./run_tests.sh [filter]`, which exits 0 when every selected test passes.

- [ ] **Step 1: Write a minimal project file**

`project.godot`:
```ini
; Engine configuration file.
; It's best edited using the editor UI and not directly,
; since the parameters that go here are not all obvious.

config_version=5

[application]

config/name="Skywright"
```

- [ ] **Step 2: Write the TestCase base class**

`tests/test_case.gd`:
```gdscript
class_name TestCase
extends Node
## Base class for tests. The runner makes a fresh instance for each test_* method,
## adds it to the scene tree, awaits the method, awaits after_each(), then frees it.

## Assertion failures recorded while the current test runs.
var failures: PackedStringArray = []
## Engine errors this test may log on purpose (for example when it loads a broken
## file). More errors than this fail the test.
var allowed_engine_errors := 0


## Override to clean up after each test: close sockets, delete temp files.
func after_each() -> void:
	pass


func assert_true(value: bool, message := "") -> void:
	if not value:
		_fail("expected true", message)


func assert_false(value: bool, message := "") -> void:
	if value:
		_fail("expected false", message)


## Passes when both values have the same type and compare equal.
func assert_eq(actual: Variant, expected: Variant, message := "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		_fail("expected %s, got %s" % [var_to_str(expected), var_to_str(actual)], message)


func assert_near(actual: float, expected: float, tolerance: float, message := "") -> void:
	if not absf(actual - expected) <= tolerance:
		_fail("expected %s ± %s, got %s" % [expected, tolerance, actual], message)


## Waits a frame at a time until condition returns true or timeout seconds pass,
## and returns whether it came true. Use it as: await wait_until(...)
func wait_until(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await get_tree().process_frame
	return true


func _fail(what: String, message: String) -> void:
	failures.append(what if message.is_empty() else "%s: %s" % [message, what])
```

- [ ] **Step 3: Write the runner**

`tests/run_tests.gd`:
```gdscript
extends SceneTree
## Runs every tests/**/test_*.gd headless and exits 0 when all pass, 1 otherwise.
## Run it through ./run_tests.sh, which imports the project first so class_name
## scripts resolve on a fresh checkout. An optional argument after "--" keeps only
## test files whose name contains it. A test fails when an assert fails or when the
## engine logs more errors during it than the test allows.

const TEST_ROOT := "res://tests"


## Counts engine and script errors so a crash inside a test can't pass silently.
class ErrorCounter extends Logger:
	var count := 0
	var last := ""
	var _lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		count += 1
		last = "%s (%s:%d, %s)" % [rationale if rationale else code, file, line, function]
		_lock.unlock()


var _errors := ErrorCounter.new()


func _initialize() -> void:
	OS.add_logger(_errors)
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var filter := args[0] if not args.is_empty() else ""
	var passed := 0
	var failed := 0
	for path in _find_tests(TEST_ROOT):
		if not path.get_file().contains(filter):
			continue
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			failed += 1
			print("  FAIL  %s: could not load" % path)
			continue
		for method in script.get_script_method_list():
			var test_name: String = method["name"]
			if not test_name.begins_with("test_"):
				continue
			var problems := await _run_one(script, test_name)
			var label := "%s :: %s" % [path.get_file().get_basename(), test_name]
			if problems.is_empty():
				passed += 1
				print("  ok    ", label)
			else:
				failed += 1
				print("  FAIL  ", label)
				for problem in problems:
					print("        ", problem)
	print("\n%d passed, %d failed" % [passed, failed])
	OS.remove_logger(_errors)
	quit(0 if failed == 0 and passed > 0 else 1)


func _run_one(script: GDScript, test_name: String) -> PackedStringArray:
	var instance: Object = script.new()
	if not instance is TestCase:
		return PackedStringArray(["does not extend TestCase"])
	var test := instance as TestCase
	root.add_child(test)
	var errors_before := _errors.count
	await test.call(test_name)
	await test.after_each()
	var problems := test.failures.duplicate()
	var new_errors := _errors.count - errors_before
	if new_errors > test.allowed_engine_errors:
		problems.append("engine logged %d error(s), last: %s" % [new_errors, _errors.last])
	test.queue_free()
	await process_frame
	return problems


func _find_tests(dir: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for file in DirAccess.get_files_at(dir):
		if file.begins_with("test_") and file.ends_with(".gd") and file != "test_case.gd":
			found.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_find_tests(dir.path_join(sub)))
	found.sort()
	return found
```

- [ ] **Step 4: Write the one-command wrapper**

`run_tests.sh` (then `chmod +x run_tests.sh`):
```bash
#!/usr/bin/env bash
# Runs every test headless and exits non-zero if any fail.
#   ./run_tests.sh            all tests
#   ./run_tests.sh session    only test files whose name contains "session"
# Set GODOT to use a Godot binary other than the one on PATH.
set -euo pipefail
cd "$(dirname "$0")"
godot="${GODOT:-godot}"
# Importing builds Godot's class cache, which class_name scripts need on a fresh checkout.
if ! "$godot" --headless --import >/dev/null 2>&1; then
	echo "Import failed. Run '$godot --headless --import' to see why." >&2
	exit 1
fi
exec timeout 600 "$godot" --headless --script res://tests/run_tests.gd -- "$@"
```

- [ ] **Step 5: Write tests for the helpers**

`tests/test_test_case.gd`:
```gdscript
extends TestCase
## The assert helpers themselves, so a broken helper can't hide failures.


func test_assert_eq_fails_on_different_values_or_types() -> void:
	var probe := TestCase.new()
	probe.assert_eq(1, 2)
	probe.assert_eq(1, 1.0, "int and float differ")
	probe.assert_eq({"a": 1}, {"a": 1})
	assert_eq(probe.failures.size(), 2)
	probe.free()


func test_assert_near_fails_on_nan() -> void:
	var probe := TestCase.new()
	probe.assert_near(NAN, 0.0, 1.0)
	probe.assert_near(0.5, 0.0, 1.0)
	assert_eq(probe.failures.size(), 1)
	probe.free()


func test_wait_until_waits_frame_by_frame() -> void:
	var calls := [0]
	var third_call := func() -> bool:
		calls[0] += 1
		return calls[0] >= 3
	assert_true(await wait_until(third_call, 1.0))
	assert_eq(calls[0], 3)


func test_wait_until_gives_up_after_the_timeout() -> void:
	assert_false(await wait_until(func() -> bool: return false, 0.1))
```

- [ ] **Step 6: Run and see the helper tests pass**

Run: `./run_tests.sh`
Expected: 4 `ok` lines, then `4 passed, 0 failed`, exit code 0.

- [ ] **Step 7: Prove the runner catches failures**

Create a temporary `tests/test_zz_must_fail.gd`:
```gdscript
extends TestCase


func test_failing_assert() -> void:
	assert_eq(1, 2)


func test_failing_after_an_await() -> void:
	await get_tree().process_frame
	assert_true(false, "after a frame")


func test_runtime_error() -> void:
	var nothing: Node = null
	nothing.get_name()
```
Run: `./run_tests.sh; echo "exit=$?"`
Expected: 3 `FAIL` lines (the third reports "engine logged 1 error(s)"), then `4 passed, 3 failed` and `exit=1`.
Then delete it: `rm tests/test_zz_must_fail.gd`.

- [ ] **Step 8: Commit**

```bash
git add project.godot run_tests.sh tests/
git commit -m "Add headless test runner"
```

---

### Task 2: Project configuration

**Files:**
- Create: `tests/test_project.gd`
- Modify: `project.godot`

**Interfaces:**
- Produces:
  - Input actions: `move_forward`, `move_back`, `move_left`, `move_right`, `jump`, `descend`, `sprint`, `interact`, `toggle_camera`, `pause`.
  - Physics and renderer settings per the Global Constraints.

- [ ] **Step 1: Write the failing test**

`tests/test_project.gd`:
```gdscript
extends TestCase
## Project settings the design depends on (spec §4.1).


func test_physics_is_jolt_at_60_ticks_with_interpolation() -> void:
	assert_eq(ProjectSettings.get_setting("physics/3d/physics_engine"), "Jolt Physics")
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
		"pause": [KEY_ESCAPE],
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
```

- [ ] **Step 2: Run it and see it fail**

Run: `./run_tests.sh project`
Expected: FAIL on all three tests. The engine is `"DEFAULT"` and no actions exist.

- [ ] **Step 3: Configure the project**

Replace `project.godot` with:
```ini
; Engine configuration file.
; It's best edited using the editor UI and not directly,
; since the parameters that go here are not all obvious.

config_version=5

[application]

config/name="Skywright"
config/description="An airship game: build ships block by block, and physics decides if they fly."
config/version="0.1.0"
config/features=PackedStringArray("4.7", "Forward Plus")

[display]

window/size/viewport_width=1600
window/size/viewport_height=900
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"

[input]

move_forward={
"deadzone": 0.2,
"events": [Object(InputEventKey,"device":-1,"physical_keycode":87), Object(InputEventKey,"device":-1,"physical_keycode":4194320)]
}
move_back={
"deadzone": 0.2,
"events": [Object(InputEventKey,"device":-1,"physical_keycode":83), Object(InputEventKey,"device":-1,"physical_keycode":4194322)]
}
move_left={
"deadzone": 0.2,
"events": [Object(InputEventKey,"device":-1,"physical_keycode":65), Object(InputEventKey,"device":-1,"physical_keycode":4194319)]
}
move_right={
"deadzone": 0.2,
"events": [Object(InputEventKey,"device":-1,"physical_keycode":68), Object(InputEventKey,"device":-1,"physical_keycode":4194321)]
}
jump={
"deadzone": 0.2,
"events": [Object(InputEventKey,"device":-1,"physical_keycode":32)]
}
descend={
"deadzone": 0.2,
"events": [Object(InputEventKey,"device":-1,"physical_keycode":4194326), Object(InputEventKey,"device":-1,"physical_keycode":67)]
}
sprint={
"deadzone": 0.2,
"events": [Object(InputEventKey,"device":-1,"physical_keycode":4194325)]
}
interact={
"deadzone": 0.2,
"events": [Object(InputEventKey,"device":-1,"physical_keycode":69)]
}
toggle_camera={
"deadzone": 0.2,
"events": [Object(InputEventKey,"device":-1,"physical_keycode":86)]
}
pause={
"deadzone": 0.2,
"events": [Object(InputEventKey,"device":-1,"physical_keycode":4194305)]
}

[physics]

3d/physics_engine="Jolt Physics"
common/physics_ticks_per_second=60
common/physics_interpolation=true

[rendering]

renderer/rendering_method="forward_plus"
```

- [ ] **Step 4: Run it and see it pass**

Run: `./run_tests.sh`
Expected: `7 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add project.godot tests/test_project.gd
git commit -m "Configure Jolt physics, rendering and input actions"
```

---

### Task 3: Settings

**Files:**
- Create: `src/core/settings.gd`, `tests/test_settings.gd`
- Modify: `project.godot` (add the `[autoload]` section)

**Interfaces:**
- Produces the `Settings` autoload (script `res://src/core/settings.gd`, no `class_name`), with:
  - Constants: `PATH`, `DEFAULT_NAME := "Captain"`, `MAX_NAME_LENGTH := 24`, `DEFAULT_ADDRESS := "127.0.0.1"`.
  - Variables: `player_name: String`, `fullscreen: bool`, `vsync: bool`, `master_volume: float` (0–1), `mouse_sensitivity: float` (0.1–3), `last_address: String`.
  - Methods: `load_from(path: String) -> void`, `save_to(path: String) -> Error`, `save() -> void`, `apply() -> void`, `static clean_name(raw: String) -> String`.

- [ ] **Step 1: Write the failing tests**

`tests/test_settings.gd`:
```gdscript
extends TestCase
## Settings load, save and clean their values (spec §4.10).

const SettingsScript := preload("res://src/core/settings.gd")
const TEMP_PATH := "user://test_settings.cfg"

var _made: Array[Node] = []


func after_each() -> void:
	for node in _made:
		node.free()
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))


## A Settings instance outside the tree, so it neither loads nor applies the real file.
func fresh() -> SettingsScript:
	var settings := SettingsScript.new()
	_made.append(settings)
	return settings


func write_temp(text: String) -> void:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_missing_file_keeps_defaults() -> void:
	var settings := fresh()
	settings.load_from("user://no_such_settings.cfg")
	assert_eq(settings.player_name, "Captain")
	assert_eq(settings.master_volume, 0.8)
	assert_eq(settings.vsync, true)
	assert_eq(settings.last_address, "127.0.0.1")


func test_saved_settings_load_back_unchanged() -> void:
	var saved := fresh()
	saved.player_name = "Ann"
	saved.fullscreen = true
	saved.vsync = false
	saved.master_volume = 0.35
	saved.mouse_sensitivity = 2.25
	saved.last_address = "10.0.0.7:4000"
	assert_eq(saved.save_to(TEMP_PATH), OK)
	var loaded := fresh()
	loaded.load_from(TEMP_PATH)
	assert_eq(loaded.player_name, "Ann")
	assert_eq(loaded.fullscreen, true)
	assert_eq(loaded.vsync, false)
	assert_eq(loaded.master_volume, 0.35)
	assert_eq(loaded.mouse_sensitivity, 2.25)
	assert_eq(loaded.last_address, "10.0.0.7:4000")


func test_out_of_range_numbers_are_clamped() -> void:
	write_temp("[audio]\nmaster_volume=5.0\n[controls]\nmouse_sensitivity=-2\n")
	var settings := fresh()
	settings.load_from(TEMP_PATH)
	assert_eq(settings.master_volume, 1.0)
	assert_eq(settings.mouse_sensitivity, 0.1)


func test_wrong_types_fall_back_to_defaults() -> void:
	write_temp("[display]\nfullscreen=\"yes\"\n[audio]\nmaster_volume=\"loud\"\n[player]\nname=42\nlast_address=\"   \"\n")
	var settings := fresh()
	settings.load_from(TEMP_PATH)
	assert_eq(settings.fullscreen, false)
	assert_eq(settings.master_volume, 0.8)
	assert_eq(settings.player_name, "42")
	assert_eq(settings.last_address, "127.0.0.1")


func test_unreadable_file_keeps_defaults() -> void:
	allowed_engine_errors = 1  # ConfigFile reports the parse error.
	write_temp("[[[ this is not a config file")
	var settings := fresh()
	settings.load_from(TEMP_PATH)
	assert_eq(settings.player_name, "Captain")
	assert_eq(settings.master_volume, 0.8)


func test_names_are_cleaned() -> void:
	assert_eq(SettingsScript.clean_name("  Ann  "), "Ann")
	assert_eq(SettingsScript.clean_name("   "), "Captain")
	assert_eq(SettingsScript.clean_name("Ann\nBob\t"), "Ann Bob")
	assert_eq(SettingsScript.clean_name("x".repeat(40)).length(), 24)
```

- [ ] **Step 2: Run it and see it fail**

Run: `./run_tests.sh settings`
Expected: `FAIL tests/test_settings.gd: could not load`, because `settings.gd` doesn't exist.

- [ ] **Step 3: Implement Settings**

`src/core/settings.gd`:
```gdscript
extends Node
## Player settings, loaded from user://settings.cfg at startup and saved on change.
## Loaded values are cleaned, so a hand-edited or broken file can't put the game
## in a bad state.

const PATH := "user://settings.cfg"
const DEFAULT_NAME := "Captain"
const MAX_NAME_LENGTH := 24
const DEFAULT_ADDRESS := "127.0.0.1"

var player_name := DEFAULT_NAME
var fullscreen := false
var vsync := true
var master_volume := 0.8        ## 0 to 1
var mouse_sensitivity := 1.0    ## 0.1 to 3
var last_address := DEFAULT_ADDRESS


func _ready() -> void:
	load_from(PATH)
	apply()


## Reads settings from path. A missing or unreadable file leaves the current values.
func load_from(path: String) -> void:
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return
	player_name = clean_name(str(file.get_value("player", "name", player_name)))
	last_address = _clean_address(str(file.get_value("player", "last_address", last_address)))
	fullscreen = _as_bool(file.get_value("display", "fullscreen", fullscreen), fullscreen)
	vsync = _as_bool(file.get_value("display", "vsync", vsync), vsync)
	master_volume = _as_number(file.get_value("audio", "master_volume", master_volume), master_volume, 0.0, 1.0)
	mouse_sensitivity = _as_number(file.get_value("controls", "mouse_sensitivity", mouse_sensitivity), mouse_sensitivity, 0.1, 3.0)


func save_to(path: String) -> Error:
	var file := ConfigFile.new()
	file.set_value("player", "name", player_name)
	file.set_value("player", "last_address", last_address)
	file.set_value("display", "fullscreen", fullscreen)
	file.set_value("display", "vsync", vsync)
	file.set_value("audio", "master_volume", master_volume)
	file.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	return file.save(path)


## Saves to user://settings.cfg, warning rather than failing if the disk refuses.
func save() -> void:
	var err := save_to(PATH)
	if err != OK:
		push_warning("Couldn't save settings: %s" % error_string(err))


## Pushes the display and audio settings to the engine.
func apply() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	AudioServer.set_bus_mute(0, master_volume <= 0.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.001)))


## Trims a name, turns control characters into spaces, caps it at MAX_NAME_LENGTH,
## and falls back to DEFAULT_NAME when nothing is left.
static func clean_name(raw: String) -> String:
	var printable := ""
	for character in raw:
		printable += character if character.unicode_at(0) >= 32 else " "
	var cleaned := printable.strip_edges().left(MAX_NAME_LENGTH).strip_edges()
	return cleaned if not cleaned.is_empty() else DEFAULT_NAME


static func _clean_address(raw: String) -> String:
	var address := raw.strip_edges().left(253)
	return address if not address.is_empty() else DEFAULT_ADDRESS


static func _as_bool(value: Variant, fallback: bool) -> bool:
	return value if value is bool else fallback


static func _as_number(value: Variant, fallback: float, low: float, high: float) -> float:
	if (value is float or value is int) and is_finite(float(value)):
		return clampf(float(value), low, high)
	return fallback
```

Add the autoload to `project.godot`, as a new section after `[application]`:
```ini
[autoload]

Settings="*res://src/core/settings.gd"
```

- [ ] **Step 4: Run the tests and see them pass**

Run: `./run_tests.sh`
Expected: `13 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add project.godot src/core/settings.gd tests/test_settings.gd
git commit -m "Add Settings autoload with cleaned load and save"
```

---

### Task 4: Session

**Files:**
- Create: `src/net/session.gd`, `tests/test_session.gd`
- Modify: `project.godot` (autoload)

**Interfaces:**
- Consumes: `SettingsScript.clean_name(raw: String) -> String`, through `preload("res://src/core/settings.gd")`.
- Produces the `Session` autoload (script `res://src/net/session.gd`, no `class_name`), with:
  - Signals: `started`, `ended(reason: String)`, `players_changed`.
  - `enum Mode { NONE, SOLO, HOST, CLIENT }`.
  - Constants: `PROTOCOL_VERSION := 1`, `DEFAULT_PORT := 24650`, `MAX_PLAYERS := 8`.
  - Variables: `mode: Mode`, `players: Dictionary` (peer id `int` → `{"name": String}`), `port: int`, `max_players: int`, `protocol_version: int`, `connect_timeout: float`, `log_enabled: bool`.
  - Methods: `is_server() -> bool`, `start_solo(player_name: String) -> void`, `host(player_name: String, host_port := DEFAULT_PORT) -> Error`, `join(player_name: String, address: String, join_port := DEFAULT_PORT) -> Error`, `leave() -> void`.
  - Static helpers: `parse_address(text: String) -> Dictionary` (`{"host": String, "port": int}`, or `{}` when unusable) and `lan_addresses(addresses: PackedStringArray) -> PackedStringArray`.

- [ ] **Step 1: Write the failing tests**

`tests/test_session.gd`:
```gdscript
extends TestCase
## Session roles, the join handshake, and the address helpers (spec §4.3, §7).

const SessionScript := preload("res://src/net/session.gd")

var _branches: Array[Node] = []


func after_each() -> void:
	for branch in _branches:
		(branch.get_node("Session") as SessionScript).leave()
		get_tree().set_multiplayer(null, branch.get_path())


## A Session under its own branch with its own MultiplayerAPI, so a host and a
## client can run in one process.
func make_session(branch_name: String) -> SessionScript:
	var branch := Node.new()
	branch.name = branch_name
	add_child(branch)
	get_tree().set_multiplayer(SceneMultiplayer.new(), branch.get_path())
	var session := SessionScript.new()
	session.name = "Session"
	session.log_enabled = false
	branch.add_child(session)
	_branches.append(branch)
	return session


func free_port() -> int:
	return 30000 + randi() % 20000


## Hosts on a fresh port, joins it, and waits until both sides have the full roster.
func host_and_join(host: SessionScript, client: SessionScript, guest_name := "Guest") -> bool:
	var port := free_port()
	if host.host("Host", port) != OK or client.join(guest_name, "127.0.0.1", port) != OK:
		return false
	return await wait_until(func() -> bool: return client.players.size() == 2 and host.players.size() == 2, 5.0)


func test_solo_is_a_server_with_just_you() -> void:
	var solo := make_session("Solo")
	var started := [false]
	solo.started.connect(func() -> void: started[0] = true)
	solo.start_solo("  Ann  ")
	assert_eq(solo.mode, SessionScript.Mode.SOLO)
	assert_true(solo.is_server())
	assert_true(started[0], "started fires")
	assert_eq(solo.players, {1: {"name": "Ann"}})


func test_client_joins_and_both_sides_share_the_roster() -> void:
	var host := make_session("Host")
	var client := make_session("Client")
	var started := [false]
	client.started.connect(func() -> void: started[0] = true)
	assert_true(await host_and_join(host, client), "roster reaches both sides")
	assert_true(started[0], "client's started fires once accepted")
	assert_eq(client.mode, SessionScript.Mode.CLIENT)
	assert_false(client.is_server())
	assert_true(host.is_server())
	var guest_id := client.multiplayer.get_unique_id()
	assert_eq(host.players.get(guest_id), {"name": "Guest"})
	assert_eq(client.players.get(1), {"name": "Host"})


func test_host_cleans_joiner_names() -> void:
	var host := make_session("Host")
	var client := make_session("Client")
	assert_true(await host_and_join(host, client, "  \n  "), "joined")
	assert_eq(host.players.get(client.multiplayer.get_unique_id()), {"name": "Captain"})


func test_host_refuses_a_different_version() -> void:
	var host := make_session("Host")
	var client := make_session("Client")
	var port := free_port()
	host.host("Host", port)
	client.protocol_version = SessionScript.PROTOCOL_VERSION + 1
	var reason := [""]
	client.ended.connect(func(why: String) -> void: reason[0] = why)
	client.join("Guest", "127.0.0.1", port)
	assert_true(await wait_until(func() -> bool: return reason[0] != "", 5.0), "client is told why")
	assert_true(reason[0].contains("version 1") and reason[0].contains("version 2"), reason[0])
	assert_eq(client.mode, SessionScript.Mode.NONE)
	assert_eq(host.players.size(), 1)


func test_host_refuses_when_full() -> void:
	var host := make_session("Host")
	var client := make_session("Client")
	host.max_players = 1
	var port := free_port()
	host.host("Host", port)
	var reason := [""]
	client.ended.connect(func(why: String) -> void: reason[0] = why)
	client.join("Guest", "127.0.0.1", port)
	assert_true(await wait_until(func() -> bool: return reason[0] != "", 5.0), "client is told why")
	assert_eq(reason[0], "The game is full.")


func test_host_drops_a_player_who_leaves() -> void:
	var host := make_session("Host")
	var client := make_session("Client")
	assert_true(await host_and_join(host, client), "joined")
	var reason := ["unset"]
	client.ended.connect(func(why: String) -> void: reason[0] = why)
	client.leave()
	assert_eq(reason[0], "", "leaving on purpose has no reason")
	assert_eq(client.mode, SessionScript.Mode.NONE)
	assert_eq(client.players, {})
	assert_true(await wait_until(func() -> bool: return host.players.size() == 1, 5.0), "host drops the guest")


func test_client_is_told_when_the_host_quits() -> void:
	var host := make_session("Host")
	var client := make_session("Client")
	assert_true(await host_and_join(host, client), "joined")
	var reason := [""]
	client.ended.connect(func(why: String) -> void: reason[0] = why)
	host.leave()
	assert_true(await wait_until(func() -> bool: return reason[0] != "", 5.0), "client notices")
	assert_eq(reason[0], "The host ended the game.")


func test_client_is_told_when_the_connection_drops() -> void:
	var host := make_session("Host")
	var client := make_session("Client")
	assert_true(await host_and_join(host, client), "joined")
	var reason := [""]
	client.ended.connect(func(why: String) -> void: reason[0] = why)
	host.multiplayer.multiplayer_peer.close()  # the host vanishes without a goodbye
	assert_true(await wait_until(func() -> bool: return reason[0] != "", 5.0), "client notices")
	assert_eq(reason[0], "Lost the connection to the host.")


func test_join_gives_up_when_nobody_answers() -> void:
	var client := make_session("Client")
	client.connect_timeout = 0.5
	var reason := [""]
	client.ended.connect(func(why: String) -> void: reason[0] = why)
	assert_eq(client.join("Guest", "127.0.0.1", free_port()), OK)
	assert_true(await wait_until(func() -> bool: return reason[0] != "", 3.0), "gives up")
	assert_eq(reason[0], "The host didn't answer.")
	assert_eq(client.mode, SessionScript.Mode.NONE)


func test_leaving_while_connecting_cancels_cleanly() -> void:
	var client := make_session("Client")
	client.connect_timeout = 0.3
	var reasons: Array[String] = []
	client.ended.connect(func(why: String) -> void: reasons.append(why))
	client.join("Guest", "127.0.0.1", free_port())
	client.leave()
	await wait_until(func() -> bool: return false, 0.6)  # outlast the timeout
	assert_eq(reasons, [""] as Array[String])


func test_hosting_on_a_busy_port_fails_cleanly() -> void:
	allowed_engine_errors = 2  # ENet reports the failed bind.
	var first := make_session("First")
	var second := make_session("Second")
	var port := free_port()
	assert_eq(first.host("Ann", port), OK)
	assert_eq(second.host("Bob", port), ERR_CANT_CREATE)
	assert_eq(second.mode, SessionScript.Mode.NONE)


func test_parse_address_reads_hosts_and_ports() -> void:
	assert_eq(SessionScript.parse_address("192.168.0.5"), {"host": "192.168.0.5", "port": 24650})
	assert_eq(SessionScript.parse_address("  example.com:3000 "), {"host": "example.com", "port": 3000})
	assert_eq(SessionScript.parse_address("[::1]:5000"), {"host": "::1", "port": 5000})
	assert_eq(SessionScript.parse_address("::1"), {"host": "::1", "port": 24650})


func test_parse_address_refuses_junk() -> void:
	for junk in ["", "   ", "10.0.0.1:", "10.0.0.1:99999", "10.0.0.1:0", "10.0.0.1:abc", "http://10.0.0.1", "my host", "[::1"]:
		assert_eq(SessionScript.parse_address(junk), {}, "'%s' is refused" % junk)


func test_lan_addresses() -> void:
	var all := PackedStringArray(["127.0.0.1", "192.168.0.102", "::1", "fe80::1", "10.1.2.3", "172.20.0.5", "172.40.0.1", "8.8.8.8"])
	assert_eq(SessionScript.lan_addresses(all), PackedStringArray(["192.168.0.102", "10.1.2.3", "172.20.0.5"]))
	assert_eq(SessionScript.lan_addresses(PackedStringArray()), PackedStringArray())
```

- [ ] **Step 2: Run it and see it fail**

Run: `./run_tests.sh session`
Expected: `FAIL tests/test_session.gd: could not load`.

- [ ] **Step 3: Implement Session**

`src/net/session.gd`:
```gdscript
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
			get_tree().create_timer(0.25).timeout.connect(old_peer.close)
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
```

Add it to the `[autoload]` section of `project.godot`, after `Settings`:
```ini
Session="*res://src/net/session.gd"
```

- [ ] **Step 4: Run the tests and see them pass**

Run: `./run_tests.sh`
Expected: `27 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add project.godot src/net/session.gd tests/test_session.gd
git commit -m "Add Session autoload: solo, host, join and handshake"
```

---

### Task 5: Launch options and scene flow

**Files:**
- Create: `src/core/launch_options.gd`, `tests/test_launch_options.gd`, `src/core/game.gd`
- Modify: `project.godot` (autoload)

**Interfaces:**
- Consumes: `Session.started`, `Session.ended(reason)`, `Session.host(...)`, `Session.join(...)`, `Session.parse_address(...)`, `Session.DEFAULT_PORT` and `Settings.player_name`.
- Produces:
  - `class_name LaunchOptions`, with `static parse(args: PackedStringArray) -> Dictionary`. The keys are `"host": true`, `"join": String`, `"name": String` and `"port": int`.
  - The `Game` autoload, with `menu_message: String`, `MENU_SCENE := "res://src/ui/main_menu.tscn"` and `WORLD_SCENE := "res://src/world/world.tscn"`.

- [ ] **Step 1: Write the failing test**

`tests/test_launch_options.gd`:
```gdscript
extends TestCase
## Command-line options after "--" (used for two-copy testing and servers).


func test_reads_host_join_name_and_port() -> void:
	assert_eq(LaunchOptions.parse(PackedStringArray(["--host", "--name=Ann", "--port=4000"])), {"host": true, "name": "Ann", "port": 4000})
	assert_eq(LaunchOptions.parse(PackedStringArray(["--join=10.0.0.2:4000"])), {"join": "10.0.0.2:4000"})


func test_ignores_unknown_and_malformed_options() -> void:
	assert_eq(LaunchOptions.parse(PackedStringArray(["--fly", "--port=abc", "--port=70000", "host"])), {})
```

- [ ] **Step 2: Run it and see it fail**

Run: `./run_tests.sh launch`
Expected: `FAIL tests/test_launch_options.gd: could not load` (`LaunchOptions` isn't declared).

- [ ] **Step 3: Implement LaunchOptions and Game**

`src/core/launch_options.gd`:
```gdscript
class_name LaunchOptions
## Reads the options passed after "--" on the command line:
##   --host            start hosting straight away
##   --join=ADDRESS    join ADDRESS (host, host:port or [ipv6]:port) straight away
##   --name=NAME       play as NAME instead of the saved name
##   --port=PORT       host on PORT instead of 24650
## Unknown or malformed options are ignored.


static func parse(args: PackedStringArray) -> Dictionary:
	var options := {}
	for arg in args:
		if arg == "--host":
			options["host"] = true
		elif arg.begins_with("--join="):
			options["join"] = arg.trim_prefix("--join=")
		elif arg.begins_with("--name="):
			options["name"] = arg.trim_prefix("--name=")
		elif arg.begins_with("--port="):
			var value := arg.trim_prefix("--port=")
			if value.is_valid_int() and value.to_int() >= 1 and value.to_int() <= 65535:
				options["port"] = value.to_int()
	return options
```

`src/core/game.gd`:
```gdscript
extends Node
## Moves between the main menu and the world as sessions start and end, carries
## the reason a session ended back to the menu, and applies launch options (see
## LaunchOptions), for example: godot --path . -- --host --name=Ann

const MENU_SCENE := "res://src/ui/main_menu.tscn"
const WORLD_SCENE := "res://src/world/world.tscn"

## Why the last session ended, for the menu to show once. "" when there's nothing to say.
var menu_message := ""


func _ready() -> void:
	Session.started.connect(_on_session_started)
	Session.ended.connect(_on_session_ended)
	_apply_launch_options.call_deferred(LaunchOptions.parse(OS.get_cmdline_user_args()))


func _apply_launch_options(options: Dictionary) -> void:
	var player_name: String = options.get("name", Settings.player_name)
	if options.has("host"):
		var host_port: int = options.get("port", Session.DEFAULT_PORT)
		var err := Session.host(player_name, host_port)
		if err != OK:
			push_error("Couldn't host on port %d: %s" % [host_port, error_string(err)])
	elif options.has("join"):
		var target := Session.parse_address(options["join"])
		if target.is_empty():
			push_error("Can't join '%s': that isn't an address." % options["join"])
		else:
			Session.join(player_name, target["host"], target["port"])


func _on_session_started() -> void:
	menu_message = ""
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_session_ended(reason: String) -> void:
	menu_message = reason
	get_tree().change_scene_to_file(MENU_SCENE)
```

Add it to the `[autoload]` section of `project.godot`, after `Session`:
```ini
Game="*res://src/core/game.gd"
```

- [ ] **Step 4: Run the tests and see them pass**

Run: `./run_tests.sh`
Expected: `29 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add project.godot src/core/launch_options.gd src/core/game.gd tests/test_launch_options.gd
git commit -m "Add launch options and scene flow"
```

---

### Task 6: Menus and world

**Files:**
- Create:
  - `src/ui/ui_theme.gd`
  - `src/world/sky_backdrop.gd`
  - `src/ui/settings_panel.gd`
  - `src/ui/main_menu.gd` and `src/ui/main_menu.tscn`
  - `src/world/world.gd` and `src/world/world.tscn`
  - `tests/test_scenes.gd`
- Modify: `project.godot` (main scene) and `tests/test_project.gd` (the compile test)

**Interfaces:**
- Consumes: the `Settings`, `Session` and `Game` autoloads as defined above.
- Produces:
  - `class_name UiTheme`, with:
    - Colours: `TEXT`, `TEXT_DIM`, `ACCENT`, `WARNING`, `PANEL`.
    - Static functions: `build() -> Theme`, `title(text: String) -> Label`, `caption(text: String) -> Label`, `button(text: String, on_pressed: Callable) -> Button`, `gap(height: float) -> Control`.
  - `class_name SkyBackdrop extends Node3D`.
  - `class_name SettingsPanel extends VBoxContainer`, with signal `closed` and method `focus_first() -> void`.

- [ ] **Step 1: Write the failing tests**

`tests/test_scenes.gd`:
```gdscript
extends TestCase
## The menu and world scenes build and run a few frames without engine errors.


func test_main_menu_builds() -> void:
	await _run_scene("res://src/ui/main_menu.tscn")


func test_world_builds() -> void:
	await _run_scene("res://src/world/world.tscn")


func _run_scene(path: String) -> void:
	var packed := load(path) as PackedScene
	assert_true(packed != null, "%s loads" % path)
	if packed == null:
		return
	var scene := packed.instantiate()
	add_child(scene)
	for i in 5:
		await get_tree().process_frame
	scene.queue_free()
	await get_tree().process_frame
```

Append to `tests/test_project.gd`:
```gdscript


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
```

- [ ] **Step 2: Run them and see them fail**

Run: `./run_tests.sh scenes`
Expected: FAIL on both tests: "res://src/ui/main_menu.tscn loads: expected true", and the engine logs that it can't open the file.

- [ ] **Step 3: Write the shared theme**

`src/ui/ui_theme.gd`:
```gdscript
class_name UiTheme
## The game's UI look: night-sky glass panels, brass accents, warm cream text.

const TEXT := Color("f4ecdb")
const TEXT_DIM := Color("c9c0ae")
const ACCENT := Color("e8a948")
const WARNING := Color("ff9b7a")
const PANEL := Color(0.04, 0.07, 0.13, 0.84)


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 20
	theme.set_color("font_color", "Label", TEXT)

	var clear := Color(0, 0, 0, 0)
	theme.set_stylebox("normal", "Button", _button_box(clear, clear))
	theme.set_stylebox("hover", "Button", _button_box(Color(1, 1, 1, 0.06), ACCENT))
	theme.set_stylebox("pressed", "Button", _button_box(Color(1, 1, 1, 0.1), ACCENT))
	theme.set_stylebox("hover_pressed", "Button", _button_box(Color(1, 1, 1, 0.1), ACCENT))
	theme.set_stylebox("focus", "Button", _button_box(clear, ACCENT))
	theme.set_stylebox("disabled", "Button", _button_box(clear, clear))
	theme.set_color("font_color", "Button", TEXT)
	for state in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(state, "Button", ACCENT)
	theme.set_color("font_disabled_color", "Button", Color(TEXT, 0.35))
	theme.set_font_size("font_size", "Button", 26)

	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.border_color = Color(1, 1, 1, 0.08)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(32)
	theme.set_stylebox("panel", "PanelContainer", panel)

	var field := StyleBoxFlat.new()
	field.bg_color = Color(1, 1, 1, 0.07)
	field.border_color = Color(1, 1, 1, 0.15)
	field.border_width_bottom = 2
	field.set_corner_radius_all(4)
	field.set_content_margin_all(10)
	theme.set_stylebox("normal", "LineEdit", field)
	var field_focus := field.duplicate() as StyleBoxFlat
	field_focus.border_color = ACCENT
	theme.set_stylebox("focus", "LineEdit", field_focus)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", Color(TEXT, 0.4))
	theme.set_color("caret_color", "LineEdit", ACCENT)
	return theme


## A big, widely spaced title.
static func title(text: String) -> Label:
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.spacing_glyph = 10
	font.variation_embolden = 0.8
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 84)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	label.add_theme_constant_override("shadow_offset_y", 3)
	return label


## Secondary text.
static func caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", TEXT_DIM)
	return label


## A left-aligned text button that calls on_pressed.
static func button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(on_pressed)
	return b


## Empty vertical space.
static func gap(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	return spacer


static func _button_box(fill: Color, bar: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = bar
	box.border_width_left = 3
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box
```

- [ ] **Step 4: Write the sky backdrop**

`src/world/sky_backdrop.gd`:
```gdscript
class_name SkyBackdrop
extends Node3D
## A slow drift through golden-hour sky above the storm. It sits behind the menus
## and the stage 1 world until the world stage builds the real sky.

const DRIFT := 0.02  ## Camera yaw in radians per second.

var _camera: Camera3D
var _yaw := 0.0


func _ready() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("27497a")
	sky_material.sky_horizon_color = Color("e7b98c")
	sky_material.ground_horizon_color = Color("7a6479")
	sky_material.ground_bottom_color = Color("1b1828")
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color("9d8ea6")
	env.fog_density = 0.00035
	env.fog_sky_affect = 0.15
	env.fog_height = 300.0
	env.fog_height_density = 0.004
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-10.0, 150.0, 0.0)
	sun.light_color = Color("ffd6a3")
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)

	for spec: Array in [[Vector3(-220, 760, -900), 70.0], [Vector3(340, 820, -1400), 110.0],
			[Vector3(-640, 690, -1800), 90.0], [Vector3(130, 745, -520), 34.0],
			[Vector3(900, 700, 300), 80.0], [Vector3(-1100, 780, 700), 120.0]]:
		add_child(_island(spec[0], spec[1]))

	_camera = Camera3D.new()
	_camera.position = Vector3(0, 800, 0)
	_camera.far = 6000.0
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)
	_camera.make_current()


func _process(delta: float) -> void:
	_yaw += DRIFT * delta
	_camera.rotation = Vector3(deg_to_rad(-4.0), _yaw, 0.0)


## A placeholder floating island: a grassy cap on a tapering rock.
static func _island(at: Vector3, radius: float) -> Node3D:
	var island := Node3D.new()
	island.position = at
	var rock_mesh := CylinderMesh.new()
	rock_mesh.top_radius = radius
	rock_mesh.bottom_radius = radius * 0.12
	rock_mesh.height = radius * 1.5
	rock_mesh.radial_segments = 9
	rock_mesh.rings = 1
	var rock := MeshInstance3D.new()
	rock.mesh = rock_mesh
	rock.position.y = -radius * 0.75
	rock.material_override = _flat(Color("5d4d47"))
	island.add_child(rock)
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = radius * 1.02
	cap_mesh.bottom_radius = radius
	cap_mesh.height = radius * 0.12
	cap_mesh.radial_segments = 9
	var cap := MeshInstance3D.new()
	cap.mesh = cap_mesh
	cap.material_override = _flat(Color("6e8d4c"))
	island.add_child(cap)
	return island


static func _flat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	return material
```

- [ ] **Step 5: Write the settings panel**

`src/ui/settings_panel.gd`:
```gdscript
class_name SettingsPanel
extends VBoxContainer
## Edits Settings. Changes apply straight away and are saved when the panel closes.

signal closed

var _name_field: LineEdit


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	add_child(UiTheme.caption("Your name"))
	_name_field = LineEdit.new()
	_name_field.max_length = Settings.MAX_NAME_LENGTH
	_name_field.text = Settings.player_name
	_name_field.text_changed.connect(func(text: String) -> void: Settings.player_name = Settings.clean_name(text))
	add_child(_name_field)
	add_child(_toggle("Fullscreen", Settings.fullscreen, func(on: bool) -> void: Settings.fullscreen = on))
	add_child(_toggle("VSync", Settings.vsync, func(on: bool) -> void: Settings.vsync = on))
	add_child(UiTheme.caption("Master volume"))
	add_child(_slider(0.0, 1.0, Settings.master_volume, func(value: float) -> void: Settings.master_volume = value))
	add_child(UiTheme.caption("Mouse sensitivity"))
	add_child(_slider(0.1, 3.0, Settings.mouse_sensitivity, func(value: float) -> void: Settings.mouse_sensitivity = value))
	add_child(UiTheme.gap(8))
	add_child(UiTheme.button("Back", _close))


func focus_first() -> void:
	_name_field.grab_focus()


func _close() -> void:
	Settings.save()
	closed.emit()


func _toggle(text: String, value: bool, set_value: Callable) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = text
	toggle.button_pressed = value
	toggle.toggled.connect(func(on: bool) -> void:
		set_value.call(on)
		Settings.apply()
	)
	return toggle


func _slider(low: float, high: float, value: float, set_value: Callable) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size.x = 320
	slider.value_changed.connect(func(new_value: float) -> void:
		set_value.call(new_value)
		Settings.apply()
	)
	return slider
```

- [ ] **Step 6: Write the main menu**

`src/ui/main_menu.gd`:
```gdscript
extends Node3D
## The main menu: play solo, host, join, settings and quit, over a drifting sky.

var _message: Label
var _menu: VBoxContainer
var _join_panel: VBoxContainer
var _address: LineEdit
var _join_button: Button
var _settings: SettingsPanel


func _ready() -> void:
	add_child(SkyBackdrop.new())
	var layer := CanvasLayer.new()
	add_child(layer)

	var rail := PanelContainer.new()
	rail.theme = UiTheme.build()
	rail.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	rail.custom_minimum_size.x = 560
	layer.add_child(rail)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	rail.add_child(column)
	column.add_child(UiTheme.gap(40))
	column.add_child(UiTheme.title("SKYWRIGHT"))
	column.add_child(UiTheme.caption("Build a ship. Physics decides if it flies."))
	column.add_child(UiTheme.gap(48))

	_message = UiTheme.caption("")
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.visible = false
	column.add_child(_message)

	_menu = VBoxContainer.new()
	column.add_child(_menu)
	_menu.add_child(UiTheme.button("Play solo", _play_solo))
	_menu.add_child(UiTheme.button("Host game", _host))
	_menu.add_child(UiTheme.button("Join game", _open_join))
	_menu.add_child(UiTheme.button("Settings", _open_settings))
	_menu.add_child(UiTheme.button("Quit", get_tree().quit))

	_join_panel = _build_join_panel()
	column.add_child(_join_panel)
	_settings = SettingsPanel.new()
	_settings.closed.connect(_show_menu)
	column.add_child(_settings)

	_show_menu()
	if not Game.menu_message.is_empty():
		_show_problem(Game.menu_message)
		Game.menu_message = ""


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _menu.visible:
		_back()
		get_viewport().set_input_as_handled()


func _build_join_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 12)
	panel.add_child(UiTheme.caption("Host's address"))
	_address = LineEdit.new()
	_address.placeholder_text = "192.168.0.10 or 192.168.0.10:24650"
	_address.text_submitted.connect(func(_text: String) -> void: _join())
	panel.add_child(_address)
	var row := HBoxContainer.new()
	_join_button = UiTheme.button("Join", _join)
	row.add_child(_join_button)
	row.add_child(UiTheme.button("Back", _back))
	panel.add_child(row)
	return panel


func _show_menu() -> void:
	_menu.visible = true
	_join_panel.visible = false
	_settings.visible = false
	(_menu.get_child(0) as Button).grab_focus()


func _open_join() -> void:
	_menu.visible = false
	_join_panel.visible = true
	_address.text = Settings.last_address
	_address.grab_focus()
	_address.caret_column = _address.text.length()


func _open_settings() -> void:
	_menu.visible = false
	_settings.visible = true
	_settings.focus_first()


## Back out of a panel. While connecting, this cancels the connection, which
## returns to a fresh menu through Game.
func _back() -> void:
	if Session.mode != Session.Mode.NONE:
		Session.leave()
	else:
		_message.visible = false
		_show_menu()


func _play_solo() -> void:
	Session.start_solo(Settings.player_name)


func _host() -> void:
	var err := Session.host(Settings.player_name)
	if err == ERR_CANT_CREATE:
		_show_problem("Port %d is already in use. Is another game running?" % Session.DEFAULT_PORT)
	elif err != OK:
		_show_problem("Couldn't start hosting (%s)." % error_string(err))


func _join() -> void:
	var typed := _address.text.strip_edges()
	var target := Session.parse_address(typed)
	if target.is_empty():
		_show_problem("Enter an address like 192.168.0.10 or 192.168.0.10:24650.")
		return
	Settings.last_address = typed
	Settings.save()
	var err := Session.join(Settings.player_name, target["host"], target["port"])
	if err != OK:
		_show_problem("Couldn't start connecting (%s)." % error_string(err))
		return
	_show_note("Connecting to %s…" % typed)
	_join_button.disabled = true


func _show_problem(text: String) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", UiTheme.WARNING)
	_message.visible = true


func _show_note(text: String) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_message.visible = true
```

`src/ui/main_menu.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/ui/main_menu.gd" id="1_menu"]

[node name="MainMenu" type="Node3D"]
script = ExtResource("1_menu")
```

- [ ] **Step 7: Write the world placeholder**

`src/world/world.gd`:
```gdscript
extends Node3D
## The game world. In stage 1 it's the sky backdrop and a HUD showing the session;
## stage 2 adds the ship.

var _status: Label
var _crew: Label
var _pause: PanelContainer
var _resume: Button


func _ready() -> void:
	add_child(SkyBackdrop.new())
	var layer := CanvasLayer.new()
	add_child(layer)
	var theme := UiTheme.build()

	var hud := PanelContainer.new()
	hud.theme = theme
	hud.position = Vector2(32, 32)
	layer.add_child(hud)
	var column := VBoxContainer.new()
	hud.add_child(column)
	_status = Label.new()
	column.add_child(_status)
	_crew = UiTheme.caption("")
	column.add_child(_crew)
	column.add_child(UiTheme.gap(8))
	column.add_child(UiTheme.caption("Flying arrives in stage 2. Press Esc for the menu."))

	var center := CenterContainer.new()
	center.theme = theme
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	_pause = PanelContainer.new()
	_pause.visible = false
	center.add_child(_pause)
	var pause_column := VBoxContainer.new()
	_pause.add_child(pause_column)
	_resume = UiTheme.button("Resume", _toggle_pause)
	pause_column.add_child(_resume)
	pause_column.add_child(UiTheme.button("Leave game", Session.leave))

	Session.players_changed.connect(_refresh)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _toggle_pause() -> void:
	_pause.visible = not _pause.visible
	if _pause.visible:
		_resume.grab_focus()


func _refresh() -> void:
	_status.text = _status_text()
	var names: PackedStringArray = []
	for id: int in Session.players:
		names.append(Session.players[id]["name"])
	_crew.text = "Crew (%d): %s" % [names.size(), ", ".join(names)]


func _status_text() -> String:
	if Session.mode == Session.Mode.SOLO:
		return "Solo game"
	if Session.mode == Session.Mode.HOST:
		var lan := Session.lan_addresses(IP.get_local_addresses())
		if lan.is_empty():
			return "Hosting on port %d" % Session.port
		return "Hosting. Friends on your network join at %s:%d" % [lan[0], Session.port]
	if Session.mode == Session.Mode.CLIENT:
		return "Connected to the host"
	return ""
```

`src/world/world.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/world/world.gd" id="1_world"]

[node name="World" type="Node3D"]
script = ExtResource("1_world")
```

Set the main scene in `project.godot`, in `[application]` after `config/version`:
```ini
run/main_scene="res://src/ui/main_menu.tscn"
```

- [ ] **Step 8: Run all tests and see them pass**

Run: `./run_tests.sh`
Expected: `32 passed, 0 failed`.

- [ ] **Step 9: Commit**

```bash
git add project.godot src/ tests/
git commit -m "Add main menu, settings panel, and world placeholder"
```

---

### Task 7: README and end-to-end checks

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Write the README**

`README.md`:
````markdown
# Skywright

An airship game: design ships block by block, and real physics decides whether they fly. Crew them with friends, explore a generated sky of floating islands above an endless storm, and push toward the Eye.

Built with Godot 4.7.2. The design is in [`docs/superpowers/specs/2026-09-29-skywright-design.md`](docs/superpowers/specs/2026-09-29-skywright-design.md), and the current stage's plan is in `docs/superpowers/plans/`.

## Status

**Stage 1 of 10 (Foundations).** You can:
- open the main menu;
- play solo;
- host a game or join one on your network;
- change settings.

Flying arrives in stage 2.

## Run it

Install Godot 4.7.2 (the standard build, not .NET), put it on your PATH as `godot`, then:

```bash
godot --path .            # play
godot --path . --editor   # open in the editor
```

## Play with friends

1. One player chooses **Host game**. The HUD shows the address friends should use, for example `192.168.0.102:24650`.
2. Everyone else chooses **Join game** and types that address.

Games use UDP port 24650. Over the internet, the host must forward that port on their router.

To test with two copies on one machine:

```bash
godot --path . -- --host --name=Ann
godot --path . -- --join=127.0.0.1 --name=Bob
```

Launch options (after `--`): `--host`, `--join=ADDRESS`, `--name=NAME`, `--port=PORT`.

## Test

```bash
./run_tests.sh           # every test, headless
./run_tests.sh session   # only test files whose name contains "session"
```

A test fails when an assert fails, or when the engine logs an error the test didn't expect.

## Layout

```
src/core/     Settings and Game autoloads, launch options
src/net/      Session autoload: solo, host, join, handshake
src/ui/       menus and the shared UI theme
src/world/    the world scene and the sky backdrop
tests/        test runner and tests
docs/         design spec and implementation plans
```

## Graphics on hybrid laptops

Godot picks a GPU at startup and prints it, for example `Using Device #0: AMD ... Radeon 680M`. To choose a different one, run it with `--verbose` to list the devices, then pass `--gpu-index N`.
````

- [ ] **Step 2: Run the whole suite**

Run: `./run_tests.sh; echo "exit=$?"`
Expected: `32 passed, 0 failed`, `exit=0`.

- [ ] **Step 3: Check the game runs on the GPU and looks right**

Run (this opens a window for about 3 seconds):
```bash
godot --path . --quit-after 180 --write-movie "${TMPDIR:-/tmp}/menu.png" 2>&1 | grep -E "Vulkan|Using Device|ERROR"
```
Expected: one line naming the Vulkan device and no `ERROR` lines. Open the last `menu*.png`: the SKYWRIGHT panel sits on the left over a golden-hour sky with floating islands. Record the device in the README's graphics section if it isn't the expected GPU.

- [ ] **Step 4: Check two copies on one machine (host, join, leave)**

```bash
godot --headless --path . --max-fps 60 -- --host --name=Ann --port=24690 > "${TMPDIR:-/tmp}/host.log" 2>&1 &
HOST=$!
sleep 2
godot --headless --path . --max-fps 60 --quit-after 300 -- --join=127.0.0.1:24690 --name=Bob > "${TMPDIR:-/tmp}/client.log" 2>&1
sleep 1
kill $HOST
grep "\[session\]" "${TMPDIR:-/tmp}/host.log" "${TMPDIR:-/tmp}/client.log"
```
Expected:
- The host log shows `hosting on port 24690`, then `peer … joined as Bob`, then `peer … left` once the client quits.
- The client log shows `connecting to 127.0.0.1:24690`, then `joined; crew: Ann, Bob`.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "Add README for stage 1"
```
