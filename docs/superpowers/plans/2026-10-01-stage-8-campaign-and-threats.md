# Stage 8: Campaign and Threats Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The journey from the Calm Reaches to the Eye becomes a campaign. Ships burn fuel, so range matters. The Stormwall blows outward harder than the starter ship can fly, so only a capable ship crosses it: one with the thrust (and the fuel) to push through, or the lift to fly over it. Storms strike ships with lightning that sets envelopes burning, rock their decks and close in the fog. Leviathans roam the Gale Expanse: curious, harmless until shot, then ramming whoever shot them. The Warden, a far bigger one, circles the heart of the Eye. Logs found at landmarks and on town quays tell the story, and two of them unlock alloy and the Wallbreaker's blueprint. Reaching the heart after the Warden falls plays the ending for everyone in the world, and the world flies on. Danger and reward grow region by region from one table.

**Architecture:**
- **The campaign is data.** `Campaign` (static, no nodes) holds the region table (pirate raids, leviathans, lightning, contract rewards and prices by region) and the heart's place. `Story` (static) holds the twelve logs, where each is found, and what two of them unlock. `Wallbreaker` is the blueprint one of them gives.
- **The Stormwall is wind, not a door.** `Wind` blows 22 m/s outward through the Stormwall below 1,700 m. A ship crosses it with enough thrust and fuel, or by flying above it. Nothing checks a ship's papers. No town stands in it: the tenth town moves into the Eye.
- **Fuel is a ship resource,** like spares. Tanks hold it; the server's ships burn it every physics tick with their throttle and their trim above 1.0; it's sent once a second, saved, bought at docks, and priced into launches.
- **Storms act through the server.** Lightning strikes the highest block of a ship in rough air (a storm cell, or the Stormwall), turbulence rocks ships with a torque, and the fog closes in around the camera. All three come from the world clock and the server's `rng`.
- **Leviathans are creatures, not block ships.** A `Leviathan` is a kinematic body on a collision layer of its own, so shots hit it and ships pass through it. `Leviathans` (`World/Leviathans`, a third RPC node beside `Sync` and `Ledger`) spawns them, thinks for them on the server, and sends them at 10 Hz. A ram is a `Damage.blast` through `WorldSync.ram`. The Warden is a leviathan of its own kind, bound to the heart.
- **Story progress lives in the account.** The logs a player has found are kept by name in their account. The Ledger checks the reader's reach, records the log, grants its unlock, and plays the ending when someone reaches the heart after the Warden falls.

**Tech Stack:** Godot 4.7.2 (standard build, `~/.local/bin/godot`), statically typed GDScript, Jolt, ENet through SceneMultiplayer, `AnimatableBody3D` with a `CapsuleShape3D` (leviathans), `Environment` depth fog, the existing `SnapshotBuffer`, `Weather.strike` bolts, `RandomNumberGenerator`, `JSON` saves, and the existing headless test runner.

**Spec:** `docs/superpowers/specs/2026-09-29-skywright-design.md` (stage 8 in §5; the campaign in §3.7; threats in §3.5; regions in §3.1 and §4.7; fuel in §4.4; saves in §4.10; the §9 decisions table).

**Where:** branch `stage-8-campaign-threats`, in the worktree `../game-stage-8`, branched from `stage-7-towns-progression` (at `c8149a8` or later: the stage 7 final-review fixes).

## Global Constraints

- Godot 4.7.2 standard build, and GDScript with static types everywhere. No addons or other dependencies. No external art or audio: everything is generated in code (spec §3.9).
- The server is authoritative for fuel, lightning, leviathans, the Warden, logs, unlocks and the ending. A client only asks. Everything a peer receives from another machine is checked, and so is everything read from a save file.
- Protocol version 7. Channel 0 is reliable for events, channel 1 unreliable-ordered for ship and leviathan snapshots, channel 2 unreliable-ordered for crew and helm keys.
- Every number that decides how ships fly stays in `src/ship/tuning.gd` (tank size, burn rates, turbulence). The Stormwall's numbers live in `Wind`, the region table in `Campaign.REGIONS`, prices and rewards in `Economy`, leviathan numbers in `Leviathan`, lightning numbers in `WorldSync`, and the story's words in `Story`.
- Randomness on the server comes from `WorldSync.rng`, so tests can seed it.
- New messages are the exact strings in this plan. Money is shown as `%d crowns`.
- Tests use ports 20000–29999. `NetCase` worlds use `NetCase.SEED` with pirates, leviathans and lightning off (`Session.pirates`, `Session.leviathans`, `Session.lightning`), so the stage 1–7 tests never meet a raid, a leviathan or a strike. Tests that save point `SaveGame.dir` at `user://test_saves_<random>` and delete it in `after_each`.
- GDScript lambdas capture locals by value: a flight test's `simulate` callback keeps what it measures in a Dictionary or Array.
- Contract map markers (stage 10) and boarding (stage 9) stay out.
- Deliberate shortcuts carry a `ponytail:` comment naming the ceiling and the upgrade path.
- Commit messages have no `Co-Authored-By` line or other trailers (user rule).

## Review Focus

