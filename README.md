# Skywright

An airship game: design ships block by block, and real physics decides whether they fly. Crew them with friends, explore a generated sky of floating islands above an endless storm, and push toward the Eye.

Built with Godot 4.7.2. The design is in [`docs/superpowers/specs/2026-09-29-skywright-design.md`](docs/superpowers/specs/2026-09-29-skywright-design.md), and each stage's plan is in `docs/superpowers/plans/`.

## Status

**Stage 7 of 10 (Towns and progression).** You can:
- trade crates between towns, each making two goods cheap and wanting two dear, carried in cargo bays that weigh your ship down where they're stowed;
- take contracts from town boards: deliveries, bounties, salvage and scouting;
- hire hands: gunners who fire at pirates, repairers who put out fires and mend, and engineers who drive the engine harder;
- unlock alloy plates and lift stones at towns further in, and pay for launches and spares, trading in your old ship;
- abandon a stranded ship, insured for half her cost;
- save and continue in three slots, with autosaves, and pick up a co-op game where you left it;
- man a cannon and fire round shot, chain shot, shells and harpoons on arcs you can see before you shoot;
- shoot holes in ships, cut them apart, and send severed envelopes floating off, while the part with the helm flies on what's left;
- fight pirates who raid you away from the towns, circling and firing broadsides;
- repair your ship with spares, rebuild lost planks and patch the envelope, and put out fires;
- salvage spares from wrecks, and lose a ship to the Roil and rebuild her from her blueprint;
- fly a generated world: a disc 16 km across of floating islands, from the Calm Reaches in to the Stormwall and the Eye, the same for everyone who plays the same seed;
- visit ten towns, each with a dock, a shipyard and a beacon you can see from far off;
- ride sky rivers, fly through storms, and fit sails to a ship and sail with the wind;
- step off your ship onto an island, walk about, glide, and climb back aboard;
- anchor your ship so she stays put;
- open the map (M) to see what you've explored, and steer by the compass along the top of the screen;
- crew one ship with up to 7 friends, find games on your network in a list, or run a dedicated server;
- design ships block by block in the shipyard at any town's dock, test-fly them, launch them, and save designs as blueprints.

Everyone starts aboard the host's starter ship with 1,500 crowns, and can launch a ship of their own from any town's dock.

## Controls

| Key | On deck | At the helm | Ashore |
|---|---|---|---|
| W A S D | Walk | W/S throttle, A/D rudder | Walk |
| Space | Jump, or climb a ladder | Climb | Jump; in the air, hold it to glide |
| Ctrl or C | Climb down a ladder | Descend | |
| Shift | Sprint | | Sprint |
| E | Take the helm, man a cannon, or salvage a wreck | Leave the helm | Climb aboard, next to a ship; salvage a wreck |
| R (hold) | Repair the block you look at | | |
| G | | Drop or raise the anchor | |
| H | | Autopilot on or off | |
| V | | Chase view | |
| M | Map | Map | Map |
| Mouse | Look | Look, or orbit in the chase view | Look |
| B | Shipyard, at a dock | | Shipyard, at a dock |
| T | Town, at a dock | | Town, at a dock |
| Esc | Menu | Menu | Menu |

At a cannon, the mouse aims (within its arc), left click fires and Q changes the ammunition; E leaves it. The pause menu (Esc) has Save game and Abandon ship.

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
- **Towns.** Ten towns stand on big islands: four in the Calm Reaches (the first is where you start), three in the Shattered Belt, two in the Gale Expanse and one at the Stormwall. Each has a quay with a slipway for every player, a pier beside each slipway, houses and a beacon tower. The shipyard opens at any town's dock, and ships launch from that town. Landmarks (spires, arches and ruins) and wrecks of old pirate ships are scattered about.
- **Wind** circles the Eye and blows harder toward it. **Sky rivers** are fast currents, up to 35 m/s, that you can ride or fight. **Storm cells** are drifting circles of gusts and updrafts, with lightning. Sails push a ship along the way they face. The wind is the same for everyone, because it comes from the seed and the world clock.
- **The Roil** is at the bottom of everything. Fog sheets lie over it, and lightning flickers in it.
- **The map** (M) fills in as you fly. The compass shows your bearing, the towns you've seen, and the region you're in.
- **Seeds.** Each game's world comes from a seed, and the same seed always makes the same world. The pause menu shows it. Pick one with `--seed=N` (0 to 2147483647) to play a world again. Friends who join get the host's world.

## On foot

