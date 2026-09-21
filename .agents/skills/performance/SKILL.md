# performance

## Purpose
Owns performance discipline: budgets, profiling method, render/simulation/
memory measurement, and the rule that decisions are measured — never felt,
never prematurely native.

## When to use
Before/after any feature that touches per-frame or per-tick work; reviewing
draw-call or node growth; RAM/GPU regressions; tuning questions like "can
we afford N?".

## Non-goals
The stress world's operation (`diagnostics`), the anti-pattern list's
enforcement points (each runtime skill), micro-optimising assets beyond
budget (`mesh-optimization`).

## Dependencies
- Budgets (`.agents/references/performance-budgets.md`): 60 FPS @ 1920×1080
  on integrated graphics; RAM < 700 MB; GPU < 512 MB; sim tick comfortably
  inside the 20 Hz fixed-tick budget; domain suite < 30 s.
- `F3` debug overlay: FPS, frame time, draw calls, visible objects, visible
  trains, terrain chunks, rail chunks, simulation tick time, pathfinding
  time, RAM estimate — Godot `Performance` monitors plus service counters
  (terrain/rail chunk rebuilds, tick time, pathfinding time).
- Stress world: `python tools/rr.py stress --ticks 2000`.

## Invariants
1. Every performance claim in this repo carries a measured number + the
   environment it was measured on (hardware/renderer), or is marked "not
   measured" — reports state measurements, not claims.
2. The prohibitions are absolute (`AGENTS.md` list: node/tile,
   material/building, physics body/rail tile, offscreen animation,
   pathfinding/tick, full-terrain rebuild). A PR violating one needs a
   spec change, not a waiver.
3. Scaling properties are the first test: doubling entities must keep draw
   calls bounded by chunks×meshes, nodes constant for statics, and rebuild
   counts bounded (≤4 chunks/tile edit).
4. Do not move systems to native code early; profile, then fix the
   algorithm/structure — GDScript with the right data layout is the V1 plan.
5. Measurement runs on a dev build with the Compatibility renderer; numbers
   from Forward+ or editor-profiling runs are not the reported numbers.

## Public interfaces
- `python tools/rr.py stress --ticks N` (headless; logs tick time, status
  summaries).
- Debug overlay (`F3`) + service counters exposed for scripts/tests.
- A perf-report note format: environment line + budget table rows
  "budget | measured | status".

## Implementation rules
- Measure before and after features that touch tick/render loops; record
  both numbers in the PR.
- Watch the counters, not the FPS dip: a chunk-rebuild spike of 64
  identifies the bug; "felt slow" doesn't.
- Cache-friendly layouts first (typed arrays, batched loops) before
  algorithm changes; then algorithm (cached paths, event-driven updates).
- Keep per-frame LINQ-style allocations out of hot loops (GDScript
  `new()`/array churn shows up in GC spikes).
- UI refresh throttle (0.1 s) is a performance rule, not a style choice.

## Validation
The budgets themselves: stress run completes with all 100 trains reporting;
`F3` metrics recorded into `build/` notes with environment; regression
threshold alerts — e.g. draw-call count at furthest zoom grows >20% without
explanation ⇒ flagged.

## Common mistakes
- Optimising on the dev machine's dGPU and declaring victory (target is
  integrated graphics).
- Fixing a rebuild storm by rate-limiting the symptom instead of dirty
  regions.
- "Temporary" per-tile nodes that outlive the prototype.
- Benchmarking with the debug overlay itself enabled (it costs; toggle off
  for final numbers).

## Related skills
`diagnostics`, `runtime-rendering`, `terrain-system`, `lod-policy`,
`mesh-optimization`, `testing`, `performance-budgets` reference.