1. **The Stormwall is a physics gate** (the starter ship with an engineer at her ceiling, the Wallbreaker, a lift-stone ship over the top, towns placed near the wall, a test flight used as a ferry): only a capable ship gets in, and nothing else can carry you. Tests: `test_the_starter_ship_cant_cross`, `test_the_wallbreaker_crosses`, `test_a_ship_can_go_over_the_top`, `test_no_town_stands_in_the_stormwall`, `test_a_test_flight_cant_ferry_you_across` (Task 3).
2. **Fuel is spent and kept honestly** (throttle, trim, an engineer, anchoring, empty tanks, a tank shot away, a launch's price and trade-in, a stage 7 save): the numbers are right on every machine. Tests: `test_engines_burn_fuel_with_the_throttle`, `test_a_ship_without_fuel_drifts`, `test_a_shot_tank_spills_its_fuel`, `test_a_new_ship_comes_fuelled_and_priced`, `test_fuel_reaches_the_guest` (Task 2).
3. **The server decides** (a modified guest buying fuel away from a dock or spamming asks, reading a log from a kilometre off or one that doesn't exist, reaching the heart on a test flight; a modified host sending junk fuel, strikes or leviathans): refused, and nothing changes. Tests: `test_the_server_ignores_junk_fuel_asks`, `test_a_junk_fuel_message_is_refused` (Task 2), `test_a_junk_strike_is_ignored` (Task 4), `test_junk_beast_messages_are_refused` (Task 6), `test_the_server_ignores_junk_log_asks` (Task 8), `test_a_test_flight_doesnt_end_the_story` (Task 9).
4. **Leviathans behave, and every machine agrees** (curious, angered, ramming, calming, slain, a gunner's target, the Warden on its leash, a late joiner): Tests: `test_a_leviathan_is_curious_and_harmless`, `test_an_angry_leviathan_rams`, `test_a_slain_leviathan_sinks_and_pays` (Task 5), `test_guests_see_leviathans`, `test_gunners_fire_at_angry_leviathans` (Task 6), `test_the_warden_keeps_to_the_heart` (Task 7), `test_host_and_guest_fight_a_leviathan` (Task 10).
5. **Saves stay readable** (a stage 7 save, a ship saved where a town used to be, and fuel, logs and the Warden kept): a version 1 save loads with sensible defaults and its ships in port, and nothing new is lost. Tests: `test_a_version_1_save_still_loads` (Task 2), `test_a_stage_7_save_wakes_in_port` (Task 3), `test_the_warden_stays_beaten_in_a_save` (Task 7), `test_logs_are_kept_by_name_in_a_save` (Task 8).
6. **The ending plays once, for everyone present** (the Warden alive, the Warden beaten, a guest aboard, a late joiner): Tests: `test_the_heart_waits_for_the_warden`, `test_reaching_the_heart_ends_the_story`, `test_everyone_present_sees_the_ending` (Task 9).

---

## What prototyping settled before this plan

Prototyped in a detached worktree of stage 7, with flight tests run headless at 60 ticks a second.

| Question | Answer |
|---|---|
| Where do the starter ship's fuel tanks go? | Two tanks (80 kg) for two keel frames (60 kg) add 40 kg: she floats at 872.1 m, outside the 881 ± 5 m that `test_cannons` and `test_ship_grid` allow. Tanks at `(0, −1, 4)` and `(0, −1, 6)` with the helm deck's two side frames at `(±2, 1, 5)` swapped for deck planks (−40 kg) leave her at 9,566 kg, 301 blocks, floating at 882.5 m, trim 0.000° and no list. Every stage 2–7 balance test stands. |
| What can the starter ship do? | 19.6 m/s at 880 m and 20.5 at 1,100 m; her ceiling at trim 1.1 is 1,121 m. An engineer's 25% gives about 22.9 m/s. |
| How strong must the Stormwall be? | An outward wind, full from 1,750 to 2,050 m from the centre and fading over 150 m to nothing at 1,600 and 2,200, with the existing prevailing wind and gusts on top. Flown inward from 2,450 m out at full throttle for 300 s, from ten angles: at 22 m/s the starter ship **with an engineer**, at her ceiling (1,100 m), never got in (closest 1,751–1,953 m from the centre); at 21 m/s one of ten got in. A twin-engine design (the Wallbreaker below) at 1,000 m got in from all ten angles in 82–194 s at 22 m/s, but only three of five at 23 and one of five at 25. So 22 m/s. |
| Can a ship go over the top? | With the wall full below 1,700 m and gone by 1,900 m, the starter ship with eight lift stones flying at 1,900 m got in from all ten angles in 77–87 s. Eight stones float her at 1,783 m at trim 1 (ceiling 2,021 m) but keep her above about 1,224 m even at trim 0.8; ten float her at 2,070 m and keep her above 1,512 m, too high for most docks. The shipyard's numbers show that trade-off. |
| The Wallbreaker | The starter ship with an engine for the iron at `(0, −1, 1)`, propellers at `(±2, 2, 7)`, a ridge of 11 balloon cells at `(0, 11, −4…6)` and two more tanks at `(0, −1, −2)` and `(0, −1, −4)`: 9,914 kg, 314 blocks, floats at 986 m (ceiling 1,225 m), 10 kN of thrust, 27.6 m/s at 880 m, stern down 0.37°, no warnings. |
| Turbulence | A torque of `inertia × 0.1 rad/s² × shake(t)` rolled the starter ship up to 2.7° and pitched her up to 6.7° over a minute (0.05: 1.1° and 3.4°; 0.2: 5.3° and 13.4°). With it on, the crossings above held: the starter ship and engineer closest 1,755 m; the Wallbreaker in 82–188 s; eight lift stones in 77–87 s. |
| Where do towns go? | With the tenth town drawn in the Eye, and every town's dock area and island kept out of the band 1,600–2,200 m from the centre (and an Eye town's dock area at least 800 m from the centre), seeds 1–40 and the test seed all have ten towns, and seeds 1–20 keep every landmark and wreck count per region. For the test seed, towns 0–7, the landmarks and the wrecks are unchanged; town 8 (the second Gale Expanse town) moves, because its old quay reached 2,084 m from the centre, in the wall's fade; town 9 is in the Eye at 1,203 m. From the start to the nearest Gale town is 6.2 km, and from there to the Eye's town 1.9 km. |
| A leviathan's body | An `AnimatableBody3D` capsule (radius 4 m, 36 m long) on collision layer 5 with mask 0: a shot's ray (`intersect_ray`, every layer) hits it, and a ship overlapping it as it moved felt nothing (0.24 m/s, her float drift). |
| Fuel (arithmetic) | At 0.8 units a second for an engine at full throttle, the starter ship's 400 units last 500 s: 9.8 km at full throttle, or about 13.9 km at half throttle (0.4 units a second, about 13.9 m/s). The Wallbreaker's 800 units at 1.6 a second last 13.8 km, and a crossing burns 130–310. Trim 1.1 burns 137 × 0.1 × 0.05 = 0.685 units a second. At 4 units a crown the starter ship's tanks cost 100 crowns, so she costs 1,480: a guest's first ship still fits in 1,500. |
| Leviathans' numbers (arithmetic) | Round shot does 160, so a 2,000-point leviathan takes 13 hits and the 6,000-point Warden 38. A ram of 120 within 3 m destroys the deck planks within 1 m of where it lands (about 6 blocks) and dents the rest. A leviathan charges at 24 m/s, faster than the starter ship and slower than the Wallbreaker. |

## Where this stage departs from the spec

The spec is updated to match in Task 10.

| Spec | This stage | Why |
|---|---|---|
| §3.1: "one [town] at the Stormwall" | The tenth town is in the Eye. No town's quay, slipways or island lie in the Stormwall band (1,600–2,200 m from the centre), and the Eye's town keeps 800 m from the heart. No plain island stands within 450 m of the heart. | The Stormwall is a band of headwind. A harbour in it would be a hole in the gate, and ships at its slipways would be blown away. The Eye's town is where you refuel for the Warden and the way home. |
| §3.1: crossing the Stormwall "needs a strong, well-built ship or a gap in a sky river" | It needs thrust (about 25 m/s or more at the wall, with the fuel to keep it up for two or three minutes) or height (cruising above 1,900 m). Sky rivers aren't gaps. | A physics gate the shipyard's numbers explain: top speed, fuel range and ceiling. |
| §4.4: fuel tank "80 kg (+ fuel)" | Fuel weighs nothing: a tank is 80 kg full or empty. | Burning would change a ship's trim in flight, and the starter ship's balance tests stand. ponytail: in `Ship.fuel`. |
| §3.4: "An engine station waits for fuel, stage 8" | Still no engine station. The throttle at the helm burns the fuel, and an engineer's boost burns 25% more. | An engine station would only move the throttle. |
| §3.5: "Sky leviathans: roaming giants in the Gale Expanse, plus one boss" | Leviathans are creatures, not block ships: one body with hit points (2,000), drifting, curious about ships, and angered when shot, when they ram whoever shot them. They don't count toward bounty contracts; slaying one pays 300 crowns to each player within 1.5 km. The Warden (6,000 hit points) circles the heart and attacks any ship within 700 m of it, ramming and calling lightning. | A block-built creature would need organic blocks, a pilot and break-apart rules for a body. Bounties stay a pirate matter. |
| §3.5: "Weather: storm cells bring lightning and turbulence" | Lightning strikes the highest block of a ship in rough air (a storm cell, or the Stormwall below its top): a small blast that may set the blocks around it alight. Turbulence rocks a ship with a torque. The fog closes in around the camera inside rough air. | The smallest weather a crew feels: a strike to put out, a deck that moves, and not seeing far. |
| §3.5: pirates raid "50% and two further in" | From the region table: none in the Stormwall and the Eye. | A pirate ship can't hold her place in the wall, and the Warden keeps the Eye. |
| §3.6: "Blueprints and parts come from shipyards, wrecks and story progress" | Two story unlocks: the log at the first Shattered Belt landmark unlocks alloy plates, and the log at the first Gale Expanse landmark puts the Wallbreaker in your shipyard's blueprints. | Small, and each points at the next region. |
| §3.6: launch prices | A ship's price includes full tanks (4 units a crown), and her worth counts her fuel. The starter ship costs 1,480 crowns. | Fuel is priced like spares, so relaunching isn't a free refuel. |
| §3.7: the campaign | Twelve logs: one at each of the eight landmarks, three on town quays (the start, the first Gale town, the Eye's town), and the heart's own, which is the ending. E reads a log within 30 m of its spot, and L rereads the ones you've found. Reaching within 250 m of the heart after the Warden falls plays the ending for everyone in the world; the world flies on. | The smallest campaign that tells a story and ends. |
| §4.10: saves are version 1 | Saves are version 2: ships carry `fuel`, accounts `logs`, and the world `warden`. Version 1 saves still load: ships full of fuel, no logs, the Warden alive, and every ship in port at the slipways of the town nearest where she was saved. | A stage 7 save must never be stranded, and towns moved: a ship left at the old Stormwall town would wake in the wall. |
| (not in the spec) | Prices and contract rewards grow inward, by region. | Trade and contracts pay for the danger further in. |
| (not in the spec) | Stepping off a test flight ends it, and you're back where you came from. | Otherwise a free test flight in locked parts could carry you over the Stormwall to launch a ship in the Eye. |
| (not in the spec) | A test flight finds no logs and can't end the story. | Stage 7's rule: a test flight earns nothing. |

## Protocol (version 7)

| RPC | Change |
|---|---|
| `Session.PROTOCOL_VERSION` | 7 |
| Ship entries (in `_world` and `_ship_added`) | 13 fields: `[id, blocks, paint, transform, pilot, captain, test, blueprint, pirate, spares, cargo, hands, fuel]`. `fuel` is a float from 0 to her tanks' capacity (Task 2). |
| `WorldSync._fuel(id, fuel)` | New, server → clients: ship `id`'s fuel, once a second while it changes. |
| `WorldSync._strike(id, cell)` | New, server → clients: lightning struck ship `id` at `cell`. The damage follows in `_blocks_changed`, and any fire in `_fires`. |
| `Leviathans._beast_added(time, entry)` | New, server → clients: `[id, kind, position, velocity, heading, hp, mood]`. |
| `Leviathans._beast_removed(id)` | New, server → clients. |
| `Leviathans._beasts(time, states)` | New, server → clients, channel 1 unreliable-ordered, 10 Hz: `[[id, position, velocity, heading, mood], …]`. |
| `Leviathans._beast_hurt(id, hp)` | New, server → clients. |
| `Ledger._account(account)` | The account gains `logs`, the log indices found. |
| `Ledger._buy_fuel()` | New, client → server: fill the ship I'm aboard at a dock. |
| `Ledger._read_log(index)` | New, client → server: record the log whose spot I'm at. |
| `Ledger._ending()` | New, server → each player in the world: the ending plays. |

`mood` is an index into `Leviathan.MOODS`: `["drift", "curious", "angry", "slain"]`. Budget: a leviathan's state is about 50 bytes, so five at 10 Hz is about 2.5 KB/s; fuel is about 20 bytes a burning ship a second; a strike is about 30 bytes plus its blocks. Every ask goes through the Ledger's `_may_ask` (one every 0.1 s a peer).

---

## File structure

| File | Responsibility |
|---|---|
| `src/campaign/campaign.gd` | `Campaign`: the region table, the heart's place, and building the heart |
| `src/campaign/story.gd` | `Story`: the logs' words, where each is found, what they unlock |
| `src/campaign/wallbreaker.gd` | `Wallbreaker`: the twin-engine blueprint a log gives |
| `src/ai/leviathan.gd` | `Leviathan`: the creature, its moods and movement, its body and look |
| `src/ai/leviathans.gd` | `Leviathans`: spawning, roaming, the Warden, shots and rewards, and their RPCs |
| `src/ui/log_book.gd` | `LogBook`: the logs you've found (L), and one being read |
| `src/ui/ending_screen.gd` | `EndingScreen`: the heart's words and the credits |
| `src/ship/tuning.gd` | `FUEL_PER_TANK`, `ENGINE_BURN`, `TRIM_BURN`, `TURBULENCE` |
| `src/ship/ship.gd` | `fuel`, `fuel_capacity`, `burn_rate`, `trim_limit`, burning, no thrust when dry, turbulence |
| `src/ship/starter_ship.gd` | Two fuel tanks |
| `src/ship/ship_stats.gd` | Fuel and range in the readout; the no-tank warning |
| `src/crew/helm.gd` | Trim limited by fuel |
| `src/world/wind.gd` | The Stormwall's wind, `wall_strength`, `roughness`, `shake` |
| `src/world/world_gen.gd` | The tenth town in the Eye, towns clear of the wall, no island by the heart |
| `src/world/world_sky.gd` | Storm fog |
| `src/world/weather.gd` | `bolt_to` |
| `src/world/world.gd` | The Leviathans node, the heart, bolts, fog, test flights ending ashore, logs, the log book, the ending |
| `src/net/world_sync.gd` | Fuel, strikes, rams, shots into leviathans, the region table's raids, `warden_beaten`, protocol 7 |
| `src/net/session.gd` | Protocol 7, `leviathans`, `lightning` |
| `src/economy/economy.gd` | Fuel prices, region-scaled prices and rewards, rewards for leviathans, accounts with logs |
| `src/economy/ledger.gd` | Buying fuel, reading logs and their unlocks, rewards near a point, the ending |
| `src/save/save_game.gd` | Version 2, reading version 1 |
| `src/ai/crew_hand.gd`, `src/ai/pirate_captain.gd` | Gunners fire at angry leviathans; `fire_at_point` |
| `src/ui/hud.gd`, `src/ui/town_panel.gd`, `src/ui/map_view.gd`, `src/builder/shipyard.gd` | Fuel line and prompt; the market's fuel row; leviathans on the map; story blueprints |
| `project.godot` | Action `logs` (L) |
| `tests/net_case.gd` | Leviathans and lightning off |
| `tests/test_campaign.gd`, `test_fuel.gd`, `test_stormwall.gd`, `test_storms.gd`, `test_leviathans.gd`, `test_leviathans_net.gd`, `test_warden.gd`, `test_logs.gd`, `test_ending.gd`, `test_campaign_net.gd` | New tests |
| `README.md`, spec | Stage 8 status, fuel, the campaign, controls |

---

### Task 1: The campaign's rules

Build-log items s08-06: "Difficulty tuning across regions" (the table, and the prices, rewards and raids that follow it) and s08-04: "Story told through logs found in ruins and towns" (the words and where they're found).

**Files:**
- Create: `src/campaign/campaign.gd`, `src/campaign/story.gd`, `src/campaign/wallbreaker.gd`, `tests/test_campaign.gd`
- Modify: `src/economy/economy.gd`, `src/net/world_sync.gd`, `tests/test_pirates.gd`, `tests/test_save_game.gd`

**Interfaces:**
- Consumes: `WorldGen` (towns, landmarks, `Region`, `region_at`), `IslandMesh.height`, `Dock.quay_spot`, `StarterShip`, `ShipGrid`.
- Produces:
  - `class_name Campaign` (static):
    - `const REGIONS := [...]`, by `WorldGen.Region`, each `{"raids": float, "raiders": int, "leviathans": int, "spawn": float, "strikes": float, "rewards": float, "prices": float}`:

      | Region | raids | raiders | leviathans | spawn | strikes | rewards | prices |
      |---|---|---|---|---|---|---|---|
      | The Eye | 0.0 | 0 | 0 | 0.0 | 0.0 | 2.0 | 1.5 |
      | The Stormwall | 0.0 | 0 | 0 | 0.0 | 0.05 | 2.0 | 1.5 |
      | The Gale Expanse | 0.5 | 2 | 2 | 0.4 | 0.035 | 1.6 | 1.25 |
      | The Shattered Belt | 0.5 | 2 | 0 | 0.0 | 0.0 | 1.25 | 1.1 |
      | The Calm Reaches | 0.25 | 1 | 0 | 0.0 | 0.0 | 1.0 | 1.0 |
      | The Rim | 0.0 | 0 | 0 | 0.0 | 0.0 | 1.0 | 1.0 |

      `raids` is the chance a raid sends a pirate at a crewed ship there, and `raiders` the most pirates near her (stage 6's `RAID_CHANCE` and `RAID_LIMIT`). `leviathans` is the most leviathans near a ship, and `spawn` the chance a roam sends one (Task 6). `strikes` is lightning's chance a second, per ship, in fully rough air (Task 4). `rewards` and `prices` multiply contract rewards and goods prices at towns of that region.
    - `const HEART := Vector3(0.0, 1000.0, 0.0)`, `const HEART_REACH := 250.0`.
    - `static func of(p: Vector3) -> Dictionary` (`REGIONS[WorldGen.region_at(p)]`).
  - `class_name Story` (static):
    - `const REACH := 30.0` (m from a log's spot that it's read from), `const HEART_LOG := 11`.
    - `const LOGS := [...]`: twelve `{"title": String, "text": String, "at": "town", "landmark" or "heart", "index": int, "unlocks": String ("" or a part), "blueprint": String ("" or a name)}`, in the order of the table below.
    - `static func spot(gen: WorldGen, log: int) -> Variant`: where it's read, a `Vector3`, or null (the heart's, or a place the world doesn't have). A landmark's log is at its foot: `landmark["at"] + Vector3(0, IslandMesh.height(landmark["island"], 0, 0), 0)`. A town's is `Dock.quay_spot(town["dock"])`.
    - `static func blueprints(logs: Array) -> Array[String]` (the blueprints the found logs give, in log order) and `static func blueprint(blueprint_name: String) -> ShipGrid` (`"Wallbreaker"` gives `Wallbreaker.build()`).
  - `class_name Wallbreaker`: `static func build() -> ShipGrid`: `StarterShip.build()` with an engine at `(0, −1, 1)` in place of the iron, propellers at `(−2, 2, 7)` and `(2, 2, 7)`, balloon cells at `(0, 11, z)` for z −4…6, and fuel tanks at `(0, −1, −2)` and `(0, −1, −4)` in place of keel frames; painted `{"balloon": Color("2f5d8a")}`.
  - `Economy`: `const LEVIATHAN_REWARD := 300`, `const WARDEN_REWARD := 2000`; `new_account()` gains `"logs": []`.
  - `WorldSync`: `RAID_CHANCE` and `RAID_LIMIT` are gone; `_raid` reads `Campaign.REGIONS`.

**The logs** (titles and texts are exact; landmark and town indices are `WorldGen`'s, whose plans put the first Shattered Belt landmark at 2, the first Gale Expanse landmark at 4, the Stormwall's at 6, the Eye's at 7, the first Gale town at 7 and the Eye's town at 9):

| Log | At | Title | Text | Gives |
|---|---|---|---|---|
| 0 | town 0 | A notice on the quay | Captains wanted for the inward routes. The Shattered Belt pays in salvage, the Gale Expanse pays in everything, and nobody has come back over the Stormwall in living memory. Fill your tanks, fill your spares, and don't fly into a storm you can't see out of. The harbourmaster. | |
| 1 | landmark 0 | Carved at the spire's foot | We raised this spire on the first island that held. When the ground went down into the Roil, the stone at the Eye's heart kept the rest of us up. Every island still turns around it, slow as the hand of a clock. Remember the heart. | |
| 2 | landmark 1 | A traveller's journal | The wind goes round the Eye the way the islands do, and it blows harder the further in you go. Fly with it and an engine lasts all day. Fly against it and you'll learn what fuel costs. Plan the way back before the way in. | |
| 3 | landmark 2 | An armourer's ledger | Iron is too heavy for the inward routes. We beat alloy thin and it stops shot nearly as well, at two-thirds of the weight. The method is written out below, for any yard that wants it. Take it: we won't be needing it now. | unlocks `alloy` |
| 4 | landmark 3 | A salvager's last entry | The wrecks in the Belt are what the Gale sends back: ships that went in proud and came out as kindling. We strip them and say a word for their crews. Lift stones are sold further in, they say. So is trouble. | |
| 5 | landmark 4 | The Wallwright's notes | The Stormwall blows outward, harder than any one engine can push. Two engines and four propellers will make headway, slowly, and burn fuel all the while: carry four tanks. Or climb above it, where the wall lets go, if your envelope or your stones can take you there. My drawings are pinned beneath. | blueprint `Wallbreaker` |
| 6 | landmark 5 | A leviathan watcher's log | They're curious, not cruel. One swam beside us for an hour today, close enough to count its scars. Shoot one and it won't forget you until you're gone, and it hits like a falling island. The great one in the Eye is another matter. | |
| 7 | landmark 6 | Scratched into the stone | We made it this far on stones and balloons. Above the storm the wind lets go, and the air is thin and quiet. Below, the lightning never stops. If you can read this, you're in the wall. Keep going in. | |
| 8 | landmark 7 | The wardens' charge | We bound the Warden to the heart, to keep the storm away from the Keel. While it circles, the Keel holds. It knows nothing of friends now. Whoever comes after us: it will not let you pass without a fight, and you must not let it win. | |
| 9 | town 7 | A dockmaster's warning | Ships out of here fly through storms that strike the highest thing they find, which is usually your envelope. Keep a hand on the repairs, keep your spares full, and give the leviathans room. They only fight when you start it. | |
| 10 | town 9 | The lamplighters' book | We came over the wall with what we could carry, and found the calm. The heart is close: you can see its light from the quay. The Warden circles it day and night, and comes for anything that flies near. Rest here first. | |
| 11 | heart | The Keel | Below the calm, a stone the size of a town turns in the air, humming. The Keel: every island in the sky hangs from it. The wardens bound a guardian to it and were forgotten, and the guardian forgot everything but the stone. Now it's quiet. The Keel still turns, the islands will hold, and the way to the heart is open to anyone with a ship and the nerve to cross the wall. | the ending (Task 9) |

Rules:
- **Prices:** `price = maxi(1, roundi(base × factor × (1 + noise) × prices))`, with `prices` from the town's region. `sell_price` follows it. Town 0's prices are unchanged (Calm, 1.0).
- **Contract rewards:** after `draw_contract` works out a reward as now, it becomes `roundi(reward × rewards)` for the town's region. Town 0's contracts are unchanged.
- **Accounts** (`read_account`): `logs` may be missing (a stage 7 save), which reads as `[]`. Otherwise it's an Array of distinct whole numbers from 0 to `Story.LOGS.size() − 1` (whole floats from JSON become ints). Anything else gives null.
- **Raids** (`_raid`) take `raids` and `raiders` from `Campaign.REGIONS[region]`, with nothing else changed. Stage 6's limits in the Calm Reaches (1) and the Shattered Belt (2) stand, and the Stormwall and the Eye get none.

- [ ] **Step 1: Write the failing tests** (`tests/test_campaign.gd`, `extends NetCase`, with plain checks unless a world is named; `gen := WorldGen.new(NetCase.SEED)`):
  - `test_the_regions_get_harder_further_in`: from the Calm Reaches through the Shattered Belt and the Gale Expanse to the Stormwall and the Eye, `rewards` and `prices` never fall. `raids` is 0 in the Eye, the Stormwall and the Rim. Only the Gale Expanse has `leviathans` and `spawn`. Only the Gale Expanse and the Stormwall have `strikes`, and the Stormwall's is the higher.
  - `test_prices_rise_further_in`: for every town and traded good, `price` lies between `roundi(base × factor × 0.9 × prices)` and `roundi(base × factor × 1.1 × prices)` for that town's region, and `sell_price < price`. Town 0's prices equal what the stage 7 formula gives.
  - `test_contracts_pay_more_further_in`: with rng seed 1, 200 draws at town 7 (the first Gale town): every bounty pays 400 a pirate (`roundi(250 × 1.6)`). The same 200 draws at town 0 give the stage 7 rewards.
  - `test_accounts_keep_their_logs`: `new_account()` has `"logs": []`. An account with logs `[0, 5]` reads with them; one with logs `[0.0, 5.0]` reads as ints; one without `logs` reads with `[]`. Logs `[12]`, `[−1]`, `[1, 1]`, `["2"]` and `2.5` each give null.
  - `test_the_story_is_placed_in_the_world`: twelve logs with distinct titles of at most 40 characters and texts of at most 600. Every log but the heart's has a spot: landmark logs at their landmark's foot, town logs at their town's `Dock.quay_spot`. The heart's spot is null. Exactly one log unlocks `alloy` (log 3) and one gives `Wallbreaker` (log 5). `Story.blueprints([5])` is `["Wallbreaker"]` and `Story.blueprints([0, 3])` is `[]`.
  - `test_the_wallbreaker_flies`: `ShipStats.of(Wallbreaker.build(), 880)`: 10,000 N of thrust, top speed over 27 m/s, no warnings, floats between 950 and 1,050 m, list under 0.1°, `bow_down` within 1°; one helm, two engines, four propellers.
  - `test_raids_follow_the_table`: a solo world, pirates on, `sync.rng.seed = 1`, your ship anchored at the Gale spot `(0, 1000, −3000)` after `open_sky(world, 1000)`: 40 `_raid()`s spawn exactly 2 pirates. Each removed, then at the Stormwall spot `(0, 1000, −1900)` and the Eye spot `(0, 1000, −1000)`, 40 `_raid()`s spawn none.
  - `tests/test_pirates.gd`: the raid test expects `Campaign.REGIONS[region]["raiders"]`.
  - `tests/test_save_game.gd`: the accounts in its saves carry `"logs": []`.
- [ ] **Step 2: Run `./run_tests.sh campaign`.** Expected: the tests fail (`Campaign` doesn't exist).
- [ ] **Step 3: Implement** `Campaign`, `Story`, `Wallbreaker`, the economy's region factors and logs, and raids from the table.
- [ ] **Step 4: Run the whole suite.** Expected: everything passes.
- [ ] **Step 5: Commit** "Add the campaign's rules: a region table for danger and reward, the story's logs, and the Wallbreaker".

### Task 2: Fuel

Build-log item s08-01: "Region progression and the Stormwall crossing" (fuel range, which is part of the gate).

**Files:**
- Create: `tests/test_fuel.gd`
- Modify: `src/ship/tuning.gd`, `src/ship/ship.gd`, `src/ship/starter_ship.gd`, `src/ship/ship_stats.gd`, `src/ship/blocks.gd`, `src/crew/helm.gd`, `src/economy/economy.gd`, `src/economy/ledger.gd`, `src/net/world_sync.gd`, `src/net/session.gd`, `src/save/save_game.gd`, `src/world/world.gd`, `src/ui/hud.gd`, `src/ui/town_panel.gd`, `tests/test_cargo.gd`, `tests/test_economy.gd`, `tests/test_unlocks.gd`, `tests/test_sinking.gd`, `tests/test_abandon.gd`, `tests/test_world.gd`, `tests/test_fleet.gd`, `tests/test_session.gd`, `tests/test_designed_ship.gd`, `tests/test_save_game.gd`, `tests/test_campaign.gd`

**Interfaces:**
- Consumes: the Ledger's `_docked_ship`, `pay`, `tell`, `_may_ask` (stage 7); `Wallbreaker` (Task 1).
- Produces:
  - `Tuning`: `const FUEL_PER_TANK := 200.0` (units a tank holds), `const ENGINE_BURN := 0.8` (units a second an engine burns at full throttle), `const TRIM_BURN := 0.05` (units a second each balloon cell burns for each 1.0 of trim over 1).
  - `Ship`: `var fuel := -1.0` (units; below 0 when she's added means fill her tanks); `func fuel_capacity() -> float`; `func burn_rate() -> float`; `func trim_limit() -> float`.
  - `StarterShip`: fuel tanks at `(0, −1, 4)` and `(0, −1, 6)` in place of keel frames, and deck planks at `(±2, 1, 5)` in place of the helm deck's side frames.
  - `ShipStats`: `var fuel := 0.0` (units her tanks hold), `var fuel_range := 0.0` (m at full throttle); `describe()` gains `"Fuel       %d units, %.1f km at full throttle"` after the top speed line; the warning `No fuel tank: her engines won't run.`
  - `Economy`: `const FUEL_PER_CROWN := 4` (units a crown buys); `cost(grid)` adds full tanks; `static func value(grid: ShipGrid, spares: int, fuel: float) -> int`.
  - `Ledger`: `func buy_fuel() -> void`; RPC `_buy_fuel()`.
  - `WorldSync`: RPC `_fuel(id, fuel)`; entries of 13 fields, `fuel` last; `_add(…, spares: int, fuel: float)`.
  - `Session.PROTOCOL_VERSION := 7`.
  - `SaveGame`: `const VERSION := 2`; it reads versions 1 and 2.
  - `Hud.readout` gains `Fuel      %d/%d` after the spares line.
  - `Blocks.INFO["fuel_tank"]["about"]` becomes `Holds 200 units of fuel for the engines.`

Rules:
- **Capacity** is `FUEL_PER_TANK` for each fuel tank she has. `_ready` fills a ship whose `fuel` is below 0. `rebuild` keeps `fuel` within her capacity: a tank shot away spills its share. Counts of engines, tanks and balloons are cached at each rebuild, so nothing per tick walks the grid.
- **Burning** (`Ship._physics_process`, a simulated ship only): `fuel = maxf(0, fuel − burn_rate() × delta)`. `burn_rate()` is `|throttle| × ENGINE_BURN × (engines + ENGINE_BOOST × tended_engines()) + balloons × maxf(0, trim − 1) × TRIM_BURN`, and 0 for a frozen ship (anchored, or a dedicated server's ship while nobody is aboard).
- **A ship with no fuel** has no thrust (`_integrate_forces` skips it), and her trim is held at 1.0 or below: `trim_limit()` is `TRIM_MAX` with fuel and 1.0 without, the helm and autopilot clamp to it, and `_physics_process` lowers a trim above it. She drifts at the height trim 1 floats her.
- **On the network:** `add_ship` fills a ship's tanks unless she has no helm (a wreck's are empty). Each entry carries `fuel`, checked as a finite float from 0 to the entry grid's capacity, or the ship is left out. In `_wear`, the server sends `_fuel(id, fuel)` for each ship whose fuel isn't what it last told. Clients take it if the ship is known and it's a finite float from 0 to her capacity, and ignore anything else without a warning.
- **Buying fuel** (`_buy_fuel_for(peer)`): the asker must be aboard a docked ship (`_docked_ship`). `units = minf(capacity − fuel, money × FUEL_PER_CROWN)`, and it costs `ceili(units / FUEL_PER_CROWN)`. Messages: `Bought %d fuel for %d crowns.` (units rounded), `Her tanks are full.` (less than one unit of room), `You can't afford fuel.` and `Buy fuel at a town's dock, aboard a ship.` Everyone hears the ship's `_fuel`.
- **Prices:** `cost` adds `ceili(capacity / FUEL_PER_CROWN)` (a new ship comes full). `value` adds `fuel / FUEL_PER_CROWN`. Every caller of `value` passes the ship's fuel: `Ledger.trade_in` and `World._trade_in`. The starter ship costs 1,480 (parts 1,180, spares 200, fuel 100), and her insurance is 740.
- **The town panel's market** gains, after the spares row, `Fuel      %d/%d   %d units a crown` (rounded fuel, capacity, `FUEL_PER_CROWN`) with a `Fill` button (`buy_fuel`). That label is refreshed in place every `CHECK_EVERY`, and the summary leaves fuel out, so a ship burning fuel at the dock doesn't rebuild the rows under your mouse.
- **Saves:** `record` adds `"fuel"`. `read_ship` takes `fuel` as a finite number from 0 to the ship's capacity (`has fuel that doesn't fit her tanks.`), and a record without it (version 1) gets full tanks. `restore` sets it. Files are written as version 2; a version other than 1 or 2 says `This save is version %s; this game reads versions 1 and 2.`
- ponytail: fuel weighs nothing, so burning never changes her trim; give it mass in `mass_properties` if heavy tanks should matter.

- [ ] **Step 1: Write the failing tests** (`tests/test_fuel.gd`, `extends NetCase`; plain ships in calm air in the tree, or a solo world at the dock, unless marked network):
  - `test_the_starter_ship_carries_two_tanks_and_still_floats_level`: tanks at `(0, −1, 4)` and `(0, −1, 6)`, deck planks at `(±2, 1, 5)`. `ShipStats.of(StarterShip.build(), 880)`: mass 9,566 kg (±1), floats at 882.5 ± 1 m, `bow_down` under 0.1°, list under 0.01°, 301 blocks, 400 units of fuel, and `describe()` has `Fuel       400 units, 9.8 km at full throttle`. `Economy.cost` of her is 1,480.
  - `test_engines_burn_fuel_with_the_throttle`: a plain starter ship. Full throttle for 10 s burns 8 units (±0.1); half throttle for 10 s, 4 more; throttle 0 with trim held at 1.1 for 10 s, 6.85 (±0.1); an engineer at her engine and full throttle for 10 s, 10; anchored at full throttle and trim 1.1, none.
  - `test_a_ship_without_fuel_drifts`: fuel 0. Full throttle for 20 s: her horizontal speed stays under 1 m/s. Trim set to 1.1 is 1.0 a tick later. At the helm with climb held for 5 s, trim stays at most 1.0; with the autopilot holding 1,100 m for 20 s, likewise.
  - `test_a_shot_tank_spills_its_fuel`: with 400 units, destroying `(0, −1, 4)` leaves capacity 200 and fuel 200 after the rebuild.
  - `test_a_design_without_a_tank_is_warned`: the starter ship without her tanks warns `No fuel tank: her engines won't run.` and reads `Fuel       0 units, 0.0 km at full throttle`.
  - `test_fuel_is_bought_at_a_dock`: fuel 100 at slipway 0: `ledger.buy_fuel()` gives 400, takes 75 crowns, and says `Bought 300 fuel for 75 crowns.`. Again: `Her tanks are full.`. With 10 crowns and no fuel: 40 units for 10 crowns, then `You can't afford fuel.`. At `open_sky`: `Buy fuel at a town's dock, aboard a ship.`, and nothing changes. The town panel's market shows `Fuel      40/400   4 units a crown` with `Fill`.
  - `test_a_new_ship_comes_fuelled_and_priced`: with 300 units left and 40 spares, launching the starter ship again costs 25 crowns (`Launched for 25 crowns.`), and she comes with 400.
  - Network: `test_fuel_reaches_the_guest`: after `sail_together()`, the host's ship set to 250 units: the guest's copy has 250 within 1.5 s, and a late joiner's entry has it.
  - Network: `test_a_junk_fuel_message_is_refused`: the guest's `sync._fuel` with an unknown ship, `−5.0`, `401.0`, `NAN`, `"x"` and `3` (an int): nothing changes and no error is logged.
  - Network: `test_the_server_ignores_junk_fuel_asks`: the guest's `_buy_fuel` sent 20 times in one frame, with the host's ship at the dock and 100 units, is answered once and charged once. From 3 km away ashore, it's refused and nothing changes.
  - `tests/test_save_game.gd`: ship records carry `"fuel"`. `test_a_version_1_save_still_loads`: a save written, then rewritten as version 1 without `fuel` in its ships or `logs` in its accounts, loads with each ship's tanks full and each account's logs `[]`. A version 3 save gives `This save is version 3; this game reads versions 1 and 2.`
  - `tests/test_cargo.gd`: the starter ship costs 1,480. `tests/test_economy.gd`: a grid with one block of every type costs the sum of `PART_COST` plus 250 (spares and a tankful); `value` takes fuel, and the whole starter ship with 40 spares and 400 units is worth exactly her cost. `tests/test_unlocks.gd`: `She costs 1480 crowns and you have 100.`, and insurance 740. `tests/test_sinking.gd`: the purse goes down by 740. `tests/test_abandon.gd`: insured 740.
  - `tests/test_world.gd`: the helm readout has `Spares    40/40\nFuel      400/400\nHold      0/4 crates`.
  - `tests/test_fleet.gd`: 13-field entries, and junk with fuel `401.0` and `"x"`. `tests/test_session.gd`: protocol version 7.
  - `tests/test_designed_ship.gd`: the skiff gets a fuel tank in place of its keel frame at `(0, −1, 3)`, so it has no warnings and reaches its top speed.
  - `tests/test_campaign.gd`: the Wallbreaker holds 800 units, and `Economy.cost` of her is 1,742.
- [ ] **Step 2: Run `./run_tests.sh fuel`.** Expected: fail.
- [ ] **Step 3: Implement** fuel in the ship, the starter ship's tanks, the stats, the helm's limit, prices, buying, the network, the readout and market, and saves at version 2.
- [ ] **Step 4: Run the whole suite.** Expected: pass. Every stage 2–7 flight and balance test stands: the starter ship weighs and trims as she did, and every flight test runs well within her 500 s of full throttle.
- [ ] **Step 5: Commit** "Burn fuel: tanks on every ship, engines and trim that drink it, fuel at the docks, and saves that keep it".

### Task 3: The Stormwall

Build-log item s08-01: "Region progression and the Stormwall crossing".

**Files:**
- Create: `tests/test_stormwall.gd`
- Modify: `src/world/wind.gd`, `src/world/world_gen.gd`, `src/world/world.gd`, `src/save/save_game.gd`, `tests/test_world_gen.gd`, `tests/test_save_game.gd`

**Interfaces:**
- Consumes: `Wallbreaker` (Task 1), fuel (Task 2), `WorldGen.REGION_OUTER`, `Dock.area`.
- Produces:
  - `Wind`: `const WALL_WIND := 22.0` (m/s outward in the wall's core), `const WALL_FADE := 150.0` (m over which it fades at its inner and outer edges), `const WALL_TOP := 1700.0` (m: full below), `const WALL_TOP_FADE := 200.0` (m: gone above `WALL_TOP` plus this); `static func wall_strength(p: Vector3) -> float`.
  - `WorldGen`: `const TOWN_PLAN` ends `[Region.EYE, 1]`; `const HEART_CLEAR := 800.0`, `const HEART_ISLANDS := 450.0`; `static func clear_of_the_wall(dock: Vector3) -> bool`.
  - `World`: stepping off your own test flight ends it; `func recover(prefer: Ship, at_bunk := false, quay_town := -1) -> Ship` (a quay town of 0 or more stands you on that town's quay instead of the nearest).

Rules:
- **The wall's wind:** `wall_strength(p)` is `smoothstep(1600, 1750, d) × (1 − smoothstep(2050, 2200, d)) × (1 − smoothstep(WALL_TOP, WALL_TOP + WALL_TOP_FADE, p.y))`, where d is p's horizontal distance from the centre (1,600 and 2,200 are `REGION_OUTER` for the Eye and the Stormwall). `Wind.at` adds `flat / d × WALL_WIND × wall_strength(p)`: outward, away from the Eye. Gusts and the prevailing wind stay as they are.
- **Towns:** the tenth town is drawn in the Eye. `clear_of_the_wall(dock)` holds when every corner of `Dock.area(dock)` and the town island's disc (`dock + TOWN_ISLAND`, `TOWN_RADIUS`) are either all within 1,600 m of the centre and at least `HEART_CLEAR` from it, or all at least 2,200 m from it. `_town_fits` requires it for every town.
- **The heart's open sky:** a plain island's disc keeps `HEART_ISLANDS` from the centre (`_plain_island_fits`).
- **Test flights:** when you step off your own test flight (`go_ashore` from her), she ends (`sync.end_test()`) and the HUD says `You stepped off your test flight, so it's over.` When she's removed while you're ashore, you board the ship you came from, else your own, else the home ship (never a wreck), and with none you stand on the quay of the town whose shipyard you flew from (`recover(_came_from, false, _yard_town)`).
- **Stage 7 saves wake in port:** towns have moved (the tenth always, and for some seeds the Gale Expanse's), and plain islands now grow where their exclusions were, so a ship saved near an old town could wake in the Stormwall or inside an island. `SaveGame.read` therefore moves each ship of a version 1 save to slipway k (her index in the ship list, modulo `Dock.SLIPWAYS`) of the town whose dock is nearest her, in `WorldGen.new(seed)`'s world: `Dock.slipway(dock, k)`, facing the bow, anchored. Version 2 saves keep their places.
- ponytail: the wall is the same all the way round; give it gaps (the spec's "gap in a sky river") if one route in feels thin.

- [ ] **Step 1: Write the failing tests** (`tests/test_stormwall.gd`; plain `TestCase` helpers in an `extends NetCase` file. The flight helper `cross(grid, angle, altitude, seconds, engineer := false) -> Dictionary` adds a plain ship with `weather = Wind.new(WorldGen.new(NetCase.SEED))` at `(cos a × 2450, altitude, sin a × 2450)` facing the centre, with an engineer at her first engine when asked, the autopilot on at that altitude and full throttle. Each tick it sets the wind's time to the tick's and `target_heading = atan2(p.x, p.z)` (straight for the centre), and returns `{"closest": m, "inside_at": s or −1}` for getting within 1,500 m):
  - `test_the_stormwall_blows_outward`: with `Wind.new()` (no rivers or storms), averaged over 600 s at `(0, 1000, −1900)`: the wind's z is −22 ± 1 (outward) and x is −14 ± 1 (the prevailing wind). At `(0, 2000, −1900)`, `(0, 1000, −1450)` and `(0, 1000, −2350)`, |z| is under 1. `wall_strength` is 1 at `(0, 1000, −1900)` and 0 at `(0, 1950, −1900)`.
  - `test_the_wall_is_smooth`: one-metre steps outward from 1,400 to 2,400 m at 1,000 m high, and upward from 1,500 to 2,100 m high at 1,900 m out: no step changes `Wind.new().at` by more than 3 m/s.
  - `test_the_starter_ship_cant_cross`: `cross(StarterShip.build(), a, 1100, 300, true)` for a = 0 and 3.9: `closest` stays over 1,700 m. (Holding 1,100 m takes trim 1.08, so with her engineer she burns about 1.55 units a second and runs dry after about 258 s; by then she has long been turned back.)
  - `test_the_wallbreaker_crosses`: `cross(Wallbreaker.build(), a, 1000, 240)` for a = 0.6 and 3.9: `inside_at` is between 0 and 240.
  - `test_a_ship_can_go_over_the_top`: the starter ship with lift stones at `(±1, −1, z)` for z −1…2, `cross(…, 0.0, 1900, 150)`: `inside_at` is between 0 and 150.
  - `test_no_town_stands_in_the_stormwall`: for seeds 1–20 and `NetCase.SEED`: ten towns, every one `clear_of_the_wall`, the tenth in the Eye with every corner of its dock area at least 800 m from the centre. No plain island in the chunks around the centre comes within 450 m of it.
  - `test_a_test_flight_cant_ferry_you_across`: a solo world at the dock, aboard your ship: a test flight of the starter ship, then `go_ashore()`: within 1 s the test ship is gone, you're aboard your own ship, and the HUD said `You stepped off your test flight, so it's over.`. After abandoning your own ship (nothing else to board), a test flight and stepping off leave you standing on the starting town's quay.
  - `tests/test_world_gen.gd`: the tenth town is in the Eye.
  - `tests/test_save_game.gd`: `test_a_stage_7_save_wakes_in_port`: a version 1 save of `NetCase.SEED` with two ships, one at stage 7's Stormwall town dock `(1927.6, 861.1, 530.0)` and one at `(100, 900, 6500)`: read back, the first is at `Dock.slipway` 0 of town 8 (the nearest dock now) and the second at slipway 1 of town 0, both level and anchored. The same save at version 2 keeps both places.
- [ ] **Step 2: Run `./run_tests.sh stormwall`.** Expected: fail.
- [ ] **Step 3: Implement** the wall's wind, towns clear of it, the heart's open sky, and test flights that end ashore.
- [ ] **Step 4: Run the whole suite.** Expected: pass (`test_wind`'s Stormwall walk too). Then fly by hand: the starter ship into the wall (she's pushed back), and the Wallbreaker through it (test-flown from a Gale town: it ends if you step off).
- [ ] **Step 5: Commit** "Raise the Stormwall: an outward wind only a strong ship can cross, and move the tenth town into the Eye".

### Task 4: Storms

Build-log item s08-03: "Storm events: lightning strikes, turbulence, low visibility".

**Files:**
- Create: `tests/test_storms.gd`
- Modify: `src/ship/tuning.gd`, `src/ship/ship.gd`, `src/world/wind.gd`, `src/world/weather.gd`, `src/world/world_sky.gd`, `src/world/world.gd`, `src/net/world_sync.gd`, `src/net/session.gd`, `tests/net_case.gd`, `tests/test_wind.gd`

**Interfaces:**
- Consumes: `Campaign.of` (Task 1), `wall_strength` (Task 3), `Damage.blast`, `Damage.ignite`, `damage_ship`, `_send_fires` (stage 6), `Weather.strike` (stage 5).
- Produces:
  - `Tuning.TURBULENCE := 0.1` (rad/s² of shake at full roughness).
  - `Wind`: `func roughness(p: Vector3, t: float) -> float` (`maxf(storm_strength(p, t), wall_strength(p))`); `static func shake(t: float) -> Vector3` (`Vector3(sin(1.7 t) + 0.5 sin(2.9 t), 0.3 sin(1.1 t), sin(1.3 t) + 0.5 sin(3.1 t))`).
  - `WorldSync`: `const STRIKE_RADIUS := 1.2`, `const STRIKE_DAMAGE := 60.0`, `const BOLT_HEIGHT := 600.0`; `signal struck(ship: Ship, cell: Vector3i)` (every machine); `func strike(ship: Ship) -> Vector3i` (server); `func _strike_storms() -> void` (server); RPC `_strike(id, cell)`.
  - `Session`: `var lightning := true` (server: storms strike ships in this game). `NetCase.make_session` sets it false.
  - `Weather.bolt_to(point: Vector3) -> MeshInstance3D`: a bolt from `BOLT_HEIGHT` above `point`, up to 80 m to one side, down to it.
  - `WorldSky`: `var storm := 0.0` (0–1: the roughness at the camera; the World sets it each frame), `const STORM_FOG := Color("4a4656")`.

Rules:
- **Turbulence:** in `_integrate_forces`, a ship that isn't `calm` or frozen, in air of roughness r above 0, gets `state.apply_torque(basis × (inertia × Wind.shake(t) × TURBULENCE × r))`, with t the world clock. Flight tests in calm air feel none. Clients see it through the snapshots, and crew feel it as the deck tilting.
- **A strike** (`strike(ship)`, server) hits her highest block by world y (ties within 0.01 m go to the smallest cell). It applies `Damage.blast(grid, cell, STRIKE_RADIUS, STRIKE_DAMAGE)` through `damage_ship`, then, if she's still here, `Damage.ignite` over the blast's cells with `rng`, as a shell's burst does (sending `_fires` when one caught). It tells everyone `_strike(id, cell)`, emits `struck` here, and returns the cell. On the starter ship it destroys one balloon cell and leaves its three face neighbours at 20 of 30 hit points, each of which catches fire a quarter of the time: about 0.75 fires a strike.
- **Storms strike** (`_strike_storms`, from `_wear` when `session.lightning`): each ship strikes with chance `Campaign.of(p)["strikes"] × wind.roughness(p, now())`, one `rng.randf()` each, in ship-id order.
- **Clients** take `_strike` for a known ship and a cell in the build area, emit `struck`, and ignore anything else without a warning. The damage arrives in `_blocks_changed` as any hit's does.
- **Bolts:** every machine with a Weather draws `bolt_to(ship.global_transform × Vector3(cell))` on `struck`.
- **Fog:** `WorldSky._apply` sets `fog_depth_begin = lerpf(900, 30, storm)`, `fog_depth_end = lerpf(2600, 400, storm)`, and `fog_light_color` the horizon colour blended toward `STORM_FOG` by `storm`. The World sets `storm` to `wind.roughness(camera position, sync.now())` each frame, and 0 with no player.
- ponytail: lightning strikes the highest block, with no lightning rods; add a rod block if players want a defence.

- [ ] **Step 1: Write the failing tests** (`tests/test_storms.gd`, `extends NetCase`; a `RoughAir` inner class extends `Wind` with no wind and a `roughness` of its own, as `test_wind.gd`'s `SteadyWind` does):
  - `test_turbulence_rocks_a_ship_in_rough_air`: a plain starter ship with `weather = RoughAir` at roughness 1, for 60 s: she rolls past 1.5° and pitches past 3° at some point. At roughness 0 she stays within 0.3° both ways.
  - `test_calm_flight_tests_feel_no_turbulence`: the same ship, `calm`, at roughness 1: within 0.3° both ways.
  - `test_lightning_strikes_the_highest_block`: a solo world, your ship anchored level at the dock: `sync.strike(ship)` returns `(−1, 10, −4)`, which is destroyed; its face neighbours in the grid (`(0, 10, −4)`, `(−1, 9, −4)` and `(−1, 10, −3)`) are at 20 hit points, and nothing else changed; `struck` fired once with that ship and cell.
  - `test_a_strike_can_start_a_fire`: `sync.rng.seed = 1`, ten strikes on your ship: at least one fire is burning afterwards (each strike has about a 58% chance of starting one).
  - `test_storms_strike_only_in_rough_air`: lightning on, `sync.rng.seed = 1`, your ship anchored at the Stormwall spot `(0, 1000, −1900)` after `open_sky`: 300 `_strike_storms()` strike between 5 and 30 times (about 15 expected). At `(0, 1950, −1900)`, above the wall: none in 300. At the dock: none. Back in the wall with `session.lightning = false`, 60 `_wear()`s strike nothing.
  - `test_the_fog_closes_in_inside_a_storm`: a solo world, your ship moved to `(0, 1000, −1900)`: a frame later the sky's `fog_depth_end` is under 450 and `fog_depth_begin` under 100. Back at the dock: 2,600 and 900.
  - Network: `test_guests_see_lightning`: after `sail_together()`, the host's `sync.strike(ship)`: within 1 s the guest's `struck` fired for that cell, its Weather drew a bolt (`bolts_struck` went up), and its copy lost the cell.
  - Network: `test_a_junk_strike_is_ignored`: the guest's `sync._strike` with an unknown ship, a cell at x 100, a `String` cell and an int ship of `"1"`: no `struck`, no bolt, no error.
  - `tests/test_wind.gd`: `roughness` is 1 in the wall below its top, 0 above it, and a storm core's strength inside one.
- [ ] **Step 2: Run `./run_tests.sh storms`.** Expected: fail.
- [ ] **Step 3: Implement** turbulence, strikes, `_strike`, bolts and storm fog, and the `lightning` switch.
- [ ] **Step 4: Run the whole suite, then fly by hand:** into a Gale storm and into the wall. Watch for strikes, the rolling deck and the fog.
- [ ] **Step 5: Commit** "Make storms felt: lightning that strikes ships, turbulence that rocks them, and fog that closes in".

### Task 5: A leviathan

Build-log item s08-02: "Sky leviathans that roam with their own behaviour, plus one boss" (the creature).

**Files:**
- Create: `src/ai/leviathan.gd`, `src/ai/leviathans.gd`, `tests/test_leviathans.gd`
- Modify: `src/net/world_sync.gd`, `src/net/session.gd`, `src/economy/ledger.gd`, `src/world/world.gd`, `tests/net_case.gd`

**Interfaces:**
- Consumes: `Economy.LEVIATHAN_REWARD`, `BOUNTY_REACH` (Task 1); `Damage.blast`, `damage_ship`, `_knock_out`, `crew_positions`, `Projectiles` hits (stage 6); `Ledger._players_near` (stage 7).
- Produces:
  - `class_name Leviathan extends AnimatableBody3D`:
    - `const LAYER := 1 << 4` (collision layer 5; mask 0).
    - `const KINDS := {"leviathan": {"length": 36.0, "radius": 4.0, "hp": 2000, "cruise": 8.0, "charge": 24.0, "turn": 0.35, "ram_radius": 3.0, "ram_damage": 120.0}, "warden": {"length": 72.0, "radius": 8.0, "hp": 6000, "cruise": 12.0, "charge": 26.0, "turn": 0.25, "ram_radius": 5.0, "ram_damage": 180.0}}`. The wire sends the kind's name.
    - `const MOODS := ["drift", "curious", "angry", "slain"]`.
    - `const THINK_EVERY := 0.5`, `const ACCEL := 4.0` (m/s²), `const CLIMB := 6.0` (m/s), `const LOW := 600.0`, `const HIGH := 1600.0` (the heights it drifts between), `const SIGHT := 600.0`, `const BESIDE := 120.0`, `const CURIOUS_TIME := 60.0`, `const BORED_TIME := 90.0`, `const CALM_AFTER := 45.0`, `const GIVE_UP := 1500.0`, `const RAM_REACH := 3.0`, `const RAM_PUSH := 3.0` (m/s), `const BACK_OFF := 6.0`, `const SINK := 15.0`, `const SLAIN_TIME := 25.0`.
    - `var kind: String`, `var hp: int`, `var mood := "drift"`, `var target: Ship`, `var velocity := Vector3.ZERO`, `var heading := 0.0` (as `Ship.heading()` counts), `var simulated := true` (false on clients), `var held := false` (it doesn't move: for tests).
    - `func _init(world_sync: WorldSync, beast_kind: String, with_visuals: bool)`; `func forward() -> Vector3`; `func head() -> Vector3` (world: its middle plus `forward() × length / 2`); `func hurt(damage: int, by: Ship) -> void` (server); `static func damage_of(ammo: String) -> int` (`AMMO[ammo]["damage"] + AMMO[ammo]["blast_damage"]`, rounded: round 160, chain 60, shell 130, harpoon 20).
  - `class_name Leviathans extends Node` (named `Leviathans`, added to the World after its Ledger): `var sync: WorldSync`; `var beasts: Dictionary = {}` (id → Leviathan); `func _init(world_sync: WorldSync, with_visuals: bool)`; server: `func spawn(kind: String, at: Vector3, facing: float) -> Leviathan`, `func remove(beast: Leviathan) -> void`, `func shot(beast: Leviathan, ammo: String, by: Ship) -> void`.
  - `WorldSync`: `var leviathans: Leviathans` (set by the World); `func ram(ship: Ship, at: Vector3, radius: float, damage: float, push: Vector3) -> void` (server).
  - `Ledger.reward_near(at: Vector3, amount: int, text: String) -> void` (server: pays each player within `BOUNTY_REACH` of `at`, not on a test flight, and tells them `text`).
  - `Session`: `var leviathans := true` (server: leviathans roam, and the Warden wakes, in this game). `NetCase.make_session` sets it false.

Rules:
- **Its body:** a `CapsuleShape3D` of its kind's radius, `length` long, along its z, on `LAYER` with mask 0. Shots' rays hit it; ships and crew pass through it. It's moved by setting its transform, with the basis `Basis(Vector3.UP, heading)`.
- **Its look** (with visuals): nine sphere segments along its length, radii tapering `[0.6, 0.85, 1, 1, 0.95, 0.85, 0.7, 0.5, 0.35]` of its radius, slate `Color("55626f")` (the Warden `Color("3b2f3a")`); two flat fins by the second segment; two small emissive eyes, pale `Color("e8f0ff")`, and `Color("ff5a3a")` while angry. Each frame the segments swim sideways by `sin(2 t − 0.7 i) × radius × 0.3 × i / 9`. ponytail: one MeshInstance3D a segment (about 12 draw calls a beast) and a hitbox that doesn't follow the swimming; one skinned mesh if many beasts cost frames.
- **Moving** (server, each physics tick, unless `held` or slain): its heading turns toward its wish at `turn` rad/s, its speed eases toward its wish at `ACCEL`, it climbs or sinks toward its wished height at `clampf((wish − y) × 0.2, −CLIMB, CLIMB)`, and `velocity` is its forward times its speed plus that climb. A slain one sinks at `SINK` and doesn't think. ponytail: leviathans swim through islands; steer them around (as pirates would need) if players notice.
- **Moods** (server, every `THINK_EVERY`):
  - **angry** (hurt within `CALM_AFTER`, with a target that's still here, not a wreck, and within `GIVE_UP`): charges at `charge` toward where its target will be (her place plus her velocity times the distance over `charge`), at her height. Within `RAM_REACH` of her world box, its `head()` rams: `sync.ram(target, head(), ram_radius, ram_damage, forward() × RAM_PUSH)`, then it swims straight away at `cruise` for `BACK_OFF` before charging again. Otherwise it calms to **drift**, with no target.
  - **curious**: the nearest ship within `SIGHT` that isn't a pirate, a wreck or a test flight, and that it isn't bored of. It swims for the point `BESIDE` off her nearer side, at her horizontal speed plus a fifth of its distance to that point (at most 0.6 × `charge`). After `CURIOUS_TIME` it drifts, bored of her for `BORED_TIME`. It never harms anyone.
  - **drift**: `cruise`, its heading wandering by `rng.randf_range(−0.2, 0.2)` each think, with a new wished height in `LOW`–`HIGH` every 30 s.
- **Hurt** (`hurt(damage, by)`): `hp −= damage`. At 0 or below it's **slain**. Otherwise a leviathan turns **angry**, with `by` as its target if `by` is a ship that's here and not a wreck, and its calm clock starts again.
- **Shots:** `WorldSync._on_shot_hit` sends a shot whose collider is a `Leviathan` to `leviathans.shot(beast, ammo, the firing ship)`, which calls `hurt(Leviathan.damage_of(ammo), by)`. Crew bursts and `_hit` go out as for any hit.
- **Slain:** `Ledger.reward_near(its place, LEVIATHAN_REWARD, "The leviathan falls. +%d crowns." % LEVIATHAN_REWARD)`. It's removed when below `Tuning.ROIL_ALTITUDE`, or `SLAIN_TIME` after it fell.
- **A ram** (`WorldSync.ram`): the blast at `at`, in her space and clamped into her box, goes through `damage_ship`; each player within `radius + 1` of `at` is knocked down; and a ship that isn't frozen gets `apply_central_impulse(push × mass)`.
- This task's `Leviathans` lives on the server only; Task 6 puts leviathans on every machine and lets them roam.

- [ ] **Step 1: Write the failing tests** (`tests/test_leviathans.gd`, `extends NetCase`; a solo world, `sync.rng.seed = 1`, your ship anchored at `open_sky(world, 1000)`; leviathans added with `world.leviathans.spawn("leviathan", …)`):
  - `test_a_leviathan_drifts`: one spawned 1,500 m from your ship at 1,000 m: after 60 s it has moved more than 300 m, stayed between 600 and 1,600 m high, is still drifting, and your ship is whole.
  - `test_a_leviathan_is_curious_and_harmless`: one spawned 500 m off, heading across your bow: within 60 s it's within 200 m of your ship and curious. After 60 s more, every block of your ship is at full hit points.
  - `test_shots_hurt_and_anger_a_leviathan`: one `held` 200 m to starboard: round shot from your starboard cannon, aimed with `Projectiles.aim` at its middle: within 3 s its hp is 1,840, it's angry, and its target is your ship.
  - `test_an_angry_leviathan_rams`: one angry at your ship from 300 m off: within 40 s your ship has lost blocks, and within 20 s more she has lost more (it backed off and rammed again).
  - `test_a_ram_knocks_down_crew_nearby`: `sync.ram(ship, your world position, 3.0, 120.0, Vector3.ZERO)`: you're knocked down and the blocks around you lost hit points. A ram 20 m from you doesn't knock you down.
  - `test_an_angry_leviathan_calms_down`: angry at your ship 300 m off and never hurt again: `CALM_AFTER` + 1 s later it's drifting with no target. Angry again, with your ship moved 2 km off: within 1 s it's drifting (she got away).
  - `test_a_slain_leviathan_sinks_and_pays`: shot by `shot(beast, "round", ship)` until slain (13 times): it's slain, your purse is up 300, and the HUD says `The leviathan falls. +300 crowns.`. Within 25 s it's gone from `beasts`. A second one slain while you're on a test flight pays nothing.
- [ ] **Step 2: Run `./run_tests.sh leviathans`.** Expected: fail.
- [ ] **Step 3: Implement** `Leviathan`, the server's `Leviathans`, shots into them, rams, and rewards.
- [ ] **Step 4: Run the whole suite.** Expected: pass.
- [ ] **Step 5: Commit** "Add leviathans: drifting, curious, angered by shots, ramming whoever shot them, and slain for a reward".

### Task 6: Leviathans roam the Gale Expanse, on every machine

Build-log items s08-02: "Sky leviathans that roam with their own behaviour, plus one boss" (roaming and the network) and s08-06: "Difficulty tuning across regions" (where they roam).

**Files:**
- Create: `tests/test_leviathans_net.gd`
- Modify: `src/ai/leviathans.gd`, `src/ai/leviathan.gd`, `src/ai/crew_hand.gd`, `src/ai/pirate_captain.gd`, `src/net/world_sync.gd`, `src/ui/map_view.gd`

**Interfaces:**
- Consumes: `Campaign.REGIONS` (Task 1); the server's `Leviathans` (Task 5); `SnapshotBuffer`, `WorldSync.DELAY`, `peer_entered`, `player_positions`, `FAR` (stages 3–6).
- Produces:
  - `Leviathans`: `const SEND_EVERY := 6` (physics ticks: 10 Hz), `const ROAM_EVERY := 30.0`, `const NEAR := 2000.0`, `const MAX := 4`, `const DISTANCE := 900.0`; `func _roam() -> void` (server); RPCs `_beast_added(time, entry)`, `_beast_removed(id)`, `_beasts(time, states)` (channel 1, unreliable-ordered), `_beast_hurt(id, hp)`.
  - `WorldSync.peers_in_world() -> Array[int]`.
  - `PirateCaptain.fire_at_point(world_sync: WorldSync, ship: Ship, cannon: Cannon, aim_point: Vector3, velocity: Vector3, ammo: String) -> bool` (static): the leading and firing `fire_at` does, aimed at a point moving at `velocity`. `fire_at` calls it, with no change in behaviour.
  - `MapView`: leviathans drawn as dots, `const BEAST := Color("9b7fd4")`, the Warden's bigger.

Rules:
- **Roaming** (server, every `ROAM_EVERY` when `session.leviathans`): for each crewed ship that isn't a pirate, wreck or test flight, with her region's `leviathans` above 0: if fewer than that many leviathans are within `NEAR` of her and fewer than `MAX` are about, then with her region's `spawn` chance (`rng`), one comes in `DISTANCE` away at a random angle, at her height clamped to `LOW`–`HIGH`, heading across her path.
- **Upkeep** (server, every second): a leviathan further than `WorldSync.FAR` from every player is removed. A drifting leviathan outside the Gale Expanse heads for the ring 3,100 m from the centre.
- **On every machine:** `spawn` tells everyone `_beast_added(time, [id, kind, position, velocity, heading, hp, mood])`, `remove` tells `_beast_removed(id)`, and each hurt tells `_beast_hurt(id, hp)`. Every `SEND_EVERY` ticks the server sends `_beasts(time, states)`. A late joiner gets a `_beast_added` for each leviathan after `_world` (on `peer_entered`).
- **Clients** add a `Leviathan` with `simulated = false`, which never thinks, and draw it `WorldSync.DELAY` behind along a `SnapshotBuffer`, as ships are drawn. They check everything: an entry needs a new int id, a `KINDS` key, a finite position and velocity, a finite heading, hp from 0 to its kind's, and a mood index; a state needs an id they know and finite numbers; `_beast_hurt` needs a known id and hp from 0 to its kind's. Junk is ignored without a warning.
- **Gunners** (`CrewHand._gun`) fire at the nearest within `PirateCaptain.FIRE_RANGE` of the pirates that aren't wrecks and the leviathans that are angry. At a leviathan they fire round shot through `fire_at_point(…, beast.global_position, beast.velocity, "round")`. They never fire at a drifting or curious leviathan.

- [ ] **Step 1: Write the failing tests** (`tests/test_leviathans_net.gd`, `extends NetCase`; a solo world unless marked network):
  - `test_leviathans_roam_the_gale`: leviathans on, `sync.rng.seed = 1`, your ship anchored at the Gale spot `(0, 1000, −3000)` after `open_sky`: 20 `_roam()`s bring exactly 2 leviathans, each first seen 900 m from her. At the dock (the Calm Reaches): none in 20. At the Gale spot with `session.leviathans = false`: none. Your ship moved 3.5 km away: both are removed within 1 s.
  - `test_a_drifting_leviathan_keeps_to_the_gale`: one spawned 4,200 m from the centre heading outward: within 120 s it's within 4,000 m.
  - `test_gunners_fire_at_angry_leviathans`: a gunner at the starboard cannon `(2, 1, 1)`; a `held` leviathan 300 m to starboard. Drifting: no shot in 10 s. Angry: a shot leaves `(2, 1, 1)` within 8 s, and its hp falls within 15 s.
  - Network: `test_guests_see_leviathans`: after `sail_together()`, the host spawns one 300 m off: within 1 s the guest has a `Leviathan` with its id and kind, not simulated, drawn within 10 m of where the host had it `DELAY` ago. A `shot` on the host gives the guest the same hp within 1 s, and its removal removes it. A late joiner has it.
  - Network: `test_junk_beast_messages_are_refused`: the guest's `_beast_added` with kind `"dragon"`, a `NAN` position, hp −1, hp 99,999 and an id it already has; `_beasts` with a `String`, a three-field state and an unknown id; `_beast_hurt` with hp 99,999 and an unknown id: nothing changes and no error is logged.
  - `tests/test_pirates.gd` and `tests/test_hands.gd` pass unchanged (`fire_at` behaves as before).
- [ ] **Step 2: Run `./run_tests.sh leviathans_net`.** Expected: fail.
- [ ] **Step 3: Implement** roaming and upkeep, the RPCs and drawing on clients, late joiners, gunners and the map.
- [ ] **Step 4: Run the whole suite, then fly by hand** into the Gale Expanse and wait for a leviathan. Let it pace you, then shoot it.
- [ ] **Step 5: Commit** "Let leviathans roam the Gale Expanse on every machine, and send gunners after the angry ones".

### Task 7: The Warden

Build-log items s08-02: "Sky leviathans that roam with their own behaviour, plus one boss" (the boss) and s08-05: "The Eye: the final region and the ending" (its guardian).

**Files:**
- Create: `tests/test_warden.gd`
- Modify: `src/ai/leviathan.gd`, `src/ai/leviathans.gd`, `src/net/world_sync.gd`, `src/world/world.gd`, `src/save/save_game.gd`

**Interfaces:**
- Consumes: `Campaign.HEART`, `Economy.WARDEN_REWARD` (Task 1); `WorldSync.strike` (Task 4); leviathans (Tasks 5 and 6).
- Produces:
  - `Leviathan`: `const ORBIT := 300.0`, `const REACH := 700.0`, `const LEASH := 900.0`, `const BOLT_EVERY := 12.0` (the Warden's).
  - `Leviathans`: `const WAKE := 2500.0`, `const SLEEP := 3500.0`; `func warden() -> Leviathan` (or null); `func _guard() -> void` (server, every second).
  - `WorldSync`: `var warden_beaten := false` (server).
  - A save's world gains `"warden"`: whether the Warden is beaten.

Rules:
- **Waking** (`_guard`, when `session.leviathans` and the Warden isn't beaten): with no Warden and a player within `WAKE` of the heart (horizontally), the Warden is spawned at `Campaign.HEART + Vector3(ORBIT, 0, 0)`. With a Warden and every player further than `SLEEP`, it's removed. ponytail: the Warden heals when everyone leaves; keep its hit points in the world if players feel cheated.
- **Guarding** (its moods): its target is the nearest ship within `REACH` of the heart (horizontally) that isn't a pirate, a wreck or a test flight; a ship it's hurt by counts too, while she's within `LEASH`. With a target it's angry and charges and rams as a leviathan does, never calming, and every `BOLT_EVERY` it calls `sync.strike(target)`. With none, or once it's further than `LEASH` from the heart, it drops its target and circles the heart at `ORBIT`, at `HEART.y`: along `(to.cross(Vector3.UP) + to × clampf((d − ORBIT) / ORBIT, −1, 1) × 0.8).normalized()`, where `to` is the horizontal direction to the heart and d the distance. It's never curious.
- **Slain:** `warden_beaten` is set, everyone in the world is told `The Warden falls. The way to the heart is open.`, and each player within `BOUNTY_REACH` is paid `WARDEN_REWARD` with `The Warden falls. The way to the heart is open. +%d crowns.` instead. It sinks as a leviathan does, and never wakes again.
- **Saves:** `capture` writes `"warden": warden_beaten`, and `_restore` sets it. `_read_world` takes `warden` as a bool, and a world without it (version 1) reads as false.

- [ ] **Step 1: Write the failing tests** (`tests/test_warden.gd`, `extends NetCase`; a solo world with leviathans on and `sync.rng.seed = 1`, after `open_sky`, unless marked):
  - `test_the_warden_wakes_when_you_near_the_heart`: your ship anchored at `(0, 1000, −1500)`: `_guard()` wakes one Warden (kind `"warden"`, hp 6,000). After 60 s it circles 250–350 m from the heart (horizontally), within 100 m of its height. Your ship moved 4 km off: the next `_guard()` removes it.
  - `test_the_warden_attacks_ships_near_the_heart`: your ship anchored 500 m from the heart: within 60 s she has lost blocks to a ram, and `struck` fired for her at least once. With your ship anchored 1,000 m from the heart instead, she's untouched after 60 s.
  - `test_the_warden_keeps_to_the_heart`: the Warden angry at your ship 600 m from the heart; your ship moved to 1,400 m: within 30 s the Warden is within `LEASH` of the heart and has no target.
  - `test_slaying_the_warden_opens_the_heart`: shot to 0 (38 round shots by `shot`): `warden_beaten`, your purse up 2,000, and the HUD says `The Warden falls. The way to the heart is open. +2000 crowns.`. `_guard()` never wakes another.
  - `test_the_warden_stays_beaten_in_a_save` (with `SaveGame.dir` a temp folder, `save_slot = "1"`): after it's slain, `save_game()` writes `"warden": true`, and a world loaded from that slot has `warden_beaten`. A version 1 save loads with it false.
- [ ] **Step 2: Run `./run_tests.sh warden`.** Expected: fail.
- [ ] **Step 3: Implement** waking, guarding, the Warden's bolts, its fall, and saving it.
- [ ] **Step 4: Run the whole suite.** Expected: pass.
- [ ] **Step 5: Commit** "Bind the Warden to the heart of the Eye: it wakes when you come near, rams and calls lightning, and stays beaten".

### Task 8: Story logs

Build-log item s08-04: "Story told through logs found in ruins and towns".

**Files:**
- Create: `src/ui/log_book.gd`, `tests/test_logs.gd`
- Modify: `src/economy/ledger.gd`, `src/world/world.gd`, `src/ui/hud.gd`, `src/builder/shipyard.gd`, `project.godot`, `tests/test_project.gd`

**Interfaces:**
- Consumes: `Story`, `Wallbreaker`, accounts with `logs` (Task 1); the Ledger's asks and accounts (stage 7).
- Produces:
  - `Ledger`: `func read_log(index: int) -> void` (this machine's player); RPC `_read_log(index)`.
  - `class_name LogBook extends CanvasLayer`: `signal close_requested`; `func _init(world_ledger: Ledger)`; `func show_log(index: int) -> void`; `var titles: Array[Button]` (for tests).
  - `World`: `var log_book: LogBook`; `func log_in_reach() -> int` (the log whose spot is within `Story.REACH` of you, or −1; the heart's never); `func read_log(index: int) -> void`; `func open_log_book() -> void`; `func close_log_book() -> void`.
  - `Hud`: `var log_spot := -1` (set by the World each frame).
  - Action `logs` on L.

Rules:
- **Reading** (E, when nothing else takes it and no wreck is in reach to salvage): `World.read_log(log_in_reach())` opens the log book on that log at once (its words are the same on every machine) and asks the server to record it. The HUD prompt `E   Read the log` comes after `E   Salvage`.
- **The server** (`_read_log_for(peer, index)`): `index` must be a log other than the heart's with a spot in this world, and the reader's last world position within `Story.REACH + WorldSync.REACH_SLACK` of it. On a test flight it says `Logs found on a test flight aren't kept.` and keeps nothing. A log already found does nothing. Otherwise it's added to their `logs` and the account sent. A log that unlocks a part adds it to their unlocks (unless they have it) and says `Unlocked %s.` (the part's name). A log that gives a blueprint says `The %s's drawings are in your shipyard.` (the blueprint's name).
- **The log book** (L, or E at a log) is in the UI theme. Its caption is `Logs`, then a button for each log you've found (its title), in log order, then the shown log's title and text, then `Close (L)`. With none found it reads `No logs yet. They're found at landmarks and on town quays.` L, Esc or Close shuts it. While it's open your controls stop and the mouse is free, as for the town panel. It shows what `ledger.mine["logs"]` holds, refreshing when the account changes.
- **The shipyard's blueprints** list `Story.blueprints(account["logs"])` after `Starter ship`, and pressing one puts `Story.blueprint(name)` in the design.
- **Saves** keep `logs` in each account by name (`read_account` already reads it).

- [ ] **Step 1: Write the failing tests** (`tests/test_logs.gd`, `extends NetCase`; a solo world unless marked network; "ashore at" a spot is `go_ashore()` then the crew put there, as `test_salvage.gd` does):
  - `test_a_log_is_read_at_its_landmark`: ashore at `Story.spot(gen, 1)`: the prompt is `E   Read the log`; E opens the log book showing `Carved at the spire's foot` and its text, and `mine["logs"]` is `[1]`. E again: still `[1]`. Ashore 40 m from it: no prompt, and `log_in_reach()` is −1.
  - `test_town_logs_are_on_the_quay`: ashore at the starting town's quay spot: E reads log 0.
  - `test_the_log_book_keeps_what_you_found`: L with nothing found reads `No logs yet. They're found at landmarks and on town quays.`. After logs 0 and 1, it lists their two titles; pressing the second shows its text. L closes it and gives your controls back.
  - `test_the_armourers_ledger_unlocks_alloy`: reading log 3 adds `alloy` to your unlocks, says `Unlocked Alloy plate.` and charges nothing; back at the dock, a design with an alloy plate launches.
  - `test_the_wallwrights_notes_give_the_wallbreaker`: reading log 5 says `The Wallbreaker's drawings are in your shipyard.`. The shipyard's blueprints then list `Wallbreaker`, and pressing it puts `Wallbreaker.build()`'s blocks in the design.
  - `test_logs_are_kept_by_name_in_a_save` (`SaveGame.dir` a temp folder, `save_slot = "1"`): after reading logs 0 and 1, a saved and reloaded game gives you `[0, 1]`.
  - Network: `test_a_guest_reads_a_log`: after `sail_together()`, the guest ashore at log 1's spot reads it: within 1 s the host's account for `Guest` has `[1]`, and so does the guest's `mine`.
  - Network: `test_the_server_ignores_junk_log_asks`: the guest's `_read_log` with 99, −1, `"1"`, 11 (the heart's), log 1 from 1 km away, and log 1 from aboard the guest's own test flight moved to its spot: no account changes.
  - `tests/test_project.gd`: `logs` is L.
- [ ] **Step 2: Run `./run_tests.sh logs`.** Expected: fail.
- [ ] **Step 3: Implement** reading and recording logs, their unlocks, the log book, L, the prompt, and the shipyard's story blueprints.
- [ ] **Step 4: Run the whole suite, then play by hand:** read the quay's notice, then fly to the nearest landmark and read its log.
- [ ] **Step 5: Commit** "Tell the story in logs found at landmarks and on quays, kept by name, with two that unlock alloy and the Wallbreaker".

### Task 9: The heart of the Eye, and the ending

Build-log item s08-05: "The Eye: the final region and the ending".

**Files:**
- Create: `src/ui/ending_screen.gd`, `tests/test_ending.gd`
- Modify: `src/campaign/campaign.gd`, `src/economy/ledger.gd`, `src/net/world_sync.gd`, `src/world/world.gd`

**Interfaces:**
- Consumes: `Campaign.HEART`, `HEART_REACH`, `Story.HEART_LOG` (Task 1); `warden_beaten` (Task 7); the log book (Task 8).
- Produces:
  - `Campaign`: `static func create_heart(visuals: bool) -> Node3D`.
  - `Ledger`: `signal ending` (this machine's player sees the ending); `func check_heart() -> void` (server, from `_wear`); RPC `_ending()`.
  - `class_name EndingScreen extends CanvasLayer`: `signal closed`; `const CREDITS := ["Skywright", "Built with Godot 4.7.2, Jolt Physics and GDScript.", "Every ship, island, sky and storm is made by the game's own code.", "Thanks for flying."]`.
  - `World`: `var heart: Node3D`; `var ending_screen: EndingScreen`.

Rules:
- **The heart** (`create_heart`), at `Campaign.HEART`: a low-poly stone (a sphere mesh of 6 rings and 8 segments, flat shaded, 60 m across and 40 m tall, `Color("8d8578")` with a faint emissive glow) on a `StaticBody3D` with a 28 m sphere, and a pillar of pale light (an unshaded, emissive, half-transparent cylinder 6 m in radius) from 200 m to 2,200 m that casts no shadow. A dedicated server's has the body only. The World adds it beside the towns and turns the stone once every 120 s with a looping tween.
- **Reaching it** (`check_heart`, server, each `_wear`): when `warden_beaten`, if a player within `HEART_REACH` of the heart (by `_players_near`, so not on a test flight) hasn't found `HEART_LOG`, every player in the world who hasn't is given it (account sent) and sees the ending: `ending` emits for this machine's player, and the others get `_ending()`. A player who has it sees nothing again. Before the Warden falls nothing happens.
- **The ending screen**, in the UI theme: the caption `The heart of the Eye`, the heart's log text (`Story.LOGS[HEART_LOG]["text"]`), the caption `Credits` and each line of `CREDITS`, and a `Fly on` button. While it's up, your controls stop and the mouse is free; `Fly on` (or Esc) closes it and gives them back. The world goes on: nothing is removed, saved or reset. The log book can reread `The Keel`.

- [ ] **Step 1: Write the failing tests** (`tests/test_ending.gd`, `extends NetCase`; a solo world with leviathans off, after `open_sky`, unless marked network):
  - `test_the_heart_stands_at_the_centre`: the world's `heart` is at `Campaign.HEART` with a `StaticBody3D`. A dedicated server's world has one with no `MeshInstance3D`.
  - `test_the_heart_waits_for_the_warden`: your ship moved to within 200 m of the heart with the Warden not beaten: after three `_wear()`s, no ending screen, and your logs lack 11.
  - `test_reaching_the_heart_ends_the_story`: `warden_beaten` set, your ship moved within 200 m: within 2 s the ending screen shows `The heart of the Eye`, the Keel's text, `Credits` and `Fly on`; your controls are off and your logs have 11. `Fly on` closes it, gives your controls back, and the world's clock and your ship go on. Three more `_wear()`s there bring no second ending.
  - `test_a_test_flight_doesnt_end_the_story`: `warden_beaten` set, a test flight of the starter ship moved within 200 m: no ending, and your logs lack 11.
  - Network: `test_everyone_present_sees_the_ending`: after `sail_together()`, `warden_beaten` set and the host's ship (with both aboard) moved to the heart: within 2 s both machines show the ending screen, and both accounts have log 11. A client that joins afterwards doesn't see it.
- [ ] **Step 2: Run `./run_tests.sh ending`.** Expected: fail.
- [ ] **Step 3: Implement** the heart, reaching it, `_ending`, and the ending screen.
- [ ] **Step 4: Run the whole suite, then play by hand:** with `warden_beaten` set by a temporary line (removed before committing), fly a Wallbreaker over the Stormwall to the heart and read the ending. Check the heart's light is visible from the Eye's town.
- [ ] **Step 5: Commit** "Raise the Keel at the heart of the Eye, and play the ending for everyone there once the Warden falls".

### Task 10: The campaign on two machines, README and spec

Build-log item s08-06: "Difficulty tuning across regions" (measured across the regions in a live world), and the stage's promise for s08-01 to s08-05.

**Files:**
- Create: `tests/test_campaign_net.gd`
- Modify: `README.md`, `docs/superpowers/specs/2026-09-29-skywright-design.md`

- [ ] **Step 1: Write the tests** (`tests/test_campaign_net.gd`, `extends NetCase`):
  - `test_each_region_is_harder_than_the_last`: a solo world with pirates, leviathans and lightning on, `sync.rng.seed = 1`, after `open_sky`. Your ship anchored in turn at an open spot in the Calm Reaches (`(−6000, 1000, 2000)` checked at least 1,500 m from every dock), at `open_sky`'s spot (the Shattered Belt), at the Gale spot `(0, 1000, −3000)`, in the Stormwall at `(0, 1000, −1900)` and in the Eye at `(0, 1000, −1000)`. At each, 40 `_raid()`s and 20 `leviathans._roam()`s (removing what came before moving on): pirates 1, 2, 2, 0 and 0; leviathans (not counting the Warden, who wakes in the Eye) 0, 0, 2, 0 and 0. 300 `_strike_storms()` strike in the Stormwall and in a Gale storm's core (her moved there), and nowhere else. A bounty at town 7 pays 400 a pirate against town 0's 250.
  - `test_host_and_guest_fight_a_leviathan`: after `sail_together()` with both aboard the host's ship, the host spawns a leviathan angry at her 300 m off and `shot`s it to death, one round shot a second: after each, the guest has the same hp within 1 s; at the end both purses are up 300, and both machines lose it.
  - `test_the_campaign_stays_within_the_network_budget`: four leviathans swimming around the host's ship and a strike on her every second for 20 s: the guest's `get_host().pop_statistic(HOST_TOTAL_RECEIVED_DATA)` over those 20 s is under 20 × 32 KB.
  - `test_a_dedicated_server_runs_the_campaign`: a dedicated host in this process with leviathans on; a guest joins, launches their own ship, is moved with her to the Gale spot, and reads log 0 at the start town's quay first. `_roam()` on the server brings a leviathan the guest sees within 1 s, and the server's account for `Guest` has log 0.
- [ ] **Step 2: Run the whole suite three times.** Expected: it passes every time.
- [ ] **Step 3: Measure by hand** on the Radeon 680M (`godot --path . --gpu-index 0 -- --solo --seed=20260930` after choosing a slot): fly into the Stormwall and sit in its fog through a few strikes with two leviathans and then the Warden in view. Record the lowest and typical fps in "Changes during execution". If a frame takes more than 16 ms, record what was on screen; one MultiMesh a leviathan and a skinned body are the upgrades (ponytail in `Leviathan`).
- [ ] **Step 4: Update the README:**
  - The status: stage 8 of 10, and what you can do now: fuel your ship and watch her range, cross the Stormwall in a capable ship (or over it), weather storms that strike and rock you, meet leviathans and fight the Warden, find and reread logs, and reach the heart for the ending.
  - Controls: L opens the logs; E reads a log at its spot.
  - "The world": the tenth town is in the Eye; the Stormwall blows outward; the heart of the Eye.
  - "Towns and money": fuel (4 units a crown, a full load priced into a launch), prices and rewards that grow inward.
  - A "Campaign" section: the regions and their dangers (the table in words), fuel and range, the Stormwall and the two ways across, storms, leviathans and their moods, the Warden, logs and the two story unlocks, the heart and the ending.
  - "Saves": version 2, and stage 7 saves load with full tanks and every ship in port at the town nearest her.
  - The layout gains `src/campaign/`.
- [ ] **Step 5: Update the spec:**
  - the status line;
  - §3.1 (the tenth town in the Eye; the Stormwall's wind and top; the heart's open sky);
  - §3.3 (the starter ship's tanks);
  - §3.4 (still no engine station; an engineer burns more fuel);
  - §3.5 (raids by the region table; leviathans and the Warden as built; weather as built);
  - §3.6 (fuel prices and launches with fuel, the starter ship at 1,480; region prices and rewards; the two story unlocks);
  - §3.7 (the campaign as built: logs, the Warden, the heart, the ending);
  - §4.2 (`src/campaign/` exists);
  - §4.4 (fuel: 200 units a tank, weightless, the burn rates, no thrust and trim 1.0 without it; turbulence);
  - §4.6 (protocol 7 and its budget);
  - §4.7 (the wall's wind; towns clear of the wall; no island near the heart);
  - §4.8 (storm fog; bolts on ships);
  - §4.10 (saves at version 2, reading version 1);
  - §9 decisions: fuel weighs nothing; the Stormwall is wind (22 m/s below 1,700 m), crossed by thrust or height; the tenth town is in the Eye; test flights end when you step off; leviathans are creatures, not ships, and pay when slain; the Warden heals when everyone leaves; lightning strikes the highest block; region-scaled prices and rewards; two story unlocks; the ending for everyone in the world; saves at version 2.
- [ ] **Step 6: Commit** "Test the campaign on two machines; update README and spec for stage 8".

---

## Playtest checklist

Build-log item s08-07: "Playtest stage 8: the plan's checklist". A person does this, not the executor.

1. **Fuel:** fly the starter ship from the first town to the nearest Gale Expanse town at full throttle. Does the fuel line make range feel real without being a chore? Is 4 units a crown right?
2. **Running dry:** run out in mid-air. Is it clear what happened? Is drifting at your float height, until you abandon ship or a friend's harpoon tows you, a fair consequence?
3. **The Stormwall in the starter ship:** fly at it. Does it read as "my ship isn't strong enough", not as an invisible wall? Do the shipyard's top speed, range and ceiling explain why?
4. **The Wallbreaker:** find the Wallwright's notes, launch her and cross. Is a push of two or three minutes through fog and lightning tense in a good way? Is there fuel enough for the crossing, and for the way home?
5. **Over the top:** build a lift-stone ship and climb over. Is finding the height, and getting back down to a dock, a fair puzzle?
6. **Storms:** fly through a Gale Expanse storm. Do the strikes, fires, rolling deck and fog feel like weather? Too much or too little?
7. **Leviathans:** let a curious one pace you. Does it feel alive? Shoot one: is the fight fair, are its rams frightening, and is 300 crowns worth it?
8. **Gunners:** do hired gunners help against an angry leviathan, and do they leave the curious ones alone?
9. **The Warden:** does it feel like a finale? Is 6,000 hit points right for one ship? For two? Is its lightning fair?
10. **Logs:** find a few. Are the spots findable without markers? Does the story hang together? Is the log book easy to use?
11. **The ending:** does reaching the heart feel earned? In co-op, does your friend see it too? Does flying on afterwards feel right?
12. **Difficulty:** from the Calm Reaches in to the Eye, does each region feel harder, and pay better, than the last?
13. **Frame rate:** inside a storm, with leviathans and then the Warden in view, on the Radeon 680M.
14. **Old saves:** continue a stage 7 save. Are the ships fuelled and nothing lost?

---

## Changes during execution and after the final review