- **Stepping off.** Walk off the edge of the deck and you're ashore. At a dock, a pier runs beside each slipway, just below the deck. You keep the ship's speed at first.
- **Gliding.** Fall and hold Space to open a glider: about 13 m/s forward and sinking no faster than 3 m/s. Let go and you fall. Land on an island and walk around.
- **Climbing aboard.** Land on a ship's deck, or stand beside her hull and press E.
- **The Roil.** Fall into it and you're put back aboard, or if there's no ship left, you wake on the nearest town's quay. When the ship you're on is lost, you wake on the quay at once.
- **Anchoring.** At the helm, G drops the anchor: the ship stops and stays exactly where she is, whatever the wind. The readout says "Anchored". G again raises it.

Friends see you wherever you go, as a plain figure with no glider. Ashore you move at 50 m/s at most.

## Combat

- **Cannons.** The starter ship carries two, one on each side. Stand by one and press E to man it. While you man it, a white line shows where a shot would fly. A cannon turns 40° either way from where it faces, and reloads in 4 s.
- **Ammunition.** Q cycles through four kinds, and cannons never run out:
  - **round shot** punches through about two planks;
  - **chain shot** shreds balloons;
  - **shells** burst, hurting everything within 3 m and setting wood alight;
  - **harpoons** tie a rope between the two ships for 45 s.
- **Damage.** Every block has hit points. Shots break blocks, and a broken block is gone: you can see the hole and fall through it, and the ship flies on what's left. Lose balloons and she sinks or lists; lose a propeller and she pulls to one side. The helm's readout shows her hull and spares.
- **Breaking apart.** A section cut off from the helm's piece breaks away as a wreck, keeping its speed. A severed envelope floats off, and the ship falls. A helm shot loose on its own is lost, and the ship becomes a wreck that can't be steered. Pieces under 4 blocks vanish.
- **Being hit.** A shot through you, or a shell bursting within 3 m, knocks you down for 5 s. You come to at a bunk, or by the helm.
- **Repairs.** Hold R and look at a block within 6 m. Four times a second, a repair puts out any fire there, or else uses one spare to heal a damaged block or rebuild a lost one beside it from the ship's blueprint. That patches the envelope from the deck, too. Helms and cannons can't be rebuilt away from a shipyard. A ship carries up to 40 spares, bought at any town's dock for 5 crowns each.
- **Fires.** Shells set wood and cloth alight. Fire eats 5 hit points a second, spreads, and burns out after 30 s. Hold R at it to put it out, which is free.
- **Pirates** raid crewed ships away from the towns: up to one at a time in the Calm Reaches, and two further in. They chase you, circle about 350 m out, and fire broadsides. Shoot off a pirate's helm and she's a wreck. Pirates leave when you get far away.
- **Salvage.** Press E by a wreck to salvage her. Each wreck in the world gives 150 crowns and 12 spares once, and the world remembers she's been stripped. A broken-off wreck gives a spare for every 10 blocks and a crown a block, and is broken up. The spares go to the ship you're aboard, else your own, as many as fit.
- **The Roil.** Below 200 m the storm wears away a ship's blocks. Below 0 m she's lost. Her captain's shipyard then holds her blueprint, and launching rebuilds her whole, for half her cost: her insurance pays the rest.

## Towns and money

- **Purses.** Each player has their own purse of crowns, starting at 1,500, shown under your name. The host keeps the books.
- **Markets.** T at a town's dock opens the town. Its market buys and sells crates of grain, timber, cloth, tools and spirits. Each town makes two goods and sells them cheap (about 0.6 of the usual price), and wants two and pays dear (about 1.5), so buy where a good is made and sell where it's wanted. A market pays 85% of what it charges. Prices come from the world's seed and don't move with trade.
- **Cargo.** A crate fills a cargo bay and weighs 100 kg where it's stowed: crates in the bow put her down by the bow, and a full hold floats lower. The starter ship has four bays. Crates belong to whoever bought them, and you can sell only your own.
- **Contracts.** Each town's board offers three. A delivery loads mail crates and pays when a ship carrying them docks at its town. A bounty pays for pirates beaten within 1.5 km of you. Salvage pays when you strip the named wreck, and scouting when you get within 400 m of the landmark. Titles say how far and which way. You can hold three, and drop one anywhere.
- **Hands.** The town's Crew section hires hands onto the ship you're aboard, one per bunk (the starter ship has two). A gunner (150 crowns) mans a cannon and fires at pirates. A repairer (120) puts out fires, then mends with the ship's spares. An engineer (200) tends an engine, for about 12% more speed. Hands go down with their ship and move to the one that replaces her.
- **Parts.** Wood and iron are free to build with. Alloy plates unlock for 2,000 crowns at towns in the Shattered Belt or further in, and lift stones for 4,000 in the Gale Expanse or further in. A design with locked parts can be test-flown but not launched.
- **Launch prices.** A ship costs her parts and a full load of 40 spares: the starter ship is 1,350 crowns. Launching trades in your old ship at what she's worth now, so relaunching a damaged ship costs what her damage is worth, and a smaller ship costs nothing. Crates aboard move to the new ship. The Launch button shows the price.
- **Insurance.** A ship lost to the Roil, or abandoned, is insured for half her cost, and your next launch counts it as her trade-in.
- **Abandon ship.** The pause menu's Abandon ship (press it twice) gives up your ship wherever she is, and you wake on the nearest town's quay. It's how a captain whose helm was shot off gets home.

