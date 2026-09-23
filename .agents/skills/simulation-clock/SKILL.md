# simulation-clock

## Purpose
Owns simulated time: the fixed 20 Hz tick loop decoupled from rendering,
game speeds (Paused/1×/2×/4×), the day/month/year calendar from January
1850, and the `month_changed` event that drives production, allocation,
accounting and recurring charges.

## When to use
Anything about tick stepping, pause behaviour, calendar dates, time-ratio
tuning, or subsystems that need to run "monthly".

## Non-goals
What happens on a tick (each system's skill), render frame timing
(`godot-project`), autosave scheduling (subscribes here — see `save-load`).

## Dependencies
- `GameSession` owns `SimulationClock`; subsystems subscribe to its events.
- Data: `game/data/economy/timing.json` — ticks-per-day, real-to-calendar
  ratio, dwell factors; the **only** place time pacing is tuned.
- Train movement consumes `tick_duration` (see `train-system`).

## Invariants
1. Fixed step: 20 Hz target, leftover time accumulated so varying render
   frame rate does not change outcomes over the same tick count; tick time
   is a 64-bit integer count.
2. Subsystems update in a fixed documented order each tick (reproducible);
   order is: clock/calendar → trains (movement) → stations/interaction
   arrivals → month-boundary handlers when the month rolled
   (project decision, pinned in code comment + test).
3. Speeds: Paused halts all simulation but leaves camera/UI/selecting fully
   responsive; 1×/2×/4× consume ticks proportionally.
4. Calendar is day/month/year starting January 1850; exactly one
   `month_changed` per calendar month; production/accounting subscribe —
   nobody polls the date.
5. Time ratio is one config value — `timing.json: ticks_per_day`, read at
   `configure()` — and **it is chosen against the rails, not against a taste
   for fast calendars.** A month must take longer than a loaded leg takes to
   run, or a producer's platform pins at its storage ceiling before the first
   train arrives and the industry looks broken while every number is correct.
   The shipped value is **60**: a month is ~1 800 ticks = ~90 s at 1×, a
   slightly-longer-than-a-leg (see the `pace_comment` in the data file, which
   records the measurement it came from). The dial for "I want it faster" is
   1×/2×/4×, which consumes more ticks per second of real time — that is the
   sanctioned compression, and it keeps simulation identical per tick.
6. No wall-clock or unseeded `randf()` inside simulation; a lint-style test
   asserts the clock is the only time source (seeded RNG injected into the
   session).

## Public interfaces
`SimulationClock`:
- properties `tick_count: int`, `ticks_per_day: int`, `speed_index: int`,
  `date: GameDate`, `tick_seconds: float`
- `configure(ticks_per_day, speed_index)` (from timing data),
  `set_speed_index(index)` / `set_speed(value)`, `speed()`, `speed_label()`,
  `is_paused()`
- `feed(real_delta) -> int` — render-side accumulation, **the only place
  `delta` may enter simulation**; `step()` one tick; `step_ticks(count)` for
  tests and fast-forward
- `add_subsystem(label, callback)` — the fixed per-tick update order
- `tick_time_micros()` / `tick_time_average_micros()` for the F3 overlay
- signals `tick_advanced(tick)`, `day_advanced(date)`, `month_changed(date)`
- `TICK_RATE := 20.0` is a GDScript const. `timing.json: tick_rate_hz` is
  **read by nothing** — changing the tick rate is a code change, and ground
  speed does not depend on it (see `train-system`).

## Implementation rules
- Expose tick count (never `Time.get_ticks_msec`) to simulation consumers.
- Keep the loop dumb: the clock does no gameplay work; handlers do.
- Headless tests drive `step_ticks(n)` directly — no real-time waiting in
  tests. Waiting for a *condition* uses `TestSession.run_until(session,
  predicate, budget)`, never a remembered tick count: a fixture that steps a
  hard-coded number of ticks silently truncates the moment `ticks_per_day`
  moves (it did, at 12 → 60).
- All pacing constants via timing.json; changing feel ≠ changing code.

## Validation
Tests: same scenario at simulated 30 vs 120 render fps executes identical
tick counts; pause ⇒ zero train motion, camera queries still served; month
rolls once per month (count events over 12 months = 12); year 1850→1851
rollover; ratio-halving test shows months ×2 faster, per-tick positions
unchanged; `test_the_timing_data_sets_the_pace_and_nothing_else` pins that the
clock runs at the pace the data file gives it and that the shipped pace leaves
a month longer than a loaded leg.

## Common mistakes
- Reading `Time.get_unix_time_from_system()` / `delta` inside domain code.
- Doing production work every tick and checking "is it the 1st?" (event
  instead).
- Speed = multiplying per-tick movement deltas instead of consuming more
  ticks (breaks determinism).
- Emitting `month_changed` twice on a year boundary.
- Setting `ticks_per_day` from the calendar's convenience instead of the
  rails' (invariant 5).

## Related skills
`train-system`, `cargo-system`, `economy`, `industry-system`,
`town-system`, `save-load`, `testing`, `performance`.
