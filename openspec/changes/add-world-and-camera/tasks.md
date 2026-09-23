# Tasks

## 1. World data model

- [x] 1.1 Implement `WorldGrid` with typed arrays for terrain, height, occupancy kind, occupancy id and rail, and verify index math maps a coordinate to the correct slot for a 256 × 256 grid
- [x] 1.2 Implement bounds-checked accessors returning a distinct out-of-bounds result, and verify an out-of-range query cannot read a neighbour's data
- [x] 1.3 Implement `WorldCoords` conversions between tile coordinates and world space including elevation, and verify a random round-trip test recovers tile coordinates exactly
- [x] 1.4 Implement occupancy set/clear with stable 64-bit entity ids from a session `IdFactory`, and verify ids remain unique across many creations
- [x] 1.5 Implement terrain and occupancy change notifications reporting affected tiles and chunks, and verify a single-tile edit reports only its chunk

## 2. Map loading

- [x] 2.1 Implement a run-length encoded map loader reading heights, terrain types and feature lists from JSON, and verify a decoded 256 × 256 layer matches the authored source
  `MapDocument` decodes heights, the terrain word layer and `MapFeatures`; it now also
  exposes `load_dictionary`, which the file loader delegates to, so a generated or edited
  map is proved through the shipped decoder (`tests/test_map_kinds.gd` compares a decoded
  256 × 256 layer against the authored rule, tile by tile; `tests/test_scenery_world.gd`
  covers the feature list, and the shipped valley is re-decoded as a regression case).
- [x] 2.2 Generate a deterministic 256 × 256 test map with water, forest, hill and plain tiles and verify all four terrain kinds are present
  `tests/test_map_kinds.gd` authors it from a rule — a river, a lake, an escarpment, two
  woods — encoded run-length like real content. All four kinds are present, hills stand
  above the water line, and the same seed reproduces the layer byte for byte while a
  different seed moves the water. Founder's Valley itself contains no hill tiles, which is
  why the generated map, not the authored one, carries this check.
- [x] 2.3 Implement a water-validity query reporting a water-specific rejection reason, and verify rail placement on water is refused with that reason

## 3. Terrain rendering

- [x] 3.1 Implement chunked terrain mesh generation producing one vertex-coloured mesh per 32 × 32 chunk and verify a 256 × 256 world creates exactly 64 chunk nodes
- [x] 3.2 Add a one-tile neighbour skirt to chunk generation and verify no visible seam appears at chunk borders on a sloped map
- [x] 3.3 Implement dirty-chunk rebuild driven by world change notifications and verify a counter shows exactly one rebuilt chunk for an interior edit and up to four for a border edit
- [x] 3.4 Render water as a single cheap animated surface per water body with no simulation, and verify simulation work is unchanged when water is offscreen
  A flood fill groups water cells; each group is one `MeshInstance3D` with one mesh,
  built in space local to its own centre so the animation is a single `position.y` write
  per body per frame (`WATER_BOB_AMPLITUDE` 0.045, no accumulated state, no physics body).
  Bodies beyond `WATER_NEAR_TILES` from the camera are skipped outright —
  `water_animated_last_tick()` reports zero writes — and both the hidden and the idle case
  are proved to leave terrain, heights, rail, occupancy, ticks and cash identical.
- [x] 3.5 Instance scenery per chunk with `MultiMeshInstance3D` from map feature data and verify the scene node count is independent of instance count
  `TerrainRenderer._rebuild_scenery` keeps one `MultiMeshInstance3D` per chunk per scenery
  asset and rewrites only the instance buffer; `tests/test_scenery_instances.gd` puts one
  tree in each of 16 chunks, then fills ~10,000 cells, and the node count does not move.
- [x] 3.6 Expose terrain elevation sampling at a world position and verify a placement ghost follows elevation across a hill

## 4. Isometric camera

- [x] 4.1 Implement the camera rig with orthographic projection, 45-degree yaw and fixed 35.264-degree pitch, and verify a fresh rig reports the canonical orientation
- [x] 4.2 Implement commanded-value smoothing for target, yaw and size with snap-to-exact behaviour for discrete actions, and verify a snap lands on an exact 45-degree multiple
- [x] 4.3 Implement logarithmic zoom clamped between about 4, 28 and 96 tiles and verify repeated equal scroll steps change size by a constant ratio
- [x] 4.4 Implement cursor-anchored zoom by re-solving the target from the cursor's terrain intersection, and verify the tile under the cursor stays under it within a small pixel tolerance
- [x] 4.5 Bind wheel, middle-drag pan, right-drag rotate, `Q`/`E`, `Home`, `WASD`, double-click focus and `F` to the camera system, and verify each produces the documented change and that pitch never changes
- [x] 4.6 Implement focus and follow with follow cancelled by any manual pan, and verify zoom and yaw are untouched while following

## 5. Selection

- [x] 5.1 Implement ray-to-heightfield intersection by march-and-refine against the height array and verify picks on flat and sloped tiles return the visually-correct tile
- [x] 5.2 Implement occupancy-based entity resolution from a screen position with no physics bodies, and verify clicking a station selects its entity id
- [x] 5.3 Implement screen-space train hit testing that takes precedence over terrain, and verify a train over plain track selects the train
- [x] 5.4 Implement selection state with highlight and a published selection-changed event, and verify clicking empty ground clears selection and Escape clears it
- [x] 5.5 Implement hover resolution through the same path and verify it identifies an industry without changing selection

## 6. Verification

- [x] 6.1 Add a headless boot test that loads a 256 × 256 world with renderer attached and verifies chunk count, node count and a successful pick, and verify it passes in the test suite
