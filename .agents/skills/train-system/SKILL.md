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

## The speed scale (read this before touching a speed number)
The game has two units of distance and one of them is not metres. They meet in
exactly one place, and it is derived rather than chosen:

```
TrainService.KMH_TO_TILE_PER_TICK = 1 / (3.6 * WorldConstants.TILE_METRES * SimulationClock.TICK_RATE)
```

- `WorldConstants.TILE_METRES` (currently **16.0**) comes from
  `art/config/world.toml [world] metres_per_tile`, and is anchored: the 4-4-0 is
  built 0.85 tiles long and is a ~14 m engine over buffers, so a tile is ~16 m.
  See `.agents/references/asset-scale.md`.
- `max_speed_kmh` in the locomotive JSON is therefore the **only** speed a
  designer sets. `top_speed_tiles_per_tick()` and `speed_kmh()` are both
  derived from it, so the panel and the ground can never disagree — which is
  what was wrong when the conversion was a hand-tuned `0.0105`: the label said
  55 km/h and the valley ran at ~20 locomotive-lengths a second.
- Ground speed in tiles/second is `kmh / (3.6 * TILE_METRES)`, **independent of
  the tick rate**. Raising `tick_rate_hz` cannot speed a train up; it only makes
  each tick finer (dwell and loading get finer-grained, not faster).
- Acceleration and braking are the same physical quantities and must be scaled
  the same way: 0.35 m/s² and 0.90 m/s² through `TILE_METRES` at `TICK_RATE`
  give `acceleration_per_tick 0.0011` / `braking_per_tick 0.0028`. An absolute
  limit in `_accelerate` (a creep floor of "0.02 tiles") means one thing at the
  old scale and 30% of top speed at the new one — the floor is
  `CREEP_FRACTION_OF_TOP * top` instead.
- Pace is graded by the eye in **body lengths per second**, which the 16 m
  anchor puts at ~1.2 for the shipped express. `tests/test_travel_scale.gd`
  bounds it at 0.4–3.0 body lengths/s and 8–120 s to cross the default view.
  If a change makes a train feel like a fired bullet, the scale is wrong — fix
  the scale, not the label.

## How a model is turned
Assets are authored **nose along +X, axle along Y**. So local +X maps to
`(cos θ, −sin θ)` and yaw for a travel direction `d` is `atan2(-d.y, d.x)`,
which is `WorldCoords.yaw_for_direction(d)` (`yaw_degrees_for_direction` for
`heading()`). Writing `atan2(-d.x, d.y)` is a mirror, not a rotation: it is 90°
off on every axis-aligned run. A consist is strung out along local **−X**
behind its engine, so cars are offset on X, not Z.

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
`tests/test_travel_scale.gd` additionally pins the km/h↔tile identity, the
reported speed against measured ground, the body-lengths/s and view-crossing
bounds, and that a drawn consist faces the way it travelled.

## Common mistakes
- Incrementing cell + leftover offset separately (drifts from the graph).
- Frame-rate-driven movement (breaks determinism and tick tests).
- Tuning a tiles-per-tick constant to "feel right" while the km/h readout
  stays honest. Everything speed-shaped derives from `max_speed_kmh` and
  `TILE_METRES`.
- Per-vehicle subclasses for behaviour (specs/data do it; code doesn't).
- Driving simulation from animation state ("train stopped because the
  animation ended") — never.

## Related skills
`route-system`, `cargo-system`, `rail-network`, `economy`,
`animation-authoring`, `simulation-clock`, `data-contracts`,
`runtime-effects`.
