# Workflow: create-wagon

Create a wagon asset **and** its rolling-stock definition so it appears in
the consist editor with no train-code changes. V1 ships: Passenger Coach,
Mail Car, Coal Hopper.

## Read first (skills)
`asset-scale` · `art-style` · `voxel-modeling` · `material-palette` ·
`animation-authoring` · `mesh-optimization` · `gltf-export` ·
`asset-validation` · `train-system` · `data-contracts`

## Steps
1. **Fix dimensions.** ~0.7 tile long × 0.45 wide (`asset-scale`),
   `lod_class = "vehicle"`, budget 4,000 tris LOD0. Truck/wheel diameters
   consistent with coupler ride height 0.04.
2. **Data.** `game/data/wagons/<id>.json`:
   ```json
   { "id": "coal_hopper", "display_name": "Coal Hopper",
     "asset_id": "coal_hopper", "price": 4000, "running_cost": 40,
     "cargo_type": "coal", "capacity": 40, "weight": 12 }
   ```
   `cargo_type` must reference an existing `game/data/cargo/` id; capacity
   is the per-wagon cap enforced by `train-system`.
3. **Model.** Body from primitives; hopper chutes / coach windows / mail
   cabinets as the readable class cue. Windows `glass_fake`. Company trim
   optional per type.
4. **Loading points.** Publish `cargo_load_0…` attachment points so
   dwell/loading animation and effects bind by name (`animation-authoring`).
5. **Optional `loading` action** (chute drop, door open) — short, loopable;
   map in the manifest.
6. **LODs.** Three levels; LOD2 = box silhouette with roofline/type cue.
7. **Build / validate / preview / integrate / test:**
   - `python tools/rr.py art build <id>` → `art validate <id>` →
     `art preview <id>` (16 views; couple a pair nose-to-nose at the
     published couplers — gaps/clip check)
   - integrate: def auto-appears in the consist editor
     (`DataRegistry`-driven) — no wagon-specific code path
   - test (`--filter consist`/`wagon`): capacity per type enforced (no
     hopper ⇒ coal stays ashore), weight feeds estimated max speed,
     purchase cost/running cost totals update when added.

## Done when
Asset validated and previewed; a train can be purchased with the wagon in a
headless test; cargo-type capacity assertions pass; adding it required zero
changes to `TrainService` or the transport code.
