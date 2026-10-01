# Stage 7: Towns and Progression Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Towns become places to do business. Every player has a purse of crowns. Ships carry cargo crates in their bays, and the crates weigh the ship down where they're stowed. Each town's market buys and sells goods at its own prices, so trade routes pay. A contract board offers deliveries, bounties, salvage and scouting. Hired hands staff your ship: gunners fire at pirates, repairers walk the decks putting out fires and mending, and engineers drive the engine harder. Alloy plates and lift stones are unlocked with money at towns further in. Launching a ship costs her parts, less what your old ship is worth. Spares cost money, a lost ship is insured for half her worth, and a stranded captain can abandon ship. The world saves to slots, autosaves, and falls back to an older save when one is broken.

**Architecture:**
- **The economy is data.** `Economy` (static, no nodes, like `Damage`) holds every price and rule: goods and each town's prices, part costs, what a ship is worth, launch prices, unlocks, hiring fees, insurance, and drawing contracts. Its tests need no world.
- **The server keeps the books.** `Ledger` (a node, `World/Ledger`, beside `World/Sync`) keeps every player's account by name: money, unlocks, contracts and insurance. Clients only ask. It checks each ask against where the asker last said they were, rate-limits asks, and sends each player their own account. It's a second RPC node because `WorldSync` is already 1,400 lines; ship state (cargo, hands, launches) stays in `WorldSync`.
- **Cargo is part of the grid.** `ShipGrid.cargo` maps a cargo bay's cell to the crate in it, `{good, owner}`. A crate adds `Tuning.CRATE_MASS` to its cell in `mass_properties`, so weight and balance follow the crates. A destroyed bay loses its crate, and a piece that breaks away takes its crates with it.
- **Hands are server nodes on ships.** `Ship.hands` lists a ship's hired crew on every machine, and clients draw them as avatars. On the server each gunner and repairer has a `CrewHand` brain, the way pirates have a `PirateCaptain`. Gunners fire through `PirateCaptain.fire_at`, the captain's own leading code. Repairers mend through `WorldSync.mend`, the same server path a player's repair takes. Engineers have no brain: a ship with one drives her propellers harder.
- **Saves are files of plain JSON.** `SaveGame` (static) writes and reads `world.json`, `ships.json` and `player.json`, checks them as untrusted input, rotates autosaves and falls back from a broken save. The World captures and restores itself through it. Ships of captains who aren't here wait in the save as records until their captain comes back.

