# Stage 3: Online Co-op Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two players crew one ship over Wi-Fi, smooth and in sync. Games on the LAN appear in a list. Disconnects, version mismatches and full games are handled. A dedicated server runs headless. A two-process test proves two players can share a ship on a server running in its own process.

**Architecture:**
- **The server flies.** Only the server (solo, host or dedicated) simulates ships. On clients a ship is a frozen, kinematic copy (`Ship.simulated = false`) that follows the server's snapshots.
- **`WorldSync`** (one node per world, `World/Sync`) carries all world traffic:
  - ship snapshots at 30 Hz;
  - crew positions in ship space, reported by each player and passed on by the server;
  - station requests, which the server decides;
  - the pilot's helm keys.
- **Clients draw the past.** Clients draw ships and other crew 100 ms in the past. `SnapshotBuffer` gives each one a Hermite curve through its snapshots, using their velocities, and up to 250 ms of dead reckoning when packets are late.
- **Each player walks their own crew member** in their own copy of the ship's interior (client-authoritative movement, spec §4.3). Everyone else is drawn as a `CrewAvatar`.
- **Stations belong to peers.** `Helm.pilot` is a peer id. The local player asks the helm for it. On the server the helm answers at once. On a client it emits `asked`, `WorldSync` forwards the request, and the server checks reach against where that player last said they were.
- **Session gains a lobby, LAN discovery and a dedicated server.**
  - `sailing`: players gather in a lobby until the host sets sail, and anyone joining later goes straight into the world.
  - A `LanBeacon` answers LAN queries.
  - `--server` hosts with no player of its own.
- **Joining only once the world is loaded.** Only peers whose world is loaded get world traffic. A client's `WorldSync` says `_enter_world` when it's ready, and the server replies with the ships.

**Tech Stack:** Godot 4.7.2 (standard build, `~/.local/bin/godot`), statically typed GDScript, ENet through SceneMultiplayer, `PacketPeerUDP` for discovery, and the existing headless test runner.

**Spec:** `docs/superpowers/specs/2026-09-29-skywright-design.md` (stage 3 in §5; sessions in §4.3; networking in §4.6; errors in §7).

## Global Constraints

- Godot 4.7.2 standard build, and GDScript with static types everywhere. No addons or other dependencies.
- ENet over UDP on port 24650. LAN discovery on UDP port 24651. Up to 8 players.
- Channels: 0 reliable for events, 1 unreliable-ordered for ship snapshots, 2 unreliable-ordered for crew movement and helm keys.
- Ship snapshots and crew at 30 Hz. Clients draw 100 ms in the past and extrapolate at most 250 ms.
- The server is authoritative for ships and stations. Clients send inputs: station requests, helm keys, and their own crew member's movement.
- Everything a peer receives from another machine is untrusted: the server checks every client message, clients check ship blocks, and the LAN browser checks every answer.
- Player names are trimmed and capped at 24 characters. An empty name becomes "Captain".
- Error messages follow spec §7 word for word where it gives them.
- Tests use ports 20000–29999, below the ephemeral range.
- Commit messages never include a `Co-Authored-By` line (user rule).

## Review Focus

1. **Joining a ship that is already under way** (far from the start, at speed): the joiner gets the ship where it is now and stands aboard it, not at the start. Test: `test_a_late_joiner_boards_the_ship_where_it_is` (Task 5).
2. **Two players pressing E at the helm in the same instant:** exactly one gets it, and the other sees who has it. Tests: `test_one_pilot_at_a_time_and_a_clean_handover`, `test_two_players_asking_at_once_get_one_pilot` (Task 7).
3. **The pilot's connection dropping mid-turn:** the helm is freed, the rudder centres, and anyone else can take it. Test: `test_a_pilot_who_drops_frees_the_helm` (Task 8).
4. **The host crashing or being killed** (no goodbye): clients are back in the menu within about 8 s with "Lost the connection to the host." Test: `test_a_client_notices_a_host_that_goes_silent` (Task 1).
5. **Junk from the network** (a modified client sending NaN, far-away positions or out-of-range helm keys; junk LAN packets; bad ship blocks from a host): it's ignored, nothing crashes, and nobody else sees it. Tests: `test_the_server_ignores_crew_reports_that_make_no_sense`, `test_helm_keys_from_anyone_but_the_pilot_are_ignored` (Tasks 6–7), `test_the_browser_ignores_junk` (Task 3), `test_from_blocks_refuses_bad_ships` (Task 5).

---

## What prototyping settled before this plan

