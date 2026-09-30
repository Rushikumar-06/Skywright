# Skywright: design spec

- **Date:** 2026-09-29
- **Status:** Design parts 1–3 agreed in chat on 2026-09-29; this document consolidates them. Updated on 2026-09-30 with what stages 2, 3 and 4 settled.
- **Tracker:** [Skywright Build Log](https://claude.ai/artifact/N8W3J8xUU77JcdYdhcSZCx)

## 1. Summary

Skywright is a 3D airship game for desktop (Linux and Windows), built in Godot 4.7.2. Players design airships block by block, and real physics decides whether they fly. Players crew their ships on foot in first person and explore a generated archipelago of floating islands above a storm sea. There is a single-player campaign and online multiplayer (co-op and skirmish) between players on their own machines.

## 2. Goals

**What was asked for:** a full, structured game with single-player and multiplayer, not a small one, something new and big. The genre was left open. Multiplayer is online, with each player on their own device.

**Success looks like:**

1. The solo campaign plays from the Calm Reaches to the Eye.
2. A friend on another computer joins over Wi-Fi and a match plays smoothly.
3. A ship's behaviour visibly follows its design: lopsided ships lean, overloaded ships sink, and damage changes how a ship flies.
4. Builds run on Linux and Windows.

**Scale:** built in ten stages, and each stage ends playable. After one session the game won't have a studio game's content, but it is structured to keep growing.

## 3. Game design

### 3.1 World

The ground is gone under **the Roil**, a storm sea that fills everything below 200 m. People live on floating islands between 300 m and 1,800 m. The world is a disc 16 km across (radius 8,000 m) centred on the origin, and it gets more dangerous toward the centre. Distances below are the distance from the centre.

| Region | Distance | Character |
|---|---|---|
| Calm Reaches | 6,000–8,000 m | Light wind, trading towns, small pirate crews. The starting town is here. |
| Shattered Belt | 4,000–6,000 m | Dense broken islands, wrecks to salvage, pirate forts |
| Gale Expanse | 2,200–4,000 m | Sky rivers (fast wind currents), storm cells, leviathans |
| Stormwall | 1,600–2,200 m | A ring of violent storm. Crossing it needs a strong, well-built ship or a gap in a sky river. |
| The Eye | 0–1,600 m | The endgame region |

Beyond 8,000 m, rim winds push ships back inward (a soft boundary). The seed generates islands, towns, wrecks and winds, so each world is different. There is a day–night cycle.

### 3.2 Core loop

Build a ship at a shipyard, fly out, explore, take contracts (deliveries, bounties, salvage, scouting), fight, and earn money and new parts. Then rebuild a better ship and push further toward the Eye.

### 3.3 Ships and building

- **Grid:** ships are built on a 1 m grid. There's a limit of 4,000 blocks per ship, and every ship needs at least one helm.
- **Block catalogue:** frames, deck planks, iron and alloy plates, balloon cells, lift stones, engines, propellers, rudders and fins, sails, fuel tanks, ballast tanks, helm, cannons, cargo bays, bunks and ladders. Starting values are in §4.4.
- **Weight and forces:** every block has weight. Balloons and propellers push from where they're mounted. Wind and drag act on every exposed face.
- **Shipyard readouts:** weight, lift at the current altitude, thrust, estimated top speed and climb rate. Markers show the centre of mass against the centre of lift, with warnings such as "lists 8° to port" or "too heavy to hold altitude".
- **Cargo:** crates are stowed in cargo bays, and their weight counts where they're stowed.
- **Damage:** destroyed blocks are removed. Any section no longer connected to the helm's section breaks away as its own wreck, and a severed balloon floats away.
- **Shipyard:** until towns arrive (stage 5), the shipyard opens within 150 m of a placeholder dock at the start, which has a slipway for each player. Blocks are placed, removed, turned, tipped and mirrored, with undo and redo. Mirror mode makes every edit on both sides of the keel.
- **Test flights:** a design can be flown at once from the shipyard, with the designer at the helm, and returned from instantly. A test flight is a real ship that's removed when it ends.
- **Blueprints:** designs are saved as blueprints, which are shareable files.

### 3.4 Crew and stations

- Players walk the deck in first person, climb ladders and use stations: helm, cannon, engine and repair.
- At the helm, the camera can switch to a third-person chase view.
- The helm has an autopilot that holds heading and altitude, so a solo player can leave the helm to man a gun.
- AI crew hired in towns staff stations: gunner, engineer and repairer.
- Players can leave the ship on foot to explore islands, and glide back to it. A ship can be anchored so it stays put.

### 3.5 Threats and combat

- **Pirates:** ships built from the same blocks and flying on the same physics, with AI captains that chase, circle and fire broadsides.
- **Sky leviathans:** roaming giants in the Gale Expanse, plus one boss.
- **Weather:** storm cells bring lightning and turbulence.
- **Cannon ammunition:** round shot (block damage), chain shot (shreds balloons), explosive shells (area damage) and harpoons (tethering).
- **The Roil:** below 200 m a ship takes storm damage, and below 0 m it is lost. You keep the blueprint and can rebuild the ship at a shipyard for a price.

### 3.6 Economy and progression

- Money and inventory. Markets whose prices differ between towns make trade routes worthwhile.
- Contracts: deliveries, bounties, salvage and scouting.
- Part tiers: wood, then iron, then alloy. Balloons come first, then lift stones, which give strong lift that doesn't weaken with altitude.
- Blueprints and parts come from shipyards, wrecks and story progress.

### 3.7 Campaign

- The journey runs from the Calm Reaches to the Eye.
- Region progression is gated by ship capability. The Stormwall is the main gate.
- The story is told through logs found in ruins and towns.
- The Eye holds the final region, a boss and the ending.

### 3.8 Multiplayer

- **Co-op:** friends join the host's world and either crew the host's ship or fly their own alongside it (from stage 4, which brings ships of your own; in stage 3 everyone crews the host's ship). Each player has one ship and one test flight at a time, and a leaver's ships go with them. The world is saved on the host's machine.
- **Lobby:** the host's crew gather in a lobby until the host sets sail. Anyone who joins after that goes straight aboard.
- **Skirmish:** team ship battles on arena maps using your own blueprints, and sky-river races with checkpoints. Players can board enemy ships with grapple lines and fight with cutlass and pistol.
- **Size:** up to 8 players.

### 3.9 Presentation

- Stylized low-poly art, generated in code, with no external art assets.
- Warm light above the clouds, and a dark, lightning-lit storm below.
- Camera: first person on foot, and an optional chase camera at the helm.
- Sound is generated in code (see §4.9).

### 3.10 Not in the first version

- Fighting AI on foot: pirates don't board you, although players can board each other in skirmish.
- Trading between players.
- Finding games over the internet through matchmaking or relays. Internet play works by address with a port opened, or through a dedicated server.
- Controller support: planned for stage 10 if time allows.

## 4. Technical architecture

### 4.1 Engine and project settings

- Godot 4.7.2 (standard build) with GDScript, statically typed throughout. There are no other dependencies.
- Rendering: the Forward+ renderer (Vulkan).
- Physics: Jolt Physics, stepped at 60 ticks per second. It's set explicitly in `project.godot`, because the engine setting still reads `DEFAULT` in 4.7.2.
- Physics interpolation is on (SceneTree-based since 4.5), so motion renders smoothly at any frame rate.
- One unit is one metre, and gravity is 9.81 m/s².

### 4.2 Code layout

```
project.godot
run_tests.sh              imports the project, then runs every test headless
src/core/                 autoloads: Settings, Game (scene flow)
src/net/                  Session autoload (roles, handshake); later sync and LAN discovery
src/ship/                 blocks, grid, mass properties, forces, meshes, damage   (stage 2+)
src/crew/                 ship-space physics, player controller, stations        (stage 2+)
src/builder/              shipyard build mode                                     (stage 4)
src/world/                world scene; later generation, streaming, wind, Roil
src/combat/ src/ai/ src/economy/ src/campaign/ src/audio/ src/save/               (later stages)
src/ui/                   menus, HUD
tests/                    run_tests.gd, test_case.gd, test_*.gd
docs/superpowers/         specs and plans
```

Folders are created when their stage needs them, not ahead of time.

### 4.3 Sessions and authority

Every game runs a server. `Session` (an autoload) has four modes:

| Mode | Meaning |
|---|---|
| `NONE` | In the menus |
| `SOLO` | The server runs inside your game with no network. Your peer id is 1. |
| `HOST` | ENet server on UDP port 24650. You play as peer 1, and others join. |
| `CLIENT` | Connected to a host |

A dedicated server (stage 3) is `HOST` mode with no local player, started with `-- --server` and run with `--headless`. Its world starts at once, with no lobby, and it caps its frame rate at the physics rate. While nobody is aboard, it anchors its ships: held still, with the throttle at 0 and the autopilot off.

The server is authoritative for ships, blocks, damage, projectiles, AI, the world and the economy. Clients send inputs: station commands, plus their own character's movement (see §4.5).

**Handshake:** joining uses SceneMultiplayer's authentication step. A joiner isn't connected, and receives no RPCs, until the host accepts it.

1. The client sends its protocol version and name as plain bytes. That format stays readable whatever RPCs later versions add.
2. The host replies in one of two ways:
   - Accepted: both sides complete authentication. The host then sends `welcome` with the roster and broadcasts the new roster to everyone.
   - Refused, with the reason, for a version mismatch or a full game. Peers still joining count toward the limit. The host disconnects that client once the reason has been sent.
3. A joiner that never introduces itself is dropped after 5 s. If the whole join hasn't finished after 8 s, the client gives up with the message "The host didn't answer."

Player names are trimmed and capped at 24 characters. An empty name becomes "Captain".

### 4.4 Ships

**Data.** A ship is a `ShipGrid`: a dictionary from cell (`Vector3i`) to block `{type, rotation (0–23), hp}`, plus `paint`. There is one rigid body per ship (Jolt). Rotations are Godot's orthogonal index (the one GridMap uses), so 0 is the block as modelled, facing the bow.

**Starting catalogue values** (tuned in stages 2 and 4):

| Block | Mass kg | HP | Function |
|---|---|---|---|
| Frame (wood) | 60 | 100 | Structure |
| Deck plank (wood) | 40 | 80 | Walkable floor |
| Iron plate | 180 | 300 | Armour |
| Alloy plate | 110 | 260 | Light armour (late) |
| Balloon cell | 8 | 30 | 900 N lift × air density |
| Lift stone | 250 | 400 | 6,000 N lift, not affected by altitude |
| Engine | 300 | 200 | Powers propellers; burns fuel |
| Propeller | 50 | 60 | Up to 2,500 N thrust along its axis |
| Rudder / fin | 30 | 60 | Control surface |
| Sail | 20 | 40 | 6 m² of wind area |
| Fuel tank | 80 (+ fuel) | 120 | 200 fuel units |
| Ballast tank | 60 (+ up to 500 water) | 100 | Water that can be dropped |
| Helm | 80 | 150 | Pilot station; required |
| Cannon | 220 | 200 | Manned weapon |
| Cargo bay | 50 (+ cargo) | 100 | Holds crates |
| Bunk | 40 | 60 | Crew capacity and respawn point |
| Ladder | 15 | 40 | Climbable |

Sanity check: a starter ship with a 12 × 4 hull and about 5 t of blocks needs about 70 balloon cells to float at 800 m. That's an envelope about the size of the hull, which reads as an airship. Two propellers giving 5 kN reach about 27 m/s.

The stage 2 starter ship came out bigger: 8.9 t on a 5 × 13 m deck, with 127 balloon cells. Iron in the middle of its keel puts its weight right under its lift, so it floats level at 877 m. Its two propellers reach 20 m/s.

**Mass properties:**
- Total mass is the sum of the blocks.
- Centre of mass is the mass-weighted average of cell centres.
- Inertia is the diagonal of the summed point-mass-plus-cube tensor about the centre of mass.
- These are set on the body with a custom centre of mass and inertia, and recomputed whenever the grid changes.

> ponytail: only the diagonal of the inertia tensor is kept (Godot takes principal moments). Fine for mirror-symmetric ships. Rotate into principal axes if asymmetric ships feel wrong.

**Forces each physics tick** (at world position `p`, air density factor `ρ(h) = exp(−(h − 200) / 2500)` for h ≥ 200, and 1 below). Every constant is in `src/ship/tuning.gd`:
- **Balloon lift:** `900 N × ρ × trim` per cell. The pilot sets trim between 0.8 and 1.1, and trim above 1.0 burns fuel once fuel exists (stage 7). Lift stones give a fixed 6,000 N.
- **Thrust:** `throttle × engine power share × 2,500 N` per propeller, along its facing. One engine drives up to two propellers at full power. A propeller facing aft pushes the ship astern.
- **Drag:** cells are grouped into 4 × 4 × 4 zones. Each zone stores its exposed face area per local axis and its centre. Zone drag is `−½ × 1.2 × ρ × Cd × A_axis × |v_axis| × v_axis`, per local axis, with Cd 0.45. It uses the air-relative velocity at the zone centre: body velocity at that point minus the wind. Rotational damping falls out of this, and the body adds spin damping of 0.5 per second.
- **Keel:** each zone also pushes back against slipping sideways while it moves forward: `−½ × 1.2 × ρ × 8 × A_x × |v_forward| × v_side`, along the ship's x axis. It works the way a keel does in water. Without it a ship skids instead of turning. With it the starter ship turns at about 6°/s and keeps about two-thirds of its speed through a hard turn. It needs forward speed, so a hovering ship still drifts with the wind.
- **Control surfaces:** a rudder acts along its facing too. Side force `k × ρ × v_forward × |v_forward| × deflection`, where `v_forward` is the airflow along the ship, so a rudder works backwards going astern.
- **Gravity** is applied by the engine, at 9.81 m/s².

**Collision:** cells are merged into boxes with greedy meshing and added as box shapes on the body. A hit's shape index plus its local hit point identify the cell.

**Rendering:** one mesh per ship, with one surface per material. Stage 6 may split it into 16³ sections so a hit only rebuilds its section. Shaped blocks (propeller, rudder, sail, cannon, helm) are drawn as shapes but still collide and drag as cubes. Balloons are drawn as one cloth envelope.

**Break-apart:** after blocks are destroyed, a flood fill finds the connected components.
- The largest component that still contains a helm stays the ship.
- Every other component becomes a new wreck, with its own body, the velocity it had at that point, and its own mass properties.
- If no helm survives, the whole ship becomes a wreck that can't be steered.

**Physics guard:** a ship whose position or velocity becomes non-finite, faster than 400 m/s, or spinning faster than 20 rad/s is restored to its last good transform with zero velocity, and the event is logged.

### 4.5 Crew on moving decks

- **Interior world:** each ship owns an interior `SubViewport` with `own_world_3d = true`. That gives it a separate physics space; it's never rendered. The interior holds a static copy of the ship's collision boxes in ship-local coordinates, plus the `CharacterBody3D` of everyone aboard.
- **Gravity aboard:** crew gravity is `ship_basis⁻¹ × (0, −9.81, 0)`, and `up_direction` is its opposite. A tilted ship therefore feels like a sloped deck. Look yaw is relative to the ship, so you turn with it.
- **Drawing crew:** a crew member is drawn in the main world at the ship's interpolated transform multiplied by their local transform.
- **Leaving and boarding:** when no ship floor has been under your feet for 0.2 s and a downward ray in the main world doesn't hit this ship, you move to a main-world character. Your velocity is the ship's point velocity plus your own. Landing on any ship moves you into that ship's interior. This arrives with going ashore in stage 5. Until then, crew who fall 30 m below their ship are put back aboard where they started, and told so.
- **Walking in a tilted gravity:** walking "uphill" against gravity that isn't square to the deck makes Godot skip its floor snap, so crew apply the snap themselves (except when jumping or on a ladder). Ladders are open cells: while your body is in a ladder's column you hold on, gravity stops, and you climb along the ship's up.
- **Being hit:** each crew member also has a main-world hitbox (`Area3D`) so projectiles can hit them.
- **Other players:** each machine walks only its own crew member, in its own copy of the interior, and reports where it is (§4.6). Everyone else is drawn as an avatar with a name tag. Crew don't collide with each other until combat needs server-side crew bodies (stage 6).
- **Fallback:** if this approach fails its stage 2 check, crew become main-world characters that inherit platform velocity and yaw from the deck.

### 4.6 Networking

- **Transport:** ENet over UDP on port 24650. Up to 8 players. Guests only ever talk to the host (SceneMultiplayer's server relay is off). A connection silent for 8 s counts as lost (ENet's own default is 30 s), so a host that crashes or is killed is noticed quickly.
- **LAN discovery (UDP 24651):** query and answer. Once a second, a browser broadcasts a query (`SKYWRIGHT?` padded with zeros to 256 bytes) to port 24651, and to this machine. Each host answers the asker directly with `SKYWRIGHT!` and `var_to_bytes({id, name, players, max, version, port})`. An answer is never bigger than its query, so a host can't be used to multiply traffic, and every answer is checked. It's query and answer rather than announcements because only one program per machine can listen on 24651: a second game hosted on the same machine can be joined by address but isn't listed.
- **Channels:**
  - Channel 0 is reliable, for events.
  - Channel 1 is unreliable-ordered, for ship snapshots.
  - Channel 2 is unreliable-ordered, for crew movement and the pilot's helm keys.
- **The world clock:** seconds of physics since the server's world began. Snapshots carry it, and each client eases its own clock toward it. The day–night cycle and client interpolation both run on it, so everyone sees the same sky. Wind is still computed only on the server, so it needs no clock sync.
- **Who flies:** only the server simulates ships. On clients a ship is a frozen, kinematic copy that follows the snapshots, and no forces act on it.
- **Ship snapshots (30 Hz):** each carries `{ship id, position, rotation, linear velocity, angular velocity, throttle, rudder, trim, autopilot, target heading, target altitude}` at a server time. Clients render ships 100 ms in the past with Hermite interpolation between snapshots, and extrapolate up to 250 ms when packets are late.
- **Crew (30 Hz):** each client sends `{ship id, local position, velocity, yaw, pitch}` to the server. The server checks it (finite, at most 50 m/s, within 35 m of the ship's blocks), stamps it with its own clock and relays it to everyone else. Clients draw other crew 100 ms in the past, on their ship as it's drawn.
- **Stations:** a client asks the server for the helm. The server grants it only if the asker last reported standing aboard that ship within reach (1.8 m, plus 0.5 m of slack), and tells everyone who holds it. Only the pilot's helm keys are applied (clamped to −1…1), and only the pilot can switch the autopilot.
- **Events (reliable):** ship spawned (with compressed blocks, paint and damage), ship removed, blocks destroyed, ship split, projectile fired (`origin`, `velocity`, `type`, `server time`), projectile hit, station claimed or released, and economy changes. Every machine simulates a projectile's arc from its launch data, and only the server decides hits. 
- **Protocol 3 (stage 4):** `_ship_added` and `_ship_removed` carry ships that come and go mid-game, and `_world` sends every ship's entry `[id, blocks, paint, transform, pilot, captain, test]`. A client asks with `_launch(blocks, paint, test)` (at most one a second; the server checks the bytes) and ends a test with `_end_test`. A launch or a test replaces the player's last ship or test, and `_ship_removed` names the ship that takes over its crew. The server trusts a client to be at the dock until launching costs money (stage 7).
- **Block bytes:** two bytes of block count (`encode_u16`), then a zstd-compressed body of 7 bytes per block: `x + 64`, `y + 64`, `z + 64`, the type's index in `Tuning.BLOCKS`' key order, the rotation, and the hit points as `u16`. Reordering `Tuning.BLOCKS` changes the protocol.
- **Joining mid-game:** only peers whose world has loaded get world traffic. A client's world asks to enter when it's ready, and receives the world clock and every ship (blocks, damage, transform and pilot). Later stages add the world seed and the list of changes to the world. The crew roster comes with the handshake.
- **Budget:** at most 64 KB/s down per client. Twelve ships at 30 Hz is about 22 KB/s.

### 4.7 World generation

- **Chunks:** the seed drives everything. The disc is cut into 256 m × 256 m columns, and each column's random stream is seeded from `hash(seed, cx, cz, purpose)`.
- **Streaming:** chunks are generated on `WorkerThreadPool` and added to the scene on the main thread.
  - The server keeps collision loaded within 2.5 km of every ship and player.
  - Each client streams visuals within 2.5 km of its own player.
- **Detail levels:** full detail below 800 m, medium below 1,800 m, low below 3,000 m. Fog hides the edge.
- **Islands:** 0–3 per chunk, with density by region (the Shattered Belt is densest) and a radius of 15–120 m. Each island has a noise-shaped grassy top and a tapered, noisy rock underside. Trees and rocks are drawn as MultiMesh instances, and collision is a static trimesh.
- **Towns and wrecks:** towns sit on large islands placed by seeded Poisson sampling. There are 4 towns in the Calm Reaches (one of them the starting town), 3 in the Shattered Belt, 2 in the Gale Expanse, and 1 outpost at the Stormwall. Wrecks are generated from damaged pirate blueprints.
- **Wind:** `W(p, t)` = prevailing wind + sky rivers + storm cells + turbulence.
  - The prevailing wind circles the Eye counter-clockwise, rising from 2 m/s at the rim to 12 m/s in the Gale Expanse.
  - There are 6–10 sky rivers, splines generated from the seed. They reach up to 35 m/s within 60–120 m of the spline, fading smoothly.
  - Storm cells are drifting circles 300–800 m across.
  - The Stormwall is a band of extreme turbulence.
  - Wind is a pure function of position, time and seed, so it never needs to be sent over the network.
- **The Roil:** an animated storm surface at 200 m, with volumetric fog below and lightning flashes.

### 4.8 Rendering

- **Sky:** `ProceduralSkyMaterial` at first, replaced by a custom sky shader (sun, stars, cloud layer) when the world stage needs it.
- **Fog:** depth fog hazes the distance from 1.5 km. Volumetric fog for the Roil and cloud banks comes with the world stage, if the Radeon 680M can afford it.
- **Lighting:** a sun (`DirectionalLight3D`) with 4-split shadows, driven by the day–night cycle.
- **Detail and instancing:** `visibility_range` and mesh LODs for detail levels, and MultiMesh for vegetation.
- **Performance target:** 60 fps at 1080p on medium settings on the Radeon 680M. This laptop's integrated GPU is the baseline, and the RTX 3050 does better.

### 4.9 Audio

- **Generated sound:** sound effects are generated at startup into `AudioStreamWAV` buffers:
  - cannon: a noise burst over a low sine;
  - creak: filtered noise;
  - wind: looped filtered noise, scaled by airspeed;
  - propeller hum: a sawtooth at the propeller's RPM.
- **Buses:** Master, Music, SFX and Ambience.
- **Music:** decided in stage 10.

### 4.10 Persistence

- **Settings:** `user://settings.cfg` (ConfigFile). Values are clamped on load, and a missing or broken file falls back to defaults.
- **Blueprints:** `user://blueprints/<name>.skyship.json`, stored as `{"format": "skywright-blueprint", "version": 1, "name", "blocks": [[x, y, z, type, rotation], …], "paint": {…}}`. `paint` maps a block type to a hex colour (`"balloon": "c83c3c"`), and every block of that type takes it.
  - Validation happens on load: known format and version, 1 to 4,000 blocks, coordinates in −64…63, known block types, rotation 0–23, and at least one helm.
  - Numbers may be whole floats (`3.0` is 3). Files over 1 MB are refused.
  - Other players' blueprints are untrusted input.
- **Saves:** `user://saves/<slot>/world.json`, `ships.json` and `player.json`, each with a `version`.
  - The game autosaves every 5 minutes and when docking, and keeps the last three autosaves.
  - A save that fails to load falls back to the previous autosave, and the game tells the player.

### 4.11 Performance budgets

| What | Budget |
|---|---|
| Frame rate | 60 fps at 1080p, medium settings, Radeon 680M |
| Blocks per ship | ≤ 4,000 |
| Active ships near players | ≤ 12 |
| Players | ≤ 8 |
| Host physics tick | ≤ 8 ms with 12 ships |
| Network, per client | ≤ 64 KB/s down |
| Mesh rebuild after a hit | ≤ 4 ms per 16³ section |

> ponytail: all game code is GDScript. If mesh building or world generation misses its budget, move that hot path into a GDExtension (C++) module.

## 5. Build stages

Each stage ends with something playable. **A stage is finished when its tests pass and its playtest checklist is done.** Each stage gets its own implementation plan in `docs/superpowers/plans/` when it starts.

| # | Stage | Finished when |
|---|---|---|
| 1 | Foundations | `./run_tests.sh` passes. The game opens to its menu on this laptop's GPU. Solo, host, join and leave work between two copies of the game on one machine. |
| 2 | First flight | You walk the deck of a starter ship while it rolls in the wind, take the helm, and fly between placeholder islands. Flight tests pass: a balanced ship holds level, a lopsided one lists toward its heavy side, an overloaded one sinks, and top speed is within 10% of the estimate. |
| 3 | Online co-op | Two players crew one ship over Wi-Fi. Games on the LAN appear in a list. Disconnects and version mismatches are handled. A dedicated server runs headless. The two-instance network test passes. |
| 4 | Shipyard | You build a ship with live stats and warnings, test-fly it, and save, load and share blueprints. Blueprint and stats tests pass. |
| 5 | The sky world | The full generated disc streams in at 60 fps. Wind and sails work, towns exist, and you can go on foot and glide. Determinism tests pass. |
| 6 | Damage and combat | Cannons and ammunition work. Ships break apart. Pirates attack. Ships sink into the Roil and can be rebuilt. Damage and break-apart tests pass. |
| 7 | Towns and progression | Markets, contracts, hired crew, part tiers, and save slots with autosave all work. Save and economy tests pass. |
| 8 | Campaign and threats | Regions are gated, the Stormwall can be crossed, leviathans and the boss appear, storms happen, story logs exist, and the Eye ending plays. |
| 9 | Skirmish | Team ship battles, sky-river races, boarding, and a full match flow. |
| 10 | Sound and polish | Generated sound and ambience, full settings, a tutorial, a performance pass, and Linux and Windows builds. |

Online co-op comes third on purpose. Networking a physics game late is where projects like this usually break, so everything after stage 3 is built and tested with two players.

## 6. Testing

- **Runner:** `./run_tests.sh` imports the project, then runs `tests/run_tests.gd` headless.
  - It finds every `tests/**/test_*.gd`, and runs each `test_*` method on a fresh instance. Async tests can `await`.
  - It exits 0 when everything passes and 1 otherwise.
  - Engine or script errors logged during a test count as failures, from the moment the test enters the tree until it has left it, so a crash can't pass silently.
  - It runs Godot with `--fixed-fps 60`, so every frame is exactly one physics tick of 1/60 s. A fixed frame rate turns off Godot's frame cap, so frames run as fast as the machine allows. Game time, timers included, follows frames, so flight tests (`TestCase.simulate(seconds)`) run minutes of flying in seconds. Network tests that must keep pace with the wall clock tick in real time with `NetCase.play()`: ENet's timeouts do, and so does a server in another process.
- **Unit tests:** settings, session roles and handshake, input map, mass properties, lift and drag, greedy box merging, break-apart detection, blueprint validation, world determinism (same seed, same world), wind continuity, saves and prices.
- **Flight tests:** real physics runs headless for a few simulated minutes, with the assertions listed for stage 2. These protect the promise that physics decides whether a ship flies.
- **Network tests:** several players run in one process. Each gets a branch (a `SubViewport` with its own `SceneMultiplayer` and its own 3D world), joined over ENet on localhost. `test_two_games` also starts a headless dedicated server in a second process: two players join it, hand the helm over, and check they see the ship in the same place.
- **Playtest checklist:** each stage ends with one, covering what only a person can judge, such as whether flying feels good or whether combat is fun.

## 7. Error handling

| Situation | Behaviour |
|---|---|
| Host quits | Clients return to the menu with "The host ended the game." |
| Connection lost | The client returns to the menu with "Lost the connection to the host." |
| Connection goes silent | After 8 s it counts as lost, on both sides. |
| A player drops | Their stations are freed and the rudder centres. A dedicated server anchors its ships once nobody is aboard. |
| Can't reach the host | After 8 s: "The host didn't answer." |
| Version mismatch | Refused with "This game is version A; you have version B." |
| Game full | Refused with "The game is full (8 players)." |
| Port in use when hosting | "Port 24650 is already in use. Is another game running?" |
| Broken settings file | Defaults are used and the file is rewritten on the next save. |
| Broken save | The previous autosave loads, and the player is told. |
| Invalid blueprint | It's refused with the first problem found, and nothing is loaded. The checks are in `Blueprint.parse` and `ShipGrid.read_blocks`. |
| Physics blow-up | The physics guard in §4.4 applies. |

## 8. Risks

| Risk | Mitigation |
|---|---|
| Walking on a moving deck feels wrong or is buggy | It's proven first in stage 2, with the fallback described in §4.5. |
| Ships feel twitchy or sluggish | Flight tests, one tuning file, and the shipyard readouts |
| GDScript is too slow for meshes or world generation | Worker threads and budgets, with a GDExtension as the upgrade path |
| Internet play needs port forwarding | Documented. A dedicated server can run on a VPS. Matchmaking is out of scope. |
| Hybrid GPU drivers (RADV on the 680M, NVK on the RTX 3050) | Stage 1 records which GPU Godot picks and documents `--gpu-index`. |
| Scope | Staged delivery, with each stage playable |

## 9. Decisions

| Date | Decision |
|---|---|
| 2026-09-29 | Concept: Skywright, chosen over Ironstride and Hadal |
| 2026-09-29 | Approach: real physics ships, chosen over scripted flight and captain-simulated physics |
| 2026-09-29 | Engine: Godot 4.7.2, GDScript, Jolt, Forward+; desktop Linux and Windows |
| 2026-09-29 | Every game runs a server. Solo means a local server with no network. |
| 2026-09-29 | Online co-op is built at stage 3, before content |
| 2026-09-30 | Ships get a keel term in their drag, so they carve turns instead of skidding (about 6°/s for the starter ship) |
| 2026-09-30 | The starter ship is balanced by iron ballast in its keel, and floats level at 877 m |
| 2026-09-30 | Until stage 5, crew who fall overboard are put back aboard where they started |
| 2026-09-30 | LAN discovery is query and answer, not announcements, because only one program per machine can listen on 24651 |
| 2026-09-30 | Online games gather in a lobby until the host sets sail; late joiners go straight aboard |
| 2026-09-30 | A connection silent for 8 s counts as lost (ENet's default is 30 s) |
| 2026-09-30 | One world clock, seconds since the server's world began, drives the sky and client interpolation |
| 2026-09-30 | In stage 3 everyone crews the host's one ship; each machine walks only its own crew member, and crew don't collide |
| 2026-09-30 | Block rotations are Godot's orthogonal basis index (0–23) |
| 2026-09-30 | Propellers and rudders act along their facing |
| 2026-09-30 | Each player has one ship and one test flight at a time; a leaver's ships go with them |
| 2026-09-30 | A blueprint is refused with the first problem found, and nothing is loaded |
| 2026-09-30 | The shipyard opens only at the dock until towns arrive in stage 5 |
