# town-system

## Purpose
Owns towns as economic entities: data-defined population and generation
rates for passengers and mail, source registration for station coverage, and
the rule that town buildings are visual while the town is the simulation
entity.

## When to use
Town definitions, town cargo generation inputs, labels/inspector town data,
or how town visuals relate to the economic entity.

## Non-goals
Generation→station allocation (`cargo-system`), coverage (`station-
system`), visual city generation specifics (presentation; resolved by
`add-game-shell-and-persistence` open question), industry logic
(`industry-system`).

## Dependencies
- Data: `game/data/` town definitions — `{id, name, population, position,
  passenger_generation, mail_generation}` loaded once by `DataRegistry`
  into immutable `TownDef`s; instances hold runtime state only.
- Founder's Valley ships exactly 2 towns at authored positions.
- `SourceIndex` + occupancy grid so selection and coverage share one lookup.

## Invariants
1. Towns are defined in data, never constructed in code; V1 towns **do not
   grow** — population is constant across any amount of good service.
2. Each town contributes exactly its declared monthly passenger and mail
   quantities on the month boundary (via `cargo-system` allocation, the
   only writer into stations).
3. The town itself is the economic entity; its buildings/roads/scenery are
   visual only and carry no simulation state.
4. Town identity is a stable 64-bit `TownId`; name, population and position
   survive save/load unchanged.
5. A station catchment may overlap a town; the town's cargo is distributed
   once across covering stations (no duplication — `cargo-system` rule).

## Public interfaces
`TownService`:
- `define(town_def)`, `town(id) -> {name, population, position,
  passenger_generation, mail_generation}`
- registers itself as a cargo source into `SourceIndex`
  (`sources()` includes towns).

## Implementation rules
- Generation rates are units/month, accumulated fractionally, released as
  integer units (shared accumulator convention with industries).
- Town visuals may be authored scenery placed around the town centre —
  presentation may never assume building counts have economic meaning.
- Labels ("Brighton") come from town data through the pooled label layer,
  zoom-thresholded (`ui-layout` reference).
- Nearest-town name is the default station display name (ask this service,
  don't scan in UI).

## Validation
Tests: one month yields both streams at declared quantities; twelve months
of profitable service leaves population unchanged; overlapping-stations
case sums to exactly the produced amount (conservation lives in cargo tests
but town sources are exercised); save/load preserves id/name/position.

## Common mistakes
- Growing population with delivered cargo (dynamic growth is out of scope).
- Treating a town building as a selectable economic entity (selection goes
  to the town id via occupancy).
- Per-tick generation (month boundary only).
- Hard-coding Founder's Valley town names in code.

## Related skills
`cargo-system`, `industry-system`, `station-system`, `data-contracts`,
`save-load`, `town` visuals via `create-building` workflow.
