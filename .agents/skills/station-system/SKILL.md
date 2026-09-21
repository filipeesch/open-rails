# station-system

## Purpose
Owns the single V1 station class: placement validity (footprint + rail
alignment), the 4-tile catchment and coverage queries, the placement preview,
per-cargo waiting inventory, naming/identity.

## When to use
Working on station placement, coverage/catchment visuals, station inventory
reporting, or station rename behaviour.

## Non-goals
Cargo allocation across stations (`cargo-system`), which trains stop here
(`route-system`), the Station build tool's UI shell (`build-mode-ux`),
adjacency legality (`rail-network` answers alignment).

## Dependencies
- `RailService` — required straight-rail alignment is asked, not invented.
- `WorldGrid` occupancy registration + `SourceIndex` (towns/industries).
- `EconomyService` (station_construction charge on commit).
- Constants: `STATION_CATCHMENT = 4.0` tiles from `WorldConstants`.
- Data: `game/data/stations/` def (cost, footprint, alignment).

## Invariants
1. A station requires footprint tiles on buildable land (no water, no
   occupied tiles) **and** an adjacent rail cell with the allowed alignment;
   every rejection carries its specific reason ("Requires straight rail").
2. Catchment radius is 4 tiles (one value, from world config); coverage =
   every town/industry whose position lies within it; computed once per
   station against the spatial source grid, cached, invalidated on
   station add/remove — never a per-tick distance scan.
3. Placement preview shows footprint, required alignment, catchment drawn
   on terrain, covered towns/industries highlighted, estimated cargo
   per month, and cost; an invalid ghost cannot be purchased and charges
   nothing; valid commit is one `station_construction` transaction.
4. Station inventory is per-cargo waiting quantities; allocation is the
   **only** writer (via `cargo-system`), trains remove on load; totals are
   always queryable.
5. Station identity is a stable 64-bit id + a display name (default:
   nearest place name); rename never changes the id — routes keep working.

## Public interfaces
`StationService`:
- `can_place(footprint_origin, rotation) -> Reason`
- `place(origin) -> StationId` (charges economy; registers occupancy)
- `station(id)`, `stations()`, `covered_sources(station_id) -> {towns,
  industries}`, `catchment_tiles(station_id)`
- `inventory(station_id, cargo) -> int`, `take(...)` / `deposit(...)`
  (called by cargo system / loading only)
- signal `station_created(station_id)`.

## Implementation rules
- Catchment visualisation renders on the terrain surface (ground decal
  band), highlights covered sources; the player must know **before**
  building what the station will serve.
- Coverage and selection share the occupancy/source lookups — one source
  of truth.
- Estimated-monthly figures reuse the same allocation weights the
  simulation will apply, so preview promises match reality.
- Footprint tile sets come from `WorldCoords` conventions.

## Validation
Tests: mine at 3 tiles covered / town at 6 not covered; no-adjacent-rail
rejection names rail access; curve-only adjacency rejected with straight
requirement; month pass grows waiting coal by the allocated amount; load of
20 from 42 leaves 22; rename keeps id referenced by a route. Manual: ghost
over town+mine highlights both with per-cargo estimates and $ cost.

## Common mistakes
- Scanning sources per tick instead of cached coverage.
- Duplicating cargo allocation here — allocation belongs to `cargo-system`
  (this service only reports coverage and holds inventory).
- Keying routes/UI on station name (renames must be harmless).
- Checking straight-rail by inspecting masks directly — ask `RailService`.

## Related skills
`cargo-system`, `rail-network`, `rail-builder`, `town-system`,
`industry-system`, `economy`, `build-mode-ux`, `iso-world`.
