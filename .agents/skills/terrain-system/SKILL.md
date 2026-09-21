# terrain-system

## Purpose
Owns the world model and its visible surface: `WorldGrid` typed-array state,
heightfield semantics, terrain change notifications, chunked terrain meshes,
water surfaces and instanced scenery.

## When to use
Working on terrain data, chunk generation/rebuilds, water rendering,
scenery placement/instancing, or terrain height queries.

## Non-goals
Rail data (`rail-network`), terraforming/editor tools (out of scope V1),
pointer→tile conversion (`iso-world`), track batching details
(`runtime-rendering` shares the chunk grid but owns track pieces).

## Dependencies
- `WorldConstants` (TILE_SIZE, HEIGHT_STEP, CHUNK_SIZE=32, MAP 256×256).
- `WorldGrid` arrays, indexed `y * width + x`: `terrain`
  (`PackedByteArray`), `height` (`PackedByteArray`), `occupancy_kind`
  (`PackedByteArray`), `occupancy_id` (`PackedInt64Array`), `rail`
  (`PackedByteArray`).
- Founder's Valley map: one JSON document with RLE height/terrain layers +
  explicit town/industry/scenery lists, authored once and committed as data
  (`game/data/`).
- Terrain surfaces: grass/dirt/rock/water via vertex colours on shared
  materials.

## Invariants
1. World state lives only in typed arrays; node count is constant with map
   size; access is direct index arithmetic, not search or dictionaries.
2. Heightfield only: no caves, no overhangs; elevation is a whole number of
   HEIGHT_STEPs. V1 has no terraforming — terrain data is authored, read-only
   at runtime except occupancy/rail.
3. Changes emit notifications identifying affected tiles; a chunk rebuilds
   iff its own tiles (or its one-tile skirt) changed — counters exposed, at
   most 4 chunks per tile edit.
4. A 256×256 map renders as exactly 64 chunks, one mesh each, vertex colours,
   shared materials only.
5. Water: one mesh per water-body bounding region, flat transparent surface
   just below the waterline with a cheap vertex-shader wobble; zero
   simulation; rail over water is invalid (reason "water").
6. Scenery (trees, rocks, bushes, fences, telephone poles) draws via
   `MultiMeshInstance3D` per chunk per type; no per-instance nodes, no
   per-instance animation.

## Public interfaces
`WorldGrid`:
- `height_at(tile) / terrain_at(tile) / occupancy_at(tile) -> {kind, id}`
- `set_occupancy(tile, kind, id)` (station/industry registration — also
  feeds `SourceIndex` and the occupancy grid used by selection)
- signal `tiles_changed(tiles: Array[Vector2i])`

`TerrainRenderer`: rebuild-from-dirty-region, `terrain_height_at(world_pos)`.

## Implementation rules
- Out-of-bounds queries fail deterministically; never clamp silently.
- Chunk meshes include a one-tile skirt of neighbour vertices to avoid seam
  cracks; keep chunk AABBs accurate for culling.
- Scenery instance transforms derive from the world seed (deterministic) —
  the stress world must be reproducible from its seed.
- Water wobble must never cost simulation work when the camera looks away
  (visual-only update).

## Validation
Headless: 65,536 tiles readable, node count constant, OOB rejected.
Rendering: one local height edit ⇒ rebuild counter +1..4, never 64; forest
chunk's node count independent of tree count; stress run completes.

## Common mistakes
- A `Dictionary` of tiles "for flexibility" — the typed arrays are the
  design (cache locality, O(1), determinism).
- Rebuilding the whole terrain after a rail commit.
- Placing one `Node3D` tree per scenery instance.
- Reading terrain height from meshes; `WorldGrid.height` is authoritative.

## Related skills
`iso-world`, `runtime-rendering`, `rail-network`, `asset-scale`,
`performance`, `data-contracts`, `terrain` consumers `station-system`,
`rail-builder`.
