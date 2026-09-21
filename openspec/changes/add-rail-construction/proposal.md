# Proposal

## Why

Laying railway is the verb the game is named after, and the specification sets a hard bar for Milestone 3: "at this point the player should enjoy simply laying railway." Manual tile-by-tile placement would make that miserable, and a rail model built for rendering rather than for simulation would have to be rewritten when trains arrive. The logical graph and the visual mesh have to be separated now.

## What Changes

- Add the logical rail network: per-cell 8-direction connection bitmask (`N, NE, E, SE, S, SW, W, NW`) from which the rail graph is derived, with all intersections behaving as connected junctions.
- Add reachability and path queries over the graph (A*) used by construction planning now and by trains later.
- Add the drag-based rail builder: click start, move cursor, continuous route preview, cost, confirm endpoint — with Shift for precision/manual single-tile placement.
- Add construction validation and preview feedback: green/yellow/red validity, obstruction reason shown adjacent to the cursor, total length and total cost, slope rule of at most one height step between adjacent connected cells, water invalid.
- Add construction cost charged through `EconomyService`, plus `Ctrl+Z` undo of rail build and remove that restores the financial transaction.
- Add track rendering that selects canonical pieces (straight, diagonal, 45° curve, 90° curve, junction, slope) from connectivity and rebuilds only affected render chunks.

## Capabilities

### New Capabilities
- `rail-network`: The logical rail graph, its connection semantics, slope and water rules, and graph queries.
- `rail-construction`: Planning, previewing, validating, committing, costing and undoing track construction.
- `track-rendering`: Choosing track geometry from connectivity and presenting it in batches per chunk.

### Modified Capabilities
_(none)_

## Impact

- New `game/src/domain/rail/`, `game/src/presentation/rail/` and build-tool UI under `game/src/ui/tools/`.
- Introduces `EconomyService` as the single point of money mutation (expanded by `add-trains-routes-and-revenue`).
- Emits `track_changed`, consumed later by route recalculation and the rail renderer.
- Depends on `add-world-and-camera` for the occupancy grid, selection and camera.
