# Skywright: design spec

- **Date:** 2026-09-29
- **Status:** Design parts 1–3 agreed in chat on 2026-09-29; this document consolidates them. Updated on 2026-09-30 and 2026-10-01 with what stages 2 to 7 settled.
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

Beyond 8,000 m, rim winds push ships back inward (a soft boundary). The seed generates islands, towns, landmarks, wrecks, sky rivers and storms, so each world is different, and the same seed always makes the same world. There is a day–night cycle.

There are ten towns: four in the Calm Reaches, three in the Shattered Belt, two in the Gale Expanse and one at the Stormwall. The first, in the Calm Reaches, is the starting town, at the same place in every world. Each town has a dock and a shipyard. Eight named landmarks (spires, arches and ruins, one of them in the Eye) and twenty wrecks (none in the Eye) give the sky things worth flying to.

### 3.2 Core loop

Build a ship at a shipyard, fly out, explore, take contracts (deliveries, bounties, salvage, scouting), fight, and earn money and new parts. Then rebuild a better ship and push further toward the Eye.

### 3.3 Ships and building

- **Grid:** ships are built on a 1 m grid. There's a limit of 4,000 blocks per ship, and every ship has exactly one helm (stage 6: a second helm would make break-apart ambiguous).
- **Block catalogue:** frames, deck planks, iron and alloy plates, balloon cells, lift stones, engines, propellers, rudders and fins, sails, fuel tanks, ballast tanks, helm, cannons, cargo bays, bunks and ladders. Starting values are in §4.4.
- **Weight and forces:** every block has weight. Balloons and propellers push from where they're mounted. Wind and drag act on every exposed face.
- **Shipyard readouts:** weight, lift at the current altitude, thrust, estimated top speed and climb rate. Markers show the centre of mass against the centre of lift, with warnings such as "lists 8° to port" or "too heavy to hold altitude".
- **Cargo:** crates are stowed in cargo bays, one a bay, and each adds 100 kg (`Tuning.CRATE_MASS`) where it's stowed, so weight and balance follow the crates. A destroyed bay loses its crate, and a piece that breaks away takes its crates. The starter ship carries four bays in her main deck at (±1, 0, −2) and (±1, 0, 4), and two bunks in her keel at (0, −1, ±3), placed so she weighs and trims as she did without them.
- **Damage:** every block has hit points, and destroyed blocks are removed; the ship flies on what's left. Any section no longer connected to the helm's section breaks away as its own wreck, and a severed balloon floats away. A helm shot loose on fewer than 4 blocks is lost with them, and the ship becomes a wreck that can't be steered.
- **Shipyard warning:** blocks not joined through faces to the helm's piece are flagged, because they'd fall away at the first hit.
- **Shipyard:** the shipyard opens within 150 m of any town's dock, which has a slipway for each player. A launch or test flight goes from the slipways of the town whose shipyard it was made in, even after you come back from a test flight somewhere else. Blocks are placed, removed, turned, tipped and mirrored, with undo and redo. Mirror mode makes every edit on both sides of the keel.
- **Test flights:** a design can be flown at once from the shipyard, with the designer at the helm, and returned from instantly. A test flight is a real ship that's removed when it ends.
- **Blueprints:** designs are saved as blueprints, which are shareable files.

### 3.4 Crew and stations

- Players walk the deck in first person, climb ladders and use stations: the helm and cannons. (An engine station waits for fuel, stage 8.)
- **Repairs:** holding R at a block within 6 m puts out fires around it, or else uses one of the ship's spares to heal it or rebuild a lost block beside it from her blueprint, four times a second. That patches the envelope from the deck. Helms and cannons need a shipyard. A ship carries up to 40 spares, bought at any town's dock for 5 crowns each.
- At the helm, the camera can switch to a third-person chase view.
- The helm has an autopilot that holds heading and altitude, so a solo player can leave the helm to man a gun.
- **Hired hands** (stage 7) are hired at a town's dock for a one-off fee (gunner 150 crowns, repairer 120, engineer 200), one per bunk, and are server-side brains on their ship. A gunner mans one cannon and fires only at pirates within 600 m, aiming as pirate captains do (at the target's block nearest her centre of mass). A repairer walks the ship in straight lines at 4 m/s, putting out fires first and then mending with her spares, through the same server path as a player's repair. An engineer tends an engine, and her propellers push 25% (`Tuning.ENGINE_BOOST`) harder for each one tended, shared over her engines: about 12% more speed. Hands aren't hit or knocked down, never leave their ship, never steer, and never fire at players. They're lost with their ship, and move to the ship that replaces theirs at a launch while she has bunks and posts; the rest stay ashore.
- Players can leave the ship on foot to explore islands, and glide back to it. Stepping off the deck puts you ashore, where you walk in the world with ordinary gravity; holding Space in the air opens a glider. Landing on a ship's deck, or pressing E beside her hull, puts you aboard. Falling into the Roil puts you back aboard.
- A pilot can anchor the ship (G at the helm). An anchored ship is held still where she is, whatever the wind, until the pilot weighs anchor.

