# Proposal

## Why

The repository currently contains only a README and a requirements document. Nothing can be built, run, tested or handed to another contributor or agent, and there is no place for the shared conventions (tile scale, material palette, domain terminology) that every later system must agree on. Milestone 0 of the V1 specification exists precisely to remove that blocker before any gameplay code is written.

## What Changes

- Create the repository layout mandated by the specification (`game/`, `art/`, `tools/`, `docs/`, `.agents/`, `build/`) with explicit ownership boundaries.
- Create a Godot 4.7.2 Standard project using the Compatibility renderer, GDScript only, with a bootable main scene.
- Add one repository-wide development CLI, `python tools/rr.py`, exposing `game run`, `test`, `art build`, `art validate`, `art preview` and `check`, so agents and humans use identical commands.
- Add a headless simulation test runner that executes domain tests without rendering.
- Add toolchain discovery for Godot and Blender with actionable errors instead of silent failure.
- Add one shared world-constants source (`TILE_SIZE = 1.0`, `HEIGHT_STEP = 0.25`) consumed by both the art tooling and the runtime, and never re-declared per asset.
- Populate `.agents/` with the skill, reference and workflow documents required by the specification.

## Capabilities

### New Capabilities
- `project-foundation`: Repository layout, Godot project bootstrap, the `rr.py` development CLI, headless test running, toolchain discovery, shared world conventions and the `.agents/` knowledge base.

### Modified Capabilities
_(none — this is the first change in the repository)_

## Impact

- New top-level directories and `game/project.godot`.
- New Python package `tools/` (no third-party runtime dependencies).
- New `.agents/skills`, `.agents/references`, `.agents/workflows` documents.
- No gameplay behaviour exists yet; every later change builds on this layout and on the CLI as its only entry point.
