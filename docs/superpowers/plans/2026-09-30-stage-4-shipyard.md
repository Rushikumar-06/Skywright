# Stage 4: Shipyard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Design your own ship and find out whether it flies. At the dock you build a ship block by block in a 3D shipyard, with live stats, centre of mass and centre of lift markers, and warnings. You send it on a test flight and come back instantly, or launch it as your ship. You save, load and share blueprints as files. In co-op every player can launch a ship of their own.

**Architecture:**
- **Blocks face a way.** A block's `rotation` (0–23, already in the data) is Godot's orthogonal index, the one GridMap uses. `Blocks` holds the catalogue (names, groups, materials, what each block does) and the rotation maths: turn, tip and mirror. Propellers push and rudders steer along their facing.
- **Stats are maths, not flying.** `ShipStats.of(grid, altitude)` works out weight, lift, float height, ceiling, thrust, top speed, climb rate, the two centres, list and trim, and warnings, with the flight model's own formulas. Flight tests check that ships fly the way their stats say.
- **Designing is data.** `ShipDesign` edits a copy of a `ShipGrid`: place, remove, mirror mode, undo and redo. Aiming uses `ShipGrid.raycast`, a voxel walk along the ray, so the shipyard needs no physics.
- **The shipyard is its own little world.** `Shipyard` (a `CanvasLayer`) shows a `BuildView` (a `SubViewport` with its own 3D world: sky, light, slipway grid, the design, a ghost of the next block, and the two centres), plus panels: the block palette, paint, stats, warnings and blueprints. It only designs. It asks the `World` for test flights and launches.
- **Ships come and go mid-game.** The server spawns and removes ships while players are in the world, and tells everyone: `_ship_added` and `_ship_removed(id, successor)`. Blocks travel compressed. Every ship has a `captain` (a peer id, or 0) and a `test` flag. You board your own ship when it arrives. When the ship you're on goes away, you board its successor, or the ship you came from, or the host's ship.
- **Launches are the server's call.** A player asks to launch a design. The server builds it at that player's slipway at the dock (test flights a little further out), clear of other ships, with that player at the helm. A new ship replaces the player's old one and takes its crew. A test flight replaces the last test flight. B ends it. A leaver's ships go with them.

**Tech Stack:** Godot 4.7.2 (standard build, `~/.local/bin/godot`), statically typed GDScript, ENet through SceneMultiplayer, and the existing headless test runner.

**Spec:** `docs/superpowers/specs/2026-09-29-skywright-design.md` (stage 4 in §5; ships and building in §3.3 and §4.4; co-op in §3.8; networking in §4.6; blueprints in §4.10; errors in §7).

**Where:** branch `stage-4-shipyard`, in the worktree `../game-stage-4`, branched from `stage-3-online-co-op`.

## Global Constraints

- Godot 4.7.2 standard build, and GDScript with static types everywhere. No addons or other dependencies.
- Ships are built on a 1 m grid, with coordinates from −64 to 63 on every axis and at most 4,000 blocks. Every ship needs at least one helm (spec §3.3, §4.10).
- Every number that decides how ships fly stays in `src/ship/tuning.gd`. Block masses and hit points don't change in this stage.
- Blueprints: `user://blueprints/<name>.skyship.json`, stored as `{"format": "skywright-blueprint", "version": 1, "name", "blocks": [[x, y, z, type, rotation], …], "paint": {…}}` (spec §4.10). Other players' blueprints are untrusted input. An invalid blueprint is refused with the first problem found, and nothing is loaded (spec §7).
- The server is authoritative for ships. A client only asks: "launch this design", "end my test flight". Everything a peer receives from another machine is checked.
- Protocol version 3. Channel 0 is reliable for events, channel 1 unreliable-ordered for ship snapshots, channel 2 unreliable-ordered for crew and helm keys.
- Network budget: at most 64 KB/s down per client (spec §4.11). A ship's blocks travel compressed.
- Error messages follow spec §7 word for word where it gives them. New messages are the exact strings in this plan.
- Tests use ports 20000–29999. Tests that write files use a fresh folder under `user://` and delete it in `after_each`.
- Commit messages have no `Co-Authored-By` line or other trailers (user rule).

## Review Focus

1. **Blueprint files from other players** (broken JSON, truncated, huge, wrong types, fractional or enormous numbers such as `1e400`, a missing helm, bad paint): each is refused with the first problem, nothing is loaded, and the engine logs no errors. Tests: `test_bad_blueprints_are_refused_with_the_first_problem`, `test_a_huge_file_is_refused_before_it_is_read` (Task 3), `test_a_bad_blueprint_file_says_what_is_wrong` (Task 8).
2. **Coming back from a test flight whatever is happening** (far away, sinking into the Roil, at the helm with the autopilot on, B pressed twice, two test flights asked for at once): there's never more than one test ship. You're back aboard your ship, with the shipyard open and your design as you left it. Tests: `test_b_returns_from_a_test_flight_instantly`, `test_a_second_test_flight_replaces_the_first` (Task 7), `test_a_test_flight_and_back_keeps_the_design` (Task 8).
3. **The edges of the build area and mirror mode** (cells at −64 and 63, mirror partners outside the area, the 4,000-block limit, the keel line itself): no block is ever placed outside the area or over the limit, and nothing crashes. Tests: `test_mirror_skips_cells_outside_the_build_area`, `test_place_refuses_occupied_cells_the_edge_and_the_limit` (Task 4).
4. **Ships changing hands in co-op** (the host launches with a guest aboard; a guest leaves mid-test-flight; a modified client sends junk launch requests): crew always end up aboard a ship, a leaver's ships go, and junk is ignored. Tests: `test_the_crew_follow_the_host_to_a_new_ship`, `test_a_leaving_guests_ships_go_with_them`, `test_the_server_ignores_junk_launches` (Task 7).
5. **Losing work** (loading a blueprint over an unsaved design, saving over a blueprint with the same name, closing the shipyard): the design survives, loading can be undone, and replacing a file asks first. Tests: `test_loading_a_blueprint_can_be_undone` (Task 4), `test_saving_over_a_blueprint_asks_first`, `test_the_design_is_kept_between_visits` (Task 8).

---

## What prototyping settled before this plan

| Question | Answer |
|---|---|
| How do the 24 rotations map to bases? | `GridMap.get_basis_with_orthogonal_index(i)` gives 24 distinct proper rotations, and index 0 is the identity. A quarter turn about +Y is index 16. Mirroring across x (`M·B·M` with `M = diag(−1, 1, 1)`) maps the table onto itself: 0→0, 1→3, 16→22 and so on. Build the table once from a `GridMap` instance and free it. |
| Compression for ship data? | `decompress_dynamic` only supports gzip, deflate and Brotli, and **logs engine errors on junk**. `decompress(size, COMPRESSION_ZSTD)` with the size known returns an empty array for junk or a size that's too small, **with no error logged**. For a size that's too large it returns the real size. So send the block count, decompress to `count × 7` bytes, and check the length. |
| What does JSON give for numbers? | Every number is a `float` (`[1]` → `1.0`). `1e400` parses as `inf`. `JSON.new().parse(text)` returns an error code **without logging**. So blueprints accept whole-number floats and refuse the rest. |
| Can the shipyard aim headless? | Yes. `Camera3D.project_ray_origin/normal` work in a headless `SubViewport` with `own_world_3d`. |
| How big are ships on the wire? | The stage 3 format (`var_to_bytes` of `[x, y, z, type, rotation, hp]` arrays) is 256 KB for 4,000 blocks, four seconds of a client's budget. At 7 bytes a block plus zstd it's a few KB. |
| How long does a big ship take to build? | `ShipMesh.build` takes about 14 ms for 4,000 blocks, and mass properties plus drag zones about 8 ms. Rebuilding the whole design after each edit is fine. |
| Other APIs | `String.validate_filename()` turns `Storm/chaser: v2?` into `Storm_chaser_ v2_`. `Color.html_is_valid("c0392b")` is true. `SurfaceTool.set_smooth_group` exists. `SurfaceTool.commit(mesh)` appends a surface to an existing `ArrayMesh`. `GeometryInstance3D.transparency` and `Viewport.disable_3d` exist. `DirAccess.dir_exists_absolute` is silent for a missing folder. |

## Where this stage departs from the spec

The spec is updated to match in Task 9.

| Spec | This stage | Why |
|---|---|---|
| §3.2: "Build a ship at a shipyard" in towns | One placeholder dock at the start, with a slipway for each player. The shipyard opens within 150 m of it. | Towns arrive in stage 5. |
| §3.8: friends "crew the host's ship or fly their own alongside it" | Each player can have one ship and one test flight at a time. A leaver's ships go with them. | That's the simplest rule where nobody is ever left aboard nothing. Saving ships comes with saves (stage 7). |
| §4.4: "one mesh per ship per material, built in 16³ sections" | One mesh per ship, with one surface per material. No sections. | Sections pay off when damage rebuilds the mesh on every hit (stage 6). |
| §4.4: collision | Shaped blocks (propeller, rudder, sail, cannon, helm) are drawn as shapes but still collide and drag as full cubes. | Crew can't walk into them anyway, and flight is unchanged. |
| §3.3: sails, "6 m² of wind area" | Sails are drawn as canvas but fly as cubes. | Wind on sails is stage 5 (Build Log s05-04). |
| §4.10: `"paint": {…}` | `paint` maps a block type to a hex colour, and every block of that type takes it. | Painting single blocks can come later. |
| §3.6: ships cost money | Building, testing and launching are free, and the server trusts a client to be at the dock when it launches. | The economy is stage 7. Check the dock on the server when launching costs money. |
| (not in the spec) | Paint changes can't be undone. | Only block edits and loads can; paint is one click to change back. |

## Protocol (version 3)

