# Proposal

## Why

The V1 visual identity — chunky voxel-inspired geometry, vertex colours, shared materials, close-zoom readability — is impossible to maintain if assets are hand-modelled in `.blend` files. The specification makes Blender an offline asset compiler: assets are Python plus metadata, reproducible, cacheable and validated. Without that pipeline the first train, station and tree cannot exist, and every art change would be unreviewable.

## What Changes

- Add `art/railroad_art/`, a Python library of high-level modelling primitives (frames, boilers, wheels, roofs, boxes, props) so asset scripts rarely touch `bpy` directly.
- Add the asset package format `art/assets/<category>/<id>/{asset.py, asset.toml}`; `.blend` files are never canonical sources.
- Add the canonical material palette with vertex-colour-driven shared materials and a company-colour material, enforced at build time.
- Add animation authoring that maps authored Blender actions to the canonical runtime states (`idle`, `moving`, `working`, `loading`, `unloading`) and publishes them as metadata.
- Add `python tools/rr.py art build|validate|preview` with parallel isolated Blender processes, per-job temp directories and logs, atomic publication into `game/generated/`, and an input-hash build cache.
- Add automatic asset validation (scale, origin, materials, triangle budget, animation names, GLB integrity) and 8-angle × 2-zoom preview renders.
- Author the six Milestone-2 assets entirely through the pipeline: tree, house, coal mine, station, steam locomotive, wagon.

## Capabilities

### New Capabilities
- `art-authoring`: How a 3D asset is described — package format, shared scale conventions, the Railroad Art primitive library, material palette, LOD policy and the animation state contract.
- `art-build-and-validation`: How a description becomes a runtime GLB — headless Blender execution, parallel jobs, atomic output, caching, manifest generation, validation checks and preview rendering.

### Modified Capabilities
_(none)_

## Impact

- New Python package `art/railroad_art/` plus `art/assets/**` and `art/config/material_palette.json`.
- New generated output tree `game/generated/models/*.glb` and `game/generated/manifests/*.json` (git-ignored build output, consumed by the runtime).
- Extends `tools/rr.py` with the `art` command group.
- Requires a Blender binary on the machine or via `RR_BLENDER` / `RR_BLENDER_PATH`; no Blender at runtime.
