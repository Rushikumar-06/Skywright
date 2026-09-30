# Stage 5: The Sky World Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A huge generated archipelago worth exploring. The whole 16 km disc is generated from a seed and streams in around the ships and players: floating islands with grassy tops, rocky undersides, trees and waterfalls, ten towns with docks and shipyards, wrecks and landmarks. Wind has sky rivers and storm cells, and sails catch it. Clouds, fog layers and lightning fill the sky. A map and compass fill in as you explore. You can leave the ship on foot, walk the islands, glide back, and anchor the ship so it stays put.

**Architecture:**
- **The seed makes the world, as data.** `WorldGen.new(seed)` works out, once, everything the whole disc needs to know: the ten towns, the landmarks, the wrecks, the sky rivers and the storm cells. Islands are worked out per 256 m chunk on demand, from `hash([seed, cx, cz, "islands"])`, so any chunk can be made alone, in any order, on any machine, and comes out the same. Nothing here touches nodes, so it runs on worker threads and in tests.
- **Shapes are arrays.** `IslandMesh` turns an island's description into flat-shaded triangle arrays for three levels of detail, collision faces, tree spots and a waterfall. `WorldChunk.generate(gen, chunk, visuals)` (worker thread) gathers a chunk's arrays; `WorldChunk.build(data)` (main thread) turns them into nodes: one mesh per level of detail with `visibility_range` doing the switching, trees as a MultiMesh, one static collision body, clouds, and any wreck or landmark in the chunk.
- **Streaming follows focus points.** `WorldStreamer` loads every chunk within 2.5 km of a focus point and frees chunks beyond 2.8 km. The server's focus points are every ship and every player; a client's is its own player. Generation runs on `WorkerThreadPool`; adding to the scene is spread over frames with a time budget. A dedicated server loads collision only.
- **Towns are always there.** Ten towns (four in the Calm Reaches, the first being the starting town at `START`) are built when the world loads. Each has a quay with a slipway for every player and a finger pier beside each slipway, a flat island with houses and a beacon tower, and a name. The shipyard opens at any town's dock, and launches and test flights go from the nearest town's slipways.
- **Wind is a field.** `Wind.new(gen)` is prevailing wind by distance from the Eye, plus sky rivers, storm cells, turbulence and the rim's push inward. It's a pure function of position, time and seed. `WorldSync` drives its clock from the world clock, so storms are where everyone sees them. Sails push along their facing.
- **On foot is the main world.** A `CrewMember` whose `ship` is null walks in the main world with ordinary gravity. Stepping off a deck (no floor for 0.2 s and nothing of the ship below) moves you ashore; landing on a ship's deck, or E next to its hull, puts you aboard. In the air, holding Space glides. Falling into the Roil brings you back aboard. A pilot can anchor a ship (G), which holds it still.
- **The seed travels with the handshake.** `Session.world_seed` is chosen when solo or hosting starts (or given with `--seed=N`) and sent in `_welcome`, so a guest's world is generated before it loads. Protocol 4.

**Tech Stack:** Godot 4.7.2 (standard build, `~/.local/bin/godot`), statically typed GDScript, `FastNoiseLite`, `RandomNumberGenerator`, `WorkerThreadPool`, Jolt, ENet through SceneMultiplayer, and the existing headless test runner.

**Spec:** `docs/superpowers/specs/2026-09-29-skywright-design.md` (stage 5 in §5; the world in §3.1; crew and leaving the ship in §3.4 and §4.5; networking in §4.6; world generation and wind in §4.7; rendering in §4.8).

**Where:** branch `stage-5-sky-world`, in the worktree `../game-stage-5`, branched from `stage-4-shipyard`.

## Global Constraints

- Godot 4.7.2 standard build, and GDScript with static types everywhere. No addons or other dependencies. No external art: everything is generated in code (spec §3.9).
- The world is a disc of radius 8,000 m centred on the origin. The Roil fills everything below 200 m. Islands float between 300 m and 1,800 m (spec §3.1).
- Regions by distance from the centre: the Eye 0–1,600 m, the Stormwall 1,600–2,200 m, the Gale Expanse 2,200–4,000 m, the Shattered Belt 4,000–6,000 m, the Calm Reaches 6,000–8,000 m. Beyond 8,000 m is the rim.
- Chunks are 256 m × 256 m columns, seeded from `hash([seed, cx, cz, purpose])` (spec §4.7). The same seed always builds the same world.
- Streaming: 2.5 km around every ship and player on the server, 2.5 km around your own player on a client (spec §4.7). Detail: full below 800 m, medium below 1,800 m, low below 3,000 m.
- North is −Z and east is +X. Compass bearings run clockwise from north, as the helm's heading already does.
- The server is authoritative for ships and the world. A client only asks. Everything a peer receives from another machine is checked.
- Protocol version 4. Channel 0 is reliable for events, channel 1 unreliable-ordered for ship snapshots, channel 2 unreliable-ordered for crew and helm keys.
- Every number that decides how ships fly stays in `src/ship/tuning.gd`. World-generation numbers live in `WorldGen`, wind numbers in `Wind`.
- Performance target: 60 fps at 1080p on medium settings on the Radeon 680M (spec §4.11). Adding chunks to the scene spends at most 3 ms of a frame.
- New messages are the exact strings in this plan.
- Tests use ports 20000–29999, and `NetCase` worlds use the fixed seed `NetCase.SEED` so tests don't depend on luck.
- Commit messages have no `Co-Authored-By` line or other trailers (user rule).

## Review Focus

