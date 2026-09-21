# material-palette

## Purpose
Owns the canonical colour system: palette categories, the shared
vertex-colour material, company-colour parameterisation, and the vertex-colour
rules (fake glass, metal, wood conventions). No asset invents a new visual
material without changing this system first.

## When to use
When colouring any asset surface, when a build fails a material check, or
when runtime terrain/entity colours must match art.

## Non-goals
Geometry (`voxel-modeling`), runtime material/shader implementation detail
(`runtime-rendering`), which colours look good on trains artistically
(`art-style`).

## Dependencies
- `.agents/references/material-palette.md` — 15 categories + proposed RGBs.
- `art/config/material_palette.json` — canonical palette data (named by the
  `add-art-pipeline` design; it stores the RGB the runtime reuses for
  terrain). JSON wins over the reference copy on disagreement.
- `railroad_art` colour helpers (assign palette categories, bake AO darkening).

## Invariants
1. The 15 spec categories are the whole vocabulary: grass, earth, stone,
   brick_red, brick_brown, roof_red, roof_dark, wood_light, wood_dark, iron,
   steel, glass_fake, water, company_primary, company_secondary.
2. Every opaque surface in every asset is drawn by ONE shared vertex-colour
   material; an asset defines no unique material of its own.
3. Company-coloured faces reference the shared company material (two runtime
   colour parameters) — never baked vertex colour.
4. Any material name outside the palette fails the build (`art validate`).
5. Colour data reaches meshes only as vertex colours; textures are
   exceptional and require justification in review.

## Public interfaces
- Art: `railroad_art` helpers to tag faces with a palette category and to mark
  `[company_colors] primary/secondary` regions per `asset.toml`.
- Runtime: materials are project resources (one vertex-colour material, one
  company material); the company colour parameter is set per-company at
  spawn — one asset renders any livery.

## Implementation rules
- Pick the category that reads at distance, not the "true" object colour:
  e.g. a grey slate roof is `roof_dark`.
- Fake AO is vertex colour: multiply 0.75–0.9 near ground contact, corners,
  and under eaves at generation time; never add a light for it.
- `glass_fake` is opaque; mild emission allowed for night-readability, but no
  alpha. Metal is just `iron`/`steel` vertex colour — no specular workflow.
- Wagon/locomotive liveries: primary body band + secondary trim, so company
  tinting reads on both; declare the regions in `asset.toml`, don't improvise.
- Terrain reuses identical palette values so a `grass` hill matches `grass`
  on an industry's lawn.

## Validation
`python tools/rr.py art validate --all` enumerates material slots: any name
not in the palette fails with the offending name; company regions are checked
to use the company material; opaque-only surfaces contain no alpha inputs.

## Common mistakes
- Assigning raw RGB instead of a palette category.
- Baking the company red into vertex colours (kills livery support).
- Adding a second "wood_barn_red" one-off category before checking the 15.
- Real transparent window material tanking overdraw on the Compatibility
  renderer.

## Related skills
`asset-scale`, `art-style`, `voxel-modeling`, `gltf-export`,
`runtime-rendering`, `asset-validation`.
