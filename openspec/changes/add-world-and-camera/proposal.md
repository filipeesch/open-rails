# Proposal

## Why

The whole game is experienced through the camera and the map. The specification calls the camera "one of the most important systems in the project" and Milestone 1 exists to prove that navigating the world feels good before anything else is built. A 256 × 256 map also breaks the naive Godot approach — one node per tile would be hundreds of thousands of nodes — so the compact data-first world model has to be established here, once, for every later system to build on.

## What Changes

- Add the tile-based world model as compact typed arrays (`terrain[]`, `height[]`, `occupancy[]`, `rail[]`) with stable 64-bit entity IDs — no Godot Node per terrain tile.
- Add chunked terrain rendering (32 × 32 tiles, one mesh per chunk, 64 chunks for a 256 × 256 map) using vertex colours and dirty-region rebuilds only.
- Add cheap water surfaces with colour and optional motion, no simulation, and no railway construction over water.
- Add instanced scenery (trees, rocks, bushes, fences, telephone poles) grouped by chunk.
- Add the orthographic isometric camera rig: fixed 35.264° pitch, full 360° smooth yaw with 45° snaps, logarithmic orthographic-size zoom, cursor-anchored wheel zoom, pan, focus and follow.
- Add desktop input handling for wheel/middle-drag/right-drag/Q/E/Home/WASD/double-click/F.
- Add pointer-to-entity selection through screen ray → terrain intersection → tile coordinate → occupancy grid → entity ID, with highlight and inspector hand-off.

## Capabilities

### New Capabilities
- `world-model`: The authoritative tile/height/occupancy data, coordinate conventions and stable entity identity.
- `terrain-rendering`: Chunked terrain, water and instanced scenery presentation derived from world state.
- `isometric-camera`: Orthographic projection, orientation, zoom, pan, focus, follow and the desktop control scheme.
- `world-selection`: Resolving a pointer position to a world entity without physics bodies.

### Modified Capabilities
_(none)_

## Impact

- New `game/src/domain/world/` and `game/src/presentation/` code plus `game/src/presentation/camera/`.
- Depends on `project-foundation` for the project layout, shared constants and CLI.
- Introduces the "rendering is a projection of state" rule that `add-rail-construction` and later changes reuse.
- No gameplay, economy or construction yet; the deliverable is a navigable, selectable map.