**Tech Stack:** Godot 4.7.2 (standard build, `~/.local/bin/godot`), statically typed GDScript, Jolt, ENet through SceneMultiplayer, `JSON`, `FileAccess` and `DirAccess`, `Image` PNG and `Marshalls` base64 (the map's exploration in a save), `RandomNumberGenerator`, and the existing headless test runner.

**Spec:** `docs/superpowers/specs/2026-09-29-skywright-design.md` (stage 7 in §5; economy and progression in §3.6; crew and stations in §3.4; the stage 6 hand-offs in §3.4 (spares), §3.5 (rebuilding, ammunition, loot) and §4.6 (launches); multiplayer saves in §3.8; persistence in §4.10; error handling in §7).

**Where:** branch `stage-7-towns-progression`, in the worktree `../game-stage-7`, branched from `stage-6-damage-combat`.

## Global Constraints

- Godot 4.7.2 standard build, and GDScript with static types everywhere. No addons or other dependencies. No external art: everything is generated in code (spec §3.9).
- The server is authoritative for money, cargo, contracts, unlocks, hands and saves. A client only asks. Everything a peer receives from another machine is checked, and so is everything read from a save file.
- Protocol version 6. Channel 0 is reliable for events, channel 1 unreliable-ordered for ship snapshots, channel 2 unreliable-ordered for crew and helm keys. Every economy event goes on channel 0.
- Money and progression are per player, keyed by player name. Names are unique on a roster (Task 3).
- Every number that decides how ships fly stays in `src/ship/tuning.gd` (a crate's mass and an engineer's boost included). Every price, fee, reward and unlock lives in `Economy`. Hand behaviour numbers live in `CrewHand`, autosave timing in the World, and save format numbers in `SaveGame`.
- Randomness on the server comes from `WorldSync.rng`, so tests can seed it. Prices come from the world seed alone.
- New messages are the exact strings in this plan. Money is shown as `%d crowns`.
- Tests use ports 20000–29999. `NetCase` worlds use `NetCase.SEED` with pirates off. `NetCase` sessions have no save slot, so they never autosave. Tests that save point `SaveGame.dir` at `user://test_saves_<random>` and delete it in `after_each`. No test touches `user://saves`.
- Deliberate shortcuts carry a `ponytail:` comment naming the ceiling and the upgrade path.
- Commit messages have no `Co-Authored-By` line or other trailers (user rule).

## Review Focus

1. **The server decides money** (a modified guest buying with no money, trading away from a dock, selling someone else's crates, spamming asks, taking a contract that's gone or a fourth one, hiring with no bunk, launching from a town they aren't at or without the money): it's refused, and no purse or hold changes. Tests: `test_the_server_ignores_junk_trades` (Task 4), `test_the_server_ignores_junk_contract_asks` (Task 5), `test_the_server_refuses_a_launch_it_shouldnt_make` (Task 6), `test_the_server_ignores_junk_hiring` (Task 8).
2. **Cargo weighs where it's stowed** (crates fore and aft, a bay shot away, a bow broken off with crates in it, junk cargo from a modified host): mass and balance follow the crates on every machine. Tests: `test_crates_weigh_the_ship_down_where_they_are_stowed`, `test_a_destroyed_bay_loses_its_crate`, `test_crates_go_with_a_piece_that_breaks_away`, `test_a_junk_cargo_list_is_refused` (Task 2).
3. **Launch prices** (relaunching a damaged ship, a bigger design, a design with locked parts, a lost or abandoned ship's insurance, crates that don't fit the new ship): the price is right, and money moves once. Tests: `test_launch_costs_the_parts_less_her_trade_in` (Task 1), `test_launching_charges_the_difference`, `test_a_design_with_locked_parts_cant_launch`, `test_a_lost_ship_is_insured_for_half`, `test_crates_move_to_the_new_ship` (Task 6), `test_an_abandoned_ship_is_insured` (Task 7).
4. **Saves keep everything and survive damage** (a full round trip, a broken file, a newer version, three autosaves rotating, a guest who's away when the host saves): loading gives back the same world, and a broken save falls back to an older one and says so. Tests: `test_a_save_round_trips`, `test_saves_are_checked`, `test_a_broken_save_falls_back_to_the_previous_autosave`, `test_autosaves_keep_the_last_three`, `test_a_solo_game_saves_and_loads`, `test_a_leavers_ship_waits_for_them` (Task 9), `test_a_hosted_game_saves_and_loads_with_its_guest` (Task 11).
5. **Hands at work** (a gunner with a pirate abeam, astern, or a friendly ship abeam; a repairer facing fire and damage, with and without spares; an engineer's boost; a hand's ship lost or replaced): hands do their job and nothing else. Tests: `test_a_gunner_fires_at_pirates_abeam`, `test_a_repairer_puts_out_fires_then_mends`, `test_an_engineer_makes_her_faster`, `test_hands_go_down_with_their_ship`, `test_hands_move_to_the_ship_that_replaces_theirs` (Task 8).

---

## What prototyping settled before this plan

| Question | Answer |
|---|---|
| Where can the starter ship carry cargo and crew? | Bays replacing keel frames make her lighter, and bunks in the stern cabin made her bow-up by 0.26–0.35°, outside the 0.1° her tests allow. Four cargo bays in the main deck at `(±1, 0, −2)` and `(±1, 0, 4)` (deck planks, +10 kg each) and two bunks in the keel at `(0, −1, −3)` and `(0, −1, 3)` (frames, −20 kg each) leave her mass at 9,566 kg, her blocks at 301, her float at 882.5 m and her trim at 0.000° bow down, with no list. Every stage 2–6 balance test stands. Keel bunks have deck above them, so `respawn_spot` still skips them. |
| How much does a crate weigh her down? | At 100 kg a crate, four crates make her float at 780 m instead of 882 m. She holds 880 m at trim 1.04, within the 1.1 limit. Two crates in the fore bays put her 0.51° bow down; two in the port bays make her list 0.17° to port. |
| What does a ship cost? | At the part costs in Task 1, the starter ship's parts cost 1,150 crowns, plus 200 for a full load of 40 spares: 1,350. The pirate ship's parts cost 1,250. |
| How big and slow is a save? | A 4,000-block ship's record (blocks with hit points, plus her blueprint) is 173 KB of JSON: 14 ms to write as text, and 16 ms to parse and check through `ShipGrid.read_blocks`. The starter ship's is 14 KB and 1 ms. Eight full-size ships would stall an autosave for about 240 ms on the main thread (ponytail in `SaveGame`). |
| Saving the map | A part-explored 128 × 128 `FORMAT_L8` exploration image is 138 bytes as PNG, or 184 as base64. It reloads as the same size and format. |
| JSON numbers | `7000.123456789` round-trips exactly through `JSON.stringify` and `JSON.parse_string`. JSON makes every number a float, so readers take whole floats as ints, as `ShipGrid.read_blocks` already does. |
| A hired gunner | Over five runs, the captain's leading code fired your two cannons at a pirate circling your anchored ship in the Shattered Belt. It fired 0–17 shots in 3 minutes and hit in four runs, first at 86–124 s. In the two runs checked at the end, the pirate had lost its target in the wind and was drifting off. So the gunner test uses an anchored pirate abeam, and the playtest judges the circling fight. |
| An engineer's boost | This is arithmetic, not a prototype: drag grows with the square of speed, so 25% more thrust gives `√1.25` = 11.8% more top speed. |

## Where this stage departs from the spec

The spec is updated to match in Task 11.

| Spec | This stage | Why |
|---|---|---|
| §3.6: "Money and inventory" | Money is crowns in a purse per player. A player's inventory is the crates they own, wherever they're stowed, and crates are saved with the ships that carry them. Loot from salvage is crowns. | Cargo already has to be per crate for its weight. A second store of weightless items would duplicate it. |
| §3.6: part tiers "wood, then iron, then alloy" | Iron is unlocked from the start. Alloy plates unlock for 2,000 crowns at a town in the Shattered Belt or further in. Lift stones unlock for 4,000 at a town in the Gale Expanse or further in. A design with locked parts can't be launched, but it can be test-flown. | The starter ship's keel is iron ballast, and every captain must be able to relaunch her. |
| §3.6: "Blueprints and parts come from shipyards, wrecks and story progress" | Parts unlock with money at shipyards. Wrecks give crowns and spares. | Story progress is stage 8. One source keeps it simple. |
| §4.4: engines and trim above 1.0 burn fuel "once fuel exists (stage 7)"; fuel tanks hold 200 units | There's no fuel yet. Fuel tanks stay dead weight, trim is free, and engines never run dry. | Fuel matters when range gates the regions, which is stage 8. It moves there. |
| §3.4: an engine station; the engineer | Players have no engine station. A hired engineer tends an engine, and while that engine stands, the ship's propellers push `Tuning.ENGINE_BOOST` (25%) harder for each engineer, shared over her engines. | It's the smallest version of the role that a player feels (about 12% more speed) without fuel. The engine station comes with fuel. |
| §3.4: "AI crew hired in towns staff stations: gunner, engineer and repairer" | Hands are hired at a town's dock for a one-off fee, with no wages. Each needs a bunk. A gunner mans one cannon and fires only at pirates. A repairer has no station: he walks the ship in straight lines, putting out fires first and then mending with the ship's spares. An engineer tends one engine. Hands aren't hit by shots, aren't knocked down, never leave their ship, never steer, and never fire at another player's ship. They're lost with their ship, and they move to the ship that replaces theirs at a launch. | Enough to make crew worth hiring. Hands that can be hurt or that board belong with stage 9's boarding. |
| §3.4: spares "filled free at any town's dock until stage 7 prices them" | Spares cost 5 crowns each, bought at a town's dock. A new ship's price includes a full load of 40. | Stage 6 hand-off. |
| §3.5: a lost ship rebuilds "free until stage 7 sets a price" | A lost ship is insured for half of her cost. That credit counts as her trade-in at your next launch, so rebuilding her costs half. | Stage 6 hand-off. |
| §3.5: "Cannons never run out until ammunition becomes cargo (stage 7)" | Cannons still never run out. | Ammunition as cargo would need counts per cannon or ship, buying, a new way to lose mid-fight, and pirates with magazines. Spares already make fighting cost money, and the reload already limits fire. Revisit if fights feel free. |
| §3.5: "Loot beyond spares waits for inventory" | A world wreck gives 150 crowns and 12 spares, once. A broken-off wreck gives a spare per 10 blocks and a crown per block. | See inventory above. |
| §4.6: "The server trusts a client to be at the dock until launching costs money (stage 7)" | The server launches or test-flies a design only from the dock of a town the asker last said they were at. | Stage 5 and 6 hand-off. |
| §3.3: the stranded wreck (stage 6 deferral) | Abandon ship (in the pause menu, twice): your own ship is lost, insured like a sunk one, and you wake on the nearest town's quay. Losing a ship to the Roil also puts you on the quay at once, instead of making you fall through the Roil. | It fits insurance, and it needs no helm repairs. It also fixes stage 6's other deferral: the Roil's rescue message no longer hides the loss message. |
| §3.8: "The world is saved on the host's machine" | It is, with every player's account, keyed by name. A guest's ship waits in the save until they're back. Guests' maps (exploration) aren't saved, since the host never sees them. | Exploration lives on each machine (§4.7). |
| §4.10: saves, autosaves, falling back | As specified, in three slots (`1`, `2`, `3`, and `server` for a dedicated server). Autosaves go in `<slot>/auto-1` to `auto-3`. Loading takes the newest save in the slot that reads cleanly, and says so when that isn't the newest. Leaving the game also autosaves. Contract boards, pirates, wrecks and fires aren't saved. | Boards are drawn again, and the rest is short-lived. |
| (not in the spec) | Player names are unique on a roster: a second "Ann" becomes "Ann 2". | Progress is saved by name. |
| (not in the spec) | Prices are fixed for a world: trading doesn't move them. Contracts have no deadlines, and they pay at once when done, wherever you are. The map doesn't mark contract targets; each title says how far and which way from the town. | The smallest economy that has routes worth flying. Markers can come with the polish stage (stage 10). |
| (not in the spec) | The starter ship carries four cargo bays and two bunks. | You can trade and hire from the start. |

## Protocol (version 6)

| RPC | Change |
|---|---|
| `Session.PROTOCOL_VERSION` | 6 |
| Ship entries (in `_world` and `_ship_added`) | `[id, blocks, paint, transform, pilot, captain, test, blueprint, pirate, spares, cargo, hands]`. `cargo` is `ShipGrid.cargo_list()`: `[[x, y, z, good, owner], …]` (Task 2). `hands` is `[[id, name, role, post, at], …]` (Task 8). |
| `WorldSync._cargo(id, cargo)` | New, server → clients: every crate aboard ship `id`. |
| `WorldSync._hands(id, hands)` | New, server → clients: ship `id`'s hands, with where each stands. |
| `WorldSync._salvage_result(spares, money)` | Adds `money`, the crowns gained. |
| `WorldSync._abandon()` | New, client → server: abandon my own ship. |
| `Ledger._account(account)` | New, server → its owner: `{money, unlocks, contracts, insured}`. |
| `Ledger._say(text)` | New, server → one player: a message (a refusal, a sale, a contract done), at most 200 characters. |
| `Ledger._buy_spares()` | New, client → server: fill the ship I'm aboard at a dock. |
| `Ledger._trade(good, count)` | New, client → server: buy (`1`) or sell (`−1`) one crate of `good` at the dock I'm at. |
| `Ledger._ask_board()`, `Ledger._board(town, offers)` | New: ask for, and get, the contracts on the board of the town I'm at. |
| `Ledger._take(id)`, `Ledger._drop(id)` | New, client → server: take an offered contract, or drop one of mine. |
| `Ledger._unlock(part)` | New, client → server: buy an unlock at the town I'm at. |
| `Ledger._hire(role)`, `Ledger._dismiss(id)` | New, client → server: hire a hand onto the ship I'm aboard, or let one go. |
| `WorldSync._launch(blocks, paint, test, town)` | Unchanged arguments. The server now checks the town, the unlocks and the price, and refusals come back through `_say`. |

Budget: an account is under 1 KB, and a cargo list is about 20 bytes a crate. A walking repairer's position goes out twice a second. Everything else is sent when a player asks. The server takes at most one economy ask from each peer every `Ledger.ASK_EVERY` (0.1 s), so a guest can't make it flood everyone.

---

## File structure

| File | Responsibility |
|---|---|
| `src/economy/economy.gd` | `Economy`: goods and prices, part costs, ship value and launch price, unlocks, hands, insurance, contracts, account checks |
| `src/economy/ledger.gd` | `Ledger`: accounts by name, purses, spares, trade, contract boards and contracts, unlocks, launch charges, insurance, hiring; its RPCs |
| `src/ai/crew_hand.gd` | `CrewHand`: a gunner's or repairer's brain; reading hand lists |
| `src/save/save_game.gd` | `SaveGame`: slots, writing and reading the three files, autosave rotation, falling back, checking saves |
| `src/ui/town_panel.gd` | `TownPanel`: the town screen (T): market, contracts, crew |
| `src/ship/ship_grid.gd` | `cargo`, crates in `mass_properties`, `free_bays`, `cargo_list`, `read_cargo` |
| `src/ship/ship.gd` | `set_cargo`, `hands`, `set_hands`, `tended_engines`, `spot_near`, hand avatars, `at_town`, `beaten` |
| `src/ship/damage.gd` | A destroyed block loses its crate; `next_job` |
| `src/ship/tuning.gd` | `CRATE_MASS`, `ENGINE_BOOST` |
| `src/ship/starter_ship.gd` | Four cargo bays and two bunks |
| `src/ai/pirate_captain.gd` | `fire_at`, shared with gunners |
| `src/net/world_sync.gd` | Cargo, hands, `mend`, docking, salvage money, launch checks and charges, insurance, abandoning, ship records, ships waiting for their captains, the clock; protocol 6 |
| `src/net/session.gd` | Protocol 6, unique names, `save_slot`, `loaded` |
| `src/world/world.gd` | The Ledger, the town panel, routing messages, abandoning, the quay after a loss, capture and restore, autosaves, the pause menu's Save game and Abandon ship |
| `src/world/exploration.gd` | `to_text`, `read_text` |
| `src/builder/shipyard.gd` | Prices, locks and unlocking |
| `src/crew/player_controller.gd` | The spares prompt's text |
| `src/ui/hud.gd` | The purse, the hold line, the town prompt |
| `src/ui/main_menu.gd` | The saved games panel |
| `src/core/game.gd` | A dedicated server plays the `server` slot |
| `project.godot` | Action `town` (T) |
| `tests/test_economy.gd`, `test_cargo.gd`, `test_ledger.gd`, `test_markets.gd`, `test_contracts.gd`, `test_unlocks.gd`, `test_abandon.gd`, `test_hands.gd`, `test_save_game.gd`, `test_saves.gd`, `test_save_menu.gd`, `test_economy_net.gd` | New tests |
| `README.md`, spec | Stage 7 status, the economy, saves, controls |

---

### Task 1: The economy's rules

Build-log item s07-07: "Tests: save round trip and economy calculations" (the economy half).

**Files:**
- Create: `src/economy/economy.gd`, `tests/test_economy.gd`

**Interfaces:**
- Consumes: `WorldGen` (towns, wrecks, landmarks, `Region`), `Sites.wreck_center`, `ShipGrid`, `Tuning.BLOCKS`, `Blocks.INFO`, `Hud.bearing`.
- Produces (`class_name Economy`, all static, no nodes):
  - `const STARTING_MONEY := 1500`.
  - `const GOODS := {"grain": {"name": "Grain", "price": 20}, "timber": {"name": "Timber", "price": 32}, "cloth": {"name": "Cloth", "price": 48}, "tools": {"name": "Tools", "price": 70}, "spirits": {"name": "Spirits", "price": 95}, "mail": {"name": "Mail", "price": 0}}`. A price of 0 means it's never traded: mail is a contract's crates.
  - `const MAKES := 0.6`, `const WANTS := 1.5`, `const PRICE_NOISE := 0.1`, `const SELL_SHARE := 0.85`.
  - `const PART_COST := {"frame": 4, "deck": 3, "iron": 12, "alloy": 30, "balloon": 2, "lift_stone": 150, "engine": 80, "propeller": 20, "rudder": 10, "sail": 6, "fuel_tank": 20, "ballast_tank": 15, "helm": 40, "cannon": 60, "cargo_bay": 10, "bunk": 8, "ladder": 2}`.
  - `const SPARE_PRICE := 5`, `const INSURANCE := 0.5`.
  - `const UNLOCKS := {"alloy": {"price": 2000, "region": WorldGen.Region.SHATTERED}, "lift_stone": {"price": 4000, "region": WorldGen.Region.GALE}}`.
  - `const HANDS := {"gunner": {"name": "gunner", "fee": 150}, "repairer": {"name": "repairer", "fee": 120}, "engineer": {"name": "engineer", "fee": 200}}`, `const HAND_NAMES := ["Fenn", "Marta", "Osric", "Ilse", "Bram", "Tove", "Cass", "Joss", "Wren", "Edda", "Rook", "Sable"]`.
  - `const SALVAGE_MONEY := 150`, `const SCRAP_MONEY := 1`.
  - `const MAX_CONTRACTS := 3`, `const BOARD_SIZE := 3`, `const NEARBY := 3`, `const KINDS := ["delivery", "bounty", "salvage", "scout"]`.
  - `const DELIVERY_BASE := 30`, `const DELIVERY_PER_KM := 40` (a crate), `const BOUNTY_PAY := 250` (a pirate), `const SALVAGE_BASE := 100`, `const SALVAGE_PER_KM := 50`, `const SCOUT_BASE := 80`, `const SCOUT_PER_KM := 50`, `const SCOUT_REACH := 400.0`, `const BOUNTY_REACH := 1500.0`.
  - `static func new_account() -> Dictionary`: `{"money": STARTING_MONEY, "unlocks": [], "contracts": [], "insured": 0}`.
  - `static func trade_of(gen: WorldGen, town: int) -> Dictionary`: `{"makes": Array[String], "wants": Array[String]}`.
  - `static func price(gen: WorldGen, town: int, good: String) -> int` (what a crate costs there) and `static func sell_price(gen: WorldGen, town: int, good: String) -> int` (what the market pays).
  - `static func cost(grid: ShipGrid) -> int`, `static func value(grid: ShipGrid, spares: int) -> int`, `static func launch_cost(design: ShipGrid, trade_in: int) -> int`.
  - `static func locked(grid: ShipGrid, unlocks: Array) -> Array[String]`, `static func unlockable_at(part: String, region: int) -> bool`.
  - `static func draw_contract(gen: WorldGen, town: int, salvaged: Dictionary, rng: RandomNumberGenerator) -> Dictionary`.
  - `static func bearing_word(from: Vector3, to: Vector3) -> String`.
  - `static func read_account(data: Variant) -> Variant` and `static func read_contract(data: Variant) -> Variant` (a clean Dictionary, or null).

Rules:
- **What a town trades:** the traded goods (price over 0) in `GOODS` order, shuffled with a `RandomNumberGenerator` seeded `hash([gen.world_seed, town, "market"])` (Fisher–Yates from the end, `randi_range(0, i)`). The first two are what it makes, and the next two what it wants.
- **Prices:** `price = maxi(1, roundi(base × factor × (1 + noise)))`. `factor` is `MAKES` for a good the town makes, `WANTS` for one it wants, and 1 otherwise. `noise` is `randf_range(−PRICE_NOISE, PRICE_NOISE)` from an rng seeded `hash([gen.world_seed, town, good, "price"])`. `sell_price = roundi(price × SELL_SHARE)`. Both are 0 for mail. So a crate bought where it's made (at most 0.66 of base) sells where it's wanted for at least 1.15 of base.
- **A ship's cost** is the sum of `PART_COST` over her blocks, plus `Damage.SPARES_MAX × SPARE_PRICE` (a full load of spares). **Her value** is `roundi(Σ PART_COST × hp / full + spares × SPARE_PRICE)`. **A launch costs** `maxi(0, cost(design) − trade_in)`: scrapping a bigger ship for a smaller one pays nothing back.
- **Locked parts** are the `UNLOCKS` keys the grid uses and `unlocks` lacks, sorted. `unlockable_at(part, region)` is true when `UNLOCKS` has the part and `region <= UNLOCKS[part]["region"]` (regions count inward from the Eye, 0).
- **Drawing a contract:** `kind = KINDS[rng.randi_range(0, 3)]`. A salvage contract with every wreck salvaged becomes a delivery. `km` is the distance from the town's dock to the target, over 1,000. Targets are chosen with `rng.randi_range(0, mini(NEARBY, n) − 1)` from the `n` candidates sorted nearest first (ties by index):
  - **delivery:** to another town; `count = rng.randi_range(1, 3)` crates; `reward = count × (DELIVERY_BASE + roundi(DELIVERY_PER_KM × km))`; title `Carry a crate of mail to %s` or `Carry %d crates of mail to %s`.
  - **bounty:** `count = 1 + (1 if rng.randf() < 0.3 else 0)`; `reward = count × BOUNTY_PAY`; `target = −1`; title `Sink a pirate` or `Sink %d pirates`.
  - **salvage:** a world wreck not in `salvaged` (by `Sites.wreck_center`); `reward = SALVAGE_BASE + roundi(SALVAGE_PER_KM × km)`; title `Salvage the wreck %.1f km %s of %s` (km, `bearing_word`, the town's name).
  - **scout:** a landmark (by its `at`); `reward = SCOUT_BASE + roundi(SCOUT_PER_KM × km)`; title `Scout %s, %.1f km %s of %s` (the landmark's name, km, bearing, town).
  - It returns `{"kind", "title", "reward", "target", "count", "done": 0}`. The Ledger adds `"id"`. `count` is 1 for salvage and scouting.
- **`bearing_word`** is `["N", "NE", "E", "SE", "S", "SW", "W", "NW"][roundi(Hud.bearing(to − from) / 45.0) % 8]`.
- **Checking accounts** (from the network and from saves): a Dictionary with `money` and `insured` whole and 0 or more (ints, or whole floats from JSON), `unlocks` an Array of distinct `UNLOCKS` keys, and `contracts` an Array of at most `MAX_CONTRACTS` contracts. A contract has `id` 1 or more, `kind` in `KINDS`, `title` a String of at most 120 characters, `reward` 0 to 100,000, `target` −1 or more, `count` 1 to 64, and `done` 0 to `count`. Anything else gives null. The clean copy has ints, not floats.

- [ ] **Step 1: Write the failing tests** (`tests/test_economy.gd`, plain `TestCase`; `gen := WorldGen.new(NetCase.SEED)`):
  - `test_prices_come_from_the_world`: two `WorldGen`s from one seed give the same `price` and `sell_price` for every town and good. A world from seed 1 differs in at least one.
  - `test_each_town_makes_two_goods_and_wants_two`: for every town, `makes` and `wants` have two goods each, share none, and never include mail. Each price is within `noise` of `base × factor` (for example a made good is between `roundi(0.54 × base)` and `roundi(0.66 × base)`).
  - `test_a_market_buys_for_less_than_it_sells`: `sell_price < price` for every town and traded good. Mail is 0 both ways.
  - `test_some_route_pays`: for each good town 0 makes, some other town's `sell_price` beats town 0's `price`.
  - `test_a_ship_costs_her_parts_and_a_full_load_of_spares`: a one-frame grid costs 204. A grid with one block of every type costs the sum of `PART_COST` plus 200. (The starter ship's 1,350 is checked in Task 2, which gives her the bays and bunks it includes.)
  - `test_a_damaged_ship_is_worth_less`: the starter ship with 40 spares is worth exactly her `cost`. With a frame at 50 hit points she's worth 2 less. With 30 spares as well, 52 less. With a cannon removed as well, 112 less.
  - `test_launch_costs_the_parts_less_her_trade_in`: relaunching the whole starter ship against her own value costs 0. Against the damaged one (52 less) it costs 52. The starter ship with ten iron plates added, against a whole starter ship, costs 120. The `skiff` from `test_launch.gd` (fewer balloons) costs 0, not less. With no trade-in it costs her whole `cost`, and against `roundi(INSURANCE × cost)` it costs the rest.
  - `test_alloy_and_lift_stones_are_locked`: `locked(StarterShip.build(), [])` is empty. A grid with an alloy plate and a lift stone gives `["alloy", "lift_stone"]`. With `["alloy"]` unlocked it gives `["lift_stone"]`.
  - `test_unlocks_are_sold_further_in`: alloy isn't sold in the Calm Reaches, but is in the Shattered Belt and the Gale Expanse. Lift stones aren't sold in the Shattered Belt, but are in the Gale Expanse. Iron is never sold, because it's never locked.
  - `test_contracts_are_drawn_from_the_world`: with rng seed 1, 200 draws at town 0 include every kind. Every delivery goes to one of the three towns nearest town 0, with 1–3 crates and the reward by the formula. Every salvage names one of the three nearest wrecks not in `salvaged`; with the nearest marked salvaged, it's never chosen. Every scouting names one of the three nearest landmarks. Bounties ask for 1 or 2 pirates at 250 each. Titles read as above (for example `Carry 2 crates of mail to %s` with the town's name). The same seed gives the same 200.
  - `test_accounts_and_contracts_are_checked`: `new_account()` passes, and so does the same account with whole floats (`1500.0`). Each of these gives null: money −1, `"5"` or 1.5; an unknown unlock or the same unlock twice; four contracts; a contract of kind `"heist"`, with a 121-character title, `done` over `count`, or a missing `id`.
  - `test_bearing_words`: from the origin, `(0, 0, −100)` is `N`, `(100, 0, 0)` is `E`, and `(−100, 0, 100)` is `SW`.
- [ ] **Step 2: Run `./run_tests.sh economy`.** Expected: the tests fail (`Economy` doesn't exist).
- [ ] **Step 3: Implement** `Economy`.
- [ ] **Step 4: Run the whole suite.** Expected: everything passes.
- [ ] **Step 5: Commit** "Add the economy's rules: prices, part costs, launch prices, unlocks and contracts".

### Task 2: Cargo crates

Build-log item s07-01: "Money, inventory, and cargo crates that weigh the ship down where they're stowed" (the crates).

**Files:**
- Create: `tests/test_cargo.gd`
- Modify: `src/ship/ship_grid.gd`, `src/ship/ship.gd`, `src/ship/damage.gd`, `src/ship/tuning.gd`, `src/ship/starter_ship.gd`, `src/net/world_sync.gd`, `src/net/session.gd`, `src/ui/hud.gd`, `tests/test_fleet.gd`, `tests/test_session.gd`, `tests/test_world.gd`, `tests/test_damage.gd`

**Interfaces:**
- Consumes: `Economy.GOODS` (Task 1).
- Produces:
  - `Tuning.CRATE_MASS := 100.0` (kg a crate adds to its bay).
  - `ShipGrid`: `var cargo: Dictionary = {}` (a cargo bay's cell → `{"good": String, "owner": String}`); `func free_bays() -> Array[Vector3i]` (bays with no crate, sorted); `func cargo_list() -> Array` (`[[x, y, z, good, owner], …]` by cell); `static func read_cargo(data: Variant, grid: ShipGrid) -> Variant` (a cargo Dictionary, or null).
  - `Ship.set_cargo(cargo: Dictionary) -> void`: sets `grid.cargo` and recomputes mass, centre of mass and inertia now, without a rebuild.
  - `WorldSync.set_cargo(ship: Ship, cargo: Dictionary) -> void` (server: sets it and tells everyone in the world); RPC `_cargo(id, cargo)`; entries of 11 fields, `cargo` last; `Session.PROTOCOL_VERSION := 6`.
  - `StarterShip`: cargo bays at `(±1, 0, −2)` and `(±1, 0, 4)` in place of deck planks, and bunks at `(0, −1, −3)` and `(0, −1, 3)` in place of keel frames.
  - `Hud.readout` gains `Hold      %d/%d crates` (crates aboard, cargo bays) after the spares line.

Rules:
- `mass_properties` counts a crate as `Tuning.CRATE_MASS` at its bay's cell. `ShipStats` and the shipyard never see cargo, because designs have none.
- `copy()` copies cargo. `whole()` drops it, so a blueprint never carries crates.
- `Damage.apply` erasing a block erases its crate. `Ship.take_cells` moves the crates in those cells to the piece.
- `read_cargo` takes at most `MAX_BLOCKS` entries. Each is `[x, y, z, good, owner]` with whole numbers (or whole floats), a cell that's a cargo bay in `grid` and isn't listed twice, a `GOODS` key, and an owner that's a String of 1 to 24 characters. Anything else gives null.
- The server sends `_cargo` whenever cargo changes through `set_cargo`. Splits and destroyed bays need nothing new: every machine applies the same block changes, so it drops the same crates. Clients apply `_cargo` through `read_cargo` and ignore junk without a warning.
- `_add_entry` checks the 11th field with `read_cargo` against the entry's grid, and leaves out the ship as before when it's junk.

- [ ] **Step 1: Write the failing tests** (`tests/test_cargo.gd`, `extends NetCase`; plain ships in the tree unless marked network):
  - `test_the_starter_ship_has_four_bays_and_two_bunks_and_still_floats_level`: four `cargo_bay` cells and two `bunk` cells where listed. `ShipStats.of(StarterShip.build(), 880)` floats at 882.5 ± 1 m, with `bow_down` under 0.1° and no list. Her mass is 9,566 kg (±1), she has 301 blocks, and `Economy.cost` of her is 1,350.
  - `test_crates_weigh_the_ship_down_where_they_are_stowed`: four crates make her 400 kg heavier, and `trim_to_float_at(877)` goes up by a factor of 1.0418 ± 0.001. In a calm-air flight test against an empty twin 200 m away: with crates in the two fore bays, after 60 s she's more than 0.3° bow down and the twin less than 0.15°. With crates in the two port bays, she lists to port by more than 0.1° and the twin by less than 0.05°.
  - `test_a_destroyed_bay_loses_its_crate`: a crate at `(1, 0, −2)`; `damage({(1, 0, −2): 0})` drops the crate, and a frame later her mass is 150 kg less.
  - `test_crates_go_with_a_piece_that_breaks_away`: in a solo world, crates in all four bays, then `damage_ship` sets every cell at z 0 to 0. The bow wreck's `grid.cargo` holds the two fore crates, the ship keeps the two aft ones, and each body's mass matches its `grid.mass_properties()`.
  - Network: `test_cargo_reaches_the_guest`: after `sail_together()`, the host's `set_cargo` puts two crates aboard. Within 1 s the guest's copy has the same `cargo_list()`, and a late joiner's copy has it in its entry.
  - Network: `test_a_junk_cargo_list_is_refused`: the guest's `sync._cargo` called with an unknown ship, a crate on a deck plank, a good `"gold"`, an owner of 25 characters, a cell listed twice, and a `String`: nothing changes and no error is logged.
  - `tests/test_damage.gd`: `apply` erasing a bay erases its crate; healing it doesn't.
  - `tests/test_fleet.gd`: the junk-entry test builds 11-field entries, and adds one with a crate on a deck plank.
  - `tests/test_session.gd`: the protocol version is 6.
  - `tests/test_world.gd`: `test_the_helm_readout` expects `Spares    40/40\nHold      0/4 crates`.
- [ ] **Step 2: Run `./run_tests.sh cargo`.** Expected: fail.
- [ ] **Step 3: Implement** cargo in the grid and ship, the starter ship's bays and bunks, `set_cargo`, `_cargo`, the entries, protocol 6 and the hold line.
- [ ] **Step 4: Run the whole suite.** Expected: pass. The stage 2–6 flight, balance and damage tests stand unchanged.
- [ ] **Step 5: Commit** "Stow cargo crates in bays, where their weight counts; the starter ship carries four".

### Task 3: Purses

Build-log item s07-01: "Money, inventory, and cargo crates that weigh the ship down where they're stowed" (the money).

**Files:**
- Create: `src/economy/ledger.gd`, `tests/test_ledger.gd`
- Modify: `src/net/world_sync.gd`, `src/net/session.gd`, `src/world/world.gd`, `src/ui/hud.gd`, `src/crew/player_controller.gd`, `tests/test_session.gd`, `tests/test_salvage.gd`, `tests/test_repairs.gd`

**Interfaces:**
- Consumes: `Economy` (Task 1).
- Produces:
  - `class_name Ledger extends Node` (named `Ledger`, added to the World after its Sync):
    - `signal account_changed` (this machine's player's account changed), `signal told(text: String)` (a message for this machine's player).
    - `const ASK_EVERY := 0.1`, `const MAX_TEXT := 200`.
    - `var sync: WorldSync`, `var accounts: Dictionary = {}` (server: player name → account), `var mine: Dictionary = Economy.new_account()` (this machine's player's account, as the server last sent it).
    - `func _init(world_sync: WorldSync)`.
    - `func account_of(peer: int) -> Dictionary` (server: by name, made fresh the first time), `func pay(peer: int, amount: int) -> void` (server: adds, or charges when negative, never below 0, then sends the account), `func send_account(peer: int) -> void`, `func tell(peer: int, text: String) -> void`.
    - `func buy_spares() -> void` (this machine's player).
    - RPCs `_account(account)`, `_say(text)`, `_buy_spares()`.
  - `WorldSync`: `var ledger: Ledger` (set by the World); `func name_of(peer: int) -> String` (from the roster, or as remembered after they left); `func aboard(peer: int) -> Ship` (the ship they're aboard, or null); `func world_position_of(peer: int) -> Variant` (was `_world_position_of`); `func in_world(peer: int) -> bool` (this machine's player, or a peer whose world has loaded); `func town_at(p: Vector3) -> int` (`World.town_at` now calls it); `signal salvage_result(spares: int, money: int)` and RPC `_salvage_result(spares, money)`.
  - `Session.unique_name(raw: String, taken: Array) -> String` (static).
  - `Hud`: `var ledger: Ledger` (set by the World); `var _purse: Label`, under the crew line.

Rules:
- **Accounts** are keyed by `sync.name_of(peer)`. A name seen for the first time gets `Economy.new_account()`. A guest who leaves and comes back under the same name finds their purse as they left it.
- **Unique names:** the host gives a joiner `unique_name(cleaned, taken)`, where `taken` is the names already on the roster or joining. A taken name gets ` 2`, ` 3` and so on, cutting the name so the whole stays within 24 characters.
- **Sending accounts:** `send_account(peer)` sets `mine` and emits `account_changed` for this machine's player, and otherwise sends `_account` to that peer if they're in the world. The server sends it when a peer enters the world, on every change, and to its own player when the Ledger is ready. Clients take `_account` through `Economy.read_account` and ignore junk.
- **Asks:** every client → server Ledger RPC passes `_may_ask(peer)` first. The peer must be in the world and must not have asked within `ASK_EVERY`. More asks are ignored without an answer. The server's own player isn't limited. Tests that send a guest's asks one after another wait `ASK_EVERY` between them.
- **Messages:** `tell` emits `told` for this machine's player, and otherwise sends `_say`. Clients drop text that isn't a String or is longer than `MAX_TEXT`. The World shows `told` in the open shipyard's note, else in the town panel's note (Task 4), else as a HUD message.
- **Spares cost money:** `_wear` no longer fills spares at docks. `buy_spares` (server: `_buy_spares_for(peer)`) needs the asker aboard a ship that isn't a test flight or a pirate, at a town's dock (`town_at(ship.global_position) >= 0`). It buys `mini(SPARES_MAX − spares, money / SPARE_PRICE)` spares and tells everyone the ship's `_spares`. The messages are `Bought %d spares for %d crowns.`, `Her spares are full.`, `You can't afford a spare (%d crowns).` and `Buy spares at a town's dock, aboard a ship.`
- **Salvage pays crowns:** a world wreck gives `SALVAGE_MONEY` to the salvager, plus up to 12 spares to the ship (as many as fit). It's stripped either way. A wreck ship gives `ceili(blocks / 10.0)` spares (as many as fit) plus `SCRAP_MONEY` a block, and is broken up. The HUD says `Salvaged %d crowns and %d spares.` when spares came, else `Salvaged %d crowns.`, and `Nothing left to salvage here.` for a stripped wreck. The old `No room for more spares.` is gone.
- **The repair prompt** with no spares reads `No spares left: buy more at a town's dock`.
- **The HUD purse** reads `%d crowns` (`ledger.mine["money"]`).

- [ ] **Step 1: Write the failing tests** (`tests/test_ledger.gd`, `extends NetCase`; a solo world at the dock unless marked network):
  - `test_you_start_with_a_purse`: `world.ledger.mine["money"]` is 1,500, and the HUD's purse reads `1500 crowns`.
  - `test_spares_are_bought_at_a_dock`: spares 5 at slipway 0; 1.5 s later they're still 5 (no free refill). `ledger.buy_spares()`: 40 spares, 1,325 crowns, and `Bought 35 spares for 175 crowns.` Moved to `open_sky` with 5 spares: `Buy spares at a town's dock, aboard a ship.`, and nothing changes.
  - `test_you_buy_what_you_can_afford`: 50 crowns and 5 spares: 15 spares and 0 crowns. Then, at 0 crowns: `You can't afford a spare (5 crowns).`
  - `test_salvage_pays_crowns`: your ship 3 km from every dock with 40 spares, you at wreck site 0: E gives 150 crowns, `Salvaged 150 crowns.`, and the site is stripped. A broken-off wreck of 30 blocks, with 10 spares aboard: 3 spares, 30 crowns, and `Salvaged 30 crowns and 3 spares.`
  - Network: `test_each_player_has_their_own_purse`: after `sail_together()`, the guest's `mine` shows 1,500. The host's `ledger.pay(guest, 100)` makes it 1,600 within 1 s, and the host's own stays 1,500.
  - Network: `test_a_purse_is_kept_by_name`: the guest is paid 100 and leaves. A new client joining as `Guest` has 1,600; one joining as `Cy` has 1,500.
  - Network: `test_asks_are_rate_limited`: the guest's `_buy_spares` sent 20 times in one frame, with the host's ship at the dock and 5 spares, is answered once.
  - `tests/test_session.gd`: `test_two_players_with_one_name_get_two_names`: the host is `Ann` and a guest joins as `Ann`: the roster is `Ann` and `Ann 2`. `unique_name` keeps a 24-character name within 24 characters.
  - `tests/test_salvage.gd`: messages as above. `test_no_room_for_more_spares` becomes `test_a_full_ship_still_takes_the_crowns`.
  - `tests/test_repairs.gd`: `test_spares_refill_at_a_dock` is removed (the new test covers it), and `test_out_of_spares` expects the new prompt.
- [ ] **Step 2: Run `./run_tests.sh ledger`.** Expected: fail.
- [ ] **Step 3: Implement** the Ledger core, unique names, the purse, buying spares and salvage money.
- [ ] **Step 4: Run the whole suite.** Expected: pass.
- [ ] **Step 5: Commit** "Give every player a purse; spares cost money and salvage pays crowns".

### Task 4: Markets

Build-log item s07-02: "Markets with prices that differ between towns".

**Files:**
- Create: `src/ui/town_panel.gd`, `tests/test_markets.gd`
- Modify: `src/economy/ledger.gd`, `src/world/world.gd`, `src/ui/hud.gd`, `project.godot`, `tests/test_project.gd`, `tests/test_shipyard.gd`

**Interfaces:**
- Consumes: `Economy.price`, `sell_price`, `GOODS` (Task 1); `WorldSync.set_cargo`, `ShipGrid.free_bays` (Task 2); the Ledger core (Task 3).
- Produces:
  - `Ledger.trade(good: String, count: int) -> void` (this machine's player); RPC `_trade(good, count)`.
  - `class_name TownPanel extends CanvasLayer`: `signal close_requested`; `func _init(world_ledger: Ledger, town_index: int, ship_aboard: Callable)` (`ship_aboard` returns the ship you're aboard, or null); `func show_section(section: String) -> void` (`"market"`, `"contracts"` or `"crew"`); `func say(text: String) -> void`; `func refresh() -> void`; `var market_rows: Dictionary` (good → its Label, for tests).
  - `World`: `var town_panel: TownPanel`; `func open_town() -> void`; `func close_town() -> void`.
  - Action `town` on T (shared with the shipyard's tip key, as M is shared).
  - The HUD's dock prompt becomes `B   Shipyard   T   Town`.

Rules:
- **Trading** (server, `_trade_for(peer, good, count)`): `count` must be 1 (buy) or −1 (sell), and `good` a traded `GOODS` key. The asker must be aboard a ship that isn't a test flight or a pirate, at a town's dock. That town is the market.
  - **Buying** needs a free bay and `price` crowns. The crate `{good, owner: the asker's name}` goes in the first free bay, and the money comes out of their purse.
  - **Selling** takes the asker's own crate of that good from the bay first in cell order, and pays `sell_price`.
  - Every change goes out through `set_cargo` and the asker's account. Refusals: `Trade at a town's dock, aboard a ship.`, `Her hold is full.`, `You can't afford %s (%d crowns).` (the good's name), `You have no %s aboard.`, and `Mail isn't for sale.` A sale says nothing; the panel shows it.
- **The town panel** opens with T at a town's dock (`town_at(player.world_position()) >= 0`), whether you're aboard or ashore, and not on a test flight or with the shipyard or pause menu open. Away from a dock, T says `The market is at the dock.`. T, Esc or Close shuts it. While it's open your controls stop and the mouse is free, as for the shipyard, but the world still draws.
- **The panel's layout** is in the UI theme. At the top: the town's name, `%d crowns`, a button per section and `Close (T)`, and a note line. Then the section's rows. This task builds the Market section; Tasks 5 and 8 add Contracts and Crew, each with its button.
  - **Market**, for each traded good: a monospace label `"%-8s buy %3d   sell %3d   aboard %d" % [name, price, sell price, your crates of it aboard]` with `Buy` and `Sell` buttons. Then `Spares    %d/%d   %d crowns each` with a `Fill` button, and `Hold      %d/%d crates`. When you're not aboard a ship at this dock: `Come aboard a ship at the dock to trade.`
- The panel rebuilds its rows only when what they show changes: it compares a summary of your account, the ship's cargo, spares and hands, and the board four times a second.

- [ ] **Step 1: Write the failing tests** (`tests/test_markets.gd`, `extends NetCase`; a solo world at the dock unless marked network; `move_to_town` as in `test_towns.gd`):
  - `test_t_opens_the_town_at_a_dock`: the prompt is `B   Shipyard   T   Town`. T opens a `TownPanel` titled with the starting town's name and turns off your controls. T closes it and gives them back. At `open_sky`, T opens nothing and says `The market is at the dock.`
  - `test_prices_differ_between_towns`: at town 0, each good's market row shows `Economy.price` and `sell_price` for town 0. At town 3, its own prices. At least one good's price differs between them.
  - `test_buying_a_crate_stows_it_and_charges_you`: buying grain puts `{"good": "grain", "owner": "Ann"}` at `(−1, 0, −2)` (the first free bay), takes its price from your purse, and adds 100 kg. The row reads `aboard 1`.
  - `test_selling_pays_you_and_frees_the_bay`: selling it pays `sell_price` and frees the bay. You end with less money than you started.
  - `test_a_full_hold_or_an_empty_purse_refuses`: after four crates, `Her hold is full.` With 10 crowns, buying spirits says `You can't afford Spirits (%d crowns).`. Selling tools you don't have says `You have no Tools aboard.`, and selling mail says `Mail isn't for sale.`. Nothing changes.
  - `test_you_cant_sell_someone_elses_crates`: a grain crate owned by `Bo`: selling grain says `You have no Grain aboard.`, and Bo's crate stays.
  - `test_the_panel_fills_your_spares`: with 10 spares, `Fill` makes 40 and the row reads `Spares    40/40   5 crowns each`.
  - Network: `test_a_guest_trades`: after `sail_together()` (both aboard the host's ship at the dock), the guest buys timber. The host's ship holds a timber crate owned by `Guest`, the guest's purse is down by its price, and the host's isn't. The guest's copy shows the crate within 1 s.
  - Network: `test_the_server_ignores_junk_trades`: the guest's `_trade` with good `"gold"`, `"mail"`, a count of 5, a count of `"1"`, a good of `7`; selling the host's crate; buying while ashore away from the dock; and buying when their purse is 0. None of these changes a purse or the hold. Afterwards one legal buy works.
  - `tests/test_project.gd`: `town` is T.
  - `tests/test_shipyard.gd`: the dock prompt is `B   Shipyard   T   Town`.
- [ ] **Step 2: Run `./run_tests.sh markets`.** Expected: fail.
- [ ] **Step 3: Implement** trading, the town panel with its market, T, and the prompt.
- [ ] **Step 4: Run the whole suite, then play by hand:** buy what Town 0 makes, fly it to a town that wants it, and sell it. Watch the helm readout's hold line and the trim the autopilot needs.
- [ ] **Step 5: Commit** "Open markets at every town's dock, with prices of their own".

### Task 5: Contracts

Build-log item s07-03: "Contract board: deliveries, bounties, salvage, scouting".

**Files:**
- Create: `tests/test_contracts.gd`
- Modify: `src/economy/ledger.gd`, `src/net/world_sync.gd`, `src/ship/ship.gd`, `src/ui/town_panel.gd`

**Interfaces:**
- Consumes: `Economy.draw_contract`, `read_contract`, the reward constants (Task 1); trading's checks (Task 4); salvage (stage 6).
- Produces:
  - `Ledger`: `signal board_changed(town: int)`; `var boards: Dictionary` (town → Array of offers: on the server the boards, on a client the ones it was sent); `func ask_board() -> void`, `func take_contract(id: int) -> void`, `func drop_contract(id: int) -> void` (this machine's player); server hooks `func on_docked(ship: Ship, town: int) -> void`, `func on_salvaged(peer: int, site: int) -> void`, `func pirate_beaten(at: Vector3) -> void`, `func check_scouts() -> void`; RPCs `_ask_board()`, `_board(town, offers)`, `_take(id)`, `_drop(id)`.
  - `WorldSync`: `signal docked(ship: Ship, town: int)` (server).
  - `Ship`: `var at_town := -1` (server: the town whose dock she's at, or −1), `var beaten := false` (server: a pirate already counted for bounties).

Rules:
- **Boards:** a town's board is drawn the first time someone asks: `BOARD_SIZE` offers from `Economy.draw_contract` with `sync.rng`, each given the next id (counting from 1). `ask_board` sends the asker the board of the town at whose dock they stand (`town_at(world_position_of(peer))`), as `_board(town, offers)`. Clients check each offer with `read_contract`. Boards aren't saved.
- **Taking** (`_take_for(peer, id)`): the asker must stand at the dock of the town whose board has that id, with fewer than `MAX_CONTRACTS` contracts. A delivery needs the asker aboard a ship there (not a test flight or pirate) with `count` free bays. Then:
  - `count` crates `{"good": "mail", "owner": name}` go into her free bays;
  - the contract (with `done` 0) goes into the asker's account;
  - a fresh offer replaces it on the board, and the asker gets the board;
  - the message is `Contract taken: %s.`
  - Refusals: `That contract is gone.`, `You have three contracts already.`, `Your hold has room for %d crates.`, and `Take contracts at a town's board.`
- **Dropping** (`_drop_for(peer, id)`) works anywhere. It removes the contract, and for a delivery up to `count` of the asker's mail crates from every ship. Message: `Contract dropped: %s.`
- **Completing** pays `reward` into the holder's account, removes the contract, and tells them `Contract done: %s. +%d crowns.`
  - **Deliveries** complete in `on_docked(ship, town)`: for each account with a delivery to `town`, if `ship` holds at least `count` of its owner's mail crates, those crates come off and it's done.
  - **Bounties:** `pirate_beaten(at)` adds 1 to `done` for each player on the roster within `BOUNTY_REACH` of `at` holding a bounty, and it's done at `count`.
  - **Salvage:** `on_salvaged(peer, site)` completes the salvager's salvage contract for that site.
  - **Scouting:** `check_scouts()` completes the scouting of each player within `SCOUT_REACH` of its landmark's `at`.
- **Docking** (server, in `_wear`): each ship that isn't a pirate, wreck or test flight has `at_town = town_at(global_position)` (others −1). A change to a town 0 or above emits `docked(ship, town)`. `_add` sets `at_town` at once on the server, so being launched at a dock doesn't count as docking. The Ledger connects to `docked`.
- **Beaten pirates** (server, in `_wear`): a pirate that's a wreck and not `beaten` is marked `beaten`, and `ledger.pirate_beaten(her position)` is called. `remove_ship` does the same for a pirate lost to the Roil that wasn't beaten. `_wear` calls `ledger.check_scouts()` once a second.
- **The Contracts section** of the town panel calls `ask_board()` when it opens. It shows each offer as `"%s   %d crowns" % [title, reward]` with `Take`. Under the caption `Your contracts` it shows each of yours with `Drop`, a bounty's as `"%s   %d crowns   %d/%d" % [title, reward, done, count]`.

- [ ] **Step 1: Write the failing tests** (`tests/test_contracts.gd`, `extends NetCase`; a solo world at the dock unless marked network; a test puts a known offer on a board with `ledger.boards[0] = [offer]` after `ask_board()`):
  - `test_a_board_offers_three_contracts`: `ask_board()`: the board of town 0 has three offers with ids, titles and rewards, and the panel's Contracts section lists all three with `Take`.
  - `test_taking_a_delivery_loads_its_mail`: a delivery of 2 crates to town 1 for 240 crowns: taking it puts two mail crates owned by `Ann` in `(−1, 0, −2)` and `(−1, 0, 4)`, puts the contract in `mine`, and shows a new offer in its place on the board.
  - `test_a_delivery_pays_at_its_town`: then the ship moved to town 1's slipway 0: within 1.5 s the mail is gone, the purse is 240 up, the HUD says `Contract done: Carry 2 crates of mail to %s. +240 crowns.`, and the contract is gone. At a third town nothing happens.
  - `test_a_bounty_pays_for_pirates_beaten_nearby`: a bounty for 2 (pirates added with `add_ship(PirateShip.build(), …, pirate = true)`, anchored, no captain). A pirate 2 km away, its helm destroyed: after a frame and `_wear`, `done` is still 0. One 300 m off, its helm destroyed: `done` is 1. A second 300 m off lost to the Roil completes it.
  - `test_a_salvage_contract_pays_when_you_strip_her`: a salvage contract for site 0: salvaging site 0 pays the salvage's crowns and the reward. Salvaging another site doesn't complete it.
  - `test_scouting_pays_when_you_get_there`: a scouting contract: ashore 500 m from its landmark, `_wear` changes nothing; at 350 m it completes.
  - `test_three_contracts_at_most`: a fourth says `You have three contracts already.`
  - `test_dropping_a_delivery_unloads_its_mail`: dropping it removes the two mail crates and says `Contract dropped: Carry 2 crates of mail to %s.` (town 1's name).
  - `test_a_delivery_needs_room`: with the hold full of grain, taking a delivery says `Your hold has room for 0 crates.`
  - Network: `test_a_guest_takes_and_completes_a_contract`: after `sail_together()`, the guest takes a scouting contract. It's in their `mine` within 1 s, and the host's account for `Guest` has it. The guest, ashore, glides to within 350 m of the landmark (moved there): they're paid and told within 2 s.
  - Network: `test_the_server_ignores_junk_contract_asks`: the guest's `_take` of an unknown id, an id on another town's board, from 3 km out, as a fourth contract, and with `"1"`; and `_drop` of the host's contract id. No account or board changes.
- [ ] **Step 2: Run `./run_tests.sh contracts`.** Expected: fail.
- [ ] **Step 3: Implement** boards, taking, dropping, the four completions, docking and beaten pirates, and the Contracts section.
- [ ] **Step 4: Run the whole suite, then play by hand:** take one of each kind and finish them.
- [ ] **Step 5: Commit** "Post contracts on town boards: deliveries, bounties, salvage and scouting".

### Task 6: Part tiers, unlocks and launch prices

Build-log item s07-05: "Part unlocks and tiers: wood, iron, alloy; balloons, then lift stones". It also closes the stage 6 hand-offs on launch and rebuild prices, and the stage 5 and 6 deferral of checking the launch town.

**Files:**
- Create: `tests/test_unlocks.gd`
- Modify: `src/economy/ledger.gd`, `src/net/world_sync.gd`, `src/builder/shipyard.gd`, `src/world/world.gd`, `tests/test_sinking.gd`

**Interfaces:**
- Consumes: `Economy.cost`, `value`, `launch_cost`, `locked`, `unlockable_at`, `UNLOCKS`, `INSURANCE` (Task 1); `set_cargo` (Task 2); `pay`, `tell` (Task 3).
- Produces:
  - `Ledger`: `func unlock(part: String) -> void` (this machine's player); RPC `_unlock(part)`; `func charge_launch(peer: int, design: ShipGrid, own: Ship) -> String` (server: "" when charged, else why not); `func insure(captain: int, blueprint: ShipGrid) -> void` (server); `func trade_in(peer: int, own: Ship) -> int`.
  - `Shipyard`: `signal unlock_requested(part: String)`; `var account: Dictionary`, `var trade_in := 0`, `var region := WorldGen.Region.CALM` (set by the World before adding it); `func set_account(new_account: Dictionary) -> void`.
  - `World`: passes the account, trade-in and the yard town's region to the shipyard, keeps them current on `account_changed`, and sends `unlock_requested` to `ledger.unlock`.

Rules:
- **The server's launch** (`_launch_for`), before anything is built:
  1. The asker's last world position must be `Dock.near` the named town's dock, for test flights too. Else: `Launch from a town's dock.`
  2. A test flight costs nothing and may use locked parts.
  3. Otherwise `charge_launch` checks the design's locked parts against the asker's unlocks (`Unlock %s first.`, part names joined with ` and `), and the crates aboard their own ship against the design's bays (`She has room for %d of the %d crates aboard. Sell some first.`). It charges `launch_cost(design, trade_in)` (`She costs %d crowns and you have %d.`). Any refusal goes back through `tell`, and nothing is built.
  4. The trade-in is `Economy.value(own.grid, own.spares)` when the asker has their own ship, else their account's `insured`, which the launch uses up.
  5. On success the asker hears `Launched for %d crowns.`. The new ship has a full load of spares, since her price includes it. Her predecessor's crates move into her free bays in cell order before the predecessor is removed.
- **Insurance:** `remove_ship(ship, successor, lost = true)` of a ship with a captain that isn't a test flight calls `ledger.insure(captain, ship.blueprint)`, which sets their `insured` to `roundi(INSURANCE × cost(blueprint))`. The World's loss message becomes `Your ship is lost to the Roil. The shipyard has her blueprint, and her insurance pays half of her.`
- **Unlocking** (`_unlock_for(peer, part)`): `part` must be an `UNLOCKS` key the asker hasn't unlocked. They must stand at a town's dock where `unlockable_at(part, town region)` holds, with the price. It's charged, then added to their unlocks: `Unlocked %s.` (the part's name). Refusals: `%s isn't sold here: try a town in %s or further in.` (with `WorldGen.REGION_NAMES` of the part's region), `You can't afford %s (%d crowns).`, `You've unlocked %s already.` and `Unlock parts at a town's shipyard.`
- **The shipyard** shows:
  - each palette entry for a locked part as `"%s   %d kg   locked"`;
  - the selected block as `%d kg · %d hit points · %d crowns`;
  - the Launch button as `Launch · free` when the price is 0, else `Launch · %d crowns`, disabled with no helm, with locked parts, or when you can't pay;
  - a note: with locked parts `Unlock %s to launch her.`; when you can't pay `She costs %d crowns; you have %d.`;
  - for each locked part, an `Unlock %s · %d crowns` button when this town sells it, else a caption `%s is sold at towns in %s or further in.`
  - Test flight stays enabled whatever the price or locks.
- The client's trade-in is the same sum over its own copy of your ship, which has her hit points and spares, or your account's `insured`.

- [ ] **Step 1: Write the failing tests** (`tests/test_unlocks.gd`, `extends NetCase`; a solo world at the dock unless marked network; `skiff` as in `test_launch.gd`; `first_town_in(world, region)` returns the index of the first town of that region):
  - `test_launching_charges_the_difference`: launching the starter ship with ten iron plates added (under her keel, at `(0, −2, −4…5)`) costs 120 crowns and says `Launched for 120 crowns.`. Relaunching her after a frame drops to 50 hit points costs 2. Launching the skiff costs nothing.
  - `test_a_design_with_locked_parts_cant_launch`: a design with an alloy plate says `Unlock Alloy plate first.`, launches nothing and charges nothing. The shipyard's Launch button is disabled, and its note says `Unlock Alloy plate to launch her.`
  - `test_test_flights_are_free_even_with_locked_parts`: the alloy design test-flies, and the purse doesn't change.
  - `test_unlocking_at_a_town_further_in`: at town 0, unlocking alloy says `Alloy plate isn't sold here: try a town in The Shattered Belt or further in.`. At the first Shattered Belt town it costs 2,000 (the purse set to 2,500 first), says `Unlocked Alloy plate.`, adds `alloy` to `mine["unlocks"]`, and the alloy design then launches. Unlocking it again says `You've unlocked Alloy plate already.`
  - `test_a_lost_ship_is_insured_for_half`: your ship lost to the Roil: `mine["insured"]` is 675, and the message is the new loss message. Back at the dock, launching her blueprint costs 675, and `insured` is 0 afterwards.
  - `test_crates_move_to_the_new_ship`: with two crates aboard, launching the starter ship carries them to the new ship's first two bays. A design with one bay is refused with `She has room for 1 of the 2 crates aboard. Sell some first.`
  - `test_the_shipyard_shows_the_price_and_the_locks`: `Launch · free` for the unchanged starter ship, `Launch · 120 crowns` with the iron added, the palette's `Alloy plate   110 kg   locked`, and with alloy selected `110 kg · 260 hit points · 30 crowns`. At town 0 there's the caption `Alloy plate is sold at towns in The Shattered Belt or further in.`
  - Network: `test_the_server_refuses_a_launch_it_shouldnt_make`: the guest, with no ship of their own and standing at town 0, sends `_launch` naming town 3: `Launch from a town's dock.`. With their purse set to 100, the starter ship: `She costs 1350 crowns and you have 100.`. With 1,500 but an alloy plate: `Unlock Alloy plate first.`. Nothing is built or charged. Then a legal launch sent twice within the cooldown builds one ship and charges 1,350 once.
  - `tests/test_sinking.gd`: the loss message is the new one, and `test_rebuilding_a_lost_ship_launches_her_blueprint_whole` also checks the purse went down by 675.
- [ ] **Step 2: Run `./run_tests.sh unlocks`.** Expected: fail.
- [ ] **Step 3: Implement** the launch checks and charges, insurance, unlocking, and the shipyard's prices and locks.
- [ ] **Step 4: Run the whole suite.** Expected: pass. Stage 4–6 launch tests still pass: their designs cost no more than their trade-in, and a guest's first ship fits in 1,500 crowns.
- [ ] **Step 5: Commit** "Price launches by their parts less the old ship, insure lost ships, and unlock alloy and lift stones further in".

### Task 7: Abandon ship

Build-log item: none of its own. This closes the stage 6 hand-off: a ship whose helm is shot off can't be repaired away from a shipyard, so she can strand you far from a dock. It counts under s07-05's launch prices, through insurance.

**Files:**
- Create: `tests/test_abandon.gd`
- Modify: `src/net/world_sync.gd`, `src/world/world.gd`, `tests/test_sinking.gd`

**Interfaces:**
- Consumes: `insure` (Task 6); `recover` (stage 6).
- Produces:
  - `WorldSync.abandon() -> void` (this machine's player); RPC `_abandon()`.
  - `World`: `func abandon_ship() -> void`; `func come_ashore(at: Vector3) -> void` (puts you standing at `at` in the world, making your controls if you have none yet); the pause menu's `Abandon ship` button.

Rules:
- **The server** (`_abandon_for(peer)`) removes the asker's own ship (not a test flight), if they have one, with `remove_ship(own, null, true)`. She's lost: insured, with her cargo and hands gone with her.
- **The pause menu** shows `Abandon ship` while you have a ship of your own that isn't a test flight. The first press changes it to `Abandon ship: press again`, and the second calls `abandon_ship()`. Closing the menu resets it.
- **On the abandoner's machine** the loss message is `You abandon ship. The shipyard has her blueprint, and her insurance pays half of her.` Aboard her, or ashore, you wake on the nearest town's quay (`recover(null)`). Aboard another ship, you stay there.
- **After any loss, you go to the quay at once.** In `_on_ship_removed`, when the ship you're on is removed with nowhere to board, you're put on the nearest quay (`recover(null)`) if she was lost, and stepped into the air as before if not. `recover`'s quay branch uses `come_ashore`.

- [ ] **Step 1: Write the failing tests** (`tests/test_abandon.gd`, `extends NetCase`; a solo world, your ship anchored at `open_sky(world, 1000)` unless marked network):
  - `test_abandoning_ship_puts_you_on_the_nearest_quay`: pause, press `Abandon ship` twice: your ship is gone, you're ashore and on the floor of the nearest town's quay within 2 s, the HUD says the abandon message, and `world.design` holds her blueprint.
  - `test_an_abandoned_ship_is_insured`: `mine["insured"]` is 675 afterwards.
  - `test_a_wrecked_ship_can_be_abandoned_from_ashore`: her helm destroyed and you ashore 2 km away: abandoning puts you on the nearest quay.
  - `test_the_abandon_button_needs_a_ship_of_your_own`: after abandoning, the pause menu has no `Abandon ship`. On a test flight with no ship of your own, it has none either.
  - `test_losing_a_ship_puts_you_on_the_quay_at_once`: aboard as she's lost to the Roil: on the quay right after she's removed, with no fall, and the loss message still showing 1 s later.
  - Network: `test_a_guest_can_abandon_only_their_own_ship`: after `sail_together()`, the guest's `_abandon` with no ship of their own changes nothing, and the host's ship stays. With their own ship launched, it's gone and the host's stays.
  - `tests/test_sinking.gd`: `test_a_ship_below_the_roil_is_lost_and_its_crew_rescued` still passes, now reaching the quay without the Roil's rescue.
- [ ] **Step 2: Run `./run_tests.sh abandon`.** Expected: fail.
- [ ] **Step 3: Implement** abandoning, `come_ashore`, and the quay after a loss.
- [ ] **Step 4: Run the whole suite.** Expected: pass.
- [ ] **Step 5: Commit** "Let a stranded captain abandon ship, and wake on the nearest quay after a loss".

### Task 8: Hired hands

Build-log item s07-04: "Hire AI crew to staff stations: gunner, engineer, repairer".

**Files:**
- Create: `src/ai/crew_hand.gd`, `tests/test_hands.gd`
- Modify: `src/ai/pirate_captain.gd`, `src/ship/ship.gd`, `src/ship/damage.gd`, `src/ship/tuning.gd`, `src/net/world_sync.gd`, `src/economy/ledger.gd`, `src/ui/town_panel.gd`, `tests/test_fleet.gd`, `tests/test_damage.gd`

**Interfaces:**
- Consumes: `Economy.HANDS`, `HAND_NAMES` (Task 1); trading's checks and the town panel (Task 4); the launch (Task 6); `fire_cannon`, `Damage.repair`, `put_out`, `Projectiles.aim` (stage 6).
- Produces:
  - `Tuning.ENGINE_BOOST := 0.25`.
  - `PirateCaptain.fire_at(world_sync: WorldSync, ship: Ship, cannon: Cannon, target: Ship, ammo: String) -> bool` (static): the captain's leading and aiming code for one loaded cannon. It fires through `fire_cannon` when the cannon can bear, and returns whether it fired. The captain's `_fire` loops over its cannons through it, with no change in behaviour.
  - `Damage.next_job(grid: ShipGrid, blueprint: ShipGrid, burning: Array, from: Vector3, mending: bool) -> Variant`: the cell to work at (a `Vector3i`), or null.
  - `Ship`: `var hands: Array[Dictionary] = []` (each `{"id": int (below 0), "name": String, "role": String, "post": Vector3i, "at": Vector3}`); `func set_hands(list: Array) -> void` (sets them, works out her power again, and draws them); `func tended_engines() -> int`; `func spot_near(cell: Vector3i) -> Vector3`.
  - `class_name CrewHand extends Node` (server only, a child of the ship): `const THINK_EVERY := 0.5`, `const WALK := 4.0`, `const SEARCH_EVERY := 1.0`, `const TELL_EVERY := 0.5`; `var hand: Dictionary`, `var job: Variant`, `var shots := 0`; `func _init(world_sync: WorldSync, hand_entry: Dictionary)`; `static func read_hands(data: Variant, grid: ShipGrid) -> Variant`.
  - `WorldSync`: `func set_hands(ship: Ship, hands: Array) -> void` (server: sets them, makes a `CrewHand` for each gunner and repairer, mans gunners' cannons, and tells everyone); `func tell_hands(ship: Ship) -> void` (server: tells everyone where they stand); `func mend(ship: Ship, cell: Vector3i) -> bool` (server: one repair action, as `_repair_for` does after its checks; true when it did something); RPC `_hands(id, hands)`; entries of 12 fields, `hands` last.
  - `Ledger`: `func hire(role: String) -> void`, `func dismiss(id: int) -> void` (this machine's player); RPCs `_hire(role)`, `_dismiss(id)`.

Rules:
- **Hiring** (`_hire_for(peer, role)`): `role` is a `HANDS` key. The asker must be aboard a ship that isn't a test flight or a pirate, at a town's dock. Refusals: `Hire crew at a town's dock.`, `She has no free bunk.`, `She has no free cannon for a gunner.`, `She has no free engine for an engineer.` and `You can't afford a %s (%d crowns).`
  - Her hands must number fewer than her bunks.
  - A gunner needs a cannon nobody mans (sorted by cell); it becomes his post, and its `gunner` becomes his id.
  - An engineer needs an engine with no engineer; it becomes his post.
  - A repairer needs no post (his `post` is `Vector3i.ZERO`).
  - On success the fee is charged, and the hand gets the next id (−1, −2, …), a name from `HAND_NAMES` drawn with `sync.rng` (skipping names already aboard while any are left), and `at = spot_near(post)` (a repairer `crew_spawn(0)`). The message is `%s the %s joins the crew.`
- **Dismissing** (`_dismiss_for(peer, id)`) needs the asker aboard that ship at a dock. A gunner's cannon is let go. No refund. `%s leaves the crew.`
- **`spot_near(cell)`:** the empty cell nearest `cell` (by distance, then cell order), within 3 cells each way, with a block other than a ladder below it and nothing above it, standing at its centre plus 0.45 m up (as `crew_spawn` stands crew). With none, `crew_spawn(0)`.
- **Gunners** (every `THINK_EVERY`): with their cannon still manned by them and a pirate that isn't a wreck within `PirateCaptain.FIRE_RANGE` of the ship (the nearest), `fire_at` with `PirateCaptain.VOLLEY[shots % 3]` (round shot when it has no balloons), and `shots += 1` when it fires. They fire at nothing but pirates.
- **Repairers** (every `Damage.REPAIR_EVERY`):
  - At most every `SEARCH_EVERY`, when they have no job, the job is `next_job(grid, blueprint, burning, at, spares > 0)`.
  - `next_job` returns the burning cell nearest `from` (ties by cell order); else, when `mending`, the nearest block for which `Damage.repair` does something; else null.
  - Within `Damage.REPAIR_REACH` of the job they `mend` it, and the job ends when `mend` returns false. Otherwise they walk straight at it at `WALK` m/s, through anything. `tell_hands` goes out at most every `TELL_EVERY` while they move.
  - ponytail: a repairer searches the whole grid once a second and walks through walls; keep a damaged-cell list and walk the decks if big ships or the look of it need it.
- **Engineers:** `tended_engines()` counts the distinct engine cells that an engineer's post names and the grid still has. `rebuild` and `set_hands` set the propellers' power to `ShipForces.propeller_power(grid) × (1 + ENGINE_BOOST × tended / engines)`.
- **Hands go with their ship.** Removing her frees her `CrewHand`s. At a launch, the predecessor's hands move to the new ship in order while she has bunks, each to a free post of their role, and the rest stay ashore: `%s stays ashore: she has no room for a %s.`. `_let_leavers_go` lets go only of cannons whose `gunner` is above 0, so hands aren't let go as leavers.
- **Drawing hands:** every machine draws each hand as a `CrewAvatar` labelled with their name, a child of the ship at `at` with physics interpolation inherited. Clients set `hands` from entries and `_hands` through `read_hands`. That takes at most 64 entries of `[id (below 0), name (a String of 1 to 24 characters), role (a HANDS key), post (a Vector3i in the build area), at (a finite Vector3 within the grid's bounds grown CREW_REACH)]`, and ignores junk.
- **The Crew section** of the town panel shows `Hands     %d/%d bunks`. Then a button for each role, `Hire a %s   %d crowns`, and a row per hand, `%s, %s` (name, role), with `Dismiss`.
- ponytail: gunners only shoot pirates and repairers ignore shots; hands are never hit or knocked down, and wait for boarding (stage 9) to fight.

- [ ] **Step 1: Write the failing tests** (`tests/test_hands.gd`, `extends NetCase`; a solo world at the dock unless marked network; `sync.rng.seed = 1`. The hiring tests hire through the Ledger. The behaviour tests put hands aboard with `sync.set_hands` directly, so they can fly anywhere):
  - `test_hiring_a_hand_needs_a_bunk_and_a_post`: hiring a gunner: one hand, his post the port cannon `(−2, 1, 1)` (first in cell order), that cannon's `gunner` his id, 150 crowns charged, and `%s the gunner joins the crew.` with his name. Hiring an engineer: posted at the engine `(0, −1, −5)`. A third hire: `She has no free bunk.`
  - `test_a_gunner_fires_at_pirates_abeam`: your ship anchored at `open_sky(world, 1000)` with a gunner posted at the starboard cannon `(2, 1, 1)`. A pirate ship added with no captain, anchored, 300 m to starboard: within 5 s a shot leaves from `(2, 1, 1)`, and within 8 s the pirate has lost blocks (as stage 6's hit tests at 150–200 m do). The pirate moved 300 m astern: no shot in the next 10 s. A ship that isn't a pirate 300 m to starboard: no shot in 10 s.
  - `test_a_repairer_puts_out_fires_then_mends`: in open sky with a repairer, a fire at a plank, a second plank at 20, and a third destroyed. Within 10 s no fires burn, then within 40 s the damaged plank is whole and the lost one is back. Spares went down by the mends (none for the fire). With 0 spares, a new fire still goes out and nothing is healed.
  - `test_an_engineer_makes_her_faster`: a calm-air flight test of two starter ships at full throttle for 90 s, one with an engineer at her engine: she's at least 8% faster. With her engine destroyed, `tended_engines()` is 0.
  - `test_hands_go_down_with_their_ship`: your ship lost to the Roil: her hands and their `CrewHand`s are gone.
  - `test_hands_move_to_the_ship_that_replaces_theirs`: with a gunner and a repairer, launching the starter ship again: both are aboard the new one, and the gunner mans her port cannon. Launching a design with one bunk instead: one stays, and the HUD says `%s stays ashore: she has no room for a %s.`
  - `test_dismissing_a_hand`: dismissing the gunner frees his cannon and says `%s leaves the crew.`
  - Network: `test_guests_see_the_hands`: after `sail_together()`, the host hires a gunner and a repairer. The guest's copy has two hands with the same names and two labelled avatars, and the walking repairer's `at` is within 1 m of the host's within 1 s.
  - Network: `test_the_server_ignores_junk_hiring`: the guest's `_hire("captain")`, `_hire(3)`, a hire from 3 km away, a hire with an empty purse, `_dismiss(−99)`, and dismissing a hand of a ship they aren't aboard: nothing changes.
  - `tests/test_damage.gd`: `next_job` picks the nearest fire before any damage, the nearest damage when there's no fire, and nothing without `mending`.
  - `tests/test_fleet.gd`: 12-field entries, and one with junk hands.
  - `tests/test_pirates.gd` passes unchanged.
- [ ] **Step 2: Run `./run_tests.sh hands`.** Expected: fail.
- [ ] **Step 3: Implement** `fire_at`, `next_job`, hands on the ship, `CrewHand`, hiring and dismissing, the engineer's boost, the network, and the Crew section.
- [ ] **Step 4: Run the whole suite, then play by hand:** hire two gunners, fly out until a pirate comes, and watch them fire. Then hire a repairer and an engineer.
- [ ] **Step 5: Commit** "Hire hands at the dock: gunners fire at pirates, repairers mend, engineers drive the engine harder".

### Task 9: Saves and autosaves

Build-log item s07-06: "Save and load, autosave, multiple save slots" (the saving), and s07-07: "Tests: save round trip and economy calculations" (the save half).

**Files:**
- Create: `src/save/save_game.gd`, `tests/test_save_game.gd`, `tests/test_saves.gd`
- Modify: `src/world/world.gd`, `src/net/world_sync.gd`, `src/net/session.gd`, `src/world/exploration.gd`

**Interfaces:**
- Consumes: `Economy.read_account` (Task 1); `ShipGrid.read_blocks`, `read_paint`, `read_cargo` (Task 2); the ledger's accounts and `send_account` (Task 3); `docked` (Task 5); `World.come_ashore` (Task 7); `CrewHand.read_hands` and `set_hands` (Task 8).
- Produces:
  - `class_name SaveGame` (static):
    - `static var dir := "user://saves"` (tests point it elsewhere).
    - `const VERSION := 1`, `const FILES := {"world": "world.json", "ships": "ships.json", "players": "player.json"}`, `const SLOTS := ["1", "2", "3"]`, `const AUTOSAVES := 3`, `const MAX_FILE_SIZE := 16777216`.
    - `static func slot_path(slot: String) -> String`, `static func autosave_paths(slot: String) -> Array[String]`, `static func autosave_path(slot: String) -> String`.
    - `static func write(path: String, save: Dictionary) -> Error`, `static func read(path: String) -> Dictionary` (`{"save": Dictionary}` or `{"problem": String}`).
    - `static func load_slot(slot: String) -> Dictionary` (`{}` for an empty slot, `{"save", "note"}`, or `{"problem"}`).
    - `static func prepare(session: Node, slot: String) -> Dictionary` (loads the slot into the session for the next game, and returns what `load_slot` gave).
    - `static func read_ship(record: Dictionary) -> Dictionary`, `static func rename(save: Dictionary, from: String, to: String) -> void`, `static func date_text(unix: float) -> String`, `static func summary(slot: String) -> String`.
  - `Session`: `var save_slot := ""` (the slot this server saves to; "" never saves), `var loaded: Dictionary = {}` (a `load_slot` result for the next world). `_reset` leaves both alone.
  - `WorldSync`: `var stored: Dictionary = {}` (server: captain name → the record of their ship, while they're away); `func record(ship: Ship) -> Dictionary`; `func restore(record: Dictionary, captain: int) -> Ship`; `func set_clock(time: float) -> void` (server); `signal entered` (a client's world has had `_world`).
  - `Exploration`: `func to_text() -> String` (base64 PNG), `func read_text(text: String) -> bool`.
  - `World`: `const AUTOSAVE_EVERY := 300.0`, `const AUTOSAVE_GAP := 30.0`; `var _since_save := 0.0` (seconds of play since the last save); `func capture() -> Dictionary`; `func save_game(auto := false) -> Error` (with no `save_slot` it writes nothing and returns `ERR_UNCONFIGURED`).

Rules:
- **A save** is `{"world": {seed, time, salvaged, exploration, host, saved}, "ships": [records], "players": {name: account}}`. On disk, each part is its own file: `{"version": 1, "<part>": …}`.
  - `host` is the host player's name ("" on a dedicated server).
  - `saved` is `Time.get_unix_time_from_system()`.
  - `exploration` is the host player's map ("" with no player).
- **A ship's record** (`record`) is `{"captain": name ("" for nobody's), "at": [x, y, z, qx, qy, qz, qw], "trim", "anchored", "spares", "blocks": to_blocks(), "blueprint": blueprint.to_blocks(), "paint": paint_names(), "cargo": cargo_list(), "hands": [[name, role, px, py, pz, ax, ay, az], …]}`.
- **What's saved:** `capture()` records every ship except test flights, pirates and nobody's wrecks, and adds the records in `stored`. Accounts are saved whole. Boards, pirates, wrecks, fires and shots aren't.
- **Writing:** `write` makes the folder and writes each file to `<name>.tmp`, then renames it over the old one, as `Blueprint.save` does. ponytail: the three files are written one after another, on the main thread (about 240 ms for eight 4,000-block ships); a crash between files mixes two saves, and the autosaves cover it. Thread it if autosaves stutter.
- **Reading** checks everything and stops at the first problem:
  - each file exists (`This save is missing %s.`), is no bigger than `MAX_FILE_SIZE` (`%s is too big.`), and is UTF-8 JSON holding a Dictionary (`%s is damaged.`);
  - its version is 1 (`This save is version %d; this game reads version 1.`);
  - `world.seed` is 0 to 2,147,483,647, `time` is finite and 0 or more, `salvaged` holds whole numbers, `exploration` and `host` are Strings, and `saved` is a number;
  - each ship passes `read_ship`, which uses `read_blocks` (`needs_helm` false, so a helmless ship of yours keeps), `read_paint`, `read_cargo` and the hands' own checks, with a finite place and a normalised rotation, `trim` within the trim limits, and `spares` 0 to 40;
  - each account passes `Economy.read_account`.
  - Problems name the file, for example `ships.json: ship 2 has a block outside the build area (-64 to 63).`
- **Autosaves** go to `autosave_path(slot)`: the first of `auto-1` to `auto-3` that's missing, else the one with the oldest `saved`. Saving by hand writes `slot_path(slot)`.
- **Loading a slot** (`load_slot`) tries the slot's save and its autosaves, newest `saved` first, and returns the first that reads. When it isn't the newest, `note` says `The latest save in slot %s couldn't be read (%s), so the one from %s was loaded.` (with `date_text` of its `saved`, local time as `2026-10-01 14:02`). When none reads: `{"problem": "Slot %s couldn't be read: %s"}` with the newest's problem.
- **`prepare(session, slot)`** sets `save_slot = slot`. With a loadable save it also sets `loaded`, and `requested_seed` to the save's seed.
- **`summary(slot)`** is what the menu shows: `Slot %s   empty`, `Slot %s   can't be read`, or `Slot %s   %s · %d crowns · seed %d · %s` (the saved host's name, or `server` with no host; that player's money, or 0; the seed; and `date_text` of `saved`).
- **Restoring** (the server's World, in `_ready`, when `session.loaded` isn't empty; the starter ship isn't added):
  1. On a hosted or solo game whose saved `host` differs from the host's name now, `rename` moves that account, captaincies and crate owners to the new name.
  2. `set_clock(time)`, the salvaged sites, and the host's exploration.
  3. `ledger.accounts` are the saved accounts, and this machine's player is sent theirs.
  4. Each record's captain on the roster gets their ship back through `restore` (nobody's ships too). Records of anyone else go into `stored`.
  5. `session.loaded` is cleared, and its `note` is shown when you arrive.
- **`restore`** adds the ship with her saved blocks, blueprint, place, trim, anchoring, spares, cargo and hands (new ids, gunners manning their posts), not moving, and tells everyone as `add_ship` does.
- **Captains who come and go:** when a captain leaves, `_let_leavers_go` stores their own ship's record in `stored` before removing her (test flights aren't stored). When a peer enters the world, after `_world`, a stored ship of theirs is restored with them as captain and leaves `stored`.
- **With no ship to board**, you start ashore on the starting town's quay (`come_ashore(Dock.quay_spot(START))`): on the server after restoring, and on a client when `entered` fires and you aren't aboard anything.
- **Autosaving** happens only on a server with a `save_slot`: when `AUTOSAVE_EVERY` of play has passed since the last save, and on `docked` when at least `AUTOSAVE_GAP` has. A failed autosave says `Couldn't autosave (%s).`
- **Exploration** `to_text` is `Marshalls.raw_to_base64(image.save_png_to_buffer())`. `read_text` takes only a 128 × 128 PNG, converts it to `FORMAT_L8`, counts what's seen, and bumps `revision`. Anything else returns false and changes nothing.

- [ ] **Step 1: Write the failing tests:**
  - `tests/test_save_game.gd` (plain `TestCase`; `SaveGame.dir` set to a fresh `user://test_saves_<random>` and removed in `after_each`):
    - `test_a_save_round_trips`: a save built in the test has the starter ship (damaged, with two crates, 12 spares, a gunner and a repairer), a helmless ship of `Bo`'s, two accounts (one with a contract and an unlock), salvaged `[2, 5]`, and an exploration string. `write`, then `read`, gives back the same Dictionary, numbers as ints where they were ints. `read_ship` of each record gives the same grid, cargo, hands and place.
    - `test_saves_are_checked`: one change at a time to a good save: `ships.json` deleted, `world.json` with `{`, version 2, seed −1, a block at x 100, a crate on a deck plank, an account with money −5, a 2 MB string in `host` when `MAX_FILE_SIZE` is lowered for the test. Each gives its problem, naming the file.
    - `test_a_broken_save_falls_back_to_the_previous_autosave`: the slot's save (saved 200) and `auto-1` (saved 100): `load_slot` gives the save with no note. With the save's `ships.json` broken, it gives `auto-1`'s and the note. With both broken, it gives the problem.
    - `test_autosaves_keep_the_last_three`: four autosaves saved 1, 2, 3 and 4 leave `auto-1` at 4, `auto-2` at 2 and `auto-3` at 3. `load_slot` gives the one saved at 4.
    - `test_an_empty_slot_is_empty`: `load_slot("1")` is `{}`, and `summary("1")` is `Slot 1   empty`. After a save of `Ann` with 2,340 crowns and seed 7, it's `Slot 1   Ann · 2340 crowns · seed 7 · ` plus the date.
    - `test_renaming_the_host`: `rename(save, "Ann", "Anna")` moves the account, the captaincy and the crates' owners, and leaves `Bo`'s alone.
    - `test_exploration_round_trips`: an `Exploration` revealed at two points, written with `to_text` and read into a fresh one, has the same `seen` cells and `seen_fraction()`. `read_text("junk")` is false.
  - `tests/test_saves.gd` (`extends NetCase`; `SaveGame.dir` as above):
    - `test_a_solo_game_saves_and_loads`: a solo world with `save_slot = "1"`, prepared with: a cell at 10 hit points and one destroyed, two crates, 12 spares, a gunner, 900 crowns, a scouting contract, wreck site 2 salvaged, the clock at least 30 s on, and exploration revealed at the start. `save_game()`, leave, then a new solo session with `SaveGame.prepare(session, "1")` and a new world: your ship has the same cells and hit points, within 0.01 m and 0.01 rad of where she was; the same crates, 12 spares and a gunner at her post; `mine` with 900 crowns and the contract; site 2 salvaged; the clock within 0.5 s; and the same exploration.
    - `test_autosaves_every_five_minutes_and_on_docking`: with `save_slot = "1"` and `_since_save` set to 299 s, simulating 1.5 s writes `auto-1`. Docking at town 1 within 30 s doesn't write again. Docking at town 0 after `_since_save` is set to 31 s writes `auto-2`.
    - `test_a_loaded_game_without_your_ship_starts_on_the_quay`: a save with no ships: you're standing on the starting town's quay.
    - `test_the_host_keeps_their_progress_under_a_new_name`: a solo save by `Ann` loaded by `Anna`: her ship is Anna's, and so is her purse.
    - Network: `test_a_leavers_ship_waits_for_them`: after `sail_together()`, the guest launches their own ship and buys a crate. The guest leaves: their ship leaves the world, and `stored["Guest"]` holds her record with the crate. `capture()` has her. A new client joins as `Guest`: within 5 s their ship is back with the same cells, crate and place, they're aboard her, and their purse is as it was.
- [ ] **Step 2: Run `./run_tests.sh save`.** Expected: fail.
- [ ] **Step 3: Implement** `SaveGame`, records and restoring, stored ships, the clock, exploration as text, capture, autosaves, and starting on the quay.
- [ ] **Step 4: Run the whole suite.** Expected: pass.
- [ ] **Step 5: Commit** "Save the world in slots: autosave, keep the last three, and fall back from a broken save".

### Task 10: Saved games in the menus

Build-log item s07-06: "Save and load, autosave, multiple save slots" (the menus).

**Files:**
- Create: `tests/test_save_menu.gd`
- Modify: `src/ui/main_menu.gd`, `src/world/world.gd`, `src/core/game.gd`

**Interfaces:**
- Consumes: `SaveGame.SLOTS`, `summary`, `load_slot`, `prepare` (Task 9); `World.save_game` (Task 9).
- Produces:
  - `src/ui/main_menu.gd`: a saved games panel (`var _saves: VBoxContainer`), `func _open_saves(hosting: bool) -> void`, `func _continue(slot: String) -> void`, `func _new_game(slot: String) -> void`.
  - `World`: the pause menu's `Save game` button and a note line; `func leave_game() -> void` (autosaves first on a server with a slot, then leaves).
  - `Game`: `--server` plays the `server` slot.

Rules:
- **Play solo** and **Host game** open the saved games panel instead of starting at once. It has the caption `Saved games` and, for each of `SaveGame.SLOTS`, a row with the slot's `summary` and two buttons:
  - `Continue` is disabled for an empty or unreadable slot. It runs `SaveGame.prepare(Session, slot)`; on a problem it shows it as the menu's problem and starts nothing. Otherwise it starts solo, or hosts (then the lobby as now).
  - `New game` on an empty slot sets `Session.save_slot = slot`, `Session.loaded = {}` and `Session.requested_seed = −1`, then starts. On a used slot the first press changes it to `Start over: press again`, and only the second starts.
  - `Back` returns to the menu, and Esc does too.
- **The pause menu** gains `Save game` (on a server with a `save_slot`) above `Leave game`. It writes the slot's save and shows `Saved to slot %s.` or `Couldn't save (%s).` in its note. `Leave game` calls `leave_game()`.
- ponytail: closing the window leaves without saving; the last autosave is at most five minutes old. Save on `NOTIFICATION_WM_CLOSE_REQUEST` if players lose progress.
- **A dedicated server** (`--server`) runs `SaveGame.prepare(Session, "server")` before hosting. It prints the note when it fell back, and a problem as `%s; starting a new world.` (`load_slot`'s problem, which already begins `Slot server couldn't be read:`) to stderr, then starts fresh.
- A note from loading shows as a HUD message when you arrive (Task 9).

- [ ] **Step 1: Write the failing tests** (`tests/test_save_menu.gd`, `extends NetCase`; the menu with the `Session` autoload, as `test_menu.gd` does; `SaveGame.dir` set to a temp folder, and `Session.save_slot` and `loaded` restored in `after_each`):
  - `test_play_solo_shows_the_slots`: pressing `Play solo` shows three rows reading `Slot 1   empty`, `Slot 2   empty` and `Slot 3   empty`, with `Continue` disabled.
  - `test_continue_loads_the_slot`: a slot-2 save written with seed 7: its row reads its summary. `Continue` starts a solo game with `Session.world_seed` 7, `save_slot` `"2"` and `loaded` set.
  - `test_a_broken_slot_says_so`: slot 1 with only a broken save: its row reads `Slot 1   can't be read` and `Continue` is disabled.
  - `test_new_game_on_a_used_slot_asks_twice`: the first `New game` on slot 2 changes the button to `Start over: press again` and starts nothing. The second starts a game with `save_slot` `"2"` and `loaded` empty.
  - `test_save_game_in_the_pause_menu`: a solo world with `save_slot = "3"`: `Save game` writes `slot_path("3")` and the note says `Saved to slot 3.`. With no slot, the button is hidden.
  - `test_leaving_saves_first`: `leave_game()` on a solo world with slot 3 writes `auto-1` before the session ends.
  - `test_a_dedicated_server_plays_the_server_slot`: with a saved `server` slot (seed 9), `SaveGame.prepare(session, "server")` sets `save_slot`, `loaded` and `requested_seed` 9. A dedicated host started after it has world seed 9, and its world restores the saved ship as nobody's.
- [ ] **Step 2: Run `./run_tests.sh save_menu`.** Expected: fail.
- [ ] **Step 3: Implement** the saved games panel, the pause menu's Save game, leaving with a save, and the dedicated server's slot.
- [ ] **Step 4: Run the whole suite, then play by hand:** start slot 1, trade, quit, continue it. Delete `ships.json` from its newest save and continue again: you should see the fallback message.
- [ ] **Step 5: Commit** "Choose a save slot to continue or start over, and save from the pause menu".

### Task 11: Business on two machines, README and spec

Build-log item s07-07: "Tests: save round trip and economy calculations" (the network half, and the stage's promise).

**Files:**
- Create: `tests/test_economy_net.gd`
- Modify: `README.md`, `docs/superpowers/specs/2026-09-29-skywright-design.md`

- [ ] **Step 1: Write the tests** (`tests/test_economy_net.gd`, `extends NetCase`; `SaveGame.dir` set to a temp folder):
  - `test_a_hosted_game_saves_and_loads_with_its_guest`: after `sail_together()`, with `host.save_slot = "1"`: the guest launches their own ship, buys a crate at the dock and takes a contract; the host buys a crate and hires a gunner. The host's `save_game()` runs, and both leave. The host prepares slot 1 and hosts again, sets sail, and the guest joins as `Guest`. Within 5 s both have their ships (same cells), crates, purses and contracts, and the gunner mans the host's cannon.
  - `test_two_players_trade_at_one_dock`: both aboard the host's ship at the dock buy grain. Each sees two crates in her hold and `aboard 1` in their own market row. Each can sell only their own crate, and each purse moves only for its owner.
  - `test_a_dedicated_server_keeps_its_world`: a dedicated host in this process with `save_slot = "server"`. A guest joins, launches their own ship, and buys a crate. The server's `save_game(true)` runs, and both leave. A new dedicated host prepared from `server` starts. The guest joins again: their ship and crate are back, and the server's own ship is nobody's again.
- [ ] **Step 2: Run the whole suite three times.** Expected: it passes every time.
- [ ] **Step 3: Measure by hand** on the Radeon 680M (`godot --path . --gpu-index 0 -- --solo` after choosing a slot in the menu): time a save with the starter ship, and again after launching a ship of about 1,500 blocks, using `Time.get_ticks_usec` around `save_game` (a temporary print, removed before committing). Record both in "Changes during execution". If a save takes more than 50 ms, record it; a thread is the upgrade (ponytail in `SaveGame`).
- [ ] **Step 4: Update the README:**
  - The status: stage 7 of 10, and what you can do now: trade between towns, take contracts, hire hands, unlock alloy and lift stones, pay for spares and launches, abandon ship, and save and continue in three slots.
  - Controls: T opens the town at a dock. In the pause menu, Save game and Abandon ship.
  - A "Towns and money" section: purses, markets and why prices differ, cargo bays and crate weight, the four contracts, hands and what they do, unlocks and where they're sold, launch prices and trade-in, spares, insurance, abandoning ship.
  - A "Saves" section: slots, autosaves every five minutes and on docking, keeping three, falling back, the dedicated server's `server` slot, and where the files live.
  - The layout gains `src/economy/` and `src/save/`.
- [ ] **Step 5: Update the spec:**
  - the status line;
  - §3.3 (cargo as built, the starter ship's bays and bunks);
  - §3.4 (hands as built, spares bought, no engine station until fuel);
  - §3.5 (ammunition stays unlimited, salvage loot in crowns, insurance and abandoning ship);
  - §3.6 (the economy as built: crowns, inventory as crates, markets, contracts, unlocks and where, launch prices);
  - §3.8 (whose progress is saved, absent captains' ships, guests' maps);
  - §4.2 (`src/economy/` and `src/save/` exist);
  - §4.4 (`CRATE_MASS`, `ENGINE_BOOST`, fuel moved to stage 8);
  - §4.6 (protocol 6 and its budget, unique names, the launch-town check);
  - §4.10 (saves as built: slots, files, autosave rotation, falling back);
  - §7 (the broken save's message);
  - §9 decisions: inventory is crates, iron unlocked from the start, no fuel until stage 8, engineers boost engines, ammunition unlimited, spares and launches priced with trade-in, insurance at half, abandon ship, unique names, saves by name.
- [ ] **Step 6: Commit** "Test business on two machines; update README and spec for stage 7".

---

## Playtest checklist

1. **Trading:** fly a route from a town that makes a good to one that wants it. Is the profit worth the trip? Are the market rows easy to read?
2. **Cargo weight:** load four crates, then two at the bow only. Can you feel her sit lower and lean? Does the autopilot cope?
3. **Contracts:** take one of each kind. Are the titles' distances and directions enough to find the target without map markers? Do the rewards feel fair for the trip?
4. **Hired gunners:** hire two and get raided. Do they help in a fight, or just make noise?
5. **Repairers and engineers:** does a repairer keep up with a fire and with damage? Is the engineer's extra speed noticeable?
6. **Unlocks:** is it clear why alloy and lift stones are locked and where to buy them? Is getting to the Shattered Belt for alloy a goal worth having?
7. **Launch prices:** does relaunching a damaged ship to repair her feel fair? Is a bigger design's price clear before you press Launch?
8. **Spares and insurance:** does paying for spares change how you fight? After losing a ship, is half price for rebuilding right?
9. **Abandon ship:** shoot your own helm off far from a dock, then abandon ship. Does it rescue you without feeling like a cheat?
10. **Saves:** save, quit and continue. Is everything where you left it: ships, damage, crates, hands, money, contracts, the map? Break a file in the newest save and continue: is the fallback message clear?
11. **Autosaves:** is there a hitch at the five-minute mark or when docking?
12. **Co-op:** a friend leaves and rejoins. Are their ship, crates and purse back? Can two of you trade at one dock without confusion?
13. **Money pacing:** after 30 minutes of play, how much have you earned, and what did you spend it on?

---

## Changes during execution and after the final review

All eleven tasks ran inline, test first, with one whole-branch review at the end. Nobody could play by hand, so each task's "play by hand" step became a screenshot check of the town panel's three sections and the shipyard (after Task 8), plus the playtest below.

| Problem | Fix |
|---|---|
| The Ledger had no hook for "when a peer enters the world". | `WorldSync.peer_entered(peer)` fires at the end of `_enter_world`, and the Ledger sends that peer their account. |
| With the new dock check, a guest's launch right after joining was refused: the server hadn't yet heard where they stood. Only a test is that fast. | `NetCase.sail_together` (and two dedicated-server tests) wait until the host has heard the guest (`NetCase.heard`). |
| Two stage 5 town tests launched from a shipyard 2 km from its dock, and at a town the guest wasn't at. | They now expect "Launch from a town's dock." and launch where the guest is: the plan checks the town for every launch. |
| A hired gunner aiming at a pirate's centre of mass fired through the open air between her deck and envelope (traced: a round shot crossed her box at 300 m without touching a block). | `PirateCaptain.fire_at` takes an optional `aim_cell`, and gunners aim at the pirate's block nearest her centre of mass. Pirate captains aim as before. |
| The plan's "Hire a %s" gave "Hire a engineer". | `Economy.a_hand` gives "an engineer" in the button, the refusal and the stays-ashore message. |
| The plan's `WorldSync.entered` signal already existed as stage 6's `world_arrived`. | `world_arrived` is used, through `World.come_ashore`. |
| A hand's place went through a single-precision `Vector3`, so 1.45 read back as 1.4500000477 and the exact round trip failed. | A save's record keeps hand positions as the doubles written. |
| You stand a few metres from the ship's origin, so a loaded game can see one more map cell than was saved. | The solo round-trip test checks that every cell seen before saving is seen after loading. |
| Smaller wording calls. | Taking a delivery while not aboard a docked ship says "Your hold has room for 0 crates."; a free launch says "Launched for 0 crowns."; the fallback note drops the problem's own full stop inside its brackets; `SaveGame.rename` renames the saved host too; a save whose `world.json` won't read is ordered by its files' times. |

The final whole-branch review: "with fixes", one critical finding (reproduced), six important and eleven minor. One minor was re-graded important by its effect. Each fix below has a test that failed first; the whole suite then passed, 545 of 545.

| Problem | Fix |
|---|---|
| **Critical.** A long ship cut short left a hand (a bow engineer, a walking repairer) more than 35 m off her hull. Her record then failed to read, so every later save failed, autosaves rotated over the good ones, late joiners never saw her, and a returning captain's stored ship was erased and lost. | After a split, a gunner or engineer whose post broke away goes with it, and anyone left off the hull steps back aboard (`test_hands_stay_aboard_a_ship_cut_short`). `record()` also clamps hands inside the hull (`test_a_ship_record_always_reads`), and a stored ship leaves `stored` only once she's restored. |
| Contract ids started from 1 again after loading, so a new contract could share an id with a saved one, and Drop dropped the wrong one (unloading its mail). | `Ledger.set_accounts` numbers new contracts after every saved one (`test_contracts_taken_after_loading_have_new_ids`). |
| A failed autosave (full disk, read-only folder) retried every physics frame, stalling the host. | The five-minute clock restarts whether or not the autosave worked (`test_a_failed_autosave_waits_for_the_next_one`). |
| A repairer's search for work called `Damage.repair` on every block: 26–33 ms on a healthy 4,000-block ship, every second. | `next_job` looks only at damaged blocks and the neighbours of blocks the blueprint can rebuild: one pass, well under 8 ms at 4,000 blocks (`test_looking_for_work_on_a_big_healthy_ship_is_quick`). |
| A free test flight in parts not yet unlocked could earn money: salvage, bounties and scouting. | A player on a test flight earns nothing: "Test flights can't salvage.", and bounties and scouting don't count (`test_a_test_flight_earns_nothing`). |
| A friend who left with crates in your hold left those bays full for good, and you couldn't launch a design with fewer bays. | Her captain can sell crates whose owner isn't here, crediting the owner's purse: "Sold Bo's Grain for them: 27 crowns." Mail still can't be sold (`test_the_captain_sells_crates_left_by_an_absent_owner_for_them`). |
| Anyone aboard your ship at a dock could dismiss the hands you paid for. | Only her captain can, or anyone aboard a ship that's nobody's: "Only her captain can let her crew go." (`test_only_her_captain_dismisses_her_hands`). |
| (Minor, re-graded by effect.) The town panel rebuilt its rows twice a second while a repairer walked, so clicks were lost. | The panel's summary leaves out where hands stand (`test_the_town_holds_still_while_a_repairer_walks`). |

**Save timing.** On the Radeon 680M (`--gpu-index 0`, a solo world, five saves each): with the starter ship, 1.3–1.7 ms; with a 1,500-block ship added (1,802 blocks), 5.0–6.2 ms. That's well under 50 ms, so no save thread is needed.

**Tests.** The whole suite passed three runs in a row before the review (537 tests), and again after the fixes (545 tests).

**Deferred (minor, from the final review):**
- One pirate counts toward every bounty a player holds, so three one-pirate bounties pay 750 for one pirate. Two salvage or scouting contracts for the same target both pay too.
- A board drawn before its wreck was stripped still offers salvaging her, and that contract can never complete.
- `SaveGame.rename` overwrites a saved guest's account if the host's new name is that guest's.
- A returning captain's ship is restored where she was, without the launch's clear-spot check, so she can overlap a ship launched there since.
- Save-file hardening: a huge clock (e.g. 1e18) freezes the world clock; the map PNG is decoded before its 128 × 128 size is checked; ship places are only checked as finite.
- "Start over" doesn't clear the slot: its summary shows the old game until the new one saves, and the old hand-made save can become a fallback.
- The README and spec say a lost ship's crew wake on the quay at once; in co-op a guest boards another ship (her successor, the one they came from, their own, or the host's) when there is one.
- Wording: "Your hold has room for 0 crates." when you're ashore; "Launched for 0 crowns." against the yard's "Launch · free".
