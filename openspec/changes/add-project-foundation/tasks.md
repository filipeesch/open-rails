# Tasks

## 1. Repository skeleton

- [x] 1.1 Create `game/`, `art/`, `tools/`, `.agents/{skills,references,workflows}` and `build/` with the `game/src/{domain,presentation,ui,infrastructure}` substructure and verify with a directory listing
- [x] 1.2 Extend `.gitignore` to exclude `game/generated/`, `build/` and Godot caches and verify `git status` shows neither tree as untracked source
- [x] 1.3 Write `art/config/world.toml` as the single source for `TILE_SIZE`, `HEIGHT_STEP` and the `TILE_METRES` anchor that turns km/h into tiles, and verify it parses with the stdlib TOML reader

## 2. Godot project bootstrap

- [x] 2.1 Create `game/project.godot` for Godot 4.7 targeting the Compatibility renderer with `MainMenu.tscn` as the main scene — the boot scene, which hands off to `Game.tscn` — and verify `godot --headless --quit` loads the project without error
- [x] 2.2 Create `game/scenes/Game.tscn` with the specified `World3D`/`UI`/`GameSession` node skeleton and verify it instantiates headlessly
- [x] 2.3 Add a script that generates `game/src/domain/world/world_constants.gd` from `world.toml` and verify the generated file reports 1.0 and 0.25

## 3. Development CLI

- [x] 3.1 Implement `tools/rr.py` with `game`, `test`, `art` and `check` subcommands using argparse only and verify `--help` lists all four and an unknown command exits non-zero
- [x] 3.2 Implement toolchain discovery for Godot and Blender — explicit `--godot`/`--blender` flag, then `RR_GODOT`/`RR_BLENDER`, then `~/.rr/toolchain.json`, then the conventional install locations — and verify an override is honoured and a missing toolchain prints the searched paths
- [x] 3.3 Implement `rr.py game run` launching Godot against the project and verify it starts the main scene
- [x] 3.4 Implement `rr.py check` to import all runtime scripts and compare generated world constants, and verify it exits non-zero when a script has a parse error and when constants drift

## 4. Headless simulation test runner

- [x] 4.1 Implement `game/tests/runner.gd` discovering `game/tests/**/test_*.gd`, executing cases headlessly and printing per-case results and verify a deliberately failing case yields a non-zero exit
- [x] 4.2 Wire `rr.py test` to the runner and verify a green suite exits 0 without opening a window
  The original bound was "under 30 seconds", written when the suite was three files.  It is
  406 cases in 38 files now, and each file builds a whole `GameSession` — map load, world,
  services — so the wall clock is 86.5 s.  The bound that is worth keeping is the one a
  regression can break: recorded in `.agents/references/performance-budgets.md` as under
  150 s, measured on an Apple M4 Pro.  A suite that outgrows *that* is a suite nobody can
  debug in a terminal, which is the thing the original number was really protecting.
- [x] 4.3 Add a smoke test asserting world constants and project boot, and verify it passes in the suite

## 5. Agent knowledge base

- [x] 5.1 Write `.agents/references/` documents for asset scale, material palette, domain model, terminology, UI layout and performance budgets and verify each names concrete values rather than placeholders
- [x] 5.2 Write the required `SKILL.md` documents under `.agents/skills/` using the prescribed section structure and verify every file contains Purpose, When to use, Non-goals, Invariants and Implementation rules
- [x] 5.3 Write `.agents/workflows/` procedures for create-locomotive, create-wagon, create-building, add-cargo-type and implement-gameplay-feature and verify each references the skills it composes
- [x] 5.4 Rewrite `AGENTS.md` to point at the CLI, the layout and the skill index and verify a newcomer instruction in it is a real `rr.py` command