| Question | Answer |
|---|---|
| Can a client's copy of a ship just be moved? | Yes. A `RigidBody3D` with `freeze = true` in `FREEZE_MODE_KINEMATIC`, moved by setting `global_transform` each physics tick, reports the velocity it's moved at in `linear_velocity` under Jolt. The helm readout works on clients unchanged. Setting `linear_velocity` on it does nothing. |
| Does `rpc_id(1, …)` work in a solo game? | Yes. With the `OfflineMultiplayerPeer`, the unique id is 1, and `call_local` RPCs to 1 run locally with sender 1. It isn't needed, though: solo requests go straight to the helm. |
| Can two programs on one machine both listen for LAN broadcasts on 24651? | **No.** Godot doesn't set `SO_REUSEADDR`, so the second `bind` fails (`ERR_UNAVAILABLE`, no error logged). Broadcasts to 255.255.255.255 do loop back to this machine. So discovery is **query and answer**. A browser binds any free port (`bind(0)` works) and broadcasts a query to 24651, and each host replies straight to it. Any number of browsers can then run on one machine. |
| What happens when joining an unknown host name? | `ENetMultiplayerPeer.create_client` fails with `ERR_CANT_CREATE` and logs two engine errors. `IP.resolve_hostname` returns `""` quickly, with no error. So `Session.join` resolves first and returns `ERR_CANT_RESOLVE`. |
| Is `bytes_to_var` safe on junk? | It never crashes, but it can decode junk into nonsense (`true`), or log an engine error. So discovery packets start with a magic prefix, and only a packet with the prefix is decoded. |
| How does a headless server stop on `SIGTERM` (for example `systemctl stop`)? | Immediately, with no notification, so it can't say goodbye. Clients therefore detect silence: the ENet timeout drops a silent peer after `Session.DROP_AFTER` (8 s) instead of ENet's default 30 s. |
| How big is a LAN answer? | 160 bytes with a 24-character name. Queries are padded to 256 bytes, and an answer is never sent if it would be bigger, so a host can't be used to amplify traffic. |

## Where this stage departs from the spec

The spec is updated to match in Task 10.

| Spec | This stage | Why |
|---|---|---|
| §4.6: "the host announces its name, player count, protocol and port once a second" | Browsers broadcast a query to 24651 once a second, and hosts answer. | Only one program per machine can bind 24651, so with announcements a second copy on the same machine couldn't see any games. |
| §3.8: friends "crew the host's ship or fly their own alongside it" | Everyone crews the host's one ship. | Players get ships of their own from the shipyard (stage 4). |
| §7: "A player drops: their stations are freed and their ship anchors in place" | Stations are freed. The shared ship anchors (held still, throttle 0, autopilot off) when the last player leaves a dedicated server. | There are no player-owned ships yet. A dedicated server with nobody aboard would otherwise let the ship drift off in the wind for hours. |
| §4.6: "ship spawned (with compressed blueprint and damage)" | Blocks are sent uncompressed, as `[x, y, z, type, rotation, hp]`. | The starter ship is about 10 KB. Compress it when stage 4 allows 4,000-block ships. |
| §4.5: other crew | Crew don't collide with each other. Each machine walks only its own crew member; everyone else is drawn. | Server-side crew bodies arrive with combat (stage 6), where hits need them. |
| (not in the spec) | A lobby before setting sail. Late joiners go straight into the world. | The Build Log asks for a lobby screen. |
| (not in the spec) | A connection that goes silent for 8 s counts as lost. | ENet's default is 30 s, too long to sit in a frozen world. |
| §4.7: time of day | The world clock is seconds since the server's world began. The day–night cycle and client interpolation both run on it. | Everyone sees the same sky. Wind is still computed only on the server, so it needs no clock sync. |

## Protocol (version 2)

Every world RPC lives on `WorldSync` (`World/Sync`), so there's one place to validate them.

