# rail-network

## Purpose
Owns the logical rail network: per-cell 8-direction connection masks, the
graph derived from them, traversal/reachability/shortest-path queries, and
terrain validity rules. It does **not** own build UI or previews
(`rail-builder`).

## When to use
Anything touching rail data or the graph: construction validity, connectivity
questions, path queries for trains or the planner, `track_changed` semantics.

## Non-goals
Drag interaction, ghosts, cost/commit/undo (`rail-builder`), track meshes
(`runtime-rendering`), station alignment policy (station asks, this answers).

## Dependencies
- `WorldGrid.rail` — one byte per cell, bits `N, NE, E, SE, S, SW, W, NW`.
- `RailService` (validity) + `RailNetwork` (data/queries), owned by
  `GameSession`.
- Terrain facts: heights (`height[]`), water flags (`terrain[]`).
- `WorldCoords` for neighbour tile arithmetic.

## Invariants
1. Connections are the single source of truth; the graph is derived, never
   maintained twice. Adding a connection writes the reciprocal in the
   neighbour atomically; removing a cell clears all inbound references.
2. The graph is undirected in V1; every intersection is a connected junction
   (any arriving branch may leave by any other). Grade-separated crossings
   are not representable.
3. Slope rule: a connection is valid only when endpoint heights differ by
   **≤ 1 HEIGHT_STEP**; steeper fails with a slope-specific reason.
4. Water and incompatible occupancy reject rail, each with a distinct,
   player-facing reason (never a generic boolean failure).
5. `can_connect(cell, dir) -> Reason` is the only validity authority —
   planner, tools and any future bridge code all call it. Reasons are an
   enum with a `message()` mapping.
6. Every network change emits one `track_changed` event listing every
   affected tile (renderers + routes subscribe; no polling).

## Public interfaces
`RailNetwork`:
- `connections(tile) -> int` (bitmask), `neighbours(tile) -> Array[Vector2i]`
- `reachable(from_tile, to_tile) -> bool`
- `shortest_path(from_tile, to_tile) -> Array` of `(cell, direction)` or
  empty ⇒ unreachable, A* with a documented cost function (diagonal √2,
  turn penalty, slope penalty, reuse bonus).

`RailService`:
- `can_connect(cell, dir) -> Reason`
- signals `track_changed(tiles)`.

## Implementation rules
- Treat "disconnected" as a first-class answer: return unreachable, never a
  partial path.
- Cost weights are data (documented in `data-contracts`) so planner
  preferences are testable, not vibes.
- Keep queries allocation-light; trains' cached paths plus `track_changed`
  mean this is event-driven — **no per-tick pathfinding**.
- Straight vs diagonal is a cost property, not a separate track "type".

## Validation
Tests (spec §106): reciprocal connections after lay; removal leaves no
inbound refs; junction offers every branch; one-step climb legal /
two-step illegal with slope reason; water rejection distinguishable; a
multi-tile commit fires exactly one event with the full tile list.

## Common mistakes
- Maintaining an edge list alongside masks (they drift — this was rejected
  in design).
- Returning `[]` ambiguously (empty can mean start==goal vs unreachable;
  distinguish).
- Silently skipping invalid neighbours during BFS so callers think partial
  paths are valid routes.

## Related skills
`rail-builder`, `route-system`, `train-system`, `station-system`,
`terrain-system`, `track` visuals `runtime-rendering`, `testing`.
