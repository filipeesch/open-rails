# cargo-system

## Purpose
Owns cargo end-to-end: data-defined cargo types, monthly generation from
sources, duplication-free allocation to covering stations, batch storage,
loading/unloading transfers, delivery quality decay and the revenue
formula.

## When to use
Cargo generation/allocation bugs, batch aggregation, load/unload rules,
delivery quality/revenue calculations, adding a cargo type (also see the
`add-cargo-type` workflow).

## Non-goals
Which stations exist / their inventory storage (`station-system`), source
definitions (`town-system`, `industry-system`), ledger posting (`economy`),
train dwell/capacity mechanics (`train-system`).

## Dependencies
- Data: `game/data/cargo/` — V1 exactly `passengers`, `mail`, `coal`
  (`{id, display_name, base_rate, time_sensitivity}`; e.g. coal `base_rate
  8.0, time_sensitivity 0.05`).
- Month boundary: `SimulationClock.month_changed` drives generation +
  allocation (never poll the date).
- `StationService.covered_sources` + `SourceIndex`; `EconomyService` for
  revenue posting; `Money` helper for rounding.

## Invariants
1. V1 cargos: exactly passengers (town→town, time-sensitive, high revenue),
   mail (town→town, moderate), coal (mine→plant, little/no decay). The
   transport system must handle a 4th cargo from data with **no code
   change**.
2. Allocation runs per source per month and is the **only** place cargo
   enters a station: gather covering stations, weight `1/(distance+1)`,
   distribute integer units largest-remainder so Σ allocations == produced
   quantity exactly; uncovered sources emit nothing usable; fractional
   remainders accumulate in a float accumulator per source.
3. Cargo is batches keyed `(station, cargo_type, origin_key)` carrying
   {type, quantity, origin, destination, created_at}; compatible arrivals
   aggregate (combined quantity, earliest creation time). Batch count is
   bounded by source/station pairs, never by unit count.
4. Loading/unloading is one atomic two-phase transfer at arrival: unload
   what the destination accepts first, then load the configured cargo up to
   suitable wagon capacity; whole batches move oldest-first; rejected cargo
   stays aboard or at the station.
5. Revenue at unload: `quantity × base_rate × rail_distance × quality`,
   `quality = clamp(1 − time_sensitivity × age_months, floor, 1)`, rounded
   half-up once at the end via the shared `Money` helper; every delivery is
   one ledger transaction naming cargo/quantity/route.
6. Generation and allocation are deterministic for (world state, month,
   config) — tests assert exact quantities.

## Public interfaces
`CargoService`:
- `define(cargo_def)` (from DataRegistry), batches per station queryable:
  `batches(station_id)`, `waiting(station_id, cargo) -> int`
- `allocate_month()` (subscribed to `month_changed`)
- `transfer_on_arrival(train_id, stop)` (called by train-system)
- signals `cargo_delivered(cargo, quantity, from_station, to_station,
  revenue)`.

## Implementation rules
- Never instantiate one object per passenger; aggregate on arrival.
- Conservation is asserted in tests (Σ station stock + industry inventory
  + onboard == Σ produced − Σ delivered).
- Keep coefficients (rates, quality floor, dwell factors) in
  `game/data/economy/` — balancing never edits code.
- Delivery distance is the **rail** distance origin→delivery station.

## Validation
Tests: single covering station gets all 20 coal; two stations over a 30-
passenger town sum to exactly 30, nearer larger; 400 units/month keeps one
batch; capacity 40 vs stock 60 loads 40; aged passengers earn less, coal
doesn't; doubled base_rate doubles revenue without code edits; ledger entry
exists per delivery.

## Common mistakes
- Allocating per station ("each covering station gets full production") —
  duplicates cargo, the central hazard this design exists to prevent.
- One batch per unit or per tick (memory + non-deterministic ordering).
- Rounding quality per component (drift vs exact test totals — round once).
- Mutating station inventory outside the allocation/transfer paths.

## Related skills
`town-system`, `industry-system`, `station-system`, `train-system`,
`route-system`, `economy`, `data-contracts`, `testing`.
