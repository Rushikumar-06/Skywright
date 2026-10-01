# Stage 6: Damage and Combat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ships fight. Every block has hit points: shots break planks, holes open in decks, and a ship flies on whatever is left of her. Sections cut off from the helm fall away as wrecks, and a severed envelope floats off. Players man cannons and lob arcing round shot, chain shot, shells and harpoons. Crews repair with spares, rebuild lost blocks, patch balloons and put out fires. Pirate ships with AI captains chase, circle and fire broadsides. Wrecks can be salvaged for spares. A ship that sinks into the Roil is lost, and can be rebuilt from her blueprint at any shipyard.

**Architecture:**
- **Damage is data.** `Damage` (static, no nodes) holds the ammunition table and every rule: what a shot does along its path, what a blast does, how fire burns and spreads, what one repair does, and how a grid splits into the piece that stays and the pieces that break away. Its tests need no physics.
- **A ship rebuilds itself from its grid.** `Ship.damage(changes)` sets hit points and removes dead blocks; once per frame the ship rebuilds its mass, collision boxes, forces, mesh, interior hull and stations from the grid. A ship whose helm is gone is a wreck (`helm == null`): it can't be steered, and nobody is put aboard it. Every ship keeps its `blueprint` (the design at full hit points), which repairs rebuild from and a lost ship is rebuilt from.
- **The server decides every hit.** `WorldSync.fire` launches a shot and tells everyone its origin, velocity and time. `Projectiles` simulates every shot's arc from those on every machine (clients draw them on the same 100 ms delay as ships). Only the server casts rays, finds the block a shot enters (`ShipGrid.raycast` from the hit point, not shape indices), applies `Damage`, splits the ship, and sends the changed hit points to everyone. Crew are hit when a shot passes near where they last reported standing.
- **Stations are nodes on the ship.** The helm is joined by a `Cannon` node per cannon block. Both work the same way: a client asks, the server grants within reach, and a destroyed block lets its user go.
- **Pirates are ships with a captain node.** A pirate is an ordinary ship built from `PirateShip.build()`, flagged `pirate`, with a server-only `PirateCaptain` that steers through the helm's autopilot and fires cannons through the same server call players use. The server raids crewed ships away from towns.
- **One server tick a second wears ships.** `WorldSync._wear()` burns fires, refills spares at docks, grinds ships in the Roil, loses ships below 0 m, and clears away old wrecks and far pirates.

**Tech Stack:** Godot 4.7.2 (standard build, `~/.local/bin/godot`), statically typed GDScript, Jolt, ENet through SceneMultiplayer, `ImmediateMesh` (the aiming arc), `MultiMesh` (flames), `RandomNumberGenerator`, and the existing headless test runner.

**Spec:** `docs/superpowers/specs/2026-09-29-skywright-design.md` (stage 6 in §5; ships, damage and break-apart in §3.3 and §4.4; threats and combat in §3.5; crew and hitboxes in §4.5; networking in §4.6; wrecks in §4.7; budgets in §4.11).

**Where:** branch `stage-6-damage-combat`, in the worktree `../game-stage-6`, branched from `stage-5-sky-world`.

## Global Constraints

- Godot 4.7.2 standard build, and GDScript with static types everywhere. No addons or other dependencies. No external art: everything is generated in code (spec §3.9).
- The server is authoritative for ships, blocks, damage, projectiles, fires, repairs, salvage and pirates. A client only asks. Everything a peer receives from another machine is checked.
- Protocol version 5. Channel 0 is reliable for events, channel 1 unreliable-ordered for ship snapshots, channel 2 unreliable-ordered for crew and helm keys. Every combat event goes on channel 0.
- Network budget: at most 64 KB/s down per client (spec §4.6). Combat adds only events; ship snapshots stay as they are.
- Every number that decides how ships fly stays in `src/ship/tuning.gd`. Damage, ammunition, fire, repair, spares and salvage numbers live in `Damage`; cannon numbers in `Cannon`; shot and rope numbers in `Projectiles`; AI numbers in `PirateCaptain`; raid and upkeep numbers in `WorldSync`.
- Performance target: 60 fps at 1080p on medium settings on the Radeon 680M (spec §4.11). A ship rebuilds at most once a frame, however many hits it takes.
- Randomness on the server comes from `WorldSync.rng` (a `RandomNumberGenerator`), so tests can seed it. Nothing uses the global random functions.
- New messages are the exact strings in this plan.
- Tests use ports 20000–29999. `NetCase` worlds use the fixed seed `NetCase.SEED`, and `NetCase` sessions have pirates off (`Session.pirates = false`) unless a test turns them on, so existing tests never meet a raid.
- Deliberate shortcuts carry a `ponytail:` comment naming the ceiling and the upgrade path.
- Commit messages have no `Co-Authored-By` line or other trailers (user rule).

## Review Focus

