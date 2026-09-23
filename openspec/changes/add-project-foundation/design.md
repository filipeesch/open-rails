# Design

## Context

Greenfield repository: one commit containing a README, `.gitignore` and `docs/requirements/v1.md`, plus an initialised OpenSpec root. Nothing is buildable. The V1 specification mandates Godot 4.7.2 Standard with GDScript, Blender as an offline asset compiler, a specific directory tree and a single development CLI that agents and humans share. The machine has Python 3.14, `uv` and Blender 5.2 LTS; Godot is not installed by default, so the CLI must discover it rather than assume a fixed path.

## Goals / Non-Goals

**Goals:**
- Make `python tools/rr.py` the only way anything gets built, run or tested in this repository.
- Make the domain test loop fast enough to run on every edit — headless, seconds, no rendering.
- Establish the one place world constants live, so art and runtime can never disagree about scale.
- Give agents the project knowledge they need without re-deriving it from the 3,600-line requirement document.

**Non-Goals:**
- No gameplay, no CI provider configuration beyond a runnable command, no packaging or release tooling.
- No third-party Python dependencies in `tools/` — the CLI must run on a bare interpreter.

## Decisions

**Godot test harness over a Python test framework.** Domain logic lives in GDScript because that is the runtime language, so tests must execute inside Godot. Running `godot --headless --script` against a test runner script keeps a single language and avoids a second implementation of the simulation for testing. `gdUnit`-style third-party add-ons are rejected: they add a vendored dependency and slow the loop; a ~200-line in-repo runner (`game/tests/`) gives the same reporting and can assert exact floats.

**`rr.py` as a stdlib-only dispatcher.** `argparse` subcommands map one-to-one onto the spec's command list. Alternatives considered: `make` (awkward on Windows, hides output), `nox`/`tox` (dependency), direct `godot` invocation (violates "agents use the same commands humans use"). Environment overrides `RR_GODOT` and `RR_BLENDER`; discovery is explicit flag → environment → `~/.rr/toolchain.json` → conventional install paths.

**Shared constants generated, not hand-mirrored.** `art/config/world.toml` is the source; `tools/rr.py` generates `game/src/domain/world/world_constants.gd` from it, and `check` regenerates in memory and diffs, failing on drift. A hand-maintained duplicate on each side was rejected because drift is silent and produces art at the wrong scale.

**Test discovery by filename convention.** Files matching `game/tests/**/test_*.gd` each expose `func suite() -> Array[Callable]`-style cases; the runner instantiates, runs, catches failures and prints a summary. Keeps test authoring free of decorators or base-class ceremony.

**`.agents/` content is documentation, generated once.** Skills use the prescribed SKILL.md section layout. These are written from the requirement document, not invented, so a later contributor reads project decisions rather than generic advice.

## Risks / Trade-offs

- [Godot binary absent on a fresh machine] → `rr.py` prints the exact download for 4.7.2-stable plus the `RR_GODOT` override; `check` reports missing toolchain as its first diagnostic.
- [A hand-rolled test runner silently skips tests] → the runner reports the number of collected cases per file and fails when a matched file contributes zero cases.
- [Headless import errors are easy to miss in Godot] → `check` runs a full project import and treats any `SCRIPT ERROR` line on stderr as failure rather than trusting the exit code alone.
