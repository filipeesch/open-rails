# Workflow: create-industry

Create an industry: its 3D asset **and** its data-driven behaviour. V1 ships
coal mine + power plant; this procedure also covers a new industry type
without touching the cargo system.

## Read first (skills)
`industry-system` · `data-contracts` · `asset-scale` · `art-style` ·
`voxel-modeling` · `material-palette` · `animation-authoring` ·
`mesh-optimization` · `gltf-export` · `asset-validation` · `cargo-system`

## Steps
1. **Design the economics first.** In `game/data/industries/<id>.json`:
   ```json
   { "id": "coal_mine", "display_name": "Coal Mine", "asset_id": "coal_mine",
     "produces": [{ "cargo": "coal", "rate": 20, "capacity": 60 }],
     "accepts": [] }
   ```
   Producers: rate units/month, storage capacity, accumulate-to-full.
   Consumers: `"accepts": [{ "cargo": "coal", "capacity": N }]`. Multi-in/
   out (steel mill) is expressible the same way. New cargos referenced must
   exist in `game/data/cargo/` first.
2. **Model the plant** (3–6 tiles footprint, `lod_class = "industry"`,
   ≤ 10,000 tris LOD0) per `create-building` steps 2–5, plus:
   - mechanical `working` animation (pump, conveyor, wheel) looped per
     `animation-authoring`, registered in the manifest state map;
   - attachment points for loaders/delivery presentation
     (`cargo_load_0…`);
   - chimney/smoke origin if effects are wanted (`runtime-effects` binds
     them later).
3. **Build & validate.** `python tools/rr.py art build <id>` →
   `art validate <id>` → `art preview <id>` (all 16 views; machinery reads
   at normal zoom).
4. **Hook into the registry.** `DataRegistry` picks the JSON up
   automatically; no service branch. If the def references a missing cargo,
   boot fails — fix the reference.
5. **Author the source.** Register the industry into `SourceIndex`/
   occupancy grid at its map tile (Founder's Valley map document for
   shipped content).
6. **Test.** Extend `game/tests/domain/`: rate accumulation over one month
   (+20), saturation at capacity with full-report, consumption recording;
   allocation conservation with stations covering it. Run
   `python tools/rr.py test --filter industry`.
7. **Play-check.** `python tools/rr.py game run`: inspector shows
   production/month, stored, transported %, served-by; storage-full
   notification fires once at transition.

## Done when
Def parses at boot; asset validated; month-driven behaviour proven by
tests; no `IndustryService` subclass was added (data describes it).