| RPC | Direction | Channel | Payload | Receiver checks |
|---|---|---|---|---|
| `_enter_world` | client → server | 0 reliable | — | the sender is on the roster and not already in the world |
| `_world` | server → client | 0 reliable | `time`, `[[id, blocks, transform, pilot], …]` | `ShipGrid.from_blocks` validates blocks; entries are shape-checked |
| `_ships` | server → clients | 1 unreliable-ordered | `time`, `[[id, position, rotation, velocity, spin, throttle, rudder, trim, autopilot, target_heading, target_altitude], …]` | only the server can call it; entry shape |
| `_crew_report` | client → server | 2 unreliable-ordered | `ship id, position, velocity, yaw, pitch` | sender in the world; the ship exists; all values finite; speed ≤ 50 m/s; position within 35 m of the ship's blocks |
| `_crew_moved` | server → clients | 2 unreliable-ordered | `peer, ship id, time, position, velocity, yaw, pitch` | only the server can call it; the peer is on the roster |
| `_helm_keys` | client → server | 2 unreliable-ordered | `ship id, throttle, rudder, climb` | the sender is that helm's pilot; values are finite, then clamped to −1…1 |
| `_request` | client → server | 0 reliable | `ship id, "helm" or "autopilot", on` | the sender is in the world; for the helm: aboard that ship and in reach (reach plus 0.5 m slack); for the autopilot: the pilot |
| `_pilot` | server → clients | 0 reliable | `ship id, peer` | only the server can call it |
| `Session._sail` | host → clients | 0 reliable | — | a client that was accepted |
| `Session._welcome` | host → joiner | 0 reliable | `roster, sailing` | as in stage 1 |

LAN discovery (UDP 24651, outside ENet):
- A query is `SKYWRIGHT?` padded with zeros to 256 bytes.
- An answer is `SKYWRIGHT!` followed by `var_to_bytes({"id", "name", "players", "max", "version", "port"})`, and is at most 256 bytes.

---

## File structure

| File | Responsibility |
|---|---|
| `src/net/session.gd` | Lobby (`sailing`, `set_sail`, `sailed`), dedicated server, LAN beacon while hosting, drop timeout, resolving names, re-hosting, §7 wording, protocol 2 |
| `src/net/lan_beacon.gd` | `LanBeacon`: answers discovery queries with the game's details |
| `src/net/lan_browser.gd` | `LanBrowser`: asks once a second and lists the games that answer |
| `src/net/snapshot_buffer.gd` | `SnapshotBuffer`: timed samples and Hermite interpolation with capped extrapolation |
| `src/net/world_sync.gd` | `WorldSync`: world entry, ship snapshots, the clock, crew reports and avatars, stations and helm keys |
| `src/core/settings.gd` | `clean_name` also turns C1 controls and Unicode line and paragraph separators into spaces |
| `src/core/launch_options.gd`, `src/core/game.gd` | `--server`, and the world loads when the session sets sail |
| `src/ship/ship_grid.gd` | `to_blocks()`, `from_blocks()` with validation, `bounds()` |
| `src/ship/ship.gd` | `simulated`, and `crew_spawn(slot)` |
| `src/crew/helm.gd` | `pilot` is a peer id; `pilot_changed`, `asked`, `ask_helm`, `ask_autopilot`, `in_reach`, `REACH` |
| `src/crew/crew_avatar.gd` | `CrewAvatar`: body, visor and name tag |
| `src/crew/player_controller.gd` | Asks the helm instead of taking it; follows `pilot_changed`; draws itself with `CrewAvatar` |
| `src/ui/hud.gd` | Uses the world's session; `invite_text()`; "Bob is at the helm"; join and leave messages |
| `src/ui/main_menu.gd` | Lobby panel; LAN games list; message for unknown host names |
| `src/world/world.gd` | Finds its Session as a sibling; creates `WorldSync`; builds the player when the ship arrives; no player on a dedicated server |
| `src/world/world_sky.gd` | `hour_at(seconds)`; the world sets the hour from the shared clock |
| `tests/net_case.gd` | `NetCase`: branches with their own multiplayer and 3D world, sessions, worlds, ports |
| `tests/test_lan.gd`, `tests/test_snapshot_buffer.gd`, `tests/test_world_sync.gd`, `tests/test_two_games.gd`, `tests/test_menu.gd` | New tests |
| `README.md`, spec | Stage 3 status, lobby, LAN list, dedicated server, VPS notes |

---

### Task 1: Session follow-ups, messages and dropped connections

Build-log items:
- "Stage 1 review follow-ups: networking polish";
- part of "Handle disconnects, version mismatches and full games".

**Files:**
- Modify: `src/net/session.gd`, `src/core/settings.gd`, `src/ui/main_menu.gd`
- Create: `tests/net_case.gd`
- Test: `tests/test_session.gd` (now `extends NetCase`), `tests/test_settings.gd`, `tests/test_menu.gd`

