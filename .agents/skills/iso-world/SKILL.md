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
- `WorldConstants` (TILE_SIZE 1.0, HEIGHT_STEP 0.25, TILE_METRES 16.0) — via
  `art/config/world.toml`, never literals.
- `WorldCoords` — the single home of the conversions (see below).
- `WorldGrid.occupancy_kind` / `occupancy_id` for entity resolution.

## Invariants
1. Convention is fixed: tile `(x, y)` → world `((x + 0.5) * TILE_SIZE, height
   * HEIGHT_STEP, (y + 0.5) * TILE_SIZE)` — the tile's **y is world Z**;
   elevation = `height * HEIGHT_STEP`;
   `world_to_tile(tile_to_world(t)) == t` exactly.
2. A model's yaw comes from the world, never from the viewer: assets are
   authored **nose along local +X, axle along local Y**, so turning a model to
   face a tile-space direction `d` is `rotation.y =
   WorldCoords.yaw_for_direction(d)` = `atan2(-d.y, d.x)`. The old
   `atan2(-d.x, d.y)` was a mirror of this, not a rotation: it left every
   axis-aligned train and station about 90° off. `yaw_degrees_for_direction`
   is the same thing for a text heading.
3. Pointer → entity resolution is arithmetic: ray ∩ terrain heightfield
   (march step half a tile, binary refine to 1e-3, validate against height
   continuity) → tile → occupancy → stable entity id. **No physics bodies.**
4. Trains are hit-tested by a screen-space bounding-circle check against
   rendered positions, evaluated **before** the terrain result, so a train
   in front of track wins.
5. Out-of-bounds tiles are reported as out-of-bounds, never wrapped or
   resolved to a neighbour's data.
6. Hover uses the identical resolution path as selection and must cost
   O(ray steps) per pointer move — no allocations, no queries into UI.
7. Clicking empty ground clears selection rather than keeping the old one.

## Public interfaces
`WorldCoords` (pure/static, no scene tree needed):
- `tile_to_world(tile, height_steps := 0) -> Vector3`, `tile_to_world_xz(tile)
  -> Vector2`, `height_to_world(steps)`, `world_to_height(y)`
- `world_to_tile(pos: Vector3) -> Vector2i`, `world_to_tile_floor(pos:
  Vector2) -> Vector2i`
- `tiles_in_span(min, size)`, `tile_center_of_span(min, size)`,
  `tiles_in_radius(centre, radius)`, `distance_tiles(a, b)`, `chebyshev(a, b)`
- `yaw_for_direction(direction: Vector2) -> float` (radians for
  `rotation.y`; ZERO vector → 0.0), `yaw_degrees_for_direction(...)`

`SelectionService` (presentation, attached to rig + session):
- `point_at(screen)` hover, `select_at_screen(screen)` / `select_at(tile,
  screen)`, `select_train(id)` / `select_station(id)` / `select_tile(tile)`,
  `clear_selection()`
- `pick_ray(screen) -> {origin, direction}`, `resolve_entity(tile, screen)`,
  `train_anchor(train_id) -> Vector3`, `viewport_rect()`

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
selection; train precedence test with a train over plain track;
`turning_a_model_to_a_direction_points_its_nose_down_it` in
`tests/test_travel_scale.gd` pins `yaw_for_direction` against all eight rail
directions.

## Common mistakes
- Using the tile corner instead of centre convention (asymmetric footprints).
- Re-implementing a ray-plane solve inside a tool — ask `WorldCoords`.
- Inventing a yaw formula at the call site, or turning a model to the camera
  because the projection looks like a billboard. `yaw_for_direction` is the
  one formula; the camera is not a heading.
- Adding an `Area3D` "to make clicking easier" — prohibited by the runtime
  rules; fix the arithmetic instead.
- Forgetting elevation: ghosts placed at y=0 float or bury on hills.

## Related skills
`terrain-system`, `camera-navigation`, `runtime-rendering`, `rail-builder`,
`station-system`, `asset-scale`, `godot-project`.