## Saves

- **Slots.** Play solo and Host game ask for a slot, 1 to 3: Continue its game, or start a New game (over a used slot, press it twice).
- **Autosaves.** The host's game autosaves every five minutes, when a ship docks (at most every 30 s), and when you leave. Each slot keeps the save made by hand (pause menu, Save game) and the last three autosaves.
- **Falling back.** Continue loads the newest save in the slot that reads. If that isn't the newest, because a file is damaged, it says so when you arrive.
- **What's kept.** Every ship but pirates and wrecks, with her damage, crates and hands; every player's purse, contracts and unlocks, by name; the clock, the stripped wrecks, and the host's map. A friend's ship waits in the save until they come back under the same name. Pirates, wrecks, fires and contract boards aren't kept. Closing the window doesn't save; the last autosave is at most five minutes old.
- **Where.** `~/.local/share/godot/app_userdata/Skywright/saves/<slot>` on Linux, `%APPDATA%\Godot\app_userdata\Skywright\saves\<slot>` on Windows. Each save is three JSON files.

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

The panels show what your design will do: weight, lift, where she floats, thrust, top speed and climb rate. Two markers show the centre of mass and the centre of lift. If they don't line up, she lists or trims that way. Warnings say what's wrong before you fly: "Lists 8° to port", "Too heavy to fly", "Every ship needs a helm" (and only one), or blocks that aren't joined to the helm and would fall away when she's hit.

**Test flight.** F puts a copy of your design in the air with you at its helm. Fly it, then press B: you're back in the shipyard at once, with your design as you left it. You can have one test flight at a time.

**Launching.** Launch sends your design down your slipway at the town whose shipyard you're in as a real ship, and you and anyone aboard sail on it. You can have one ship at a time, so launching again replaces your last one, for her price less what the old one is worth (see Towns and money). A player who leaves takes their ship with them, and finds her waiting when they come back. Building and test flights are free.

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
- It plays the `server` save slot: it continues its last world, autosaving as a host does, and starts a new world if the slot is empty or can't be read (saying why).

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
src/ship/     blocks and the tuning file, the ship grid, blueprints, ship stats, the starter ship, flight forces, damage, the ship body and mesh
src/builder/  the shipyard: the design and its undo, the 3D build view, the panels
src/crew/     each ship's interior world, crew members (aboard and ashore) and how others see them, the helm, the player's controls and camera
src/ui/       menus (with the saved games), the HUD, the town panel, the map and compass, and the shared UI theme
src/combat/   projectiles (shots, bursts and harpoon ropes) and cannons
src/ai/       the pirate ship and its captain, and hired hands
src/economy/  the economy's rules (prices, part costs, contracts) and the Ledger that keeps every player's account
src/save/     saved games: slots, the three files, autosaves and falling back
src/world/    the world scene: the seeded world and its chunks, streaming, island shapes, towns and docks, landmarks and wrecks, wind, weather, exploration, the sky and the Roil, the menu backdrop
tests/        test runner and tests
docs/         design spec and implementation plans
```

Every number that shapes how ships fly and handle is in `src/ship/tuning.gd`.

## Graphics on hybrid laptops

Godot picks a GPU at startup and prints it. On the development laptop it picks the discrete GPU: `Vulkan 1.4.354 - Forward+ - Using Device #1: NVIDIA - NVIDIA GeForce RTX 3050 6GB Laptop GPU (NVK GA107)`. To choose a different one, run it with `--verbose` to list the devices, then pass `--gpu-index N`. Index 0 is the integrated Radeon 680M.
