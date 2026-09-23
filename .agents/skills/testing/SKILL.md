# testing

## Purpose
Owns the headless Godot test suite: how tests are written, discovered and
run, what must stay covered (spec §106 + the mandatory integration
scenario), and the determinism rules that make assertions exact.

## When to use
Adding any simulation test; when changing behaviour that tests pin;
debugging a red suite; deciding what a new system must prove before merge.

## Non-goals
Perf measurement (`performance`), stress world operation (`diagnostics`),
art validation (`asset-validation`), CI provider config (none yet —
`rr.py test` is the contract).

## Dependencies
- Runner: `game/tests/runner.gd` (in-repo, ~200 lines; no third-party
  framework) discovers `game/tests/**/test_*.gd`; run via
  `python tools/rr.py test [--filter <substr>]`.
- A matched file contributing zero cases fails the run (no silent skips).
- `check` separately imports every script + diffs world constants
  (`rr.py check`) and treats any `SCRIPT ERROR` as failure.
- Determinism: fixed 20 Hz clock, injected seeded RNG, no wall-clock
  (`simulation-clock` invariants).

## Invariants
1. Domain tests run headless with **no UI loaded**; a full gameplay month
   executes without any UI node existing.
2. Mandatory coverage: rail connectivity, rail pathfinding, track
   construction validation, station coverage, cargo generation, cargo
   allocation, loading/unloading, revenue, ledger, train route execution,
   save/load round trip, simulation clock.
3. The core integration scenario exists and passing it gates health:
   create game → create rail → mine station → power station → purchase
   train → add coal wagons → configure route → advance simulation →
   verify coal moved → plant received → company revenue increased.
4. Assertions are exact (floats compared as configured integers/exact
   values; revenue to the unit of currency).
5. Economy guard: ledger reconstructs cash exactly; the guard is part of
   the suite, not documentation.
6. A failing case output names the test and expected-vs-observed values;
   exit code non-zero. Whole suite green in under 30 s, no window.

## Public interfaces
- Test file: `game/tests/domain/test_<area>.gd` exposing `func suite() ->
  Array[Callable]`-style cases (no decorators, no base-class ceremony).
- Helpers: build isolated `GameSession` (services wired, no UI),
  `advance_ticks(n)` / `advance_months(n)`, seeded RNG.
- Naming: file names filter-friendly (`test_rail_path.gd` matches
  `--filter rail`).

## Implementation rules
- New simulation behaviour lands with its test in the same change;
  balance-only data edits may reuse existing assertions.
- Prefer driving services directly over any scene instantiation;
  presentation-touching tests are the exception and say so in a comment.
- Determinism test guards: the clock is the only time source; rerun same
  seed twice, compare states.
- Use `--filter` while iterating; run the full suite before merge.
- When a test checks what presentation *drew*, read it back off the geometry —
  the mesh's vertex array, not the arguments that were handed to the renderer.
  Colours stored in a vertex array are bytes, so compare them at a 1/255
  tolerance (`check_near` per channel), never with `check_eq` on a `Color`.
- Presentation nodes that react to the controller are proved by connecting a
  real controller to a real renderer and feeding it pointer events; a renderer
  whose entry point nobody calls is invisible to a compile-only check.
- Never delete/weaken an assertion to go green — fix or justify on the PR
  (the integration scenario is untouchable).

## Validation
Meta-checks: deliberately fail one case ⇒ runner exits non-zero naming it;
empty test file in the tree ⇒ failure; integration scenario survives a
fresh `GameSession`.

## Common mistakes
- Testing through UI signals (UI may be absent by design).
- `randf()` without the session RNG in code under test (breaks exactness).
- Asserting timing in real seconds instead of ticks.
- Tests depending on each other's ordering (each builds its own session).

## Related skills
`simulation-clock`, `economy`, `cargo-system`, `route-system`, `rail-
network`, `save-load`, `performance`, `godot-project`, `validate-release`
workflow.
