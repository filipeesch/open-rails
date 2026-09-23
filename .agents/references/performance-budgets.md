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
| Domain test suite | green in under 150 s, headless, no window. Measured: 406 cases in 38 files in 86.5 s (≈213 ms per case) on an Apple M4 Pro — see the measured table below. This is a *regression bound*, not a speed target: the suite pays for a whole `GameSession` (map load, world build) per file, so the honest budget is one month of cases per second, and a suite that stops being debuggable in a terminal is the thing to notice. (project-foundation tasks 4.2 originally claimed "< 30 s" against a 3-file suite; that number stopped being true when the map, render and UI suites arrived.) |

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

## Measured report

`runtime-performance` demands a measured line per budget, with the environment
it was measured on, or an explicit "not measured".  This is that record; the
line that stops being true is the line that has to be re-measured.

**Environment:** Apple M4 Pro, 12 cores, 24 GB RAM, macOS 26.7, Godot 4.7.2
Standard headless, Compatibility renderer.  Command:
`python tools/rr.py stress --ticks 2000`, run 2026-09-23.

| Budget | Measured | Notes |
|---|---|---|
| Simulation tick | **23.9 ms of tick time per second of game time at 1×** (48 % of the 50 ms budget) | 2,000 ticks in 2,895 ms = 691 ticks/s, avg tick 1,193 µs, with 100 trains and 5,000 buildings alive |
| RAM | **31 MB** in the headless stress world | No renderer, no meshes: this is the *simulation and world state* cost, and it is what spec §112's "world state is not nodes" promise buys.  RAM with the renderer loaded is **not measured** — measure it in a windowed run |
| Frame rate at 1920×1080 | **not measured** | Headless runs draw nothing.  Measure with `rr.py game run` and the `F3` overlay, on the integrated display |
| GPU memory | **not measured** | Needs a windowed run; `F3` shows the `Performance` video-memory monitor |
| Pathfinding off the tick | **200 path finds for 2,000 ticks**, 63.2 ms of query time in total | Every find is a route or a `track_changed` event; nothing in `_tick` queries (spec §112) |
| No node per world entity | **0 extra scene nodes for 5,000 buildings and 10,049 vegetation instances** | The stress world's entity counts are occupancy records, not nodes |
| Reproducibility | **identical checksum across two builds** (`955786920013269750`) | Same seed ⇒ same placements, consists and result |
| Terrain rebuild locality | **not measured headless** (0 rebuilds recorded because nothing meshes) | Measure a one-tile edit's rebuild count in a windowed run with `F3` |

## Measurement requirements

- `F3` debug overlay shows: FPS, frame time, draw calls, visible objects,
  visible trains, terrain chunks, rail chunks, simulation tick time,
  pathfinding time, RAM estimate (Godot `Performance` monitors plus service
  counters for chunk rebuilds/pathfinding/tick time).
- Performance decisions are measured, not felt; do not prematurely move
  systems to native code (spec §102).
- UI panel refresh is throttled to 0.1 s so signal storms can't thrash
  layout.
