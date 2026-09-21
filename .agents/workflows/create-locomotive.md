# Workflow: create-locomotive

Create the 3D asset for a locomotive with running-gear animation and company
livery regions. (The V1 game ships exactly one: `steam_440`, a 4-4-0.)

## Read first (skills)
`asset-scale` · `art-style` · `voxel-modeling` · `material-palette` ·
`animation-authoring` · `mesh-optimization` · `gltf-export` ·
`asset-validation` · `lod-policy` · `blender-headless`

## Steps
1. **Fix the dimensions.** From `.agents/references/asset-scale.md`:
   length ~0.85, footprint width 0.45, driving wheels r=0.11 ×2/side,
   leading wheels r=0.06 ×2/side, boiler r=0.14, cab w=0.24, chimney h=0.22.
   `lod_class = "vehicle"`, budget 12,000 tris LOD0.
2. **Package.** `art/assets/vehicles/<id>/asset.toml`:
   ```toml
   id = "<id>"
   type = "locomotive"
   footprint = [1.0, 0.45]
   lod_class = "vehicle"

   [animation]
   moving = true

   [company_colors]
   primary = true
   secondary = true
   ```
3. **Build from primitives only** (`railroad_art`):
   `frame/boiler/cab/chimney/add_driving_wheels/add_leading_wheels` —
   the spec requires primitive-only construction for these parts.
   Wheels/rods stay separate named nodes.
4. **Animate.** `animate_running()` on the 24-frame loop convention; the
   action maps to canonical state `moving` in the manifest (`idle: null`).
   Rod phase will be driven by distance travelled — author the loop so one
   cycle = one wheel revolution.
5. **Company livery.** Tag cab/water-tank bands with
   `company_color("cab")` style helpers → faces use the company material,
   not baked colour (two liveries from one asset).
6. **Attachment points.** `chimney_smoke`, `coupler_front`, `coupler_rear`
   published in the manifest with local coordinates.
7. **LODs.** LOD1 (normal gameplay), LOD2 silhouette (rods/wheels may
   merge; boiler+cab+chimney profile must read).
8. **Build / validate / preview / integrate / test:**
   - `python tools/rr.py art build <id>`
   - `python tools/rr.py art validate <id>` (budgets, palette, actions,
     attachments)
   - `python tools/rr.py art preview <id>` — all 16 angles/zooms; check
     rods and wheels at close zoom (spec: close zoom must show wheels,
     windows, rods clearly)
   - integrate: add `game/data/locomotives/<id>.json`
     (`{id, display_name, asset_id, price, running_cost, max_speed, power,
     weight}`) — purchase/consist UI picks it up through `DataRegistry`
   - `python tools/rr.py test` + `game run`: buy it at a station, confirm
     wheels stay locked to speed (no slide) when the train runs.

## Done when
Validated asset + manifest, company tint verified with two colour
parameters, wheel phase sync visually correct, def purchased through the
economy in a test.