| RPC | Direction | Channel | Payload | Receiver checks |
|---|---|---|---|---|
| `_world` | server → client | 0 reliable | `time`, `[entry, …]` | each entry as below; every ship is added before `ship_added` fires for any |
| `_ship_added` | server → clients | 0 reliable | `time`, `entry` | only the server can call it; entry as below |
| `_ship_removed` | server → clients | 0 reliable | `id`, `successor id` (0 for none) | only the server can call it; ints; unknown ids are ignored |
| `_launch` | client → server | 0 reliable | `blocks` (bytes), `paint`, `test` | sender in the world; at most one launch a second; `ShipGrid.from_bytes` and `read_paint` succeed; `test` is a bool |
| `_end_test` | client → server | 0 reliable | — | sender in the world |

An **entry** is `[id, blocks, paint, transform, pilot, captain, test]`:
- `blocks` is `ShipGrid.to_bytes()`.
- `paint` is `{type: "rrggbb"}`.
- `transform` must be finite. `pilot` and `captain` are ints, and `test` is a bool.

All other RPCs are unchanged from stage 3.

**Block bytes:** bytes 0–1 hold the block count (`encode_u16`). The rest is the zstd-compressed body: 7 bytes per block, which are `x + 64`, `y + 64`, `z + 64`, the type's index in `Tuning.BLOCKS`' key order, the rotation, and the hit points as `u16`. Changing the order of `Tuning.BLOCKS` changes the protocol, so it needs a new protocol version.

---

## File structure

| File | Responsibility |
|---|---|
| `src/ship/blocks.gd` | `Blocks`: catalogue info for the palette, materials, shaped blocks, and the 24 rotations (turn, tip, mirror) |
| `src/ship/ship_forces.gd` | Adds `propeller_power(grid)` and `forward_thrust(grid)` |
| `src/ship/ship.gd` | Propellers and rudders act along their facing; `captain` and `test` |
| `src/ship/ship_stats.gd` | `ShipStats`: readouts, the two centres, list and trim, and warnings |
| `src/ship/ship_grid.gd` | `paint`, `copy()`, `read_blocks()` with messages, `to_bytes()` / `from_bytes()`, paint checks, `in_area()`, `raycast()` |
| `src/ship/blueprint.gd` | `Blueprint`: blueprint files and their names, reading them safely |
| `src/ship/ship_mesh.gd` | One surface per material, shaped and turned blocks, a cloth envelope, paint |
| `src/builder/ship_design.gd` | `ShipDesign`: edits, mirror mode, undo and redo |
| `src/builder/build_view.gd` | `BuildView`: the shipyard's 3D view, camera and aiming |
| `src/builder/shipyard.gd` | `Shipyard`: panels, keys and mouse, blueprints, asking for flights |
| `src/world/dock.gd` | `Dock`: the quay, the slipways and test berths, and how near counts as at the dock |
| `src/net/world_sync.gd` | Ships added and removed mid-game, compressed entries, launches, test flights, leavers' ships |
| `src/net/session.gd` | `PROTOCOL_VERSION := 3` |
| `src/world/world.gd` | The dock; boarding; test flights and launches; opening and closing the shipyard; B and Esc |
| `src/crew/player_controller.gd` | `board(crew)`; `fell_overboard` passed on |
| `src/ship/ship.gd` (`crew_spawn`) | Spots in front of the helm too |
| `src/ui/hud.gd` | The test flight banner; the "B   Shipyard" hint at the dock |
| `src/core/settings.gd` | `clean_name(raw, max_length, fallback)` |
| `project.godot` | Actions: `shipyard` B, `turn_block` R, `tip_block` T, `mirror` M, `undo` Ctrl+Z, `redo` Ctrl+Y and Ctrl+Shift+Z, `test_flight` F |
| `tests/net_case.gd` | `sail_together()` moved here from `test_world_sync.gd` |
| `tests/test_blocks.gd`, `test_ship_stats.gd`, `test_blueprint.gd`, `test_ship_design.gd`, `test_ship_mesh.gd`, `test_fleet.gd`, `test_launch.gd`, `test_shipyard.gd`, `test_designed_ship.gd` | New tests |
| `README.md`, spec | Stage 4 status, the shipyard, blueprints, ships of your own |

---

### Task 1: Block catalogue and facing

Build-log item: "Block catalogue: hull, deck, frames, balloons, lift stones, engines, propellers, rudders, sails, cannons, cargo bays, bunks, ladders".

**Files:**
- Create: `src/ship/blocks.gd`, `tests/test_blocks.gd`
- Modify: `src/ship/ship_forces.gd`, `src/ship/ship.gd`
- Test: `tests/test_blocks.gd`, `tests/test_ship.gd`

