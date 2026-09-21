# route-system

## Purpose
Owns routes: ordered station stops with per-stop load/unload cargo
configuration, reachability validation, path resolution via rail A*, and
recalculation when the network changes.

## When to use
Route editor logic, station-picking mode, path revalidation on
`track_changed`, reachability feedback at pick time.

## Non-goals
Movement/dwell (`train-system`), what transfers actually move (`cargo-
system`), graph queries (`rail-network`), the drawer's widget layout
(`ui-components`).

## Dependencies
- `RailNetwork` / `RailService` for paths and reachability;
  `StationService` for stops.
- Domain event `track_changed` (recompute trigger).
- Train purchase/route link owned by `GameSession` wiring: a route belongs
  to exactly one train.

## Invariants
1. A route is an ordered list of ≥2 station stops, each configuring cargo
   to load and cargo to unload; executed cyclically until edited; stop
   order is respected exactly.
2. Paths resolve via rail A* **on route creation and on `track_changed`
   for affected routes** — never per tick; reachability checks at
   stop-pick time use the same query with a limit.
3. Adding a stop is done by clicking the station on the map
   (station-picking mode); no dropdown for world entities; unreachable
   stations are invalid at pick time and rejected with the reason
   "unreachable".
4. A route that becomes impossible (track removed) keeps its definition,
   marks itself invalid, and a notification names the train and the
   unreachable station; rebuilding the connection restores validity without
   recreating the route.
5. Stop configuration only offers cargo present at / accepted by that
   stop; configuring absent cargo reports unavailability rather than
   silently no-op'ing.

## Public interfaces
`RouteService`:
- `create(train_id) -> RouteId`, `add_stop(route_id, station_id) -> Reason`,
  `remove_stop`, `move_stop`, `set_stop_config(route_id, stop_idx,
  {load_cargo, unload_cargo})`
- `path(route_id) -> Array[(cell, direction)]` or invalid marker
- `reachable_stations(route_id) -> set` (for pick-time highlighting)
- signal `route_invalidated(route_id, train_id, station_id)`.

## Implementation rules
- Recompute only affected routes: subscribe to `track_changed` and check
  which routes' stop pairs touch the changed tiles.
- Show live reachability in the editor while editing; reordering
  revalidates immediately.
- Route definitions and their resolved paths are both saved — a load
  restores validity state without waiting for the first `track_changed`.
- Keep A* limits generous but bounded (V1 map is 256×256).

## Validation
Tests: two-stop route loops forever; A/B/C order honoured; pick on
disconnected station rejected with reason; sole-bridge tile removal ⇒
route invalid + notification names train + station; rebuild ⇒ valid again;
reorder connected stops ⇒ path recomputed, route stays valid.

## Common mistakes
- Resolving paths in the train tick loop (event-driven only).
- Deleting an impossible route's definition (player loses work; spec says
  keep and mark).
- Offering all stations at pick time (only reachable ones are valid).
- Duplicating A* here instead of calling the rail-network query.

## Related skills
`rail-network`, `train-system`, `cargo-system`, `station-system`,
`build-mode-ux`, `ui-components`, `save-load`.
