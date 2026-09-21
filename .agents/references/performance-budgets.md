# Performance Budgets

Targets from spec §110–§112 and the `runtime-performance` spec delta. They
are *targets until measured*: any perf report must show a measured value with
the hardware/renderer it was measured on, or be explicitly marked "not
measured".

## Machine budgets (V1)

| Budget | Value |
|---|---|
| Frame rate (normal gameplay) | 60 FPS at 1920×1080 on ordinary integrated graphics |
| Frame rate (large zoomed-out view, 96 tiles) | 60 FPS target |
| RAM (normal play) | < 700 MB |
| GPU memory | < 512 MB |
| Simulation tick | comfortably below the fixed-tick budget (20 Hz → 50 ms of tick time per second of game time at 1×; measure and record) |
| Domain test suite | green in under 30 s, headless, no window (project-foundation tasks 4.2) |

## Triangle budgets per asset class (spec §27, LOD0)

| lod_class | LOD0 max tris |
|---|---|
| Small prop | 500 |
| Tree | 800 |
| House | 2,500 |
| Station | 8,000 |
| Large industry | 10,000 |
| Wagon | 4,000 |
| Locomotive | 12,000 |

LOD counts decrease monotonically LOD0 → LOD1 → LOD2; `art validate`
enforces these numbers.

## Hard runtime prohibitions (spec §112 — never, no exceptions)

- No node per terrain tile (a 256×256 map = 65,536 tiles, 0 world nodes).
- No material per building (shared vertex-colour material only).
- No physics body per rail tile (selection is arithmetic).
- No animation of offscreen decorative objects.
- No pathfinding every simulation tick (paths cached; recomputed on
  `track_changed` or route edits only).
- No full-terrain rebuild for a local edit (dirty-region rebuild; a tile edit
  may rebuild at most the 4 chunks whose skirt touches it — counted).

Corresponding preferred mechanisms: chunking, instancing (`MultiMeshInstance3D`
per chunk per type), cached paths, dirty-region rebuilds, shared materials,
distance-based updates, event-driven updates.

## Structural budgets

| Structure | Count on Founder's Valley (256×256) |
|---|---|
| Terrain chunks | 64 (one mesh each) |
| Track scene nodes | scale with chunks × piece types, not tiles |
| Scenery draws | bounded by chunk × mesh count, not instance count |
| Terrain scene nodes | constant regardless of map size |
| World state nodes | constant (typed arrays, not nodes) |
| Map labels | one pooled `Control` layer, zoom-thresholded |

## Animation LOD tiers (driven by camera orthographic size as distance proxy)

| Distance | Visual treatment |
|---|---|
| Near | full mechanical animation, smoke/steam effects |
| Medium | mechanical animation, reduced effect rate |
| Far | reduced animation update frequency, particles disabled |
| Offscreen | visual animation suspended (`VisibleOnScreenNotifier3D`); simulation continues |

## Stress world (`python tools/rr.py stress --ticks 2000`)

Reproducible from a seed: 256×256 terrain, ~5,000 town/scenery objects,
~10,000 vegetation instances, 2,000 rail tiles, 100 stations, 100 industries,
100 trains. All 100 trains must report a status and the sim must complete
without errors. Two runs with the same seed produce identical placements and
consists. This exceeds normal V1 gameplay; it exists to catch scalability
failure, not to define budgets.

## Measurement requirements

- `F3` debug overlay shows: FPS, frame time, draw calls, visible objects,
  visible trains, terrain chunks, rail chunks, simulation tick time,
  pathfinding time, RAM estimate (Godot `Performance` monitors plus service
  counters for chunk rebuilds/pathfinding/tick time).
- Performance decisions are measured, not felt; do not prematurely move
  systems to native code (spec §102).
- UI panel refresh is throttled to 0.1 s so signal storms can't thrash
  layout.
