# Design

## Context

See `add-trains-routes-and-revenue/proposal.md` for motivation. Rail graph, stations, cargo batches and the `EconomyService` skeleton exist. This change closes the first playable loop and must satisfy the specification's mandatory integration scenario: build rail, build two stations, buy a train, add hoppers, set a route, advance simulation, verify coal moved, the plant received it and revenue rose.

## Goals / Non-Goals

**Goals:**
- Simulation that is exact enough to assert in a unit test, including revenue to the unit of currency.
- Movement decoupled from rendering so tests run with no visuals at all.
- Rolling stock and route behaviour driven by data, not by code paths per vehicle.

**Non-Goals:**
- No collisions, signals or block reservation; no physics; no fuel or crew modelling.
- No 3D asset production here — models come from `add-art-pipeline`; this change only consumes manifests.

## Decisions

**Fixed 20 Hz tick, integer simulation time.** The clock counts ticks as a 64-bit integer; the real-to-calendar ratio and the ticks-per-day value live in `game/data/economy/timing.json`. Positions advance by `speed * tick_duration`, so determinism does not depend on frame timing. Alternative: frame-rate-driven movement — rejected outright by the specification's determinism requirement.

**Train state is a plain record owned by `TrainService`; presentation interpolates.** `path` is a list of `(cell, direction)` plus cumulative distances; the train stores distance travelled along the path and derives cell and segment offset on demand. Deriving rather than incrementing cell state avoids drift between position and graph.

**Speed model is a simple closed form.** `v_max = loco.max_speed * min(1, loco.power / (total_weight + loco.weight))` then multiplied by a grade factor when the next cell is higher, with acceleration and braking limits so arrival timing is predictable. A full tractive-effort model was rejected as unverifiable in V1.

**Pathfinding reuses `RailService` A\* over rail cells**, run when a route is created or `track_changed` fires for an affected route — never per tick, satisfying the runtime rules. Reachability at stop-pick time is the same query with a limit.

**Loading is a two-phase transfer** (unload to destination, then load from stop) executed as an atomic step at arrival, producing a dwell tick count `max(min_dwell, units * per_unit_dwell)`. Transfers move whole batches oldest-first, so the oldest cargo ships first and delivery quality rewards efficient routing.

**Revenue is computed at unload from batch origin and destination station distance**, using `quantity * base_rate * distance * quality`, with `quality = clamp(1 - time_sensitivity * age_months, floor, 1)`, rounded half-up to whole currency once at the end so tests can assert exact totals.

**`EconomyService` becomes the sole mutation point**, extended here with category-tagged expenses, monthly aggregation on `month_changed` and an assertion-friendly transaction id. A test guard asserts the ledger sum equals cash, which is how the "never scatter `cash -= cost`" rule stays enforced rather than merely documented.

**Wheel phase is presentation-only:** `phase = fmod(distance_travelled / (2π * wheel_radius), 1)`, consumed by the locomotive's rod animation. Simulation never reads it.

**Service wiring lives in `GameSession`,** an `Node` composition root that constructs services in dependency order and exposes typed signals. Autoload singletons are avoided so a test can create an isolated session.

## Risks / Trade-offs

- [Determinism breaks if any subsystem reads wall-clock or `randf()`] → a lint-style test asserts the clock is the only time source and seeded RNG is injected into the session.
- [Dwell time and speed constants make the loop either boring or unreadable] → all constants in `game/data/economy/timing.json` and a test asserting a typical route completes in a target tick band.
- [Rounding policy mismatch between revenue and ledger] → one shared `Money` helper performs all rounding, used by both sides.

## Migration Plan

Additive services plus UI drawers. Rollback removes train and route code; stations keep accumulating cargo exactly as in the previous change.

## Open Questions

- Whether trains accelerate from a standstill at every stop or only after a dwell threshold — a feel decision deferred to playtesting, with the threshold already in data.