### 3.5 Threats and combat

- **Pirates:** ships built from the same blocks and flying on the same physics, with AI captains that chase, circle and fire broadsides. One design (`PirateShip`, four cannons). The server raids crewed ships more than 1,200 m from every dock every 30 s: a 25% chance in the Calm Reaches with at most one pirate near you, 50% and two further in, four in the world at most. Captains fire the guns themselves (no pirate crew), steer against the wind's drift, and don't steer around islands. Pirates far from every player leave.
- **Sky leviathans:** roaming giants in the Gale Expanse, plus one boss.
- **Weather:** storm cells bring lightning and turbulence.
- **Cannon ammunition:** round shot (block damage, about two planks), chain shot (shreds balloons), explosive shells (3 m bursts that start fires) and harpoons (a rope between the ships for 45 s). Cannons never run out: spares already make fighting cost money, and the reload already limits fire (stage 7 decided against ammunition as cargo).
- **Being hit:** a shot through a player, or a shell bursting within 3 m, knocks them down for 5 s; they come to at a bunk or by the helm. There's no health bar.
- **Fire:** wood and cloth burn, losing 5 hit points a second, spreading, and burning out after 30 s.
- **Salvage:** each world wreck gives 150 crowns and 12 spares (as many as fit) once, and the world remembers; a broken-off wreck gives a spare per 10 blocks and a crown a block, and is broken up.
- **The Roil:** below 200 m a ship takes storm damage, and below 0 m it is lost. You keep the blueprint, and she's insured for half her cost: your next launch counts the insurance as her trade-in. Whoever was aboard wakes on the nearest town's quay at once.
- **Abandon ship:** the pause menu's Abandon ship (pressed twice) loses your own ship wherever she is, insured like a sunk one, and puts you on the nearest town's quay unless you're aboard another ship. It rescues a captain whose helm was shot off far from a shipyard.

### 3.6 Economy and progression

