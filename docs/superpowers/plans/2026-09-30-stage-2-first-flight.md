# Stage 2: First Flight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** You walk the deck of a starter airship while it rolls in the wind, take the helm, and fly between placeholder islands over the Roil, through day and night. Flight tests prove that physics decides how the ship flies: a balanced ship holds level, a lopsided one lists toward its heavy side, an overloaded one sinks, and top speed is within 10% of the estimate.

**Architecture:**
- A ship is a `ShipGrid` (cells → blocks) turned into one Jolt `RigidBody3D` (`Ship`). The ship's mass, centre of mass and inertia come from its blocks.
- Collision is the solid cells merged into boxes.
- Each physics tick, `Ship._integrate_forces` applies:
  - balloon lift that thins with altitude;
  - propeller thrust;
  - drag, plus a keel push, on 4 m zones;
  - rudder side force.
- Every number that shapes the flying lives in `Tuning`.
- Crew walk in the ship's interior: a `SubViewport` with its own physics world, holding a still copy of the ship's boxes in ship space. Gravity there is the ship's "down", so a rolling deck feels like a slope (spec §4.5).
- The `Helm` turns a pilot's keys into throttle, rudder and trim, and runs the autopilot.
- `PlayerController` reads the keyboard and mouse and places the camera: first person, or a chase view at the helm.
- The world adds a day–night sky, the Roil below 200 m, placeholder islands and a HUD.

**Tech Stack:** Godot 4.7.2 (standard build, `~/.local/bin/godot`), statically typed GDScript, Jolt Physics, and the existing headless test runner.

**Spec:** `docs/superpowers/specs/2026-09-29-skywright-design.md` (stage 2 in §5; ships in §4.4; crew in §4.5).

## Global Constraints

- Godot 4.7.2 standard build, and GDScript with static types everywhere. No addons or other dependencies.
- Jolt Physics at 60 ticks per second with physics interpolation, and the Forward+ renderer.
- One unit is one metre. Gravity is 9.81 m/s².
- Ship space: `-Z` is the bow, `+X` starboard and `+Y` up. Cell `(x, y, z)` is the 1 m cube centred on `(x, y, z)`.
- Block stats come from spec §4.4. Every flight number lives in `src/ship/tuning.gd` (spec §8: "one tuning file").
- The Roil's top is at 200 m. Air density is `exp(-(h - 200) / 2500)` above it and 1 below.
- Lift is `900 N × density × trim` per balloon, with trim from 0.8 to 1.1. A lift stone gives 6,000 N.
- Thrust is `throttle × power share × 2,500 N` per propeller.
- Zone drag is `-½ × 1.2 × density × Cd × area × |v| × v` per ship axis. It uses each zone's velocity through the air.
- The physics guard restores a ship that is non-finite, faster than 400 m/s or spinning faster than 20 rad/s (spec §4.4).
- Folders are created only when a task needs them: `src/ship/` and `src/crew/` arrive in this stage.
- Commit messages never include a `Co-Authored-By` line (user rule).

## Review Focus

1. **Ramming an island at full throttle:** the ship stops without the physics guard firing, and the crew keep their feet. Test: `test_ramming_an_island_is_survivable` (Task 9).
2. **Opening the pause menu at the helm with keys held:** steering stops, and E, V and H do nothing until you resume. Test: `test_controls_stop_while_a_menu_is_open` (Task 7).
3. **Falling overboard** (walking off the bow, dropping off the helm deck): you are put back aboard where you started, and the HUD says so. Test: `test_falling_overboard_brings_you_back_aboard` (Task 5).
4. **A physics blow-up** (a huge or non-finite velocity): the ship goes back to its last good place, stopped, with a warning. Test: `test_a_physics_blow_up_puts_the_ship_back` (Task 4).
5. **Leaving the helm with keys held, or with the autopilot on:** the inputs reset and the rudder centres. The autopilot keeps flying. Tests: `test_throttle_and_trim_stay_set_and_the_rudder_centres` and `test_the_autopilot_keeps_flying_when_the_pilot_leaves` (Task 6).

---

## What a prototype settled before this plan

The risky parts were tried in a scratch copy first, so the code below has already run. These were the findings:

| Question | Answer |
|---|---|
| Can crew walk on a deck that rolls ±15° and pitches ±8°? | Yes, in a `SubViewport` world with gravity rotated into ship space. After 20 s they had drifted under 1 mm, and they were on the floor every tick. Walking "uphill" against tilted gravity skips Godot's own floor snap, so `CrewMember` calls `apply_floor_snap()` itself, except on ladders and jumps. |
| Does Jolt honour a custom centre of mass and inertia? | Yes. `apply_force`'s position is an offset from the body origin in global axes, and `linear_velocity` is the centre of mass's velocity. Setting the damp modes to `REPLACE` with 0 removes Godot's default damping. That default would have been 13 kN of fake drag at cruise. |
| Can flight tests simulate minutes quickly? | Yes. `--fixed-fps 60` makes each frame exactly one physics tick with no real-time wait. The runner caps frames at 60/s so the network tests' timers still match real time, and `TestCase.simulate()` lifts the cap while it runs. All ~9 minutes of simulated flying take about 10 s. |
| Is the starter ship level? | Yes, after a search over envelope span and ballast. An iron keel under the middle puts her centre of mass 0.004 m from her lift in z, which is 0.04° of pitch. She is 8,886 kg with 127 balloon cells and floats at 877 m at trim 1. Trim 0.8–1.1 reaches about 320–1,116 m, all above the Roil. |
| Does the physics match the theory? | Yes. Lopsided list: 2.58° simulated against 2.59° predicted. Top speed: 20.27 m/s simulated against a 20.23 m/s estimate. Overloaded: sinks through 200 m within 40 s. |
| Why the keel term? | With drag alone the ship couldn't turn. Turning needs a sideways force of mass × speed × turn rate, about 18 kN at 6°/s. Quadratic sideslip drag can't give that, so the ship skidded at about 2°/s and lost half its speed. `ShipForces.keel` models the hull resisting sideslip at speed, as a keel does. With `HULL_LIFT` 8 and `RUDDER_FORCE` 8, she turns at about 6°/s and keeps about 15 of her 22 m/s. It needs forward speed, so a hovering ship still drifts with the wind. |
| Does she roll in the wind? | Gently. At cruise through gusts she rolls ±2° and holds heading within 1°. Hovering, she drifts with the wind and rolls under 1°. |
| Autopilot gains? | It holds heading within 1° and altitude within 3 m through gusts. It turns 90° in about 15 s. |
| Engine warning "Jolt Physics job system exceeded the maximum number of jobs" | This appears only when physics runs faster than real time: under the test runner or the movie writer. It never appeared in 40 s of real-time flying. It is a warning, so the runner doesn't count it. |

## Where this stage departs from the spec

The spec is updated to match in Task 10.

| Spec | This stage | Why |
|---|---|---|
| §4.4 forces: lift, thrust, drag, control surfaces | Adds a **keel push** per zone, `-½ × 1.2 × density × HULL_LIFT × side area × \|v_forward\| × v_side`, and **spin damping** (`ANGULAR_DAMPING` 0.5/s). | Without the keel, ships skid instead of turning (see above). The damping settles rolls in about 10 s instead of minutes. |
| §4.4 control surfaces: `k × ρ × \|v_air\|² × deflection` | `k × ρ × v_forward × \|v_forward\| × deflection` | The same when going forward, but a rudder works backwards when going astern, as a real one does. |
| §4.4 thrust "along its axis" | Propellers push toward the bow. Block rotation is stored but not yet used. | Nothing turns blocks until the shipyard (stage 4). |
| §4.4 "engine power share" | One engine drives up to 2 propellers at full power (`PROPELLERS_PER_ENGINE`). | The spec left it open. The starter ship has one engine and two propellers, giving the 5 kN of the spec's sanity check. |
| §3.3, §4.4 fuel | Not modelled: engines and trim above 1.0 burn nothing. | Fuel matters when there's an economy (stage 7). |
| §4.5 leaving and boarding | Crew who fall 30 m below the ship are put back aboard where they started, with a message. | Going ashore and gliding back is stage 5's job. |
| §4.7 volumetric fog below the Roil | Depth fog from 1.5 km, and a dark animated surface with lightning underneath. | It's cheap on the Radeon 680M, and it reads as a storm sea. Volumetric fog can come with the world stage. |
| §4.6 one shared world | In this stage every copy of the game flies its own ship. | Syncing ships is stage 3. |
| §4.2 one mesh per ship per material, in 16³ sections | One mesh for the whole ship, with vertex colours. | Sections matter when hits rebuild the mesh (stage 6). |

---

## File structure

| File | Responsibility |
|---|---|
| `run_tests.sh` | Adds `--fixed-fps 60` |
| `tests/run_tests.gd` | Caps frames at 60/s. Counts errors raised in a test's `_ready` and `_exit_tree`. |
| `tests/test_case.gd` | `simulate(seconds, before_tick)` |
| `tests/test_runner.gd`, `tests/test_runner_fixture.gd` | The runner counts errors while a test is added and removed |
| `src/ship/tuning.gd` | `Tuning`: the block catalogue and every flight and helm number |
| `src/ship/ship_grid.gd` | `ShipGrid`: blocks, mass properties, merged collision boxes, drag zones |
| `src/ship/starter_ship.gd` | `StarterShip.build()`: the first ship |
| `src/ship/ship_forces.gd` | `ShipForces`: air density, zone drag, the keel, the top-speed estimate |
| `src/world/wind.gd` | `Wind.at(position, time)`: prevailing wind plus gusts |
| `src/ship/ship_mesh.gd` | `ShipMesh.build(grid)`: one low-poly mesh coloured by block type |
| `src/ship/ship.gd` | `Ship`: the rigid body, its forces, the physics guard, and its interior and helm |
| `src/crew/ship_interior.gd` | `ShipInterior`: the crew's physics world in ship space |
| `src/crew/crew_member.gd` | `CrewMember`: walking, jumping, ladders and overboard, in ship space |
| `src/crew/helm.gd` | `Helm`: the pilot, throttle, rudder, trim and autopilot |
| `src/crew/player_controller.gd` | `PlayerController`: keys, mouse, stations, first-person and chase cameras |
| `src/world/world_sky.gd` | `WorldSky`: sun, moon, sky colours through the day, haze |
| `src/world/roil.gd` | `Roil`: the storm surface and lightning |
| `src/world/island.gd` | `Island.create()`: a solid placeholder island (moved out of `SkyBackdrop`) |
| `src/ui/hud.gd` | `Hud`: session, crosshair, E prompt, helm instruments, messages |
| `src/world/world.gd` | The world: sky, Roil, islands, ship, player, HUD, pause menu |
| `src/core/launch_options.gd`, `src/core/game.gd` | `--solo` |
| `project.godot` | Gravity 9.81, `autopilot` action on H |
| `README.md` | Stage 2 status, controls and layout |

---

### Task 1: Test tooling and the stage 1 follow-ups

Build-log item: "Stage 1 review follow-ups: gravity 9.81 m/s², test runner error counting".

**Files:**
- Modify: `run_tests.sh`, `tests/run_tests.gd`, `tests/test_case.gd`, `tests/test_test_case.gd`, `project.godot`, `tests/test_project.gd`
- Create: `tests/test_runner.gd`, `tests/test_runner_fixture.gd`

**Interfaces:**
- Produces: `TestCase.simulate(seconds: float, before_tick := Callable()) -> void`, a coroutine you `await`. It runs `roundi(seconds × 60)` physics ticks, calling `before_tick.call(tick: int)` before each one.

- [ ] **Step 1: Write the failing tests**

`tests/test_runner_fixture.gd`:
```gdscript
extends TestCase
## A test that passes, unless SKYWRIGHT_FIXTURE asks it to log an error from _ready
## or _exit_tree. test_runner.gd uses it to check the runner counts those errors.


func _ready() -> void:
	if OS.get_environment("SKYWRIGHT_FIXTURE") == "ready":
		push_error("an error in _ready")


func _exit_tree() -> void:
	if OS.get_environment("SKYWRIGHT_FIXTURE") == "exit":
		push_error("an error in _exit_tree")


func test_nothing() -> void:
	pass
```

`tests/test_runner.gd`:
```gdscript
extends TestCase
## The runner itself: errors logged while a test is added or removed count against it.


func test_an_error_in_ready_fails_the_test() -> void:
	assert_eq(_run_fixture("ready"), 1, "the runner exits 1")


func test_an_error_in_exit_tree_fails_the_test() -> void:
	assert_eq(_run_fixture("exit"), 1, "the runner exits 1")


func test_the_fixture_passes_on_its_own() -> void:
	assert_eq(_run_fixture(""), 0, "the runner exits 0")


## Runs test_runner_fixture.gd in a fresh headless Godot and returns its exit code.
func _run_fixture(mode: String) -> int:
	OS.set_environment("SKYWRIGHT_FIXTURE", mode)
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/run_tests.gd", "--", "runner_fixture"], output, true)
	OS.unset_environment("SKYWRIGHT_FIXTURE")
	return code
```

Append to `tests/test_test_case.gd`:
```gdscript


func test_simulate_runs_that_many_physics_ticks() -> void:
	var start := Engine.get_physics_frames()
	await simulate(0.5)
	assert_eq(Engine.get_physics_frames() - start, 30)
```

In `tests/test_project.gd`, `test_physics_is_jolt_at_60_ticks_with_interpolation` gains a line:
```gdscript
	assert_eq(ProjectSettings.get_setting("physics/3d/physics_engine"), "Jolt Physics")
	assert_eq(ProjectSettings.get_setting("physics/3d/default_gravity"), 9.81)
```

- [ ] **Step 2: Run them to see them fail**

Run: `./run_tests.sh runner; ./run_tests.sh test_case; ./run_tests.sh project`
Expected:
- `test_an_error_in_ready_fails_the_test` and `test_an_error_in_exit_tree_fails_the_test` fail with "expected 1, got 0".
- `test_test_case.gd` "could not load" (no `simulate`).
- The project test fails with "expected 9.81, got 9.8".

- [ ] **Step 3: Make the runner count errors around a test, cap frames, and fix gravity**

