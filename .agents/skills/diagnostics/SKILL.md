# diagnostics

## Purpose
Owns the developer-facing visibility layer: the `F3` debug overlay, service
counters, the stress world runner, and the log/toolchain failure surfaces
that make "why is this slow/wrong?" answerable in one step.

## When to use
Investigating a bug or regression; reproducing scale failures; wiring a new
service's counters; reading a failing `rr.py art build` log; answering
"what is train #47 doing?".

## Non-goals
Budget policy and measurement method (`performance`); test authoring
(`testing`); Blender job internals (`blender-headless`).

## Dependencies
- `F3` (`debug_overlay` action) on dev builds: FPS, frame time, draw calls,
  visible objects, visible trains, terrain chunks, rail chunks,
  simulation tick time, pathfinding time, RAM estimate.
- Service counters (not a profiler): `terrain_chunk_rebuilds`,
  `rail_chunk_rebuilds`, pathfinding query count + time, tick time,
  allocation total vs produced (cargo conservation).
- `python tools/rr.py stress --ticks N` — seed-reproducible synthetic world
  (256×256, ~5k town/scenery objects, 10k vegetation instances, 2k rail
  tiles, 100 stations/industries/trains).
- `rr.py` toolchain diagnostics: missing Godot/Blender messages list the
  env vars (`RR_GODOT`/`RR_BLENDER`) and searched paths.

## Invariants
1. The overlay shows a value for every listed metric whenever visible, and
   toggles off on a second `F3`.
2. Counters are cumulative-since-boot plus last-window; they are plain
   integers on services — readable from tests and the overlay alike, no
   debug-only singletons.
3. Stress runs are reproducible: same seed ⇒ identical entity placements
   and consists; results quote the hardware/renderer.
4. Diagnostics are read-only: observing must not change simulation
   (counters increment as a side effect of work, nothing more).
5. The overlay is cheap enough to leave open during normal development; it
   is excluded from release builds.

## Public interfaces
`DebugOverlay` (autoload-free, built into `Game.tscn` UI layer):
- toggle on `debug_overlay`; each metric row is `name = value`.
- Service counter registry: `Counters.get("terrain_chunk_rebuilds")`.
- Stress entry point: `tests/stress_world.gd` driven by `rr.py stress
  --ticks 2000`; prints per-phase summaries and a final 100-train status
  table.

## Implementation rules
- New risky loop? Add its counter with the feature (tick-time of a new
  monthly phase, query count of a new A* user) — make it visible the day
  it lands.
- Investigate slow frames by counter deltas across the frame, not by
  adding prints ad hoc; promote a recurring print to a counter.
- Stress findings: attach the seed + `rr.py` invocation to the report so
  anyone can rerun it.
- Art-build failures: read the named per-job log first; `--keep-temp` when
  iterating on a broken builder.

## Validation
`F3` twice toggles with all rows populated; counters increase under
scripted load (add 500 rail tiles ⇒ bounded chunk rebuilds); stress run
twice with same seed ⇒ byte-identical placement summary; overlay absent
from a release-profile export list.

## Common mistakes
- Debug overlay reading wall time for "tick time" (use tick budget units).
- A counter that itself allocates per frame (defeats observation).
- Reproducing "random" slowness without the seed (stress is seeded — use
  it).
- Trusting exit codes alone on Godot headless runs — `check` already scans
  stderr for `SCRIPT ERROR`; read those lines.

## Related skills
`performance`, `testing`, `runtime-rendering`, `blender-headless`,
`godot-project`, `simulation-clock`, `validate-release` workflow.