1. **Breaking apart** (a cut across the keel, a cut through the helm, cuts that leave splinters, the envelope's posts shot through, a ship spinning when she breaks): the part with the helm stays the ship, every other piece is a wreck with its own mass and the velocity it had, splinters vanish, and every machine agrees. Tests: `test_split_finds_every_piece` (Task 1), `test_the_part_with_the_helm_stays_the_ship`, `test_broken_off_sections_keep_their_velocity`, `test_a_ship_without_a_helm_is_a_wreck`, `test_a_severed_balloon_floats_away` (Task 3).
2. **The server decides** (junk change lists from a modified host, a guest firing a cannon they don't man, repairing from 10 m away or too fast, salvaging from a kilometre off): junk is refused and nothing changes. Tests: `test_a_junk_change_list_is_refused` (Task 2), `test_the_server_ignores_fire_from_someone_not_at_the_cannon` (Task 5), `test_the_server_ignores_repairs_out_of_reach` (Task 6), `test_the_server_ignores_salvage_from_afar` (Task 8).
3. **Stations under fire** (the helm shot away under the pilot, a manned cannon destroyed, a gunner knocked down by a shell): whoever was using it is let go at once on every machine, and nobody is left steering or aiming something that isn't there. Tests: `test_losing_the_helm_lets_the_pilot_go` (Task 2), `test_a_shell_bursts_and_knocks_down_crew` (Task 4), `test_a_destroyed_cannon_lets_its_gunner_go`, `test_a_knocked_out_gunner_leaves_the_cannon` (Task 5).
4. **Shots on every machine** (a shot through a hole, a shot fired straight up, the same shot drawn by host and guest, a broadside of every ammunition): hits land on the block the shot flies into, never on the firing ship, and host and guest end with the same blocks. Tests: `test_a_shot_hits_the_block_it_flies_into`, `test_a_cannon_never_hits_its_own_ship`, `test_every_machine_draws_the_same_arc` (Task 4), `test_host_and_guest_agree_after_a_broadside` (Task 10).
5. **Losing a ship and rebuilding** (your ship sinks with you aboard, every ship is gone, a guest's own ship sinks): you always end up standing somewhere, the lost ship's blueprint is what the shipyard rebuilds, and it comes back whole. Tests: `test_a_ship_below_the_roil_is_lost_and_its_crew_rescued`, `test_nobody_falls_forever_when_every_ship_is_gone`, `test_rebuilding_a_lost_ship_launches_her_blueprint_whole` (Task 9).

---

## What prototyping settled before this plan

| Question | Answer |
|---|---|
| How does a hit find its block? | `intersect_ray` against a ship returns the ship as `collider`, but `shape` is the index of a merged box (0 for a hit on the starter ship's starboard side), which covers many cells. Moving the hit into ship space and walking the grid (`ShipGrid.raycast` from 1 cm before the hit point, along the shot) gave the right cell, `(2, 0, 1)`, entered through its `+X` face. So hits never use shape indices. Ray queries don't hit areas or start inside shapes by default. |
| What does a rebuild cost? | For the 287-block starter ship: mesh 2.9 ms, merged boxes 0.2 ms, drag zones and mass 0.6 ms, flood fill 0.3 ms, swapping the body's 22 shapes 0.4 ms and the interior's 1.0 ms. At 503 blocks: 3.8, 0.3, 1.1 and 0.6 ms; at 1,007: 6.1, 0.6, 2.2, 1.2; at 4,031: 23.2, 2.5, 9.0, 5.0. The mesh dominates. A ship of up to about 500 blocks rebuilds whole in under 8 ms, so this stage keeps one mesh and rebuilds at most once a frame (see "departs"). |
| Splitting a body in flight | Changing a Jolt body's mass, centre of mass, inertia and shapes while it moved at 10 m/s and spun at 0.5 rad/s: it didn't jump (0.28 m in two ticks, as 10 m/s should) and kept its velocity to within 0.03 m/s. A new body given `linear_velocity` before `add_child` kept it (6.41 m/s, gravity aside). The two bodies, touching face to face at the cut, didn't push each other apart. |
| The interior losing blocks | Freeing the interior hull's shapes and adding new ones while a crew member stood on the removed deck: no errors, and the crew member fell through (y 1.40 → 0.21 in 0.5 s). The interior stays and only its hull's shapes change, because the crew are its children. |
| Cannons on the starter ship | Two cannons (+360 kg) in the rails at z 0 made her bow-heavy by 0.35° (the flight test allows 0.3°); at z 1 by 0.04°, at z 2 bow-up 0.28°. Six more balloon cells, `(−1…1, 9, −6)` and `(−1…1, 9, 8)`, bring her float height back to 881 m (from 778 m). She is 9.29 t and 293 blocks. |
| A pirate ship | The starter ship with four cannons at `(±2, 1, −1)` and `(±2, 1, 2)`, the same six extra balloons, and a ridge of 11 balloons at `(0, 11, −4…6)`: 9.74 t, 304 blocks, floats at 962 m, bow down 0.33°, 20.2 m/s. Cannons at z −2 and 1 made her 0.93° bow down. |
| Circling on the autopilot | A starter ship steered only by setting the helm's autopilot heading every 0.5 s (toward the target beyond 1.9 × the orbit, else along the tangent bent inward by `0.8 × (d − 260) / 260`): from 700 m away it closed at up to 16 m/s and settled into a circle 323–363 m from the target, holding its altitude within 3 m, for three minutes. The orbit radius is a bias, not what it holds. It turns at about 6°/s, so a tighter circle isn't possible for this hull. |
| Measuring the network | `ENetConnection.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)` exists in 4.7.2, through `ENetMultiplayerPeer.get_host()`, for the budget test. |

## Where this stage departs from the spec

The spec is updated to match in Task 10.

| Spec | This stage | Why |
|---|---|---|
| §3.2, §3.6: money, inventory and parts; §3.4 "spare materials" | Each ship carries `spares`, 0–40, filled free of charge at any town's dock. Repairs use them, and salvage gives them. | Money and inventory arrive in stage 7, which can put a price on spares. |
| §3.5: "rebuild the ship at a shipyard for a price" | Rebuilding is free: the shipyard opens on the lost ship's blueprint and Launch rebuilds her. | Stage 7 sets the price. |
| §3.5: salvage and loot | Salvage gives spares. A world wreck gives 12 once per session (the host's world remembers); a broken-off wreck gives one spare per 10 blocks and is broken up. | Loot beyond spares needs inventory (stage 7). Saving what was salvaged comes with saves (stage 7). |
| §3.4: stations "helm, cannon, engine and repair"; AI crew | Helm and cannons are stations. Repair is a tool always in hand (hold R aimed at a block). No engine station and no AI crew. | Hired crew are stage 7. An engine station has nothing to do until fuel exists (stage 7). |
| §4.5: a main-world `Area3D` hitbox per crew member; server-side crew bodies in stage 6 | The server tests shots against where each player last reported standing (0.7 m from the shot's path, or inside a shell's blast). Any hit knocks you down for 5 s; you come to at a bunk (or by the helm). There is no health bar. | No extra bodies in either world, and crew still don't collide with each other. |
| §4.4: 16³ render sections, "≤ 4 ms per 16³ section" | One mesh per ship, rebuilt whole at most once a frame when blocks go or come back. Hit points changing alone don't redraw. | Prototyping measured 2.9 ms for the starter ship and 3.8 ms at 500 blocks. Split into sections when big ships stutter under fire (ponytail in `ShipMesh`). |
| §4.4: break-apart | As the spec, plus: when no piece has a helm, the largest stays the ship (now a wreck); pieces under 4 blocks vanish as splinters; ties go to the piece with the smallest cell, so every machine agrees. | Splinters would be dozens of tiny bodies. |
| §4.6: events "blocks destroyed, ship split" | `_blocks_changed` carries every hit-point change (hits, fire, the Roil, repairs; 0 is destroyed). A split is one `_blocks_changed` followed by `_ship_added` for each wreck. | One path for every change, and wrecks are ordinary ships to the network. |
| §3.5: pirates | One pirate design (`PirateShip`, from the starter ship's hull), raiding crewed ships away from towns. Pirate forts and bigger designs come with stage 8's threats. Pirates' guns are fired by the captain; there's no visible pirate crew, and pirates never board (§3.10). Pirates don't steer around islands. | Enough to fight; stage 8 grows the threats. |
| §3.5: ammunition | Cannons never run out of ammunition. | Ammunition as cargo needs inventory (stage 7). |
| (not in the spec) | Repairs can't rebuild a lost helm or cannon; that needs a shipyard. | A rebuilt helm would un-wreck a ship and re-wire stations mid-fight. |
| (not in the spec) | Crew standing on a section that breaks away fall off it, and can land on it. | The usual stepping-off rule, with nothing new. |
| (not in the spec) | The starter ship carries two cannons and six more balloon cells. | You can fight the first pirate you meet. |
| (not in the spec) | Other players don't see where a cannon is aimed; barrels are drawn fixed. | The shot shows where it went. |
| §4.7: "Wrecks will be made from pirate blueprints when pirates arrive" | Done: world wrecks are damaged pirate ships. | |

## Protocol (version 5)

| RPC | Change |
|---|---|
| `Session.PROTOCOL_VERSION` | 5 |
| `WorldSync._world(time, entries, salvaged)` | Adds `salvaged`: an `Array` of the world-wreck indices already salvaged this session. |
| Ship entries (in `_world` and `_ship_added`) | `[id, blocks, paint, transform, pilot, captain, test, blueprint, pirate, spares]`: adds the blueprint's bytes (`ShipGrid.to_bytes`), whether it's a pirate (bool) and its spares (int, 0–40). |
| `WorldSync._ship_removed(id, successor, lost)` | Adds `lost` (bool): the Roil took her. |
| `_blocks_changed(id, changes)` | New, server → clients: `Damage.pack`ed hit points; 0 is destroyed, and a change for an empty cell restores the blueprint's block there. |
| `_fires(id, cells)` | New, server → clients: every burning cell of the ship, 3 bytes each (`x + 64`, `y + 64`, `z + 64`). |
| `_spares(id, count)` | New, server → clients. |
| `_fired(shot, ammo, origin, velocity, time, ship_id)` | New, server → clients: `ammo` is an index into `Damage.AMMO`'s keys; `ship_id` is the firing ship. |
| `_hit(shot, point, time)` | New, server → clients: the shot ends at `point` at server time `time`. |
| `_tether(rope, a_id, a_cell, b_id, b_cell, length)`, `_untether(rope)` | New, server → clients: a harpoon's rope. |
| `_man(ship_id, cell, on)` | New, client → server: take or leave the cannon at `cell`. |
| `_gunner(ship_id, cell, peer)` | New, server → clients: who mans that cannon (0 for nobody). |
| `_fire(ship_id, cell, yaw, pitch, ammo)` | New, client → server: fire the cannon you man, with this aim and ammunition. |
| `_repair(ship_id, cell)` | New, client → server: one repair action aimed at `cell`. |
| `_salvage(kind, index)` | New, client → server: `kind` is `"site"` (a world wreck, `index` into `WorldGen.wrecks`) or `"ship"` (a wreck ship's id). |
| `_salvaged(index)` | New, server → clients: that world wreck is empty now. |
| `_salvage_result(spares)` | New, server → the salvager: spares gained, or 0 for "nothing left", −1 for "no room". |
| `_knocked_out()` | New, server → the one player hit. |

Budget: a shot is one `_fired` (about 70 bytes) and one `_hit`; a hit's changes are 5 bytes a block; fires are sent at most once a second per burning ship. A broadside of four is under 1 KB.

---

## File structure

| File | Responsibility |
|---|---|
| `src/ship/damage.gd` | `Damage`: ammunition, shots, blasts, fire, repairs, the Roil's wear, splitting, packing changes |
| `src/ship/ship_grid.gd` | `cells_along` (the voxel walk `raycast` now uses), `whole()` |
| `src/ship/ship.gd` | `blueprint`, `spares`, `pirate`, `fires`, `born`, `lost`, `cannons`; `damage`, `take_cells`, `rebuild`, `is_wreck`, `condition`, `station_near`, `respawn_spot`, flames |
| `src/ship/ship_mesh.gd` | Its ponytail note: one mesh, rebuilt whole |
| `src/ship/starter_ship.gd` | Two cannons and six balloon cells |
| `src/crew/ship_interior.gd` | `reshape` |
| `src/combat/projectiles.gd` | `Projectiles`: shots on every machine, the server's hit tests, bursts, harpoon ropes, the arc and aiming maths |
| `src/combat/cannon.gd` | `Cannon`: the cannon station, its aim, ammunition and reload |
| `src/ai/pirate_ship.gd` | `PirateShip`: the pirate blueprint |
| `src/ai/pirate_captain.gd` | `PirateCaptain`: chase, circle, fire |
| `src/net/world_sync.gd` | Damage, splits, shots, stations, repairs, spares, fires, salvage, raids, the Roil, losses, knock-downs; the protocol above |
| `src/net/session.gd` | Protocol 5, `pirates` |
| `src/crew/player_controller.gd` | Cannons as stations, aiming and firing, ammunition, the aiming arc, holding R to repair |
| `src/ui/hud.gd` | Cannon readout, hull and spares lines, repair and salvage prompts |
| `src/ui/map_view.gd` | Pirates in red |
| `src/world/world.gd` | `Projectiles`, knock-downs, `recover`, salvage, lost ships, the Roil rescue's last resort |
| `src/world/dock.gd` | `quay_spot` |
| `src/world/sites.gd` | Wrecks from pirate ships; `wreck_center` |
| `project.godot` | Actions: `fire` (left mouse), `ammo` Q, `repair` R |
| `tests/net_case.gd` | Pirates off; `open_sky` |
| `tests/test_damage.gd`, `test_ship_damage.gd`, `test_break_apart.gd`, `test_projectiles.gd`, `test_cannons.gd`, `test_repairs.gd`, `test_pirates.gd`, `test_salvage.gd`, `test_sinking.gd`, `test_combat_net.gd` | New tests |
| `README.md`, spec | Stage 6 status, combat, controls |

---

### Task 1: The damage rules

Build-log item s06-08: "Tests: damage and break-apart logic".

**Files:**
- Create: `src/ship/damage.gd`, `tests/test_damage.gd`
- Modify: `src/ship/ship_grid.gd`, `tests/test_ship_grid.gd`

**Interfaces:**
- `ShipGrid`:
  - `func cells_along(from: Vector3, direction: Vector3, max_distance := 200.0, count := 1) -> Array[Dictionary]`: the first `count` blocks a ray enters (ladders included), in order, each `{"cell": Vector3i, "normal": Vector3i}`. `raycast` becomes `cells_along(from, direction, max_distance, 1)`'s first entry, or `{}`.
  - `func whole() -> ShipGrid`: a copy at full hit points, with paint.
- Produces (`class_name Damage`, all static, no nodes):
  - `const AMMO := {"round": {"name": "Round shot", "speed": 120.0, "damage": 160.0, "reach": 4, "cloth": 1.0, "blast": 0.0, "blast_damage": 0.0}, "chain": {"name": "Chain shot", "speed": 90.0, "damage": 60.0, "reach": 8, "cloth": 4.0, "blast": 0.0, "blast_damage": 0.0}, "shell": {"name": "Shell", "speed": 100.0, "damage": 40.0, "reach": 1, "cloth": 1.0, "blast": 3.0, "blast_damage": 90.0}, "harpoon": {"name": "Harpoon", "speed": 80.0, "damage": 20.0, "reach": 1, "cloth": 1.0, "blast": 0.0, "blast_damage": 0.0}}`. The keys' order is the ammunition index on the wire.
  - `const CLOTH := ["balloon", "sail"]`, `const FLAMMABLE := ["wood", "cloth"]` (materials), `const NOT_REBUILT := ["helm", "cannon"]`.
  - `const DEBRIS := 4` (pieces smaller than this vanish), `const BYTES_PER_CHANGE := 5`.
  - `const FIRE_DAMAGE := 5`, `const FIRE_SPREAD := 0.1`, `const FIRE_TIME := 30.0`, `const FIRE_CHANCE := 0.25`.
  - `const REPAIR_STEP := 25`, `const REPAIR_EVERY := 0.25`, `const REPAIR_REACH := 6.0` (a boathook's reach: the envelope can be patched from the deck), `const SPARES_MAX := 40`.
  - `const ROIL_DAMAGE := 10`.
  - `const SALVAGE_SPARES := 12`, `const SALVAGE_REACH := 4.0`, `const SITE_REACH := 14.0`.
  - `static func shot(grid: ShipGrid, from: Vector3, direction: Vector3, ammo: String) -> Dictionary` (cell → new hit points, 0 for destroyed; ship space).
  - `static func blast(grid: ShipGrid, center: Vector3, radius: float, damage: float) -> Dictionary`.
  - `static func apply(grid: ShipGrid, changes: Dictionary, blueprint: ShipGrid = null) -> bool`: true when a block was destroyed or restored.
  - `static func split(grid: ShipGrid) -> Dictionary`: `{"keep": Array[Vector3i], "wrecks": Array (of Array[Vector3i]), "debris": Array[Vector3i]}`.
  - `static func pack(changes: Dictionary) -> PackedByteArray` and `static func unpack(data: Variant) -> Variant` (a Dictionary, or null).
  - `static func flammable(type: String) -> bool`.
  - `static func ignite(grid: ShipGrid, fires: Dictionary, cells: Array, rng: RandomNumberGenerator) -> void`, `static func burn(grid: ShipGrid, fires: Dictionary, rng: RandomNumberGenerator) -> Dictionary`, `static func put_out(fires: Dictionary, cell: Vector3i) -> bool`.
  - `static func repair(grid: ShipGrid, blueprint: ShipGrid, cell: Vector3i) -> Dictionary`.
  - `static func roil(grid: ShipGrid, place: Transform3D) -> Dictionary`.

Rules:
- **A shot** walks `cells_along(from, direction, 200, reach)`. It carries `budget = damage`. At each cell, `factor = cloth` for balloons and sails, else 1; `dealt = minf(budget * factor, hp)`; the cell's hit points become `maxi(0, hp - roundi(dealt))`; `budget -= dealt / factor`. It stops when `budget <= 0.01` or after `reach` cells. So round shot breaks two planks (80 + 80) and stops in the third block; chain shot goes through up to eight balloon cells (7.5 of budget each) and spends the rest on the first solid block; a shell or harpoon hits one block.
- **A blast:** every block whose cell centre is within `radius` of `center` loses `roundi(damage * (1 - d / radius))`, down to 0. Blocks that lose nothing are left out.
- **Applying:** a change of 0 (or less) erases the block. A positive change sets its hit points, capped at the type's full hit points. A positive change for an empty cell restores the blueprint's block there (type and rotation) when the blueprint has one; otherwise it's ignored.
- **Splitting:** blocks connect through their six faces (ladders too; edges and corners don't). `keep` is the largest piece with a helm, or the largest piece when none has one. Ties go to the piece whose smallest cell (in `Vector3i` sort order) is smallest, so the answer doesn't depend on the order blocks were added. Every other piece of `DEBRIS` blocks or more is a wreck (listed by smallest cell); smaller pieces are `debris`.
- **Packing:** `u16` count, then per change (cells sorted) `x + 64`, `y + 64`, `z + 64`, hit points as `u16`. `unpack` returns null for anything that isn't a `PackedByteArray` of exactly `2 + count * 5` bytes, a count of 0 or over `ShipGrid.MAX_BLOCKS`, or a coordinate over 63.
- **Fire:** `fires` maps a burning cell to the seconds it has burned. `ignite` sets each flammable block among `cells` burning with `FIRE_CHANCE` (cells sorted, one `rng.randf()` each). `burn` is one second: in sorted order, a fire whose block is gone goes out; otherwise its block loses `FIRE_DAMAGE`, its time goes up by 1, it goes out at `FIRE_TIME`, and each of its six neighbours that is flammable and not burning catches with `FIRE_SPREAD` (one draw each, in the fixed face order). New fires start burning next second. It returns the hit-point changes. `put_out` removes every fire within one cell (each axis) of `cell`, and returns whether there were any.
- **One repair action** aimed at `cell`: if the block there is damaged, heal it by `REPAIR_STEP` (capped). Otherwise restore the nearest of the 26 cells around it (faces, then edges, then corners; ties by cell order) that the blueprint has, the grid doesn't, and isn't in `NOT_REBUILT`, at `mini(REPAIR_STEP, full)` hit points. Otherwise `{}`.
- **The Roil:** every block whose centre, placed by `place`, is below `Tuning.ROIL_ALTITUDE` loses `ROIL_DAMAGE`.

- [ ] **Step 1: Write the failing tests** (`tests/test_damage.gd`, plain `TestCase`):
  - `test_round_shot_breaks_planks_and_stops_at_iron`: a row deck, deck, iron, frame at x 0…3 (and a helm elsewhere): `shot` from `(-2, 0, 0)` along +X with round shot gives exactly `{(0,0,0): 0, (1,0,0): 0}`; with a row deck, iron it gives `{(0,0,0): 0, (1,0,0): 220}`.
  - `test_chain_shot_shreds_balloons`: four balloons then a frame: all four 0, the frame 70; the same with round shot destroys the four balloons (120) and does 40 to the frame.
  - `test_damage_only_reaches_so_far`: six balloons in a row, round shot: four destroyed, the fifth and sixth untouched.
  - `test_a_shell_bursts`: a 7 × 1 × 7 deck, `blast` at `(0, 0, 0)`, radius 3, 90: the centre is 0, a cell 2 m away is 50, cells 3 m or more away are absent, and the result is symmetric about both axes.
  - `test_applying_changes_removes_dead_blocks_and_restores_from_the_blueprint`: a change of 0 erases; 999 caps at full; a positive change for an empty cell restores the blueprint's type and rotation; without a blueprint it's ignored; the return value says whether blocks came or went.
  - `test_split_finds_every_piece`: a bar of 12 frames along z with a helm at z 11; removing z 4 leaves `keep` the helm's side and one wreck (z 0…3); also removing z 1 leaves z 0 as debris and z 2…3 as debris; a grid built in the reverse order gives the same answer.
  - `test_split_counts_faces_not_corners`: two blocks touching only at an edge are two pieces; a ladder joins what it touches.
  - `test_without_a_helm_the_largest_piece_stays`: two pieces of 6 and 9 blocks, no helm: `keep` is the 9; two pieces of 6: `keep` is the one with the smaller smallest cell.
  - `test_the_starter_ship_breaks_in_two_across_her_keel`: `StarterShip.build()` with every cell at z 0 removed: `keep` holds the helm and has no cell with z < 0; one wreck, every cell of it with z < 0; no debris.
  - `test_changes_pack_and_unpack`: a round trip of 50 random changes is equal; `PackedByteArray([1, 2, 3])`, a count of 0, a count of 4,001, a coordinate byte of 200 and a `String` all give null.
  - `test_fire_spreads_through_wood_and_burns_out`: rng seed 1; a row of five deck planks and an iron plate, fire at one end: after one `burn` that plank lost 5; after 40 burns no fire remains, no fire burned longer than `FIRE_TIME`, and the iron was never on fire.
  - `test_putting_out_a_fire`: fires at `(0,0,0)`, `(1,1,0)` and `(3,0,0)`: `put_out(fires, (0,0,0))` is true and leaves only `(3,0,0)`.
  - `test_one_repair_heals_or_rebuilds`: a plank at 20 heals to 45; a full plank next to a lost blueprint plank restores it at 25 with its rotation; with lost planks at a face and at a corner, the face one comes first; a lost cannon next to it is never restored; nothing to do gives `{}`.
  - `test_the_roil_wears_whats_under_it`: the starter ship placed with its origin at y 199: keel and deck cells lose 10, the rails and everything higher lose nothing.
  - `tests/test_ship_grid.gd`: `cells_along` returns blocks in order with the faces entered, stops at `count`, and `raycast` is unchanged; `whole()` restores hit points and keeps paint.
- [ ] **Step 2: Run `./run_tests.sh damage`.** Expected: the tests fail (`Damage` doesn't exist).
- [ ] **Step 3: Implement** `Damage`, `cells_along` and `whole`.
- [ ] **Step 4: Run the whole suite.** Expected: everything passes.
- [ ] **Step 5: Commit** "Add the damage rules: shots, blasts, fire, repairs and splitting a ship into pieces".

### Task 2: Ships take damage

Build-log item s06-01: "Block damage, destruction and hull breaches".

**Files:**
- Create: `tests/test_ship_damage.gd`
- Modify: `src/ship/ship.gd`, `src/ship/ship_mesh.gd`, `src/crew/ship_interior.gd`, `src/net/world_sync.gd`, `src/net/session.gd`, `src/ui/hud.gd`, `tests/test_fleet.gd`, `tests/test_session.gd`, `tests/test_world.gd`

**Interfaces:**
- Consumes: `Damage.apply`, `Damage.pack`, `Damage.unpack`, `ShipGrid.whole` (Task 1).
- Produces:
  - `Ship`: `var blueprint: ShipGrid` (set before adding it; `_ready` uses `grid.whole()` when null), `var spares := 0`, `var pirate := false`, `var born := 0.0` (server clock when added), `var lost := false`; `signal blocks_changed` (after each rebuild); `func damage(changes: Dictionary) -> bool` (applies, and rebuilds once at the end of the frame if blocks came or went; returns that); `func rebuild() -> void` (now); `func is_wreck() -> bool` (`helm == null`); `func condition() -> float` (hit points over the blueprint's full hit points, 0–1).
  - `ShipInterior.reshape(boxes: Array[AABB]) -> void`: replaces its hull's shapes, keeping the crew.
  - `WorldSync.damage_ship(ship: Ship, changes: Dictionary) -> void` (server): applies, tells everyone in the world, and removes a ship with no blocks left.
  - `WorldSync.add_ship(grid, at, captain := 0, test := false, pilot := 0, pirate := false) -> Ship`: sets `blueprint = grid.whole()`, `spares = Damage.SPARES_MAX` (0 for a pirate), and `born`.
  - `WorldSync._blocks_changed(id, changes)`; entries of 10 fields (see the protocol table); `Session.PROTOCOL_VERSION := 5`.
  - `Hud.readout` gains `Hull      %3d%%` (`roundi(condition() * 100)`) after the autopilot line, before `Anchored`.

Rules:
- `rebuild()` redoes, from the grid: mass, centre of mass and inertia; the body's `CollisionShape3D`s (old ones freed); the balloon, lift stone, propeller, rudder and sail lists; power; drag zones; bounds; the mesh (the old `MeshInstance3D` freed); the interior's hull (`reshape`); and the helm: if its cell is gone, `helm.leave(helm.pilot)`, autopilot off, the node freed, `helm = null`, and `anchored = false` (a wreck drifts). `_ready` builds through the same code, then makes the interior and the helm.
- `damage` defers `rebuild` with `call_deferred` and a pending flag, so any number of hits in one frame rebuild once. Hit-point changes alone don't rebuild.
- Every machine applies the same changes: the server in `damage_ship`, clients in `_blocks_changed` (unpacked and checked; junk is ignored with no warning).
- `ShipMesh`'s ponytail becomes: `# ponytail: one mesh for the whole ship, rebuilt whole when blocks go (2.9 ms for the starter ship, 3.8 ms at 500 blocks, 23 ms at 4,000). Split it into 16³ sections (spec §4.4) when big ships stutter under fire.`
- `_add_entry` checks the three new fields: the blueprint decodes (`ShipGrid.from_bytes`), `pirate` is a bool, and `spares` is an int from 0 to `Damage.SPARES_MAX`. Anything else leaves the ship out, as now.

- [ ] **Step 1: Write the failing tests** (`tests/test_ship_damage.gd`; plain `TestCase` with ships in the tree unless marked network, which `extends NetCase` in `tests/test_ship_damage_net.gd`):
  - `test_a_destroyed_block_is_gone_from_the_ship`: a starter ship, `damage({Vector3i(0, 0, 1): 0})`, a frame later: the cell is gone, the mass fell by 40 kg, the body's and the interior's shape counts both equal `merged_boxes().size()`, and a physics ray straight down through where it was hits 1 m lower (the keel) than a ray through its neighbour.
  - `test_a_hole_in_the_deck_drops_you_through`: a crew member standing at `(0, 1.4, 1)` on an anchored ship; the deck and keel cells under and around them destroyed: within 1 s their `position.y` is below 0.
  - `test_damage_changes_how_she_flies` (flight tests in calm air, each against an undamaged twin 200 m away): 20 balloon cells destroyed: after 30 s she's at least 20 m lower than the twin. The port propeller `(-2, 1, 7)` destroyed at full throttle: after 20 s her heading changed more than 10° while the twin's changed less than 1°. The engine destroyed: `max_thrust()` is 0 and after 20 s at full throttle she's under 1 m/s.
  - `test_many_hits_in_one_frame_rebuild_once`: five `damage` calls destroying blocks in the same frame emit `blocks_changed` exactly once.
  - `test_hit_points_alone_dont_rebuild`: `damage({cell: 10})` emits nothing and the mesh node is the same object.
  - `test_rebuilding_a_hit_ship_is_quick`: the median of ten `rebuild()` calls is under 15 ms for the starter ship and under 25 ms for a 500-block ship (the starter widened with deck and iron, as prototyped). Generous for this machine; it catches a tenfold regression.
  - Network: `test_losing_the_helm_lets_the_pilot_go`: after `sail_together()`, the guest takes the helm; the host destroys the helm cell: on both machines `ship.helm` is null and `is_wreck()`; the guest's `crew.station` is null and its HUD helm panel hidden; the host's ship is not anchored.
  - Network: `test_damage_reaches_the_guest`: the host's `damage_ship` destroys three cells and sets a fourth to 10: within 1 s the guest's copy lacks the three, has 10 at the fourth, and its mass equals the host's.
  - Network: `test_a_late_joiner_gets_the_damage_and_the_blueprint`: damage, then a late joiner (as in `test_a_late_joiner_boards_the_ship_where_it_is`): its copy has the damaged grid, and its `blueprint` is the whole starter ship.
  - Network: `test_a_junk_change_list_is_refused`: the guest's `sync._blocks_changed` called with an unknown ship id, `PackedByteArray([1, 2, 3])`, a count of 4,001 and a cell at x 100: nothing changes and no error is logged.
  - `tests/test_fleet.gd`: the junk-entry test builds 10-field entries, and adds entries with a junk blueprint, `pirate` as `1`, and `spares` of 41.
  - `tests/test_session.gd`: the protocol version is 5.
  - `tests/test_world.gd`: `test_the_helm_readout` expects `Hull      100%` after the autopilot line.
- [ ] **Step 2: Run `./run_tests.sh ship_damage`.** Expected: fail.
- [ ] **Step 3: Implement** `damage`, `rebuild`, `reshape`, `damage_ship`, `_blocks_changed`, the entries and protocol 5, and the hull line.
- [ ] **Step 4: Run the whole suite.** Expected: pass.
- [ ] **Step 5: Commit** "Let ships take damage: blocks break, holes open, and the ship flies on what's left".

### Task 3: Breaking apart

Build-log item s06-02: "Sections cut off from the ship break away as falling wrecks".

**Files:**
- Create: `tests/test_break_apart.gd`
- Modify: `src/ship/ship.gd`, `src/net/world_sync.gd`, `src/world/world.gd`, `src/crew/player_controller.gd`, `tests/test_launch.gd`

**Interfaces:**
- Consumes: `Damage.split` (Task 1), `damage_ship` (Task 2).
- Produces:
  - `Ship.take_cells(cells: Array) -> ShipGrid`: moves those blocks (with their hit points, and the ship's paint) into a new grid, and rebuilds this ship at the end of the frame.
  - `WorldSync`: `const WEAR_EVERY := 1.0`, `const WRECK_LIFETIME := 180.0`, `const MAX_WRECKS := 8`, `const FAR := 3000.0`; `func crewed_ships() -> Array[Ship]` (server: ships this machine's player or a remote player's last report is aboard); `func _wear() -> void` (server, every `WEAR_EVERY`: here, wreck upkeep; later tasks add to it).
  - `WorldSync.home_ship()` skips wrecks and pirates.

Rules:
- In `damage_ship`, after applying, when a block was destroyed: `Damage.split(ship.grid)`. Its `debris` cells join the changes (as 0) and leave the grid. Each wreck piece leaves through `take_cells`. The changes go out in one `_blocks_changed`; then each piece becomes a ship with `add_ship(piece, ship.global_transform, 0)` (captain 0, not a test, not a pirate, spares 0), its `linear_velocity` the ship's `point_velocity` at the piece's centre of mass in the world and its `angular_velocity` the ship's.
- A kept piece with no helm leaves the ship a wreck (Task 2 already lets the helm go).
- Wreck upkeep in `_wear`: a wreck (`is_wreck()` and captain 0) is removed when older than `WRECK_LIFETIME`, or further than `FAR` from every crewed ship. With more than `MAX_WRECKS` wrecks, the oldest go first.
- Nobody is put aboard a wreck by the game: `home_ship`, the World's choices of where to board next and `rescue`, and `PlayerController.ship_in_reach` all skip wrecks. Landing on a wreck's deck still puts you aboard it (you walk it; there's nothing to steer).
- Crew standing on a piece that breaks away fall, and go ashore by the usual rule.

- [ ] **Step 1: Write the failing tests** (`tests/test_break_apart.gd`, `extends NetCase`, in a solo world with the ship anchored unless the test says otherwise):
  - `test_the_part_with_the_helm_stays_the_ship`: `damage_ship` sets every cell at z 0 to 0: the ship still has its helm and no cell with z < 0; `sync.ships` has one more ship, whose cells are all z < 0, whose `global_transform` equals the ship's, which `is_wreck()`, captain 0; your crew (at the helm spot) is still aboard the ship.
  - `test_broken_off_sections_keep_their_velocity`: unanchored and calm, `linear_velocity` `(10, 0, 0)` and `angular_velocity` `(0, 0.3, 0)` set in the tick of the cut: right after it, the wreck's `linear_velocity` is within 0.05 m/s of `ship.point_velocity(wreck.global_transform * wreck.center_of_mass)` and its spin within 0.01 of the ship's.
  - `test_a_ship_without_a_helm_is_a_wreck`: destroying the helm cell alone adds no ship and leaves `is_wreck()`; with a second ship present, `home_ship()` is the other; a later cut through the wreck keeps its larger piece.
  - `test_a_severed_balloon_floats_away`: unanchored, calm, the four posts cut at y 5 (`(±2, 5, -4)` and `(±2, 5, 6)`): the envelope becomes a wreck; 10 s later it's at least 20 m higher and the ship at least 20 m lower than where they parted.
  - `test_splinters_vanish`: a ship built in the test, a 3 × 3 deck with a helm and a tail of three planks: destroying the tail's first plank adds no ship, and the other two planks are gone from `ship.grid` too.
  - `test_wrecks_are_cleared_away`: a wreck with `born` set 181 s back is removed at the next `_wear`; with nine wrecks, the oldest goes; one moved 3.5 km from every crewed ship goes.
  - `test_nobody_is_put_aboard_a_wreck`: your ship becomes a wreck while you're ashore; `rescue()` boards the host's other ship, not the wreck; `ship_in_reach()` next to the wreck is null.
  - Network: `test_the_guest_sees_the_ship_break`: after `sail_together()`, the host cuts at z 0: within 1 s the guest has the same ships, the same cells in each, and the wreck drawn within 0.5 m of the host's.
  - `tests/test_launch.gd`: `home_ship` ignores a wreck and a pirate (flags set by hand).
- [ ] **Step 2: Run `./run_tests.sh break_apart`.** Expected: fail.
- [ ] **Step 3: Implement** the split in `damage_ship`, `take_cells`, `_wear`'s wreck upkeep, `crewed_ships`, and the boarding rules.
- [ ] **Step 4: Run the whole suite.** Expected: pass.
- [ ] **Step 5: Commit** "Break ships apart: sections cut off from the helm fall away as wrecks".

### Task 4: Projectiles and ammunition

Build-log item s06-03: "Manned cannons with arcing shots: round shot, chain shot, shells, harpoons" (the shots; Task 5 mans the guns).

**Files:**
- Create: `src/combat/projectiles.gd`, `tests/test_projectiles.gd`
- Modify: `src/net/world_sync.gd`, `src/world/world.gd`, `src/world/dock.gd`, `src/ship/ship.gd`, `tests/net_case.gd`

**Interfaces:**
- Consumes: `Damage.shot`, `blast`, `AMMO` (Task 1); `damage_ship` (Task 2).
- Produces:
  - `class_name Projectiles extends Node3D`:
    - `signal hit(shot: Dictionary, collider: Object, point: Vector3, direction: Vector3)` and `signal crew_hit(shot: Dictionary, peer: int, point: Vector3)`: server only.
    - `const LIFETIME := 20.0`, `const CREW_HIT := 0.7`, `const TETHER_TIME := 45.0`, `const TETHER_STIFFNESS := 4000.0`, `const TETHER_MAX_FORCE := 40000.0`, `const TETHER_BREAK := 2.0`, `const TETHER_MIN := 15.0`.
    - `var shots: Dictionary` (id → `{"id", "ammo", "origin", "velocity", "time", "ship" (firing ship id), "cell" (the cell it was fired from), "ends" (server time it hit, INF until then), "node"}`), `var ropes: Dictionary` (id → `{"a": Ship, "a_cell", "b": Ship, "b_cell", "length", "since", "node"}`).
    - `func _init(world_sync: WorldSync, with_visuals: bool)`.
    - `static func position_at(origin: Vector3, velocity: Vector3, t: float) -> Vector3`: `origin + velocity * t + 0.5 * (0, −g, 0) * t²`, g from the project's gravity.
    - `static func arc(origin: Vector3, velocity: Vector3, seconds: float, steps: int) -> PackedVector3Array`: `steps + 1` points from `t = 0` to `seconds`.
    - `static func aim(offset: Vector3, speed: float) -> Vector3`: the unit direction of the low arc that reaches `offset` at `speed`, or `Vector3.ZERO` when it can't.
    - `func launch(id: int, ammo: String, origin: Vector3, velocity: Vector3, time: float, ship_id: int) -> void`, `func land(id: int, point: Vector3, time: float) -> void`.
    - `func tie(id: int, a: Ship, a_cell: Vector3i, b: Ship, b_cell: Vector3i, length: float) -> void`, `func untie(id: int) -> void`.
  - `WorldSync`: `var projectiles: Projectiles` (set by the World, like `wind`); `const KNOCKOUT_TIME := 5.0`; `const MUZZLE := 0.8`; `signal knocked_out` (on the machine of the player hit); `func fire(ship: Ship, cell: Vector3i, direction: Vector3, ammo: String) -> int` (server; ship-space unit direction; returns the shot id); `func crew_positions() -> Dictionary` (server: peer → world position, of everyone not knocked down); RPCs `_fired`, `_hit`, `_tether`, `_untether`, `_knocked_out`.
  - `Ship.release(peer: int) -> void`: lets `peer` go from any station they hold on this ship (here the helm; Task 5 adds cannons).
  - `Ship.respawn_spot() -> Vector3`: standing on the first bunk (sorted) with two empty cells above it (`Vector3(bunk + Vector3i.UP) + Vector3(0, 0.45, 0)`), else `crew_spawn(0)`.
  - `Dock.quay_spot(at: Vector3) -> Vector3`: `at + Vector3(0, -0.5, 37)`, standing on the quay behind slipway 0.
  - `World`: `var projectiles: Projectiles`; `func knock_out() -> void`; `func recover(prefer: Ship, at_bunk := false) -> Ship`: boards the first of `prefer`, your own ship and `home_ship()` that is still here and not a wreck (at its `respawn_spot()` when `at_bunk`, else `crew_spawn(my_slot())`) and returns it; with none, puts you ashore standing at `Dock.quay_spot` of the town nearest your world position and returns null.
  - `NetCase.open_sky(world: Node3D, altitude: float) -> Vector3`: frees the world's streamer (so no islands load) and returns the first of `(1000 k, altitude, 7000 − 1000 k)` and `(−1000 k, altitude, 7000 − 1000 k)`, k = 1…6, at least 1,500 m from every town's dock.

Rules:
- **Firing** (`WorldSync.fire`, server): `origin = ship.global_transform * (Vector3(cell) + direction * MUZZLE)`; `velocity = ship.point_velocity(origin) + ship.global_basis * direction * AMMO[ammo].speed` (a shot keeps its ship's motion). The id counts up from 1. Everyone in the world gets `_fired(id, ammo index, origin, velocity, time, ship id)`, with `time` the server clock.
- **Flight** on every machine, from launch data only. The server moves each shot at `sync.now() − time`; clients draw it at `sync.now() − WorldSync.DELAY − time`, the same delay ships are drawn at, so shots meet ships where they're drawn. A shot is a 0.2 m dark sphere (a harpoon a 0.1 × 0.1 × 1.2 m bar along its velocity). It ends after `LIFETIME` or below 0 m.
- **Hits** (server, each physics tick): a ray from the shot's last position to its new one (`intersect_ray`, excluding the firing ship's RID for the whole flight). Then each crew position within `CREW_HIT` of the segment, before the ray's hit point along it, is hit instead. The first hit ends the shot.
  - A ship: ship-space point `p` and direction `d`; changes `Damage.shot(grid, p - d * 0.01, d, ammo)`, then `damage_ship`. A shell also bursts: its changes applied, then `Damage.blast(grid, p, blast, blast_damage)` through `damage_ship` again. A harpoon whose hit block survives ties a rope from the firing cannon's cell to it (`length = maxf(TETHER_MIN, distance now)`), sent as `_tether`.
  - Anything else (islands, towns, the static wreck sites): the shot ends. A shell still bursts on crew.
  - Everyone gets `_hit(id, point, time)`. A client keeps drawing the shot until its drawn time reaches `time`, then shows the burst: a shell a 3 m emissive orange sphere fading over 0.4 s, round and chain shot a 1 m brown splinter puff over 0.3 s, a harpoon nothing.
- **Crew hits:** a player hit by a shot, or within a shell's `blast` of where it burst, is knocked down: the server calls `release(peer)` on every ship, marks them down for `KNOCKOUT_TIME` (shots pass them meanwhile), and sends `_knocked_out` to them (its own player: emits `knocked_out` directly).
- **Knocked down** (`World.knock_out`): the HUD says `You're hit! Back on your feet in 5 s.`, your controls stop, and after `KNOCKOUT_TIME` you come to with `recover(ship, true)` (aboard the ship you were on, at a bunk; ashore, `recover(null, true)`), your controls back unless the pause menu is open.
- **Ropes** (server, each physics tick): with world points `pa`, `pb` and `dist = |pb − pa|`, when `dist > length` pull both along the rope with `minf(TETHER_STIFFNESS * (dist − length), TETHER_MAX_FORCE)` (`apply_force` at the points). A rope goes (`_untether`) after `TETHER_TIME`, when stretched past `TETHER_BREAK * length`, or when either ship or either block is gone. Every machine draws it as a 0.08 m brown bar between the two blocks each frame.
- On a dedicated server `Projectiles` draws nothing.
- `ponytail:` notes: shots and ropes are one `MeshInstance3D` each (a `MultiMesh` if big battles cost draw calls); clients apply `_blocks_changed` when it arrives, up to `DELAY` before the shot is drawn arriving (queue changes by time if holes appearing early shows).

- [ ] **Step 1: Write the failing tests** (`tests/test_projectiles.gd`, `extends NetCase`; `AT := Vector3(0, 1900, 7000)`, above every island; ships anchored unless the test says otherwise):
  - `test_a_shot_follows_its_arc`: `position_at(Vector3.ZERO, Vector3(0, 0, -100), 2.0)` is `(0, -19.62, -200)` within 0.001; `arc(...)` has `steps + 1` points, the first the origin and the last `position_at(seconds)`.
  - `test_aim_finds_the_low_arc`: for offsets `(300, 20, 0)`, `(0, -50, 400)` and `(150, 0, 150)` at 120 m/s, the arc from `aim` passes within 0.5 m of the offset and its elevation is under 45°; `(3000, 0, 0)` at 120 m/s gives `Vector3.ZERO`; straight down works.
  - `test_a_shot_hits_the_block_it_flies_into`: a solo world, your ship moved to `AT`, a second ship at `AT + (150, 0, 0)`: `fire` round shot from `(2, 1, 1)` aimed (with `aim`) at the target's `(-2, 0, 0)` in the world. Within 3 s the target's `(-2, 0, 0)` is destroyed, and every changed cell has x ≤ 0 and y 0.
  - `test_a_cannon_never_hits_its_own_ship`: `fire` from `(0, 0, 0)` straight up `(0, 1, 0)` through the envelope: after 20 s your ship has every block at full hit points and the shot is gone.
  - `test_chain_shot_tears_the_envelope`: chain shot aimed at the target's envelope side `(-2, 9, 0)`: at least 3 balloon cells destroyed, and no other block below full.
  - `test_a_shell_bursts_and_knocks_down_crew`: the target built from the starter ship with a bunk at `(1, 1, -3)`; you aboard it (`world.board(target)`); a shell aimed at its deck 2 m from you: blocks around the burst lost hit points; `player.enabled` is false and the HUD message is `You're hit! Back on your feet in 5 s.`; 5 s later you're aboard the target standing on the bunk, controls back. While down, a second shell through you doesn't knock you down again (the server's down list).
  - `test_a_harpoon_ties_two_ships`: both unanchored and calm, the target 60 m off; a harpoon hits it: a rope exists on the server with length about 60 (±2); the target pushed away at 5 m/s: 3 s later they're within 1.3 × the length; 46 s after the hit the rope is gone.
  - `test_recover_always_finds_somewhere`: with no ships at all (remove them), `recover(null)` returns null and puts you ashore standing on the quay of the town nearest you within 2 s.
  - Network: `test_every_machine_draws_the_same_arc`: after `sail_together()`, the host fires: the guest's shot has exactly the host's origin, velocity and time, and its drawn node is within 0.01 m of `position_at(origin, velocity, client now − DELAY − time)`.
  - Network: `test_hits_reach_the_guest`: the host shoots its second ship: within 1 s of the hit the guest's shot is gone (after its drawn time passed the hit), and the guest's copy has the host's hit points.
  - Network: `test_the_guest_can_be_knocked_down`: the guest standing on the host's deck; a shell from a second ship bursts beside them: the guest's world gets `knocked_out`, and the host's `crew_positions()` leaves them out for 5 s.
  - Network: `test_ropes_reach_the_guest`: a harpoon hit: the guest has the rope within 1 s, and loses it when the host's goes.
- [ ] **Step 2: Run `./run_tests.sh projectiles`.** Expected: fail.
- [ ] **Step 3: Implement** `Projectiles`, `fire`, the hit handling, knock-downs, ropes, `recover`, `quay_spot` and `open_sky`.
- [ ] **Step 4: Run the whole suite.** Expected: pass.
- [ ] **Step 5: Commit** "Fire projectiles on arcs that every machine draws, with round shot, chain shot, shells and harpoons".

### Task 5: Manned cannons

Build-log item s06-03: "Manned cannons with arcing shots: round shot, chain shot, shells, harpoons" (the guns).

**Files:**
- Create: `src/combat/cannon.gd`, `tests/test_cannons.gd`
- Modify: `src/ship/ship.gd`, `src/ship/starter_ship.gd`, `src/crew/player_controller.gd`, `src/ui/hud.gd`, `src/net/world_sync.gd`, `src/world/world.gd`, `project.godot`, `tests/test_project.gd`, `tests/test_ship.gd`

**Interfaces:**
- Consumes: `WorldSync.fire`, `Projectiles.arc`, `Projectiles.aim` (Task 4); `rebuild` (Task 2).
- Produces:
  - `class_name Cannon extends Node`:
    - `signal gunner_changed`, `signal asked(on: bool)` (a client's copy: man or leave, for the server), `signal fire_asked` (the gunner wants to fire now).
    - `const REACH := 1.8`, `const ARC := 0.7` (rad either side of its facing), `const PITCH_MIN := -0.17`, `const PITCH_MAX := 0.61`, `const RELOAD := 4.0`.
    - `var ship: Ship`, `var cell: Vector3i`, `var gunner := 0` (setter emits `gunner_changed`), `var aim_yaw := 0.0`, `var aim_pitch := 0.0`, `var ammo := "round"`, `var reload_left := 0.0`.
    - `func _init(cannon_ship: Ship, cannon_cell: Vector3i)`; `func facing() -> Vector3`; `func direction() -> Vector3` (ship space: the facing's horizontal part turned by `aim_yaw` about ship up, then raised by `aim_pitch`); `func aim_at(direction: Vector3) -> bool` (sets yaw and pitch toward a ship-space direction; false, and unchanged, outside the limits); `func take(peer: int) -> bool`; `func leave(peer: int) -> void`; `func in_reach(where: Vector3, slack := 0.0) -> bool`; `func ask_man(peer: int, on: bool) -> void`; `func ask_fire(peer: int) -> void` (emits `fire_asked` when `peer` is the gunner and it's loaded); `func next_ammo() -> void` (cycles `Damage.AMMO`'s keys).
  - `Ship`: `var cannons: Array[Cannon]`; `func station_near(where: Vector3) -> Node` (the helm or a cannon in reach of `where`, the nearest, or null). `rebuild` lets go of and frees cannons whose cells are gone. `release(peer)` lets go of cannons too, and `Cannon.take` calls it first.
  - `WorldSync`: `func fire_cannon(ship: Ship, cannon: Cannon) -> int` (server: nothing while reloading; else `reload_left = RELOAD` and `fire(ship, cannon.cell, cannon.direction(), cannon.ammo)`); RPCs `_man`, `_gunner`, `_fire`.
  - `PlayerController`: `func station_in_reach() -> Node`; `crew.station` may be a `Helm` or a `Cannon`; `prompt()` gains `Man the cannon` and `Leave the cannon`.
  - `Hud`: `static func cannon_readout(cannon: Cannon) -> String`.
  - `StarterShip`: cannons at `(2, 1, 1)` facing starboard (`Blocks.turned(0)`) and `(-2, 1, 1)` facing port (`Blocks.rotation_of(Basis(Vector3.UP, PI / 2))`), in place of rail planks; balloon cells at `(-1…1, 9, -6)` and `(-1…1, 9, 8)`.
  - Actions: `fire` on the left mouse button, `ammo` on Q.

Rules:
- **Manning:** E within `REACH` of a cannon block (`station_near`) asks for it; the server grants it only if the asker last reported standing aboard that ship within reach (plus `REACH_SLACK`), as for the helm, and tells everyone (`_gunner`). A player holds one station at a time: taking one lets go of any other. E again leaves.
- **Aiming:** at a cannon you look as usual, and the aim follows your look: `aim_yaw = clampf(wrapf(crew.look_yaw − facing_yaw, −PI, PI), −ARC, ARC)` (`facing_yaw = atan2(−f.x, −f.z)` of the facing's horizontal part) and `aim_pitch = clampf(look_pitch, PITCH_MIN, PITCH_MAX)`. A cannon facing straight up or down fires along its facing. While you man a cannon, a line (an `ImmediateMesh` strip of `Projectiles.arc` over 8 s in 48 steps from its muzzle, drawn only on your machine) shows where the shot will go.
- **Firing:** the left mouse button asks to fire. On the server that's `fire_cannon`. A client sends `_fire(ship id, cell, aim_yaw, aim_pitch, ammo index)` and starts its own reload for the HUD. The server takes it only from the cannon's gunner, with finite yaw and pitch (clamped to the limits) and a known ammunition index, and only when loaded.
- **Ammunition:** Q cycles round shot, chain shot, shell, harpoon.
- **At a cannon**, the HUD's station panel shows `cannon_readout`: `Cannon    Round shot` and then `Ready` or `Reloading 2.1 s`, with the caption `Mouse aim · Click fire · Q ammo · E leave` (the helm keeps its own caption).
- `PlayerController` sets `crew.station` from both kinds: the helm if you're its pilot, else the cannon you man, else null; it listens to the helm's `pilot_changed` and every cannon's `gunner_changed`.
- A destroyed cannon lets its gunner go before it's freed (as the helm does), and a knock-down lets go of cannons too.
- The starter ship stays level: her flight tests stand unchanged.

- [ ] **Step 1: Write the failing tests** (`tests/test_cannons.gd`, `extends NetCase`, in a solo world unless marked network):
  - `test_the_starter_ship_carries_two_cannons_and_still_floats_level`: two cannons, facing +X and −X; `ShipStats.of(StarterShip.build(), 880)` floats at 881 ± 5 m with `bow_down` under 0.1° and no list; `test_ship.gd`'s flight tests pass unchanged.
  - `test_manning_a_cannon_and_firing`: stand at `(1, 1.4, 1)`: the prompt is `E   Man the cannon`; E: `crew.station` is the starboard cannon, the prompt `E   Leave the cannon`; press `fire`: a shot leaves from within 1 m of the muzzle, moving within 5° of `direction()` relative to the ship; pressing again within 4 s fires nothing; after 4 s it fires again.
  - `test_the_aim_stays_within_the_cannons_arc`: at the starboard cannon, looking toward the bow gives `aim_yaw` 0.7; looking straight up gives `aim_pitch` 0.61; `aim_at` a direction behind the cannon returns false.
  - `test_q_changes_the_ammunition`: Q four times goes chain, shell, harpoon, round; the readout shows `Cannon    Chain shot` after the first.
  - `test_a_player_holds_one_station_at_a_time`: at the helm, `ship.cannons[0].ask_man(peer, true)`: the helm's pilot is 0 and your station is the cannon; E then leaves the cannon.
  - `test_a_destroyed_cannon_lets_its_gunner_go`: manning the starboard cannon, `damage_ship` destroys it: `crew.station` null, `ship.cannons` has one, the panel hidden.
  - `test_a_knocked_out_gunner_leaves_the_cannon`: manning a cannon, knocked down (a shell from a second ship): the cannon's gunner is 0 and your station is null.
  - Network: `test_the_guest_mans_a_cannon_and_fires`: after `sail_together()`, the guest mans the port cannon: the host's copy has the guest as gunner within 1 s; the guest fires chain shot: both machines have the shot, of chain shot, and the host's cannon is reloading.
  - Network: `test_the_server_ignores_fire_from_someone_not_at_the_cannon`: the guest's `_fire` for a cannon the host mans, for a cannon nobody mans, with a NaN yaw, with ammo index 9, and twice within the reload: at most the one legal shot is fired. `_man` from 10 m away is refused.
  - `tests/test_project.gd`: `fire` is the left mouse button and `ammo` is Q.
- [ ] **Step 2: Run `./run_tests.sh cannons`.** Expected: fail.
- [ ] **Step 3: Implement** `Cannon`, stations on the ship, the controller and HUD, the network, and the starter ship's guns.
- [ ] **Step 4: Run the whole suite, then play by hand:** man a cannon, watch the arc, and hit an island and a second ship (host a game and launch a second ship from the shipyard).
- [ ] **Step 5: Commit** "Man cannons: aim, fire and choose ammunition; the starter ship carries two".

### Task 6: Repairs, spares and fires

Build-log item s06-04: "Repairs with tools and spare materials; fires; patching balloons".

**Files:**
- Create: `tests/test_repairs.gd`
- Modify: `src/ship/ship.gd`, `src/net/world_sync.gd`, `src/crew/player_controller.gd`, `src/ui/hud.gd`, `src/world/world.gd`, `project.godot`, `tests/test_project.gd`, `tests/test_world.gd`

**Interfaces:**
- Consumes: `Damage.repair`, `ignite`, `burn`, `put_out`, `SPARES_MAX` (Task 1); `damage_ship` (Task 2); shell bursts (Task 4); `_wear` (Task 3).
- Produces:
  - `Ship`: `var fires: Dictionary` (server: cell → seconds burning); `var burning: Array[Vector3i]` (what's drawn, on every machine); `func show_fires(cells: Array) -> void` (sets `burning` and draws flames on those cells).
  - `WorldSync`: `var rng := RandomNumberGenerator.new()`; `func repair(ship: Ship, cell: Vector3i) -> void` (this machine's player); RPCs `_repair`, `_fires`, `_spares`.
  - `PlayerController`: `signal repairing(cell: Vector3i)`; `func aimed_block() -> Dictionary` (`{"cell": Vector3i}` of the block you look at within `Damage.REPAIR_REACH`, or `{}`).
  - `Hud`: the helm readout gains `Spares    %2d/%d` after the hull line; repair prompts.
  - Action `repair` on R (shared with the shipyard's turn key, as M is shared).

Rules:
- **Holding R** aboard, not at a station: every `REPAIR_EVERY`, `aimed_block()` walks the ship's grid (`ShipGrid.raycast`) from your eye (`crew.position + (0, EYE_HEIGHT, 0)`) along your look (`Basis.from_euler(Vector3(look_pitch, look_yaw, 0)) * FORWARD`), and emits `repairing(cell)`. The World passes it to `sync.repair`.
- **The server** (`_repair` or its own player): the repairer must be aboard that ship with their last reported position within `REPAIR_REACH + CrewMember.EYE_HEIGHT + REACH_SLACK` of the cell, and not have repaired within `REPAIR_EVERY − 0.05` s. Then, in order:
  1. Fires within one cell of it are put out (`put_out`), free. Everyone gets the ship's new `_fires`.
  2. Otherwise, with at least 1 spare: `Damage.repair(grid, blueprint, cell)`; if it changes anything, spares −1, the change goes through `damage_ship`, and everyone gets `_spares`.
- **Patching balloons** is the same action: aimed at the envelope beside a hole, it restores the lost balloon cell.
- **Spares:** new ships launch with `SPARES_MAX` (pirates and wrecks with 0). In `_wear`, a ship (not a pirate or wreck) near any town's dock (`Dock.near`) is filled to `SPARES_MAX`.
- **Fire:** a shell's burst ignites (`Damage.ignite` over the blast's cells, with `rng`). In `_wear`, each burning ship `burn`s once; its changes go through `damage_ship`; when its set of burning cells changes, everyone gets `_fires` and `show_fires` redraws. Flames: a `MultiMeshInstance3D` on the ship of 0.8 m cubes in emissive `Color("ff7a1a")` (energy 4), flickering in size, no shadows.
- **Prompts** (after the E prompts, before gliding and the shipyard): aimed at a burning block or beside a fire `Hold R   Put out the fire`; at a damaged block `Hold R   Repair  %d/%d` (its hit points); at a block beside a lost one `Hold R   Rebuild`; any of these with no spares `No spares left: refill at a town's dock`.

- [ ] **Step 1: Write the failing tests** (`tests/test_repairs.gd`, `extends NetCase`, in a solo world at the dock unless the test says otherwise; `repair` called every 0.25 s by the test through the controller's `repairing` signal):
  - `test_repairing_heals_a_block_and_uses_a_spare`: a deck plank at 20, ship moved 3 km from the dock (no refill), standing beside it and looking at it with R held for 1.1 s: its hit points go 45, 70, 80, and spares went from 40 to 37; holding on uses no more.
  - `test_rebuilding_lost_blocks_from_the_blueprint`: a plank destroyed; aimed at its neighbour: it comes back as a deck plank with the blueprint's rotation at 25, and heals to 80 with more repairs.
  - `test_patching_the_envelope`: balloon cells `(2, 9, -1…1)` destroyed; you on the deck at `(1, 1.4, 0)` looking straight up at `(1, 8, 0)` (5.4 m away): three repairs restore `(2, 9, 0)`, then `(2, 9, -1)`, then `(2, 9, 1)`; `trim_to_float_at(880)` is back to the whole ship's.
  - `test_helms_and_cannons_need_a_shipyard`: a destroyed cannon isn't restored by repairs beside it.
  - `test_out_of_spares`: spares 0: nothing changes, and the prompt reads `No spares left: refill at a town's dock`.
  - `test_spares_refill_at_a_dock`: spares 5 at slipway 0: 1.5 s later, 40; 3 km away, still 5.
  - `test_fire_spreads_and_can_be_put_out`: `sync.rng.seed = 1`; a plank set burning: 3 s later it's 15 down and the fire set is larger or the same; R aimed at it: every fire within a cell of it is out, the plank isn't healed by that action, and the next repair heals it.
  - `test_a_shell_can_start_a_fire`: `sync.rng.seed = 1`; five shells at a second ship's deck, the two ships 150 m apart at `Vector3(0, 1900, 7000)`: at least one fire burns on it.
  - Network: `test_the_server_ignores_repairs_out_of_reach`: the guest's `_repair` for a cell 10 m from them, for a cell on another ship, and twice within 0.1 s: only the one legal repair counts.
  - Network: `test_fires_and_spares_reach_the_guest`: the host sets a fire and repairs: the guest's copy has the same `burning` cells and the new spares within 1.5 s.
  - `tests/test_project.gd`: `repair` is R.
  - `tests/test_world.gd`: the readout expects `Spares    40/40` after the hull line.
- [ ] **Step 2: Run `./run_tests.sh repairs`.** Expected: fail.
- [ ] **Step 3: Implement** repairs, spares, fires and their prompts.
- [ ] **Step 4: Run the whole suite, then play by hand:** shoot your second ship's envelope and deck, set it on fire, then walk it with R.
- [ ] **Step 5: Commit** "Repair with spares, rebuild lost blocks and patch balloons, and fight fires".

### Task 7: Pirates

Build-log item s06-05: "Pirate ships with AI captains that chase, circle and fire broadsides".

**Files:**
- Create: `src/ai/pirate_ship.gd`, `src/ai/pirate_captain.gd`, `tests/test_pirates.gd`
- Modify: `src/net/world_sync.gd`, `src/net/session.gd`, `src/world/sites.gd`, `src/ui/map_view.gd`, `tests/net_case.gd`, `tests/test_towns.gd`

**Interfaces:**
- Consumes: `Cannon.aim_at`, `fire_cannon` (Task 5); `Projectiles.aim` (Task 4); the helm's autopilot; `WorldGen`.
- Produces:
  - `class_name PirateShip`: `static func build() -> ShipGrid` (the starter ship with its cannons moved to `(±2, 1, -1)` and `(±2, 1, 2)`, the rail planks at z 1 back, and a ridge of balloon cells at `(0, 11, -4…6)`), painted `{"balloon": Color("5a2a2a"), "deck": Color("5b4636"), "frame": Color("3b2a20")}`.
  - `class_name PirateCaptain extends Node`: `const SIGHT := 900.0`, `const GIVE_UP := 1500.0`, `const CLOSE := 500.0`, `const ORBIT := 260.0`, `const INWARD := 0.8`, `const FIRE_RANGE := 600.0`, `const THINK_EVERY := 0.5`, `const MIN_ALTITUDE := 400.0`, `const MAX_ALTITUDE := 1800.0`, `const PATROL_THROTTLE := 0.3`, `const CHASE_THROTTLE := 1.0`, `const CIRCLE_THROTTLE := 0.7`, `const PATROL_TURN := 0.05`, `const VOLLEY := ["round", "round", "chain"]`; `var target: Ship`, `var state := "patrol"` (`"patrol"`, `"chase"`, `"circle"`), `var shots := 0`; `func _init(world_sync: WorldSync)`.
  - `WorldSync`: `var gen: WorldGen` (set by the World); `const RAID_EVERY := 30.0`, `const RAID_CHANCE := [0.5, 0.5, 0.5, 0.5, 0.25, 0.0]` and `const RAID_LIMIT := [2, 2, 2, 2, 1, 0]` (by `WorldGen.Region`), `const RAID_NEAR := 2000.0`, `const MAX_PIRATES := 4`, `const SAFE := 1200.0`, `const PIRATE_DISTANCE := 800.0`; `func spawn_pirate(near: Ship) -> Ship` (server; null when there's no clear spot); `func _raid() -> void`.
  - `Session.pirates := true` (server: pirates raid in this game). `NetCase.make_session` sets it false.
  - `Sites.wreck_grid` starts from `PirateShip.build()`.
  - `static func MapView.ship_color(ship: Ship) -> Color`: red for pirates, as now for the rest.

Captain rules (server only; it's added to pirate ships on the server, so clients never think):
- Every `THINK_EVERY`: keep the target while it's here, not a wreck, and within `GIVE_UP`; otherwise take the nearest ship that isn't a pirate, a wreck or a test flight, within `SIGHT`, or none.
- The helm's autopilot flies it (`set_autopilot(true)` once); the captain sets `target_heading` (`atan2(−w.x, −w.z)` for a wished direction `w`), `target_altitude` and `ship.throttle`:
  - **patrol** (no target): heading turns by `PATROL_TURN` a think, throttle `PATROL_THROTTLE`, altitude where it spawned;
  - **chase** (farther than `CLOSE`): straight at the target, `CHASE_THROTTLE`;
  - **circle** (within `CLOSE`): along `(t + to * clampf((d − ORBIT) / ORBIT, −1, 1) * INWARD).normalized()`, where `to` is the horizontal direction to the target and `t = to.cross(Vector3.UP)`; `CIRCLE_THROTTLE`. It settles about 330–360 m out with the target abeam.
  - In chase and circle the altitude is the target's, clamped to `MIN_ALTITUDE`…`MAX_ALTITUDE`.
- **Firing,** each think, each loaded cannon, within `FIRE_RANGE`: the muzzle `m = ship.global_transform * (Vector3(cell) + facing() * WorldSync.MUZZLE)`; the ammunition `VOLLEY[shots % 3]` (round shot when the target has no balloons); lead the target: `t = distance / speed`, twice `offset = aim_point + (target velocity − own point velocity at m) * t − m`, `w = Projectiles.aim(offset, speed)`, `t = horizontal distance / (speed * horizontal part of w)`. If `w` isn't zero and `cannon.aim_at(ship.global_basis.inverse() * w)` is true, `fire_cannon`. Only cannons on the side facing the target can aim, so it fires broadsides.
- A pirate whose helm is gone is a wreck: its captain frees itself.

Raid rules (server, every `RAID_EVERY`, when `session.pirates`):
- For each crewed ship that isn't a pirate, wreck or test flight, and is more than `SAFE` from every town's dock: if fewer than `RAID_LIMIT[region]` pirates are within `RAID_NEAR` of it and fewer than `MAX_PIRATES` exist, then with `RAID_CHANCE[region]` (`rng`), `spawn_pirate(it)`.
- `spawn_pirate(near)`: from a random angle, up to 8 directions 45° apart, the first spot `PIRATE_DISTANCE` away horizontally, at `clampf(near.y, MIN_ALTITUDE, 1600)`, with no island (from `gen`) in the 3 × 3 chunks around it whose disc comes within `radius + 60` m horizontally. The pirate faces `near`, is added with `pirate = true` and 0 spares, gets a `PirateCaptain`, and returns; none clear gives null.
- In `_wear`, a pirate further than `FAR` from every crewed ship is removed.
- The map draws pirates as red dots (`Color("d9534f")`).

- [ ] **Step 1: Write the failing tests** (`tests/test_pirates.gd`; the flight test a plain `TestCase` ship with no world, the rest `extends NetCase` in a solo world with pirates off, your ship anchored at `open_sky(world, 1000)`):
  - `test_the_pirate_ship_flies`: `ShipStats.of(PirateShip.build(), 960)`: floats at 900–1,050 m, list under 0.5°, bow down under 1°, top speed over 15 m/s, no warnings; four cannons, two facing each side. In calm air at 962 m for 60 s she holds her height within 30 m and her pitch within 1.5°.
  - `test_a_pirate_chases_and_circles`: `spawn_pirate(ship)`: 800 m away; within 90 s it has been in `"circle"`, and over the next 30 s its distance stays between 150 and 500 m and its altitude within 40 m of yours.
  - `test_a_pirate_fires_broadsides`: in 120 s it fires at least 4 shots; every shot leaves from a cannon whose facing (in the world, flattened) is within 50° of the direction to your ship; your ship has blocks below full hit points.
  - `test_a_pirate_without_a_helm_gives_up`: destroy its helm: its captain is gone and it fires nothing more in 30 s.
  - `test_a_pirate_turns_on_whoever_is_nearest`: two targets, one 700 m and one 1,200 m away: it chases the nearer; move that one 2 km off: it takes the other.
  - `test_pirates_raid_away_from_towns`: pirates on (`world.session.pirates = true`), `sync.rng.seed = 1`: at the dock, 40 `_raid()`s spawn none; at the `open_sky` spot (the Calm Reaches, over 1,500 m from any dock), 40 `_raid()`s spawn exactly one (the region's limit); the pirate isn't within its island clearance of any island in `gen`.
  - `test_pirates_leave_when_far`: a pirate moved 3.5 km from every crewed ship is removed at the next `_wear`.
  - `test_wrecks_are_pirate_ships`: `Sites.wreck_grid(w)` has no balloons, is the same twice, and every block is at a cell of `PirateShip.build()`.
  - Network: `test_the_guest_sees_pirates`: after `sail_together()`, the host spawns one: the guest's copy has `pirate` true, no `PirateCaptain`, and `MapView.ship_color` of it is `Color("d9534f")`.
  - `tests/test_towns.gd`: the wreck test's box count still holds for pirate wrecks (adjust if the grid's box count changed).
- [ ] **Step 2: Run `./run_tests.sh pirates`.** Expected: fail.
- [ ] **Step 3: Implement** `PirateShip`, `PirateCaptain`, spawning, raids, and the other changes.
- [ ] **Step 4: Run the whole suite, then play by hand:** fly 2 km out of the starting town and wait for a pirate; fight it.
- [ ] **Step 5: Commit** "Send pirates with AI captains that chase, circle and fire broadsides".

### Task 8: Salvage

Build-log item s06-06: "Salvage and loot from wrecks".

**Files:**
- Create: `tests/test_salvage.gd`
- Modify: `src/net/world_sync.gd`, `src/world/world.gd`, `src/world/sites.gd`, `src/ui/hud.gd`

**Interfaces:**
- Consumes: wrecks (Task 3), spares (Task 6), `Sites` (stage 5).
- Produces:
  - `Sites.wreck_center(wreck: Dictionary) -> Vector3`: the middle of a world wreck's blocks, in the world (`create_wreck` and this share one placement function).
  - `WorldSync`: `var sites: Array[Vector3]` (every world wreck's centre, set by the World), `var salvaged: Dictionary` (site index → true), `signal salvage_result(spares: int)`; `func salvage_site(index: int) -> void`, `func salvage_ship(wreck: Ship) -> void` (this machine's player); RPCs `_salvage`, `_salvaged`, `_salvage_result`; `_world(time, entries, salvaged)`.
  - `World.salvage_in_reach() -> Array`: `["site", index]`, `["ship", wreck]`, or `[]`.

Rules:
- **In reach** (every machine, for its prompt): a world wreck not salvaged whose centre is within `SITE_REACH` of your world position; or a wreck ship (captain 0) whose world box grown `SALVAGE_REACH` holds you, aboard it or not. Sites come first.
- **E salvages** when nothing else takes E (the World handles `interact` after the controller, when `player.prompt()` is empty). The HUD prompt `E   Salvage` comes after `Climb aboard` and before the repair prompts.
- **The server** checks the same reach against the salvager's last report (their world position: the ship's transform times their ship-space position, or their ashore position), plus `REACH_SLACK`. Junk kinds and indices are ignored.
- **The spares go** to the ship the salvager is aboard if it isn't a wreck, else their own ship, else `home_ship()`, capped at `SPARES_MAX`. When nothing fits, nothing is taken: result −1.
- **A world wreck** gives `SALVAGE_SPARES` once: `salvaged[index] = true`, everyone gets `_salvaged(index)`, and late joiners get the list in `_world`. It stays in the sky, empty. **A wreck ship** gives `ceili(blocks / 10.0)` and is broken up (removed).
- The salvager hears `_salvage_result`, and the HUD says `Salvaged %d spares.`, `Nothing left to salvage here.` or `No room for more spares.`

- [ ] **Step 1: Write the failing tests** (`tests/test_salvage.gd`, `extends NetCase`, in a solo world):
  - `test_salvaging_a_wreck_site`: your ship anchored 3 km from every dock with 10 spares; you ashore, placed at `Sites.wreck_center(gen.wrecks[0])` (the test presses E at once, so it doesn't matter whether the island has loaded): the prompt is `E   Salvage`; E: spares 22 and `Salvaged 12 spares.`; E again: `Nothing left to salvage here.` and the prompt is gone.
  - `test_salvaging_a_broken_off_section`: your ship anchored 3 km from every dock with 10 spares; the bow cut off (every cell at z −3 destroyed); you aboard the piece (`come_aboard`): E gives your ship `ceili(piece blocks / 10.0)` spares and the wreck is gone.
  - `test_salvage_goes_to_the_ship_you_are_aboard`: aboard a second ship (captain 0, spares set to 0), 3 km from every dock, with a wreck within 4 m: the spares go to the ship you're aboard, not your own.
  - `test_no_room_for_more_spares`: spares 40: `No room for more spares.` and the site stays unsalvaged.
  - Network: `test_the_world_remembers_what_was_salvaged`: the guest salvages site 0: the host's `salvaged` has it and the guest's prompt is gone; a late joiner's `salvaged` has it.
  - Network: `test_the_server_ignores_salvage_from_afar`: the guest's `_salvage("site", 0)` from 1 km away, `("site", 99)`, `("site", -1)`, `("ship", 12345)`, `("ship", <a ship that isn't a wreck>)` and `("junk", 0)`: nothing changes.
- [ ] **Step 2: Run `./run_tests.sh salvage`.** Expected: fail.
- [ ] **Step 3: Implement** salvage.
- [ ] **Step 4: Run the whole suite, then play by hand:** glide down to a wreck in the Shattered Belt and salvage it; break a pirate and strip its wreck.
- [ ] **Step 5: Commit** "Salvage spares from wrecks".

### Task 9: Sinking into the Roil, and rebuilding

Build-log item s06-07: "Sinking into the Roil: the ship is lost, rebuild it from its blueprint".

**Files:**
- Create: `tests/test_sinking.gd`
- Modify: `src/net/world_sync.gd`, `src/world/world.gd`, `tests/test_ashore.gd`

**Interfaces:**
- Consumes: `Damage.roil` (Task 1), `damage_ship` (Task 2), `_wear` (Task 3), `recover` (Task 4).
- Produces:
  - `WorldSync`: `const LOST_ALTITUDE := 0.0`; `func remove_ship(ship: Ship, successor: Ship = null, lost := false) -> void`; `_ship_removed(id, successor, lost)` sets `ship.lost` before `ship_removed` fires.
  - `World.rescue()` uses `recover(left)`.

Rules:
- In `_wear`: every ship takes `Damage.roil(grid, global_transform)` through `damage_ship` (so a ship dipping into the Roil breaks up from the keel). A ship whose origin is below `LOST_ALTITUDE` is removed with `lost = true`.
- On the machine of the lost ship's captain (not a test flight): `design = ShipDesign.new(removed.blueprint)` and the HUD says `Your ship is lost to the Roil. The shipyard has her blueprint: launch to rebuild her.` Anyone else aboard sees `She's lost to the Roil.` Wrecks and pirates go without a word.
- Crew aboard a lost ship go where they always go when a ship is removed: the next ship, else into the air where she was, where the Roil's rescue catches them.
- `rescue()` is `recover(left)`: aboard a ship, `The Roil nearly took you. Back aboard!` as now; with no ship left, on the nearest town's quay with `The Roil nearly took you. You wake on the quay at %s.` (the town's name).
- Rebuilding costs nothing: Launch in the shipyard builds the design whole, as now.

- [ ] **Step 1: Write the failing tests** (`tests/test_sinking.gd`, `extends NetCase`, in a solo world with your ship at `open_sky(world, 250)`):
  - `test_the_roil_wears_a_ship_down`: anchored with her origin at y 199: after 3 `_wear`s the keel and deck cells lost 30 and the rails nothing.
  - `test_a_ship_below_the_roil_is_lost_and_its_crew_rescued`: every balloon destroyed, unanchored: within 60 s she's removed with `lost`; the HUD said `Your ship is lost to the Roil. The shipyard has her blueprint: launch to rebuild her.`; within 5 s after, you're ashore on the floor, on the quay of the nearest town.
  - `test_nobody_falls_forever_when_every_ship_is_gone`: ashore at y 190 with no ships in the world: you're on the nearest town's quay and the message names the town.
  - `test_rebuilding_a_lost_ship_launches_her_blueprint_whole`: after the loss, `world.design.grid`'s blocks equal the lost ship's blueprint's; at the dock, launching it gives you a new ship at your slipway with every blueprint block at full hit points and 40 spares.
  - `test_wrecks_and_pirates_sink_without_a_word`: a wreck and a pirate below 0 m are removed at the next `_wear` with no HUD message.
  - Network: `test_a_guest_sees_their_ship_lost`: the guest launches a ship and flies it; the host sinks it: the guest gets the message and the design; the host's ship is untouched.
  - `tests/test_ashore.gd`: `test_the_roil_sends_you_back_aboard` still passes unchanged.
- [ ] **Step 2: Run `./run_tests.sh sinking`.** Expected: fail.
- [ ] **Step 3: Implement** the Roil's wear, losing ships, the messages and the design, and `rescue` through `recover`.
- [ ] **Step 4: Run the whole suite.** Expected: pass.
- [ ] **Step 5: Commit** "Lose ships to the Roil and rebuild them from their blueprints".

### Task 10: A battle on two machines, README and spec

Build-log item s06-08: "Tests: damage and break-apart logic" (the network half; the stage's promise).

**Files:**
- Create: `tests/test_combat_net.gd`
- Modify: `README.md`, `docs/superpowers/specs/2026-09-29-skywright-design.md`

- [ ] **Step 1: Write the tests** (`tests/test_combat_net.gd`, `extends NetCase`):
  - `test_host_and_guest_agree_after_a_broadside`: after `sail_together()`, both ships moved to `open_sky`, a second ship 200 m to starboard (unanchored, calm); the host fires three of each ammunition from its starboard cannon, aimed with `Projectiles.aim` at the second ship, one every reload; 8 s after the last: host and guest have the same ship ids, and for each the same cells, types and hit points, and the same `burning` cells.
  - `test_a_battle_stays_within_the_network_budget`: the same with a pirate circling (spawned by the host) for 20 s: the guest's `get_host().pop_statistic(HOST_TOTAL_RECEIVED_DATA)` over those 20 s is under 20 × 32 KB (half the 64 KB/s budget).
  - `test_a_dedicated_server_fights_too`: a dedicated host in this process (`host.host("Server", port, true)`, as `test_a_dedicated_server_loads_collision_only` does), a guest joins and launches a ship, moved to `open_sky(host_world, 1000)`; the host calls `spawn_pirate` on it: the guest's ship takes damage within 120 s, and the host's `Projectiles` has no `MeshInstance3D` children.
- [ ] **Step 2: Run the whole suite three times.** Expected: it passes every time.
- [ ] **Step 3: Measure by hand** on the Radeon 680M (`godot --path . --gpu-index 0 -- --solo --seed=7`): fight a pirate for two minutes, shooting the envelope off and setting fires. Record the lowest and typical fps, and the slowest frame when a ship breaks, in "Changes during execution". If a break costs more than 16 ms, record it; sections are the upgrade (ponytail in `ShipMesh`).
- [ ] **Step 4: Update the README:**
  - The status: stage 6 of 10, and what you can do now (man cannons with four kinds of shot, break ships apart, repair and fight fires, fight pirates, salvage wrecks, lose a ship to the Roil and rebuild her).
  - Controls: left click fires, Q changes ammunition, E mans a cannon, hold R to repair.
  - A "Combat" section: cannons and the arc, the four kinds of shot, damage and holes, breaking apart, being knocked down, repairs and spares (filled free at any dock), fires, pirates (where they raid), salvage, the Roil, rebuilding for free.
  - The layout gains `src/combat/` and `src/ai/`.
- [ ] **Step 5: Update the spec:** the status line; §3.3 (damage as built); §3.4 (the repair tool, cannons as stations); §3.5 (ammunition as built, pirates, the Roil, free rebuilding until stage 7); §4.4 (the rebuild, one mesh, break-apart as built, the starter ship's cannons); §4.5 (crew hits by reported positions, knock-downs); §4.6 (protocol 5, the events and their budget); §4.7 (wrecks from pirate ships); §4.11 (the measured rebuild times); §9 decisions (spares, free rebuilds, one mesh, hits by reported positions, pirates fired by the captain).
- [ ] **Step 6: Commit** "Test a battle on two machines; update README and spec for stage 6".

---

## Playtest checklist

1. **Cannons:** man a cannon. Does the arc make aiming easy at 100 m and fun at 400 m? Is a 4 s reload right?
2. **Ammunition:** does each kind feel different? Round shot punching through planks, chain shot shredding the envelope, shells bursting and starting fires, a harpoon hauling a ship in.
3. **Damage:** does a hit ship visibly suffer: holes you can see and fall through, a list after losing balloons on one side, a limp after losing a propeller?
4. **Breaking apart:** shoot away the envelope's posts. Does the envelope float off and the hull fall? Does a ship cut in two look right? Does anything stutter when she breaks?
5. **Pirates:** fly out of town and wait for a raid. Do they close in, circle and fire broadsides that feel dangerous but beatable? Is one pirate in the Calm Reaches the right amount?
6. **Repairs:** under fire, can you keep a ship flying with R? Do fires feel urgent without being tedious? Is 40 spares the right amount?
7. **Being hit:** get knocked down by a shell. Is 5 s fair? Do you come to somewhere sensible?
8. **Salvage:** strip a pirate's wreck and a world wreck. Is it worth the detour?
9. **Losing a ship:** let a ship sink into the Roil. Is it clear what happened and how to rebuild her?
10. **Co-op:** a friend mans the other cannon while you steer. Do you both see the same shots, holes, fires and wrecks?
11. **Frame rate:** does a battle hold 60 fps on the Radeon 680M, including the moment a ship breaks?

---

## Changes during execution and after the final review

Tasks 1–5 ran with an implementer and a reviewer each. From Task 6 on, at the user's request, they ran inline: test first, then the whole suite, with one whole-branch review at the end.

| Problem | Fix |
|---|---|
| The starter ship's envelope didn't touch her hull: the posts stopped at y 7 and the envelope's bottom row is 3 wide, so the first hit anywhere would have split the envelope off. | Frames at (±2, 8, −4) and (±2, 8, 6) carry the posts into the envelope's widest row, and four balloon cells at (±2, 9, −5) and (±2, 9, 7) keep her height. She now splits into keep only, and a cut at z 0 gives one wreck. |
| A shipyard design with a gap would lose blocks on the first hit, without warning. | `ShipStats` warns "%d blocks aren't joined to the helm: they'll fall away when she's hit." |
| Round shot through four balloons never reaches the frame behind them (reach 4), unlike the plan's test. | The reach rule stands, and the test asserts the frame untouched. |
| Without her engine the starter ship is 300 kg lighter and rises, so "under 1 m/s" couldn't hold. | The engine-loss test checks horizontal speed. |
| Clients refused ships without a helm, so wrecks never reached them, nor late joiners. | `ShipGrid` readers take `needs_helm` (true by default); ship entries pass false. |
| Boarding a wreck read `helm.cell` and crashed. | `crew_spawn` on a wreck stands you on her highest block near the middle. |
| Wrecks were cleared within a second whenever nobody was aboard a ship, so one could vanish under a player jumping to it. | Wreck and pirate upkeep measure from every player's position, aboard or ashore (`WorldSync.player_positions()`). |
| The six extra balloon cells already gave the joined, armed ship 882.5 m. | The plan's cells stand; `test_ship_grid`'s float centre moved from 877 to 881 m, with the tolerance unchanged. |
| With the spec's literal break-apart rule, shooting out the one plank under the starter ship's helm kept a one-block helm as "the ship" and broke her whole hull away as a wreck. | A helm only keeps the ship on a piece of at least 4 blocks. Otherwise the hull stays the ship, as a wreck, and the loose helm goes as a splinter. |
| The pirate's circling prototype flew in calm air. In the Shattered Belt's 7 m/s wind she circled 430–640 m out. | The captain steers against the wind's drift: the bow goes off by the angle between heading and ground track, at most 0.6 rad, above 5 m/s. Four spawn angles now circle 305–367 m out. |
| `NetCase.open_sky` lands in the Shattered Belt for the test seed, not the Calm Reaches. | The raid test expects that region's own limit. |
| E by a wreck couldn't go through the World in tests, which drive the controller. | The controller emits `idle_interact` when E has nothing else to do, and the World salvages. |
| A captain whose own ship was wrecked couldn't rebuild her if she sank. | A lost ship with a captain gives back her blueprint, wreck or not. Only nobody's wrecks and pirates sink without a word. |
| Late joiners didn't see fires already burning. | They get each burning ship's `_fires` after `_world`, as they get cannon gunners. |

**Frame rate.** On the Radeon 680M (`--gpu-index 0`, seed 7, 1920 × 1080, vsync off), a scripted two-minute fight was measured: your anchored ship in the Shattered Belt with the world streaming, a pirate circling and firing, and your cannon firing shells, chain shot and round shot back every 2 s.
- With a warm shader cache it averaged 226 fps. The slowest second was 183 fps, and the worst frame after loading was 18 ms.
- On the very first run, with a cold shader cache, one frame took 384 ms. That was the driver compiling shaders, and it didn't recur.
- No ship broke apart in the run. Rebuilds measured 2.9 ms (starter ship) to 3.8 ms (500 blocks) in prototyping.
- Playtest item 11 is the hand-flown check.

**Network.** A two-machine fight with a pirate stayed under 32 KB/s down to the guest (`test_a_battle_stays_within_the_network_budget`).

**Deferred:**
- A ship whose helm is shot off is a wreck you can't repair, because helms need a shipyard. If she still floats, you're stranded far from a dock. Consider an "abandon ship" back to the nearest quay, or repairs that rebuild a helm, in stage 7 or 8.
- Right after a loss, the Roil's quay rescue replaces "Your ship is lost to the Roil…" within a second, so the rebuild hint may go unseen. Playtest item 9.
- Smaller items: `Projectiles.untie` broadcasts through `WorldSync.tell_world`; `_down` is never pruned; a wreck keeps a mannable cannon; clients set `Ship.born` on arrival; the aim line leaves out the ship's motion on guests.