`run_tests.sh`:
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
exec timeout 600 "$godot" --headless --fixed-fps 60 --script res://tests/run_tests.gd -- "$@"
```

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
	Engine.max_fps = 60
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var filter := args[0] if not args.is_empty() else ""
	var passed := 0
	var failed := 0
	for path in _find_tests(TEST_ROOT):
		if not filter.is_empty() and not path.get_file().contains(filter):
			continue  # note: contains("") is false in Godot, hence the is_empty check
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
	var errors_before := _errors.count  # before add_child, so errors in _ready count
	root.add_child(test)
	await test.call(test_name)
	await test.after_each()
	var problems := test.failures.duplicate()
	var allowed := test.allowed_engine_errors
	test.queue_free()
	await process_frame  # _exit_tree runs, and its errors count too
	var new_errors := _errors.count - errors_before
	if new_errors > allowed:
		problems.append("engine logged %d error(s), last: %s" % [new_errors, _errors.last])
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

In `tests/test_case.gd`, add before `_fail`:
```gdscript
## Runs the physics for seconds of simulated time, calling before_tick(tick) ahead
## of each tick when given. Under ./run_tests.sh (--fixed-fps 60) this goes as fast
## as the machine can manage. Use it as: await simulate(...)
func simulate(seconds: float, before_tick := Callable()) -> void:
	var cap := Engine.max_fps
	Engine.max_fps = 0
	for tick in roundi(seconds * Engine.physics_ticks_per_second):
		if before_tick.is_valid():
			before_tick.call(tick)
		await get_tree().physics_frame
	Engine.max_fps = cap