**Interfaces:**
- Produces:
  - `Session.PROTOCOL_VERSION == 2`
  - `Session.DROP_AFTER := 8.0` and `var drop_after: float`
  - `Session.join()` returns `ERR_CANT_RESOLVE` for a name that doesn't resolve
  - `NetCase.make_branch(name) -> Node` (a `SubViewport` with its own 3D world and MultiplayerAPI), `make_session(name, script := SessionScript) -> SessionScript`, `free_port() -> int`, `host_and_join(host, client, guest_name := "Guest") -> bool`

- [ ] **Step 1: Move the multiplayer test helpers into `tests/net_case.gd`**, and make each branch a `SubViewport` with `own_world_3d`, so worlds in one process don't share physics. `test_session.gd` extends `NetCase`.
- [ ] **Step 2: Write the failing tests:**
  - `test_rehosting_straight_after_leaving_works`: host with a guest, `leave()`, then `host()` on the same port returns `OK`.
  - `test_joining_an_unknown_host_name_fails_straight_away`: `join("Guest", "no-such-host.invalid")` returns `ERR_CANT_RESOLVE`, the mode stays `NONE`, and no engine errors are logged.
  - `test_host_refuses_a_different_version`: the message is exactly `"This game is version 2; you have version 3."`.
  - `test_host_refuses_when_full`: with `max_players = 2` and one guest in, the next joiner gets exactly `"The game is full (2 players)."`.
  - `test_a_client_notices_a_host_that_goes_silent`: set `client.drop_after = 1.0`, set `get_tree().multiplayer_poll = false`, and poll only the client by hand. It ends with `"Lost the connection to the host."` within 4 s.
  - `test_clean_name_turns_unicode_line_breaks_into_spaces` (in `test_settings.gd`): `"Ann Bob\u0085Cy Di\u007f"` becomes `"Ann Bob Cy Di"`.
  - `test_an_unknown_host_name_says_so` (in `test_menu.gd`): the join panel shows `Couldn't find "no-such-host.invalid". Check the address.`
- [ ] **Step 3: Run `./run_tests.sh session`, `./run_tests.sh settings` and `./run_tests.sh menu`.** Expected: the new tests fail.
- [ ] **Step 4: Implement:**
  - Keep the lingering socket in `_lingering`, and close it at once when a new session starts.
  - Resolve names with `IP.resolve_hostname` before `create_client`.
  - Update the §7 wording.
  - In `_on_peer_connected`, set each ENet peer's timeout to `drop_after` (`set_timeout(32, ms, ms)`), on both the host and the client.
  - `clean_name` also turns 0x7F–0x9F, U+2028 and U+2029 into spaces.
  - The menu maps `ERR_CANT_RESOLVE` to its message.
- [ ] **Step 5: Run the whole suite.** Expected: everything passes.
- [ ] **Step 6: Commit** "Close a lingering socket before hosting again, resolve names first, drop silent peers after 8 s, and use the spec's messages".

### Task 2: The lobby

Build-log item: "Host and join by address, with a lobby screen".

**Files:**
- Modify: `src/net/session.gd`, `src/core/game.gd`, `src/ui/main_menu.gd`, `src/ui/hud.gd`
- Test: `tests/test_session.gd`, `tests/test_menu.gd`

**Interfaces:**
- Produces:
  - `Session.sailed` signal
  - `Session.sailing: bool`
  - `Session.set_sail()`, for the host only
  - `_welcome(roster, sailing)`
  - `Game` loads the world on `sailed`, not `started`
  - `Hud.invite_text(port: int) -> String` (static)

- [ ] **Step 1: Write the failing tests:**
  - `test_solo_sails_straight_away`.
  - `test_setting_sail_takes_the_crew_to_the_world`: host and guest are both in the lobby (`sailing` false); after `host.set_sail()`, both emit `sailed`.
  - `test_late_joiners_go_straight_to_the_world`.
  - `test_a_guest_cannot_set_sail`.
  - `test_hosting_opens_the_lobby` (menu): the crew list shows "Ann (host)", "Set sail" is visible, and after a guest joins the list shows both.
  - `test_joining_shows_the_lobby_and_waits_for_the_host` (menu).
- [ ] **Step 2: Run them.** Expected: they fail.
- [ ] **Step 3: Implement:**
  - In `Session`: `sailing`, `set_sail`, `_sail`, and `sailed` from solo.
  - In `Game`: connect `sailed` to the world, and remove the `started` handler.
  - In the menu: a lobby panel with the crew list, the invite text (host), "Set sail" (host) or "Waiting for the host to set sail…" (guest), and "Leave". Esc leaves.
  - Move the address text out of `Hud._status_text` into `Hud.invite_text`.
