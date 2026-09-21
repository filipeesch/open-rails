# gltf-export

## Purpose
Owns the contract between the Blender build and Godot: GLB export settings,
axis/transform conventions, mesh and node naming, animation export, and the
generated manifest written alongside each model.

## When to use
When adding or changing anything the exporter produces — node names, LOD
packing, attachment points — or when Godot consumes generated models
unexpectedly.

## Non-goals
Geometry quality (`voxel-modeling`), palette membership (`material-palette`),
Godot-side scene assembly (`runtime-rendering`), validation rules themselves
(`asset-validation`).

## Dependencies
- Output paths: `game/generated/models/<id>.glb` +
  `game/generated/manifests/<id>.json`. Previews (`build/previews/`) are
  review artefacts and never referenced by the runtime.
- `asset.toml` metadata (`id`, `type`, `footprint`, `lod_class`,
  `[animation]`, `[company_colors]`) feeds the manifest.
- `railroad_art` export step (driven by `python tools/rr.py art build <id>`).

## Invariants
1. Runtime format is `.glb` only (no `.gltf`/`.fbx` in `game/generated/`).
2. Y-up world orientation, transforms applied (no unapplied scale/rotation
   on exported meshes), origins per `asset-scale` (ground contact, Z-up base
   at 0 in authoring space).
3. LOD meshes are sibling nodes named exactly `LOD0`/`LOD1`/`LOD2`; the
   manifest records triangle counts per level.
4. Animation names in the GLB match the manifest's canonical-state mapping
   1:1; nothing references Blender-internal datablock names.
5. The manifest is authoritative: id, type, lod_class, footprint, per-LOD
   triangle counts, materials used, attachment points, animation map. The
   runtime consumes manifests, never raw GLB structure guesses.
6. Build publication is atomic: manifest and GLB appear together or not at
   all (`os.replace` from staging).

## Public interfaces
- Manifest JSON shape (excerpt):

```json
{
  "id": "steam_440",
  "type": "locomotive",
  "lod_class": "vehicle",
  "footprint": [1.0, 0.45],
  "triangles": {"LOD0": 11200, "LOD1": 3100, "LOD2": 700},
  "materials": ["vertex_color", "company_color"],
  "attachments": {"chimney_smoke": [0.31, 0.0, 0.52]},
  "animations": {"idle": null, "moving": "Move"}
}
```

- Godot loads `res://generated/models/<id>.glb` through an adapter that
  reads the manifest; attachment points become named markers for effects
  and wagon coupling presentation.

## Implementation rules
- Export selection per job from the staging dir only; never export from the
  user's Blender scene.
- Apply transforms on export; freeze everything at authored scale.
- Keep node names stable and semantic (`LOD0`, `wheel_driving_L`,
  `coupler_front`) — runtime and validation match on them.
- Do not export lights, cameras, or scene collections.
- Vertex colour attribute must be exported with the mesh (point domain);
  Godot imports it for the shared material.

## Validation
`python tools/rr.py art validate <id>`: manifest exists, parses, GLB exists
and is non-truncated, names referenced in manifest resolve in the GLB, LOD
counts decrease monotonically. `art validate --all` gates the whole set.

## Common mistakes
- Hand-editing a GLB in `game/generated/` (it's build output; the next build
  overwrites it).
- Changing an action name in Blender without updating the manifest mapping.
- Letting `LOD0` become a bare copy of the scene collection with lights.
- Assuming Godot importer defaults — the manifest adapter is the boundary;
  surprises stay behind it.

## Related skills
`asset-validation`, `lod-policy`, `material-palette`, `animation-authoring`,
`blender-headless`, `runtime-rendering`.