1. **Stepping off and coming aboard** (jumping on deck, walking off the rail at speed, the deck tilting in a gust, standing on a ship's roof, landing on another ship, E next to a hull, falling into the Roil, your ship replaced while you're ashore): you only go ashore when you've really left the ship, you never flicker between ashore and aboard, and you always end up standing somewhere. Tests: `test_jumping_on_deck_stays_aboard`, `test_walking_off_the_side_goes_ashore_with_the_ships_speed`, `test_you_dont_bounce_straight_back_aboard`, `test_landing_on_a_deck_boards_that_ship`, `test_the_roil_sends_you_back_aboard`, `test_a_new_ship_arriving_while_ashore_boards_you` (Task 8).
2. **Streaming while things move and end** (a ship at full speed, a teleport of 3 km, a world freed while chunks are still generating, a chunk wanted, dropped and wanted again): collision is always there before a ship reaches it, no chunk is ever loaded twice, and no engine errors are logged. Tests: `test_a_fast_ship_never_outruns_the_collision`, `test_chunks_far_away_are_freed_and_come_back_the_same`, `test_freeing_the_world_mid_generation_is_clean` (Task 3).
3. **Two machines, one world** (a guest generating the host's world from the seed in the handshake; a modified host sending a junk seed): host and guest see the same islands in the same places, and junk is refused. Tests: `test_the_seed_travels_with_the_handshake`, `test_host_and_guest_generate_the_same_chunks` (Task 1), `test_a_junk_seed_is_refused` (Task 1).
4. **Towns and their docks** (the shipyard away from the start, launching from the third town, a junk town index from a client, a big ship that doesn't fit beside the piers): launches go from the nearest town's slipways, junk is ignored, and nothing is built inside a pier or an island. Tests: `test_the_shipyard_opens_at_any_towns_dock`, `test_launching_at_another_town_uses_its_slipways`, `test_the_server_ignores_launches_at_junk_towns` (Task 5).
5. **Wind at the edges** (the exact centre, the rim, inside a river's core, at a river's end, a storm cell passing, an anchored ship in a storm): no NaN anywhere, the wind is continuous, and an anchored ship stays put. Tests: `test_the_wind_is_finite_and_continuous_everywhere`, `test_a_river_fades_smoothly_at_its_edge_and_ends` (Task 4), `test_an_anchored_ship_stays_put_in_a_storm` (Task 8).

---

## What prototyping settled before this plan

| Question | Answer |
|---|---|
| Is `hash()` of an array stable? | `hash([1234, 5, -7, "islands"])` gave `3975870881` in two separate runs. It's a pure function of the values, so the same seed seeds the same chunk on every run and machine running this Godot. |
| How long does an island take? | A 32 × (6 + 8) ring island (896 triangles, flat shaded, noise-shaped) takes about 0.85 ms of GDScript. Sixteen on `WorkerThreadPool` took 5 ms on this 16-thread machine. A lambda that captures locals runs fine on the pool. |
| What costs the main thread? | `ConcavePolygonShape3D.set_faces` with 896 triangles: 0.08 ms. `ArrayMesh.add_surface_from_arrays`: 0.15 ms. So workers make arrays and the main thread makes resources and nodes, within a per-frame budget. |
| Chunks in range | About 300 chunks lie within 2.5 km of a point, fewer near the rim. The whole disc is about 3,100 chunks. |
| Where do sails face? | `ShipMesh` draws a sail as a 1 × 1 × 0.08 m board: its flat side faces along its own Z, so its normal in ship space is `Blocks.facing(rotation)`. |
| Where do ships sit at a slipway? | The starter ship spans x −2.5…2.5 and z −6.5…7.5 around its slipway, deck top at y 0.5. The quay is 23 m behind the sterns (z 30–44). That's why this stage adds a finger pier beside each slipway. |
| Environment height fog | `fog_height` and `fog_height_density` exist, but whether they apply in depth-fog mode wasn't checked. This plan uses translucent fog sheets instead, which are cheap and look the same everywhere. |

## Where this stage departs from the spec

The spec is updated to match in Task 9.

| Spec | This stage | Why |
|---|---|---|
| §4.7: "Wrecks are generated from damaged pirate blueprints" | Wrecks are damaged starter ships. | Pirates arrive in stage 6. Swap the grid when they do. |
| §4.7: towns "on large islands placed by seeded Poisson sampling" | Seeded dart throwing with a 1,500 m spacing between docks, per region. The starting town is always at `START`. | The same thing in a few lines. A fixed start keeps every existing test and the dock where it was. |
| §4.7: the server "keeps collision loaded within 2.5 km of every ship and player" | Every loaded chunk has collision and visuals (visuals switch off with `visibility_range`), except on a dedicated server, which loads collision only. | One kind of chunk. The host's own camera never draws far chunks anyway. |
| §4.8: volumetric fog "if the Radeon 680M can afford it" | Translucent fog sheets above the Roil, and depth fog that hides the streaming edge. | Cheap on any GPU. Volumetric fog can come with the polish stage. |
| §4.5: "Landing on any ship moves you into that ship's interior" | Landing on a ship's deck, or pressing E within 3 m of her hull, puts you aboard. | You can't jump 2 m up a hull, and ships don't hold still at a quay. |
| (not in the spec) | Anchoring (G at the helm) freezes the ship where she is. | "Stays put" in its simplest form, the way a dedicated server already anchors ships. |
| (not in the spec) | Crew who go ashore are drawn to others as a plain avatar, with no glider. | A glider model can come with the polish stage. |

## Protocol (version 4)

| RPC | Change |
|---|---|
| `Session._welcome(roster, under_way, seed)` | Adds the world seed, an `int` from 0 to 2,147,483,647. A client refuses anything else and ends with "The host sent a world this game can't make." |
| `WorldSync._launch(blocks, paint, test, town)` | Adds the town whose dock to launch from, an `int` index into `WorldGen.towns`. Anything else is ignored. |
| `WorldSync._ships` states | Each state gains a 12th field, `anchored` (bool). |
| `WorldSync._request(ship_id, what, on)` | `what` may also be `"anchor"`. Only the pilot may anchor. |
| `WorldSync._crew_report` / `_crew_moved` | `ship_id` 0 means ashore: `position` and `velocity` are in world space. The server checks ashore reports are finite, at most 50 m/s, and within 11,000 m of the centre and between 0 and 5,000 m high. |

---

## File structure

| File | Responsibility |
|---|---|
| `src/world/world_gen.gd` | `WorldGen`: regions, chunk islands, towns, landmarks, wrecks, sky rivers, storm cells, names |
| `src/world/island_mesh.gd` | `IslandMesh`: an island's outline, surface height, triangle arrays per level of detail, collision faces, trees, waterfall |
| `src/world/world_chunk.gd` | `WorldChunk`: a chunk's arrays on a worker (`generate`), and its nodes on the main thread (`build`); shared materials |
| `src/world/world_streamer.gd` | `WorldStreamer`: which chunks to load and free, the worker queue, the per-frame budget |
| `src/world/town.gd` | `Town`: a town's island, houses, beacon, sign and dock |
| `src/world/sites.gd` | `Sites`: wreck and landmark nodes |
| `src/world/weather.gd` | `Weather`: fog sheets, storm cloud columns, lightning bolts |
| `src/world/wind.gd` | `Wind`: the wind field (rewritten as an instance) |
| `src/world/dock.gd` | Piers, the town island in the obstacles, and no placeholder island |
| `src/world/world.gd` | The seed, `gen`, `wind`, towns, streamer, weather, exploration, map; at the dock of any town; ashore and aboard; anchoring |
| `src/world/exploration.gd` | `Exploration`: which 128 m cells you've seen |
| `src/ui/map_view.gd` | `MapView`: the map (M) |
| `src/ui/compass.gd` | `Compass`: the HUD's compass strip and region name |
| `src/ui/hud.gd` | Compass, wind in the readout, anchor, ashore prompts, the map |
| `src/crew/crew_member.gd` | Ashore when `ship` is null: world gravity, gliding, landing, leaving, the Roil |
| `src/crew/player_controller.gd` | Drives crew ashore, glide key, E to climb aboard, G to anchor, signals on to the World |
| `src/crew/helm.gd` | `ask_anchor` |
| `src/ship/ship.gd` | `weather`, sails, `anchored`, `is_over()` |
| `src/ship/tuning.gd` | `SAIL_AREA`, `SAIL_COEFFICIENT` |
| `src/net/session.gd` | `requested_seed`, `world_seed`, the seed in `_welcome`, protocol 4 |
| `src/net/world_sync.gd` | `docks` in place of berths; launches name a town; anchored in snapshots; anchor requests; crew ashore; the wind's clock; focus points |
| `src/core/launch_options.gd`, `src/core/game.gd` | `--seed=N` |
| `project.godot` | Actions: `map` M, `anchor` G |
| `tests/net_case.gd` | `SEED`; sessions use it |
| `tests/test_world_gen.gd`, `test_island_mesh.gd`, `test_streaming.gd`, `test_wind.gd`, `test_towns.gd`, `test_weather.gd`, `test_map.gd`, `test_ashore.gd`, `test_determinism.gd` | New tests |
| `README.md`, spec | Stage 5 status, exploring, on foot, the map, seeds |

---

### Task 1: The seeded world generator

Build-log item s05-01: "Seeded world generator with five regions, from the Calm Reaches to the Eye".

**Files:**
- Create: `src/world/world_gen.gd`, `tests/test_world_gen.gd`
- Modify: `src/net/session.gd`, `src/core/launch_options.gd`, `src/core/game.gd`, `tests/net_case.gd`, `tests/test_session.gd`, `tests/test_launch_options.gd`

**Interfaces:**
- Produces (`class_name WorldGen extends RefCounted`):
  - `const RADIUS := 8000.0`, `const CHUNK := 256.0`, `const START := Vector3(0.0, 880.0, 7000.0)` (the starting town's slipway 0; `World.START` becomes `WorldGen.START`).
  - `enum Region { EYE, STORMWALL, GALE, SHATTERED, CALM, RIM }`, `const REGION_NAMES := ["The Eye", "The Stormwall", "The Gale Expanse", "The Shattered Belt", "The Calm Reaches", "The Rim"]`, `const REGION_OUTER := [1600.0, 2200.0, 4000.0, 6000.0, 8000.0]`.
  - `const TOWN_ISLAND := Vector3(240.0, -1.5, 160.0)` (a town island's top centre, from its dock) and `const TOWN_RADIUS := 130.0`.
  - `var world_seed: int`, `var towns: Array[Dictionary]`, `var landmarks: Array[Dictionary]`, `var wrecks: Array[Dictionary]`, `var rivers: Array[Dictionary]`, `var storms: Array[Dictionary]`.
  - `func _init(seed_value: int)` works all of those out.
  - `static func region_at(p: Vector3) -> int` (by horizontal distance from the origin; exactly 1,600 m is the Stormwall).
  - `static func chunk_of(p: Vector3) -> Vector2i` (`floori(p.x / CHUNK)`, `floori(p.z / CHUNK)`).
  - `static func chunk_origin(chunk: Vector2i) -> Vector3` (its corner at y 0).
  - `static func chunks_near(p: Vector3, radius: float) -> Array[Vector2i]`: chunks whose square comes within `radius` of `p` horizontally and within `RADIUS + CHUNK` of the centre, nearest first.
  - `func islands_in(chunk: Vector2i) -> Array[Dictionary]`: the chunk's plain islands plus the islands of the landmarks and wrecks whose `at` lies in it.
  - `func storm_center(index: int, time: float) -> Vector3` (y 0).
- Island dictionary: `{"id": String, "at": Vector3 (top centre), "radius": float, "depth": float, "seed": int, "trees": float (0–1), "waterfall": bool, "flat": bool, "site": String ("" | "landmark" | "wreck")}`.
- Town: `{"name": String, "dock": Vector3, "region": int, "seed": int, "island": island}`. Landmark: `{"name", "kind": "spire" | "arch" | "ruin", "at", "region", "seed", "island"}`. Wreck: `{"at", "region", "seed", "yaw": float, "roll": float, "island"}`. River: `{"points": PackedVector3Array, "width": float, "speed": float, "box": AABB}`. Storm: `{"orbit": float, "angle": float, "spin": float (rad/s), "radius": float}`.
- `Session`: `var requested_seed := -1` (set before starting; −1 picks one at random), `var world_seed := 0`, `const PROTOCOL_VERSION := 4`, `_welcome(roster, under_way, seed)`.
- `LaunchOptions.parse`: `--seed=N` gives `options["seed"]` for 0 ≤ N ≤ 2,147,483,647.

Rules:
- Every random choice uses a `RandomNumberGenerator` seeded with `hash([world_seed, ..., purpose])`: `"towns"`, `"landmarks"`, `"wrecks"`, `"rivers"`, `"storms"`, and `[world_seed, cx, cz, "islands"]` per chunk. Nothing uses the global random functions.
- **Towns** (`towns[0]` is the start):
  - `towns[0]`: dock at `START`, region CALM.
  - Then 3 more in the Calm Reaches, 3 in the Shattered Belt, 2 in the Gale Expanse and 1 at the Stormwall, in that order. For each, up to 400 darts: a point uniform by area in the region's ring, kept 150 m inside its edges, dock altitude 500–1,300 m. Take the first dart whose dock is at least 1,500 m (horizontally) from every earlier town's dock and whose town island (at `dock + TOWN_ISLAND`, radius `TOWN_RADIUS`) is inside the disc. If none fits, the town is skipped (with this spacing it never is; a test checks the count for 20 seeds).
  - The town island is `{"flat": true, "radius": TOWN_RADIUS, "depth": TOWN_RADIUS * 1.3, "trees": 0.25, "waterfall": true, "site": ""}`.
  - Names come from `name_town(rng)`: a first part from `["Ash", "Bright", "Cinder", "Dun", "Ever", "Fair", "Gull", "Harrow", "Iron", "Kestrel", "Lark", "Mill", "North", "Oak", "Pike", "Rook", "Salt", "Thorn", "Wind", "Yarrow"]` and a second from `["haven", "hold", "mere", "port", "reach", "stead", "wick", "moor", "fall", "ford", "crest", "gate"]`, redrawn until it's unused ("Gullhaven").
  - A town's **exclusion** is its dock area (`Dock.area(dock)`, grown 150 m) plus its island's disc grown 60 m. No other island, landmark or wreck overlaps it horizontally.
- **Landmarks:** 2 in the Calm Reaches, 2 in the Shattered Belt, 2 in the Gale Expanse, 1 at the Stormwall and 1 in the Eye. Darts as for towns (altitude 450–1,400, island radius 40–70), at least 800 m from every town's dock and every earlier landmark. Kind cycles spire, arch, ruin. Name: `["Hollow", "Grey", "Weeping", "Broken", "Sunward", "Lantern", "Iron", "Drowned", "Whistling", "Crowned"][i]` + `" Spire" | " Arch" | " Ruins"`, unique. Island: `radius` 40–70, not flat, `site: "landmark"`.
- **Wrecks:** 3 in the Calm Reaches, 10 in the Shattered Belt, 5 in the Gale Expanse, 2 at the Stormwall. Darts (altitude 350–1,500, island radius 25–45), at least 300 m from every town, landmark and earlier wreck. `yaw` 0–TAU, `roll` 0.15–0.45 rad. Island `site: "wreck"`.
- **Chunk islands** (`islands_in`):
  - The chunk's region is the region of its centre. Outside the disc (the chunk's nearest point over `RADIUS`), there are none.
  - Tries and radii by region: EYE 2 tries of 40–120 m; STORMWALL 1 try of 15–40 m; GALE 2 tries of 30–110 m; SHATTERED 4 tries of 15–60 m; CALM 2 tries of 25–100 m. Each try succeeds with probability 0.7.
  - Centre: uniform in the chunk, kept `radius + 8` m inside its edges (radius is capped at 115 m). Top altitude: 350–1,500 m (SHATTERED 300–1,700 m).
  - Refused if it pokes outside the disc, overlaps an earlier island of the chunk (horizontal gap under 20 m while the tops are within `(r1 + r2) * 1.3` m of each other in height), or overlaps any town exclusion or any landmark or wreck island grown 40 m.
  - `depth` is `radius * randf_range(1.0, 1.6)`, `trees` is `randf_range(0.2, 1.0)` (0.1–0.4 in the Stormwall), `waterfall` is `radius >= 35 and randf() < 0.35`, `seed` is `rng.randi()`, and `id` is `"%d,%d,%d" % [cx, cz, i]`.
  - Every random draw happens in a fixed order whether or not a try succeeds, so a refusal never shifts later islands.
- **Sky rivers:** `rng.randi_range(6, 10)` of them. Each: start angle 0–TAU, start distance 2,500–7,500 m, direction ±1, altitude 600–1,400 m, drift −150…150 m per point, 20 points 450 m apart along the arc (`θ += direction * 450 / r`), distance clamped to 1,000–7,900 m, altitude `a0 + 250 * sin(k * 0.5 + phase)`. `width` 60–120 m, `speed` 20–35 m/s, `box` the points' AABB grown by `2 * width`.
- **Storm cells:** `rng.randi_range(6, 10)` of them. `orbit` 2,400–3,800 m, `angle` 0–TAU, `radius` 150–400 m. They drift with the prevailing wind, counter-clockwise from above: `spin = -Wind.prevailing_speed(orbit) / orbit`. `storm_center(i, t) = Vector3(cos(angle + spin * t), 0, sin(angle + spin * t)) * orbit`.

The seed:
- `Session.start_solo` and `Session.host` set `world_seed = requested_seed if requested_seed >= 0 else randi() & 0x7fffffff`, before anything else happens.
- `_welcome` gains the seed. The host sends `world_seed`. A client checks `seed is int and 0 <= seed <= 0x7fffffff`; otherwise it ends the session with `The host sent a world this game can't make.`
- `Game._apply_launch_options` sets `Session.requested_seed = options.get("seed", -1)`.
- `NetCase`: `const SEED := 20260930`; `make_session` sets `session.requested_seed = SEED`.

- [ ] **Step 1: Write the failing tests** (`tests/test_world_gen.gd`, plain `TestCase` except the network ones):
  - `test_regions_by_distance_from_the_eye`: `region_at` of `(0, 900, 0)` is EYE, `(0, 0, 1599)` EYE, `(1600, 0, 0)` STORMWALL, `(0, 0, -3000)` GALE, `(4500, 0, 0)` SHATTERED, `(0, 0, 7000)` CALM, `(9000, 0, 0)` RIM.
  - `test_the_same_seed_builds_the_same_world`: two `WorldGen.new(42)` have equal `towns`, `landmarks`, `wrecks`, `rivers`, `storms` (compare with `var_to_str`), and equal `islands_in` for 50 chunks along a line through the disc. `WorldGen.new(43)` differs in `towns` and in at least one of those chunks.
  - `test_chunks_dont_depend_on_the_order_they_are_made_in`: `islands_in(Vector2i(10, 20))` is the same before and after asking for 30 other chunks.
  - `test_ten_towns_in_their_regions`: for seeds 1–20: 10 towns; `towns[0].dock == START`; regions in order CALM ×4, SHATTERED ×3, GALE ×2, STORMWALL ×1; docks at least 1,500 m apart; names unique and non-empty; every town island inside the disc.
  - `test_islands_keep_clear_of_towns_and_each_other` (seed 7, every chunk within 3 km of each town, and 200 chunks along a spoke): every island is in the disc, between 300 and 1,800 m, clear of every town exclusion, and clear of the chunk's other islands as the rule says.
  - `test_the_shattered_belt_is_densest`: over the whole disc for seed 7, islands per chunk in the Shattered Belt exceed each other region's. The disc has between 2,000 and 8,000 islands.
  - `test_landmarks_and_wrecks_have_their_own_islands`: 8 landmarks, 20 wrecks, in their regions; each appears in `islands_in(chunk_of(at))` with its `site` set, exactly once in the whole disc.
  - `test_rivers_and_storms`: 6–10 rivers of 20 points each, every point between 1,000 and 7,900 m from the centre; 6–10 storms. `storm_center(i, 0)` is `orbit` from the centre, and 100 s later it has moved counter-clockwise seen from above (its angle, `atan2(z, x)`, has decreased).
  - `test_chunks_near_lists_the_nearest_first`: `chunks_near(START, 2500)` has between 200 and 330 chunks, the first is `chunk_of(START)`, and distances never decrease.
  - Network (`extends NetCase`, in `tests/test_world_gen_net.gd`):
    - `test_the_seed_travels_with_the_handshake`: `host_and_join`; `client.world_seed == host.world_seed == NetCase.SEED`.
    - `test_host_and_guest_generate_the_same_chunks`: after `sail_together()`, `host_world.gen.islands_in(c) == client_world.gen.islands_in(c)` for the chunk under the ship. (Needs `World.gen` from Task 3; until then this test stays in the file but checks `WorldGen.new(host.world_seed)` against `WorldGen.new(client.world_seed)`. Task 3 switches it to the worlds' own.)
    - `test_a_junk_seed_is_refused`: a host whose Session script overrides `_seed_for_welcome() -> Variant` to return `-5` (the host's `_welcome` call takes its seed from that method, which normally returns `world_seed`): the client ends with `The host sent a world this game can't make.`
  - `tests/test_session.gd`: solo and host pick a seed in range when `requested_seed` is −1, and use `requested_seed` when set.
  - `tests/test_launch_options.gd`: `--seed=123` gives 123; `--seed=-1`, `--seed=abc` and `--seed=99999999999` are ignored.
- [ ] **Step 2: Run `./run_tests.sh world_gen`.** Expected: the tests fail (`WorldGen` doesn't exist).
- [ ] **Step 3: Implement** `WorldGen`, the seed in `Session` (and bump `PROTOCOL_VERSION` to 4), `--seed`, and `NetCase.SEED`.
- [ ] **Step 4: Run the whole suite.** Expected: everything passes.
- [ ] **Step 5: Commit** "Generate the world from a seed: regions, towns, landmarks, wrecks, rivers and storms".

### Task 2: Generated islands

Build-log item s05-02: "Generated islands: grassy tops, rocky undersides, trees, waterfalls".

**Files:**
- Create: `src/world/island_mesh.gd`, `tests/test_island_mesh.gd`

**Interfaces:**
- Consumes: the island dictionary from Task 1.
- Produces (`class_name IslandMesh`, all static, thread-safe: no nodes, no resources but `FastNoiseLite`):
  - `const LODS := [[32, 6, 8], [16, 3, 4], [8, 1, 2]]` (angles, top rings, underside rings).
  - `const LOD_END := [800.0, 1800.0, 3000.0]`: where each level of detail stops being drawn (the next starts there).
  - `static func rim(island: Dictionary, angle: float) -> float`: the outline's distance from the centre at `angle`, 0.85–1.0 of the radius (0.93–1.0 when `flat`).
  - `static func height(island: Dictionary, x: float, z: float) -> float`: the top's height above `island.at.y` at local `(x, z)`; 0 everywhere for `flat`; hills of up to `0.08 * radius`, falling to 0 at the rim.
  - `static func arrays(island: Dictionary, lod: int) -> Dictionary`: `{"vertices": PackedVector3Array, "normals": PackedVector3Array, "colors": PackedColorArray}`, flat-shaded triangles (three vertices each, one face normal each), local to `island.at`, wound so Godot draws the outside.
  - `static func collision_faces(island: Dictionary) -> PackedVector3Array`: level 0's vertices.
  - `static func trees(island: Dictionary) -> Array[Transform3D]`: local, standing on the top, each scaled 0.7–1.4 and turned.
  - `static func waterfall(island: Dictionary) -> Dictionary`: `{}` without one, else `{"from": Vector3 (local, on the rim), "out": Vector3 (horizontal unit, away from the centre), "width": float, "drop": float}`.

Shape rules:
- One `FastNoiseLite` per call, `seed = island.seed`, `frequency = 1.0 / island.radius`, simplex. Outline noise samples `(cos a, sin a) * 3` so it's periodic around the island.
- Top: rings from the centre (ring 0 is the centre point) out to the rim. Vertex `k` of ring `j` sits at angle `TAU * k / angles` and distance `rim(a) * j / rings`, at `height(x, z)`.
- Underside: rings from the rim down to a point `depth` below the top centre. Ring `j` shrinks by `(1 - j / under)^0.8`, and each vertex is pushed in or out by up to 12% with noise, except the rim ring, which must match the top's edge exactly.
- Colours: top grass `Color("6e8d4c")` varied ±8% by noise, earth `Color("7b6146")` on the outer ring; underside rock bands by depth between `Color("6b5a50")` and `Color("534740")`, with `Color("3b322d")` at the tip. Flat (town) tops are `Color("7f9a5a")`.
- Trees: `round(trees * radius² / 180)` spots, at most 120, by rejection inside 0.8 of the rim, at least 5 m apart.
- Waterfall: at a random angle, `from` on the rim at the top's height there, `width` 4–8 m, `drop` `depth + 150`.

- [ ] **Step 1: Write the failing tests** (`tests/test_island_mesh.gd`):
  - `test_an_island_is_the_same_every_time`: `arrays(island, 0)` equals itself called again, and equals it for a deep copy of the island.
  - `test_detail_falls_with_distance`: triangle counts for LOD 0 > LOD 1 > LOD 2 > 0; LOD 0 has exactly `angles * (2 * rings - 1) + angles * (2 * under - 1)` triangles (the centre ring and the underside's tip are fans), and the test computes it from `LODS`.
  - `test_the_mesh_is_closed_and_faces_out`: for LOD 0, every edge is shared by exactly two triangles (count edges with rounded vertex keys), and every face normal points away from the island's centroid axis (for top faces `normal.y > 0`, for underside faces `normal.y < 0.3`).
  - `test_the_top_matches_its_height_function`: a ray cast straight down (with `Geometry3D.ray_intersects_triangle` over the collision faces) at 30 random points inside 0.8 of the rim hits at `height(x, z)` within 0.5 m (the mesh is piecewise flat).
  - `test_town_islands_are_flat`: with `flat`, `height` is 0 at 50 points and every top vertex has y 0.
  - `test_trees_stand_on_the_top`: every tree is inside the rim, at `height` there within 0.5 m, and at least 5 m from every other.
  - `test_a_waterfall_pours_off_the_rim`: an island with `waterfall` has `from` within 0.5 m of the rim at its angle and `out` horizontal and unit length; without it, `{}`.
  - `test_islands_are_fast_enough`: 20 islands of radius 100 at LOD 0 take under 60 ms in total.
- [ ] **Step 2: Run `./run_tests.sh island_mesh`.** Expected: fail.
- [ ] **Step 3: Implement** `IslandMesh`.
- [ ] **Step 4: Run it, then the whole suite.** Expected: pass.
- [ ] **Step 5: Commit** "Shape floating islands from their seeds: grassy tops, rocky undersides, trees and waterfalls".

### Task 3: Streaming the world in chunks

Build-log item s05-03: "Stream the world in chunks around each ship, with level of detail".

**Files:**
- Create: `src/world/world_chunk.gd`, `src/world/world_streamer.gd`, `tests/test_streaming.gd`
- Modify: `src/world/world.gd`, `src/net/world_sync.gd`, `tests/test_world.gd`, `tests/test_world_gen_net.gd`

**Interfaces:**
- Consumes: `WorldGen` (Task 1), `IslandMesh` (Task 2).
- Produces:
  - `WorldChunk.generate(gen: WorldGen, chunk: Vector2i, visuals: bool) -> Dictionary` (thread-safe): `{"chunk", "islands": Array[Dictionary], "lods": [arrays, arrays, arrays] (merged per level, chunk-local), "faces": PackedVector3Array (chunk-local), "trees": PackedFloat32Array (MultiMesh transform buffer, chunk-local), "falls": Array[Dictionary] (chunk-local), "clouds": ... (Task 6 adds it)}`. Without `visuals`, only `islands` and `faces`.
  - `WorldChunk.build(data: Dictionary) -> Node3D` (main thread): a `Node3D` named `"Chunk%d_%d"` at `WorldGen.chunk_origin(chunk)` with:
    - three `MeshInstance3D` (one per level, `visibility_range_end = IslandMesh.LOD_END[i]`, `visibility_range_begin` the previous level's end, `visibility_range_end_margin` and `begin_margin` 20),
    - a `MultiMeshInstance3D` of trees (`visibility_range_end` 1,200),
    - a waterfall `MeshInstance3D` per fall (`visibility_range_end` 1,800),
    - one `StaticBody3D` with one `ConcavePolygonShape3D` of every island's faces (`backface_collision` off),
    - and the site nodes (Task 5 adds them).
  - `WorldChunk.ground_material() -> StandardMaterial3D` (vertex colours, roughness 1), `tree_mesh() -> ArrayMesh`, `water_material() -> ShaderMaterial`: each made once, in static vars.
  - `class_name WorldStreamer extends Node3D`:
    - `const LOAD_RADIUS := 2500.0`, `const UNLOAD_RADIUS := 2800.0`, `const BUDGET_USEC := 3000`, `const MAX_JOBS := 8`, `const REPLAN_EVERY := 0.25`.
    - `var gen: WorldGen`, `var visuals := true`, `var focus: Callable` (returns `Array[Vector3]`), `var chunks: Dictionary` (`Vector2i -> Node3D`).
    - `func _init(world_gen: WorldGen, with_visuals: bool)`.
    - `func pending() -> int`: chunks wanted but not added yet. `func settled() -> bool`.
    - `func replan() -> void`: recomputes what's wanted now (called every `REPLAN_EVERY`, and by tests).
  - `World`: `var gen: WorldGen`, `var wind: Wind` (Task 4), `var streamer: WorldStreamer`; `const START := WorldGen.START`.
  - `WorldSync.focus_points() -> Array[Vector3]`: on the server every ship's position plus every ashore player's (Task 8) plus this machine's player's; on a client this machine's player's world position (its ship's until Task 6).

Streamer rules:
- Each replan: `wanted` = every chunk in `gen.chunks_near(p, LOAD_RADIUS)` for each focus point, nearest to any focus first. Start a job for each wanted chunk that's neither loaded nor in flight, up to `MAX_JOBS` in flight (`WorkerThreadPool.add_task`). Free each loaded chunk further than `UNLOAD_RADIUS` from every focus point (horizontal distance to the chunk's square).
- A job calls `WorldChunk.generate` and pushes its result onto a list guarded by a `Mutex`.
- Each `_process`: take finished results, nearest first, and `build` them until `BUDGET_USEC` is spent (at least one per frame). A result for a chunk no longer wanted is dropped. Then collect finished jobs' task ids with `WorkerThreadPool.wait_for_task_completion` (they're done, so it doesn't block).
- `_exit_tree` waits for every job still in flight, so no worker touches a freed world.
- The streamer runs in `_process` (a dedicated server's frames run at the physics rate).
- `World._ready` makes `gen = WorldGen.new(session.world_seed)` and the streamer with `visuals = not session.dedicated`, with `focus = sync.focus_points`, and removes `ISLANDS` and the placeholder islands. `Island` stays for the menu backdrop and old tests.
- Depth fog hides the streaming edge: `WorldSky` sets `fog_depth_begin = 900.0` and `fog_depth_end = 2600.0`. `PlayerController`'s camera `far` becomes 3,200.

- [ ] **Step 1: Write the failing tests** (`tests/test_streaming.gd`, `extends NetCase`):
  - `test_the_world_streams_in_around_the_ship`: a solo world; `await wait_until(world.streamer.settled, 20)`; every chunk in `chunks_near(ship position, 2500)` is loaded, and none further than 2,800 m. Each loaded chunk has a `StaticBody3D`, and its three meshes have the visibility ranges above.
  - `test_chunks_far_away_are_freed_and_come_back_the_same`: move the ship 3 km (set `global_position`, `reset_physics_interpolation`), `replan`, settle: the old chunks are freed and new ones loaded. Move back and settle: the chunk under `START`'s first island has the same collision faces as before (compare `faces`).
  - `test_a_fast_ship_never_outruns_the_collision`: a solo world, the ship pushed to 60 m/s along −X each tick for 60 s (`linear_velocity` set before each tick, calm): at every tick, `chunk_of(ship position)` and its 8 neighbours are loaded (checked every 30 ticks).
  - `test_islands_are_solid`: in a solo world after settling, a ray straight down onto the top of the nearest generated island (from `gen.islands_in`) hits it within 1 m of `at.y + IslandMesh.height(…)`.
  - `test_freeing_the_world_mid_generation_is_clean`: a solo world, `replan()`, then free the world the next frame. No engine errors (the runner checks), and `await get_tree().process_frame` twice more.
  - `test_a_dedicated_server_loads_collision_only`: a dedicated host's world (`host.host("Server", port, true)`, then `add_world(host)`), settled: chunks have a `StaticBody3D` and no `MeshInstance3D`.
  - `test_host_and_guest_generate_the_same_chunks` in `test_world_gen_net.gd` switches to `host_world.gen` and `client_world.gen`, and also compares the collision faces of the chunk under the ship in both worlds once each has loaded it.
  - `tests/test_world.gd`: `test_islands_are_solid` moves to `test_streaming.gd` as above; the placeholder `Island` test stays as `test_placeholder_islands_are_solid` (the menu backdrop still uses them).
- [ ] **Step 2: Run `./run_tests.sh streaming`.** Expected: fail.
- [ ] **Step 3: Implement** `WorldChunk`, `WorldStreamer`, `WorldSync.focus_points()`, and the `World` changes.
- [ ] **Step 4: Run the whole suite, then fly by hand** (`godot --path . -- --solo`): islands appear around you and none pops up close by.
- [ ] **Step 5: Commit** "Stream the generated world in chunks around every ship and player, with three levels of detail".

### Task 4: Wind, sky rivers, storm cells and sails

Build-log item s05-04: "Wind: prevailing wind, sky rivers and storm cells; sails catch it".

**Files:**
- Modify: `src/world/wind.gd` (rewrite), `src/ship/ship.gd`, `src/ship/tuning.gd`, `src/net/world_sync.gd`, `src/world/world.gd`, `src/ui/hud.gd`, `tests/test_ship_forces.gd`, `tests/test_world.gd`
- Create: `tests/test_wind.gd`

**Interfaces:**
- Consumes: `WorldGen.rivers`, `storms`, `storm_center` (Task 1).
- Produces (`class_name Wind extends RefCounted`):
  - `func _init(world_gen: WorldGen = null)`: without a `WorldGen`, no rivers or storms.
  - `var time := -1.0`: the world clock in seconds; below 0, `now()` uses physics ticks since the game started.
  - `func now() -> float`.
  - `func at(p: Vector3, t: float) -> Vector3`.
  - `static func prevailing_speed(distance: float) -> float` and `static func gust_strength(distance: float) -> float`, piecewise linear through these points (distance m → prevailing m/s, gusts m/s): (0 → 3, 1.5), (1,400 → 5, 2), (1,600 → 10, 8), (1,900 → 14, 14), (2,200 → 12, 6), (2,400 → 12, 4), (4,000 → 12, 4), (6,000 → 5, 3), (8,000 → 2, 2.5), and flat beyond.
  - `func river_at(p: Vector3) -> Vector3`, `func storm_strength(p: Vector3, t: float) -> float` (0–1).
- `Tuning.SAIL_AREA := 6.0` (m²), `Tuning.SAIL_COEFFICIENT := 1.2`.
- `Ship.weather: Wind` (set by `WorldSync._add`; a ship without one makes `Wind.new()` in `_ready`).
- `Hud.wind: Wind` (set by the World), and `Hud.readout(ship: Ship, wind := Vector3.ZERO) -> String` gains the line `Wind      %2d m/s from %03d°`.
- `static func Hud.bearing(v: Vector3) -> int`: the compass bearing `v` points toward, 0–359.

Wind at `p`, time `t`, with `d` the horizontal distance from the centre:
1. **Prevailing:** `prevailing_speed(d)` along `Vector3(p.z, 0, -p.x) / d` (counter-clockwise seen from above), or zero within 1 m of the centre.
2. **Rim:** beyond 8,000 m, `-Vector3(p.x, 0, p.z) / d * 15 * clampf((d - 8000) / 1000, 0, 1)`: back toward the centre.
3. **Gusts:** today's sum of sines (keep its frequencies), scaled by `gust_strength(d)` instead of `GUSTS`.
4. **Rivers:** for each river whose `box` has `p`: the nearest point on its polyline (segment by segment), at distance `s`. The push is `speed * (1 - smoothstep(width, 2 * width, s))` along that segment's direction. The strongest river counts (don't add them up). Near each end of a river the push fades to 0 over its first and last segment (multiply by `smoothstep(0, 1, u)` where `u` is the fraction of the way along the first segment, and likewise for the last).
5. **Storms:** strength `k = 1 - smoothstep(0.6 * radius, radius, distance to storm_center)` for the strongest storm. The storm adds `k * 10` m/s of extra gusts (the same sines at twice the frequency) and `k * 6 * sin(t * 0.9 + p.x * 0.01)` m/s straight up.

Ships:
- `Ship._integrate_forces` uses `weather.at(origin, weather.now())` (zero when `calm`).
- **Sails** (each sail cell, normal `n = basis * Blocks.facing(rotation)` in world space): `flow = (wind - v_point).dot(n)`, force `0.5 * Tuning.AIR_DENSITY * ρ * Tuning.SAIL_COEFFICIENT * Tuning.SAIL_AREA * flow * |flow| * n` at the sail. A sail pushes along its normal either way the wind hits it.
- `WorldSync` sets `wind.time = now()` every physics tick, before ships fly, on the server and clients, and gives each ship `weather = wind` in `_add`.
- The HUD's helm readout shows the wind at the ship: `Wind      12 m/s from 045°` (the bearing the wind comes from, `bearing(-w)`), under the heading line.

- [ ] **Step 1: Write the failing tests** (`tests/test_wind.gd`):
  - `test_the_prevailing_wind_rises_toward_the_gale`: averaged over 600 s (to cancel gusts), `Wind.new()` at `(0, 800, 7000)` blows east at `prevailing_speed(7000)` (3.5 m/s) ± 0.3, and at `(0, 800, -3000)` blows west at 12 ± 0.5.
  - `test_the_rim_pushes_you_back`: at `(0, 800, 9500)` the wind's z is below −10 (inward), averaged over 600 s.
  - `test_the_wind_is_finite_and_continuous_everywhere`: with `WorldGen.new(7)`: at the exact centre, at `(8000, 0, 0)`, at a river's first point and in 2,000 random points up to 10 km out, the wind is finite. Along 200 straight 1 m steps through a river's core, a storm's edge and the Stormwall, no two neighbours differ by more than 3 m/s (at a fixed time).
  - `test_a_river_is_strong_in_its_core`: at a river's middle point, the push is within 1 m/s of `speed` along the segment's direction; `2 * width + 1` m away it's zero.
  - `test_a_river_fades_smoothly_at_its_edge_and_ends`: past a river's last point (500 m on along its last segment) its push is zero, and 1 m steps across `width`…`2 * width` never jump more than 1 m/s.
  - `test_storms_drift_and_blow`: in a storm's centre the wind differs from outside by gusts that reach at least 8 m/s over 60 s; 300 s later the storm has moved and its old centre is calm again, if it moved more than its radius.
  - `test_the_same_seed_gives_the_same_wind`: two `Wind.new(WorldGen.new(9))` agree exactly at 100 points and times.
  - `test_sails_catch_the_wind` (a `TestCase` with ships): two starter ships at `(0, 880, 7000)` and `(200, 880, 7000)`, not calm, with the wind replaced by a `Wind` subclass in the test that returns a steady `(10, 0, 0)`. One has four sails facing starboard (rotation `Blocks.turned(0)`, normal +X) on its rails. After 20 s the sailed ship has gone further east than the plain one by at least 20%. A sail facing the bow in the same wind adds nothing east.
  - `tests/test_ship_forces.gd`: the old prevailing-wind test moves into `test_wind.gd` as the first test above.
  - `tests/test_world.gd`: `test_the_helm_readout` passes `Vector3(0, 0, -10)` and expects `Wind      10 m/s from 180°`.
- [ ] **Step 2: Run `./run_tests.sh wind`.** Expected: fail.
- [ ] **Step 3: Implement** the field, sails, the clock, and the readout.
- [ ] **Step 4: Run the whole suite.** Expected: pass. Flight tests fly `calm`, so they don't change.
- [ ] **Step 5: Commit** "Blow wind through sky rivers and storm cells, push ships' sails, and show the wind at the helm".

### Task 5: Towns, docks, wrecks and landmarks

Build-log item s05-05: "Towns with docks and shipyards, wrecks, landmarks".

**Files:**
- Create: `src/world/town.gd`, `src/world/sites.gd`, `tests/test_towns.gd`
- Modify: `src/world/dock.gd`, `src/world/world.gd`, `src/world/world_chunk.gd`, `src/net/world_sync.gd`, `tests/test_fleet.gd`, `tests/test_launch.gd`, `tests/test_shipyard.gd`

**Interfaces:**
- Consumes: towns, landmarks, wrecks from Task 1; `IslandMesh`; `WorldChunk.build`.
- Produces:
  - `Dock`: `const PIER := AABB(Vector3(3, -6.5, -12), Vector3(4, 5, 42))` (beside each slipway, from the quay forward); `create(at)` draws and collides the quay and every pier, and no island; `obstacles(at)` is the quay, the piers and the town island (`at + WorldGen.TOWN_ISLAND`, `TOWN_RADIUS` across, from `depth` below to 40 m above the top, which covers the houses and the beacon).
  - `Town.create(town: Dictionary, visuals: bool) -> Node3D`: the dock, the town island (three levels of detail and collision, as a chunk island), houses, a beacon tower and a sign.
  - `Sites.wreck_grid(wreck: Dictionary) -> ShipGrid`, `Sites.create_wreck(wreck, visuals) -> Node3D`, `Sites.create_landmark(landmark, visuals) -> Node3D`.
  - `World.towns: Array[Node3D]`; `World.town_at(p: Vector3) -> int` (the town whose dock `p` is near, or −1); `World.at_dock()` is `town_at(your position) >= 0`.
  - `WorldSync.docks: Array[Vector3]` (set by the World from `gen.towns`, replacing `berths`, `test_berths` and `obstacles`); `berth_of(peer, test, town := 0)`; `launch(grid, test, town := 0) -> bool`; `_launch(blocks, paint, test, town)`.
  - `World.test_flight(grid)` and `launch(grid)` launch from `town_at(your position)` (0 if none).
  - `Shipyard.new(design, altitude)` gets the town's dock altitude.

Town rules (all from `rng` seeded with `town.seed`):
- **Houses:** on a 22 m grid over the town island's top, cells whose centre is within 0.75 of the radius and more than 30 m behind the quay's back edge (local z > 74 from the dock), each taken with probability 0.55. A house is a box 6–10 × 4–7 × 6–10 m with a roof prism 3 m high, turned by a multiple of 90°. Walls from `["e9dfc9", "d9b77e", "c98f7a", "a9bfcf", "f2ead8"]`, roofs from `["a4553b", "5b6068", "7d5a6b"]`. One merged mesh (vertex colours, `WorldChunk.ground_material()`), and a `BoxShape3D` per house.
- **Beacon:** a stone tower 5 m square and 28 m high at the island's centre, topped by a 3 m emissive cube (`Color("ffd27a")`, emission energy 3), so towns can be found from afar. It collides.
- **Sign:** a `Label3D` with the town's name, 6 m above the quay at slipway 0's end, `billboard` on, `font_size` 96, `pixel_size` 0.05, `visibility_range_end` 600.
- Town nodes are named `"Town%d"` and live under `World/Towns`. They are built in `World._ready`, all ten; on a dedicated server with `visuals` false (collision only).
- The World no longer adds `Dock.create(START)` itself; the dock comes with town 0.

Wrecks and landmarks:
- `WorldChunk.generate` includes the chunk's sites (islands whose `site` isn't ""), and `build` adds `Sites.create_wreck` / `create_landmark` for them.
- **Wreck:** `StarterShip.build()` with every balloon removed and then each other block removed with probability 0.35 (rng from `wreck.seed`, visiting cells in sorted order so it's deterministic). Drawn with `ShipMesh.build`, collided with `merged_boxes()` in a `StaticBody3D`. It rests on its island: its lowest cell 1 m into the top at the island centre, turned by `yaw` and rolled by `roll`.
- **Landmark:** built from boxes and prisms in `Color("8d8578")` stone, on its island's top:
  - spire: a tapering four-sided needle 60–110 m tall (a frustum mesh), a box collision per 20 m;
  - arch: two 8 × 40 × 8 m pillars 30 m apart joined by a 46 × 8 × 8 m lintel;
  - ruin: a ring of 8 columns (3 × 6–18 × 3 m) on a 24 m radius, and a 30 m round floor slab.
  - Each has a `Label3D` of its name 10 m above its top (visibility 400 m).

- [ ] **Step 1: Write the failing tests** (`tests/test_towns.gd`, `extends NetCase`):
  - `test_ten_towns_stand_in_the_world`: a solo world has ten `Town` nodes under `World/Towns`, at their docks, each with a `Label3D` of its name, and town 0's dock is at `START`.
  - `test_a_town_has_houses_a_beacon_and_piers`: `Town.create(gen.towns[1], true)` has at least 6 house shapes plus the beacon's, and `Dock.obstacles(dock)` contains a pier beside each slipway. No house box intersects a pier, the quay or the slipways' area.
  - `test_you_can_walk_from_a_pier_to_the_town`: a ray down from 10 m above every point along the pier of slipway 0 (every 2 m), then along the quay to the island, then 20 m into the island, hits something at y within 0.1 of `dock.y - 1.5` (the quay's and pier's top and the town's flat top).
  - `test_the_shipyard_opens_at_any_towns_dock`: move the ship beside town 3's slipway 0 (set its transform to `Dock.slipway(gen.towns[3].dock, 0)`), press B: the shipyard opens, with stats at that dock's altitude. 2 km away it doesn't.
  - `test_launching_at_another_town_uses_its_slipways`: at town 3, `world.launch(StarterShip.build())`: your new ship is at `Dock.slipway(gen.towns[3].dock, 0)` (or raised clear above it).
  - `test_the_server_ignores_launches_at_junk_towns`: after `sail_together()`, the client calls `sync._launch.rpc_id(1, bytes, {}, false, X)` for X in `99`, `-1`, `"0"`, `1.5`: no ship is added.
  - `test_wrecks_and_landmarks_are_built_where_the_world_says`: a `WorldChunk.build(WorldChunk.generate(gen, chunk_of(w.at), true))` for the first Shattered Belt wreck has a wreck node whose mesh exists and whose body has at least 20 boxes; the same for a landmark, with its `Label3D`. `Sites.wreck_grid` is the same twice and has no balloons.
  - `tests/test_fleet.gd`: the obstacle test covers the piers and the town island; slipways and berths are unchanged.
  - `tests/test_launch.gd` and `test_shipyard.gd`: the berths now come from `sync.docks`.
- [ ] **Step 2: Run `./run_tests.sh towns`.** Expected: fail.
- [ ] **Step 3: Implement** towns, the dock's piers, sites in chunks, and launching from any town.
- [ ] **Step 4: Run the whole suite, then look by hand:** the starting town from the ship, the sign, the piers, a wreck on the way.
- [ ] **Step 5: Commit** "Build ten towns with docks and shipyards, and wrecks and landmarks on their own islands".

### Task 6: On foot, gliding and anchoring

Build-log item s05-08: "On foot: leave the ship, explore islands, glide back; anchor the ship".

**Files:**
- Create: `tests/test_ashore.gd`
- Modify: `src/crew/crew_member.gd`, `src/crew/player_controller.gd`, `src/crew/helm.gd`, `src/ship/ship.gd`, `src/world/world.gd`, `src/net/world_sync.gd`, `src/ui/hud.gd`, `project.godot`, `tests/test_crew.gd`, `tests/test_world.gd`, `tests/test_project.gd`, `tests/test_world_sync.gd`

**Interfaces:**
- Consumes: streamed collision (Task 3), towns and piers (Task 5).
- Produces:
  - `CrewMember`: `ship` may be null (ashore: `position` and `velocity` are in world space); `const GLIDE_SPEED := 13.0`, `GLIDE_SINK := 3.0`, `FALL_LIMIT := 50.0`, `LEAVE_AFTER := 0.2`, `REBOARD_AFTER := 0.5`; `var glide := false` (set by the controller: Space held); `var gliding: bool` (read-only: gliding this tick); signals `left_ship`, `landed_on(ship: Ship)`, `lost`. `fell_overboard` and `OVERBOARD` go.
  - `Ship`: `var anchored := false` (setter: on a simulated ship, stops it and sets `freeze`; `WorldSync`'s dedicated anchoring freezes `anchored or nobody aboard`); `func is_over(world_point: Vector3) -> bool`; `func point_velocity(world_point: Vector3) -> Vector3`.
  - `Helm.ask_anchor(peer: int, on: bool)`: the pilot only, like the autopilot; on a client it emits `asked("anchor", on)`.
  - `PlayerController`: `ship` is null while ashore; `signal left_ship`, `signal landed_on(ship: Ship)`, `signal lost`; `func world_position() -> Vector3`; `func ship_in_reach() -> Ship` (ashore: the nearest ship whose world box grown 3 m holds you); `prompt()` gains `Climb aboard`, `Drop anchor`, `Raise anchor` hints (see below).
  - `World`: `func go_ashore()`, `func come_aboard(target: Ship, local: Vector3)`, `func rescue()`; `World.ship` is null while ashore; `World.left: Ship` (the ship you last stepped off, while it's here).
  - Actions: `anchor` G, and (Task 7) `map` M.

Leaving and boarding:
- **Leaving** (aboard, not at a station, not on a ladder): count the time without floor. When it reaches `LEAVE_AFTER` and `ship.is_over(ship.global_transform * position)` is false, emit `left_ship` once. `is_over` casts a ray in the main world from the point straight down `bounds.size.length() + 2` m, and is true when it hits this ship. It needs the physics space, so the check runs in `_physics_process`.
- **`World.go_ashore()`:** a new `CrewMember.new(null, world point)`, added to the World. Its `velocity` is `ship.point_velocity(point) + ship.global_basis * crew.velocity`, capped at `FALL_LIMIT`; its `look_yaw` keeps the world direction you were facing. `World.left = ship`, `World.ship = null`, and the player's controls move to it (`player.board(crew)`, the same as boarding).
- **Ashore:** gravity is `(0, −9.81, 0)` and up is `+Y`. Walking, sprinting and jumping work as on deck. Falling speed is capped at `FALL_LIMIT`. While airborne with `glide` held (after falling for 0.3 s or on a second press of Space in the air), horizontal velocity eases toward `GLIDE_SPEED` along the look direction, plus `move.x` turning it (A/D), at rate `1 - exp(-2 * delta)`, and the fall is capped at `GLIDE_SINK`.
- **Landing on a ship:** after `move_and_slide`, a slide collision whose collider is a `Ship` and whose normal has `y > 0.6`, more than `REBOARD_AFTER` s after going ashore, emits `landed_on(ship)`. `World.come_aboard(ship, ship.to_local(crew position))` boards it there, with zero velocity.
- **E next to a hull** (ashore, `ship_in_reach()` not null, on the floor): `Climb aboard` boards that ship at `crew_spawn(my_slot())`.
- **The Roil:** ashore below `Tuning.ROIL_ALTITUDE` emits `lost`. `World.rescue()` boards, in order, `left`, your own ship, the host's ship, at `crew_spawn(my_slot())`, and the HUD says `The Roil nearly took you. Back aboard!`.
- **Your own ship arriving while ashore** (a launch you asked for) boards you as before. Your ship being removed while ashore leaves you ashore; `left` becomes null if it was that ship.
- `at_dock()` and the shipyard use `player.world_position()`. The shipyard's design starts from your ship's grid, or the starter ship's while ashore.

Anchoring:
- At the helm, G asks to anchor or weigh anchor. `Ship.anchored = true` zeroes the ship's velocities and freezes it; false unfreezes it (unless a dedicated server holds it for nobody aboard).
- The 12th field of each snapshot is `anchored`; clients set it (their ships stay frozen kinematic copies either way).
- The helm readout adds `Anchored` as its last line while anchored. The helm's caption becomes `W/S throttle · A/D rudder · Space/Ctrl climb · H autopilot · G anchor · V view · E leave`.

Network:
- `WorldSync._my_crew()` ashore returns `[0, crew.position, crew.velocity, crew.look_yaw, pitch]`.
- The server accepts `ship_id == 0` reports per the protocol table, and draws ashore crew in world space (`Transform3D.IDENTITY` in place of a ship's). Ashore crew can't take a helm.
- `focus_points()` adds every ashore player's last reported position on the server, and on a client uses `player.world_position()`.

HUD prompts, in priority order: at a station `E   Leave the helm`; `E   Take the helm`; `%s is at the helm`; ashore with a ship in reach and on the floor `E   Climb aboard`; ashore in the air not gliding `Hold Space   Glide`; `B   Shipyard`.

- [ ] **Step 1: Write the failing tests** (`tests/test_ashore.gd`, `extends NetCase`, in a solo world after the streamer settles, the ship `calm` and anchored unless the test says otherwise):
  - `test_jumping_on_deck_stays_aboard`: jump three times in the middle of the deck (`crew.jump = true`, simulate 1.2 s each): still aboard (`world.ship` not null, the crew's parent the interior).
  - `test_walking_off_the_side_goes_ashore_with_the_ships_speed`: unanchored and moving at 10 m/s east (`linear_velocity` set, calm): walk to starboard over the rail (jump and move). Within 3 s you're ashore: your crew's parent is the World, `world.ship` is null, `world.left` is the ship, and your velocity's x is at least 9.
  - `test_you_dont_bounce_straight_back_aboard`: after going ashore from an anchored ship, `landed_on` doesn't fire for 0.5 s even though you start touching its hull.
  - `test_walking_on_an_island`: put your ashore crew 2 m above the nearest generated island's top centre: after 3 s you're on the floor within 1 m of its height, and walking forward 3 s moves you at least 10 m.
  - `test_gliding_goes_far_and_falls_slowly`: ashore 300 m above nothing, facing north, `glide = true`: after 10 s you've fallen less than 40 m and moved at least 100 m north. Without gliding you'd have fallen over 300 m (check the same from another spot: at least 250 m, capped at `FALL_LIMIT`).
  - `test_landing_on_a_deck_boards_that_ship`: ashore 5 m above the middle of a second ship's deck (added with `sync.add_ship`, anchored): you land and come aboard it, standing on its deck; `world.ship` is it.
  - `test_climbing_aboard_from_the_pier`: ashore on slipway 0's pier beside your ship: the prompt reads `E   Climb aboard`; pressing E puts you aboard at `crew_spawn`.
  - `test_the_roil_sends_you_back_aboard`: ashore at y 190: you're back aboard the ship you left, and the HUD message is `The Roil nearly took you. Back aboard!`.
  - `test_a_new_ship_arriving_while_ashore_boards_you`: ashore, `world.launch(StarterShip.build())`: once it arrives you're at its helm.
  - `test_an_anchored_ship_stays_put_in_a_storm`: a ship at a storm's centre (not calm, `weather` from the world), anchored: after 20 s it hasn't moved or turned. Weighing anchor, it moves within 5 s.
  - `test_only_the_pilot_anchors`: `ask_anchor` from someone not at the helm does nothing; from the pilot it anchors.
  - Network: `test_a_guest_ashore_is_seen_where_they_are`: after `sail_together()`, the guest goes ashore; within 1 s the host draws their avatar within 2 m of their world position. A report with ship 0 from 20 km away, or at 80 m/s, is ignored.
  - Network: `test_anchoring_reaches_the_guest`: the host anchors; the guest's copy of the ship has `anchored` within 1 s.
  - `tests/test_crew.gd`: `test_falling_overboard_brings_you_back_aboard` becomes `test_falling_off_the_deck_asks_to_leave`: a crew member 5 m off the side of a ship (in a world with no ground) emits `left_ship` once within 0.5 s.
  - `tests/test_world.gd`: the overboard part of `test_boarding_another_ship_moves_you_and_your_controls` goes.
  - `tests/test_project.gd`: `anchor` is G.
- [ ] **Step 2: Run `./run_tests.sh ashore`.** Expected: fail.
- [ ] **Step 3: Implement** crew ashore, leaving and boarding, gliding, the Roil rescue, anchoring, the network changes and the prompts.
- [ ] **Step 4: Run the whole suite, then play by hand:** step off at the dock onto the pier, walk into town, glide off the island edge back to the ship, anchor at an island and walk it.
- [ ] **Step 5: Commit** "Go ashore on foot, glide, climb back aboard, and anchor ships".

### Task 7: Clouds, fog layers and lightning

Build-log item s05-06: "Clouds, fog layers and lightning in the Roil".

**Files:**
- Create: `src/world/weather.gd`, `tests/test_weather.gd`
- Modify: `src/world/world_chunk.gd`, `src/world/roil.gd`, `src/world/world.gd`

**Interfaces:**
- Consumes: `WorldGen.storms`, `storm_center` (Task 1); chunks (Task 3).
- Produces:
  - `WorldChunk.clouds(gen: WorldGen, chunk: Vector2i) -> Array[Transform3D]` (thread-safe, from `hash([seed, cx, cz, "clouds"])`): cloud puffs, chunk-local. `generate` puts them in `data["clouds"]` and `build` adds a `MultiMeshInstance3D` (`visibility_range_end` 3,000, no shadows).
  - `WorldChunk.puff_mesh() -> ArrayMesh`: a low-poly icosphere (one subdivision), made once; `cloud_material()`: white, `roughness` 1, a little `rim`, vertex colour off.
  - `class_name Weather extends Node3D`: `func _init(world_gen: WorldGen, clock: Callable)` (the clock returns world seconds); `const SHEETS := [240.0, 290.0]`; `func strike(from: Vector3, to: Vector3) -> MeshInstance3D` (a bolt, for tests too); `var bolts_struck := 0`.

Rules:
- **Clouds per chunk:** clusters by region: CALM 0–1, SHATTERED 0–2, GALE 1–3, STORMWALL 4–6, EYE 0. A cluster is 5–12 puffs around a point at 900–2,200 m, each puff scaled 20–60 m wide and 0.5–0.7 of that high, spread 80 m.
- **Fog sheets:** two huge planes (like the Roil's) at `SHEETS` heights that follow the camera, with a shader: noise-streaked alpha 0–0.55 in `Color("9d8ea6")`, fading to 0 within 30 m of the camera's height so you fly through them cleanly. `cull_disabled`, unshaded, `depth_draw_never`.
- **Storm columns:** each storm is drawn as a dark column of 20 puffs (MultiMesh), from 250 m to 2,000 m, `radius` wide, moved to `storm_center(i, clock())` each frame.
- **Lightning:** every 2–9 s (as the Roil flashes now) a bolt strikes in the Roil within 1 km of the camera, 60 m under the surface, horizontal-ish. Every 1–4 s inside each storm within 3 km of the camera, a bolt runs from 1,800 m down to the Roil within its radius. A bolt is a jagged ribbon (10–14 segments, jittered ±10% of its length sideways, 3 m wide, facing the camera when struck), emissive `Color("c7d4ff")` at energy 6, with an `OmniLight3D` (range 900 m) for 0.15 s, flickering. The Roil keeps its own surface flash.
- Weather is only visual: every machine makes its own bolts, and a dedicated server has no `Weather`.

- [ ] **Step 1: Write the failing tests** (`tests/test_weather.gd`):
  - `test_clouds_are_the_same_every_time`: `WorldChunk.clouds(gen, c)` twice gives the same puffs; the Stormwall's chunks average more than the Calm Reaches'; the Eye has none; every puff is between 850 and 2,300 m.
  - `test_chunks_carry_their_clouds`: a built chunk with clouds has a `MultiMeshInstance3D` with that many instances and `visibility_range_end` 3,000.
  - `test_storm_columns_follow_their_storms`: a `Weather` with a clock returning 500 s: after a frame, column `i`'s position is `storm_center(i, 500)` horizontally.
  - `test_a_bolt_joins_its_ends`: `strike(a, b)`'s mesh has its first vertex within 2 m of `a` and its last within 2 m of `b`; it's gone after 0.5 s.
  - `test_storms_strike`: a `Weather` with a camera inside a storm strikes at least one bolt within 5 s (`bolts_struck`).
  - `test_a_dedicated_world_has_no_weather`: a dedicated host's world has no `Weather` child.
- [ ] **Step 2: Run `./run_tests.sh weather`.** Expected: fail.
- [ ] **Step 3: Implement** clouds in chunks, `Weather`, and add it in the World (not on a dedicated server).
- [ ] **Step 4: Run the whole suite, then look by hand** at dusk: sheets over the Roil, storm columns in the Gale Expanse, bolts.
- [ ] **Step 5: Commit** "Fill the sky with clouds, fog sheets over the Roil, storm columns and lightning".

### Task 8: The map and compass

Build-log item s05-07: "Map and compass that fill in as you explore".

**Files:**
- Create: `src/world/exploration.gd`, `src/ui/map_view.gd`, `src/ui/compass.gd`, `tests/test_map.gd`
- Modify: `src/world/world.gd`, `src/ui/hud.gd`, `project.godot`, `tests/test_project.gd`

**Interfaces:**
- Consumes: `WorldGen` (towns, landmarks, wrecks, rivers, `islands_in`, `region_at`); `WorldSync.ships`; `PlayerController.world_position()` (Task 6).
- Produces:
  - `class_name Exploration extends RefCounted`: `const CELL := 128.0`, `const SIZE := 128` (cells across, covering −8,192…8,192 m), `const SIGHT := 1200.0`; `func reveal(p: Vector3) -> bool` (true if anything new was seen); `func seen(p: Vector3) -> bool`; `func seen_fraction() -> float`; `var image: Image` (`SIZE × SIZE`, `FORMAT_L8`, 255 where seen).
  - `class_name MapView extends Control`: `func _init(world_gen: WorldGen, explored: Exploration, world_sync: WorldSync, you: Callable)` (`you` returns your world position and heading as `[Vector3, float]`); `func place_of(p: Vector3) -> Vector2` (world to map pixels); `func known_towns() -> Array[int]`; `func known_landmarks() -> Array[int]`.
  - `class_name Compass extends Control`: `func _init(world_gen: WorldGen, explored: Exploration)`; `var bearing := 0.0` (degrees, set each frame by the HUD from the camera); `var region := ""`; `static func label_at(bearing: float) -> String` ("N", "NE", … for the eight points, else "").
  - `World.exploration: Exploration`, `World.map: MapView` (hidden until M).
  - Action `map` on M.

Rules:
- The World reveals around your world position every 0.5 s, and at once when the world starts. Exploration is per machine and isn't saved yet (saves are stage 7).
- **Map** (full screen over the world, on the HUD's layer, `mouse_filter` ignore): a dark disc (`Color("1b1828")`) for the unseen world, the seen cells lighter (`Color("40506a")`), drawn as the exploration image stretched over the disc with a shader or `TEXTURE_FILTER_LINEAR`; islands of seen chunks as filled circles `Color("8fae6b")` at their size (cached per chunk once seen); rivers as blue lines (`Color("7fb2e6")`, 2 px) where their points are seen; towns seen as gold dots with names; landmarks seen as white diamonds with names; wrecks seen as small grey crosses; every ship as a dot (yours an arrow in `UiTheme.ACCENT` pointing along its heading); faint region rings with their names. The whole disc fits the smaller screen side with 40 px margins. M or Esc closes it. Keys keep steering while it's open.
- **Compass** (top centre, 520 × 44, on the HUD): the bearing you look toward in the middle; ticks every 15°, the eight points labelled, 90° either side visible; each known town within that view as a gold mark with its name; the region name under it in `UiTheme.caption` style. It hides while the map is open.
- The HUD's compass `bearing` is the camera's: `Hud.bearing(-camera.global_basis.z)`.

- [ ] **Step 1: Write the failing tests** (`tests/test_map.gd`):
  - `test_exploring_reveals_cells_around_you`: a fresh `Exploration` has seen nothing; `reveal(START)` returns true and marks `START` and a point 1,100 m away as seen, not one 1,400 m away; revealing again returns false.
  - `test_the_edges_of_the_world_are_safe`: `reveal` and `seen` at `(9000, 0, 9000)`, `(-8192, 0, -8192)` and `(8191.9, 0, 0)` don't error, and outside the grid nothing is seen.
  - `test_the_map_shows_only_what_you_have_seen`: a map over seed 7 with only `START` revealed: `known_towns()` is `[0]`; after revealing `gen.towns[2].dock`, it's `[0, 2]`. Same for landmarks.
  - `test_the_map_places_the_world`: at 1,000 × 1,000 px, `place_of(Vector3.ZERO)` is the middle, and `place_of(Vector3(8000, 0, 0))` is 40 px from the right edge (±1).
  - `test_m_opens_and_closes_the_map`: in a solo world, pressing M shows the map and hides the compass, M again hides it; while it's open the player can still steer (`player.enabled` stays true).
  - `test_the_compass_reads_the_way_you_look`: in a solo world facing the bow (north), the compass's `bearing` is 0 ± 1; `label_at(90)` is "E", `label_at(225)` is "SW", `label_at(10)` is "". The region is `The Calm Reaches`.
  - `test_you_explore_as_you_fly`: in a solo world, move the ship 3 km west and wait 1 s: `exploration.seen(ship position)` is true.
  - `tests/test_project.gd`: `map` is M.
- [ ] **Step 2: Run `./run_tests.sh map`.** Expected: fail.
- [ ] **Step 3: Implement** `Exploration`, `MapView`, `Compass`, and wire them into the World and HUD.
- [ ] **Step 4: Run the whole suite, then look by hand:** open the map, fly a while, open it again.
- [ ] **Step 5: Commit** "Add a map and compass that fill in as you explore".

### Task 9: Determinism, performance, README and spec

Build-log item s05-09: "Tests: the same seed always builds the same world" (and the stage's promise).

**Files:**
- Create: `tests/test_determinism.gd`
- Modify: `README.md`, `docs/superpowers/specs/2026-09-29-skywright-design.md`, the world's pause menu (`src/world/world.gd`: shows `World seed %d`)

- [ ] **Step 1: Write the tests** (`tests/test_determinism.gd`):
  - `test_the_same_seed_always_builds_the_same_world`: for seeds 1, 2 and 2026: a digest (`hash` of `var_to_str`) of `towns`, `landmarks`, `wrecks`, `rivers`, `storms`, the islands of every chunk in the disc, and the level-0 arrays, trees, waterfall and clouds of 40 chunks spread over the disc, computed twice from fresh `WorldGen`s, is equal; and it differs between the seeds.
  - `test_the_same_seed_builds_the_same_chunks_on_worker_threads`: `WorldChunk.generate` for 16 chunks on `WorkerThreadPool` equals the same run on the main thread.
  - `test_a_wreck_and_a_town_are_the_same_every_time`: `Sites.wreck_grid` and the house boxes of `Town.create` for seed 5 twice are equal.
  - `test_the_wind_is_the_same_on_every_machine`: `Wind.new(WorldGen.new(s))` twice agree at 500 points and times.
  - `test_a_chunk_is_quick_to_make`: the slowest of 60 chunks across the regions takes under 40 ms to `generate` on one thread, and the slowest `build` under 6 ms (both generous for this machine; the point is to catch a tenfold regression).
  - `test_the_pause_menu_shows_the_seed`: pausing shows `World seed 20260930`.
- [ ] **Step 2: Run the whole suite three times.** Expected: it passes every time.
- [ ] **Step 3: Measure the frame rate by hand** on this laptop's Radeon 680M (`godot --path . --gpu-index 0 -- --solo --seed=7` with `--print-fps`, or the FPS in the editor's monitor), flying at full throttle for two minutes through the Shattered Belt and a storm. Record the lowest and typical fps in this plan's "Changes during execution" section. If it drops below 60, halve `LOAD_RADIUS`'s trees range and the clouds' visibility range, and try again; record what was changed.
- [ ] **Step 4: Update the README:**
  - The status: stage 5 of 10, and what you can do now (explore a generated world, towns, wind and sails, on foot and gliding, anchoring, the map and compass).
  - Controls: M map, G anchor (at the helm), Space in the air to glide, E to climb aboard.
  - "The world": regions, towns and docks, sky rivers and storms, the Roil, seeds (`--seed=N`, the seed in the pause menu).
  - "On foot": stepping off, gliding, climbing aboard, anchoring.
  - Launch options gain `--seed=N`. The layout gains the new world files.
- [ ] **Step 5: Update the spec:** the status line; §3.1 (towns, the start); §3.4 (on foot, anchoring); §3.3 (the shipyard at every town's dock); §4.5 (leaving and boarding as built, the 30 m rule gone); §4.6 (protocol 4); §4.7 (as built: chunks, towns, wrecks from starter ships, rivers, storms, the wind's clock); §4.8 (fog sheets, depth fog 900–2,600 m); §9 decisions.
- [ ] **Step 6: Commit** "Test that a seed always builds the same world; update README and spec for stage 5".

---

## Playtest checklist

1. **Exploring:** fly from the starting town toward the Eye. Do islands stream in without popping up close? Is the Shattered Belt denser and more broken than the Calm Reaches? Is there always something on the horizon worth flying to?
2. **Islands:** do tops read as grassy and undersides as rock? Do waterfalls look like water? Do the three levels of detail switch without you noticing?
3. **Towns:** can you spot a town from far off by its beacon? Step off onto a pier, walk into town, and use the shipyard at a town other than the first.
4. **Wind:** find a sky river. Does riding it feel fast, and fighting it slow? Fit sails to a ship and sail downwind with the engines off. Does a storm cell shake the ship?
5. **On foot:** walk off the deck onto an island, explore, then glide back to the ship. Is gliding easy to aim? Does climbing aboard with E work every time?
6. **Anchoring:** anchor next to an island in a strong wind, go ashore, come back. Is she where you left her?
7. **Sky:** do the fog sheets over the Roil look good at noon and at dusk? Are storm columns and lightning dramatic without being annoying?
8. **Map and compass:** does the map fill in as you fly? Can you find your way back to a town with the compass alone?
9. **Co-op:** a friend joins and goes ashore on another island. Do you see them walking and gliding? Do both of you see the same islands?
10. **Frame rate:** does it hold 60 fps on the Radeon 680M flying fast through the Shattered Belt?

---

## Changes during execution and after the final review

Every task had its own review, and a fresh reviewer read the whole branch at the end: "with fixes", no critical findings, four important ones. Each fix below has a test.

| Problem | Fix |
|---|---|
| Storm cells drift with `Wind.prevailing_speed`, which Task 4 was to write. | Task 1 added `prevailing_speed` to the old `wind.gd`; Task 4 kept it. |
| Outline noise sampled at `(cos a, sin a) * 3` gave a near-perfect circle, and hills at full frequency broke the 0.5 m surface tolerance. | The outline samples a circle two noise units across; hills use half the frequency. |
| Jolt refuses an empty concave shape. | A chunk with no islands has no collision body. |
| The host/guest collision test compared the chunk under the ship, which has no islands, so it compared nothing. | It compares the chunk of the island nearest `START`, and checks the faces aren't empty. |
| River wind jumped at bends (nearest segment's direction) and again where two rivers overlap going opposite ways (29 m/s in 1 m, in 44 of 100 worlds). | Every segment in reach adds its push weighted by closeness, and the sum is capped at the strongest: `sum.limit_length(strongest)`. The worst step is now 1.5 m/s. |
| The storm continuity test sampled a storm where it had been 50 s earlier. | It walks across the storm's edge where it is, and checks it really crossed it. |
| Piers 3 m out left a 0.5 m gap, so every ship at a slipway ground along its pier, and a network test was loosened to hide it. | Piers run 4–8 m out (1.5 m from the starter ship), the dock is frictionless, and launches keep 1 m from dock obstacles and 2 m from ships. The test is back to its old bound. |
| The obstacle coverage test was loosened to 2 m because the island's rock overhangs its radius. | The island's obstacle box is widened by the rock's reach (×1.12), and the test is back to 1 cm. |
| "Drop anchor" and "Raise anchor" could never show: "Leave the helm" comes first at the helm. | Dropped. The helm caption says "G anchor" and the readout says "Anchored". |
| Falling ashore could pass 50 m/s horizontally plus vertically, and the server refused the reports. | The whole speed ashore in the air is capped at 50 m/s, and the server allows 0.01 m/s of rounding. |
| Review: holding Space on an ordinary jump opened the glider on the way up. | The glide opens after 0.3 s of falling (or a second press), and so does its prompt. |
| Review: after a test flight, launching could go from the starting town if the ship you came back to had left the dock. | The shipyard remembers the town it was opened at, for launches, test flights, reopening and its stats. |
| Review: replanning took 11–22 ms with 8–20 ships and players. | Near focus points merge, and one pass builds what to load and what to keep, without sorting. 20 spread points take 1.9 ms. Far chunks are freed a few per frame. |
| Review: B with the map open opened the shipyard over it. | Opening the shipyard closes the map. |

**Frame rate.** On the Radeon 680M (`--gpu-index 0`, seed 7, 1920 × 1011, vsync off), a scripted 130 s flight from the starting town through the Shattered Belt and a storm averaged 243 fps. The slowest second was 126 fps while the first chunks loaded, and 189 fps after that. The worst 1% of frames took 5.4 ms, and the worst frame after loading 22 ms. Nothing needed tuning. A hand-flown check is playtest item 10.

**Moved or renamed:** `Hud.readout(ship, wind)`; `WorldSync.docks` replaces `berths`, `test_berths` and `obstacles`; `PlayerController.climbing(ship)` carries E beside a hull; `WorldSync.crew_speed_ok(v)`; `Exploration.revision` tells the map when to redraw; the pause menu shows `World seed %d`.

**Deferred:**
- The server trusts the town a launch names, and where a guest ashore says they are (within the checks). Check both when launching costs money (stage 7), or if griefing shows up.
- A listen host builds island meshes around every guest's ship. Measure its memory in an 8-player playtest.
- Opening the map after a long flight works out the islands of every newly seen chunk at once (up to about 100 ms for the whole disc), and the map draws every seen island each frame. Spread the first over frames and draw the second into a cached layer if it shows.
- One chunk with a wreck can take more than the 3 ms budget to build; ten towns are built at load without being timed.
- Levels of detail switch by each chunk's centre, so a low island in a tall Shattered Belt chunk can lose detail early. Watch for it in playtests.
- Smaller items: stepping off your own test flight leaves B unable to end it; boarding resets your view to the bow; ships pass through people standing on islands; trees can stand inside houses and roofs don't collide; a wreck may float or dig in by a metre; `Dock.ROCK_REACH` repeats a number from `IslandMesh`; duplicated `_add_shape` helpers; the compass's town names can overlap its cardinal letters.
