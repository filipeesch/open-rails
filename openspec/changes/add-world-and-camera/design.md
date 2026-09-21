# Design

## Context

See `add-world-and-camera/proposal.md` for motivation. The world model is greenfield, and the performance rules in the specification are absolute: no node per terrain tile, no per-instance scene tree for scenery, no full-terrain rebuild for a local edit. Rendering must therefore be a projection over data owned elsewhere, and the camera is the primary interface surface.

## Goals / Non-Goals

**Goals:**
- A 256 × 256 map that boots instantly, renders in 64 chunks and navigates smoothly at every zoom.
- One data model that rail, station and entity code will reuse without change.
- Camera feel good enough to judge Milestone 1 by playing with it.

**Non-Goals:**
- No terrain editing or terraforming, no water simulation, no day/night or weather, no physics bodies.
- No entity gameplay — occupancy knows an entity exists; what it does arrives later.

## Decisions

**Typed arrays, not Dictionaries, for grid data.** `terrain: PackedByteArray`, `height: PackedByteArray`, `occupancy_kind: PackedByteArray`, `occupancy_id: PackedInt64Array` and `rail: PackedByteArray`, indexed `y * width + x`. A `WorldGrid` class exposes typed accessors. Chosen over one `WorldTile` object per cell (65,536 heap objects, poor cache behaviour) and over `Dictionary` tile-keyed storage (no O(1) array indexing, non-deterministic ordering).

**Coordinate convention: tile centre at `(x + 0.5) * TILE_SIZE`, elevation `height * HEIGHT_STEP`.** Documented once in `WorldCoords` with `tile_to_world`, `world_to_tile` and a plane-intersection helper used by the camera and selection. An offset-origin convention was rejected because it makes every footprint calculation asymmetric.

**Terrain chunk = a `Mesh` built from an `ArrayMesh` with vertex colours and one shared material.** Chunks subscribe to `WorldGrid` change notifications and rebuild only their own vertices plus a one-tile skirt of neighbours to avoid seam cracks. A `SurfaceTool`-per-tile approach was rejected for node and draw-call cost.

**Water is one mesh per water body bounding region, not per tile.** A flat transparent surface slightly below the terrain waterline with a cheap vertex-shader wobble. Full-screen or per-tile water quads were rejected on overdraw.

**Scenery is `MultiMeshInstance3D` per chunk per scenery type.** Instance transforms are generated from the world seed; no scene nodes per tree. Individual `Node3D` per tree was rejected outright by the specification.

**Camera rig: a yaw node, a pitch node and a `Camera3D` with `keep_aspect` orthographic size.** Position is derived from a `target` world point plus a fixed offset along the view direction scaled by orthographic size, so zoom never moves the focus point. Smoothing is exponential critically-damped interpolation of `target`, `yaw` and `size` toward commanded values; snap inputs change the commanded value by exactly 45°. Cursor-anchored zoom solves for the new target that keeps the cursor's terrain intersection at the same screen pixel, which is why `WorldCoords` needs the plane-intersection helper.

**Selection is arithmetic, not physics.** Camera ray ∩ terrain heightfield (march-and-refine along the ray against `height[]`) → `world_to_tile` → `occupancy_id`. Trains get a screen-space bounding-circle test against their rendered positions, evaluated before the terrain result. Godot `Area3D`/`StaticBody3D` picking was rejected: 65,536 potential colliders contradicts the performance rules.

**`GameSession` owns the world; the renderer only listens.** The renderer is constructed by the scene and given a reference; every update path is event-driven. A renderer that owned terrain data was rejected because tests must run the world without rendering.

## Risks / Trade-offs

- [Chunk skirts mean a tile edit rebuilds up to four chunks] → accepted; rebuild count is still bounded by four, and the counter is exposed for the `runtime-performance` measurement.
- [Orthographic size plus large map can show the whole map at once] → furthest zoom is clamped near 96 tiles and terrain chunks are frustum-culled by Godot.
- [Exponential smoothing can feel floaty at high speed] → smoothing rate scales with distance to target, with a snap-when-close epsilon.
- [Ray-marched terrain picking can miss a thin cliff edge] → march step is half a tile with binary refinement to 1e-3, and the picked tile is validated against height continuity.

## Migration Plan

Additive. Removal is deleting `game/src/domain/world/` and `game/src/presentation/`; nothing earlier depends on it.

## Open Questions

- Whether terrain materials need a separate water material instance or a vertex-alpha trick — resolve during implementation by counting draw calls with the `F3` overlay later in V1.
