# Skywright

An airship game: design ships block by block, and real physics decides whether they fly. Crew them with friends, explore a generated sky of floating islands above an endless storm, and push toward the Eye.

Built with Godot 4.7.2. The design is in [`docs/superpowers/specs/2026-09-29-skywright-design.md`](docs/superpowers/specs/2026-09-29-skywright-design.md), and each stage's plan is in `docs/superpowers/plans/`.

## Status

**Stage 5 of 10 (The sky world).** You can:
- fly a generated world: a disc 16 km across of floating islands, from the Calm Reaches in to the Stormwall and the Eye, the same for everyone who plays the same seed;
- visit ten towns, each with a dock, a shipyard and a beacon you can see from far off;
- ride sky rivers, fly through storms, and fit sails to a ship and sail with the wind;
- step off your ship onto an island, walk about, glide, and climb back aboard;
- anchor your ship so she stays put;
- open the map (M) to see what you've explored, and steer by the compass along the top of the screen;
- crew one ship with up to 7 friends, find games on your network in a list, or run a dedicated server;
- design ships block by block in the shipyard at any town's dock, test-fly them, launch them, and save designs as blueprints.

Everyone starts aboard the host's starter ship, and can launch a ship of their own from any town's dock.

## Controls

| Key | On deck | At the helm | Ashore |
|---|---|---|---|
| W A S D | Walk | W/S throttle, A/D rudder | Walk |
| Space | Jump, or climb a ladder | Climb | Jump; in the air, hold it to glide |
| Ctrl or C | Climb down a ladder | Descend | |
| Shift | Sprint | | Sprint |
| E | Take the helm | Leave the helm | Climb aboard, next to a ship |
| G | | Drop or raise the anchor | |
| H | | Autopilot on or off | |
| V | | Chase view | |
| M | Map | Map | Map |
| Mouse | Look | Look, or orbit in the chase view | Look |
| B | Shipyard, at a dock | | Shipyard, at a dock |
| Esc | Menu | Menu | Menu |

On a ladder, W climbs too. Throttle and trim stay where you leave them. The autopilot holds the heading and height it was switched on at, and A, D, Space and Ctrl adjust those.

## The world

The world is a disc 16 km across, centred on the Eye. The Roil, a storm sea, fills everything below 200 m, and islands float between 300 m and 1,800 m. It gets more dangerous toward the centre:

| Region | Distance from the centre |
|---|---|
| The Calm Reaches | 6,000 to 8,000 m. You start here. |
| The Shattered Belt | 4,000 to 6,000 m. Dense, broken islands, and wrecks. |
| The Gale Expanse | 2,200 to 4,000 m. Strong wind, sky rivers and storms. |
| The Stormwall | 1,600 to 2,200 m |
| The Eye | 0 to 1,600 m |

- **Islands** stream in around you, up to 2.5 km away, in three levels of detail. Tops are grassy and undersides are rock. Some have trees and waterfalls.
- **Towns.** Ten towns stand on big islands: four in the Calm Reaches (the first is where you start), three in the Shattered Belt, two in the Gale Expanse and one at the Stormwall. Each has a quay with a slipway for every player, a pier beside each slipway, houses and a beacon tower. The shipyard opens at any town's dock, and ships launch from that town. Landmarks (spires, arches and ruins) and wrecks of old starter ships are scattered about.
- **Wind** circles the Eye and blows harder toward it. **Sky rivers** are fast currents, up to 35 m/s, that you can ride or fight. **Storm cells** are drifting circles of gusts and updrafts, with lightning. Sails push a ship along the way they face. The wind is the same for everyone, because it comes from the seed and the world clock.
- **The Roil** is at the bottom of everything. Fog sheets lie over it, and lightning flickers in it.
- **The map** (M) fills in as you fly. The compass shows your bearing, the towns you've seen, and the region you're in.
- **Seeds.** Each game's world comes from a seed, and the same seed always makes the same world. The pause menu shows it. Pick one with `--seed=N` (0 to 2147483647) to play a world again. Friends who join get the host's world.

## On foot

- **Stepping off.** Walk off the edge of the deck and you're ashore. At a dock, a pier runs beside each slipway, just below the deck. You keep the ship's speed at first.
- **Gliding.** Fall and hold Space to open a glider: about 13 m/s forward and sinking no faster than 3 m/s. Let go and you fall. Land on an island and walk around.
- **Climbing aboard.** Land on a ship's deck, or stand beside her hull and press E.
- **The Roil.** Fall into it and you're put back aboard.
- **Anchoring.** At the helm, G drops the anchor: the ship stops and stays exactly where she is, whatever the wind. The readout says "Anchored". G again raises it.

Friends see you wherever you go, as a plain figure with no glider. Ashore you move at 50 m/s at most.

## The shipyard

Every town has a dock, and you start at the first one. Each player has a slipway at each. Stand within 150 m of a dock and press B to open the shipyard. B or Esc closes it.

| Key | Shipyard |
|---|---|
| Left click | Place a block |
| Right click | Remove a block |
| Right-drag, or W A S D | Orbit |
| Mouse wheel | Zoom |
| R | Turn the block |
| T | Tip the block |
| M | Mirror mode: edits happen on both sides of the keel |
| Ctrl+Z | Undo |
| Ctrl+Y, or Ctrl+Shift+Z | Redo |
| F | Test flight |
| B | Back from a test flight |

