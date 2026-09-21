# mesh-optimization

## Purpose
Owns geometry efficiency: triangle budgets per asset class, hidden-geometry
removal, vertex duplication, material/surface counts, mesh merging, and
deciding when an object should be instanced instead of unique.

## When to use
When an asset misses its budget, when draw calls grow, or when reviewing a
builder before it merges.

## Non-goals
Visual trade-off calls (`art-style`), LOD authoring (`lod-policy`), runtime
batching strategy (`runtime-rendering`), export mechanics (`gltf-export`).

## Dependencies
- Budgets (spec §27, LOD0 max triangles): prop 500 · tree 800 · house 2,500 ·
  station 8,000 · large industry 10,000 · wagon 4,000 · locomotive 12,000.
  Recorded in `.agents/references/performance-budgets.md`.
- `material-palette` (≤ 2 materials per asset: vertex-colour + company).
- `railroad_art` cleanup helpers run before export.

## Invariants
1. LOD0 triangle count ≤ the class budget, enforced by `art validate`
   (reports actual vs budget).
2. At most 1–2 material slots per asset (vertex-colour + optional
   company); more requires an explicit review decision.
3. One surface per material — no accidental multi-surface splits.
4. No hidden or interior geometry ships: nothing the closest gameplay zoom
   can never see (inside walls, underside stacks, duplicated shells).
5. Repeated static content (scenery, track pieces) is instancing
   candidates — one mesh, drawn by `MultiMeshInstance3D`, not unique assets.

## Public interfaces
No runtime API. The builder-side interface is the cleanup sequence in
`railroad_art` before LOD assembly: remove hidden geometry → merge coplanar
faces → dissolve duplicate/unused vertices → check normals → report triangle
count per LOD.

## Implementation rules
- Optimization priority order (spec §27): remove hidden geometry, remove
  duplicate vertices, merge coplanar faces, avoid unnecessary subdivisions,
  reuse materials, preserve silhouette. Silhouette is the last thing you may
  trade.
- Fix construction, not symptoms: an 8-sided cylinder beats decimating a
  64-sided one.
- Keep wheels/rods as separate small meshes — draw-call cost is bounded,
  animation needs it, and tiny merges that break phase drive are a
  regression.
- Budgets are generous for the style; coming in well under is normal. If you
  must exceed, that's an `lod-policy`+`art-style` review, not a silent edit
  of the validator.
- Measure before optimizing: use preview renders and validate counts, not
  feelings.

## Validation
`python tools/rr.py art validate <id>` reports triangles per LOD against the
budget, material/surface counts, and flags missing-surface errors. Rebuild
(`art build <id> --force`) after cleanup to refresh manifest counts.

## Common mistakes
- Decimating first and wrecking the voxel silhouette (spec: manual LOD for
  important shapes).
- Merging everything into one mesh "to reduce draws" and breaking animation
  nodes or instancing.
- Leaving the bevel modifier unapplied → shading splits double the count.
- Optimizing the LOD0 while LOD1/LOD2 counts stay identical (they're
  separate meshes; check the monotonic decrease).

## Related skills
`lod-policy`, `voxel-modeling`, `asset-validation`, `runtime-rendering`,
`performance`, `gltf-export`.
