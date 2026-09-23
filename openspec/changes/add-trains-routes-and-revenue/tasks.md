# Tasks

## 1. Simulation clock and economy completion

- [x] 1.1 Implement the 20 Hz fixed-step clock accumulating leftover time with subsystems updated in fixed order, and verify tick count over a fixed simulated span is frame-rate independent in a headless test
- [x] 1.2 Implement Paused, 1x, 2x and 4x speeds with pause freezing simulation only, and verify trains and the calendar stop while camera and UI stay responsive
- [x] 1.3 Implement the day/month/year calendar from January 1850 with rollovers and exactly one `month_changed` event per month, and verify December 1850 rolls into January 1851
- [x] 1.4 Move the real-to-calendar ratio into `game/data/economy/timing.json` and verify halving it doubles month cadence without changing per-tick behaviour
- [x] 1.5 Extend `EconomyService` with expense categories, monthly revenue/expense/profit totals and previous-month retention, and verify profit equals revenue minus expenses at a month boundary

## 2. Rolling stock and purchase

- [x] 2.1 Write locomotive and wagon JSON definitions for the 4-4-0 and the three wagons and verify the loader exposes price, running cost, speed, power, weight, cargo type and capacity
- [x] 2.2 Implement consist composition with add, remove and reorder plus locomotive-removal protection, and verify per-cargo capacity totals update on each edit
- [x] 2.3 Implement estimated maximum speed from locomotive power against consist weight, and verify adding wagons reduces the estimate
- [x] 2.4 Implement purchase from a starting station spawning the train at its rail access, charging one combined transaction and refusing without funds or without any station, and verify all three paths
- [x] 2.5 Render the consist from generated GLBs with company primary and secondary colour parameters, and verify two liveries share one model
  A livery is two colour parameters on two shared materials: `ModelCatalog` keeps one
  `StandardMaterial3D` per reserved role (`livery_material("primary")` /
  `livery_material("secondary")`, static because a livery belongs to the company and
  not to whichever renderer loaded an asset first) and rewires each asset's reserved
  surfaces onto them at load. The wiring is done on the `Mesh` with
  `surface_set_material` rather than with `material_override`, because Godot 4.7 gives a
  `MeshInstance3D` one node-wide override and no per-surface one, and an LOD made by
  merging keeps company and body faces in one node — an override there would blank the
  livery the moment the view pulled back. `session.company_livery()` chooses the table
  entry from the company's name (`game/data/company/liveries.json`, folded by arithmetic
  written in `DataRegistry` rather than the engine's `hash()`), so no screen has to pick
  paint and a save carrying the name repaints itself. Proven by
  `game/tests/test_company_livery.gd` (6 cases): the beams and cab carry the shared
  materials and the rest of the consist still draws with the one vertex-colour material —
  three materials for a whole consist, three for a station plus a consist — the reserved
  colour survives to LOD0, LOD1 and LOD2, a domain rename plus two `albedo_color` writes
  repaints every body with the same node, mesh and material identities, and two shared
  materials serve the company however many things wear them.


## 3. Train movement and animation

- [x] 3.1 Implement `TrainService` tick advancement along a path of rail cells with current cell, segment position, speed, route, destination and cargo state, and verify two identical runs land on identical positions after 200 ticks
- [x] 3.2 Implement speed limits from consist weight and ascending grade with acceleration and braking limits, and verify a loaded train slows on a one-step grade and never exceeds its maximum
- [x] 3.3 Implement trains passing through one another with no collision or blocking, and verify two opposing trains cross without status change
- [x] 3.4 Implement presentation wheel phase from travelled distance over wheel circumference, and verify wheel phase stops during dwell and doubles with speed
  `EntityRenderer` keeps an odometer per train (`_record_travel`, driven from the
  simulation's `position_tiles` every frame whether or not the consist is on screen)
  and poses each vehicle's `AnimationPlayer` at `fmod(distance / circumference)` with
  `seek(phase * clip_length, true)` on a paused player — the compiler publishes
  `wheel_circumference_tiles` per wheel role and each `moving` clip is exactly one
  revolution, so the phase is the clip position and nothing else. Proven by
  `tests/test_view_lod.gd`: `test_the_wheels_turn_because_the_train_moved`,
  `test_the_wheels_of_a_standing_train_do_not_turn`,
  `test_the_wheels_rest_while_the_train_dwells_in_a_station` (three dwells, zero drift),
  `test_twice_the_ground_turns_the_wheels_twice_as_far` (the game's speed control is
  ticks per frame, so 2x is twice the ground between draws) and
  `test_a_consist_rebuilt_mid_run_keeps_its_crank_angle`. Two pipeline fixes came out of
  writing it: `art/railroad_art/animation.py` now rejects an action named with a leading
  or trailing `loop`/`cycle` token, because Godot's glTF importer consumes that token as a
  playback hint and files the clip under the stripped name — `steam_440`'s `run_cycle`
  arrived as `run`, invisible to the manifest's promise — and the entry list a consist's
  wheels live in is returned by `_wire_wheels` rather than mutated through an untyped
  `Dictionary`, which was silently discarding every wheel.

- [x] 3.5 Suspend offscreen train visuals while simulation continues, and verify an offscreen train still arrives, loads and earns
  `EntityRenderer.tick()` projects each consist's simulated position through the rig
  (`_is_framed`, padded by `OFFSCREEN_MARGIN_PIXELS` so a train scrolling in is already
  positioned) and hides the bodies it cannot see instead of repositioning them; framing
  is asked of `position_tiles` and never of the last drawn frame, or the suspension would
  feed on itself. `tests/test_view_lod.gd`:
  `test_a_consist_off_the_edge_of_the_screen_stops_being_worked_on` (node frozen to 1e-6
  across 600 ticks while the train moves), `test_an_offscreen_train_still_arrives_loads_and_earns`
  (deliveries, revenue and cash all grow off-screen, and the body is on the simulated tile
  the frame it comes back into view) and `test_suspending_the_animation_changes_nothing_the_simulation_decides`.


## 4. Routes, loading and delivery

- [x] 4.1 Implement route definitions with ordered stops and per-stop load/unload cargo sets, and verify a two-stop route executes cyclically in order
- [x] 4.2 Implement station-picking mode for adding a stop with reachability validation rejecting unreachable stations with a reason, and verify a reachable pick appends the stop
- [x] 4.3 Implement remove, reorder and load-configuration edits with live path validity, and verify reordering recomputes the path
- [x] 4.4 Recompute affected routes on `track_changed`, marking the route invalid with a notification naming train and unreachable station, and verify rebuilding the removed track restores validity without recreating the route
- [x] 4.5 Implement arrival-time loading and unloading with capacity and acceptance rules and dwell proportional to units handled, and verify a 40-unit stop holds the train longer than a 10-unit stop
- [x] 4.6 Implement delivery-quality decay by batch age with coal minimally affected and a clamped floor, and verify an aged passenger batch yields less revenue than a fresh one
- [x] 4.7 Implement revenue as `quantity × base_rate × distance × delivery_quality` from configuration and record one ledger transaction per delivery, and verify doubling distance doubles revenue and doubling a configured rate doubles revenue

## 5. Verification

- [x] 5.1 Add the specification's core-loop integration test — create world, build rail, build mine and plant stations, buy a train with hoppers, set the route, advance simulation, assert coal moved, plant received it and revenue increased — and verify it passes headlessly
- [x] 5.2 Run the full suite including the economy ledger-sum guard and verify all tests pass
