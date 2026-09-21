# runtime-rendering

## Purpose
Owns how world state becomes pixels: render chunks, instancing strategy,
visibility, LOD selection, material reuse, draw-call policy — under the
Compatibility renderer. Rendering is a *projection* of domain state; it owns
no state.

## When to use
Adding a renderer for any entity family, touching chunk rebuilding, scenery
instancing, track batching, materials at runtime, or draw-call regressions.

## Non-goals
Domain rules (per-system skills), terrain data ownership
(`terrain-system`), particle effects (`runtime-effects`), asset-side LOD
authoring (`lod-policy`).

## Dependencies
- `WorldGrid` + its change notifications (affected tiles) — the only source
  of truth; `WorldRenderer`, `TerrainRenderer`, `RailRenderer`,
  `EntityRenderer`, `Effects` read state, never own it.
- Chunks: 32×32 tiles, 64 for a 256×256 map; one terrain mesh per chunk;
  per-chunk `MultiMeshInstance3D` batches for scenery and each track piece
  type.
- Shared materials: one vertex-colour material, one company-colour material,
  one cheap water material (see `material-palette`).
- LOD selection driven by camera orthographic size (`lod-policy`).
- Renderer: `gl_compatibility`; no Forward+-only features.

## Invariants
1. Node count is independent of tile count: 65,536 tiles ⇒ zero per-tile
   nodes; entity visuals exist only for entities that genuinely need a
   runtime visual.
2. A local change rebuilds only dirty chunks (one-tile neighbour skirt for
   seam correctness ⇒ at most 4 chunks); rebuild counters are exposed.
3. Repeated static content draws via instancing; scene-tree contribution is
     independent of instance count.
4. Materials are shared; a per-building or per-chunk unique material is a
   defect.
5. Offscreen visuals suspend updates (VisibleOnScreenNotifier3D); simulation
   is unaffected.
6. An identical network/world state always produces identical geometry —
   render strictly from state, never from edit history.

## Public interfaces
- `TerrainRenderer` / `RailRenderer`: subscribe to grid change events;
  expose rebuild counters (`terrain_chunk_rebuilds`, `rail_chunk_rebuilds`).
- `EntityRenderer`: spawn/retire visuals for stations, industries, trains —
  one instanced scene per asset id, resolved through the manifest adapter.
- Ground sampling: terrain elevation at world position (used by ghosts,
  previews, labels).

## Implementation rules
- Build chunk meshes as a single `ArrayMesh` with vertex colours + the shared
  material; include the one-tile skirt; use SurfaceTool at chunk level, not
  per tile.
- Track pieces come from the 256-entry connection-mask piece table; unknown
  masks fall back to straight-and-isolated, never a crash.
- Frustum culling is Godot's job — keep chunk bounding boxes honest.
- Distance-based update rates for animation via camera size + per-entity
  distance buckets; never per-entity distance queries for everything
  every frame.
- When adding a renderer feature, first state its draw-call/node delta; if
  it scales with entity count, redesign it.

## Validation
`F3` overlay draw calls / chunk counts must stay flat when doubling content;
stress world (`python tools/rr.py stress --ticks 2000`) completes and reports
bounded rebuild counters; a single-tile edit reports ≤ 4 chunk rebuilds in
the counters.

## Common mistakes
- A renderer that caches its own copy of terrain (state divergence).
- Per-instance `Node3D` for "just a few" trees — use MultiMesh.
- Rebuilding all 64 chunks after a rail commit (subscribe to the change
  event's tile list).
- Unique `StandardMaterial3D` per entity to tint it — company tint has one
  sanctioned parameterised material.

## Related skills
`terrain-system`, `rail-network`, `lod-policy`, `material-palette`,
`runtime-effects`, `performance`, `iso-world`, `diagnostics`.
