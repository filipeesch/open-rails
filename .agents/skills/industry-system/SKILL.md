# industry-system

## Purpose
Owns industries as data-driven producers and consumers: coal mines producing
coal into storage, power plants accepting coal, capacity saturation
reporting, and the framework that will express iron+coal→steel chains
without touching the cargo system.

## When to use
Industry behaviour, storage-full notifications, industry inspector figures,
or authoring new industry definitions.

## Non-goals
Cargo movement/allocation (`cargo-system`), station coverage
(`station-system`), town cargo generation (`town-system`), industry meshes
(`art-*` skills).

## Dependencies
- Data: `game/data/industries/` — definitions carry
  `produces: [{cargo, rate, capacity}]` and `accepts: [{cargo, capacity}]`;
  one `IndustryService` steps the lists (no per-industry subclasses).
- `SimulationClock.month_changed` for production ticks; `SourceIndex` /
  occupancy registration; `TownService` shares the source framework.
- Founder's Valley ships 2 coal mines (e.g. 20 units/month) + 2 power
  plants, authored in the map document.

## Invariants
1. A producer accumulates its rate up to `storage_capacity`
  (`current_inventory` clamps at capacity; reaching capacity **stops**
  accumulation and is reportable for notifications).
2. A consumer records accepted cargo in `received_this_month`; deliveries
  are recorded, not rejected.
3. Industry behaviour is entirely data-described: a def may declare
  multiple inputs and outputs (steel-mill case must simulate without
  transport/cargo code changes).
4. The V1 chain stays exactly mine→coal→plant; framework generality is not
  licence to ship more content (advanced chains are out of scope).
5. Industry identity is a stable 64-bit `IndustryId`; inspector figures
  (production/month, stored, transported %, served-by) are service queries,
  not UI arithmetic over caches.
6. Production only steps on month boundaries — no per-tick industry work.

## Public interfaces
`IndustryService`:
- `define(industry_def)` (DataRegistry), `spawn(def_id, tile) -> IndustryId`
- `industry(id)` → {def, position, inventory per output, received_this_month}
- `capacity_full(id) -> bool`, `accept_delivery(id, cargo, qty) -> bool`
- signals `industry_full(id)`, plus source registration for coverage.

## Implementation rules
- Floating-point rate accumulation goes through a per-source float
  accumulator; integer units cross service boundaries (conservation).
- `transported %` is derived: delivered-to-date / produced-to-date,
  computed on demand.
- New industry kinds land as JSON + art; the service must not gain branches.
- Keep coal's low time sensitivity in `game/data/cargo/coal.json`, not in
  industry logic.

## Validation
Tests: mine 20/month, one month idle ⇒ inventory +20; capacity 60 at 55
after a month ends at 60 and reports full; 30 coal delivered ⇒ plant
received_this_month reflects it; a declared steel-mill def (coal+iron in,
steel out) constructs and steps in a test without transport-code changes.

## Common mistakes
- A `CoalMine.gd`/`PowerPlant.gd` subclass per behaviour (rejected in
  design — data describes them).
- Overflowing storage when the train picks up mid-month.
- Notifying "storage full" every tick instead of on the transition.
- Growing the shipped content beyond the spec's 2 industries.

## Related skills
`cargo-system`, `town-system`, `station-system`, `data-contracts`,
`simulation-clock`, `industry` art workflow `create-industry`.