- [ ] **Step 4: Run the whole suite.** Expected: it passes.
- [ ] **Step 5: Commit** "Gather in a lobby until the host sets sail".

### Task 3: LAN discovery

Build-log item: "LAN discovery: games on your Wi-Fi appear in a list".

**Files:**
- Create: `src/net/lan_beacon.gd`, `src/net/lan_browser.gd`
- Modify: `src/net/session.gd` (a beacon while hosting; `discovery_port`), `src/ui/main_menu.gd` (the games list in the join panel; `lan_port` for tests)
- Test: `tests/test_lan.gd`, `tests/test_menu.gd`

**Interfaces:**
- Produces:
  - `LanBeacon.new(port := DISCOVERY_PORT)`, with `info: Dictionary`, `DISCOVERY_PORT`, `QUERY_SIZE` and `static query() -> PackedByteArray`
  - `LanBrowser.new(port := LanBeacon.DISCOVERY_PORT)`, with `signal changed`, `games: Dictionary` (id -> `{address, port, name, players, max, version}`), `forget_after: float` and `static read_answer(packet) -> Dictionary`
  - `Session.discovery_port`
  - `Session.game_name`

- [ ] **Step 1: Write the failing tests:**
  - `test_a_browser_finds_a_host`.
  - `test_hosting_answers_with_the_crew_count`: 1/8, then 2/8 once a guest joins.
  - `test_the_browser_ignores_junk`: wrong magic, a non-dictionary, wrong types, out-of-range ports; a name needing cleaning is cleaned; no engine errors.
  - `test_answers_are_never_bigger_than_queries`: short queries get no answer.
  - `test_games_that_stop_answering_drop_off_the_list`.
  - `test_two_hosts_on_one_machine_both_host`.
  - `test_the_join_panel_lists_games_on_the_network` (menu): a button reading "Ann's game   1/8"; a game on another version is disabled and says so.
- [ ] **Step 2: Run them.** Expected: they fail.
- [ ] **Step 3: Implement** `LanBeacon`, `LanBrowser`, the beacon in `Session.host` (freed in `_reset`, with its info refreshed on roster changes), and the join panel list.
- [ ] **Step 4: Run the whole suite.** Expected: it passes.
- [ ] **Step 5: Commit** "List games on the local network".

### Task 4: Snapshot interpolation

Build-log item, first half: "Host runs ship physics; other players see smoothly interpolated ships".

**Files:**
- Create: `src/net/snapshot_buffer.gd`, `tests/test_snapshot_buffer.gd`

**Interfaces:**
- Produces:
  - `SnapshotBuffer.push(time: float, position: Vector3, velocity: Vector3, rotation: Quaternion, spin := Vector3.ZERO)`
  - `sample(time: float) -> Dictionary` (`{"position", "velocity", "rotation"}`)
  - `is_empty() -> bool`
  - `EXTRAPOLATE := 0.25`, `KEEP := 1.0`

- [ ] **Step 1: Write the failing tests:**
  - samples hit the snapshots exactly;
  - steady motion interpolates exactly;
  - a curve's midpoint follows its velocities;
  - rotations slerp;
  - extrapolation stops after 0.25 s, and spins the rotation;
  - before the first sample, the first is returned;
  - samples that are late or out of order are ignored;
  - old samples are dropped.
- [ ] **Step 2: Run them.** Expected: they fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them.** Expected: they pass.
- [ ] **Step 5: Commit** "Add Hermite snapshot interpolation with capped extrapolation".

### Task 5: Ships in sync

Build-log item: "Host runs ship physics; other players see smoothly interpolated ships".

