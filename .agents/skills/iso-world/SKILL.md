# iso-world

## Purpose
Owns the conversions and queries between screen, world and tile space:
tile↔world coordinates, camera/plane intersection, occupancy lookup, pointer
selection/hover resolution, and terrain height sampling.

## When to use
Any code that turns a click into a tile/entity, places ghosts on the ground,
converts footprints to tiles, or needs elevation at a position.

## Non-goals
Camera motion policy (`camera-navigation`), chunk mesh building
(`runtime-rendering`), entity rules (each system's own skill).

## Dependencies
- `WorldConstants` (TILE_SIZE 1.0, HEIGHT_STEP 0.25) — via
  `art/config/world.toml`, never literals.
- `WorldCoords` — the single home of the conversions:
  `tile_to_world(tile) -> Vector3`, `world_to_tile(pos) -> Vector2i`,
  `intersect_view_plane(ray) -> world point`, terrain march intersection.
- `WorldGrid.occupancy_kind` / `occupancy_id` for entity resolution.

## Invariants
1. Convention is fixed: tile centre at `(x + 0.5) * TILE_SIZE`,
   elevation = `height * HEIGHT_STEP`; `world_to_tile(tile_to_world(t)) == t`
   exactly.
2. Pointer → entity resolution is arithmetic: ray ∩ terrain heightfield
   (march step half a tile, binary refine to 1e-3, validate against height
   continuity) → tile → occupancy → stable entity id. **No physics bodies.**
3. Trains are hit-tested by a screen-space bounding-circle check against
   rendered positions, evaluated **before** the terrain result, so a train
   in front of track wins.
4. Out-of-bounds tiles are reported as out-of-bounds, never wrapped or
   resolved to a neighbour's data.
5. Hover uses the identical resolution path as selection and must cost
   O(ray steps) per pointer move — no allocations, no queries into UI.
6. Clicking empty ground clears selection rather than keeping the old one.

## Public interfaces
`WorldCoords` (pure/static):
- `tile_to_world(tile: Vector2i, height := -1) -> Vector3`
- `world_to_tile(pos: Vector3) -> Vector2i`
- `ray_to_tile(ray) -> {tile, world_pos, height} or empty`
- `terrain_height_at(world_pos) -> float` (ground sampling for ghosts/labels)

`WorldSelection`:
- `pick(screen_pos) -> {kind, entity_id, tile}` (train-priority path above)
- publishes selection-changed and hover-changed events with kind + id.

## Implementation rules
- All footprints (station, industry) are computed as tile sets through
  `WorldCoords` — one convention, so alignment rules agree everywhere.
- Keep the march/refine constants here; nothing else duplicates the
  ray-march.
- Selection never mutates simulation state; it publishes kind+id and lets
  services/UI react.
- Heightfield sampling must use `WorldGrid.height`, never a physics
  raycast — there are no colliders under the terrain.

## Validation
Headless tests: round-trip conversion is exact; a station on a hill clicks
onto its tile at every yaw snap (0/45/…/315); clicking empty tile clears
selection; train precedence test with a train over plain track.

## Common mistakes
- Using the tile corner instead of centre convention (asymmetric footprints).
- Re-implementing a ray-plane solve inside a tool — ask `WorldCoords`.
- Adding an `Area3D` "to make clicking easier" — prohibited by the runtime
  rules; fix the arithmetic instead.
- Forgetting elevation: ghosts placed at y=0 float or bury on hills.

## Related skills
`terrain-system`, `camera-navigation`, `runtime-rendering`, `rail-builder`,
`station-system`, `asset-scale`, `godot-project`.
