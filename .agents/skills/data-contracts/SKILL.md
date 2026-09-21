# data-contracts

## Purpose
Owns `game/data/` — the JSON definitions that make cargo, industries, towns,
stations, locomotives, wagons and economy tuning data-driven, and the
`DataRegistry` that loads them into immutable definition records at session
start.

## When to use
Adding or editing any `game/data/` file, changing a price/rate/capacity,
adding a cargo or wagon, or deciding "data or code?" for a new knob.

## Non-goals
Save-file schema (`save-load`), asset metadata `asset.toml` (art side, see
`gltf-export`), world config `art/config/world.toml` (constants, see
`asset-scale`).

## Dependencies
- Layout (spec §76): `game/data/{cargo,locomotives,wagons,industries,
  stations,economy}/`; Founder's Valley map document (RLE layers + explicit
  entity lists) also lives as data.
- `DataRegistry` parses once at `GameSession` start into `CargoDef`,
  `TownDef`, `IndustryDef`, `StationDef`, `LocoDef`, `WagonDef` records;
  instances hold runtime state only.
- JSON only for V1 (diffable, script-authorable, matches spec examples;
  `.tres` rejected by design).

## Invariants
1. Simulation behaviour knobs live in data: rates, prices, capacities,
   time sensitivity, planner weights, dwell/timing (`economy/timing.json`).
   Code provides rules; data provides numbers and content.
2. New content without code: a 4th cargo, a new wagon, a steel-mill-style
   multi-in/out industry must load and simulate with no transport-system
   edit (spec-mandated extensibility tests).
3. Definitions are immutable after load; runtime state (inventory,
   received_this_month) lives on instances, never written back to defs.
4. Cross-references are by id string (`"cargo": "coal"`); a def referencing
   an unknown id fails registry load with the file and id named — loudly,
   at boot, not mid-month.
5. `save_version` and data versions stay compatible: data edits that rename
   ids require a save migration (`save-load` contract).
6. Timing: `game/data/economy/timing.json` holds the real-to-calendar ratio
   and ticks-per-day — pacing changes never touch code.

## Public interfaces
Shape examples (canonical fields; add-only where possible):

```json
{ "id": "coal", "display_name": "Coal", "base_rate": 8.0, "time_sensitivity": 0.05 }
```

- Locomotive: `{id, display_name, asset_id, price, running_cost,
  max_speed, power, weight}`; V1 ships the 4-4-0 only.
- Wagon: `{id, display_name, asset_id, price, running_cost, cargo_type,
  capacity, weight}`; ships passenger_coach, mail_car, coal_hopper.
- Industry: `{id, display_name, asset_id, produces: [{cargo, rate,
  capacity}], accepts: [{cargo, capacity}]}`.
- Town: `{id, name, population, position, passenger_generation,
  mail_generation}`.

`DataRegistry`: `load_all()`, `cargo(id)`, `wagon(id)`, `locomotive(id)`,
`industry(id)`, `town(id)`, `station(id)`, `economy(key)`.

## Implementation rules
- One file per def, filename = id (`cargo/coal.json`) — greppable diffs.
- Numbers: integers for money/units, floats only for rates.
- Validation belongs to `DataRegistry`: required keys, known refs, ranges
  (capacity ≥ 0, sensitivity in [0,1]) — fail at boot.
- Balance passes touch only data files; if balancing needs a code change,
  the knob was hard-coded — extract it.

## Validation
Registry test: every shipped file parses, every reference resolves, a
deliberately broken ref is reported with file+id. Extensibility test: load
a 4th cargo + a new wagon from a temp data dir and exercise them through
allocation and loading with no code change.

## Common mistakes
- Hard-coding coal's rate in `IndustryService`.
- Editing a def file to hold per-instance state (one mine's inventory!).
- Renaming an id without a save migration.
- Letting a def silently default a missing key instead of failing boot.

## Related skills
`cargo-system`, `industry-system`, `town-system`, `station-system`,
`train-system`, `economy`, `simulation-clock`, `save-load`,
`add-cargo-type` workflow.
