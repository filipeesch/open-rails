# rail-builder

## Purpose
Composes `rail-network`, `iso-world`, `economy` and `build-mode-ux` into the
player-facing act of building and removing railway: drag planning with
continuous preview, cost and validity feedback, commit through the economy,
and financially honest undo.

## When to use
Working on the Rail tool, construction preview/planner UX, construction
costs, removal rules, or the undo stack for construction.

## Non-goals
Graph data and validity authority (`rail-network` — ask it, never
re-derive), money mutation (`economy` — ask it, never touch cash), track
meshes (`runtime-rendering`), station placement (`station-system`).

## Dependencies
- `RailService.can_connect` (reasons), `RailNetwork.shortest_path`
  (A* over the walkable tile lattice, not only existing rail).
- `EconomyService` (`spend` with category `track_construction`,
  `refund(transaction_id)`), `UndoService`.
- Ghost/preview layer (`build-mode-ux`), pointer tile (`iso-world`).
- Planner weights (base terrain cost, slope penalty, turn penalty, reuse
  bonus) as data.

## Invariants
1. The player drags start→cursor→endpoint; no per-tile manual placement
   except Shift = precision single tile.
2. The planner prefers short distance, few turns, gentle slopes, existing
   railway reuse and low cost; meeting built track reuses it instead of
   proposing parallel duplicates.
3. Preview recomputes **per pointer-tile change**, cached against
   `(start, goal, network revision)` — dragging over the same tile is free;
   this is the "no pathfinding every tick" rule satisfied.
4. Preview shows total length, total cost and validity; colours:
   green = valid, yellow = valid-but-expensive, red = invalid; red names
   the principal obstruction reason adjacent to the cursor.
5. Commit charges exactly one `track_construction` ledger transaction;
   insufficient funds blocks the commit with a reason and builds nothing;
   releasing over an invalid endpoint never charges.
6. Removal refunds nothing but charges nothing, and refuses to remove a
   cell a station depends on for rail access (reason names the station).
7. `Ctrl+Z` undo restores network state **and** reverses the ledger
   (`EconomyService.refund`); actions that became semantically unsafe are
   dropped from the stack, never faked.

## Public interfaces
`RailBuilderTool` (a build tool):
- `begin(tile)`, `update_cursor(tile)`, `commit(tile) -> Reason|ok`,
  `cancel()`
- `preview() -> {tiles, length, cost, valid, reason, expensive: bool}`
`UndoService`: `push({apply(), invert(), transaction_id})`, `undo()`.

## Implementation rules
- A* nodes are tiles; edges are the 8 directions with the documented cost;
  never plan over water or beyond the slope rule (validity comes from
  `RailService`).
- Yellow threshold is expressed as a multiple of the cheapest possible
  route, pinned in data (design open question → project decision: data
  value, default 1.5×).
- Undo scope stays exactly: build rail, remove rail, build station. Anything
  entangled with trains/cargo is dropped, per spec §66.
- Cursor-adjacent error labels follow the cursor, use colour + icon + text.

## Validation
Tests: equal-length plans prefer fewer turns; endpoint on existing network
reuses cells; commit produces one ledger entry and no direct cash edits;
invalid release is free; undo restores cash exactly; dependent-station
removal refused with the station named. Manual: drag feels like drawing a
line at zoom 28.

## Common mistakes
- Re-planning every render frame (cache by cursor tile + revision).
- The tool computing its own validity instead of calling
  `RailService.can_connect`.
- Undo replaying the world forward (non-deterministic with trains) — use
  inverse commands.
- Charging per tile instead of one transaction per committed route.

## Related skills
`rail-network`, `economy`, `build-mode-ux`, `iso-world`, `station-system`,
`ux-principles`, `testing`.
