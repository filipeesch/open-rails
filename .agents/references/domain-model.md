# Domain Model

The authoritative simulation layer. Lives in `game/src/domain/`; knows nothing
about presentation or UI. Summarises spec §51–§55 plus the change designs
(`add-world-and-camera`, `add-map-economy-sources`,
`add-trains-routes-and-revenue`) — read those for full rationale.

## Composition root

`GameSession` (a `Node`) constructs services in dependency order, owns all
simulation state, and exposes typed signals. No uncontrolled autoload
singletons for game state; tests create an isolated `GameSession`.

Services: `WorldService`, `RailService` (+ `RailNetwork`), `StationService`,
`TrainService`, `RouteService`, `CargoService`, `IndustryService`,
`TownService`, `EconomyService`, `SimulationClock`, `SaveService`,
`UndoService`, and a `DataRegistry` that loads `game/data/` JSON into
immutable definition records (`TownDef`, `IndustryDef`, `CargoDef`,
`StationDef`, locomotive/wagon defs).

## World data (`WorldGrid`)

Typed arrays indexed `y * width + x` — never nodes, never dictionaries:

| Array | Type | Holds |
|---|---|---|
| `terrain` | `PackedByteArray` | terrain type (grass/dirt/rock/water…) |
| `height` | `PackedByteArray` | height in HEIGHT_STEP units |
| `occupancy_kind` | `PackedByteArray` | which entity kind occupies the tile |
| `occupancy_id` | `PackedInt64Array` | stable entity ID owning the tile |
| `rail` | `PackedByteArray` | 8-bit connection bitmask per cell |

Rail bit order: `N, NE, E, SE, S, SW, W, NW`. The rail graph is *derived*
from masks; reciprocals are written together; it is never stored twice.
Changes emit notifications identifying affected tiles so renderers rebuild
only dirty chunks. `WorldCoords` owns `tile_to_world` / `world_to_tile` /
plane-intersection helpers.

## Entities and IDs

All persistent entities carry stable 64-bit IDs: `TownId`, `IndustryId`,
`StationId`, `TrainId`. IDs survive save/load and network edits; renaming
never changes them. **Never** persist or pass scene-node paths as references.

- **Town**: id, name, population, position, passenger_generation,
  mail_generation. No dynamic growth in V1. Visual buildings/scenery only.
- **Industry**: data-driven producer/consumer — `produces:
  [{cargo, rate, capacity}]` and `accepts: [{cargo, capacity}]`; a single
  `IndustryService` steps these lists (no subclasses). V1: 2 coal mines
  (e.g. 20 units/month), 2 power plants.
- **Station**: one class (Small Station). Needs footprint on buildable land
  plus adjacent rail with an allowed alignment (asked of `RailService`).
  Catchment radius 4 tiles; per-cargo waiting inventory; sources register in
  the occupancy grid / `SourceIndex`.
- **Train**: plain record owned by `TrainService` — current cell, position
  along segment, speed, route, destination stop, path (list of
  `(cell, direction)` + cumulative distances), cargo. Movement is
  deterministic along the rail graph; no physics, no collisions, trains pass
  through each other. Status from a fixed set (heading to stop / loading /
  unloading / waiting / no path).
- **Route**: ordered list of ≥2 station stops, each with load/unload cargo
  config; executed cyclically; path recomputed on creation and on
  `track_changed` — never per tick.
- **Cargo**: batches keyed `(station, cargo_type, origin_key)` carrying
  cargo_type, quantity, origin, destination, created_at. Aggregated on
  arrival; never one object per passenger/unit.
- **Economy**: cash, monthly revenue/expenses/profit, transaction ledger.
  Expense categories: track construction, station construction, train
  purchase, wagon purchase, train operating cost, track maintenance.

## Clock

Fixed 20 Hz tick, integer tick count; speeds Paused/1×/2×/4×; calendar day,
month, year starting January 1850; real-to-calendar ratio and ticks-per-day
in `game/data/economy/timing.json`. Emits exactly one `month_changed` per
month; production, allocation, accounting and recurring charges subscribe to
that event, never poll the date.

## Events (domain → anyone)

`track_changed`, `station_created`, `train_created`, `train_arrived`,
`cargo_delivered`, `money_changed`, `month_changed`, plus selection/hover
publications. Transient player-facing messages ride a `NotificationBus`.
UI listens; simulation never calls UI.
