# Workflow: create-building

Create or change a generic building/scenery asset (house, station building,
town hall). Output: a validated GLB + manifest in `game/generated/`.

## Read first (skills)
`asset-scale` · `art-style` · `voxel-modeling` · `material-palette` ·
`mesh-optimization` · `lod-policy` · `gltf-export` · `asset-validation` ·
`blender-headless`

## Steps
1. **Class it.** Pick `lod_class` (house ≤ 2,500 tris LOD0; station ≤ 8,000)
   and footprint from `.agents/references/asset-scale.md` (small house ~1
   tile, large 1–2). Record both in `asset.toml` before modelling.
2. **Scaffold the package.** `art/assets/buildings/<id>/asset.py` +
   `asset.toml`:
   ```toml
   id = "<id>"
   type = "building"
   footprint = [1.0, 1.0]
   lod_class = "house"
   ```
   Builder imports only `railroad_art` primitives (boxes, roofs, colour
   helpers) except where the abstraction genuinely fails.
3. **Model big→small.** Block silhouette → verify → one detail pass.
   Palette categories only; windows = `glass_fake`; bake fake-AO into vertex
   colours. Station-type buildings declare `[company_colors]` trim regions.
4. **LODs.** LOD0 authored; LOD1/LOD2 via auto-reduce first, hand-fix the
   silhouette if auto damages rooflines/chimneys.
5. **Build.** `python tools/rr.py art build <id>`
   (batch: `art build --all --jobs 3`). On failure, read the printed job
   log; `--keep-temp` to inspect staging.
6. **Validate.** `python tools/rr.py art validate <id>` — scale (5%
   footprint), origin, palette whitelist, per-LOD budgets, manifest
   integrity all green.
7. **Preview + review.** `python tools/rr.py art preview <id>` → review all
   16 images in `build/previews/<id>/` (8 angles × 2 zooms); check it
   beside neighbours at default zoom.
8. **Integrate.** The runtime consumes it via the manifest adapter: for
   scenery use the chunk `MultiMesh` registry; for placed entities register
   in the map/scenery data. No renderer code changes for a compatible new
   asset — if it needs one, the contract broke (stop and review).
9. **Test.** `python tools/rr.py check` (imports) and
   `python tools/rr.py test` if runtime wiring changed; confirm unchanged
   rebuild counters for an existing map load.

## Done when
`art build` + `art validate` exit 0, previews reviewed, asset visible in
game (`python tools/rr.py game run`) from all rotations, nothing in
`game/generated/` hand-edited.
