# asset-validation

## Purpose
Owns the automated checks that stop a bad asset from reaching the game:
scale, origin, materials, triangle counts, animation names, GLB/manifest
integrity, missing geometry, and the preview renders reviewers judge.

## When to use
After every asset build, before merging art changes, and as the failing
signal when `art build --all` reports issues. Debugging a specific check
failure.

## Non-goals
Making the asset good (`art-style`, `voxel-modeling`); fixing export
mechanics (`gltf-export`); Godot-side import issues (`godot-project`).

## Dependencies
- `python tools/rr.py art validate <id>|--all` — headless, pure-Python checks
  over the produced GLB + manifest (no Blender spawn needed for discovery).
- `python tools/rr.py art preview <id>` — 8 horizontal angles at 45°
  increments (0/45/…/315°) × close and normal zoom = 16 images in
  `build/previews/<id>/`.
- Expected failures list (spec §108): Blender errors, missing GLB, invalid
  material, incorrect scale, excess triangle count, missing required
  animation, incorrect origin, broken manifest.

## Invariants
1. An asset that fails any check cannot reach the game: validation runs in
   the job's staging dir **before** atomic publication.
2. Every check is a named pure function; its failure message names the check
   and the measured value (directly actionable output).
3. Previews are review artefacts only — no runtime path may reference
   `build/previews/`.
4. Checks are deterministic over the same GLB+manifest (pure functions).
5. `art validate --all` exits 0 iff every discovered asset passes; a missing
   or unparseable manifest for any asset fails the run.

## Public interfaces
Checklist (each fails loudly with a name): footprint/scale (5% tolerance vs
`asset.toml`), origin/ground-contact, palette material whitelist, per-LOD
triangle budgets, canonical animation-state mapping ⊆ {idle, moving,
working, loading, unloading} and GLB actions resolvable, LOD naming +
monotonic counts, attachment-point coordinates present, GLB integrity
(non-empty, parseable), no accidental internal geometry, no clipping.

## Implementation rules
- Read the failure message first — it names the check and measurement; don't
  re-run blindly with `--force`.
- Scale failures usually mean the builder ignored world.toml — fix
  `asset-scale` usage, not the tolerance.
- New check needed? Add a pure function + expected value to this skill and
  the validator together; validation logic is documentation.
- Treat preview angles as a rotation test: if 135°/315° look wrong, geometry
  is wrong — never "fix" a single angle.
- Keep previews opt-in per asset (they're slow and excluded from
  `art build --all`).

## Validation
Meta: deliberately break an asset (move origin, exceed budget) and confirm
`art validate <id>` fails naming that exact check, then restore and confirm
`art validate --all` is green.

## Common mistakes
- Shipping assets built before a palette/budget change (stale cache — use
  `--force` after config edits).
- Judging only close zoom previews; check both zoom bands.
- Loosening a tolerance instead of fixing the asset.
- Reviewing only one of the 16 preview images.

## Related skills
`gltf-export`, `mesh-optimization`, `lod-policy`, `material-palette`,
`asset-scale`, `blender-headless`, `art-style`.