The panels show what your design will do: weight, lift, where she floats, thrust, top speed and climb rate. Two markers show the centre of mass and the centre of lift. If they don't line up, she lists or trims that way. Warnings say what's wrong before you fly: "Lists 8° to port", "Too heavy to fly", "Every ship needs a helm".

**Test flight.** F puts a copy of your design in the air with you at its helm. Fly it, then press B: you're back in the shipyard at once, with your design as you left it. You can have one test flight at a time.

**Launching.** Launch sends your design down your slipway at the town whose shipyard you're in as a real ship, and you and anyone aboard sail on it. You can have one ship at a time, so launching again replaces your last one. A player who leaves takes their ships with them. Building, testing and launching are free.

## Blueprints

A design is saved as a blueprint: a small text file, `<name>.skyship.json`. They live here:

- Linux: `~/.local/share/godot/app_userdata/Skywright/blueprints`
- Windows: `%APPDATA%\Godot\app_userdata\Skywright\blueprints`

To share a ship, send the file. To use one, copy it into that folder. **Open folder** in the shipyard opens it. A blueprint that's broken, too big (over 1 MB) or missing a helm is refused with the first problem found, and nothing is loaded.

## Run it

Install Godot 4.7.2 (the standard build, not .NET), put it on your PATH as `godot`, then:

```bash
godot --path .                # play
godot --path . -- --solo      # straight into a solo game
godot --path . -- --solo --seed=7   # the same world every time
godot --path . --editor       # open in the editor
```

## Play with friends

1. One player chooses **Host game**. The lobby lists the crew and shows the address friends should use, for example `192.168.0.102:24650`.
2. Everyone else chooses **Join game**. Games on your network appear in a list, like `Ann's game   1/8`; pick one, or type the host's address.
3. When everyone's in the lobby, the host chooses **Set sail**. Anyone who joins later goes straight aboard.

On deck, E at the helm takes it if nobody has it; everyone else sees who's steering. Up to 8 players crew one ship, or everyone can launch their own ship at their own slipway and fly alongside each other.

Games use UDP port 24650, and the network list uses UDP port 24651. Over the internet, the host must forward UDP 24650 on their router, and friends join by address.

To test with two copies on one machine:

```bash
godot --path . -- --host --name=Ann
godot --path . -- --join=127.0.0.1 --name=Bob
```

Then choose **Set sail** in Ann's window. Launch options (after `--`): `--solo`, `--host`, `--join=ADDRESS`, `--server`, `--name=NAME`, `--port=PORT`, `--seed=N`.

## Dedicated server

A server runs the world with no player of its own, for example on a VPS, so friends can play whenever they like:

```bash
godot --headless --path . -- --server                          # on UDP 24650
godot --headless --path . -- --server --port=25000 --name=Skyport
```

- It opens UDP 24650 for games (or `--port`) and answers network lists on UDP 24651. On a VPS, allow the game port through the firewall, for example `sudo ufw allow 24650/udp`. Behind a home router, forward it.
- `--name` names the game in network lists ("Skyport's game").
- While nobody is aboard, the ship is anchored: held still with the engines stopped.
- Stop it with Ctrl+C. Players see "Lost the connection to the host." within about 8 s.
- If the port is taken, it prints "Port 24650 is already in use. Is another game running?" and exits with status 1.

## Test

```bash
./run_tests.sh           # every test, headless
./run_tests.sh session   # only test files whose name contains "session"
```

A test fails when an assert fails, or when the engine logs an error the test didn't expect. The runner uses `--fixed-fps 60`, so each frame is exactly one physics tick and frames run as fast as they can: flight tests simulate minutes of flying in seconds. Network tests run several players in one process, each in a branch with its own network and 3D world. `test_two_games` also starts a dedicated server in a second process and paces its players in real time.

## Layout

```
src/core/     Settings and Game autoloads, launch options
src/net/      Session autoload (solo, host, join, lobby, dedicated server), LAN discovery, WorldSync and snapshot interpolation
src/ship/     blocks and the tuning file, the ship grid, blueprints, ship stats, the starter ship, flight forces, the ship body and mesh
src/builder/  the shipyard: the design and its undo, the 3D build view, the panels
src/crew/     each ship's interior world, crew members (aboard and ashore) and how others see them, the helm, the player's controls and camera
src/ui/       menus, the HUD, the map and compass, and the shared UI theme
src/world/    the world scene: the seeded world and its chunks, streaming, island shapes, towns and docks, landmarks and wrecks, wind, weather, exploration, the sky and the Roil, the menu backdrop
tests/        test runner and tests
docs/         design spec and implementation plans
```

Every number that shapes how ships fly and handle is in `src/ship/tuning.gd`.

## Graphics on hybrid laptops

Godot picks a GPU at startup and prints it. On the development laptop it picks the discrete GPU: `Vulkan 1.4.354 - Forward+ - Using Device #1: NVIDIA - NVIDIA GeForce RTX 3050 6GB Laptop GPU (NVK GA107)`. To choose a different one, run it with `--verbose` to list the devices, then pass `--gpu-index N`. Index 0 is the integrated Radeon 680M.
