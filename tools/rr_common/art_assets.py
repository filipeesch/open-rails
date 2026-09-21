"""Asset discovery and palette loading — host-side, pure stdlib, never imports bpy.

This module is what `tools/rr_art.py` uses to scan `art/assets/` without ever
importing an asset's `asset.py` and without ever talking to Blender.  The
railroad_art library itself lives inside Blender and is *not* importable here.

Package layout:  art/assets/<category>/<id>/{asset.py, asset.toml}

`asset.toml` is self-describing: id, type, footprint (tile units), lod_class,
plus optional [animation] / [company_colors] / [lod] sections.
"""

from __future__ import annotations

import hashlib
import json
import tomllib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

ASSETS_RELATIVE = Path("art") / "assets"
PALETTE_RELATIVE = Path("art") / "config" / "material_palette.json"
WORLD_RELATIVE = Path("art") / "config" / "world.toml"
LIBRARY_RELATIVE = Path("art") / "railroad_art"

#: Canonical runtime animation states (art-authoring spec).  An asset manifest
#: maps each of these to a concrete authored action name, or null.
CANONICAL_STATES = ("idle", "moving", "working", "loading", "unloading")

#: LOD0 triangle budgets per lod class, from the performance-budgets reference.
TRIANGLE_BUDGETS = {
    "small_prop": 500,
    "tree": 800,
    "house": 2500,
    "station": 8000,
    "large_industry": 10000,
    "wagon": 4000,
    "locomotive": 12000,
}


class AssetSourceError(RuntimeError):
    """The asset source tree violates the package contract."""


@dataclass
class AssetMeta:
    """Parsed, trusted metadata for one asset package."""

    id: str
    category: str
    path: Path
    type: str
    footprint: tuple[float, float]
    lod_class: str
    height: float | None
    required_states: list[str] = field(default_factory=list)
    company_regions: list[str] = field(default_factory=list)
    lod_levels: int = 3
    lod_auto: bool = True
    raw: dict[str, Any] = field(default_factory=dict)

    @property
    def asset_py(self) -> Path:
        return self.path / "asset.py"

    @property
    def asset_toml(self) -> Path:
        return self.path / "asset.toml"


# --------------------------------------------------------------------------- world scale


def world(repo_root: Path) -> dict:
    """The [world] table of art/config/world.toml.  tile_size is 1.0, so
    footprint/height numbers in asset.toml and manifests are tile units that
    equal metres in the exported GLB."""
    path = repo_root / WORLD_RELATIVE
    if not path.is_file():
        raise AssetSourceError(f"missing world config at {path}")
    try:
        with path.open("rb") as handle:
            data = tomllib.load(handle)
    except tomllib.TOMLDecodeError as exc:
        raise AssetSourceError(f"{path}: {exc}") from exc
    return data.get("world", {})


# --------------------------------------------------------------------------- palette


def palette_path(repo_root: Path) -> Path:
    return repo_root / PALETTE_RELATIVE


def load_palette(repo_root: Path) -> dict[str, Any]:
    path = palette_path(repo_root)
    if not path.exists():
        raise AssetSourceError(f"missing material palette at {path}")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise AssetSourceError(f"{path}: invalid JSON: {exc}") from exc
    if "categories" not in data or "materials" not in data:
        raise AssetSourceError(f"{path}: palette must define 'categories' and 'materials'")
    return data


def palette_category_names(repo_root: Path) -> list[str]:
    return sorted(load_palette(repo_root)["categories"])


def allowed_material_names(repo_root: Path) -> set[str]:
    """Material names legally present in a generated GLB.

    The shared vertex-colour material, the water material, and every export
    name of the parameterised company material are allowed; nothing else.
    """
    palette = load_palette(repo_root)
    allowed = set()
    for name, spec in palette["materials"].items():
        allowed.add(name)
        exports = spec.get("export_names") or {}
        allowed.update(exports.values())
    return allowed


def palette_hex_to_linear(hex_str: str) -> tuple[float, float, float]:
    """Convert sRGB `#rrggbb` to linear-light RGB (Blender stores linear)."""
    h = hex_str.lstrip("#")
    r, g, b = (int(h[i : i + 2], 16) / 255.0 for i in (0, 2, 4))

    def to_linear(c: float) -> float:
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return (to_linear(r), to_linear(g), to_linear(b))


# --------------------------------------------------------------------------- discovery


def assets_root(repo_root: Path) -> Path:
    return repo_root / ASSETS_RELATIVE


def _assert_no_blend_files(root: Path) -> None:
    """`.blend` files are never canonical sources — presence is a named error."""
    offenders = sorted(p for p in root.rglob("*") if p.is_file() and p.suffix.lower() == ".blend")
    if offenders:
        joined = ", ".join(str(p) for p in offenders)
        raise AssetSourceError(
            ".blend files are not canonical sources; delete or move to a "
            f"disposable directory: {joined}"
        )


