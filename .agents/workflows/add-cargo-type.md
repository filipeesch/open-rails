# Workflow: add-cargo-type

Add a fourth cargo (e.g. "iron_ore") purely through data. The defining test
of this workflow: **zero changes to the transport/cargo/route/train code.**

## Read first (skills)
`data-contracts` · `cargo-system` · `industry-system` · `town-system` ·
`station-system` · `train-system` · `testing`

## Steps
1. **Define the cargo.** `game/data/cargo/iron_ore.json`:
   ```json
   { "id": "iron_ore", "display_name": "Iron Ore",
     "base_rate": 6.0, "time_sensitivity": 0.02 }
   ```
   `base_rate` feeds `quantity × base_rate × distance × quality`;
   `time_sensitivity ∈ [0,1]` sets decay.
2. **Define a source and/or sink** in
   `game/data/industries/<id>.json` — producers use
   `"produces": [{"cargo": "iron_ore", "rate": 15, "capacity": 60}]`,
   consumers `"accepts": [{"cargo": "iron_ore", "capacity": N}]`. Multi-in/
   out industries (iron+coal→steel chains) are declared here the same way.
3. **Define carrying stock** in `game/data/wagons/` (a new wagon JSON with
   `"cargo_type": "iron_ore"`, its own `asset_id` — model it via the
   `create-wagon` workflow if it needs a new GLB).
4. **Wire display.** Verify the cargo appears in station inspector
   "Waiting" rows, hover tooltips and stop configuration lists — all read
   cargo defs dynamically; if anything enumerates cargos in code, that's a
   bug in the consuming system (fix it there).
5. **Optional effects/icons**: UI icon for the cargo; no world asset needed
   unless a new wagon/industry was added.
6. **Test (this is the proof).** Add to `game/tests/domain/`:
   - a new cargo def is produced, allocated and stored with no code change;
   - loading respects `cargo_type` (wrong wagon leaves it at the station);
   - revenue for the new cargo follows the shared formula exactly
     (`--filter cargo`).
   Run the full `python tools/rr.py test` — everything, including the
   integration scenario, stays green (V1 content unchanged: shipped data
   still has exactly passengers/mail/coal; the test loads the extra def
   from a temp data dir).
7. **Play-check** (dev data only): place the industry, cover with a
   station, watch the month allocation and inspector totals.

## Done when
The test drives the new cargo end-to-end; diff shows no edits under
`game/src/domain/` except the test itself; `rr.py test` fully green.
