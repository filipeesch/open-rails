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
   occupied tiles) **and** rail beside the yard: a cell in one of the
   `rail_search_radius` rings *outside* the footprint that carries rail and —
   when `requires_straight_rail` — a straight run. Every rejection carries its
   specific reason ("Requires a straight rail run beside the yard"). Rail
   access is checked **before** the footprint scan, because "no room here" is
   the wrong complaint about a site that was never going to couple.
2. **Rail access is one stored cell, not a re-derived guess.**
   `find_rail_access` scores candidates by how far the cell lies off the
   yard's centre line (`absf((lane - centre).dot(normal)) * CENTRING_WEIGHT`,
   dominant)
   then by ring distance, so the deck faces the middle of the yard rather than
   a corner. The chosen cell is saved as the station's `access_tile` and read
   back by `rail_access(station_id)`; `rail_access_tile()` self-heals for a
   legacy save that stored none. Nobody re-derives it from the camera.
3. Catchment radius is 4 tiles (one value, from world config); coverage =
   every town/industry whose position lies within it; computed once per
   station against the spatial source grid, cached, invalidated on
   station add/remove — never a per-tick distance scan.
4. Placement preview shows footprint, required alignment, catchment drawn
   on terrain, covered towns/industries highlighted, estimated cargo
   per month, and cost; an invalid ghost cannot be purchased and charges
   nothing; valid commit is one `station_construction` transaction.
5. Station inventory is per-cargo waiting quantities; allocation is the
   **only** writer (via `cargo-system`), trains remove on load; totals are
   always queryable.
6. Station identity is a stable 64-bit id + a display name (default:
   nearest place name); rename never changes the id — routes keep working.

## Public interfaces
`StationService`:
- `placement_reason(definition_id, anchor) -> String` — the one legality
  authority (empty string = buildable); the ghost and the commit path share it
- `build(definition_id, anchor, label) -> {ok, id, reason}` (charges economy;
  registers occupancy), `remove_station(id)`, `rename(id, name)`
- `find_rail_access(anchor, def) -> {tile, distance, direction}` (or empty) —
  the placement question, pure
- `rail_access(station_id) -> {tile, direction}` — the **presentation**
  question: where the deck belongs, read from stored state
- `rail_access_tile(station_id) -> Vector2i` / `has_rail_access(...)` — the
  **simulation** question (`NO_RAIL_ACCESS` when there is none);
  `station_at_rail(tile)` / `owns_access_tile(tile)` are its inverses
- `run_direction(tile) -> Vector2` — the axis a straight line runs on at that
  cell (`ZERO` at a dead end), for anything that must lie along the rails
- `centre_of(anchor, size) -> Vector2` — centre of a footprint in tile units
- `station(id)`, `stations()`, `covered_sources(id)` / `covered_sinks(id)`,
  `catchment_tiles(id)`, `stations_covering(source)`
- `inventory_of(id, cargo)`, `inventory_by_cargo(id)`, `total_waiting(id)`
  (written by `cargo-system` only)
- signals `station_created`, `station_removed`, `station_renamed`,
  `station_inventory_changed`.

## Implementation rules
- Catchment visualisation renders on the terrain surface (ground decal
  band), highlights covered sources; the player must know **before**
  building what the station will serve.
- Coverage and selection share the occupancy/source lookups — one source
  of truth.
- Estimated-monthly figures reuse the same allocation weights the
  simulation will apply, so preview promises match reality.
- Footprint tile sets come from `WorldCoords` conventions.
- A yard couples to ground **beside** it: the shipped `rail_search_radius` is
  1 ring. A wider radius lets the model drift off its own platform and makes
  the station look parked in a field with a plank to the line.
- Because the cell must be straight *and* beside the yard, a qualifying line
  must run **parallel to a side of the footprint** — a perpendicular stub
  touching a yard corner can never satisfy it. Say so in the refusal, do not
  silently accept a curve.
- Where the model sits and which way it faces is derived once by
  `EntityRenderer.station_transform(instance, access)` (pure + static): the
  platform edge lies exactly on the access lane, the yard lies behind it, and
  the yaw is `WorldCoords.yaw_for_direction(dir)` of the run. **Never**
  billboard a station to the camera; a turned station reads as placed, a
  billboard reads as a decouped sticker.

## Validation
Tests: mine at 3 tiles covered / town at 6 not covered;
`a_station_beside_no_rail_says_so_instead_of_pointing_at_the_origin` and
`straight_rail_is_the_only_access_a_station_accepts` pin the refusal wording;
`a_station_couples_to_the_line_beside_its_yard` /
`a_station_that_only_overlooks_the_line_is_refused` pin the ring rule;
`the_platform_stands_at_the_rails_it_serves` and
`a_station_is_turned_to_its_line_and_not_to_the_projection` (in
`tests/test_travel_scale.gd`) pin where the model is drawn and how it is
turned; month pass grows waiting coal by the allocated amount; load of
20 from 42 leaves 22; `renaming_a_station_leaves_the_train_running_its_route`.
Manual: ghost over town+mine highlights both with per-cargo estimates and $
cost, and the built yard sits against the rails it was offered.

## Common mistakes
- Scanning sources per tick instead of cached coverage.
- Duplicating cargo allocation here — allocation belongs to `cargo-system`
  (this service only reports coverage and holds inventory).
- Keying routes/UI on station name (renames must be harmless).
- Checking straight-rail by inspecting masks directly — ask `RailService`.
- Re-deriving the access cell at draw time, or turning the model to the camera
  — read `rail_access()` and `station_transform()`. Both save/load and
  first-build paths must go through the same helper or one of them drifts.
- Naming a search radius without filtering by it. `find_rail_access` walks
  rings and stops at `def.rail_search_radius`; a square scan around the anchor
  accepts rail further away than the station class asked for.

## Related skills
`cargo-system`, `rail-network`, `rail-builder`, `town-system`,
`industry-system`, `economy`, `build-mode-ux`, `iso-world`.
