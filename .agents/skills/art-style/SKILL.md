# art-style

## Purpose
Owns the visual identity: voxel-inspired proportions, shape language, detail
density, silhouette, 1850s historical stylization, and the overall "playable
miniature railway diorama" appearance.

## When to use
When authoring or reviewing any asset, when deciding how much detail a part
deserves, or when something "looks wrong" but passes validation.

## Non-goals
Hard numbers — scale lives in `asset-scale`, colours in `material-palette`,
budgets in `mesh-optimization`. Runtime look (lighting, renderer) is owned by
`visual-style` reference + `runtime-rendering`.

## Dependencies
- `.agents/references/visual-style.md` (principles consolidated).
- `asset-scale`, `material-palette`, `voxel-modeling` skills.
- `art/railroad_art/` primitives (the style is partly enforced by the
  library: chunky boxes, beveled edges, low-poly cylinders).

## Invariants
1. If detail cannot be seen at the closest gameplay zoom (≈4 tiles on
   screen), it does not exist.
2. Silhouettes carry the design: a recognisable 4-4-0, gable-roof houses,
   headframe mine — readable at LOD2, from all 8 preview angles.
3. Every surface colour comes from the shared palette; no bespoke RGB, no
   textures except sanctioned exceptions.
4. Geometry reads as *built from chunks*: boxes, beveled boxes, simple
   cylinders — not organic, not photoreal.
5. Assets look correct under the fixed 35.264° pitch from every 45° snap;
   rotation reveals valid geometry from every side.

## Public interfaces
No code API. The interface is the review ritual: `python tools/rr.py art
preview <id>` produces 8 angles × 2 zooms in `build/previews/<id>/` — judge
style there, not in a viewport screenshot from one angle.

## Implementation rules
- Build big shapes first; verify the silhouette at far preview zoom before
  adding any detail.
- Prefer 2–3 stacked readable boxes over one complex mesh; small bevels
  (≈0.01–0.02 units) catch the light, big bevels read as blobs.
- Use palette value contrast for readability (dark `roof_dark` on light
  `wood_light` walls); reserve `company_primary`/`company_secondary` for
  rolling stock and station trim only.
- Bake fake-AO into vertex colours (darker near ground contact and inside
  corners) instead of adding lights or maps.
- Historic references: 1850s American wood/brick/iron; no plastics, no
  painted signage detail too small to read, no modern materials.

## Validation
Style review is human, over the full 16-image preview grid, plus: a fresh
asset next to existing assets at default zoom (28 tiles) must not look
"from another game". `art validate` proves legality, never style.

## Common mistakes
- Adding micro-detail "for realism" that dies at normal zoom (spec §20 avoid
  list: photorealism, micro-detail, tiny geometry).
- Rounding everything with heavy bevels/subsurf until the voxel language is
  lost — round *where period-accurate* (boilers, wheels), keep boxes boxy.
- Colouring with raw RGB in the asset script "temporarily".
- Judging an asset from one angle only; 45° curves and rod work hide bugs.

## Related skills
`asset-scale`, `material-palette`, `voxel-modeling`, `mesh-optimization`,
`asset-validation`, `lod-policy`.
