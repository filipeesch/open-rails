# train-system

## Purpose
Owns trains as simulation objects: rolling-stock data, consists, purchase,
deterministic movement along the rail graph, capacity per cargo type, speed
model, dwell, running cost, and the observable train status set.

## When to use
Train movement/consist/purchase code, wagon capacity rules, status reporting,
or connecting presentation (wheel phase, interpolation) to train state.

## Non-goals
Route stop lists and recalculation (`route-system`), loading transfer rules
and revenue (`cargo-system`), money (`economy`), path queries
(`rail-network`), visuals (`runtime-rendering`, `animation-authoring`).

## Dependencies
- Data: `game/data/locomotives/` and `game/data/wagons/` (ids, asset ids,
  price, running_cost, loco max_speed/power/weight, wagon cargo_type/
  capacity/weight) via `DataRegistry`.
- `RailNetwork.shortest_path` for paths; `StationService` spawn point;
  `EconomyService` (train_purchase / wagon_purchase / operating cost).
- `SimulationClock` 20 Hz ticks; timing constants in
  `game/data/economy/timing.json`.
- Presentation mirrors: `phase = fmod(distance_travelled /
  (2π * wheel_radius), 1)`.

## Invariants
1. Train state is a plain record owned by `TrainService`: current cell,
  position along segment, speed, route, destination stop, path (list of
  `(cell, direction)` + cumulative distances), cargo. Cell/offset are
  **derived from distance travelled**, not incremented — no graph drift.
2. Movement is deterministic; same start + route + tick count ⇒ same
   position. No physics; no collisions; two trains may share a cell
   (signals/collision are out of scope).
3. Speed model closed form: `v_max = loco.max_speed * min(1,
   loco.power / (total_weight + loco.weight))`, × grade factor on
   ascents, with acceleration/braking limits — nothing per-vehicle-code.
4. Capacity enforced per cargo type: cargo only rides wagons suited to it,
   never above wagon capacity; unusable cargo stays at the station.
5. Purchase requires a station (spawn at its rail access point), at least
   a locomotive, one `train_purchase` transaction; removing the locomotive
   from a consist is impossible while the train exists.
6. Status ∈ fixed set (heading_to_stop, loading, unloading, waiting,
   no_path …) — UI reads it, it is never inferred from animation.
7. Wheel phase and any animation are presentation-only; simulation never
   reads them (offscreen, suspended visuals still arrive/earn).

## Public interfaces
`TrainService`:
- `purchase(station_id, loco_def_id, wagon_def_ids) -> TrainId` (economy-checked)
- `train(id)` record: `speed`, `route_id`, `path`, `load(cargo)`, `status`,
  `distance_travelled`
- `consist_stats(def ids) -> {capacity per cargo, total weight, est max
  speed, purchase cost, running cost}` (shared with the consist editor UI)
- signals `train_created(id)`, `train_arrived(id, station_id)`.

## Implementation rules
- Positions advance `speed * tick_duration` with integer ticks; no
  wall-clock.
- Dwell = `max(min_dwell, units * per_unit_dwell)` ticks, constants in
  timing data.
- Consist editor reuses `consist_stats` server-side so editor numbers can
  never diverge from the purchased train.
- Presentation interpolates between derived positions; the renderer never
  writes back.

## Validation
Tests: two identical sims, 200 ticks ⇒ identical cell/segment; grade slows
the train below flat max; heavier consist ⇒ lower estimated speed; no hopper
⇒ coal stays ashore; purchase without station impossible; status becomes
`no_path` when a route dies and the reason is readable.

## Common mistakes
- Incrementing cell + leftover offset separately (drifts from the graph).
- Frame-rate-driven movement (breaks determinism and tick tests).
- Per-vehicle subclasses for behaviour (specs/data do it; code doesn't).
- Driving simulation from animation state ("train stopped because the
  animation ended") — never.

## Related skills
`route-system`, `cargo-system`, `rail-network`, `economy`,
`animation-authoring`, `simulation-clock`, `data-contracts`,
`runtime-effects`.
