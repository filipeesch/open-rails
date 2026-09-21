# lod-policy

## Purpose
Owns the LOD system for assets and animation: which levels exist, what each
level must preserve, automatic vs manual generation, distance thresholds, and
how LOD selection is driven at runtime.

## When to use
When building any substantial asset, when LOD2 "loses" the asset's identity,
or when wiring distance-based selection in presentation.

## Non-goals
Triangle budgets themselves (`mesh-optimization`), GLB packing mechanics
(`gltf-export`), particle effect tiers (`runtime-effects`).

## Dependencies
- Three conceptual levels: **LOD0** close inspection (preserves detail),
  **LOD1** normal gameplay (major geometry), **LOD2** distant overview
  (silhouette + colour primarily).
- Levels export as sibling nodes `LOD0`/`LOD1`/`LOD2`; manifest records
  per-level counts (must decrease monotonically).
- Runtime proxy: camera orthographic size is the single distance metric;
  per-train distance bucketing drives animation rate
  (`add-game-shell-and-persistence` design).

## Invariants
1. Every substantial asset ships LOD0+LOD1+LOD2; small props may ship one or
   two levels (prop/tree classes).
2. LOD2 always preserves the readable silhouette and palette colours — a
  station's roofline and a locomotive's boiler profile are never auto-decimated
  away.
3. Counts strictly decrease LOD0 → LOD1 → LOD2 and each level respects its
   class budget (validate-enforced).
4. LOD selection never changes gameplay state; it is presentation-only and
   may be replaced (Godot import LODs vs explicit selection) without domain
   changes — the manifest carries all data either way.
5. Animation LOD tiers track the same distance proxy: near = full mechanics
   + effects; medium = mechanics, reduced effect rate; far = reduced update
   frequency, no particles; offscreen = visuals suspended, simulation
   continues.

## Public interfaces
- Builder: `railroad_art` LOD assembly — `auto_lod()` (decimate-based
  starting point) plus manual LOD primitives for important shapes; the
  export step names nodes `LOD0..2`.
- Runtime: presentation reads `manifest.triangles` / LOD node names;
  CameraRig's orthographic size (4–96 tiles) maps to tiers.

## Implementation rules
- Choose per class: props/trees 1–2 levels; houses/stations/industries/
  rolling stock 3 levels.
- Try auto-reduce first for bulk geometry; hand-author LOD2 whenever auto
  damages the voxel silhouette (spec explicitly requires manual there).
- LOD2 is usually the blockout the builder made first — keep it as a real
  step in the script rather than a decimation afterthought.
- Animated parts exist only in LOD0/LOD1; LOD2 is static (far trains don't
  need rod geometry).
- Thresholds are tuning data (project decision): LOD0 under ~10 visible
  tiles, LOD1 to ~40 tiles, LOD2 beyond — pinned as data alongside camera
  zoom, tuned against `stress` runs.

## Validation
`python tools/rr.py art validate <id>`: three named LOD meshes for
substantial classes, monotonic counts, per-level budgets. `art preview
<id>` at close vs normal zoom shows both visible tiers; stress world shows
the far tier in bulk.

## Common mistakes
- Auto-decimating the entire asset for LOD2 and losing the chimney/roof read.
- Making LOD2 a copy of LOD0 (validate flags non-monotonic counts).
- Driving LOD by per-entity distance queries every frame instead of the
  camera size proxy + bucketing.
- Forgetting that company-coloured faces must survive into LOD2 too.

## Related skills
`mesh-optimization`, `gltf-export`, `runtime-rendering`,
`animation-authoring`, `asset-validation`, `performance`.
