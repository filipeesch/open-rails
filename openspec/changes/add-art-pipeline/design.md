# Design

## Context

See `add-art-pipeline/proposal.md` for motivation. Constraints: Blender must never be required at runtime; assets are Python plus TOML; the installed Blender is 5.2 LTS while the specification names 4.5 LTS, so the library must stay on stable `bpy` APIs and record the version it built with. Godot consumes `.glb` from `game/generated/`, which is build output, not source.

## Goals / Non-Goals

**Goals:**
- One asset = one folder = two files, reproducible from a clean checkout.
- Build time that scales: unchanged assets cost nothing.
- Validation strict enough that a bad asset cannot reach the game.

**Non-Goals:**
- No interactive editor tooling, no UV workflow, no texture pipeline (textures are exceptional by design).
- No runtime LOD switching logic here — that is `runtime-performance` in a later change.

## Decisions

**`railroad_art` runs only inside Blender's Python.** `art/railroad_art/` imports `bpy` at module scope; it is never imported by `tools/rr.py` in the host interpreter. The orchestrator imports a pure-Python `manifest`/`metadata` module instead. This keeps `art validate` fast and lets discovery work without spawning Blender. Alternative considered: a shim `bpy` stub for host-side dry runs — rejected as a maintenance trap.

**Blender is driven by a generated script, not a saved `.blend`.** Each build writes a throwaway runner script into the job's temp directory that adds `art/` to `sys.path`, imports the asset module, calls `build(context)` and exports. This keeps `.blend` files out of the picture entirely and makes the executed code reviewable in the log.

**Vertex colour is the material strategy.** One shared material reading a colour attribute, plus a company-colour material with two runtime parameters. Palette membership is validated against `art/config/material_palette.json`, which also stores the canonical RGB for each category so the runtime can reuse the palette for terrain. Alternative: per-asset materials with baked diffuse — rejected for draw-call and memory cost, and because company tinting needs a parameterised material anyway.

**LOD levels are separate named nodes.** `LOD0`, `LOD1`, `LOD2` as sibling objects in the exported GLB; Godot imports them as a `Mesh` with custom LODs or selects by node name. Chosen over Decimate-based auto-LOD alone because automatic reduction damages voxel silhouettes; the library offers auto-reduce as a starting point and manual LOD primitives for anything important.

**Cache key is content, not mtime.** `sha256(asset.py) + sha256(asset.toml) + sha256(railroad_art package tree) + sha256(palette + world config) + blender version + library version`. Storing the Railroad Art tree hash means a shared-primitive edit invalidates every dependent asset, which is correct and cheap. The key is stored inside the generated manifest; a build compares before launching Blender.

**Atomic publication via staging directory.** The job writes into `<temp>/out/`, is validated there, then files are moved into `game/generated/` with `os.replace` per file after a per-asset lock file prevents concurrent writes to the same id. Parallelism is a `ThreadPoolExecutor` of subprocess launches — processes are the isolation unit, threads only supervise.

**Validation is a checklist of pure functions** over the produced GLB and manifest, each named in its failure message, so `art validate` output is directly actionable. Preview renders reuse the same Blender invocation with an orthographic camera at 45° increments.

## Risks / Trade-offs

- [Blender 5.2 API differs from the 4.5 LTS the spec names] → confine all `bpy` usage to a small `railroad_art.blender_util` façade, record `blender_version` in every manifest, and build the six assets early in the milestone so breakage surfaces immediately.
- [Parallel Blender processes contend for CPU and thrash the cache] → default `--jobs` to `min(3, cpu_count // 2)` and keep the documented default of 3 in examples.
- [GLB import settings in Godot vary] → the runtime consumes manifests, not raw GLB structure, so import-time surprises stay behind one adapter.
- [Preview renders are slow] → previews are opt-in per asset and excluded from `art build --all`.

## Migration Plan

Purely additive. Rollback is deleting `art/`, `game/generated/` and the `art` subcommand group; nothing else depends on them until `add-trains-routes-and-revenue`.

## Open Questions

- Whether Godot's importer or an explicit `SceneTree`-side LOD selection is cheaper at runtime — deferred to `runtime-performance`; the manifest records all LOD data either way.