```

In `project.godot`, under `[physics]`:
```ini
3d/physics_engine="Jolt Physics"
3d/default_gravity=9.81
```

- [ ] **Step 4: Run the whole suite**

Run: `./run_tests.sh; echo "exit=$?"`
Expected: `43 passed, 0 failed`, `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add run_tests.sh tests/run_tests.gd tests/test_case.gd tests/test_test_case.gd tests/test_runner.gd tests/test_runner_fixture.gd tests/*.uid project.godot tests/test_project.gd
git commit -m "Count errors around each test, simulate fast, and use 9.81 m/s² gravity"
```

---

### Task 2: Blocks, the ship grid and the starter ship

Build-log items: "Block data: grid positions, part types, weight, hit points", and the mass-and-balance half of "Ship body: mass, centre of mass and inertia worked out from its blocks".

**Files:**
- Create: `src/ship/tuning.gd`, `src/ship/ship_grid.gd`, `src/ship/starter_ship.gd`, `tests/test_ship_grid.gd`

**Interfaces:**
- Produces:
  - `Tuning.BLOCKS: Dictionary`: type → `{"mass": float, "hp": int}`, plus the flight constants listed in the file.
  - `ShipGrid` (RefCounted):
    - `blocks: Dictionary` (Vector3i → `{"type", "rotation", "hp"}`)
    - `set_block(cell: Vector3i, type: String, rotation := 0)`
    - `type_at(cell) -> String` ("" when empty)
    - `cells_of(type) -> Array[Vector3i]`
    - `mass_properties() -> {"mass": float, "center": Vector3, "inertia": Vector3}`
    - `merged_boxes() -> Array[AABB]` (solid cells, that is everything but ladders)
    - `drag_zones() -> Array[Dictionary]` (`{"center": Vector3, "area": Vector3}`)
  - `StarterShip.build() -> ShipGrid`

- [ ] **Step 1: Write the failing tests**

`tests/test_ship_grid.gd`:
```gdscript
extends TestCase
## Ship blocks and the maths built on them: mass properties, collision boxes and
## drag zones (spec §4.4).


func grid_of(cells: Dictionary) -> ShipGrid:
	var grid := ShipGrid.new()
	for cell: Vector3i in cells:
		grid.set_block(cell, cells[cell])
	return grid


func test_blocks_start_at_full_hit_points_and_can_be_replaced() -> void:
	var grid := ShipGrid.new()
	grid.set_block(Vector3i(1, 2, 3), "frame")
	assert_eq(grid.blocks[Vector3i(1, 2, 3)], {"type": "frame", "rotation": 0, "hp": 100})
	grid.set_block(Vector3i(1, 2, 3), "iron", 5)
	assert_eq(grid.blocks[Vector3i(1, 2, 3)], {"type": "iron", "rotation": 5, "hp": 300})
	assert_eq(grid.type_at(Vector3i(1, 2, 3)), "iron")
	assert_eq(grid.type_at(Vector3i(0, 0, 0)), "")
	assert_eq(grid.cells_of("iron"), [Vector3i(1, 2, 3)] as Array[Vector3i])


func test_one_block_mass_properties() -> void:
	var props := grid_of({Vector3i(2, 0, 0): "frame"}).mass_properties()
	assert_eq(props["mass"], 60.0)
	assert_eq(props["center"], Vector3(2, 0, 0))
	assert_eq(props["inertia"], Vector3(10, 10, 10), "a 60 kg cube: m/6 about each axis")


func test_centre_of_mass_leans_to_the_heavy_block() -> void:
	var props := grid_of({Vector3i(0, 0, 0): "iron", Vector3i(4, 0, 0): "frame"}).mass_properties()
	assert_eq(props["mass"], 240.0)
	assert_eq(props["center"], Vector3(1, 0, 0), "(0 × 180 + 4 × 60) / 240")


func test_inertia_adds_the_parallel_axis_term() -> void:
	var props := grid_of({Vector3i(-1, 0, 0): "frame", Vector3i(1, 0, 0): "frame"}).mass_properties()
	# Each cube: 10 about every axis, plus 60 × 1² about y and z.
	assert_eq(props["inertia"], Vector3(20, 140, 140))


func test_a_solid_block_merges_into_one_box() -> void:
	var cells := {}
	for x in 3:
		for y in 2:
			for z in 4:
				cells[Vector3i(x, y, z)] = "deck"
	assert_eq(grid_of(cells).merged_boxes(), [AABB(Vector3(-0.5, -0.5, -0.5), Vector3(3, 2, 4))] as Array[AABB])


func test_merged_boxes_cover_every_solid_cell_once_and_skip_ladders() -> void:
	var grid := StarterShip.build()
	var boxes := grid.merged_boxes()
	var solid := 0
	for cell: Vector3i in grid.blocks:
		if grid.type_at(cell) != "ladder":
			solid += 1
			var inside := 0
			for box in boxes:
				if box.has_point(Vector3(cell)):
					inside += 1
			assert_eq(inside, 1, "%s is in exactly one box" % cell)
	var volume := 0.0
	for box in boxes:
		volume += box.get_volume()
	assert_eq(volume, float(solid))
	for cell in grid.cells_of("ladder"):
		for box in boxes:
			assert_false(box.has_point(Vector3(cell)), "ladder %s stays open to walk into" % cell)
	assert_true(boxes.size() < solid / 5, "%d boxes for %d cells" % [boxes.size(), solid])


func test_drag_zone_areas_are_outlines_along_each_axis() -> void:
	var zones := grid_of({Vector3i(0, 0, 0): "deck", Vector3i(1, 0, 0): "deck"}).drag_zones()
	assert_eq(zones.size(), 1)
	assert_eq(zones[0]["center"], Vector3(0.5, 0, 0))
	assert_eq(zones[0]["area"], Vector3(1, 2, 2), "a 2 × 1 × 1 bar seen along x, y and z")


func test_drag_zones_split_every_four_metres() -> void:
	var cells := {}
	for x in range(-4, 4):
		cells[Vector3i(x, 0, 0)] = "deck"
	var zones := grid_of(cells).drag_zones()
	assert_eq(zones.size(), 2)
	var total := Vector3.ZERO
	for zone in zones:
		total += zone["area"]
	assert_eq(total, Vector3(1, 8, 8), "each zone's outline, summed")


func test_the_starter_ship_balances_under_its_envelope() -> void:
	var grid := StarterShip.build()
	var props := grid.mass_properties()
	var com: Vector3 = props["center"]
	var balloons := grid.cells_of("balloon")
	var lift := Vector3.ZERO
	for cell in balloons:
		lift += Vector3(cell)
	lift /= balloons.size()
	assert_eq(com.x, 0.0, "port and starboard weigh the same")
	assert_near(com.z, lift.z, 0.01, "her weight hangs under her lift, so she flies level")
	assert_true(lift.y - com.y > 5.0, "the lift is well above the weight, so she rights herself")
	var weight: float = props["mass"] * 9.81
	var floats_at := Tuning.ROIL_ALTITUDE + Tuning.AIR_SCALE_HEIGHT * log(balloons.size() * Tuning.BALLOON_LIFT / weight)
	assert_near(floats_at, 877.0, 5.0, "at trim 1 she floats at about 877 m")
```

- [ ] **Step 2: Run them to see them fail**

Run: `./run_tests.sh ship_grid`
Expected: FAIL, `test_ship_grid.gd: could not load` (`ShipGrid` doesn't exist).

- [ ] **Step 3: Write the tuning file, the grid and the starter ship**

`src/ship/tuning.gd`. The helm's numbers are added in Task 6:
```gdscript
class_name Tuning
## Every number that decides how ships fly and handle, in one place (spec §8).
## Block stats start from spec §4.4.

## Block types, with mass in kg and hit points.
const BLOCKS := {
	"frame": {"mass": 60.0, "hp": 100},
	"deck": {"mass": 40.0, "hp": 80},
	"iron": {"mass": 180.0, "hp": 300},
	"alloy": {"mass": 110.0, "hp": 260},
	"balloon": {"mass": 8.0, "hp": 30},
	"lift_stone": {"mass": 250.0, "hp": 400},
	"engine": {"mass": 300.0, "hp": 200},
	"propeller": {"mass": 50.0, "hp": 60},
	"rudder": {"mass": 30.0, "hp": 60},
	"sail": {"mass": 20.0, "hp": 40},
	"fuel_tank": {"mass": 80.0, "hp": 120},
	"ballast_tank": {"mass": 60.0, "hp": 100},
	"helm": {"mass": 80.0, "hp": 150},
	"cannon": {"mass": 220.0, "hp": 200},
	"cargo_bay": {"mass": 50.0, "hp": 100},
	"bunk": {"mass": 40.0, "hp": 60},
	"ladder": {"mass": 15.0, "hp": 40},
}

const ROIL_ALTITUDE := 200.0      ## m. The air is densest here and below.
const AIR_SCALE_HEIGHT := 2500.0  ## m. Air thins by a factor of e over this height.
const AIR_DENSITY := 1.2          ## kg/m³ at the Roil.
const BALLOON_LIFT := 900.0       ## N per balloon cell in the densest air, at trim 1.
const LIFT_STONE_LIFT := 6000.0   ## N per lift stone, at any altitude.
const PROPELLER_THRUST := 2500.0  ## N per propeller at full throttle and full power.
const PROPELLERS_PER_ENGINE := 2  ## Propellers one engine drives at full power.
const DRAG_COEFFICIENT := 0.45    ## Cd of every exposed face.
const HULL_LIFT := 8.0            ## How hard the hull resists slipping sideways at speed, as a keel does. Without it ships skid instead of turning.
const RUDDER_FORCE := 8.0         ## Side force per rudder, in N per (m/s)² of airspeed, at full deflection and density.
const ANGULAR_DAMPING := 0.5      ## 1/s. Air damping of the ship's spin, on top of face drag.
const TRIM_MIN := 0.8             ## Balloon trim limits: lift is 900 N × density × trim per balloon.
const TRIM_MAX := 1.1
```

`src/ship/ship_grid.gd`:
```gdscript
class_name ShipGrid
extends RefCounted
## A ship's blocks on a 1 m grid (spec §4.4). Cell (x, y, z) is the 1 m cube centred
## on (x, y, z) in ship space, where -Z is the bow, +X starboard and +Y up.

const ZONE_SIZE := 4  ## Drag zones are ZONE_SIZE cells on a side.

## Vector3i -> {"type": String, "rotation": int (0–23), "hp": int}
var blocks: Dictionary = {}


## Places a block, replacing any already there, at full hit points.
func set_block(cell: Vector3i, type: String, rotation := 0) -> void:
	blocks[cell] = {"type": type, "rotation": rotation, "hp": Tuning.BLOCKS[type]["hp"]}


## The block type at cell, or "" when it's empty.
func type_at(cell: Vector3i) -> String:
	return blocks[cell]["type"] if blocks.has(cell) else ""


func cells_of(type: String) -> Array[Vector3i]:
	var found: Array[Vector3i] = []
	for cell: Vector3i in blocks:
		if blocks[cell]["type"] == type:
			found.append(cell)
	return found


## Total mass, the mass-weighted centre, and the diagonal of the inertia tensor
## about that centre, treating each block as a solid 1 m cube:
## {"mass": float, "center": Vector3, "inertia": Vector3}
func mass_properties() -> Dictionary:
	var mass := 0.0
	var moment := Vector3.ZERO
	for cell: Vector3i in blocks:
		var m := _mass(cell)
		mass += m
		moment += Vector3(cell) * m
	var center := moment / mass if mass > 0.0 else Vector3.ZERO
	var inertia := Vector3.ZERO
	for cell: Vector3i in blocks:
		var m := _mass(cell)
		var r := Vector3(cell) - center
		# A cube's own inertia (m/6 about each axis) plus its mass at distance r.
		inertia += Vector3(r.y * r.y + r.z * r.z, r.x * r.x + r.z * r.z, r.x * r.x + r.y * r.y) * m + Vector3.ONE * (m / 6.0)
	return {"mass": mass, "center": center, "inertia": inertia}


## The solid cells (everything but ladders) merged greedily into boxes, in ship
## space. Fewer boxes mean fewer shapes and no seams to catch feet on flat decks.
func merged_boxes() -> Array[AABB]:
	var left := {}
	for cell: Vector3i in blocks:
		if blocks[cell]["type"] != "ladder":
			left[cell] = true
	var starts := left.keys()
	starts.sort()
	var boxes: Array[AABB] = []
	for start: Vector3i in starts:
		if not left.has(start):
			continue
		var size := Vector3i.ONE
		while left.has(start + Vector3i(size.x, 0, 0)):
			size.x += 1
		while _all_in(left, start + Vector3i(0, size.y, 0), Vector3i(size.x, 1, 1)):
			size.y += 1
		while _all_in(left, start + Vector3i(0, 0, size.z), Vector3i(size.x, size.y, 1)):
			size.z += 1
		for x in size.x:
			for y in size.y:
				for z in size.z:
					left.erase(start + Vector3i(x, y, z))
		boxes.append(AABB(Vector3(start) - Vector3(0.5, 0.5, 0.5), Vector3(size)))
	return boxes


## The blocks grouped into ZONE_SIZE-cell zones for drag (spec §4.4). Each zone has
## its centre (the mean of its cells) and its area along each ship axis: half its
## exposed faces facing that way, which for a convex zone is its outline seen along
## that axis. [{"center": Vector3, "area": Vector3}]
func drag_zones() -> Array[Dictionary]:
	var sums := {}
	var counts := {}
	var areas := {}
	for cell: Vector3i in blocks:
		var zone := Vector3i(floori(cell.x / float(ZONE_SIZE)), floori(cell.y / float(ZONE_SIZE)), floori(cell.z / float(ZONE_SIZE)))
		sums[zone] = sums.get(zone, Vector3.ZERO) + Vector3(cell)
		counts[zone] = counts.get(zone, 0) + 1
		var area: Vector3 = areas.get(zone, Vector3.ZERO)
		for axis in 3:
			for side in [-1, 1]:
				var neighbour := cell
				neighbour[axis] += side
				if not blocks.has(neighbour):
					area[axis] += 0.5
		areas[zone] = area
	var zones: Array[Dictionary] = []
	for zone: Vector3i in sums:
		zones.append({"center": sums[zone] / counts[zone], "area": areas[zone]})
	return zones


func _mass(cell: Vector3i) -> float:
	return Tuning.BLOCKS[blocks[cell]["type"]]["mass"]


static func _all_in(cells: Dictionary, from: Vector3i, size: Vector3i) -> bool:
	for x in size.x:
		for y in size.y:
			for z in size.z:
				if not cells.has(from + Vector3i(x, y, z)):
					return false
	return true
```

`src/ship/starter_ship.gd`:
```gdscript
class_name StarterShip
## The ship every captain starts with: a 5 × 13 m deck on an iron-ballasted keel,
## a raised helm deck at the stern with a ladder up to it, a balloon envelope on
## four posts, and one engine driving two propellers. -Z is the bow. It floats
## level at about 900 m.


const ENVELOPE_FROM := -4
const ENVELOPE_TO := 6
const IRON_FROM := -1
const IRON_TO := 2


static func build() -> ShipGrid:
	var grid := ShipGrid.new()
	# Main deck, narrowing at the bow, on a keel. The engine sits in the bilge and
	# the middle of the keel is iron, which keeps her level.
	for z in range(-5, 7):
		for x in range(-2, 3):
			grid.set_block(Vector3i(x, 0, z), "deck")
		grid.set_block(Vector3i(0, -1, z), "iron" if z >= IRON_FROM and z <= IRON_TO else "frame")
	grid.set_block(Vector3i(0, -1, -5), "engine")
	for x in range(-1, 2):
		grid.set_block(Vector3i(x, 0, -6), "deck")
	# Rails.
	for z in range(-5, 4):
		grid.set_block(Vector3i(-2, 1, z), "deck")
		grid.set_block(Vector3i(2, 1, z), "deck")
	for x in range(-1, 2):
		grid.set_block(Vector3i(x, 1, -6), "deck")
	# The helm deck over the stern, 2 m up: planks on a front wall and side walls,
	# with rails and the helm at its front edge.
	for z in range(4, 7):
		for x in range(-2, 3):
			grid.set_block(Vector3i(x, 2, z), "deck")
		grid.set_block(Vector3i(-2, 1, z), "frame")
		grid.set_block(Vector3i(2, 1, z), "frame")
		grid.set_block(Vector3i(-2, 3, z), "deck")
		grid.set_block(Vector3i(2, 3, z), "deck")
	for x in range(-1, 2):
		grid.set_block(Vector3i(x, 1, 4), "frame")
		grid.set_block(Vector3i(x, 3, 6), "deck")
	grid.set_block(Vector3i(0, 3, 4), "helm")
	# Ladders up the front of the helm deck, either side of the helm, reaching 1 m
	# above it so you can step off.
	for y in range(1, 4):
		grid.set_block(Vector3i(-1, y, 3), "ladder")
		grid.set_block(Vector3i(1, y, 3), "ladder")
	# Propellers and rudders behind the stern.
	grid.set_block(Vector3i(-2, 1, 7), "propeller")
	grid.set_block(Vector3i(2, 1, 7), "propeller")
	grid.set_block(Vector3i(0, 1, 7), "rudder")
	grid.set_block(Vector3i(0, 2, 7), "rudder")
	# Four posts up to the envelope: at the bow end of the main deck, and at the
	# back corners of the helm deck, clear of the helmsman's view.
	for y in range(2, 8):
		grid.set_block(Vector3i(-2, y, -4), "frame")
		grid.set_block(Vector3i(2, y, -4), "frame")
	for y in range(3, 8):
		grid.set_block(Vector3i(-2, y, 6), "frame")
		grid.set_block(Vector3i(2, y, 6), "frame")
	# The envelope: 3 m tall and 5 m wide at its middle, running the ship's length.
	for z in range(ENVELOPE_FROM, ENVELOPE_TO + 1):
		for x in range(-1, 2):
			grid.set_block(Vector3i(x, 8, z), "balloon")
			grid.set_block(Vector3i(x, 10, z), "balloon")
		for x in range(-2, 3):
			grid.set_block(Vector3i(x, 9, z), "balloon")
	for z in [ENVELOPE_FROM - 1, ENVELOPE_TO + 1]:
		for x in range(-1, 2):
			grid.set_block(Vector3i(x, 9, z), "balloon")
	return grid
```

`ENVELOPE_*` and `IRON_*` came from a search for the most level ship that floats between 800 and 1,000 m. If you change the ship, re-run `test_the_starter_ship_balances_under_its_envelope`.

- [ ] **Step 4: Run the tests**

Run: `godot --headless --import >/dev/null 2>&1; ./run_tests.sh`
Expected: `52 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src/ship tests/test_ship_grid.gd tests/test_ship_grid.gd.uid
git commit -m "Add block catalogue, ship grid maths and the starter ship"
```

---

### Task 3: Air, drag, keel and wind maths

Build-log item: the maths half of "Forces: gravity, balloon lift that thins with altitude, thrust, drag, rudders".

**Files:**
- Create: `src/ship/ship_forces.gd`, `src/world/wind.gd`, `tests/test_ship_forces.gd`

**Interfaces:**
- Consumes: `Tuning` constants (Task 2).
- Produces:
  - `ShipForces.air_density(altitude) -> float`
  - `ShipForces.zone_drag(area: Vector3, air_velocity: Vector3, density) -> Vector3` (ship axes)
  - `ShipForces.keel(side_area, air_velocity, density) -> float` (along ship x)
  - `ShipForces.top_speed(thrust, forward_area, altitude) -> float`
  - `Wind.at(position: Vector3, time: float) -> Vector3`, and `Wind.PREVAILING`

- [ ] **Step 1: Write the failing tests**

`tests/test_ship_forces.gd`:
```gdscript
extends TestCase
## The flight model's formulas (spec §4.4).


func test_air_is_densest_at_the_roil_and_thins_above() -> void:
	assert_eq(ShipForces.air_density(200.0), 1.0)
	assert_eq(ShipForces.air_density(-50.0), 1.0, "no denser below the Roil's top")
	assert_near(ShipForces.air_density(2700.0), exp(-1.0), 1e-6)
	assert_near(ShipForces.air_density(800.0), 0.7866, 1e-4)


func test_drag_opposes_motion_along_each_axis_and_grows_with_speed_squared() -> void:
	var area := Vector3(2, 3, 4)
	var slow := ShipForces.zone_drag(area, Vector3(0, 0, -10), 1.0)
	var fast := ShipForces.zone_drag(area, Vector3(0, 0, -20), 1.0)
	assert_eq(slow.x, 0.0)
	assert_true(slow.z > 0.0, "moving toward -Z, drag pushes toward +Z")
	assert_near(fast.z, slow.z * 4.0, 1e-3)
	assert_near(slow.z, 0.5 * Tuning.AIR_DENSITY * Tuning.DRAG_COEFFICIENT * 4.0 * 100.0, 1e-3)
	var sideways := ShipForces.zone_drag(area, Vector3(-5, 0, 0), 0.5)
	assert_near(sideways.x, 0.5 * Tuning.AIR_DENSITY * 0.5 * Tuning.DRAG_COEFFICIENT * 2.0 * 25.0, 1e-3)


func test_the_keel_pushes_against_sideslip_only_when_moving_forward() -> void:
	assert_eq(ShipForces.keel(10.0, Vector3(3, 0, 0), 1.0), 0.0, "no forward speed, no keel")
	var slipping_right := ShipForces.keel(10.0, Vector3(3, 0, -20), 1.0)
	assert_true(slipping_right < 0.0, "pushes back to port")
	assert_near(ShipForces.keel(10.0, Vector3(3, 0, -40), 1.0), slipping_right * 2.0, 1e-3, "twice as hard at twice the speed")
	assert_near(slipping_right, -0.5 * Tuning.AIR_DENSITY * Tuning.HULL_LIFT * 10.0 * 20.0 * 3.0, 1e-3)


func test_top_speed_is_where_thrust_meets_drag() -> void:
	var speed := ShipForces.top_speed(5000.0, 50.0, 800.0)
	var drag := ShipForces.zone_drag(Vector3(0, 0, 50.0), Vector3(0, 0, -speed), ShipForces.air_density(800.0))
	assert_near(drag.z, 5000.0, 0.01)
	assert_eq(ShipForces.top_speed(0.0, 50.0, 800.0), 0.0)


func test_the_prevailing_wind_circles_the_eye_counter_clockwise() -> void:
	# Gusts come and go; over ten minutes they average out, leaving the prevailing wind.
	var sum := Vector3.ZERO
	for second in 600:
		sum += Wind.at(Vector3(0, 800, 7000), second)  # due south of the Eye
	assert_near((sum / 600.0).x, Wind.PREVAILING, 0.3, "blowing east there")
	assert_near((sum / 600.0).z, 0.0, 0.3)
```

- [ ] **Step 2: Run them to see them fail**

Run: `./run_tests.sh ship_forces`
Expected: FAIL, could not load.

- [ ] **Step 3: Write the maths**

`src/ship/ship_forces.gd`:
```gdscript
class_name ShipForces
## The flight model's formulas (spec §4.4), free of nodes so tests and the
## shipyard readouts can use them.


## Air density at altitude as a fraction of the density at the Roil: 1 at 200 m
## and below, thinning above.
static func air_density(altitude: float) -> float:
	if altitude <= Tuning.ROIL_ALTITUDE:
		return 1.0
	return exp(-(altitude - Tuning.ROIL_ALTITUDE) / Tuning.AIR_SCALE_HEIGHT)


## Drag on one zone, in ship axes, from the zone's velocity through the air in ship
## axes. Each axis is separate: -½ × ρ × Cd × area × |v| × v.
static func zone_drag(area: Vector3, air_velocity: Vector3, density: float) -> Vector3:
	return -0.5 * Tuning.AIR_DENSITY * density * Tuning.DRAG_COEFFICIENT * area * air_velocity.abs() * air_velocity


## The hull's sideways lift on one zone, along ship x: moving forward while
## slipping sideways, the hull pushes back against the slip as a keel does, which
## is what lets a ship carve a turn. It needs forward speed, so hovering ships
## still drift with the wind.
static func keel(side_area: float, air_velocity: Vector3, density: float) -> float:
	return -0.5 * Tuning.AIR_DENSITY * density * Tuning.HULL_LIFT * side_area * absf(air_velocity.z) * air_velocity.x


## The speed at which drag on forward_area matches thrust, at altitude.
static func top_speed(thrust: float, forward_area: float, altitude: float) -> float:
	if thrust <= 0.0 or forward_area <= 0.0:
		return 0.0
	return sqrt(thrust / (0.5 * Tuning.AIR_DENSITY * air_density(altitude) * Tuning.DRAG_COEFFICIENT * forward_area))
```

`src/world/wind.gd`:
```gdscript
class_name Wind
## Wind in m/s at a point and time (spec §4.7). It's a pure function of position and
## time, so every machine agrees on it without sending it. Stage 2 has the
## prevailing wind and gusts; stage 5 adds sky rivers and storm cells.

const PREVAILING := 3.0  ## m/s, circling the Eye counter-clockwise.
const GUSTS := 2.5       ## m/s, the gusts' typical strength.


static func at(position: Vector3, time: float) -> Vector3:
	var around := Vector3(position.z, 0.0, -position.x)  # counter-clockwise seen from above
	var prevailing := around.normalized() * PREVAILING if around.length() > 1.0 else Vector3.ZERO
	var gust := Vector3(
		sin(time * 0.37 + position.z * 0.011) + 0.5 * sin(time * 1.13 + position.x * 0.023),
		0.3 * sin(time * 0.71 + position.x * 0.017),
		sin(time * 0.29 + position.x * 0.013) + 0.5 * sin(time * 0.97 + position.z * 0.019))
	return prevailing + gust * GUSTS
```

- [ ] **Step 4: Run the tests**

Run: `godot --headless --import >/dev/null 2>&1; ./run_tests.sh`
Expected: `57 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src/ship/ship_forces.gd src/world/wind.gd tests/test_ship_forces.gd src/ship/*.uid src/world/*.uid tests/*.uid
git commit -m "Add air density, drag, keel and wind maths"
```

---

### Task 4: The ship body, its forces and the flight tests

Build-log items: "Ship body: mass, centre of mass and inertia worked out from its blocks", "Forces: …", and the flight tests of "Tests: mass and balance maths, plus flight tests".

**Files:**
- Create: `src/ship/ship_mesh.gd`, `src/ship/ship.gd`, `tests/test_ship.gd`

**Interfaces:**
- Consumes: `ShipGrid`, `StarterShip`, `ShipForces`, `Wind`, `Tuning`.
- Produces:
  - `Ship.new(grid: ShipGrid)`, a `RigidBody3D`, with:
    - `grid`
    - `throttle` (−0.5 to 1), `rudder` (−1 port to 1 starboard), `trim` (0.8 to 1.1)
    - `calm: bool` (no wind)
    - `MAX_SPEED`, `MAX_SPIN`
    - `max_thrust() -> float`
    - `trim_to_float_at(altitude) -> float`
    - `heading() -> float` (radians, 0 = bow along −Z, positive toward port)
  - `ShipMesh.build(grid) -> MeshInstance3D`

- [ ] **Step 1: Write the failing flight tests**

`tests/test_ship.gd`:
```gdscript
extends TestCase
## Ships built from blocks, and flight tests: real physics, run headless, decides
## whether they fly (spec §6). Ships fly in still air unless a test says otherwise.

const START := Vector3(0, 877, 7000)


## A ship from grid, in still air at START.
func launch(grid: ShipGrid) -> Ship:
	var ship := Ship.new(grid)
	ship.calm = true
	ship.position = START
	add_child(ship)
	return ship


## Degrees the ship leans to starboard (negative: to port).
func listing(ship: Ship) -> float:
	return rad_to_deg(asin(-ship.global_basis.x.y))


## Degrees the bow points up (negative: down).
func pitch(ship: Ship) -> float:
	return rad_to_deg(asin(-ship.global_basis.z.y))


## Where the balloons' lift acts in ship space.
func lift_center(grid: ShipGrid) -> Vector3:
	var sum := Vector3.ZERO
	for cell in grid.cells_of("balloon"):
		sum += Vector3(cell)
	return sum / grid.cells_of("balloon").size()


func test_a_ship_takes_its_mass_and_shape_from_its_blocks() -> void:
	var grid := StarterShip.build()
	var ship := launch(grid)
	var props := grid.mass_properties()
	assert_eq(ship.mass, props["mass"])
	assert_eq(ship.center_of_mass, props["center"])
	assert_eq(ship.inertia, props["inertia"])
	assert_eq(ship.find_children("*", "CollisionShape3D", false, false).size(), grid.merged_boxes().size())
	assert_eq(ship.max_thrust(), 5000.0, "one engine drives both propellers at full power")


func test_the_starter_ship_floats_where_the_numbers_say() -> void:
	var ship := launch(StarterShip.build())
	assert_near(ship.trim_to_float_at(START.y), 1.0, 0.01, "she floats near 877 m at trim 1")
	await simulate(60.0)
	assert_near(ship.global_position.y, START.y, 25.0, "and stays near there")


func test_a_balanced_ship_holds_level() -> void:
	var ship := launch(StarterShip.build())
	await simulate(60.0)
	assert_near(listing(ship), 0.0, 0.3)
	assert_near(pitch(ship), 0.0, 0.3)


func test_a_lopsided_ship_lists_toward_its_heavy_side() -> void:
	var grid := StarterShip.build()
	for z in range(-2, 4):
		grid.set_block(Vector3i(3, 0, z), "iron")  # iron bolted along the starboard side
	var props := grid.mass_properties()
	var com: Vector3 = props["center"]
	var lift := lift_center(grid)
	var expected := rad_to_deg(atan2(com.x - lift.x, lift.y - com.y))  # the lift ends up straight above the weight
	var ship := launch(grid)
	await simulate(60.0)
	assert_true(expected > 2.0, "the test ship is lopsided enough to see (%.2f°)" % expected)
	assert_near(listing(ship), expected, 0.3, "lists to starboard as the balance says")


func test_an_overloaded_ship_sinks() -> void:
	var grid := StarterShip.build()
	for z in range(-4, 4):
		for x in [-1, 0, 1]:
			grid.set_block(Vector3i(x, 1, z), "iron")
	var ship := launch(grid)
	assert_true(ship.trim_to_float_at(Tuning.ROIL_ALTITUDE) > Tuning.TRIM_MAX, "too heavy to float anywhere")
	await simulate(40.0)
	assert_true(ship.global_position.y < Tuning.ROIL_ALTITUDE, "sank into the Roil (at %.0f m)" % ship.global_position.y)
	assert_true(ship.linear_velocity.y < -5.0, "and is still sinking")


func test_top_speed_is_within_ten_percent_of_the_estimate() -> void:
	var ship := launch(StarterShip.build())
	ship.throttle = 1.0
	await simulate(240.0)
	var forward_area := 0.0
	for zone in ship.grid.drag_zones():
		forward_area += zone["area"].z
	var estimate := ShipForces.top_speed(ship.max_thrust(), forward_area, ship.global_position.y)
	var speed := ship.linear_velocity.length()
	assert_near(speed, estimate, estimate * 0.1, "estimate %.1f m/s" % estimate)


func test_starboard_rudder_turns_to_starboard() -> void:
	var ship := launch(StarterShip.build())
	ship.throttle = 1.0
	await simulate(30.0)
	var before := ship.heading()
	ship.rudder = 1.0
	await simulate(10.0)
	var turned := rad_to_deg(wrapf(before - ship.heading(), -PI, PI))
	assert_true(turned > 30.0, "turned %.0f° clockwise" % turned)


func test_a_physics_blow_up_puts_the_ship_back() -> void:
	var ship := launch(StarterShip.build())
	await simulate(0.5)
	var good := ship.global_transform
	ship.linear_velocity = Vector3(1000, 0, 0)
	await simulate(0.1)
	assert_true(ship.global_position.distance_to(good.origin) < 1.0, "back where it was")
	assert_true(ship.linear_velocity.length() < 1.0, "and stopped")
```

- [ ] **Step 2: Run them to see them fail**

Run: `./run_tests.sh test_ship.gd`
Expected: FAIL, could not load.

- [ ] **Step 3: Write the mesh and the ship**

`src/ship/ship_mesh.gd`:
```gdscript
class_name ShipMesh
## Draws a ship's blocks as one low-poly mesh coloured by block type (spec §3.9).
## Faces between neighbouring solid blocks are left out, and ladders are drawn as
## rails and rungs so they read as something you can walk into.
# ponytail: one mesh for the whole ship. Split it into 16³ sections (spec §4.4) when damage (stage 6) rebuilds it on every hit.

const COLORS := {
	"frame": Color("8a5a3b"),
	"deck": Color("b98a5e"),
	"iron": Color("5b6068"),
	"alloy": Color("a7b1bb"),
	"balloon": Color("e9dfc9"),
	"lift_stone": Color("7fd3c5"),
	"engine": Color("3d3a3f"),
	"propeller": Color("b48a3c"),
	"rudder": Color("9b3f2f"),
	"sail": Color("f2ead8"),
	"fuel_tank": Color("6b4f2d"),
	"ballast_tank": Color("4d6b7a"),
	"helm": Color("c9a25a"),
	"cannon": Color("2f3033"),
	"cargo_bay": Color("8f7550"),
	"bunk": Color("7d5a6b"),
	"ladder": Color("c79a64"),
}

const _FACES := [
	[Vector3i(1, 0, 0), Vector3(0.5, -0.5, -0.5), Vector3(0, 1, 0), Vector3(0, 0, 1)],
	[Vector3i(-1, 0, 0), Vector3(-0.5, -0.5, 0.5), Vector3(0, 1, 0), Vector3(0, 0, -1)],
	[Vector3i(0, 1, 0), Vector3(-0.5, 0.5, -0.5), Vector3(0, 0, 1), Vector3(1, 0, 0)],
	[Vector3i(0, -1, 0), Vector3(-0.5, -0.5, 0.5), Vector3(0, 0, -1), Vector3(1, 0, 0)],
	[Vector3i(0, 0, 1), Vector3(0.5, -0.5, 0.5), Vector3(0, 1, 0), Vector3(-1, 0, 0)],
	[Vector3i(0, 0, -1), Vector3(-0.5, -0.5, -0.5), Vector3(0, 1, 0), Vector3(1, 0, 0)],
]


static func build(grid: ShipGrid) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell: Vector3i in grid.blocks:
		var type: String = grid.blocks[cell]["type"]
		if type == "ladder":
			_add_ladder(st, Vector3(cell))
			continue
		st.set_color(COLORS[type])
		for face: Array in _FACES:
			var neighbour := grid.type_at(cell + (face[0] as Vector3i))
			if neighbour != "" and neighbour != "ladder":
				continue
			_add_quad(st, Vector3(cell) + (face[1] as Vector3), face[2], face[3], Vector3(face[0] as Vector3i))
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.9
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	mesh_instance.material_override = material
	return mesh_instance


## A quad from corner along edges u and v (a right-handed pair around normal).
static func _add_quad(st: SurfaceTool, corner: Vector3, u: Vector3, v: Vector3, normal: Vector3) -> void:
	st.set_normal(normal)
	for point in [corner, corner + u, corner + u + v, corner, corner + u + v, corner + v]:
		st.add_vertex(point)


static func _add_box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	for face: Array in _FACES:
		var scale := size
		_add_quad(st, center + (face[1] as Vector3) * scale, (face[2] as Vector3) * scale, (face[3] as Vector3) * scale, Vector3(face[0] as Vector3i))


static func _add_ladder(st: SurfaceTool, center: Vector3) -> void:
	st.set_color(COLORS["ladder"])
	for x in [-0.4, 0.4]:
		_add_box(st, center + Vector3(x, 0, 0), Vector3(0.08, 1.0, 0.08))
	for y in [-0.3, 0.0, 0.3]:
		_add_box(st, center + Vector3(0, y, 0), Vector3(0.8, 0.06, 0.06))
```

`src/ship/ship.gd`. Task 5 adds the interior and Task 6 the helm:
```gdscript
class_name Ship
extends RigidBody3D
## A ship: one rigid body built from a ShipGrid, flying on the forces of spec §4.4.
## Each physics tick it applies lift, thrust, drag and the rudders' push; the
## engine adds gravity. Its crew walk in its interior, a separate physics world in
## ship space (spec §4.5).

const MAX_SPEED := 400.0  ## m/s. Anything faster is a physics blow-up.
const MAX_SPIN := 20.0    ## rad/s. Likewise.

var grid: ShipGrid
var throttle := 0.0  ## Tuning.THROTTLE_MIN (full astern) to 1 (full ahead).
var rudder := 0.0    ## -1 (hard to port) to 1 (hard to starboard).
var trim := 1.0      ## Balloon trim, Tuning.TRIM_MIN to Tuning.TRIM_MAX.
var calm := false    ## No wind. Flight tests fly in still air.

var _balloons: Array[Vector3] = []
var _lift_stones: Array[Vector3] = []
var _propellers: Array[Vector3] = []
var _rudders: Array[Vector3] = []
var _zones: Array[Dictionary] = []
var _power := 0.0  ## The share of full thrust the engines give each propeller.
var _last_good := Transform3D.IDENTITY


func _init(ship_grid: ShipGrid) -> void:
	grid = ship_grid


func _ready() -> void:
	var props := grid.mass_properties()
	mass = props["mass"]
	center_of_mass_mode = CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = props["center"]
	inertia = props["inertia"]
	can_sleep = false
	linear_damp_mode = DAMP_MODE_REPLACE
	angular_damp_mode = DAMP_MODE_REPLACE
	angular_damp = Tuning.ANGULAR_DAMPING
	var boxes := grid.merged_boxes()
	for box in boxes:
		var cube := BoxShape3D.new()
		cube.size = box.size
		var shape := CollisionShape3D.new()
		shape.shape = cube
		shape.position = box.get_center()
		add_child(shape)
	for cell in grid.cells_of("balloon"):
		_balloons.append(Vector3(cell))
	for cell in grid.cells_of("lift_stone"):
		_lift_stones.append(Vector3(cell))
	for cell in grid.cells_of("propeller"):
		_propellers.append(Vector3(cell))
	for cell in grid.cells_of("rudder"):
		_rudders.append(Vector3(cell))
	if not _propellers.is_empty():
		_power = minf(1.0, float(grid.cells_of("engine").size() * Tuning.PROPELLERS_PER_ENGINE) / _propellers.size())
	_zones = grid.drag_zones()
	_last_good = global_transform
	add_child(ShipMesh.build(grid))


## Full-throttle thrust in N.
func max_thrust() -> float:
	return _propellers.size() * _power * Tuning.PROPELLER_THRUST


## The trim at which lift equals weight at altitude (it may fall outside the trim limits).
func trim_to_float_at(altitude: float) -> float:
	var weight := mass * float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	var balloon_lift := _balloons.size() * Tuning.BALLOON_LIFT * ShipForces.air_density(altitude)
	if balloon_lift <= 0.0:
		return Tuning.TRIM_MAX
	return (weight - _lift_stones.size() * Tuning.LIFT_STONE_LIFT) / balloon_lift


## Compass heading in radians: 0 when the bow points along -Z, growing as she turns to port.
func heading() -> float:
	var bow := -global_basis.z
	return atan2(-bow.x, -bow.z)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not _sane(state):
		push_warning("Ship %s blew up (speed %.0f m/s, spin %.1f rad/s); restoring its last good position." % [name, state.linear_velocity.length(), state.angular_velocity.length()])
		state.transform = _last_good
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		return
	_last_good = state.transform
	var basis := state.transform.basis
	var altitude := state.transform.origin.y
	# The wind's clock is physics ticks since the game started; stage 3 uses the host's.
	var wind := Vector3.ZERO if calm else Wind.at(state.transform.origin, Engine.get_physics_frames() / float(Engine.physics_ticks_per_second))

	# Lift: every balloon and lift stone pulls straight up, so together they act as
	# one force at their lift-weighted centre.
	var lift := 0.0
	var lift_moment := Vector3.ZERO
	for cell in _balloons:
		var offset := basis * cell
		var force := Tuning.BALLOON_LIFT * ShipForces.air_density(altitude + offset.y) * trim
		lift += force
		lift_moment += offset * force
	for cell in _lift_stones:
		var offset := basis * cell
		lift += Tuning.LIFT_STONE_LIFT
		lift_moment += offset * Tuning.LIFT_STONE_LIFT
	if lift > 0.0:
		state.apply_force(Vector3(0.0, lift, 0.0), lift_moment / lift)

	# Thrust. Propellers push toward the bow until the shipyard can turn blocks.
	var thrust := -basis.z * throttle * _power * Tuning.PROPELLER_THRUST
	for cell in _propellers:
		state.apply_force(thrust, basis * cell)

	# Drag and the keel's push on each zone, from its own velocity through the air.
	var to_ship := basis.transposed()
	for zone in _zones:
		var offset := basis * (zone["center"] as Vector3)
		var air := to_ship * (state.get_velocity_at_local_position(offset) - wind)
		var density := ShipForces.air_density(altitude + offset.y)
		var force := ShipForces.zone_drag(zone["area"], air, density)
		force.x += ShipForces.keel(zone["area"].x, air, density)
		state.apply_force(basis * force, offset)

	# Rudders push the stern sideways, harder the faster air flows past them.
	for cell in _rudders:
		var offset := basis * cell
		var flow := -basis.z.dot(state.get_velocity_at_local_position(offset) - wind)
		var push := Tuning.RUDDER_FORCE * ShipForces.air_density(altitude + offset.y) * flow * absf(flow) * rudder
		state.apply_force(-basis.x * push, offset)


func _sane(state: PhysicsDirectBodyState3D) -> bool:
	return state.transform.is_finite() and state.linear_velocity.is_finite() and state.angular_velocity.is_finite() \
			and state.linear_velocity.length() <= MAX_SPEED and state.angular_velocity.length() <= MAX_SPIN
```

- [ ] **Step 4: Run the tests**

Run: `godot --headless --import >/dev/null 2>&1; ./run_tests.sh`
Expected: `65 passed, 0 failed`. The flight tests simulate about 9 minutes between them in about 10 s. A "Jolt Physics job system exceeded the maximum number of jobs" warning may appear; it only happens faster than real time.

- [ ] **Step 5: Commit**

```bash
git add src/ship tests/test_ship.gd tests/test_ship.gd.uid
git commit -m "Add the ship body with lift, thrust, drag, rudders and a physics guard"
```

---

### Task 5: Walking on the deck

Build-log item: "Prove walking on a rolling, pitching deck", and the physics half of "First-person crew: walk, jump, climb ladders, use stations".

**Files:**
- Create: `src/crew/ship_interior.gd`, `src/crew/crew_member.gd`, `tests/test_crew.gd`
- Modify: `src/ship/ship.gd`

**Interfaces:**
- Consumes: `Ship` (Task 4).
- Produces:
  - `ShipInterior.new(boxes: Array[AABB])`, a `SubViewport` with its own world.
  - `Ship.interior: ShipInterior`
  - `CrewMember.new(ship: Ship, at: Vector3)`, a `CharacterBody3D` to add under `ship.interior`, with:
    - fields `move: Vector2` (as `Input.get_vector` gives it), `look_yaw`, `sprint`, `jump`, `climb`, `station: Node`, `home: Vector3`
    - signal `fell_overboard`
    - constants `WALK_SPEED`, `HEIGHT`, `RADIUS`, `EYE_HEIGHT`
    - `on_ladder() -> bool`

- [ ] **Step 1: Write the failing tests**

`tests/test_crew.gd`:
```gdscript
extends TestCase
## Walking on a moving deck (spec §4.5): crew live in the ship's interior, where
## gravity is the ship's "down". Here the ship is held and rocked by the test,
## far harder than wind ever will: ±15° of roll and ±8° of pitch.

var ship: Ship
var crew: CrewMember


func board(at: Vector3) -> void:
	ship = Ship.new(StarterShip.build())
	ship.freeze = true
	ship.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	ship.position = Vector3(0, 877, 7000)
	add_child(ship)
	crew = CrewMember.new(ship, at)
	ship.interior.add_child(crew)


func rock(tick: int) -> void:
	var t := tick / 60.0
	ship.rotation = Vector3(deg_to_rad(8.0) * sin(t * 0.9), 0.0, deg_to_rad(15.0) * sin(t * 1.3))


func test_the_interior_holds_a_still_copy_of_the_hull() -> void:
	board(Vector3(0, 1.45, -2))
	var hull := ship.interior.get_child(0) as StaticBody3D
	var boxes: Array[AABB] = []
	for shape: CollisionShape3D in hull.get_children():
		boxes.append(AABB(shape.position - (shape.shape as BoxShape3D).size / 2.0, (shape.shape as BoxShape3D).size))
	assert_eq(boxes, ship.grid.merged_boxes(), "the ship's boxes, in ship space")
	assert_eq(crew.get_world_3d(), ship.interior.find_world_3d())
	assert_true(crew.get_world_3d() != ship.get_world_3d(), "a physics world of its own")


func test_standing_on_a_rolling_deck_stays_put() -> void:
	board(Vector3(0, 1.45, -2))
	await simulate(1.0)
	var start := crew.position
	var standing := [0]
	await simulate(20.0, func(tick: int) -> void:
		rock(tick)
		if crew.is_on_floor():
			standing[0] += 1)
	assert_true(crew.position.distance_to(start) < 0.05, "drifted %.3f m" % crew.position.distance_to(start))
	assert_eq(standing[0], 20 * 60, "on the deck every tick")


func test_walking_goes_along_the_deck_while_it_rolls() -> void:
	board(Vector3(0, 1.45, 0))
	await simulate(1.0)
	crew.move = Vector2(0, -1)  # forward, toward the bow
	await simulate(1.0, rock)
	assert_near(crew.position.z, -CrewMember.WALK_SPEED, 0.2, "walked 4 m toward the bow")
	assert_near(crew.position.y, 1.4, 0.05, "and stayed on the deck")


func test_jumping_leaves_the_deck_and_lands_again() -> void:
	board(Vector3(0, 1.45, -2))
	await simulate(1.0)
	crew.jump = true
	var highest := [0.0]
	await simulate(1.5, func(tick: int) -> void:
		rock(tick)
		highest[0] = maxf(highest[0], crew.position.y))
	assert_near(highest[0] - 1.4, 1.08, 0.1, "rose about a metre")
	assert_true(crew.is_on_floor(), "landed")


func test_climbing_a_ladder_up_to_the_helm_deck() -> void:
	board(Vector3(1, 1.45, 1))  # on the main deck, in front of the starboard ladder
	await simulate(1.0)
	crew.look_yaw = PI  # facing aft
	crew.move = Vector2(0, -1)
	crew.climb = 1.0
	await simulate(5.0, rock)
	assert_near(crew.position.y, 3.4, 0.05, "standing on the helm deck")
	assert_true(crew.position.z > 3.5, "past the top of the ladder")


func test_falling_overboard_brings_you_back_aboard() -> void:
	board(Vector3(0, 1.45, -2))
	var fell := [false]
	crew.fell_overboard.connect(func() -> void: fell[0] = true)
	crew.position = Vector3(0, -40, 0)
	await simulate(0.1)
	assert_true(fell[0], "fell_overboard fires")
	assert_true(crew.position.distance_to(crew.home) < 0.1, "back where you came aboard")


func test_nobody_walks_while_at_a_station() -> void:
	board(Vector3(0, 1.45, -2))
	await simulate(1.0)
	var start := crew.position
	var station := Node.new()
	add_child(station)
	crew.station = station
	crew.move = Vector2(0, -1)
	crew.jump = true
	await simulate(1.0)
	assert_true(crew.position.distance_to(start) < 0.01, "stayed put")
```

- [ ] **Step 2: Run them to see them fail**

Run: `./run_tests.sh crew`
Expected: FAIL, could not load.

- [ ] **Step 3: Write the interior and the crew member, and give ships an interior**

`src/crew/ship_interior.gd`:
```gdscript
class_name ShipInterior
extends SubViewport
## A ship's interior (spec §4.5): a physics world of its own, in ship space, where
## its crew walk. It holds a still copy of the ship's collision boxes, so however
## the ship moves, the deck under the crew doesn't. Nothing here is drawn.


func _init(boxes: Array[AABB]) -> void:
	own_world_3d = true
	size = Vector2i(2, 2)
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	var hull := StaticBody3D.new()
	for box in boxes:
		var cube := BoxShape3D.new()
		cube.size = box.size
		var shape := CollisionShape3D.new()
		shape.shape = cube
		shape.position = box.get_center()
		hull.add_child(shape)
	add_child(hull)
```

`src/crew/crew_member.gd`:
```gdscript
class_name CrewMember
extends CharacterBody3D
## Someone aboard a ship, walking in its interior (ship space). Gravity is the
## ship's "down" (spec §4.5), so a tilting deck feels like a slope. Whoever
## controls a crew member sets move, look_yaw, sprint, jump and climb; it doesn't
## read the keyboard itself.

signal fell_overboard

const WALK_SPEED := 4.0
const SPRINT_SPEED := 6.5
const JUMP_SPEED := 4.6    ## About 1.1 m high: onto a 1 m block, but not a 2 m deck.
const CLIMB_SPEED := 2.5
const HEIGHT := 1.8
const RADIUS := 0.35
const EYE_HEIGHT := 0.7    ## Above the middle of the body.
const OVERBOARD := 30.0    ## Metres below the ship's lowest block that count as lost.

var ship: Ship
var home: Vector3            ## Where to come back aboard after falling overboard.
var move := Vector2.ZERO     ## As Input.get_vector gives it: x to starboard, y aft.
var look_yaw := 0.0          ## Radians, relative to the ship. 0 faces the bow.
var sprint := false
var jump := false            ## Jump on the next tick, if standing.
var climb := 0.0             ## On a ladder: 1 up, -1 down.
var station: Node = null     ## The station being used. Nobody walks while at one.

var _lowest := 0.0


func _init(crew_ship: Ship, at: Vector3) -> void:
	ship = crew_ship
	home = at
	position = at
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	add_child(shape)
	_lowest = INF
	for cell: Vector3i in ship.grid.blocks:
		_lowest = minf(_lowest, cell.y - 0.5)


func _physics_process(delta: float) -> void:
	var gravity := ship.global_basis.transposed() * Vector3(0.0, -float(ProjectSettings.get_setting("physics/3d/default_gravity")), 0.0)
	up_direction = -gravity.normalized()
	var wish := Basis(Vector3.UP, look_yaw) * Vector3(move.x, 0.0, move.y).limit_length(1.0) * (SPRINT_SPEED if sprint else WALK_SPEED)
	if station != null:
		wish = Vector3.ZERO
	var holding_on := on_ladder()
	var jumping := false
	if holding_on:
		# Hold on: no gravity, and climb along the ship's up.
		velocity = wish + Vector3.UP * climb * CLIMB_SPEED
	elif is_on_floor():
		var floor_normal := get_floor_normal()
		velocity = wish - floor_normal * wish.dot(floor_normal)
		if jump and station == null:
			velocity += up_direction * JUMP_SPEED
			jumping = true
	else:
		var up := up_direction
		velocity = wish - up * wish.dot(up) + up * velocity.dot(up) + gravity * delta
	jump = false
	var was_on_floor := is_on_floor()
	move_and_slide()
	if was_on_floor and not is_on_floor() and not jumping and not holding_on:
		apply_floor_snap()  # walking "uphill" against a tilted gravity skips Godot's own snap
	if position.y < _lowest - OVERBOARD:
		position = home
		velocity = Vector3.ZERO
		reset_physics_interpolation()
		fell_overboard.emit()


## Whether the middle of the body is in a ladder's cell, from the feet to the waist.
func on_ladder() -> bool:
	var column := Vector2i(roundi(position.x), roundi(position.z))
	for y in range(roundi(position.y - HEIGHT / 2.0), roundi(position.y) + 1):
		if ship.grid.type_at(Vector3i(column.x, y, column.y)) == "ladder":
			return true
	return false
```

In `src/ship/ship.gd`, add the field after `var grid: ShipGrid`:
```gdscript
var interior: ShipInterior  ## Where the crew walk.
```
and at the end of `_ready()`:
```gdscript
	interior = ShipInterior.new(boxes)
	add_child(interior)
```

- [ ] **Step 4: Run the tests**

Run: `godot --headless --import >/dev/null 2>&1; ./run_tests.sh`
Expected: `72 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src/crew src/ship/ship.gd tests/test_crew.gd tests/test_crew.gd.uid
git commit -m "Let crew walk, jump and climb in each ship's own physics world"
```

---

### Task 6: The helm and autopilot

Build-log item: "Helm: throttle, rudder, climb and descend, autopilot that holds course".

**Files:**
- Create: `src/crew/helm.gd`, `tests/test_helm.gd`
- Modify: `src/ship/ship.gd`, `src/ship/tuning.gd`

**Interfaces:**
- Consumes: `Ship`, `CrewMember`.
- Produces:
  - `Helm.new(ship, cell)`, with:
    - `pilot`, `cell`
    - `throttle_input`, `rudder_input`, `climb_input` (each −1 to 1)
    - `autopilot`, `target_heading`, `target_altitude`
    - `take(crew) -> bool`, `leave(crew)`, `set_autopilot(on: bool)`
  - `Ship.helm: Helm` and `Ship.crew_spawn() -> Vector3`

- [ ] **Step 1: Write the failing tests**

`tests/test_helm.gd`:
```gdscript
extends TestCase
## The helm: one pilot at a time, throttle and trim that stay set, a rudder that
## centres, and an autopilot that holds course (spec §3.4).

var ship: Ship
var crew: CrewMember


func _ready() -> void:
	ship = Ship.new(StarterShip.build())
	ship.calm = true
	ship.position = Vector3(0, 877, 7000)
	add_child(ship)
	crew = CrewMember.new(ship, ship.crew_spawn())
	ship.interior.add_child(crew)


func test_crew_come_aboard_just_aft_of_the_helm() -> void:
	assert_eq(ship.helm.cell, ship.grid.cells_of("helm")[0])
	assert_eq(ship.crew_spawn(), Vector3(0, 3.45, 5))
	await simulate(0.5)
	assert_true(crew.is_on_floor(), "standing on the helm deck")
	assert_eq(crew.station, null)


func test_one_pilot_at_a_time() -> void:
	var other := CrewMember.new(ship, ship.crew_spawn())
	ship.interior.add_child(other)
	assert_true(ship.helm.take(crew))
	assert_eq(crew.station, ship.helm)
	assert_false(ship.helm.take(other), "taken")
	assert_eq(other.station, null)
	ship.helm.leave(other)
	assert_eq(ship.helm.pilot, crew, "only the pilot can let go")
	ship.helm.leave(crew)
	assert_eq(ship.helm.pilot, null)
	assert_eq(crew.station, null)


func test_throttle_and_trim_stay_set_and_the_rudder_centres() -> void:
	ship.helm.take(crew)
	ship.helm.throttle_input = 1.0
	ship.helm.rudder_input = -1.0
	ship.helm.climb_input = 1.0
	await simulate(1.0)
	assert_near(ship.throttle, Tuning.THROTTLE_RATE, 0.02, "half throttle after a second")
	assert_eq(ship.rudder, -1.0)
	assert_near(ship.trim, 1.0 + Tuning.TRIM_RATE, 0.002)
	await simulate(3.0)
	assert_eq(ship.throttle, 1.0, "full ahead at most")
	assert_eq(ship.trim, Tuning.TRIM_MAX)
	ship.helm.leave(crew)
	await simulate(0.1)
	assert_eq(ship.throttle, 1.0, "throttle stays")
	assert_eq(ship.trim, Tuning.TRIM_MAX, "trim stays")
	assert_eq(ship.rudder, 0.0, "rudder centres")


func test_an_empty_helm_leaves_the_controls_alone() -> void:
	ship.rudder = 0.5
	ship.trim = 0.9
	await simulate(0.5)
	assert_eq(ship.rudder, 0.5)
	assert_eq(ship.trim, 0.9)


func test_the_autopilot_holds_course_through_gusts_and_follows_a_new_one() -> void:
	ship.calm = false
	ship.throttle = 1.0
	ship.helm.set_autopilot(true)
	await simulate(60.0)
	assert_near(rad_to_deg(wrapf(ship.heading() - ship.helm.target_heading, -PI, PI)), 0.0, 3.0, "holds heading")
	assert_near(ship.global_position.y, ship.helm.target_altitude, 10.0, "holds altitude")
	ship.helm.target_heading = wrapf(ship.helm.target_heading - PI / 2.0, -PI, PI)
	ship.helm.target_altitude += 50.0
	await simulate(60.0)
	assert_near(rad_to_deg(wrapf(ship.heading() - ship.helm.target_heading, -PI, PI)), 0.0, 3.0, "turned 90°")
	assert_near(ship.global_position.y, ship.helm.target_altitude, 10.0, "climbed 50 m")


func test_the_autopilot_keeps_flying_when_the_pilot_leaves() -> void:
	ship.helm.take(crew)
	ship.helm.set_autopilot(true)
	ship.helm.leave(crew)
	ship.helm.target_heading = wrapf(ship.helm.target_heading + 0.5, -PI, PI)
	ship.throttle = 1.0
	await simulate(20.0)
	assert_true(absf(ship.rudder) > 0.0 or absf(wrapf(ship.heading() - ship.helm.target_heading, -PI, PI)) < 0.05, "still steering")
```

- [ ] **Step 2: Run them to see them fail**

Run: `./run_tests.sh helm`
Expected: FAIL, could not load.

- [ ] **Step 3: Write the helm, its numbers, and put one on every ship**

Append to `src/ship/tuning.gd`:
```gdscript
const THROTTLE_MIN := -0.5        ## Full astern.
const THROTTLE_RATE := 0.5        ## Throttle change per second while W or S is held.
const TRIM_RATE := 0.05           ## Trim change per second while climbing or descending.

const AUTOPILOT_TURN_RATE := 0.25       ## rad/s the autopilot's heading turns while A or D is held.
const AUTOPILOT_CLIMB_RATE := 10.0      ## m/s its altitude changes while climbing or descending.
const AUTOPILOT_HEADING_GAIN := 3.0     ## Rudder per radian off course.
const AUTOPILOT_YAW_DAMPING := 6.0      ## Rudder per rad/s of turning.
const AUTOPILOT_ALTITUDE_GAIN := 0.002  ## Trim per metre off altitude.
const AUTOPILOT_CLIMB_DAMPING := 0.03   ## Trim per m/s of climb.
```

`src/crew/helm.gd`:
```gdscript
class_name Helm
extends Node
## The helm station (spec §3.4). Whoever holds it steers: throttle and trim stay
## where they're set, and the rudder follows A and D and centres when let go. The
## autopilot holds the heading and altitude it was switched on at (A, D, climb and
## descend move those targets instead), so a solo player can leave the helm. An
## empty helm with the autopilot off leaves the controls alone.

var ship: Ship
var cell: Vector3i               ## Where the helm block is, in ship space.
var pilot: CrewMember = null     ## Who is at the helm, if anyone.
var throttle_input := 0.0        ## -1 to 1: S to W, held this tick.
var rudder_input := 0.0          ## -1 to 1: A to D.
var climb_input := 0.0           ## -1 to 1: descend to climb.
var autopilot := false
var target_heading := 0.0
var target_altitude := 0.0


func _init(helm_ship: Ship, helm_cell: Vector3i) -> void:
	ship = helm_ship
	cell = helm_cell


## Puts crew at the helm. Returns false when someone else has it.
func take(crew: CrewMember) -> bool:
	if pilot != null:
		return false
	pilot = crew
	crew.station = self
	return true


## Lets go of the helm. The rudder centres; throttle and trim stay as they are.
func leave(crew: CrewMember) -> void:
	if pilot != crew:
		return
	pilot = null
	crew.station = null
	throttle_input = 0.0
	rudder_input = 0.0
	climb_input = 0.0
	if not autopilot:
		ship.rudder = 0.0


## Switches the autopilot on, holding the present heading and altitude, or off.
func set_autopilot(on: bool) -> void:
	autopilot = on
	target_heading = ship.heading()
	target_altitude = ship.global_position.y


func _physics_process(delta: float) -> void:
	if pilot == null and not autopilot:
		return
	ship.throttle = clampf(ship.throttle + throttle_input * Tuning.THROTTLE_RATE * delta, Tuning.THROTTLE_MIN, 1.0)
	if not autopilot:
		ship.rudder = rudder_input
		ship.trim = clampf(ship.trim + climb_input * Tuning.TRIM_RATE * delta, Tuning.TRIM_MIN, Tuning.TRIM_MAX)
		return
	target_heading = wrapf(target_heading - rudder_input * Tuning.AUTOPILOT_TURN_RATE * delta, -PI, PI)
	target_altitude += climb_input * Tuning.AUTOPILOT_CLIMB_RATE * delta
	# Heading is counter-clockwise, and a positive rudder turns clockwise.
	var off_course := wrapf(target_heading - ship.heading(), -PI, PI)
	ship.rudder = clampf(-Tuning.AUTOPILOT_HEADING_GAIN * off_course + Tuning.AUTOPILOT_YAW_DAMPING * ship.angular_velocity.y, -1.0, 1.0)
	var off_altitude := target_altitude - ship.global_position.y
	ship.trim = clampf(ship.trim_to_float_at(target_altitude) + Tuning.AUTOPILOT_ALTITUDE_GAIN * off_altitude \
			- Tuning.AUTOPILOT_CLIMB_DAMPING * ship.linear_velocity.y, Tuning.TRIM_MIN, Tuning.TRIM_MAX)
```

In `src/ship/ship.gd`, add the field after `var interior`:
```gdscript
var helm: Helm              ## The ship's first helm, or null.
```
at the end of `_ready()`:
```gdscript
	var helms := grid.cells_of("helm")
	if not helms.is_empty():
		helm = Helm.new(self, helms[0])
		add_child(helm)
```
and after `_ready()`:
```gdscript


## Where crew come aboard, in ship space: standing just aft of the helm.
func crew_spawn() -> Vector3:
	return Vector3(helm.cell) + Vector3(0.0, 0.45, 1.0)
```

- [ ] **Step 4: Run the tests**

Run: `godot --headless --import >/dev/null 2>&1; ./run_tests.sh`
Expected: `78 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src/crew/helm.gd src/ship tests/test_helm.gd src/crew/*.uid tests/*.uid
git commit -m "Add the helm with throttle, rudder, trim and an autopilot"
```

---

### Task 7: First-person controls, stations and the chase camera

Build-log items: the controls half of "First-person crew: walk, jump, climb ladders, use stations", and "Chase camera at the helm".

**Files:**
- Create: `src/crew/player_controller.gd`, `tests/test_player.gd`
- Modify: `project.godot`, `tests/test_project.gd`

**Interfaces:**
- Consumes: `CrewMember`, `Ship`, `Helm`, `Settings.mouse_sensitivity`.
- Produces: `PlayerController.new(crew)`, a `Node3D` in the main world, with:
  - `camera`, `crew`, `ship`
  - `chase: bool`, `enabled: bool`
  - `prompt() -> String` ("Take the helm", "Leave the helm" or "")

- [ ] **Step 1: Write the failing tests**

`tests/test_player.gd`:
```gdscript
extends TestCase
## The local player's keys: E takes and leaves the helm, V switches to the chase
## view there, H switches the autopilot, and the movement keys steer.

var player: PlayerController


func _ready() -> void:
	var ship := Ship.new(StarterShip.build())
	ship.calm = true
	ship.position = Vector3(0, 877, 7000)
	add_child(ship)
	var crew := CrewMember.new(ship, ship.crew_spawn())
	ship.interior.add_child(crew)
	player = PlayerController.new(crew)
	add_child(player)


func after_each() -> void:
	for action in ["move_forward", "move_right", "jump"]:
		Input.action_release(action)


func press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	player._unhandled_input(event)


func test_e_takes_the_helm_in_reach_and_lets_go_again() -> void:
	assert_eq(player.prompt(), "Take the helm")
	press("interact")
	assert_eq(player.crew.station, player.ship.helm)
	assert_eq(player.prompt(), "Leave the helm")
	press("toggle_camera")
	assert_true(player.chase)
	press("interact")
	assert_eq(player.crew.station, null)
	assert_false(player.chase, "leaving the helm ends the chase view")


func test_e_does_nothing_out_of_reach() -> void:
	player.crew.position = Vector3(0, 1.45, -4)  # down on the main deck
	assert_eq(player.prompt(), "")
	press("interact")
	assert_eq(player.crew.station, null)


func test_the_chase_view_and_autopilot_are_only_at_the_helm() -> void:
	press("toggle_camera")
	press("autopilot")
	assert_false(player.chase)
	assert_false(player.ship.helm.autopilot)
	press("interact")
	press("autopilot")
	assert_true(player.ship.helm.autopilot)
	press("autopilot")
	assert_false(player.ship.helm.autopilot)


func test_movement_keys_steer_from_the_helm() -> void:
	press("interact")
	Input.action_press("move_forward")
	Input.action_press("move_right")
	Input.action_press("jump")
	await simulate(1.0)
	assert_near(player.ship.throttle, Tuning.THROTTLE_RATE, 0.02, "W opens the throttle")
	assert_eq(player.ship.rudder, 1.0, "D is starboard rudder")
	assert_near(player.ship.trim, 1.0 + Tuning.TRIM_RATE, 0.002, "Space climbs")
	assert_eq(player.crew.move, Vector2.ZERO, "and nobody walks off")


func test_controls_stop_while_a_menu_is_open() -> void:
	press("interact")
	Input.action_press("move_forward")
	player.enabled = false
	press("interact")
	press("toggle_camera")
	await simulate(0.5)
	assert_eq(player.crew.station, player.ship.helm, "E does nothing")
	assert_false(player.chase, "nor V")
	assert_eq(player.ship.throttle, 0.0, "and held keys don't steer")
```

In `tests/test_project.gd`, add to the expected keys:
```gdscript
		"toggle_camera": [KEY_V],
		"autopilot": [KEY_H],
```

- [ ] **Step 2: Run them to see them fail**

Run: `./run_tests.sh player; ./run_tests.sh project`
Expected: `test_player.gd` could not load, and "autopilot exists" fails.

- [ ] **Step 3: Add the autopilot key and write the controller**

In `project.godot`, under `[input]` before `pause={`:
```ini
autopilot={
"deadzone": 0.2,
"events": [Object(InputEventKey,"device":-1,"physical_keycode":72)]
}
```

`src/crew/player_controller.gd`:
```gdscript
class_name PlayerController
extends Node3D
## The local player's eyes and hands. It reads the keyboard and mouse, walks their
## crew member or steers from the helm, and places the camera: first person, or a
## chase view behind the ship while at the helm (spec §3.4).

const MOUSE_TURN := 0.0025     ## Radians per pixel of mouse movement at sensitivity 1.
const REACH := 1.8             ## Metres from a helm's block that you can use it from.
const CHASE_DISTANCE := 40.0   ## Metres from the chase camera to the ship.

var crew: CrewMember
var ship: Ship
var camera: Camera3D
var chase := false             ## The chase view is showing.
var enabled := true            ## Off while a menu is open: keys and mouse do nothing.
var look_pitch := 0.0          ## Radians; positive looks up.

var _avatar: MeshInstance3D
var _chase_yaw := 0.0
var _chase_pitch := -0.3


func _init(player_crew: CrewMember) -> void:
	crew = player_crew
	ship = crew.ship


func _ready() -> void:
	camera = Camera3D.new()
	camera.far = 8000.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	camera.make_current()
	var body := CapsuleMesh.new()
	body.radius = CrewMember.RADIUS
	body.height = CrewMember.HEIGHT
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color("2f4f6f")
	_avatar = MeshInstance3D.new()
	_avatar.mesh = body
	_avatar.material_override = cloth
	_avatar.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_avatar)


## What E does right now, for the HUD, or "" when it does nothing.
func prompt() -> String:
	if crew.station != null:
		return "Leave the helm"
	if _helm_in_reach():
		return "Take the helm"
	return ""


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var turn: Vector2 = (event as InputEventMouseMotion).relative * MOUSE_TURN * Settings.mouse_sensitivity
		if chase:
			_chase_yaw = wrapf(_chase_yaw - turn.x, -PI, PI)
			_chase_pitch = clampf(_chase_pitch - turn.y, -1.3, 0.2)
		else:
			crew.look_yaw = wrapf(crew.look_yaw - turn.x, -PI, PI)
			look_pitch = clampf(look_pitch - turn.y, -1.5, 1.5)
	elif event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("toggle_camera") and crew.station != null:
		chase = not chase
	elif event.is_action_pressed("autopilot") and crew.station != null:
		ship.helm.set_autopilot(not ship.helm.autopilot)


func _physics_process(_delta: float) -> void:
	var keys := 1.0 if enabled else 0.0
	if crew.station != null:
		ship.helm.throttle_input = Input.get_axis("move_back", "move_forward") * keys
		ship.helm.rudder_input = Input.get_axis("move_left", "move_right") * keys
		ship.helm.climb_input = Input.get_axis("descend", "jump") * keys
		return
	crew.move = Input.get_vector("move_left", "move_right", "move_forward", "move_back") * keys
	crew.sprint = Input.is_action_pressed("sprint")
	crew.jump = Input.is_action_just_pressed("jump") and enabled
	# On a ladder, forward and jump climb and descend goes down.
	crew.climb = clampf(Input.get_axis("descend", "jump") * keys + maxf(0.0, -crew.move.y), -1.0, 1.0)


func _process(_delta: float) -> void:
	var ship_place := ship.get_global_transform_interpolated()
	var body := crew.get_global_transform_interpolated().origin
	_avatar.global_transform = ship_place * Transform3D(Basis(Vector3.UP, crew.look_yaw), body)
	_avatar.visible = chase
	if chase:
		var center := ship_place * ship.center_of_mass
		var bow := -ship_place.basis.z
		var yaw := atan2(-bow.x, -bow.z) + _chase_yaw
		var offset := Basis.from_euler(Vector3(_chase_pitch, yaw, 0.0)) * Vector3(0.0, 0.0, CHASE_DISTANCE)
		camera.global_transform = Transform3D(Basis.IDENTITY, center + offset).looking_at(center)
	else:
		var eye := Transform3D(Basis.from_euler(Vector3(look_pitch, crew.look_yaw, 0.0)), body + Vector3(0.0, CrewMember.EYE_HEIGHT, 0.0))
		camera.global_transform = ship_place * eye


func _interact() -> void:
	if crew.station != null:
		ship.helm.leave(crew)
		chase = false
	elif _helm_in_reach():
		ship.helm.take(crew)


func _helm_in_reach() -> bool:
	return ship.helm != null and crew.position.distance_to(Vector3(ship.helm.cell)) <= REACH
```

- [ ] **Step 4: Run the tests**

Run: `godot --headless --import >/dev/null 2>&1; ./run_tests.sh`
Expected: `83 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src/crew/player_controller.gd project.godot tests/test_player.gd tests/test_project.gd src/crew/*.uid tests/*.uid
git commit -m "Add first-person controls, the helm station and the chase camera"
```

---

### Task 8: Sky, day and night, and the Roil

Build-log item: "Sky, sun, day–night cycle, and the Roil storm below 200 m".

**Files:**
- Create: `src/world/world_sky.gd`, `src/world/roil.gd`, `tests/test_sky.gd`

**Interfaces:**
- Produces:
  - `WorldSky` (Node3D), with `hour: float`, `DAY_LENGTH` and `static sun_elevation(hour) -> float` (degrees).
  - `Roil` (Node3D).

- [ ] **Step 1: Write the failing tests**

`tests/test_sky.gd`:
```gdscript
extends TestCase
## The day–night sky and the Roil (spec §3.1, §4.8).


func test_the_sun_rises_at_six_and_sets_at_eighteen() -> void:
	assert_near(WorldSky.sun_elevation(6.0), 0.0, 1e-4)
	assert_near(WorldSky.sun_elevation(12.0), 70.0, 1e-4)
	assert_near(WorldSky.sun_elevation(18.0), 0.0, 1e-4)
	assert_near(WorldSky.sun_elevation(0.0), -70.0, 1e-4)


func test_the_sky_and_the_roil_run_through_a_day() -> void:
	var sky := WorldSky.new()
	add_child(sky)
	add_child(Roil.new())
	for hour in [0.0, 6.0, 12.0, 18.0, 23.9]:
		sky.hour = hour
		await get_tree().process_frame
	assert_true(sky.hour >= 23.9, "the day moves on")
```

- [ ] **Step 2: Run them to see them fail**

Run: `./run_tests.sh sky`
Expected: FAIL, could not load.

- [ ] **Step 3: Write the sky and the Roil**

`src/world/world_sky.gd`. Depth fog starts 1.5 km out, so the Roil below stays dark and only the distance hazes:
```gdscript
class_name WorldSky
extends Node3D
## The sky over the world (spec §3.1, §4.8): a sun and a moon crossing it once a
## day, sky colours that follow the sun, and haze toward the horizon.

const DAY_LENGTH := 1200.0  ## Real seconds in a whole day.

const DAY_TOP := Color("2f63a8")
const DAY_HORIZON := Color("b7d0ea")
const DUSK_HORIZON := Color("e7a974")
const NIGHT_TOP := Color("04070f")
const NIGHT_HORIZON := Color("16203a")

var hour := 10.0  ## Time of day, 0 to 24.

var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _sky: ProceduralSkyMaterial
var _environment: Environment


## The sun's height above the horizon in degrees at a time of day: it rises at 6,
## is highest at noon and sets at 18.
static func sun_elevation(at_hour: float) -> float:
	return 70.0 * sin((at_hour - 6.0) / 24.0 * TAU)


func _ready() -> void:
	_sky = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = _sky
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	_environment.glow_enabled = true
	_environment.fog_enabled = true
	_environment.fog_mode = Environment.FOG_MODE_DEPTH
	_environment.fog_depth_begin = 1500.0
	_environment.fog_depth_end = 14000.0
	_environment.fog_sky_affect = 0.0
	var world_environment := WorldEnvironment.new()
	world_environment.environment = _environment
	add_child(world_environment)

	_sun = DirectionalLight3D.new()
	_sun.light_color = Color("fff1dc")
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_max_distance = 300.0
	add_child(_sun)
	_moon = DirectionalLight3D.new()
	_moon.light_color = Color("9fb4e0")
	_moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	_moon.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	add_child(_moon)
	_apply()


func _process(delta: float) -> void:
	hour = fmod(hour + delta * 24.0 / DAY_LENGTH, 24.0)
	_apply()


func _apply() -> void:
	var elevation := sun_elevation(hour)
	# The sun rises in the east (+X), passes south (+Z) and sets in the west.
	_sun.rotation_degrees = Vector3(-elevation, 90.0 - 15.0 * (hour - 6.0), 0.0)
	var day := smoothstep(-8.0, 12.0, elevation)
	var glow := clampf(1.0 - absf(elevation - 2.0) / 14.0, 0.0, 1.0)
	_sun.light_energy = 1.4 * day
	_sun.shadow_enabled = elevation > 0.0
	_moon.light_energy = 0.4 * (1.0 - day)
	_sky.sky_top_color = NIGHT_TOP.lerp(DAY_TOP, day)
	_sky.sky_horizon_color = NIGHT_HORIZON.lerp(DAY_HORIZON, day).lerp(DUSK_HORIZON, glow * 0.6)
	_sky.ground_horizon_color = _sky.sky_horizon_color
	_sky.ground_bottom_color = _sky.sky_horizon_color
	_environment.fog_light_color = _sky.sky_horizon_color
```

`src/world/roil.gd`:
```gdscript
class_name Roil
extends Node3D
## The Roil: the storm sea under the islands, its top at 200 m (spec §3.1, §4.7).
## A dark, churning surface that follows the camera so it never ends, with
## lightning flashing underneath.

const SIZE := 60000.0  ## m across the drawn surface, so its edge hides in the haze.

const SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform float flash = 0.0;
varying vec3 world_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float clouds(vec2 p) {
	float sum = 0.0;
	float weight = 0.5;
	for (int i = 0; i < 5; i++) {
		sum += weight * noise(p);
		p *= 2.03;
		weight *= 0.5;
	}
	return sum;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz * 0.004;
	float churn = 0.6 * clouds(p + vec2(TIME * 0.02, TIME * 0.013)) + 0.4 * clouds(p * 2.7 - vec2(TIME * 0.035, 0.0));
	ALBEDO = mix(vec3(0.02, 0.018, 0.035), vec3(0.2, 0.17, 0.26), churn * churn);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = vec3(0.55, 0.6, 1.0) * flash * churn * 2.0;
}
"""

var _surface: MeshInstance3D
var _material: ShaderMaterial
var _lightning: OmniLight3D
var _next_flash := 3.0
var _flash_left := 0.0
var _random := RandomNumberGenerator.new()


func _ready() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	var shader := Shader.new()
	shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_surface = MeshInstance3D.new()
	_surface.mesh = plane
	_surface.material_override = _material
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_surface.position.y = Tuning.ROIL_ALTITUDE
	_surface.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_surface)
	_lightning = OmniLight3D.new()
	_lightning.light_color = Color("c7d4ff")
	_lightning.omni_range = 900.0
	_lightning.light_energy = 0.0
	_lightning.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_lightning)


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var at := camera.global_position
		_surface.global_position = Vector3(at.x, Tuning.ROIL_ALTITUDE, at.z)
	_next_flash -= delta
	if _next_flash <= 0.0:
		_next_flash = _random.randf_range(2.0, 9.0)
		_flash_left = _random.randf_range(0.08, 0.25)
		var around := _surface.global_position
		_lightning.global_position = around + Vector3(_random.randf_range(-700.0, 700.0), -60.0, _random.randf_range(-700.0, 700.0))
	_flash_left -= delta
	var flash := 1.0 if _flash_left > 0.0 and _random.randf() > 0.3 else 0.0
	_lightning.light_energy = 8.0 * flash
	_material.set_shader_parameter("flash", flash)
```

- [ ] **Step 4: Run the tests**

Run: `godot --headless --import >/dev/null 2>&1; ./run_tests.sh`
Expected: `85 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src/world tests/test_sky.gd tests/test_sky.gd.uid
git commit -m "Add a day-night sky and the Roil storm below 200 m"
```

---

### Task 9: The world: islands, the starter ship, the HUD and `--solo`

Build-log item: "A few placeholder islands to fly between", plus putting it all together.

**Files:**
- Create: `src/world/island.gd`, `src/ui/hud.gd`, `tests/test_world.gd`
- Modify: `src/world/sky_backdrop.gd`, `src/world/world.gd`, `src/core/launch_options.gd`, `src/core/game.gd`, `tests/test_launch_options.gd`

**Interfaces:**
- Consumes: everything above.
- Produces:
  - `Island.create(at: Vector3, radius: float) -> StaticBody3D`
  - `Hud.new(player)`, with `show_message(text)` and `static readout(ship) -> String`
  - The world scene's `START`, `ship`, `player` and `hud`
  - Launch option `--solo`

- [ ] **Step 1: Write the failing tests**

`tests/test_world.gd`:
```gdscript
extends TestCase
## The world scene: the starter ship with you aboard, islands to fly between, the
## sky's day, and the helm's instruments.


func test_you_start_aboard_the_starter_ship_by_the_helm() -> void:
	var world: Node3D = (load("res://src/world/world.tscn") as PackedScene).instantiate()
	add_child(world)
	await get_tree().process_frame
	var ship: Ship = world.ship
	var player: PlayerController = world.player
	assert_eq(ship.global_position, world.START)
	assert_eq(player.crew.get_parent(), ship.interior)
	assert_eq(player.prompt(), "Take the helm")
	assert_true(player.camera.is_current())
	world.queue_free()
	await get_tree().process_frame


func test_islands_are_solid() -> void:
	var island := Island.create(Vector3(0, 800, 0), 50.0)
	add_child(island)
	var shapes := island.find_children("*", "CollisionShape3D", false, false)
	assert_eq(shapes.size(), 2, "the rock and the grassy cap")
	for shape: CollisionShape3D in shapes:
		assert_true(shape.shape != null)


func test_ramming_an_island_is_survivable() -> void:
	add_child(Island.create(Vector3(0, 877, 6700), 60.0))
	var ship := Ship.new(StarterShip.build())
	ship.calm = true
	ship.position = Vector3(0, 877, 7000)
	ship.throttle = 1.0
	add_child(ship)
	var crew := CrewMember.new(ship, ship.crew_spawn())
	ship.interior.add_child(crew)
	var worst := [0.0]
	var standing := [0]
	await simulate(40.0, func(_tick: int) -> void:
		worst[0] = maxf(worst[0], ship.angular_velocity.length())
		if crew.is_on_floor():
			standing[0] += 1)
	assert_true(ship.global_position.z > 6700.0, "stopped by the island (at z %.0f)" % ship.global_position.z)
	assert_true(worst[0] < Ship.MAX_SPIN / 4.0, "no blow-up (spun at %.2f rad/s at most)" % worst[0])
	assert_true(standing[0] > 40 * 60 - 60, "the crew kept their feet (%d ticks)" % standing[0])


func test_the_helm_readout() -> void:
	var ship := Ship.new(StarterShip.build())
	ship.calm = true
	ship.position = Vector3(0, 877, 7000)
	add_child(ship)
	ship.throttle = 0.5
	ship.rudder = -0.4
	var text := Hud.readout(ship)
	assert_true(text.contains("50% ahead"), text)
	assert_true(text.contains("40% port"), text)
	assert_true(text.contains("Heading   000°"), text)
	assert_true(text.contains("Altitude   877 m"), text)
	assert_true(text.contains("Autopilot off"), text)
```

In `tests/test_launch_options.gd`, before `test_ignores_unknown_and_malformed_options`:
```gdscript
func test_reads_solo() -> void:
	assert_eq(LaunchOptions.parse(PackedStringArray(["--solo", "--name=Ann"])), {"solo": true, "name": "Ann"})


```

- [ ] **Step 2: Run them to see them fail**

Run: `./run_tests.sh world; ./run_tests.sh launch`
Expected: `test_world.gd` could not load, and `test_reads_solo` fails with "expected {"solo": true, …}".

- [ ] **Step 3: Write the islands, the HUD and the world, and add `--solo`**

`src/world/island.gd`. This is `SkyBackdrop._island`, with collision added:
```gdscript
class_name Island
## A placeholder floating island until the world stage generates real ones: a
## grassy cap on a tapering rock. Ships collide with it.


static func create(at: Vector3, radius: float) -> StaticBody3D:
	var island := StaticBody3D.new()
	island.position = at
	var rock_mesh := CylinderMesh.new()
	rock_mesh.top_radius = radius
	rock_mesh.bottom_radius = radius * 0.12
	rock_mesh.height = radius * 1.5
	rock_mesh.radial_segments = 9
	rock_mesh.rings = 1
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = radius * 1.02
	cap_mesh.bottom_radius = radius
	cap_mesh.height = radius * 0.12
	cap_mesh.radial_segments = 9
	for part: Array in [[rock_mesh, Color("5d4d47"), -radius * 0.75], [cap_mesh, Color("6e8d4c"), 0.0]]:
		var mesh: CylinderMesh = part[0]
		var material := StandardMaterial3D.new()
		material.albedo_color = part[1]
		material.roughness = 0.95
		var body := MeshInstance3D.new()
		body.mesh = mesh
		body.material_override = material
		body.position.y = part[2]
		island.add_child(body)
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_convex_shape()
		shape.position.y = part[2]
		island.add_child(shape)
	return island
```

`src/world/sky_backdrop.gd`. It uses `Island` now, and only the menus use the backdrop:
```gdscript
class_name SkyBackdrop
extends Node3D
## A slow drift through golden-hour sky above the storm, behind the menus.

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
		add_child(Island.create(spec[0], spec[1]))

	_camera = Camera3D.new()
	_camera.position = Vector3(0, 800, 0)
	_camera.far = 6000.0
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)
	_camera.make_current()


func _process(delta: float) -> void:
	_yaw += DRIFT * delta
	_camera.rotation = Vector3(deg_to_rad(-4.0), _yaw, 0.0)
```

`src/ui/hud.gd`. The session panel moves here from the stage 1 world:
```gdscript
class_name Hud
extends CanvasLayer
## Everything drawn over the world: the session and crew, a dot to aim with, what
## E does, the helm's instruments while you steer, and short messages.

const MESSAGE_TIME := 4.0  ## Seconds a message stays up.

var player: PlayerController

var _status: Label
var _crew: Label
var _prompt: Label
var _helm: PanelContainer
var _readout: Label
var _message: Label
var _message_left := 0.0


func _init(for_player: PlayerController) -> void:
	player = for_player


func _ready() -> void:
	var theme := UiTheme.build()
	var session := PanelContainer.new()
	session.theme = theme
	session.position = Vector2(32, 32)
	add_child(session)
	var column := VBoxContainer.new()
	session.add_child(column)
	_status = Label.new()
	column.add_child(_status)
	_crew = UiTheme.caption("")
	column.add_child(_crew)

	var dot := ColorRect.new()
	dot.color = Color(UiTheme.TEXT, 0.8)
	dot.size = Vector2(4, 4)
	dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dot)

	_prompt = Label.new()
	_prompt.theme = theme
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.offset_top = 40
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_prompt)

	_message = Label.new()
	_message.theme = theme
	_message.add_theme_color_override("font_color", UiTheme.ACCENT)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_message.offset_top = 120
	_message.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_message)

	_helm = PanelContainer.new()
	_helm.theme = theme
	_helm.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_helm.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_helm.offset_left = 32
	_helm.offset_bottom = -32
	add_child(_helm)
	var helm_column := VBoxContainer.new()
	_helm.add_child(helm_column)
	_readout = Label.new()
	_readout.add_theme_font_override("font", _monospace())
	helm_column.add_child(_readout)
	helm_column.add_child(UiTheme.caption("W/S throttle · A/D rudder · Space/Ctrl climb · H autopilot · V view · E leave"))

	Session.players_changed.connect(_refresh_session)
	player.crew.fell_overboard.connect(func() -> void: show_message("You fell overboard. Back aboard!"))
	_refresh_session()


func show_message(text: String) -> void:
	_message.text = text
	_message_left = MESSAGE_TIME


func _process(delta: float) -> void:
	var action := player.prompt()
	_prompt.text = "" if action.is_empty() else "E   " + action
	_message_left -= delta
	_message.visible = _message_left > 0.0
	_helm.visible = player.crew.station != null
	if _helm.visible:
		_readout.text = readout(player.ship)


## The helm's instruments as text.
static func readout(ship: Ship) -> String:
	var lines: PackedStringArray = []
	lines.append("Throttle  %s" % ("%3d%% ahead" % roundi(ship.throttle * 100.0) if ship.throttle >= 0.0 else "%3d%% astern" % roundi(-ship.throttle * 100.0)))
	lines.append("Rudder    %s" % ("centred" if absf(ship.rudder) < 0.05 else "%3d%% %s" % [roundi(absf(ship.rudder) * 100.0), "starboard" if ship.rudder > 0.0 else "port"]))
	lines.append("Trim      %.2f" % ship.trim)
	lines.append("Speed     %3d m/s" % roundi(ship.linear_velocity.length()))
	lines.append("Altitude  %4d m   %+.1f m/s" % [roundi(ship.global_position.y), ship.linear_velocity.y])
	lines.append("Heading   %03d°" % posmod(roundi(-rad_to_deg(ship.heading())), 360))
	if ship.helm.autopilot:
		lines.append("Autopilot %03d° at %d m" % [posmod(roundi(-rad_to_deg(ship.helm.target_heading)), 360), roundi(ship.helm.target_altitude)])
	else:
		lines.append("Autopilot off")
	return "\n".join(lines)


func _refresh_session() -> void:
	_status.text = _status_text()
	var names: PackedStringArray = []
	for id: int in Session.players:
		names.append(Session.players[id]["name"])
	_crew.text = "Crew (%d): %s" % [names.size(), ", ".join(names)]


func _status_text() -> String:
	if Session.mode == Session.Mode.SOLO:
		return "Solo game"
	if Session.mode == Session.Mode.HOST:
		var targets: PackedStringArray = []
		for address in Session.lan_addresses_by_interface(IP.get_local_interfaces()):
			targets.append("%s:%d" % [address, Session.port])
		if targets.is_empty():
			return "Hosting on port %d" % Session.port
		var text := "Hosting. Friends on your network join at " + targets[0]
		if targets.size() > 1:
			text += " (or " + ", ".join(targets.slice(1)) + ")"
		return text
	if Session.mode == Session.Mode.CLIENT:
		return "Connected to the host"
	return ""


static func _monospace() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["DejaVu Sans Mono", "Consolas", "Menlo", "monospace"])
	return font
```

`src/world/world.gd`:
```gdscript
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
```

`src/core/launch_options.gd`:
```gdscript
class_name LaunchOptions
## Reads the options passed after "--" on the command line:
##   --solo            start a solo game straight away
##   --host            start hosting straight away
##   --join=ADDRESS    join ADDRESS (host, host:port or [ipv6]:port) straight away
##   --name=NAME       play as NAME instead of the saved name
##   --port=PORT       host on PORT instead of 24650
## Unknown or malformed options are ignored.


static func parse(args: PackedStringArray) -> Dictionary:
	var options := {}
	for arg in args:
		if arg == "--solo":
			options["solo"] = true
		elif arg == "--host":
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

In `src/core/game.gd`, `_apply_launch_options` starts solo first:
```gdscript
	var player_name: String = options.get("name", Settings.player_name)
	if options.has("solo"):
		Session.start_solo(player_name)
	elif options.has("host"):
```

- [ ] **Step 4: Run the tests**

Run: `godot --headless --import >/dev/null 2>&1; ./run_tests.sh`
Expected: `90 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src tests
git commit -m "Build the stage 2 world: islands, the starter ship, the HUD and --solo"
```

---

### Task 10: README, spec and end-to-end checks

**Files:**
- Modify: `README.md`, `docs/superpowers/specs/2026-09-29-skywright-design.md`

- [ ] **Step 1: Update the README**

`README.md`:
````markdown
# Skywright

An airship game: design ships block by block, and real physics decides whether they fly. Crew them with friends, explore a generated sky of floating islands above an endless storm, and push toward the Eye.

Built with Godot 4.7.2. The design is in [`docs/superpowers/specs/2026-09-29-skywright-design.md`](docs/superpowers/specs/2026-09-29-skywright-design.md), and each stage's plan is in `docs/superpowers/plans/`.

## Status

**Stage 2 of 10 (First flight).** You can:
- walk the deck of the starter ship while it rolls in the wind, and climb its ladders;
- take the helm and fly between floating islands, with an autopilot and a chase view;
- watch day turn to night over the Roil, the storm below 200 m;
- play solo, or host a game and join one on your network.

In this stage each player flies their own ship. Crewing one ship together arrives in stage 3.

## Controls

| Key | On deck | At the helm |
|---|---|---|
| W A S D | Walk | W/S throttle, A/D rudder |
| Space | Jump, or climb a ladder | Climb |
| Ctrl or C | Climb down a ladder | Descend |
| Shift | Sprint | |
| E | Take the helm | Leave the helm |
| H | | Autopilot on or off |
| V | | Chase view |
| Mouse | Look | Look, or orbit in the chase view |
| Esc | Menu | Menu |

On a ladder, W climbs too. Throttle and trim stay where you leave them. The autopilot holds the heading and height it was switched on at, and A, D, Space and Ctrl adjust those.

## Run it

Install Godot 4.7.2 (the standard build, not .NET), put it on your PATH as `godot`, then:

```bash
godot --path .                # play
godot --path . -- --solo      # straight into a solo game
godot --path . --editor       # open in the editor
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

Launch options (after `--`): `--solo`, `--host`, `--join=ADDRESS`, `--name=NAME`, `--port=PORT`.

## Test

```bash
./run_tests.sh           # every test, headless
./run_tests.sh session   # only test files whose name contains "session"
```

A test fails when an assert fails, or when the engine logs an error the test didn't expect. The runner uses `--fixed-fps 60`, so each frame is exactly one physics tick, and flight tests simulate minutes of flying in seconds.

## Layout

```
src/core/     Settings and Game autoloads, launch options
src/net/      Session autoload: solo, host, join, handshake
src/ship/     blocks and the tuning file, the ship grid, the starter ship, flight forces, the ship body and mesh
src/crew/     each ship's interior world, crew members, the helm, the player's controls and camera
src/ui/       menus, the HUD and the shared UI theme
src/world/    the world scene, sky, the Roil, islands, wind, the menu backdrop
tests/        test runner and tests
docs/         design spec and implementation plans
```

Every number that shapes how ships fly and handle is in `src/ship/tuning.gd`.

## Graphics on hybrid laptops

Godot picks a GPU at startup and prints it. On the development laptop it picks the discrete GPU: `Vulkan 1.4.354 - Forward+ - Using Device #1: NVIDIA - NVIDIA GeForce RTX 3050 6GB Laptop GPU (NVK GA107)`. To choose a different one, run it with `--verbose` to list the devices, then pass `--gpu-index N`. Index 0 is the integrated Radeon 680M.
````

- [ ] **Step 2: Run the whole suite twice**

Run: `./run_tests.sh; ./run_tests.sh; echo "exit=$?"`
Expected: `90 passed, 0 failed` both times, `exit=0`.

- [ ] **Step 3: Look at the game on the GPU**

Run (this opens a window for about 40 s; the movie writer is slow):
```bash
godot --path . --quit-after 120 --write-movie "${TMPDIR:-/tmp}/flight.png" -- --solo 2>&1 | grep -E "Using Device|ERROR"
```
Expected: one line naming the Vulkan device, and no `ERROR` lines. Open the last `flight*.png`. You should be standing on the helm deck, looking forward between the posts, under the envelope. The islands float over the dark, churning Roil, and "E  Take the helm" shows under the crosshair.

- [ ] **Step 4: Check the frame rate on both GPUs**

Run each for about 10 s and read the FPS from the window title or `--print-fps`:
```bash
godot --path . --print-fps -- --solo 2>&1 | grep -m 5 FPS
godot --path . --print-fps --gpu-index 0 -- --solo 2>&1 | grep -m 5 FPS
```
Expected: 60 fps or more with VSync on, on both the RTX 3050 and the Radeon 680M. Note the numbers in the playtest checklist.

- [ ] **Step 5: Bring the spec up to date**

In the spec:
- **§4.4 Forces:** add the keel push, the spin damping and the rudder's signed airflow.
- **§4.4:** say that propellers push toward the bow until blocks can turn, and that one engine drives two propellers.
- **§4.5:** add the stage 2 overboard rule.
- **§6:** say the runner uses `--fixed-fps 60`, with `simulate()`.
- **§9 Decisions:** add a row for the keel term and one for the starter ship's iron keel.

The table "Where this stage departs from the spec" above has the wording.

- [ ] **Step 6: Commit**

```bash
git add README.md docs/superpowers/specs/2026-09-29-skywright-design.md
git commit -m "Update README and spec for stage 2"
```

---

## Playtest checklist

These need a person, because they're about how it feels (spec §5: "A stage is finished when its tests pass and its playtest checklist is done"):

1. **Walking the deck in flight:** at cruise through gusts, does the ±2° roll feel alive without being sickening? Walk the main deck, sprint, and jump.
2. **Ladders:** climb both ladders up to the helm deck (W or Space) and back down (Ctrl). Is getting on and off at the top natural?
3. **Taking the helm:** press E at the helm. Fly to the nearest island and around it. Is turning (about 6°/s) too slow or too fast? Does losing speed in a hard turn feel right?
4. **Climbing and descending:** hold Space or Ctrl. Does the ship settle at a new height in a reasonable time?
5. **Autopilot:** press H, leave the helm with E, walk around, and come back. Did she hold course and height?
6. **Chase view:** press V. Is it smooth at the monitor's refresh rate? Does the mouse orbit feel right?
7. **Day and night:** a day is 20 minutes. Is the night too dark to walk the deck? Are the lightning flashes under the Roil visible?
8. **Collisions:** ram an island. Nothing should explode. Is it too bouncy?
9. **Overboard:** walk off the bow. Do you come back aboard at the helm with a message?
10. **Two copies:** host one and join with the other on this machine. Both worlds load, and each flies its own ship (sharing a ship is stage 3).
11. **Frame rate:** 60 fps at 1080p on the Radeon 680M (`--gpu-index 0`)?