**Interfaces:**
- Produces:
  - `Blocks.INFO`: type -> `{"name", "group", "material", "about"}`, with an entry for every `Tuning.BLOCKS` type in palette order.
  - `Blocks.GROUPS := ["Hull", "Lift", "Power", "Control", "Crew and cargo", "Weapons"]`
  - `Blocks.MATERIALS := ["wood", "metal", "cloth", "stone"]`
  - `Blocks.SHAPED := ["propeller", "rudder", "sail", "cannon", "helm", "ladder"]`
  - Static functions:
    - `basis(rotation: int) -> Basis`
    - `rotation_of(b: Basis) -> int` (−1 when it isn't one of the 24)
    - `facing(rotation: int) -> Vector3` (`basis(r) * Vector3.FORWARD`)
    - `turned(rotation: int) -> int`: a quarter turn clockwise seen from above, so the side that faced the bow faces starboard.
    - `tipped(rotation: int) -> int`: a quarter turn forward, so the side that faced the bow faces down.
    - `mirrored(rotation: int) -> int`: reflected across the keel line.
    - `is_cube(type: String) -> bool`
  - `ShipForces.propeller_power(grid: ShipGrid) -> float`: each propeller's share of full thrust, `min(1, engines × 2 / propellers)`, or 0 with no propellers.
  - `ShipForces.forward_thrust(grid: ShipGrid) -> float`: the sum of `power × PROPELLER_THRUST × facing(rotation).dot(Vector3.FORWARD)`. It's negative when propellers push astern.
  - `Ship.max_thrust()` returns `ShipForces.forward_thrust(grid)`.

Catalogue text (players read it in the shipyard):

| type | name | group | material | about |
|---|---|---|---|---|
| frame | Frame | Hull | wood | Wooden framing: the bones of a ship. |
| deck | Deck plank | Hull | wood | A floor to walk on. |
| iron | Iron plate | Hull | metal | Heavy armour, and good ballast low in the keel. |
| alloy | Alloy plate | Hull | metal | Armour at two-thirds the weight of iron. |
| balloon | Balloon cell | Lift | cloth | 900 N of lift in dense air, and less as the air thins higher up. |
| lift_stone | Lift stone | Lift | stone | 6,000 N of lift at any height. Heavy. |
| engine | Engine | Power | metal | Drives two propellers at full power. |
| propeller | Propeller | Power | wood | Up to 2,500 N of thrust, the way it faces. |
| fuel_tank | Fuel tank | Power | metal | Holds fuel for the engines. |
| helm | Helm | Control | wood | Where the pilot steers. Every ship needs one. |
| rudder | Rudder | Control | wood | Pushes sideways on its flat side as air flows past, which turns the ship. |
| sail | Sail | Control | cloth | Canvas to catch the wind. |
| ladder | Ladder | Crew and cargo | wood | Climb it with W or Space. |
| bunk | Bunk | Crew and cargo | wood | A berth for one of the crew. |
| cargo_bay | Cargo bay | Crew and cargo | wood | Stows crates. |
| ballast_tank | Ballast tank | Crew and cargo | metal | Water to drop in an emergency. |
| cannon | Cannon | Weapons | metal | Fires the way it faces. |

The rotation table, built once:

```gdscript
static var _bases: Array[Basis] = []

static func _table() -> Array[Basis]:
	if _bases.is_empty():
		var map := GridMap.new()  # Godot's orthogonal index: the table GridMap files use
		for i in 24:
			_bases.append(map.get_basis_with_orthogonal_index(i))
		map.free()
	return _bases
```

- `rotation_of` searches the table with `is_equal_approx`.
- `turned(r) = rotation_of(Basis(Vector3.UP, -PI / 2) * basis(r))`
- `tipped(r) = rotation_of(Basis(Vector3.RIGHT, -PI / 2) * basis(r))`
- `mirrored(r) = rotation_of(m * basis(r) * m)`, with `m = Basis.from_scale(Vector3(-1, 1, 1))`

What facing means for each block type:
- **Propeller:** pushes along `facing(rotation)`. Rotation 0 pushes toward the bow, as every propeller did in stage 2.
- **Rudder:** its flat side's normal is its local +X and air flows along its local −Z. In ship space, `side = basis(r) * Vector3.RIGHT` and `chord = basis(r) * Vector3.FORWARD`.
  - `flow = (ship_basis * chord).dot(point_velocity − wind)`
  - `push = RUDDER_FORCE × ρ × flow × |flow| × rudder`, and the force is `−(ship_basis * side) × push`.
  - At rotation 0 this is exactly the stage 2 formula.

- [ ] **Step 1: Write the failing tests** (`tests/test_blocks.gd`):
  - `test_every_block_is_in_the_catalogue`: every `Tuning.BLOCKS` key has `INFO` with a non-empty name and about, a group in `GROUPS` and a material in `MATERIALS`, and a colour in `ShipMesh.COLORS`. `INFO` has no extra keys.
  - `test_there_are_24_ways_to_face`: `basis(0) == Basis.IDENTITY`; 24 distinct bases; `rotation_of(basis(r)) == r` for every r; `rotation_of(Basis.from_scale(Vector3(2, 1, 1))) == -1`.
  - `test_turning_points_the_bow_side_to_starboard`: `facing(turned(0))` is near `Vector3.RIGHT`; turning four times returns to r for every r.
  - `test_tipping_points_the_bow_side_down`: `facing(tipped(0))` is near `Vector3.DOWN`; tipping four times returns to r.
  - `test_mirroring_swaps_port_and_starboard`: `facing(mirrored(turned(0)))` is near `Vector3.LEFT`; `mirrored(mirrored(r)) == r` and `mirrored(0) == 0`.
  - `test_only_shaped_blocks_are_not_cubes`: `is_cube("frame")` and `is_cube("balloon")`; not `is_cube("propeller")` or `is_cube("ladder")`.
  - In `tests/test_ship.gd`: `test_a_propeller_pushes_the_way_it_faces`. Turn both starter propellers to face aft (`rotation_of(Basis(Vector3.UP, PI))`). `max_thrust()` is −5000. At full throttle in still air for 20 s the ship moves more than 20 m toward +Z (astern).
- [ ] **Step 2: Run `./run_tests.sh blocks` and `./run_tests.sh test_ship`.** Expected: the new tests fail (`Blocks` doesn't exist).
- [ ] **Step 3: Implement** `Blocks`, then the two `ShipForces` helpers. In `Ship._ready`, store `_thrust_axes`, `_rudder_sides` and `_rudder_chords` alongside the cells, and use them in `_integrate_forces`. Replace `_power` with `ShipForces.propeller_power(grid)`. Remove the comment "Propellers push toward the bow until the shipyard can turn blocks".
- [ ] **Step 4: Run the whole suite.** Expected: everything passes. The starter ship still flies exactly as before, because all its rotations are 0.
- [ ] **Step 5: Commit** "Add the block catalogue and let propellers and rudders work the way they face".

### Task 2: Ship stats and warnings

Build-log items: "Live stats: weight, lift at altitude, thrust, top speed, climb rate", and the maths of "Centre of mass and centre of lift markers, with list and trim warnings".

**Files:**
- Create: `src/ship/ship_stats.gd`, `tests/test_ship_stats.gd`
- Modify: `tests/test_ship.gd` (the lopsided and overloaded flight tests use the stats)

**Interfaces:**
- Consumes: `ShipForces.forward_thrust`, `ShipForces.top_speed`, `ShipForces.air_density`, `ShipGrid.mass_properties`, `ShipGrid.drag_zones`
- Produces: `class_name ShipStats extends RefCounted` with:
  - `static func of(grid: ShipGrid, at_altitude: float) -> ShipStats`
  - `func describe() -> String`
  - `const LEAN_WARNING := 2.0`
  - Fields (floats unless stated):
    - `altitude`
    - `blocks: int`
    - `mass` (kg), `weight` (N), `lift` (N at altitude, trim 1)
    - `float_altitude`, `ceiling`
    - `thrust` (N), `top_speed` (m/s), `climb_rate` (m/s)
    - `center_of_mass: Vector3`, `center_of_lift: Vector3`
    - `list` (degrees; positive leans to starboard), `bow_down` (degrees; positive is bow down)
    - `warnings: PackedStringArray`

Formulas:
- `g` is `physics/3d/default_gravity`. `B` = balloons × `BALLOON_LIFT`, `S` = lift stones × `LIFT_STONE_LIFT`, `W` = `mass × g`, `ρ(h)` = `ShipForces.air_density(h)`.
- `lift = S + B × ρ(altitude)`
- `height_where(ratio)`: the height where `ρ` equals ratio. It's `INF` when `ratio ≤ 0`, `−INF` when `ratio > 1`, and `ROIL_ALTITUDE − AIR_SCALE_HEIGHT × ln(ratio)` otherwise.
- `float_altitude`:
  - `INF` if `S > 0 and S ≥ W` (she climbs forever);
  - otherwise `−INF` if `B == 0`;
  - otherwise `height_where((W − S) / B)`.
- `ceiling`: the same, with `B × TRIM_MAX`.
- `thrust = ShipForces.forward_thrust(grid)`, and `top_speed = ShipForces.top_speed(thrust, Σ zone.area.z, altitude)`.
- `climb_rate`: with `net = S + TRIM_MAX × B × ρ − W` and `up_area = Σ zone.area.y`, it's `signf(net) × sqrt(|net| / (0.5 × AIR_DENSITY × ρ × DRAG_COEFFICIENT × up_area))`, or 0 when `up_area` is 0.
- `center_of_lift`: the lift-weighted mean of the balloon cells (each `B_cell × ρ`) and stone cells (each 6,000). It's only meaningful when `lift > 0`.
- `list = rad_to_deg(atan2(com.x − col.x, col.y − com.y))`
- `bow_down = rad_to_deg(atan2(col.z − com.z, col.y − com.y))`

These follow from the lift settling straight above the weight. `test_ship.gd`'s lopsided test already uses the `list` formula.

Warnings, in this order and word for word:
1. No helm: `Every ship needs a helm.` With no blocks at all, this is the only warning.
2. The first of these that applies:
   - `ceiling == −INF`: `Too heavy to fly: she sinks into the Roil.`
   - `ceiling < altitude`: `Too heavy to hold %d m: she can climb no higher than %d m.`, with `roundi(altitude)` and `roundi(ceiling)`.
   - `float_altitude == INF`: `Too much lift: her lift stones alone carry her, so she'll climb forever.`
3. If `lift > 0` and `col.y ≤ com.y`: `Top-heavy: her lift is below her weight, so she'll roll over.` Otherwise, if `lift > 0`:
   - `|list| ≥ 2`: `Lists %d° to %s.` with `roundi(|list|)` and "starboard" or "port";
   - `|bow_down| ≥ 2`: `Down by the %s %d°.` with "bow" or "stern" and `roundi(|bow_down|)`.
4. The first of these that applies:
   - no propellers: `No propellers: she can only drift.`
   - no engine: `No engine: her propellers won't turn.`
   - `thrust ≤ 0`: `None of her propellers push her forward.`
5. No rudder: `No rudder: she can't steer.`

`describe()` gives these lines (names padded to 11 columns):

```
Blocks     287 of 4000
Weight     8.9 t
Lift       87.4 kN at 880 m
Floats at  877 m
Ceiling    1115 m
Thrust     5.0 kN
Top speed  20 m/s
Climb      +3.2 m/s at full trim
```

- "Floats at" and "Ceiling" read `climbs forever` for `INF` and `sinks into the Roil` for `−INF`.
- Weight is `%.1f t`, lift `%.1f kN at %d m`, thrust `%.1f kN`, top speed `%d m/s`, and climb `%+.1f m/s at full trim`.

- [ ] **Step 1: Write the failing tests** (`tests/test_ship_stats.gd`, with the starter ship at 880 m unless stated):
  - `test_the_starter_ship_by_the_numbers`: `mass` equals `mass_properties()["mass"]`, and `weight = mass × 9.81`. `lift` is within 1 N of `127 × 900 × ρ(880)`. `ship.trim_to_float_at(float_altitude)` is within 1e-4 of 1.0, and `trim_to_float_at(ceiling)` is within 1e-4 of `TRIM_MAX` (use a `Ship` added to the test). `thrust == 5000.0`. `top_speed` equals `ShipForces.top_speed(5000, Σ area.z, 880)`. `climb_rate > 0`, and there are no warnings.
  - `test_lift_stones_lift_the_same_at_any_height`: a helm plus one lift stone has the same `lift` at 300 m and 1,500 m.
  - `test_an_overloaded_ship_is_too_heavy_to_fly`: the starter with iron over the deck (as in `test_an_overloaded_ship_sinks`). `ceiling == -INF`, and the warning is `Too heavy to fly: she sinks into the Roil.`
  - `test_a_ship_too_heavy_for_this_height_says_how_high_she_can_go`: remove the envelope's top layer (y = 10). The ceiling is between 200 and 880, and the warning reads exactly `Too heavy to hold 880 m: she can climb no higher than N m.` with N = `roundi(ceiling)`.
  - `test_lift_stones_that_carry_her_alone_climb_forever`: the starter plus two lift stones on the keel. `float_altitude == INF`, and the warning is present.
  - `test_a_lopsided_ship_says_which_way_it_lists`: iron at x = 3 as in `test_ship.gd` gives `Lists N° to starboard.` The same at x = −3 gives port. `list` equals the `atan2` formula.
  - `test_a_nose_heavy_ship_is_down_by_the_bow`: four iron blocks at z = −6, y = 1 give `bow_down > 2` and `Down by the bow N°.`
  - `test_a_top_heavy_ship_will_roll_over`: a helm and deck on top of balloons give the top-heavy warning, and no list or trim warning.
  - `test_missing_parts_are_named`: no helm, no propellers, no engine (but propellers), propellers facing aft, and no rudder. Each gives its warning, in the order above.
  - `test_an_empty_design_only_needs_a_helm`: warnings are exactly `["Every ship needs a helm."]`, and nothing is NaN.
  - `test_the_readout`: the starter's `describe()` contains `Blocks     287 of 4000`, `Weight     8.9 t` and `Thrust     5.0 kN`, and each of its 8 lines starts with the names above.
  - In `tests/test_ship.gd`:
    - `test_a_lopsided_ship_lists_toward_its_heavy_side` now takes `expected` from `ShipStats.of(grid, START.y).list`.
    - `test_an_overloaded_ship_sinks` asserts `ShipStats.of(grid, START.y).ceiling == -INF`.
    - New: `test_a_ship_floats_at_the_height_her_stats_give`. Remove 10 balloons from the envelope's top layer and read `float_altitude` F (about 200 m lower). Launch at START in still air and simulate 180 s. The ship is within 20 m of F.
- [ ] **Step 2: Run `./run_tests.sh stats` and `./run_tests.sh test_ship`.** Expected: they fail.
- [ ] **Step 3: Implement `ShipStats`.**
- [ ] **Step 4: Run the whole suite.** Expected: everything passes.
- [ ] **Step 5: Commit** "Work out a design's stats, balance and warnings without flying it".

### Task 3: Blueprints and compact ship data

Build-log item: "Blueprints: save, load, and share as files".

**Files:**
- Create: `src/ship/blueprint.gd`, `tests/test_blueprint.gd`
- Modify: `src/ship/ship_grid.gd`, `src/core/settings.gd`
- Test: `tests/test_ship_grid.gd`, `tests/test_settings.gd`

**Interfaces:**
- Produces, on `ShipGrid`:
  - `var paint: Dictionary` (type -> `Color`)
  - `func copy() -> ShipGrid`: independent, with hit points and paint.
  - `static func in_area(cell: Vector3i) -> bool`: true within −64…63.
  - `static func read_blocks(data: Variant) -> Dictionary`: returns `{"grid": ShipGrid}` or `{"problem": String}`. Entries are `[x, y, z, type, rotation]` (full hit points) or `[x, y, z, type, rotation, hp]`. Numbers may be ints or whole-number floats.
  - `static func from_blocks(data: Variant) -> ShipGrid`: `read_blocks(data).get("grid")`, the same API as stage 3.
  - `const BYTES_PER_BLOCK := 7`
  - `func to_bytes() -> PackedByteArray`
  - `static func from_bytes(data: Variant) -> ShipGrid`: null when invalid.
  - `func paint_names() -> Dictionary` (type -> `"rrggbb"`)
  - `static func read_paint(data: Variant) -> Variant`: a `Dictionary` (type -> `Color`), or null when invalid.
- Produces, on `Blueprint`:
  - Constants:
    - `FORMAT := "skywright-blueprint"`, `VERSION := 1`
    - `DIR := "user://blueprints"`, `EXTENSION := ".skyship.json"`
    - `MAX_FILE_SIZE := 1048576`, `MAX_NAME_LENGTH := 32`, `DEFAULT_NAME := "Untitled ship"`
  - Static functions:
    - `to_text(grid: ShipGrid, ship_name: String) -> String`
    - `parse(text: String) -> Dictionary` (`{"grid", "name"}` or `{"problem"}`)
    - `save(grid: ShipGrid, ship_name: String, dir := DIR) -> Error`
    - `load_file(path: String) -> Dictionary`
    - `path_for(ship_name: String, dir := DIR) -> String`
    - `list(dir := DIR) -> PackedStringArray`: paths, sorted.
    - `clean_name(raw: String) -> String`
- Produces, on `Settings`: `static func clean_name(raw: String, max_length := MAX_NAME_LENGTH, fallback := DEFAULT_NAME) -> String`. Existing callers are unchanged.

Rules:
- `read_blocks` checks in this order and returns the first problem (N counts from 1):
  1. Not an array, or empty: `The ship has no blocks.`
  2. Too many: `The ship has %d blocks; the most a ship can have is 4000.`
  3. An entry that isn't an array of 5 or 6 items, or has a non-string type: `Block %d isn't written as [x, y, z, type, rotation].`
  4. A number that isn't an int or a finite whole-number float: `Block %d has a number that isn't a whole number.`
  5. Outside −64…63: `Block %d is outside the build area (-64 to 63).`
  6. Unknown type (the type shown cut to 24 characters): `Block %d is an unknown type, "%s".`
  7. Rotation out of range: `Block %d has rotation %d; rotations go from 0 to 23.`
  8. Hit points out of range (6-item entries only): `Block %d has %d hit points; a %s has 1 to %d.`
  9. A cell used twice: `Block %d is in the same place as another block.`
  10. No helm: `Every ship needs a helm.`
- `to_bytes`: see the protocol section. `from_bytes` checks the following, then hands the decoded `[x, y, z, type, rotation, hp]` list to `from_blocks`:
  - it's a `PackedByteArray` of at least 3 bytes;
  - the count is 1…4000;
  - `slice(2).decompress(count × 7, FileAccess.COMPRESSION_ZSTD)` has exactly `count × 7` bytes;
  - each type index is in range.
- `read_paint`: the data must be a `Dictionary` of at most `Tuning.BLOCKS.size()` entries. Each key must be a known type, and each value a `String` for which `Color.html_is_valid` is true. `paint_names()` writes `color.to_html(false)`.
- `Blueprint.to_text`: `JSON.stringify({"format", "version", "name", "blocks", "paint"})`. Blocks are sorted by cell, with ints for every number.
- `Blueprint.parse`:
  - `JSON.new().parse(text)` must succeed and give a `Dictionary` whose `"format"` is `FORMAT`, else `This isn't a Skywright blueprint.`
  - `"version"` must be a whole number. If it's not 1: `This blueprint is version %d; this game reads version 1.`
  - `name = clean_name(data["name"])` if it's a String, else `DEFAULT_NAME`.
  - Then `read_blocks(data["blocks"])` (5-item entries).
  - Then `read_paint(data.get("paint", {}))`, whose failure is `The paint colours aren't valid.`
- `Blueprint.load_file`:
  - A file that won't open: `Couldn't open "%s".` (the file's name).
  - A file bigger than `MAX_FILE_SIZE` (checked with `get_length()` before reading): `"%s" is too big to be a blueprint.`
- `path_for`: `dir.path_join(clean_name(n).validate_filename().lstrip(". ") + EXTENSION)`, using `ship` when the stripped name is empty.
- `save` makes the folder with `DirAccess.make_dir_recursive_absolute`.
- `list` returns nothing, and logs nothing, when the folder doesn't exist.

- [ ] **Step 1: Write the failing tests.** In `tests/test_ship_grid.gd`:
  - `test_copy_is_independent`: edit the copy, and the original is unchanged. Hit points and paint are copied.
  - `test_to_bytes_and_back`: the starter ship keeps every block, type, rotation and hit point. A damaged block keeps its hp. The starter is under 2,000 bytes. A 4,000-block ship (20 × 10 × 20 frames with a helm) is under 40,000 bytes.
  - `test_from_bytes_refuses_junk`: returns null, with no engine errors, for:
    - a String, an empty array, two bytes;
    - count 0, count 4001;
    - a valid count with junk after it;
    - a body cut short;
    - a type index of 200;
    - a coordinate byte of 200;
    - two blocks in one cell;
    - no helm.
  - `test_read_blocks_names_the_first_problem`: one case per rule above, each with its exact message. `[[0, 0, 0, "helm", 0.0]]` is accepted (a whole float), and `[[0.5, 0, 0, "helm", 0]]` isn't.
  - `test_paint_is_checked`: `{"balloon": "c0392b"}` reads to `Color("c0392b")`. Refused: not a dictionary, an unknown type, `"zzz"`, a non-string value, and too many entries.
  - Update `test_from_blocks_refuses_bad_ships`: its "float coordinate" case becomes 0.5, since whole floats are now accepted.

  In `tests/test_blueprint.gd` (with a temp folder `user://test_blueprints_<randi>`, deleted in `after_each`):
  - `test_a_blueprint_round_trips`: the starter ship with a turned propeller and paint `{"balloon": red}`, saved as "Stormchaser" and loaded, has the same blocks, rotations and paint, and the name "Stormchaser".
  - `test_blueprints_are_plain_json`: the text parses as JSON, has the five keys, and every block is `[x, y, z, type, rotation]` with ints (the text contains `[-2,-1,` style entries, with no `.0`).
  - `test_bad_blueprints_are_refused_with_the_first_problem`: `parse` gives the exact message for each of:
    - `"not json"`, `"[]"`;
    - `{"format": "other"}`;
    - version 2;
    - no blocks, `"blocks": "x"`;
    - a block with `1e400`, one with `0.5`;
    - an unknown type, rotation 24;
    - a duplicate, no helm;
    - paint `{"balloon": "zzz"}`.
    No engine errors are logged.
  - `test_a_huge_file_is_refused_before_it_is_read`: a 1.5 MB file gives `"huge.skyship.json" is too big to be a blueprint.`
  - `test_file_names_come_from_the_ship_name`:
    - `path_for("Storm/chaser: v2?", dir)` ends with `/Storm_chaser_ v2_.skyship.json`;
    - `path_for("../../etc", dir)` stays inside `dir`;
    - `path_for("", dir)` ends with `/Untitled ship.skyship.json`;
    - a 40-character name is cut to 32.
  - `test_the_list_shows_saved_blueprints`: save "B ship" and "A ship" → `list(dir)` is their paths, A first. A missing folder gives `[]`, with no errors.
  - In `tests/test_settings.gd`: `test_clean_name_takes_a_length_and_fallback`.
- [ ] **Step 2: Run `./run_tests.sh blueprint`, `./run_tests.sh ship_grid` and `./run_tests.sh settings`.** Expected: they fail.
- [ ] **Step 3: Implement** `ShipGrid` (`read_blocks` replaces the checks in `from_blocks`), `Blueprint`, and `Settings.clean_name`'s parameters.
- [ ] **Step 4: Run the whole suite.** Expected: everything passes.
- [ ] **Step 5: Commit** "Save and load blueprints safely, and pack ships into a few bytes".

### Task 4: Designing: edits, mirror mode, undo and redo, aiming

Build-log item: "Build mode: place, remove, rotate, mirror, undo and redo" (everything but the screen).

**Files:**
- Create: `src/builder/ship_design.gd`, `tests/test_ship_design.gd`
- Modify: `src/ship/ship_grid.gd` (`raycast`)
- Test: `tests/test_ship_design.gd`, `tests/test_ship_grid.gd`

**Interfaces:**
- Consumes: `Blocks.mirrored`, `ShipGrid.copy`, `ShipGrid.in_area`, `ShipGrid.MAX_BLOCKS`
- Produces:
  - `ShipGrid.raycast(from: Vector3, direction: Vector3, max_distance := 200.0) -> Dictionary`: `{"cell": Vector3i, "normal": Vector3i}` for the first block the ray enters (ladders included), or `{}`.
  - `class_name ShipDesign extends RefCounted`:
    - `signal changed`: once per edit, undo, redo, replace or paint.
    - `var grid: ShipGrid`, `var mirror := false`
    - `func _init(from: ShipGrid = null)`: a copy of `from` at full hit points, keeping its paint; empty when null.
    - `func can_place(cell: Vector3i) -> bool`: in the area, empty, and under 4,000 blocks.
    - `func place(cell: Vector3i, type: String, rotation := 0) -> bool`
    - `func remove(cell: Vector3i) -> bool`
    - `func replace(with: ShipGrid) -> void`: one undoable edit, at full hit points with its paint.
    - `func set_paint(type: String, color: Variant) -> void`: a `Color`, or null for the block's own colour. It can't be undone.
    - `func undo() -> bool`, `func redo() -> bool`, `func can_undo() -> bool`, `func can_redo() -> bool`
    - `static func mirror_of(cell: Vector3i) -> Vector3i`: `(−x, y, z)`.

Rules:
- An edit is an array of changes `[cell, before, after]`, where `before` and `after` are block dictionaries or null.
- `place` puts the block at the cell. With `mirror` on and `cell.x != 0`, it also puts the block at `mirror_of(cell)` with `Blocks.mirrored(rotation)`. Each target is placed only if `can_place` allows it, counting the blocks this edit has already placed. Placing never overwrites.
- `remove` removes the cell, and the mirror cell when mirror is on.
- An edit that changes nothing isn't recorded and returns false. A new edit clears the redo list.
- `replace` records every cell that differs, and `paint` is replaced along with the blocks.

Raycast (cells are the cubes `[c − 0.5, c + 0.5]`):

```gdscript
func raycast(from: Vector3, direction: Vector3, max_distance := 200.0) -> Dictionary:
	var dir := direction.normalized()
	var p := from + Vector3(0.5, 0.5, 0.5)  # cell c now spans [c, c + 1)
	var cell := Vector3i(floori(p.x), floori(p.y), floori(p.z))
	var step := Vector3i.ZERO
	var t_max := Vector3(INF, INF, INF)
	var t_delta := Vector3(INF, INF, INF)
	for axis in 3:
		if dir[axis] > 0.0:
			step[axis] = 1
			t_max[axis] = (cell[axis] + 1 - p[axis]) / dir[axis]
			t_delta[axis] = 1.0 / dir[axis]
		elif dir[axis] < 0.0:
			step[axis] = -1
			t_max[axis] = (cell[axis] - p[axis]) / dir[axis]
			t_delta[axis] = -1.0 / dir[axis]
	var normal := Vector3i.ZERO
	var t := 0.0
	while t <= max_distance:
		if blocks.has(cell):
			return {"cell": cell, "normal": normal}
		var axis := t_max.min_axis_index()
		t = t_max[axis]
		cell[axis] += step[axis]
		t_max[axis] += t_delta[axis]
		normal = Vector3i.ZERO
		normal[axis] = -step[axis]
	return {}
```

- [ ] **Step 1: Write the failing tests.** In `tests/test_ship_grid.gd`:
  - `test_raycast_finds_the_first_block_and_its_face`: from `(0, 10, 0)` straight down onto blocks at y = 0 and y = 3, it hits `(0, 3, 0)` with normal `(0, 1, 0)`. From `(−10, 0, 0)` along +X it hits the nearest block with normal `(−1, 0, 0)`. A diagonal ray hits the cell it enters first.
  - `test_raycast_misses_and_stops_at_its_range`: a ray pointing away gives `{}`, and a block beyond `max_distance` isn't hit.

  In `tests/test_ship_design.gd`:
  - `test_a_design_is_a_copy_at_full_strength`: designing from a damaged grid doesn't change that grid, and the design's blocks have full hp.
  - `test_place_and_remove`, with `changed` emitted once each.
  - `test_place_refuses_occupied_cells_the_edge_and_the_limit`: an occupied cell; `(64, 0, 0)` and `(0, -65, 0)`; and a design already at 4,000 blocks. Each returns false with nothing changed. `(-64, 0, 0)` and `(63, 63, 63)` are accepted.
  - `test_mirror_builds_both_sides`: `place((2, 0, 0), "propeller", turned(0))` with mirror on puts a propeller at `(−2, 0, 0)` with `mirrored(turned(0))`. `remove` takes both away, and one undo brings both back.
  - `test_mirror_on_the_keel_line_places_one_block`
  - `test_mirror_skips_cells_outside_the_build_area`: placing at `(−64, 0, 0)` with mirror on places only that block, since 64 is outside.
  - `test_undo_and_redo`: three edits, undo twice, redo once, then a new edit clears the redo list. `can_undo` and `can_redo` follow along.
  - `test_loading_a_blueprint_can_be_undone`: `replace(StarterShip.build())` over a small design, then `undo()`, gives back the small design exactly.
  - `test_paint_changes_the_colour_of_a_type`: `set_paint("balloon", Color.RED)`, then `set_paint("balloon", null)` removes it again.
- [ ] **Step 2: Run `./run_tests.sh ship_design` and `./run_tests.sh ship_grid`.** Expected: they fail.
- [ ] **Step 3: Implement** `raycast` and `ShipDesign`.
- [ ] **Step 4: Run the whole suite.** Expected: everything passes.
- [ ] **Step 5: Commit** "Design ships with mirror mode, undo and redo, and aim along the grid".

### Task 5: Ship looks

Build-log item: "Ship looks: merged meshes, balloon cloth, paint colours".

**Files:**
- Modify: `src/ship/ship_mesh.gd`
- Create: `tests/test_ship_mesh.gd` (move `test_ship_faces_wind_the_way_godot_draws_them` and `winding()` here from `test_ship.gd`, extended to every surface)

**Interfaces:**
- Consumes: `Blocks.INFO[type]["material"]`, `Blocks.is_cube`, `Blocks.basis`, `ShipGrid.paint`
- Produces:
  - `ShipMesh.build(grid) -> MeshInstance3D`: an `ArrayMesh` with one surface per material used, in `Blocks.MATERIALS` order, each with its material.
  - `ShipMesh.color_of(grid: ShipGrid, type: String) -> Color`: the paint, or else `COLORS`.
  - `const ROUNDING := 0.22`, `const GORE_SHADE := 0.94`

Rules:
- **Faces:** a cube block's face is drawn unless its neighbour is a cube block. A shaped block is always drawn whole.
- **Materials:** every material uses vertex colour as albedo (sRGB).
  - wood: roughness 0.9.
  - metal: metallic 0.7, roughness 0.45.
  - cloth: roughness 1.0.
  - stone: roughness 0.6, emission `Color("7fd3c5")` at energy 0.6.
- **Shapes,** as boxes in the block's own space (forward −Z, up +Y), turned by `Blocks.basis(rotation)`. `_add_box(st, center, size, basis := Basis.IDENTITY)` turns the corners, edges and normals.
  - propeller: hub `(0.3, 0.3, 0.5)` at `(0, 0, 0.15)`; blades `(1.0, 0.16, 0.06)` and `(0.16, 1.0, 0.06)` at `(0, 0, −0.2)`.
  - rudder: `(0.16, 1.0, 1.0)`.
  - sail (cloth): `(1.0, 1.0, 0.08)`.
  - cannon: carriage `(0.8, 0.35, 0.8)` at `(0, −0.3, 0.05)`; barrel `(0.3, 0.3, 1.0)` at `(0, 0.05, −0.25)`.
  - helm: post `(0.2, 0.9, 0.2)` at `(0, −0.05, 0.2)`; spokes `(0.9, 0.08, 0.08)` and `(0.08, 0.9, 0.08)` at `(0, 0.2, 0.05)`; rim `(0.9, 0.08, 0.08)` at y = 0.62 and −0.22, and `(0.08, 0.9, 0.08)` at x = ±0.42 (all at z = 0.05, centred on y = 0.2).
  - ladder: as now, turned.
- **The balloon envelope:**
  - Collect every drawn balloon face. For each corner (keyed by `Vector3i((corner * 2.0).round())`), gather the distinct face normals that meet there.
  - Each corner's normal is the normalised sum of those normals. It moves to `corner − normal × ROUNDING × (count − 1)`, so edges bevel and corners round.
  - Emit balloon triangles with these per-vertex normals, in the stage 2 winding order.
  - Colour: `color_of(grid, "balloon")`, times `GORE_SHADE` when `posmod(cell.z, 2) == 1`.

> ponytail: the envelope's inner (concave) edges are pulled in too, which creases them. Push concave corners out instead if L-shaped envelopes look wrong.

- [ ] **Step 1: Write the failing tests** (`tests/test_ship_mesh.gd`):
  - `test_ship_faces_wind_the_way_godot_draws_them`: every surface of the starter ship's mesh, and of a one-block grid of each type, winds like `BoxMesh`.
  - `test_one_surface_per_material`: the starter ship has wood, metal and cloth (3 surfaces). Add a lift stone and it has 4, the stone's with emission on.
  - `test_faces_between_cubes_are_left_out`: two frames side by side make 10 quads (60 vertices). A frame beside a propeller keeps all 6 of its faces.
  - `test_a_propeller_is_drawn_the_way_it_faces`: at rotation 0 the blades are at the bow side (the minimum z of its vertices is below −0.2). Turned around, they're at the stern side.
  - `test_the_envelope_is_rounded_cloth`: in a 3 × 2 × 3 balloon block, some vertices are off the half-metre lattice (pulled in at edges). A top-face vertex in the middle of the block keeps normal `(0, 1, 0)`, and an edge vertex has a diagonal normal.
  - `test_paint_colours_every_block_of_a_type`: with paint `{"deck": Color("2f5d8a")}`, every deck vertex has that colour (compare the colour array of the wood surface for a deck-only grid).
- [ ] **Step 2: Run `./run_tests.sh ship_mesh`.** Expected: the new tests fail.
- [ ] **Step 3: Implement.** Replace the ponytail comment about one mesh with one about sections (stage 6).
- [ ] **Step 4: Run the whole suite.** Expected: everything passes.
- [ ] **Step 5: Commit** "Draw ships with wood, metal, cloth and stone, shaped blocks, a rounded envelope and paint".

### Task 6: The dock, and ships coming and going mid-game

Build-log items: the dock for "Test flight from the dock, with instant return", and the co-op groundwork for ships of your own (spec §3.8).

**Files:**
- Create: `src/world/dock.gd`, `tests/test_fleet.gd`
- Modify:
  - `src/net/world_sync.gd`, `src/net/session.gd` (protocol 3)
  - `src/ship/ship.gd` (`captain`, `test`, spots in front of the helm)
  - `src/world/world.gd` (the dock; boarding)
  - `src/crew/player_controller.gd` (`board`), `src/ui/hud.gd` (`fell_overboard` from the player)
  - `tests/net_case.gd` (`sail_together`), `tests/test_world_sync.gd`, `tests/test_helm.gd`, `tests/test_world.gd`

**Interfaces:**
- Consumes: `ShipGrid.to_bytes`/`from_bytes`, `paint_names`/`read_paint`
- Produces:
  - `Dock`:
    - constants `SPACING := 60.0`, `SLIPWAYS := 9`, `TEST_OFFSET := Vector3(0, 0, -90)`, `REACH := 150.0`
    - `static create(at: Vector3) -> StaticBody3D`
    - `static slipway(at: Vector3, index: int) -> Transform3D`: `at + (index × SPACING, 0, 0)`, facing the bow.
    - `static test_berth(at: Vector3, index: int) -> Transform3D`: the slipway plus `TEST_OFFSET`.
    - `static area(at: Vector3) -> AABB`, `static obstacles(at: Vector3) -> Array[AABB]`
    - `static near(at: Vector3, where: Vector3) -> bool`: `area(at).grow(REACH).has_point(where)`.
  - `Ship.captain := 0` (the owner's peer id, 0 for nobody) and `Ship.test := false` (a test flight).
  - `WorldSync`:
    - `signal ship_removed(ship: Ship, successor: Ship)`: fired after the ship is dropped from `ships` but before it's freed.
    - `add_ship(grid, at, captain := 0, test := false, pilot := 0) -> Ship`: on the server; tells every peer in the world.
    - `remove_ship(ship: Ship, successor: Ship = null)`: on the server; tells everyone.
    - `id_of(ship) -> int` (0 if it's not here)
    - `home_ship() -> Ship`: the non-test ship whose captain is 1, else one whose captain is 0, else the first non-test ship, else the first ship, else null.
  - `World.dock`, `World.board(target: Ship, spot := -1)` (−1 means your roster slot), `World.my_slot() -> int`.
  - `PlayerController.board(new_crew: CrewMember)` and `signal fell_overboard`.
  - `Session.PROTOCOL_VERSION == 3`
  - `NetCase.sail_together() -> bool`, with members `host`, `client`, `host_world`, `client_world`, moved from `test_world_sync.gd`.

The dock (placed at `World.START`, the first slipway):
- A quay: a stone box, `Color("8d8578")`, roughness 0.95, centred at `at + (240, −4, 37)`, size `(540, 5, 14)`. Its top is 1.5 m below the deck of a ship at the slipway.
- An island under it: `Island.create(at + Vector3(240, -8, 110), 70.0)`.
- `area(at)` is `AABB(at + Vector3(-30, -60, -100), Vector3(540, 120, 144))`. It covers every slipway, every test berth and the quay.
- `obstacles(at)` returns the quay's box and the island's bounding box.

Rules:
- **The server adds a ship** (`add_ship`): after `_add`, it sets `helm.pilot = pilot` before connecting the helm signals, then sends `_ship_added(time, entry)` to every peer in the world.
- **Clients take entries:** `_world` and `_ship_added` go through one checked `_add_entry(entry, time) -> Ship`. `_world` adds every ship, then emits `ship_added` for each, so `home_ship()` is right when the first one fires.
- **Removing a ship** (server `remove_ship`, client `_ship_removed`):
  - erase it from `ships`, `_buffers` and `_keys_heard`;
  - drop `_crew` entries and avatars on it;
  - emit `ship_removed(ship, successor)`;
  - then `remove_child` and `queue_free`.
- **World boarding:**
  - `_on_ship_added(added)`: on a dedicated server, nothing. If `added.captain == multiplayer.get_unique_id()`, board it at spot 0. Otherwise, if there's no player yet and `added == sync.home_ship()`, board it at your slot.
  - `_on_ship_removed(removed, successor)`: forget `_came_from` if it's the removed ship. If you're aboard the removed ship, board the first of: the successor; `_came_from`; `sync.home_ship()`.
- **`board()`:**
  - Make a `CrewMember` in the target's interior at `target.crew_spawn(spot)`.
  - The first time, build the player and HUD as stage 3 did. After that, set `_came_from` to the ship you were on, call `player.board(crew)`, and `queue_free` the old crew member.
  - Then `ship = target`.
- **`PlayerController.board(new_crew)`:**
  - Disconnect the old helm's `pilot_changed`, and set `crew` and `ship`.
  - Connect the new helm, and pass on the crew member's `fell_overboard`.
  - Call `_on_pilot_changed()` (so you're at the helm if the server made you pilot), and set `chase = false`.
  - `_ready` uses the same path.
- **Spawn spots:** `Ship.SPAWN_SPOTS` gains `(0, 0, −2), (−1, 0, −2), (1, 0, −2)` (in front of the helm) at the end, so a helm with deck only in front of it still has spots.
- **The starter ship** is added at `Dock.slipway(START, 0)` with captain 1, or captain 0 on a dedicated server.

- [ ] **Step 1: Write the failing tests.**
  - Move `sail_together()` and its members into `NetCase`.
  - In `tests/test_fleet.gd`:
    - `test_the_dock_has_slipways_and_a_reach`: slipway 0 is at `START`, slipway 2 is 120 m to starboard, and the test berth is 90 m ahead. `near` is true on the quay and 140 m off it, and false 2 km away. The world has a dock.
    - `test_a_ship_added_mid_game_reaches_everyone`: after sailing, the host adds a painted ship with captain 7 and test true at slipway 1. Within 2 s the guest has it, with the same block count, paint, captain and test flag, and it's kinematic.
    - `test_removing_a_ship_moves_its_crew_to_the_successor`: the host adds ship B, then removes the starter with successor B.
      - Both the host's player and the guest end up aboard B, and the starter is gone on both sides.
      - The guest's avatar reappears on the host within 1 s, reporting on B.
      - No engine errors, even though the guest sent a crew report for the starter in flight.
    - `test_a_ship_removed_with_no_successor_sends_you_back`: the host boards ship B with `world.board(B)`, then removes B with no successor. The host is aboard the starter again.
    - `test_a_late_joiner_boards_the_hosts_ship`:
      - The host adds a ship with captain 5 at slipway 1, then replaces the starter with a new ship with captain 1 (`add_ship`, then `remove_ship(starter, new)`).
      - A guest joins after that. They board the captain 1 ship, not the captain 5 one, which has the lower id.
  - In `tests/test_helm.gd`: `test_crew_can_board_in_front_of_the_helm`: a design with deck only in front of the helm gives a spawn spot in front of it, standing on the deck.
  - In `tests/test_world.gd`: `test_boarding_another_ship_moves_you_and_your_controls`:
    - Add a second ship next to the starter, and `world.board(it)`.
    - The crew's parent is its interior, and `world.ship` and `player.ship` are that ship.
    - `player.prompt()` is `"Take the helm"` when standing by its helm.
    - The old crew member is freed.
    - The HUD still shows "You fell overboard. Back aboard!" after a fall from the new ship.
  - Update the stage 3 tests for entries of 7 fields and protocol 3.
- [ ] **Step 2: Run `./run_tests.sh fleet`, `./run_tests.sh helm` and `./run_tests.sh test_world`.** Expected: they fail.
- [ ] **Step 3: Implement** `Dock`, the `Ship` fields and spots, the `WorldSync` changes (remove the ponytail comment in `add_ship`), `World` boarding, `PlayerController.board`, the HUD signal, and protocol 3.
- [ ] **Step 4: Run the whole suite.** Expected: everything passes.
- [ ] **Step 5: Commit** "Add the dock, and send ships that come and go mid-game to everyone".

### Task 7: Launches and test flights

Build-log items: "Test flight from the dock, with instant return", and ships of your own in co-op (spec §3.8; a new Build Log task, s04-09).

**Files:**
- Create: `tests/test_launch.gd`
- Modify: `src/net/world_sync.gd`, `src/world/world.gd`, `src/ui/hud.gd`, `project.godot` (the `shipyard` action, B)
- Test: `tests/test_launch.gd`, `tests/test_project.gd`

**Interfaces:**
- Consumes: `add_ship`, `remove_ship`, `home_ship`, `Dock.slipway`, `Dock.test_berth`, `Dock.obstacles`
- Produces:
  - `WorldSync`:
    - `const LAUNCH_COOLDOWN := 1.0`, `const CLEARANCE := 2.0`
    - `var berths: Array[Transform3D]`, `var test_berths: Array[Transform3D]` and `var obstacles: Array[AABB]`, all set by `World`.
    - `launch(grid: ShipGrid, test: bool)`: this machine's player launches grid.
    - `end_test()`
    - `ship_of(peer: int, test: bool) -> Ship`
    - `berth_of(peer: int, test: bool) -> Transform3D`
  - `World`:
    - `test_flight(grid: ShipGrid)`, `launch(grid: ShipGrid)`
    - `on_test_flight() -> bool`: aboard your own test ship.
    - `at_dock() -> bool`: your crew member, drawn in the world, is `Dock.near` the dock.
  - `Hud.test_flight: bool`: set by `World` each frame.
  - The input action `shipyard` (B).

Server rules (`_launch_for(peer, grid, test)`):

```gdscript
func _launch_for(peer: int, grid: ShipGrid, test: bool) -> void:
	if _time - _launched_at.get(peer, -INF) < LAUNCH_COOLDOWN:
		return
	_launched_at[peer] = _time
	var built := ShipDesign.new(grid).grid  # new ships are built whole
	var trial := ship_of(peer, true)
	var own := ship_of(peer, false)
	var at := _clear_spot(built, berth_of(peer, test), [trial, own])
	var ship := add_ship(built, at, peer, test, peer)
	if trial != null:
		remove_ship(trial, ship)
	if own != null and not test:
		remove_ship(own, ship)
```

- `berth_of(peer, test)` uses index `slot + (1 if session.dedicated else 0)`, where slot is `peer`'s roster index. It's `test_berths[index]` for a test, and `berths[index]` otherwise.
- `_clear_spot(grid, at, ignoring)`:
  - While the new ship's world box (`at * grid.bounds()`) meets another ship's box (`ship.global_transform * ship.bounds`, not in `ignoring`) or an obstacle, each grown by `CLEARANCE`, raise `at` by the box's height plus `CLEARANCE`.
  - Give up after 20 tries and use the last spot.
- `end_test()` on the server removes the peer's test ship with no successor.
- A leaver's ships go with them. In the deferred step after roster changes (the one that frees stations), the server removes every ship whose captain isn't 0 and isn't on the roster.
- On a client, `launch` sends `_launch.rpc_id(1, grid.to_bytes(), grid.paint_names(), test)`, and `end_test` sends `_end_test.rpc_id(1)`. The server acts for itself directly.

World and HUD rules:
- `World.test_flight` and `World.launch` call `sync.launch(grid, true/false)`.
- `_unhandled_input`: when `shipyard` is pressed during a test flight (and the pause menu is closed), call `sync.end_test()` and mark the input handled. Task 8 adds opening the shipyard.
- `World` sets `sync.berths`, `test_berths` and `obstacles` from the dock before adding the starter ship.
- The HUD shows a banner at the top centre during a test flight: `Test flight: B returns to the shipyard`.

- [ ] **Step 1: Write the failing tests** (`tests/test_launch.gd`, where `skiff()` is a small design: the starter ship with its envelope trimmed to 3 layers):
  - `test_a_test_flight_puts_you_at_the_helm_of_the_design` (solo):
    - `world.test_flight(skiff())` makes a new ship with `test`, captain 1, the skiff's block count, at the test berth.
    - You're aboard it with `crew.station == ship.helm`.
    - The starter ship is still there.
  - `test_b_returns_from_a_test_flight_instantly` (solo):
    - Test flight, full throttle and the autopilot on, fly 20 s, then press `shipyard`.
    - The test ship is gone, and you're aboard the starter, not at the helm.
    - Pressing `shipyard` again does nothing more, and no engine errors are logged.
  - `test_a_test_flight_sinking_into_the_roil_can_still_return`: a test flight of the overloaded ship, simulated 30 s, then return works.
  - `test_a_second_test_flight_replaces_the_first`: two `test_flight` calls more than a second apart leave exactly one test ship, the second design, with you aboard it. Two calls in one frame make one ship.
  - `test_launching_replaces_your_ship` (solo): `world.launch(skiff())` removes the starter. The new ship has captain 1, is not a test, stands at slipway 0, and you're at its helm.
  - `test_a_guest_launches_a_ship_of_their_own` (`sail_together`):
    - The guest's `world.launch(skiff())` makes a ship on the host with captain = the guest's id, at slipway 1, with the guest at its helm.
    - The host is still aboard the starter, and both sides have 2 ships.
  - `test_the_crew_follow_the_host_to_a_new_ship`: the host launches. The guest, who was aboard the starter, ends up aboard the new ship, and the starter is gone on both sides.
  - `test_a_guest_can_end_only_their_own_test_flight`: the host is on a test flight. The guest's `sync.end_test()` leaves it alone.
  - `test_a_leaving_guests_ships_go_with_them`: the guest launches a ship and starts a test flight, then leaves. Both ships are gone on the host within 2 s.
  - `test_launches_stay_clear_of_other_ships`: with a ship parked on slipway 1, a guest's launch comes out above it, and their world boxes don't meet.
  - `test_the_server_ignores_junk_launches`: the guest calls `_launch.rpc_id(1, …)` with a String, junk bytes, a valid ship with paint `{"x": 1}`, a valid ship with test `"yes"`, and then two good launches in one frame. The host ends with exactly one new ship, and no engine errors are logged.
  - `test_guests_on_a_dedicated_server_launch_beside_its_ship`: on a dedicated server, the first guest's launch is at slipway 1.
  - `test_the_hud_says_you_are_on_a_test_flight` (solo): the banner shows during a test flight and not after.
  - In `tests/test_project.gd`: `shipyard` is bound to B.
- [ ] **Step 2: Run `./run_tests.sh launch`.** Expected: the tests fail.
- [ ] **Step 3: Implement** the RPCs, `_launch_for`, `_clear_spot`, `end_test`, leavers' ships, `berth_of`, the `World` functions and B routing, the banner, and the action.
- [ ] **Step 4: Run the whole suite.** Expected: everything passes.
- [ ] **Step 5: Commit** "Launch ships and test flights from the dock, one of each per player".

### Task 8: The shipyard

Build-log items: "Build mode: place, remove, rotate, mirror, undo and redo" (the screen), "Live stats" (shown), "Centre of mass and centre of lift markers, with list and trim warnings" (drawn), "Test flight from the dock, with instant return" (from the shipyard), and "Blueprints: save, load, and share as files" (the panel).

**Files:**
- Create: `src/builder/build_view.gd`, `src/builder/shipyard.gd`, `tests/test_shipyard.gd`
- Modify: `src/world/world.gd`, `src/ui/hud.gd`, `project.godot`, `tests/test_project.gd`

**Interfaces:**
- Consumes: `ShipDesign`, `ShipStats`, `ShipMesh`, `Blueprint`, `Blocks`, `ShipGrid.raycast`, `World.test_flight`, `World.launch`, `World.on_test_flight`, `World.at_dock`
- Produces:
  - `BuildView extends SubViewport`:
    - `var camera: Camera3D`; `var yaw := 0.7`, `var pitch := -0.5`, `var distance := 36.0`, `var focus := Vector3.ZERO`
    - `show_design(grid: ShipGrid, stats: ShipStats, mirror: bool)`
    - `show_ghost(type: String, rotation: int, cell: Vector3i, valid: bool)`, `hide_ghost()`
    - `aim(point: Vector2, grid: ShipGrid) -> Dictionary`: `{"place": Vector3i}`, plus `"remove": Vector3i` when the ray hits a block.
    - `orbit(by: Vector2)`, `zoom(factor: float)`
    - `look_from(from: Vector3, at: Vector3)` (for tests)
  - `Shipyard extends CanvasLayer`:
    - `signal test_flight_requested(grid: ShipGrid)`, `signal launch_requested(grid: ShipGrid)`
    - `var design: ShipDesign`, `var view: BuildView`, `var stats: ShipStats`
    - `var selected := "frame"`, `var rotation := 0`
    - `var blueprint_dir := Blueprint.DIR`, `var blueprint_name := Blueprint.DEFAULT_NAME`
    - `_init(for_design: ShipDesign, at_altitude: float)`
    - `select(type: String)`
    - `click(point: Vector2, button: MouseButton)`
    - `save_blueprint(ship_name: String)`, `load_blueprint(path: String)`
    - `stats_text() -> String`, `warnings_text() -> String`, `note_text() -> String`
  - `World`:
    - `var shipyard: Shipyard`: null while closed.
    - `var design: ShipDesign`: your design, kept for the whole game.
    - `open_shipyard()`, `close_shipyard()`
  - `Hud.at_dock: bool`
  - Input actions: `turn_block` R, `tip_block` T, `mirror` M, `undo` Ctrl+Z, `redo` Ctrl+Y and Ctrl+Shift+Z, `test_flight` F.

What the player sees:
- **The view:** a `SubViewportContainer` (full screen, stretch) holding the `BuildView`, which has its own 3D world:
  - A `WorldEnvironment` with a `ProceduralSkyMaterial`: sky top `Color("3d6fb6")`, horizon `Color("a9c7e8")`, ground `Color("2b3440")`.
  - A `DirectionalLight3D` with shadows.
  - The design's `ShipMesh`, rebuilt on each `design.changed`.
  - A grid of lines at y = −0.5, covering the design's bounds grown by 6 m. The keel line (x = 0) is drawn in `UiTheme.ACCENT`.
  - A translucent plane at x = 0 while mirror mode is on.
  - The ghost: `ShipMesh.build` of a one-block grid, with `transparency = 0.5`. It's tinted red through `material_overlay` where the block can't go.
  - The centres of mass (`Color("e8a948")`) and lift (`Color("7fd3f5")`): spheres of radius 0.35 with `Label3D` "Weight" and "Lift", joined by a line. They're unshaded, with `no_depth_test`, so they show through blocks.
  - The camera orbits `focus`, which eases toward the centre of the design's bounds. Physics interpolation is off for the camera.
- **Controls:**

  | Input | Does |
  |---|---|
  | Left click | Place the selected block on the face you point at, or on the grid |
  | Right click | Remove the block you point at |
  | Right-drag (moved over 6 px), or W A S D | Orbit |
  | Mouse wheel | Zoom (×0.9 or ×1.1, distance clamped 6–160 m) |
  | R / T | Turn / tip the block |
  | M | Mirror mode on or off |
  | Ctrl+Z / Ctrl+Y (or Ctrl+Shift+Z) | Undo / redo |
  | F | Test flight |
  | B or Esc | Leave the shipyard (the World handles these) |

  While a `LineEdit` has focus, W A S D don't orbit.
- **Aiming:** a ray from `camera.project_ray_origin/normal(point)` goes through `grid.raycast`. A hit places at `cell + normal` and removes at `cell`. A miss that points down places on the grid plane y = −0.5, in the cell above it: `(roundi(x), 0, roundi(z))`.
- **Panels** (`UiTheme`):
  - Left (width 340):
    - The caption "Shipyard".
    - Blocks by group, each a button such as `Frame   60 kg`, with the selected one pressed.
    - The selected block's name, `60 kg · 100 hit points`, and its "about".
    - A paint row: 8 swatches (`e9dfc9, c0392b, 2f5d8a, 2e7d4f, e8a948, 3d3a3f, 7d5a6b, f2ead8`) and "Default", which call `design.set_paint(selected, …)`.
  - Right:
    - The stats (`ShipStats.describe()`, monospace).
    - Warnings, one per line in `UiTheme.WARNING`, or `No warnings. She should fly.` in dim text.
    - The legend `● Weight (centre of mass)   ● Lift (centre of lift)`, in the marker colours.
  - Bottom:
    - Buttons: `Test flight (F)`, `Launch`, `Undo`, `Redo`, `Mirror: off (M)` (or on), `Blueprints`, `Close (B)`.
    - The caption: `Left click place · Right click remove · Right-drag or WASD orbit · Wheel zoom · R turn · T tip`.
  - Blueprints panel (toggled):
    - A name `LineEdit` (text `blueprint_name`) and `Save`.
    - `Starter ship`, then a button per file in `Blueprint.list(blueprint_dir)`, showing the file name without `.skyship.json`.
    - `Open folder`: makes the folder, then `OS.shell_open(ProjectSettings.globalize_path(blueprint_dir))`.
    - A note label.
- **Test flight and Launch** need a helm. Without one they're disabled, and the note says `Every ship needs a helm.` Pressing them emits the request with `design.grid.copy()` and sets the note `Launching…`.
- **Saving:**
  - A design without a helm isn't saved: the note is `Every ship needs a helm.`
  - If the file exists and this isn't a second press for the same name, the note is `"%s" already exists. Save again to replace it.`
  - Otherwise the note is `Saved "%s".` (the cleaned name), and `blueprint_name` becomes that name.
  - A disk error gives `Couldn't save "%s" (%s).` with `error_string`.
- **Loading:** a good file becomes `design.replace(grid)` (undoable), with `blueprint_name` = its name and the note `Loaded "%s".`. A bad file sets the note to the problem and changes nothing. `Starter ship` replaces the design with `StarterShip.build()`.

World rules:
- `open_shipyard()`:
  - If the shipyard is open, do nothing. If you're not `at_dock()`, the HUD says `The shipyard is at the dock.`
  - Otherwise create `design` the first time as `ShipDesign.new(ship.grid)`.
  - Add `Shipyard.new(design, START.y)` on `CanvasLayer` layer 3, and connect its requests to `test_flight` and `launch`.
  - Set `player.enabled = false`, hide the HUD, show the mouse, and set `get_viewport().disable_3d = true`.
- `close_shipyard()` undoes all of that. The design is kept.
- `_unhandled_input`:
  - `shipyard`: ignored while paused. Otherwise it closes the shipyard if open, ends a test flight if on one, and opens the shipyard if not.
  - `pause` while the shipyard is open closes it, and the pause menu doesn't open.
- When your own ship arrives (captain = you): if it's a test ship, close the shipyard; if it's a new ship, close it too.
- When your test ship is removed and you've boarded back, open the shipyard again, skipping the dock check.
- The HUD sets `at_dock` each frame. When you're at the dock and not at a station, not on a test flight, with no E prompt, the prompt reads `B   Shipyard`.

- [ ] **Step 1: Write the failing tests** (`tests/test_shipyard.gd`, in a solo world, with `blueprint_dir` set to a temp folder):
  - `test_b_opens_the_shipyard_at_the_dock`: the shipyard is open, `player.enabled` is false, the HUD is hidden, and the design has the starter ship's 287 blocks. `stats_text()` starts with `Blocks     287 of 4000`, and `warnings_text()` is `No warnings. She should fly.`
  - `test_the_shipyard_is_only_at_the_dock`:
    - Move the ship 2 km away (set its `global_position`, then `reset_physics_interpolation`), and press B.
    - No shipyard opens, and the HUD message is `The shipyard is at the dock.`
  - `test_b_or_esc_closes_the_shipyard`: after either, `player.enabled` is true and the pause menu is hidden.
  - `test_stats_and_warnings_follow_the_design`: removing the helm puts `Every ship needs a helm.` in the warnings and disables `Test flight`. Undo brings them back.
  - `test_clicking_places_on_the_face_you_point_at`:
    - A one-frame design at the origin: `view.look_from(Vector3(0, 10, 0.001), Vector3.ZERO)`.
    - Left click at the view's centre places the selected block at `(0, 1, 0)` with `rotation`. Right click there removes it again.
    - On an empty design, left click places on the grid at `(0, 0, 0)`.
  - `test_keys_turn_tip_mirror_undo_and_redo`:
    - R sets `rotation = Blocks.turned(0)`, and T tips it.
    - M sets `design.mirror`, and the button reads `Mirror: on (M)`.
    - Ctrl+Z undoes and Ctrl+Y redoes.
  - `test_saving_and_loading_blueprints`:
    - Save as "Test Ship": the file exists, and the list shows `Test Ship`.
    - Remove 5 blocks, then load "Test Ship": the block count is back.
    - Undo gives the 5-fewer design again.
  - `test_saving_over_a_blueprint_asks_first`: the second save with the same name, after changes, notes `"Test Ship" already exists. Save again to replace it.` and leaves the file unchanged. The third save replaces it.
  - `test_a_bad_blueprint_file_says_what_is_wrong`: a file with `{"format": "skywright-blueprint", "version": 1, "name": "X", "blocks": [[0, 0, 0, "wing", 0]]}` notes `Block 1 is an unknown type, "wing".`, and the design is unchanged.
  - `test_painting_a_block_type`: select balloon and click the red swatch. `design.grid.paint["balloon"]` is red, and the view's mesh has red vertex colours.
  - `test_a_test_flight_and_back_keeps_the_design`:
    - Place a block, then press `Test flight`. You're aboard a test ship at its helm, with the shipyard closed.
    - Press B. You're aboard the starter, the shipyard is open again, and the design still has the placed block.
  - `test_launch_sails_the_design`: Launch leaves you at the helm of your new ship, with the shipyard closed and the starter gone.
  - `test_the_design_is_kept_between_visits`: place a block, close, and open again. The block is still there.
  - In `tests/test_project.gd`: the new actions and their keys.
- [ ] **Step 2: Run `./run_tests.sh shipyard`.** Expected: the tests fail.
- [ ] **Step 3: Implement** `BuildView`, `Shipyard`, the `World` routing, the HUD hint, and the actions.
- [ ] **Step 4: Run the whole suite, then open the shipyard by hand** (`godot --path . -- --solo`, B): build, turn and mirror blocks, look at the markers, test fly and come back, then save and load.
- [ ] **Step 5: Commit** "Build ships in a shipyard at the dock, with live stats, markers, warnings and blueprints".

### Task 9: A designed ship flies as its stats say; README, spec, Build Log

Build-log item: "Tests: blueprint round trip and stat calculations" (and the stage's promise).

**Files:**
- Create: `tests/test_designed_ship.gd`
- Modify: `README.md`, `docs/superpowers/specs/2026-09-29-skywright-design.md`

- [ ] **Step 1: Write the tests** (`tests/test_designed_ship.gd`). `skiff()` is built entirely through `ShipDesign` with mirror on:
  - a 3 × 9 deck on a frame keel, with two iron blocks in the keel;
  - an engine, two propellers at x = ±2 at the stern, and a rudder;
  - a helm with a deck behind it;
  - posts, and a 3 × 9 × 2 balloon envelope.

  Before it flies, it's saved as a blueprint, loaded back, and its stats are taken at 880 m.
  - `test_a_designed_ship_round_trips_through_a_blueprint`: same blocks, rotations and paint. The stats warn only about what the design lacks (nothing, for the skiff).
  - `test_a_designed_ship_floats_and_balances_as_her_stats_say`: launched at her `float_altitude + 40` in still air and simulated 180 s, she ends within 20 m of `float_altitude`. Her list and pitch are within 0.5° of `stats.list` and `−stats.bow_down`.
  - `test_a_designed_ship_reaches_her_top_speed`: launched at `float_altitude` at full throttle in still air for 240 s, her speed is within 10% of `ShipStats.of(grid, y).top_speed` at the height she's at.
  - `test_a_lopsided_design_lists_as_warned`: the skiff with two iron blocks added at x = 2 warns `Lists N° to starboard.` and settles within 0.5° of `stats.list`.
- [ ] **Step 2: Run them.** Fix the design (not the tolerances) if the skiff doesn't float between 400 m and 1,500 m.
- [ ] **Step 3: Update the README:**
  - The status: stage 4 of 10.
  - Controls: B for the shipyard, and a shipyard controls table.
  - "The shipyard": the dock, test flights and B, launching, what the markers and warnings mean.
  - "Blueprints": where the files live (`~/.local/share/godot/app_userdata/Skywright/blueprints` on Linux, `%APPDATA%\Godot\app_userdata\Skywright\blueprints` on Windows), sharing by copying files, and "Open folder".
  - "Play with friends": everyone can launch their own ship at their own slipway.
  - The layout gains `src/builder/`.
- [ ] **Step 4: Update the spec:**
  - The status line.
  - §3.3: the shipyard at the dock, test flights, and mirror mode.
  - §3.8: one ship and one test flight each; leavers' ships go.
  - §4.4: rotations are Godot's orthogonal index; propellers and rudders act along their facing; the mesh has one surface per material.
  - §4.6: protocol 3 entries, launches and removals, and the block bytes.
  - §4.10: paint as type -> hex; whole-number floats; the 1 MB limit.
  - §7: invalid blueprints name the first problem (link this plan's list).
  - §9: decisions.
- [ ] **Step 5: Run the whole suite three times.** Expected: it passes every time.
- [ ] **Step 6: Commit** "Test that a designed ship flies as her stats say; update README and spec for stage 4".

---

## Playtest checklist

1. **Building:** at the dock, press B. Place, remove, turn (R), tip (T) and mirror (M) blocks, and undo and redo. Does aiming land where you point from every angle? Is orbiting comfortable on the touchpad, both right-drag and WASD?
2. **Readouts:** make a ship lopsided, nose-heavy, too heavy, and one with lift stones only. Do the warnings and markers make sense before you fly?
3. **Test flight:** press F. Are you at the helm at once? Fly, then press B. Is the return instant, with the shipyard and your design just as you left them?
4. **Lopsided test flight:** does a ship that warns "Lists 8° to port" list about that much?
5. **Launch:** launch a design and sail it away. Is the old ship gone, and does a friend aboard come along?
6. **Blueprints:** save, use "Open folder", copy the file to another machine and load it there. Does a hand-broken file say what's wrong?
7. **Looks:** does the envelope read as cloth? Can you tell which way propellers, rudders and cannons face? Does paint look good in daylight and at dusk?
8. **Co-op:** two players each launch a ship at the dock and fly alongside each other. Does each see the other's ship smoothly?
9. **Big ships:** build or load a ship near 4,000 blocks. Does editing stay smooth, and does flying hold 60 fps on the Radeon 680M?
