"""Named validation checks for generated assets — host-side, no Blender.

Every check is a small pure function returning `Failure` items (each carrying
its own check name) or None, so `art validate` output is directly actionable
(art-build spec: "validation failure SHALL ... identify the specific check
that failed").  Checks run both on staged output before publication and over
`game/generated/` afterwards.

Units: manifest footprint/attachments are tile units, z-up (authoring space);
the GLB is glTF Y-up.  Horizontal axes map glTF +X -> local +X and glTF +Z ->
local ±Y; vertical: glTF +Y == local +Z.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from . import art_assets, art_glb

SCALE_TOLERANCE = 0.05           # ±5% footprint (art-authoring spec)
ORIGIN_XY_TOLERANCE = 0.10       # fraction of footprint extent the centre may drift
ORIGIN_Z_MIN = -0.05             # tile units below ground allowed (never buried)
ORIGIN_Z_MAX = 0.30              # rolling stock rides on the rail head

MANIFEST_REQUIRED_KEYS = ("schema", "id", "type", "lod_class", "footprint",
                          "lod_triangles", "materials", "attachments",
                          "animation_states", "cache_key", "build_timestamp")


@dataclass
class Failure:
    check: str
    asset_id: str
    message: str

    def __str__(self) -> str:
        return f"[{self.check}] {self.asset_id}: {self.message}"


# --------------------------------------------------------------------------- entry


def run_checks(repo_root: Path, meta: art_assets.AssetMeta,
               base_dir: Path | None = None) -> list[Failure]:
    """Run every check against one asset's generated output.  `base_dir`
    defaults to `game/generated/`; the build orchestrator passes the staging
    directory to validate before publication."""
    base = Path(base_dir) if base_dir else repo_root / "game" / "generated"
    glb_path = base / "models" / f"{meta.id}.glb"
    manifest_path = base / "manifests" / f"{meta.id}.json"

    failures: list[Failure] = []
    failure = _check_glb_present(meta, glb_path)
    if failure:
        return [failure]
    try:
        glb = art_glb.Glb.load(str(glb_path))
    except art_glb.GlbError as exc:
        return [Failure("glb-present", meta.id, str(exc))]

    failure = _check_manifest(meta, manifest_path)
    if failure:
        return [failure] if isinstance(failure, Failure) else list(failure)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    for check in (
        lambda: _check_manifest_model(meta, manifest, base),
        lambda: _check_manifest_lod_data(meta, manifest, glb),
        lambda: _check_scale(meta, manifest, glb, repo_root),
        lambda: _check_origin(meta, manifest, glb),
        lambda: _check_palette(meta, manifest, glb, repo_root),
        lambda: _check_tri_budget(meta, manifest, glb),
        lambda: _check_lod_monotonic(meta, manifest, glb),
        lambda: _check_animations(meta, manifest, glb),
    ):
        result = check()
        if result:
            failures.extend(result if isinstance(result, list) else [result])
    return failures


# --------------------------------------------------------------------------- checks


def _check_glb_present(meta, glb_path: Path) -> Failure | None:
    if not glb_path.is_file():
        return Failure("glb-present", meta.id,
                       f"missing model file {glb_path} — run `rr.py art build {meta.id}`")
    return None


def _check_manifest(meta, manifest_path: Path) -> list[Failure] | Failure | None:
    if not manifest_path.is_file():
        return Failure("manifest-integrity", meta.id, f"missing manifest {manifest_path}")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return Failure("manifest-integrity", meta.id, f"manifest is not valid JSON: {exc}")
    if not isinstance(manifest, dict):
        return Failure("manifest-integrity", meta.id, "manifest root is not a JSON object")
    missing = [k for k in MANIFEST_REQUIRED_KEYS if k not in manifest]
    if missing:
        return Failure("manifest-integrity", meta.id,
                       f"manifest missing required keys: {', '.join(missing)}")
    if manifest.get("id") != meta.id:
        return Failure("manifest-integrity", meta.id,
                       f"manifest id '{manifest.get('id')}' != package id '{meta.id}'")
    states = manifest.get("animation_states")
    if not isinstance(states, dict):
        return Failure("animation-states", meta.id, "animation_states is not an object")
    unknown = sorted(set(states) - set(art_assets.CANONICAL_STATES))
    if unknown:
        return Failure("animation-states", meta.id,
                       f"manifest maps non-canonical states {unknown}; "
                       f"permitted: {', '.join(art_assets.CANONICAL_STATES)}")
    return None


def _check_manifest_model(meta, manifest, base: Path) -> Failure | None:
    model = manifest.get("model")
    if not model:
        return Failure("manifest-integrity", meta.id, "manifest has no 'model' path")
    if not (base / str(model)).is_file():
        return Failure("manifest-integrity", meta.id,
                       f"manifest references model '{model}' which does not exist "
                       f"under {base}")
    return None


def _check_manifest_lod_data(meta, manifest, glb) -> list[Failure]:
    failures: list[Failure] = []
    declared = manifest.get("lod_triangles") or {}
    for level, count in sorted(declared.items()):
        actual = glb.subtree_triangles(str(level))
        if actual is None:
            failures.append(Failure("lod-presence", meta.id,
                                    f"manifest declares {level} but the GLB has no such node"))
        elif actual != count:
            failures.append(Failure("manifest-integrity", meta.id,
                                    f"manifest {level} triangle count {count} "
                                    f"!= GLB count {actual}"))
    materials_declared = sorted(manifest.get("materials") or [])
    materials_actual = glb.all_material_names_used()
    if materials_declared != materials_actual:
        failures.append(Failure("manifest-integrity", meta.id,
                                f"manifest materials {materials_declared} != "
                                f"GLB materials {materials_actual}"))
    return failures


def _check_scale(meta, manifest, glb, repo_root) -> Failure | None:
    tile = float(art_assets.world(repo_root).get("tile_size", 1.0))
    bounds = glb.subtree_bounds("LOD0")
    if bounds is None:
        return Failure("lod-presence", meta.id, "no LOD0 node in GLB")
    (x0, _y0, z0), (x1, _y1, z1) = bounds
    extent_x = (x1 - x0) / tile          # local +X (length)
    extent_y = (z1 - z0) / tile          # local +Y magnitude (glTF Z after Y-up)
    declared = manifest.get("footprint") or list(meta.footprint)
    measured = [round(extent_x, 4), round(extent_y, 4)]
    for i, (want, got) in enumerate(zip(declared, measured)):
        tol = SCALE_TOLERANCE * max(abs(want), 1e-6)
        if abs(got - want) > tol:
            axis = "length (local +X)" if i == 0 else "width (local +Y)"
            return Failure("scale-footprint", meta.id,
                           f"{axis}: measured {got} tiles vs declared {want} tiles "
                           f"(tolerance ±{SCALE_TOLERANCE:.0%})")
    return None


def _check_origin(meta, manifest, glb) -> Failure | None:
    bounds = glb.subtree_bounds("LOD0")
    if bounds is None:
        return Failure("lod-presence", meta.id, "no LOD0 node in GLB")
    (x0, y0, z0), (x1, _y1, z1) = bounds
    tile = float(((manifest.get("world") or {}).get("tile_size")) or 1.0)
    cx = (x0 + x1) / 2 / tile
    cz = (z0 + z1) / 2 / tile
    zmin = y0 / tile                     # glTF +Y == local +Z
    declared = manifest.get("footprint") or list(meta.footprint)
    for axis, centre, extent in (("X", cx, declared[0]), ("Y", cz, declared[1])):
        if abs(centre) > ORIGIN_XY_TOLERANCE * max(abs(extent), 1e-6):
            return Failure("origin", meta.id,
                           f"geometry centre offset on {axis}: measured {centre:+.3f} "
                           f"tiles (allowed ±{ORIGIN_XY_TOLERANCE * abs(extent):.3f})")
    if not (ORIGIN_Z_MIN <= zmin <= ORIGIN_Z_MAX):
        return Failure("origin", meta.id,
                       f"geometry bottom at z={zmin:+.3f} tiles; assets must sit on "
                       f"the ground plane (allowed [{ORIGIN_Z_MIN:+.2f}, "
                       f"{ORIGIN_Z_MAX:+.2f}] tile units)")
    return None


def _check_palette(meta, manifest, glb, repo_root) -> Failure | None:
    allowed = art_assets.allowed_material_names(repo_root)
    used = glb.all_material_names_used()
    bad = sorted(set(used) - allowed)
    if bad:
        return Failure("palette-materials", meta.id,
                       f"material(s) outside the canonical palette: {', '.join(bad)} "
                       f"(allowed: {', '.join(sorted(allowed))})")
    if not used:
        return Failure("palette-materials", meta.id, "GLB references no materials at all")
    company_used = {m for m in used if m.startswith("company_")}
    expected = {f"company_{r}" for r in (manifest.get("company_regions") or {})}
    if expected != company_used:
        return Failure("palette-materials", meta.id,
                       f"company material usage {sorted(company_used)} does not match "
                       f"declared regions {sorted(expected)}")
    return None


def _check_tri_budget(meta, manifest, glb) -> list[Failure] | None:
    lod_class = manifest.get("lod_class", meta.lod_class)
    budget = art_assets.TRIANGLE_BUDGETS.get(str(lod_class))
    if budget is None:
        return [Failure("triangle-budget", meta.id,
                        f"unknown lod_class '{lod_class}' "
                        f"(known: {', '.join(sorted(art_assets.TRIANGLE_BUDGETS))})")]
    failures = []
    for level in sorted((manifest.get("lod_triangles") or {})):
        count = glb.subtree_triangles(level)
        if count is None:
            continue                     # reported by lod-presence already
        if count > budget:
            failures.append(Failure("triangle-budget", meta.id,
                                    f"{level} of lod_class '{lod_class}' has {count} "
                                    f"triangles, over the budget of {budget}"))
    return failures or None


def _check_lod_monotonic(meta, manifest, glb) -> Failure | None:
    levels: list[tuple[str, int]] = []
    for name in ("LOD0", "LOD1", "LOD2"):
        count = glb.subtree_triangles(name)
        if count is not None:
            levels.append((name, count))
    if not levels or levels[0][0] != "LOD0":
        return Failure("lod-presence", meta.id, "asset has no LOD0 node")
    expected_levels = len(manifest.get("lod_triangles") or {})
    if len(levels) < expected_levels:
        return Failure("lod-presence", meta.id,
                       f"manifest declares {expected_levels} LOD levels, GLB provides "
                       f"{[n for n, _ in levels]}")
    for (na, ca), (nb, cb) in zip(levels, levels[1:]):
        if cb >= ca:
            return Failure("lod-monotonic", meta.id,
                           f"{nb} ({cb} tris) is not strictly smaller than "
                           f"{na} ({ca} tris)")
    return None


def _check_animations(meta, manifest, glb) -> list[Failure] | None:
    states = manifest.get("animation_states") or {}
    required = set(manifest.get("required_states") or []) | set(meta.required_states)
    glb_anims = set(glb.animation_names())
    problems: list[str] = []
    for state, action in sorted(states.items()):
        if state not in art_assets.CANONICAL_STATES:
            problems.append(f"state '{state}' is not canonical "
                            f"(permitted: {', '.join(art_assets.CANONICAL_STATES)})")
            continue
        if action is None:
            continue
        if action not in glb_anims:
            problems.append(f"state '{state}' maps to action '{action}' which the GLB "
                            f"does not contain (animations: "
                            f"{sorted(glb_anims) or 'none'})")
    for state in sorted(required):
        if not states.get(state):
            problems.append(f"asset requires state '{state}' but manifest maps it to null")
    return [Failure("animation-states", meta.id, p) for p in problems] or None
