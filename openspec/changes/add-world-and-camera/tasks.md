# Tasks

## 1. World data model

- [x] 1.1 Implement `WorldGrid` with typed arrays for terrain, height, occupancy kind, occupancy id and rail, and verify index math maps a coordinate to the correct slot for a 256 × 256 grid
- [x] 1.2 Implement bounds-checked accessors returning a distinct out-of-bounds result, and verify an out-of-range query cannot read a neighbour's data
- [x] 1.3 Implement `WorldCoords` conversions between tile coordinates and world space including elevation, and verify a random round-trip test recovers tile coordinates exactly
- [x] 1.4 Implement occupancy set/clear with stable 64-bit entity ids from a session `IdFactory`, and verify ids remain unique across many creations
- [x] 1.5 Implement terrain and occupancy change notifications reporting affected tiles and chunks, and verify a single-tile edit reports only its chunk

## 2. Map loading

- [ ] 2.1 Implement a run-length encoded map loader reading heights, terrain types and feature lists from JSON, and verify a decoded 256 × 256 layer matches the authored source
- [ ] 2.2 Generate a deterministic 256 × 256 test map with water, forest, hill and plain tiles and verify all four terrain kinds are present
- [x] 2.3 Implement a water-validity query reporting a water-specific rejection reason, and verify rail placement on water is refused with that reason

## 3. Terrain rendering

- [x] 3.1 Implement chunked terrain mesh generation producing one vertex-coloured mesh per 32 × 32 chunk and verify a 256 × 256 world creates exactly 64 chunk nodes
- [x] 3.2 Add a one-tile neighbour skirt to chunk generation and verify no visible seam appears at chunk borders on a sloped map
- [x] 3.3 Implement dirty-chunk rebuild driven by world change notifications and verify a counter shows exactly one rebuilt chunk for an interior edit and up to four for a border edit
- [ ] 3.4 Render water as a single cheap animated surface per water body with no simulation, and verify simulation work is unchanged when water is offscreen
- [ ] 3.5 Instance scenery per chunk with `MultiMeshInstance3D` from map feature data and verify the scene node count is independent of instance count
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