- **Money:** crowns, in a purse per player (1,500 to start), kept by the server by player name. A player's inventory is the crates they own, wherever they're stowed; crates are saved with the ships that carry them.
- **Markets** at every town's dock buy and sell crates of grain, timber, cloth, tools and spirits. Each town makes two goods (sold at 0.6 of base) and wants two (bought at 1.5), with ±10% noise, all from the world seed; a market pays 85% of its price. Prices don't move with trade. Mail is never traded.
- **Contracts:** each town's board offers three, drawn when first asked for: deliveries of 1–3 mail crates to one of the three nearest towns (paid when a ship carrying them docks there), bounties for 1–2 pirates beaten within 1.5 km of you, salvaging one of the three nearest unstripped wrecks, and scouting one of the three nearest landmarks (within 400 m). Rewards grow with distance. A player holds three at most and can drop one anywhere, which unloads a delivery's mail. Titles say how far and which way; the map doesn't mark targets, and contracts have no deadlines.
- **Part tiers:** wood and iron from the start (the starter ship's keel is iron). Alloy plates unlock for 2,000 crowns at a town in the Shattered Belt or further in, and lift stones for 4,000 at a town in the Gale Expanse or further in. Money is the only way to unlock, until story progress (stage 8). A design with locked parts can be test-flown but not launched.
- **Launch prices:** a ship costs her parts (`Economy.PART_COST`) and a full load of 40 spares (the starter ship: 1,350 crowns). A launch costs that less the trade-in: what the old ship is worth now (parts by hit points, and spares), or with no ship of your own her insurance. A smaller ship pays nothing back. Crates aboard the old ship move to the new one, which must have bays for them.

### 3.7 Campaign

- The journey runs from the Calm Reaches to the Eye.
- Region progression is gated by ship capability. The Stormwall is the main gate.
- The story is told through logs found in ruins and towns.
- The Eye holds the final region, a boss and the ending.

### 3.8 Multiplayer

- **Co-op:** friends join the host's world and either crew the host's ship or fly their own alongside it (from stage 4, which brings ships of your own; in stage 3 everyone crews the host's ship). Each player has one ship and one test flight at a time, and a leaver's ships go with them. The world is saved on the host's machine, with every player's account by name. A leaver's ship waits in the world's save (not in the world) until they come back under the same name. Names are unique on a roster: a second "Ann" becomes "Ann 2". Guests' maps (exploration) aren't saved, since the host never sees them.
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
src/world/                world scene, generation, streaming, wind, weather, towns, the Roil   (stage 5)
src/combat/ src/ai/        projectiles and cannons; pirates and hired hands          (stage 6, 7)
src/economy/ src/save/     the economy's rules and the Ledger; saved games            (stage 7)
src/campaign/ src/audio/                                                             (later stages)
src/ui/                   menus, HUD, map, compass
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
| Engine | 300 | 200 | Powers propellers (fuel waits for stage 8) |
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

The stage 2 starter ship came out bigger: 8.9 t on a 5 × 13 m deck, with 127 balloon cells. Iron in the middle of its keel puts its weight right under its lift, so it floats level at 877 m. Its two propellers reach 20 m/s. Stage 6 joined her envelope to her hull (her posts run into it) and gave her two cannons and more balloons: 9.6 t, 301 blocks, 137 balloon cells, level at 882 m. Stage 7 swapped four deck planks for cargo bays and two keel frames for bunks with no change to her weight or trim. A crate weighs 100 kg (`Tuning.CRATE_MASS`) at its bay, and an engineer drives an engine 25% harder (`Tuning.ENGINE_BOOST`).

**Mass properties:**
- Total mass is the sum of the blocks.
- Centre of mass is the mass-weighted average of cell centres.
- Inertia is the diagonal of the summed point-mass-plus-cube tensor about the centre of mass.
- These are set on the body with a custom centre of mass and inertia, and recomputed whenever the grid changes.

> ponytail: only the diagonal of the inertia tensor is kept (Godot takes principal moments). Fine for mirror-symmetric ships. Rotate into principal axes if asymmetric ships feel wrong.

**Forces each physics tick** (at world position `p`, air density factor `ρ(h) = exp(−(h − 200) / 2500)` for h ≥ 200, and 1 below). Every constant is in `src/ship/tuning.gd`:
- **Balloon lift:** `900 N × ρ × trim` per cell. The pilot sets trim between 0.8 and 1.1, and trim above 1.0 will burn fuel once fuel exists (stage 8; until then fuel tanks are dead weight and trim is free). Lift stones give a fixed 6,000 N.
- **Thrust:** `throttle × engine power share × 2,500 N` per propeller, along its facing. One engine drives up to two propellers at full power. A propeller facing aft pushes the ship astern.
- **Drag:** cells are grouped into 4 × 4 × 4 zones. Each zone stores its exposed face area per local axis and its centre. Zone drag is `−½ × 1.2 × ρ × Cd × A_axis × |v_axis| × v_axis`, per local axis, with Cd 0.45. It uses the air-relative velocity at the zone centre: body velocity at that point minus the wind. Rotational damping falls out of this, and the body adds spin damping of 0.5 per second.
- **Keel:** each zone also pushes back against slipping sideways while it moves forward: `−½ × 1.2 × ρ × 8 × A_x × |v_forward| × v_side`, along the ship's x axis. It works the way a keel does in water. Without it a ship skids instead of turning. With it the starter ship turns at about 6°/s and keeps about two-thirds of its speed through a hard turn. It needs forward speed, so a hovering ship still drifts with the wind.
- **Control surfaces:** a rudder acts along its facing too. Side force `k × ρ × v_forward × |v_forward| × deflection`, where `v_forward` is the airflow along the ship, so a rudder works backwards going astern.
- **Gravity** is applied by the engine, at 9.81 m/s².

**Collision:** cells are merged into boxes with greedy meshing and added as box shapes on the body. A hit's shape index plus its local hit point identify the cell.

**Rendering:** one mesh per ship, with one surface per material, rebuilt whole at most once a frame when blocks go or come back (2.9 ms for the starter ship, 3.8 ms at 500 blocks, 23 ms at 4,000). 16³ sections wait until big ships stutter under fire. Shaped blocks (propeller, rudder, sail, cannon, helm) are drawn as shapes but still collide and drag as cubes. Balloons are drawn as one cloth envelope.

**Break-apart:** after blocks are destroyed, a flood fill finds the components connected through faces.
- The largest component of at least 4 blocks that still contains a helm stays the ship. Otherwise the largest component stays, as a wreck that can't be steered. Ties go to the component with the smallest cell, so every machine agrees.
- Every other component of 4 blocks or more becomes a new wreck (nobody's), with its own body, the velocity it had at that point, and its own mass properties. Smaller ones vanish as splinters.
- Wrecks go after 3 minutes, when more than 8 are about, or when further than 3 km from every player.

**Damage rules** live in `Damage` (node-free): shots walk the grid along their path, blasts fall off with distance, fire burns and spreads once a second, repairs heal or rebuild from the blueprint. Hits are found by moving the hit point into ship space and walking the grid, not by shape index.

**Physics guard:** a ship whose position or velocity becomes non-finite, faster than 400 m/s, or spinning faster than 20 rad/s is restored to its last good transform with zero velocity, and the event is logged.

### 4.5 Crew on moving decks

- **Interior world:** each ship owns an interior `SubViewport` with `own_world_3d = true`. That gives it a separate physics space; it's never rendered. The interior holds a static copy of the ship's collision boxes in ship-local coordinates, plus the `CharacterBody3D` of everyone aboard.
- **Gravity aboard:** crew gravity is `ship_basis⁻¹ × (0, −9.81, 0)`, and `up_direction` is its opposite. A tilted ship therefore feels like a sloped deck. Look yaw is relative to the ship, so you turn with it.
- **Drawing crew:** a crew member is drawn in the main world at the ship's interpolated transform multiplied by their local transform.
- **Leaving and boarding:** you leave the ship when no ship floor has been under your feet for 0.2 s and nothing of the ship is below you (`Ship.is_over`). You then become a main-world character (`ship` is null) in world space, with the ship's point velocity plus your own. Ashore you walk with ordinary gravity, never faster than 50 m/s, and a glide (Space held through 0.3 s of falling, not rising, or pressed again in the air) eases you to 13 m/s where you look, sinking at most 3 m/s. Landing on a ship's deck puts you aboard that ship, once you've been ashore 0.5 s so you don't bounce straight back. So does E within 3 m of a ship's box, because you can't jump 2 m up a hull and ships don't hold still at a quay. Falling below the Roil's 200 m puts you back aboard the ship you left, else your own, else the host's.
- **Walking in a tilted gravity:** walking "uphill" against gravity that isn't square to the deck makes Godot skip its floor snap, so crew apply the snap themselves (except when jumping or on a ladder). Ladders are open cells: while your body is in a ladder's column you hold on, gravity stops, and you climb along the ship's up.
- **Being hit:** the server tests each shot against where each player last reported standing (within 0.7 m of its path, or inside a shell's burst), so crew need no hitboxes.
- **Other players:** each machine walks only its own crew member, in its own copy of the interior, and reports where it is (§4.6). Everyone else is drawn as an avatar with a name tag. Crew don't collide with each other until combat needs server-side crew bodies (stage 6).
- **Fallback:** if this approach fails its stage 2 check, crew become main-world characters that inherit platform velocity and yaw from the deck.

### 4.6 Networking

- **Transport:** ENet over UDP on port 24650. Up to 8 players. Guests only ever talk to the host (SceneMultiplayer's server relay is off). A connection silent for 8 s counts as lost (ENet's own default is 30 s), so a host that crashes or is killed is noticed quickly.
- **LAN discovery (UDP 24651):** query and answer. Once a second, a browser broadcasts a query (`SKYWRIGHT?` padded with zeros to 256 bytes) to port 24651, and to this machine. Each host answers the asker directly with `SKYWRIGHT!` and `var_to_bytes({id, name, players, max, version, port})`. An answer is never bigger than its query, so a host can't be used to multiply traffic, and every answer is checked. It's query and answer rather than announcements because only one program per machine can listen on 24651: a second game hosted on the same machine can be joined by address but isn't listed.
- **Channels:**
  - Channel 0 is reliable, for events.
  - Channel 1 is unreliable-ordered, for ship snapshots.
  - Channel 2 is unreliable-ordered, for crew movement and the pilot's helm keys.
- **The world clock:** seconds of physics since the server's world began. Snapshots carry it, and each client eases its own clock toward it. The day–night cycle and client interpolation both run on it, so everyone sees the same sky. Wind is a function of the seed and this clock, so every machine computes the same wind, and storms are where everyone sees them.
- **Who flies:** only the server simulates ships. On clients a ship is a frozen, kinematic copy that follows the snapshots, and no forces act on it.
- **Ship snapshots (30 Hz):** each carries `{ship id, position, rotation, linear velocity, angular velocity, throttle, rudder, trim, autopilot, target heading, target altitude, anchored}` at a server time. Clients render ships 100 ms in the past with Hermite interpolation between snapshots, and extrapolate up to 250 ms when packets are late.
- **Crew (30 Hz):** each client sends `{ship id, local position, velocity, yaw, pitch}` to the server. The server checks it (finite, at most 50 m/s, within 35 m of the ship's blocks), stamps it with its own clock and relays it to everyone else. Clients draw other crew 100 ms in the past, on their ship as it's drawn. A report with ship id 0 is of someone ashore: its position and velocity are in world space, and the server checks they are finite, at most 50 m/s (plus 0.01 m/s of slack), within 11,000 m of the centre, and between 0 and 5,000 m high.
- **Stations:** a client asks the server for the helm. The server grants it only if the asker last reported standing aboard that ship within reach (1.8 m, plus 0.5 m of slack), and tells everyone who holds it. Only the pilot's helm keys are applied (clamped to −1…1), and only the pilot can switch the autopilot.
- **Events (reliable):** ship spawned (with compressed blocks, paint and damage), ship removed, blocks destroyed, ship split, projectile fired (`origin`, `velocity`, `type`, `server time`), projectile hit, station claimed or released, and economy changes. Every machine simulates a projectile's arc from its launch data, and only the server decides hits.
- **Protocol 3 (stage 4):** `_ship_added` and `_ship_removed` carry ships that come and go mid-game, and `_world` sends every ship's entry `[id, blocks, paint, transform, pilot, captain, test]`. A client asks with `_launch(blocks, paint, test)` (at most one a second; the server checks the bytes) and ends a test with `_end_test`. A launch or a test replaces the player's last ship or test, and `_ship_removed` names the ship that takes over its crew. From stage 7 the server launches or test-flies a design only for a player who last said they were at that town's dock.
- **Protocol 4 (stage 5):**
  - `_welcome(roster, under_way, seed)` adds the world seed, an `int` from 0 to 2,147,483,647, so a guest makes the host's world before it loads. A client refuses anything else and ends with "The host sent a world this game can't make."
  - `_launch(blocks, paint, test, town)` adds the town whose dock to launch from, an index into the world's towns. Anything else is ignored.
  - Each ship state in `_ships` gains a 12th field, `anchored`.
  - `_request(ship_id, what, on)` may ask for `"anchor"`. Only the pilot may.
  - `_crew_report` and `_crew_moved` use ship id 0 for crew ashore, as above.
- **Block bytes:** two bytes of block count (`encode_u16`), then a zstd-compressed body of 7 bytes per block: `x + 64`, `y + 64`, `z + 64`, the type's index in `Tuning.BLOCKS`' key order, the rotation, and the hit points as `u16`. Reordering `Tuning.BLOCKS` changes the protocol.
- **Protocol 5 (stage 6):**
  - Ship entries gain the blueprint's bytes, whether she's a pirate, and her spares: `[id, blocks, paint, transform, pilot, captain, test, blueprint, pirate, spares]`. `_world(time, entries, salvaged)` adds the world wrecks already stripped.
  - `_blocks_changed(id, changes)` carries every hit-point change (hits, fire, the Roil, repairs; 0 is destroyed): a `u16` count, then 5 bytes a change. A split is one `_blocks_changed` followed by `_ship_added` for each wreck. `_ship_removed(id, successor, lost)` says whether the Roil took her.
  - Shots: `_fired(shot, ammo, origin, velocity, time, ship)` and `_hit(shot, point, time)`; every machine flies the arc, clients 100 ms behind like ships. Ropes: `_tether` and `_untether`.
  - Stations: `_man`, `_gunner` and `_fire` for cannons, as for the helm. Repairs: `_repair`, `_fires` (3 bytes a burning cell), `_spares`. Salvage: `_salvage`, `_salvaged`, `_salvage_result`. Knock-downs: `_knocked_out`.
  - A broadside of four is under 1 KB. A fight with a pirate measured under 32 KB/s down to a guest.
- **Protocol 6 (stage 7):**
  - Ship entries gain her cargo, `[[x, y, z, good, owner], …]`, and her hands, `[[id, name, role, post, at], …]` (ids below 0): 12 fields.
  - `WorldSync`: `_cargo(id, cargo)` and `_hands(id, hands)` (a walking repairer's place, twice a second); `_salvage_result(spares, money)`; `_abandon()`.
  - A second RPC node, `World/Ledger`, keeps the books: `_account(account)` (to its owner, under 1 KB) and `_say(text)` (at most 200 characters) from the server; `_buy_spares`, `_trade(good, count)`, `_ask_board` and `_board(town, offers)`, `_take(id)`, `_drop(id)`, `_unlock(part)`, `_hire(role)` and `_dismiss(id)` from clients. The server takes at most one economy ask from each peer every 0.1 s and checks it against where the asker last said they were.
  - `_launch` keeps its arguments; the server now checks the town, the unlocks and the price, and refusals come back through `_say`.
  - Names are made unique by the host as players join.
- **Joining mid-game:** only peers whose world has loaded get world traffic. A client's world asks to enter when it's ready, and receives the world clock and every ship (blocks as bytes, paint, transform, pilot, captain and test). The world seed comes with the handshake; later stages add the list of changes to the world. The crew roster comes with the handshake.
- **Budget:** at most 64 KB/s down per client. Twelve ships at 30 Hz is about 22 KB/s.

### 4.7 World generation

- **The seed makes the world, as data.** `WorldGen.new(seed)` works out once, with no nodes, everything the whole disc needs to know: the towns, landmarks, wrecks, rivers and storm cells. A seed is 0 to 2,147,483,647 and travels with the handshake (§4.6). Any chunk can be made alone, in any order, on any thread or machine, and comes out the same.
- **Chunks:** the disc is cut into 256 m × 256 m columns, and each column's random stream is seeded from `hash([seed, cx, cz, purpose])`. `WorldChunk.generate` makes a chunk's arrays on any thread; `WorldChunk.build` makes its nodes on the main thread: one mesh per level of detail switched by `visibility_range`, trees as a MultiMesh, a waterfall, clouds, one static collision body, and any wreck or landmark standing in it. A chunk takes about 5 ms to generate and 2 ms to build on the development laptop.
- **Streaming:** chunks are generated on `WorkerThreadPool` and added to the scene on the main thread, nearest first, within 3 ms of a frame. Far chunks are freed a few a frame in what's left of those 3 ms, and one that's wanted again before its turn is kept.
  - Chunks within 2.5 km of a focus point are loaded, and chunks beyond 2.8 km of every focus point are freed. The server's focus points are every ship and every player. A client's is its own player. Focus points within 64 m of each other count as one, such as a player aboard a ship.
  - What's wanted is worked out every 0.25 s in one pass over each focus point's circle of chunks, with no sorting: about 2 ms for 20 ships spread over the whole disc on the development laptop.
  - Every loaded chunk has collision and visuals. A dedicated server loads collision only.
- **Detail levels:** full below 800 m, medium below 1,800 m, low below 3,000 m. Trees stop at 1,200 m, waterfalls at 1,800 m and clouds at 3,000 m. Fog hides the edge.
- **Islands:** each chunk makes up to 4 tries by region, and a try lands 70% of the time if it fits. The Shattered Belt has the most (4 tries of small islands, 15–60 m in radius), the Stormwall the fewest (1 try, 15–40 m), and the others 2 tries of 25–120 m. The rim has none. Tops float between 300 m and 1,700 m. Each island has a noise-shaped grassy top and a tapered, noisy rock underside, flat shaded, with trees and sometimes a waterfall. Collision is a static trimesh.
- **Towns:** ten, placed by seeded dart throwing with at least 1,500 m between docks, in the regions' shares (§3.1). The starting town is always at the start point, `(0, 880, 7000)`. A town is a flat island with houses and a beacon tower, behind a stone quay with a slipway for every player and a finger pier 1.5 m off the side of a ship at each slipway. Docks are frictionless, so a ship blown against a pier slides along it. A launch keeps 1 m from the dock's obstacles and 2 m from other ships.
- **Landmarks and wrecks:** landmarks are spires, arches and ruins. A wreck is a pirate ship with its balloons gone and each other block lost with a 35% chance, resting on an island. Both are made from their own seeds, so they come out the same everywhere.
- **Wind:** `W(p, t)` = prevailing wind + sky rivers + storm cells + turbulence, and the rim's push inward past 8,000 m.
  - The prevailing wind circles the Eye counter-clockwise, rising from 2 m/s at the rim to 12 m/s in the Gale Expanse.
  - There are 6–10 sky rivers, each a winding spline of 20 points at 600–1,400 m. They blow 20–35 m/s in a core 60–120 m wide, fading smoothly to nothing at twice that, and at their two ends. Segments blend, so the wind swings round a bend instead of jumping.
  - There are 6–10 storm cells, circles 300–800 m across orbiting the Eye, each with extra gusts and updrafts. Gusts and updrafts are at full in a cell's core and fade out between 0.6 and 1 times its radius.
  - Wind is a pure function of position, time and seed, so it never needs to be sent over the network. `WorldSync` drives its clock from the world clock.
  - Sails push a ship along the way they face, by the wind across them.
- **The Roil:** an animated storm surface at 200 m, with fog sheets over it and lightning (§4.8).
- **Exploring:** each machine keeps a grid of 128 m cells over the disc, marked as seen when you pass within 1,200 m. The map and compass draw from it.

### 4.8 Rendering

- **Sky:** `ProceduralSkyMaterial`. The world stage kept it; a custom sky shader (sun, stars, cloud layer) is deferred to the polish stage (stage 10).
- **Fog:** depth fog hazes the distance from 900 m to 2,600 m, which hides the streaming edge. Over the Roil, two translucent fog sheets (at 240 m and 290 m) follow the camera, and each storm cell has a dark column of cloud. Volumetric fog was dropped: sheets are cheap on any GPU, and it can come with the polish stage.
- **Weather:** lightning strikes in storms within 3 km of the camera and under the islands within 1 km. It's only visual. Every machine makes its own bolts, and a dedicated server has none. Clouds are instanced puffs, made per chunk.
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
- **Saves:** slots `1`, `2` and `3`, and `server` for a dedicated server. A save is a folder of three files, `world.json` (seed, clock, stripped wrecks, the host's map as base64 PNG, the host's name, when it was saved), `ships.json` (each ship's captain by name, place, trim, anchoring, spares, blocks with hit points, blueprint, paint, crates and hands) and `player.json` (every account by name), each `{"version": 1, "<part>": …}` and written whole (`.tmp`, then renamed). A save by hand goes in `user://saves/<slot>/`, autosaves in `<slot>/auto-1` to `auto-3` (the first missing, else the oldest).
  - What's saved: every ship but pirates, nobody's wrecks and test flights, plus the ships waiting for absent captains. Contract boards, pirates, wrecks, fires and shots aren't.
  - Everything read back is checked as untrusted input (files over 16 MB are refused, blocks through `ShipGrid.read_blocks`, crates, hands and accounts through their readers), and a problem names its file.
  - The host's game autosaves every 5 minutes of play, when a ship docks (at least 30 s after the last save) and when leaving the game; closing the window doesn't save.
  - Loading a slot takes the newest save in it that reads (by its `saved` time); when that isn't the newest, the player is told which failed and which was loaded. A save made under another host name gives that player's progress to the new name.

### 4.11 Performance budgets

| What | Budget |
|---|---|
| Frame rate | 60 fps at 1080p, medium settings, Radeon 680M |
| Blocks per ship | ≤ 4,000 |
| Active ships near players | ≤ 12 |
| Players | ≤ 8 |
| Host physics tick | ≤ 8 ms with 12 ships |
| Network, per client | ≤ 64 KB/s down |
| Mesh rebuild after a hit | ≤ 4 ms per 16³ section; the whole-ship rebuild measured 2.9 ms for the starter ship and 3.8 ms at 500 blocks |

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
| Host sends a seed the game can't use | The client leaves with "The host sent a world this game can't make." |
| Game full | Refused with "The game is full (8 players)." |
| Port in use when hosting | "Port 24650 is already in use. Is another game running?" |
| Broken settings file | Defaults are used and the file is rewritten on the next save. |
| Broken save | The newest save in the slot that reads loads, and the player is told: "The latest save in slot 1 couldn't be read (ships.json is damaged), so the one from 2026-10-01 14:02 was loaded." With none readable, the menu says "Slot 1 couldn't be read: …" and a dedicated server starts a new world. |
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
| 2026-09-30 | Until stage 5, crew who fall overboard are put back aboard where they started (stage 5 replaced this with going ashore) |
| 2026-09-30 | LAN discovery is query and answer, not announcements, because only one program per machine can listen on 24651 |
| 2026-09-30 | Online games gather in a lobby until the host sets sail; late joiners go straight aboard |
| 2026-09-30 | A connection silent for 8 s counts as lost (ENet's default is 30 s) |
| 2026-09-30 | One world clock, seconds since the server's world began, drives the sky and client interpolation |
| 2026-09-30 | In stage 3 everyone crews the host's one ship; each machine walks only its own crew member, and crew don't collide |
| 2026-09-30 | Block rotations are Godot's orthogonal basis index (0–23) |
| 2026-09-30 | Propellers and rudders act along their facing |
| 2026-09-30 | Each player has one ship and one test flight at a time; a leaver's ships go with them |
| 2026-09-30 | A blueprint is refused with the first problem found, and nothing is loaded |
| 2026-09-30 | The shipyard opens only at the dock until towns arrive in stage 5 (it then opens at any town's dock) |
| 2026-09-30 | Wrecks are damaged starter ships until pirates arrive in stage 6 |
| 2026-09-30 | Towns are placed by seeded dart throwing, 1,500 m apart, per region, not Poisson sampling. The starting town is always at the start point. |
| 2026-09-30 | Every loaded chunk has collision and visuals, which switch off with `visibility_range`; only a dedicated server loads collision alone |
| 2026-09-30 | Translucent fog sheets over the Roil and depth fog (900–2,600 m) replace volumetric fog |
| 2026-09-30 | Landing on a ship's deck, or E within 3 m of her hull, puts you aboard; the stage 2 rule of 30 m below is gone |
| 2026-09-30 | Anchoring (G at the helm) freezes the ship where she is |
| 2026-09-30 | Crew ashore are drawn to others as a plain avatar, with no glider, until the polish stage |
| 2026-09-30 | River wind blends its segments, so it swings smoothly round bends instead of jumping between segments |
| 2026-09-30 | River wind is its segments' sum capped at the strongest, so rivers blowing opposite ways cancel to calm where they overlap |
| 2026-09-30 | The sky stays `ProceduralSkyMaterial` through stage 5; the custom sky shader moves to the polish stage |
| 2026-09-30 | Streaming counts focus points within 64 m of each other as one, and frees far chunks a few a frame |
| 2026-09-30 | Piers stand 1.5 m off a ship at each slipway, and docks are frictionless so a ship blown onto one slides along it; launches keep 1 m from dock obstacles and 2 m from ships |
| 2026-09-30 | Crew ashore report in world space (ship id 0), at most 50 m/s overall, with 0.01 m/s of slack on the server |
| 2026-09-30 | The world seed travels in the handshake (protocol 4), and a guest makes the world from it |
| 2026-10-01 | Ships carry spares (0–40) for repairs, filled free at docks, and lost ships rebuild free, until stage 7 prices them (it did) |
| 2026-10-01 | One mesh per ship, rebuilt whole at most once a frame; 16³ sections wait for big ships to stutter |
| 2026-10-01 | Crew are hit by where they last reported standing; a hit knocks you down for 5 s, with no health bar |
| 2026-10-01 | Pirates' guns are fired by their captains; there's no pirate crew, and pirates never board |
| 2026-10-01 | A helm on a piece under 4 blocks doesn't keep the ship: the hull stays, a wreck, and the helm goes as a splinter |
| 2026-10-01 | The starter ship's envelope is joined to her hull, so she breaks only where she's cut |
| 2026-10-01 | Pirate captains steer against the wind's drift, so they circle where they mean to |
| 2026-10-01 | A ship has exactly one helm; designs and blueprints with more are refused |
| 2026-10-01 | A ship that loses her helm loses power: throttle and rudder go to zero, and she drifts |
| 2026-10-01 | A player who arrives with no ship to board stands on the first town's quay |
| 2026-10-01 | A player's inventory is the crates they own, stowed in ships and saved with them; there's no separate store of weightless items |
| 2026-10-01 | Iron is unlocked from the start; alloy and lift stones unlock with money at towns further in |
| 2026-10-01 | No fuel until stage 8: fuel tanks are dead weight and trim is free; an engineer's boost stands in for the engine station |
| 2026-10-01 | Ammunition stays unlimited; spares cost money and reloads limit fire |
| 2026-10-01 | Spares cost 5 crowns; a launch costs the design's parts and spares less the old ship's worth, and a lost or abandoned ship is insured for half her cost |
| 2026-10-01 | Abandon ship (pause menu, twice) rescues a stranded captain; any loss puts the crew on the nearest quay at once |
| 2026-10-01 | Player names are unique on a roster ("Ann 2"), because progress is saved by name |
| 2026-10-01 | Saves keep every account by name; a leaver's ship waits in the save; guests' maps aren't saved |
| 2026-10-01 | Hired gunners aim at the target's block nearest her centre of mass, which can lie in the open air between deck and envelope |