def _parse_meta(pkg: Path, category: str) -> AssetMeta:
    toml_path = pkg / "asset.toml"
    with toml_path.open("rb") as handle:
        try:
            data = tomllib.load(handle)
        except tomllib.TOMLDecodeError as exc:
            raise AssetSourceError(f"{toml_path}: {exc}") from exc

    missing = [k for k in ("id", "type", "footprint", "lod_class") if k not in data]
    if missing:
        raise AssetSourceError(f"{toml_path}: missing required key(s): {', '.join(missing)}")
    fp = data["footprint"]
    if not isinstance(fp, (list, tuple)) or len(fp) != 2:
        raise AssetSourceError(f"{toml_path}: footprint must be two numbers [length, width] in tile units")

    anim = data.get("animation", {}) or {}
    company = data.get("company_colors", {}) or {}
    lod = data.get("lod", {}) or {}
    return AssetMeta(
        id=str(data["id"]),
        category=category,
        path=pkg,
        type=str(data["type"]),
        footprint=(float(fp[0]), float(fp[1])),
        lod_class=str(data["lod_class"]),
        height=float(data["height"]) if "height" in data else None,
        required_states=[str(s) for s in (anim.get("required_states") or [])],
        company_regions=[str(r) for r in (company.get("regions") or [])],
        lod_levels=int(lod.get("levels", 3)),
        lod_auto=bool(lod.get("auto", True)),
        raw=data,
    )


def discover_assets(repo_root: Path) -> list[AssetMeta]:
    """Scan art/assets/ for asset packages, reading only asset.toml.

    Raises AssetSourceError on a planted .blend, a missing asset.py, or a
    malformed asset.toml — never imports builder code.
    """
    root = assets_root(repo_root)
    if not root.is_dir():
        return []
    _assert_no_blend_files(root)
    found: list[AssetMeta] = []
    seen: dict[str, Path] = {}
    for toml_path in sorted(root.rglob("asset.toml")):
        pkg = toml_path.parent
        rel = pkg.relative_to(root)
        if len(rel.parts) != 2:
            raise AssetSourceError(
                f"{pkg}: asset packages must live at art/assets/<category>/<id>/ (found depth {len(rel.parts)})"
            )
        if not (pkg / "asset.py").is_file():
            raise AssetSourceError(f"{pkg}: asset package is missing asset.py")
        meta = _parse_meta(pkg, rel.parts[0])
        if meta.id != pkg.name:
            raise AssetSourceError(f"{toml_path}: id '{meta.id}' must match folder name '{pkg.name}'")
        if meta.id in seen:
            raise AssetSourceError(f"duplicate asset id '{meta.id}' in {seen[meta.id]} and {pkg}")
        seen[meta.id] = pkg
        if meta.lod_class not in TRIANGLE_BUDGETS:
            raise AssetSourceError(
                f"{toml_path}: unknown lod_class '{meta.lod_class}' (allowed: {', '.join(sorted(TRIANGLE_BUDGETS))})"
            )
        for state in meta.required_states:
            if state not in CANONICAL_STATES:
                raise AssetSourceError(
                    f"{toml_path}: required state '{state}' is not canonical (allowed: {', '.join(CANONICAL_STATES)})"
                )
        found.append(meta)
    return found


def find_asset(repo_root: Path, asset_id: str) -> AssetMeta:
    for meta in discover_assets(repo_root):
        if meta.id == asset_id:
            return meta
    raise AssetSourceError(f"no asset with id '{asset_id}' under {assets_root(repo_root)}")


# --------------------------------------------------------------------------- cache key


def _hash_file(digest: "hashlib._Hash", path: Path) -> None:
    digest.update(str(path.name).encode("utf-8"))
    digest.update(b"\0")
    digest.update(path.read_bytes())
    digest.update(b"\0")


def hash_library(repo_root: Path) -> str:
    """sha256 over the whole railroad_art source tree (content, not mtime)."""
    lib = repo_root / LIBRARY_RELATIVE
    digest = hashlib.sha256()
    if not lib.is_dir():
        raise AssetSourceError(f"missing railroad_art library at {lib}")
    for path in sorted(p for p in lib.rglob("*") if p.is_file() and "__pycache__" not in p.parts):
        digest.update(str(path.relative_to(lib)).encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def asset_cache_key(
    repo_root: Path,
    meta: AssetMeta,
    library_hash: str,
    blender_version: str,
    library_version: str,
) -> str:
    """Content hash: asset.py + asset.toml + whole library tree + palette +
    world.toml + blender version + library version (design.md 'Cache key')."""
    digest = hashlib.sha256()
    _hash_file(digest, meta.asset_py)
    _hash_file(digest, meta.asset_toml)
    digest.update(("lib-tree:" + library_hash + "\0").encode("utf-8"))
    _hash_file(digest, palette_path(repo_root))
    _hash_file(digest, repo_root / WORLD_RELATIVE)
    digest.update(("blender:" + blender_version + "\0").encode("utf-8"))
    digest.update(("railroad_art:" + library_version + "\0").encode("utf-8"))
    return digest.hexdigest()
