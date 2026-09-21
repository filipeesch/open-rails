# Material Palette

Canonical categories from spec §17. Runtime assets never define their own
materials: opaque geometry is one shared vertex-color material; company-color
faces are one shared parameterised material. A material outside this palette
fails `python tools/rr.py art validate`.

## Categories (all 15, spec-mandated)

`grass`, `earth`, `stone`, `brick_red`, `brick_brown`, `roof_red`,
`roof_dark`, `wood_light`, `wood_dark`, `iron`, `steel`, `glass_fake`,
`water`, `company_primary`, `company_secondary`.

## Shared materials

| Material | Purpose |
|---|---|
| Vertex-color material | Every opaque surface in every asset, plus terrain chunks. Color comes from the mesh colour attribute, not from material parameters. |
| Company-colour material | Faces tagged `company_primary` / `company_secondary` in `asset.toml` (`[company_colors]` section); two runtime colour parameters so one asset renders any livery. |
| Water material | Cheap coloured surface + light vertex-shader wobble (the one sanctioned transparent material). |

Windows: use `glass_fake` as a stylized opaque (optionally mildly emissive)
colour. No real transparency, no refraction. Vertex-baked AO is expressed by
darkening vertex colours near junctions (bake at generation time).

## Canonical RGB — project decision

The canonical RGB for each category lives in `art/config/material_palette.json`
(named by the `add-art-pipeline` design; it also lets the runtime reuse the
palette for terrain vertex colours). Until that file lands, propose these
sRGB hex values there — restrained, sun-faded 1850s diorama tones:

| Category | Hex | Notes |
|---|---|---|
| `grass` | `#7FA650` | dominant terrain colour |
| `earth` | `#8A6B4A` | dirt roads, excavation |
| `stone` | `#9A9A92` | ballast, foundations, rocks |
| `brick_red` | `#9C4A3A` | station/industry walls |
| `brick_brown` | `#7C5A42` | alternate walls |
| `roof_red` | `#A8452F` | painted metal roofs |
| `roof_dark` | `#4A4A52` | slate/tar roofs |
| `wood_light` | `#C19A6B` | siding, crates, wagons |
| `wood_dark` | `#6E5138` | trim, ties, beams |
| `iron` | `#5C5F66` | rails, rods, machinery frames |
| `steel` | `#8D949C` | boiler bands, boilers bright parts |
| `glass_fake` | `#CFD8DC` | windows, mild emission ok |
| `water` | `#4F7F9E` | lakes/rivers |
| `company_primary` | `#B8452C` | default company livery (runtime-tintable) |
| `company_secondary` | `#F2E8D5` | default trim/livery (runtime-tintable) |

If `material_palette.json` and this table ever disagree, the JSON wins and
this file must be updated in the same change.

## Rules

1. Asset scripts assign palette categories via `railroad_art` colour helpers,
   never raw RGB and never new materials.
2. Validation rejects any material name not in the palette
   (`art-authoring` spec: "Palette violation blocks the build").
3. Company regions must reference the company material — baking company colours
   into vertex colours makes liveries impossible (rolling-stock spec).
4. Terrain reuses the same palette values through vertex colours on shared
   terrain materials; per-chunk materials are prohibited.