**Files:**
- Create: `src/net/world_sync.gd`, `tests/test_world_sync.gd`
- Modify:
  - `src/ship/ship_grid.gd`, `src/ship/ship.gd`, `src/crew/helm.gd` (clients don't steer);
  - `src/world/world.gd`, `src/world/world_sky.gd`, `src/ui/hud.gd` (the session comes in);
  - `tests/net_case.gd` (`add_world`, `solo_world`, `play`), `tests/test_ship_grid.gd`, `tests/test_world.gd`, `tests/test_scenes.gd`, `tests/test_sky.gd`

**Interfaces:**
- Consumes: `SnapshotBuffer`, `Session.sailing`
- Produces:
  - `ShipGrid`: `to_blocks() -> Array`, `static from_blocks(data: Variant) -> ShipGrid` (null when invalid), `bounds() -> AABB`, `MAX_BLOCKS := 4000`
  - `Ship.simulated := true`, and `Ship.crew_spawn(slot := 0)`
  - `WorldSync.new(session)`, with `signal ship_added(ship)`, `ships: Dictionary` (id -> Ship), `add_ship(grid, at: Transform3D) -> Ship` (server), `now() -> float`, `SEND_EVERY := 2`, `DELAY := 0.1`
  - `World`: `session`, `sync`, `ship`, `player`, `hud`
  - `WorldSky.hour_at(seconds) -> float`
  - `NetCase.add_world(session) -> Node3D`, `solo_world() -> Node3D`, `play(seconds, each_tick := Callable())` (real-time ticks)

- [ ] **Step 1: Write the failing tests:**
  - `test_to_blocks_and_back`, and `test_from_blocks_refuses_bad_ships` (not an array, empty, too many, unknown type, coordinates out of −64…63, a float coordinate, rotation 24, hp 0 or above the block's, a duplicate cell, no helm).
  - `test_a_joining_client_gets_the_ship`: same block count and mass; kinematic and not simulated; within 1 m of the host's.
  - `test_the_client_sees_the_ship_fly_smoothly`: at full throttle for 3 s, the client's ship is within 5 cm of where the host's was at the client's draw time, and no tick's step is more than twice the median step.
  - `test_the_client_sees_the_helm_readout`: throttle, trim and the autopilot come through.
  - `test_a_late_joiner_boards_the_ship_where_it_is`: after the host has flown 20 s.
  - `test_everyone_sees_the_same_time_of_day`.
  - `test_the_world_has_a_ship_and_you_aboard_in_solo`: replaces the stage 2 world tests, now built on a solo session.
- [ ] **Step 2: Run them.** Expected: they fail.
- [ ] **Step 3: Implement:**
  - `ShipGrid` serialisation and validation.
  - `Ship.simulated`: frozen and kinematic on clients, with no forces.
  - `Helm._physics_process` does nothing on clients.
  - `WorldSync`: world entry, snapshots, the clock, and following the snapshots.
  - `World`: the session sibling, the sync, the starter ship on the server, and the player built when the ship arrives.
  - The sky hour comes from `sync.now()`.
- [ ] **Step 4: Run the whole suite.** Expected: it passes.
- [ ] **Step 5: Commit** "Fly ships on the server and draw them smoothly on clients".

### Task 6: Crew in sync

Build-log item: "Sync crew movement in ship space so deck-walking looks right to everyone".

**Files:**
- Create: `src/crew/crew_avatar.gd`
- Modify: `src/net/world_sync.gd`, `src/crew/player_controller.gd`, `src/world/world.gd`
- Test: `tests/test_world_sync.gd`

**Interfaces:**
- Produces:
  - `CrewAvatar.new(label := "")`, with `look(pitch)`
  - `WorldSync.player: PlayerController`
  - `WorldSync.avatar_of(peer) -> CrewAvatar`

- [ ] **Step 1: Write the failing tests:**
  - `test_crew_walk_where_everyone_sees_them`: the client walks forward for 1 s, and the host's avatar for them ends within 0.15 m of the client's crew position (in ship space) after the delay. The reverse direction also works.
  - `test_players_board_at_different_spots`.
  - `test_the_server_ignores_crew_reports_that_make_no_sense`: NaN, 100 m from the ship, 500 m/s, an unknown ship, and a peer not in the world.
- [ ] **Step 2: Run them.** Expected: they fail.
- [ ] **Step 3: Implement:**
  - Clients report at 30 Hz.
  - The server validates, records, relays (stamped with its own receive time) and shows remote crew.
  - Avatars are placed each frame at the ship's interpolated transform times the buffered local transform.
  - Spawn slots come from the roster order.
  - `PlayerController` draws itself with `CrewAvatar`.
- [ ] **Step 4: Run the whole suite.** Expected: it passes.
- [ ] **Step 5: Commit** "Share crew positions in ship space".

### Task 7: Stations

Build-log item: "Stations: one player each, handed over cleanly".

**Files:**
- Modify: `src/crew/helm.gd`, `src/crew/player_controller.gd`, `src/net/world_sync.gd`, `src/ui/hud.gd`
- Test: `tests/test_helm.gd`, `tests/test_player.gd`, `tests/test_world_sync.gd`

**Interfaces:**
- Produces:
  - `Helm.pilot: int` (0 = nobody)
  - `signal pilot_changed`, `signal asked(what: String, on: bool)`
  - `take(peer: int) -> bool`, `leave(peer: int)`, `ask_helm(peer: int, on: bool)`, `ask_autopilot(peer: int, on: bool)`
  - `in_reach(where: Vector3, slack := 0.0) -> bool`, `REACH := 1.8`
  - `PlayerController.helm_in_reach() -> bool`

- [ ] **Step 1: Write the failing tests:**
  - Helm tests with peer ids.
  - `test_one_pilot_at_a_time_and_a_clean_handover`: the client takes the helm; the host is refused and sees "Guest is at the helm"; the client's keys throttle the host's ship; the client leaves and the rudder centres; the host takes it.
  - `test_two_players_asking_at_once_get_one_pilot`.
  - `test_a_client_out_of_reach_cant_take_the_helm`.
  - `test_helm_keys_from_anyone_but_the_pilot_are_ignored`.
  - `test_the_autopilot_answers_only_the_pilot`.
- [ ] **Step 2: Run them.** Expected: they fail.
- [ ] **Step 3: Implement:**
  - `Helm` with peer ids.
  - `PlayerController` asks the helm and follows `pilot_changed`.
  - `WorldSync` forwards requests, decides them on the server, broadcasts `_pilot`, and sends and applies helm keys.
  - The HUD shows who's at the helm.
- [ ] **Step 4: Run the whole suite.** Expected: it passes.
- [ ] **Step 5: Commit** "Claim stations through the server, one player each".

### Task 8: Players coming and going

Build-log item: "Handle disconnects, version mismatches and full games" (the rest).

**Files:**
- Modify: `src/net/world_sync.gd`, `src/ui/hud.gd`
- Test: `tests/test_world_sync.gd`

- [ ] **Step 1: Write the failing tests:**
  - `test_a_pilot_who_drops_frees_the_helm`: the helm is freed, the rudder centres, and the avatar is gone.
  - `test_the_hud_says_who_comes_and_goes`: "Guest came aboard." and "Guest left.".
- [ ] **Step 2: Run them.** Expected: they fail.
- [ ] **Step 3: Implement:**
  - On roster changes, the server forgets peers who left and frees their stations.
  - Everyone drops their avatars.
  - The HUD compares the old and new rosters.
- [ ] **Step 4: Run the whole suite.** Expected: it passes.
- [ ] **Step 5: Commit** "Free a dropped player's stations and say who comes and goes".

### Task 9: Dedicated server

Build-log item: "Dedicated server mode for hosting on a VPS".

**Files:**
- Modify: `src/core/launch_options.gd`, `src/core/game.gd`, `src/net/session.gd` (`host(name, port, dedicated)`), `src/world/world.gd`, `src/net/world_sync.gd` (anchor when empty)
- Test: `tests/test_launch_options.gd`, `tests/test_session.gd`, `tests/test_world_sync.gd`

- [ ] **Step 1: Write the failing tests:**
  - `test_reads_server` (launch options).
  - `test_a_dedicated_server_has_no_player_of_its_own`: an empty roster; sailing; a joiner is the only player; the game is full at `max_players` joiners.
  - `test_a_dedicated_world_has_a_ship_and_nobody_aboard`: no player or HUD; the ship is anchored until someone joins, and again after they leave (throttle 0, autopilot off).
- [ ] **Step 2: Run them.** Expected: they fail.
- [ ] **Step 3: Implement:**
  - `--server` hosts as dedicated, caps the frame rate at the physics rate, and quits with an error if the port is taken.
  - The world skips the player, HUD and pause menu.
  - `WorldSync` anchors ships while the roster is empty.
- [ ] **Step 4: Run the whole suite.** Expected: it passes.
- [ ] **Step 5: Commit** "Run a dedicated server with --server".

### Task 10: Two game instances, README and spec

Build-log item: "Test: two game instances playing together on one machine".

**Files:**
- Create: `tests/test_two_games.gd`
- Modify: `README.md`, the spec

- [ ] **Step 1: Write the test:**
  - It starts a dedicated server with `OS.create_process(OS.get_executable_path(), ["--headless", "--quiet", "--path", <project>, "--", "--server", "--port=P"])`.
  - Ann and Bob join from this process, each in their own branch.
  - Ann takes the helm and opens the throttle. Bob is refused while she holds it.
  - Both see the ship move forward, within 0.5 m of each other, and see each other's avatars.
  - Ann leaves the helm and Bob takes it.
  - Both leave, and the server is killed in `after_each`.
- [ ] **Step 2: Run it** until it passes three times in a row.
- [ ] **Step 3: Update the README:**
  - the status;
  - the lobby and the LAN list in "Play with friends";
  - a "Dedicated server" section: the command, UDP 24650 and 24651, forwarding or a firewall rule, and stopping with Ctrl+C;
  - the controls, unchanged.
- [ ] **Step 4: Update the spec:**
  - §4.6: discovery by query and answer; the world clock.
  - §7: the drop timeout.
  - §9: decisions.
- [ ] **Step 5: Run the whole suite three times, and check two windows by hand:** `--host` and `--join`, set sail, walk, and hand over the helm.
- [ ] **Step 6: Commit** "Test two players on a dedicated server in another process; update README and spec for stage 3".

---

## Playtest checklist

1. **Lobby:** host, join from a second copy (from the LAN list and by typing the address), and set sail. Do both arrive aboard, at different spots?
2. **Walking together:** walk around each other on the deck while the ship turns. Does the other player glide smoothly, stay on the deck, and never slide or stutter?
3. **The helm:** one player takes it; the other sees "Ann is at the helm". Hand it over. Does the ship respond to the new pilot at once?
4. **Flying as a passenger:** at full speed through a turn, does the ship look smooth from the deck and in the chase view (no jitter at 60 Hz or 144 Hz)?
5. **Drop a player:** close the pilot's window. Is the helm freed within 8 s, and does the other player see "Bob left."?
6. **Kill the host:** does the guest get "Lost the connection to the host." within about 8 s?
7. **Dedicated server:** `godot --headless --path . -- --server`, then two copies join it by the LAN list.
8. **Wi-Fi:** two laptops on the same Wi-Fi. Is it smooth? Does the LAN list find the game?

---

## Changes during execution and after the final review

A fresh reviewer read the whole branch and gave the verdict "with fixes": no critical findings and one important one. Every fix below has a test that failed first:

| Problem | Fix | Test |
|---|---|---|
| Guests hear of each other through the host's relay, and had no ENet connection to set a timeout on. | SceneMultiplayer's server relay is off: guests only ever talk to the host. | `test_two_players_asking_at_once_get_one_pilot` |
| With exactly `max_players` ENet connections, a dedicated server's ENet refused the next joiner before the host could say "The game is full". | Servers open one spare connection. | `test_a_dedicated_server_has_no_player_of_its_own` |
| Leaving and hosting again at once couldn't list the game: the old beacon held the discovery port until the end of the frame. | The beacon is freed at once. | `test_hosting_again_straight_after_leaving_is_found` |
| A guest's world lives one frame past its session and sent an RPC to itself. | `WorldSync` does nothing once its session has ended. | the sync tests' error counts |
| Two players leaving in one poll: telling others about the first sent to the second's dead connection (seen in the server's log in `test_two_games`). | The roster broadcast after a leave, and freeing the leaver's stations, wait for the end of the frame. | `test_guests_leaving_together_are_both_dropped_cleanly`, `test_a_pilot_and_a_guest_leaving_together_are_dropped_cleanly` |
| Review: a pilot whose game hangs or whose Wi-Fi dies kept steering with their last keys until the connection counted as lost (8 s). | The server lets go of a remote pilot's keys after 0.25 s without any. | `test_a_pilot_who_goes_silent_stops_steering` |

**Found about the test runner:** under `--fixed-fps 60`, Godot's frame cap does nothing, so frames run as fast as they can (spec §6 said otherwise; corrected). `NetCase.play()` and `play_until()` pace ticks in real time, which the two-process test needs.

**Moved:** `ShipGrid.bounds()` and `Ship.crew_spawn(slot)` were built in Task 6, where they're first used. The server is started with `OS.execute_with_pipe` so the test can wait for it and check its log.

**Deferred:**
- A malicious host can send a degenerate ship basis. It passes `is_finite()` and logs one engine error.
- The worst-case LAN answer is 254 of 256 bytes. A longer name or one more field would drop long-named games from lists without a word.
- `--join=` ignores a failed join (no log for a mistyped host name).
- Resolving a host name blocks the game on slow DNS, and Godot caches the answer for the whole run.
- Full games can be clicked in the LAN list (the host then refuses), and rebuilding the list drops keyboard focus.
- Pressing H twice within about 100 ms on a guest's machine sends "on" twice.
- Truncated data after the LAN magic prefix logs an engine error.
- `tests/run_tests.gd` sets `Engine.max_fps = 60`, which does nothing under `--fixed-fps`.
