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
5. Time ratio is one config value; halving it makes months arrive twice as
   fast with per-tick train behaviour unchanged; typical routes stay
   visually understandable at 1×.
6. No wall-clock or unseeded `randf()` inside simulation; a lint-style test
   asserts the clock is the only time source (seeded RNG injected into the
   session).

## Public interfaces
`SimulationClock`:
- `set_speed(Speed.PAUSED|X1|X2|X4)`, `speed()`
- `tick_count() -> int`, `date() -> {day, month, year}`
- driven internally from `_process` accumulation (render side) — the only
  place `delta` may enter simulation
- signal `month_changed(year, month)`.

## Implementation rules
- Expose tick count (never `Time.get_ticks_msec`) to simulation consumers.
- Keep the loop dumb: the clock does no gameplay work; handlers do.
- Headless tests drive `advance_ticks(n)` directly — no real-time waiting
  in tests.
- All pacing constants via timing.json; changing feel ≠ changing code.

## Validation
Tests: same scenario at simulated 30 vs 120 render fps executes identical
tick counts; pause ⇒ zero train motion, camera queries still served; month
rolls once per month (count events over 12 months = 12); year 1850→1851
rollover; ratio-halving test shows months ×2 faster, per-tick positions
unchanged.

## Common mistakes
- Reading `Time.get_unix_time_from_system()` / `delta` inside domain code.
- Doing production work every tick and checking "is it the 1st?" (event
  instead).
- Speed = multiplying per-tick movement deltas instead of consuming more
  ticks (breaks determinism).
- Emitting `month_changed` twice on a year boundary.

## Related skills
`train-system`, `cargo-system`, `economy`, `industry-system`,
`town-system`, `save-load`, `testing`, `performance`.
