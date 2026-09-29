# Skywright

An airship game: design ships block by block, and real physics decides whether they fly. Crew them with friends, explore a generated sky of floating islands above an endless storm, and push toward the Eye.

Built with Godot 4.7.2. The design is in [`docs/superpowers/specs/2026-09-29-skywright-design.md`](docs/superpowers/specs/2026-09-29-skywright-design.md), and the current stage's plan is in `docs/superpowers/plans/`.

## Status

**Stage 1 of 10 (Foundations).** You can:
- open the main menu;
- play solo;
- host a game or join one on your network;
- change settings.

Flying arrives in stage 2.

## Run it

Install Godot 4.7.2 (the standard build, not .NET), put it on your PATH as `godot`, then:

```bash
godot --path .            # play
godot --path . --editor   # open in the editor
```

## Play with friends

1. One player chooses **Host game**. The HUD shows the address friends should use, for example `192.168.0.102:24650`.
2. Everyone else chooses **Join game** and types that address.

Games use UDP port 24650. Over the internet, the host must forward that port on their router.

To test with two copies on one machine:

```bash
godot --path . -- --host --name=Ann
godot --path . -- --join=127.0.0.1 --name=Bob
```

Launch options (after `--`): `--host`, `--join=ADDRESS`, `--name=NAME`, `--port=PORT`.

## Test

```bash
./run_tests.sh           # every test, headless
./run_tests.sh session   # only test files whose name contains "session"
```

A test fails when an assert fails, or when the engine logs an error the test didn't expect.

## Layout

```
src/core/     Settings and Game autoloads, launch options
src/net/      Session autoload: solo, host, join, handshake
src/ui/       menus and the shared UI theme
src/world/    the world scene and the sky backdrop
tests/        test runner and tests
docs/         design spec and implementation plans
```

## Graphics on hybrid laptops

Godot picks a GPU at startup and prints it. On the development laptop it picks the discrete GPU: `Vulkan 1.4.354 - Forward+ - Using Device #1: NVIDIA - NVIDIA GeForce RTX 3050 6GB Laptop GPU (NVK GA107)`. To choose a different one, run it with `--verbose` to list the devices, then pass `--gpu-index N`. Index 0 is the integrated Radeon 680M.
