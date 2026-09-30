# Skywright

An airship game: design ships block by block, and real physics decides whether they fly. Crew them with friends, explore a generated sky of floating islands above an endless storm, and push toward the Eye.

Built with Godot 4.7.2. The design is in [`docs/superpowers/specs/2026-09-29-skywright-design.md`](docs/superpowers/specs/2026-09-29-skywright-design.md), and each stage's plan is in `docs/superpowers/plans/`.

## Status

**Stage 3 of 10 (Online co-op).** You can:
- walk the deck of the starter ship while it rolls in the wind, and climb its ladders;
- take the helm and fly between floating islands, with an autopilot and a chase view;
- watch day turn to night over the Roil, the storm below 200 m;
- crew one ship with up to 7 friends: one at the helm, the rest walking the deck, everyone in sync;
- find games on your network in a list, or join by address, or run a dedicated server.

Everyone crews the host's ship. Ships of your own arrive with the shipyard in stage 4.

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

1. One player chooses **Host game**. The lobby lists the crew and shows the address friends should use, for example `192.168.0.102:24650`.
2. Everyone else chooses **Join game**. Games on your network appear in a list, like `Ann's game   1/8`; pick one, or type the host's address.
3. When everyone's in the lobby, the host chooses **Set sail**. Anyone who joins later goes straight aboard.

On deck, E at the helm takes it if nobody has it; everyone else sees who's steering. Up to 8 players crew one ship.

Games use UDP port 24650, and the network list uses UDP port 24651. Over the internet, the host must forward UDP 24650 on their router, and friends join by address.

To test with two copies on one machine:

```bash
godot --path . -- --host --name=Ann
godot --path . -- --join=127.0.0.1 --name=Bob
```

Then choose **Set sail** in Ann's window. Launch options (after `--`): `--solo`, `--host`, `--join=ADDRESS`, `--server`, `--name=NAME`, `--port=PORT`.

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
src/ship/     blocks and the tuning file, the ship grid, the starter ship, flight forces, the ship body and mesh
src/crew/     each ship's interior world, crew members and how others see them, the helm, the player's controls and camera
src/ui/       menus, the HUD and the shared UI theme
src/world/    the world scene, sky, the Roil, islands, wind, the menu backdrop
tests/        test runner and tests
docs/         design spec and implementation plans
```

Every number that shapes how ships fly and handle is in `src/ship/tuning.gd`.

## Graphics on hybrid laptops

Godot picks a GPU at startup and prints it. On the development laptop it picks the discrete GPU: `Vulkan 1.4.354 - Forward+ - Using Device #1: NVIDIA - NVIDIA GeForce RTX 3050 6GB Laptop GPU (NVK GA107)`. To choose a different one, run it with `--verbose` to list the devices, then pass `--gpu-index N`. Index 0 is the integrated Radeon 680M.
