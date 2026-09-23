# Tasks

## 1. Data layer

- [x] 1.1 Implement `DataRegistry` loading cargo, town, industry and station definitions from `game/data/` into immutable records with validation of unknown cargo references, and verify a bad reference fails with the offending file name
- [x] 1.2 Write `game/data/cargo/` definitions for passengers, mail and coal with base rate and time sensitivity, and verify coal's sensitivity is materially lower than passengers'
- [x] 1.3 Write station and industry definitions for small station, coal mine and power plant, and verify each parses into its declared produces/accepts lists

## 2. Towns and industries

- [x] 2.1 Implement `TownService` holding town instances with id, name, population, position and generation rates, and verify a simulated month yields the declared passenger and mail quantities
- [x] 2.2 Implement `IndustryService` stepping producer inventories at their rates up to capacity and reporting a full condition, and verify a 20/month mine grows 20 in a month and saturates at capacity
- [x] 2.3 Implement consumer recording of accepted deliveries against a per-month received total, and verify a 30-unit coal delivery is recorded
- [x] 2.4 Implement producer and consumer behaviour purely from data lists so a multi-input multi-output industry is expressible, and verify a synthetic iron + coal to steel definition simulates without new code
- [x] 2.5 Register towns and industries into a source index and the occupancy grid, and verify selection and coverage queries resolve them without scene nodes

## 3. Stations

- [x] 3.1 Implement station placement validation covering footprint buildability, water, occupancy and required straight-rail access with typed reasons, and verify each rejection reason is reachable in a test
- [x] 3.2 Implement the station ghost preview showing footprint, catchment on terrain, covered towns and industries, expected monthly cargo and cost, and verify coverage highlights appear before commitment
  The figures are the domain's: `BuilderService.preview_station` now returns the `catchment` cells, `catchment_radius`, the covered `sources` and a per-cargo `monthly` expectation summed from each source's own declared rate, plus one `state` word (`ok` / `expensive` / `invalid`) so the readout beside the cursor and the bands on the terrain cannot colour the same preview differently. A refused spot still gets its footprint — a red ghost has to be drawn somewhere — while the reach and the yield it would not have are withheld. `StationGhost` (presentation) draws that answer as three bands (the yard, the reach, a mark and a ribbon to every place it covers) on one shared translucent material, each tile standing on `WorldGrid.elevation_at`, and rebuilds only when the preview's answer changes. `GhostReadout` gained the reach line: "Reaches 2 places — Passengers 30 · Mail 9 a month."
  A wiring bug surfaced here: the station tool previewed at `tile - (1, 0)` but committed at the raw tile, so a click landed the yard one cell from its own ghost. `STATION_ANCHOR_OFFSET` / `station_anchor_for()` is now the single rule both paths use, and the anchor is published as `ghost_anchor` beside the preview the world draws.
  No ground in Founder's Valley puts a town and a colliery inside one 4-tile catchment (the nearest pair are further apart than the reach), so the spec's scenario is proved as the map allows: one case over Marlow shows passengers and mail with the cost before anything is built, one case over the colliery shows coal.
  Proved by `tests/test_station_ghost.gd`: `test_a_ghost_over_a_town_shows_yard_reach_yield_and_price_before_anything_exists`, `test_the_monthly_promise_is_the_covered_places_own_declared_output` (the coal figure re-summed independently from `CargoService.collect_sources`), `test_the_reach_is_drawn_on_the_ground_it_covers` (the band's drawn heights are exactly the heights of the ground it covers, across more than one height — not a plane floating over the valley), `test_a_refused_spot_shows_the_yard_it_denies_with_the_domain_s_reason`, `test_a_yard_beyond_the_cash_is_priced_dear_rather_than_refused`, `test_the_click_lands_the_yard_exactly_where_the_ghost_stood`, `test_the_ghost_quiets_when_the_tool_changes_and_redraws_only_when_the_answer_changes`, `test_the_ghost_is_three_bands_on_one_material_with_nothing_to_collide`.
- [x] 3.3 Implement station commitment charging `EconomyService` and blocking invalid ghosts without any charge, and verify an invalid confirm builds nothing
- [x] 3.4 Implement 4-tile catchment coverage reporting covered sources with a spatial index, and verify a 3-tile source is covered and a 6-tile source is not
- [x] 3.5 Implement per-cargo station inventory with totals, and verify loading reduces the stored amount by exactly the loaded quantity
- [x] 3.6 Implement stable ids with default naming from the nearest place and player renaming, and verify renaming leaves a referencing route intact

## 4. Cargo generation and allocation

- [x] 4.1 Implement cargo batch storage keyed by station, cargo and origin with aggregation on arrival, and verify two same-origin allocations collapse into one batch with the earliest creation time
- [x] 4.2 Implement monthly generation from towns and from industry inventories driven by the month boundary, and verify quantities equal the declared rates
- [x] 4.3 Implement distance-weighted largest-remainder distribution across covering stations with a per-source fractional accumulator, and verify two stations covering one town receive exactly the produced total with the nearer station getting more
- [x] 4.4 Implement the uncovered-source case where output stays in industry inventory and nothing reaches any station, and verify it
- [x] 4.5 Implement a determinism test running the same starting state twice, and verify per-station allocations are identical
- [x] 4.6 Add a conservation test asserting total generated equals total allocated across many overlapping stations, and verify it holds for a month of simulation

## 5. Founder's Valley map

- [x] 5.1 Author the Founder's Valley map document with 2 towns, 2 coal mines, 2 power plants, water, forest, plains and raised rock (the authored map carries no `hill` tiles — the ridges are `rock`), and verify the loaded map reports the exact expected entity counts
- [x] 5.2 Verify the map offers at least two viable mine-to-plant rail corridors, by a pathfinding test over authored gradients
- [x] 5.3 Set starting cash so a mine-to-plant line with two stations and one train is affordable, and verify an scripted purchase sequence succeeds from the configured start

## 6. Verification

- [x] 6.1 Add a headless month-simulation test over Founder's Valley with two stations built and verify production, allocation and station inventories match exact expected values
