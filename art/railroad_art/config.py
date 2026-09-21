"""Reads `art/config/` — the canonical palette and world scale.

Pure stdlib (json + tomllib); safe to import inside Blender's Python. The host
orchestrator has its own equivalent in `tools/rr_common/art_assets.py`; the
two files share one source of truth on disk, so they cannot drift silently.
"""

from __future__ import annotations

import json
import tomllib
from pathlib import Path


class ConfigError(RuntimeError):
    pass


def srgb_hex_to_linear(hex_str: str) -> tuple[float, float, float]:
    """sRGB `#rrggbb` → linear-light float RGB (Blender's working space)."""
    h = hex_str.lstrip("#")
    r, g, b = (int(h[i : i + 2], 16) / 255.0 for i in (0, 2, 4))

    def to_linear(c: float) -> float:
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return (to_linear(r), to_linear(g), to_linear(b))


class Palette:
    """Canonical material palette with linear-RGB lookup by category name."""

    def __init__(self, data: dict, path: Path):
        self.path = path
        self.data = data
        self.categories: dict[str, dict] = data["categories"]
        self.materials: dict[str, dict] = data["materials"]
        self._linear: dict[str, tuple] = {}
        self._resolve_company = self.materials["company_colour"]  # parameterised material

    @classmethod
    def load(cls, path: Path) -> "Palette":
        if not path.is_file():
            raise ConfigError(f"missing material palette at {path}")
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise ConfigError(f"{path}: invalid JSON: {exc}") from exc
        for key in ("categories", "materials"):
            if key not in data:
                raise ConfigError(f"{path}: palette must define '{key}'")
        return cls(data, path)

    def colour(self, category: str) -> tuple[float, float, float]:
        """Linear-light RGB for a palette category name."""
        cached = self._linear.get(category)
        if cached is not None:
            return cached
        entry = self.categories.get(category)
        if entry is None:
            raise ConfigError(
                f"{self.path}: colour category '{category}' is not in the palette "
                f"(allowed: {', '.join(sorted(self.categories))})"
            )
        value = srgb_hex_to_linear(entry["hex"])
        self._linear[category] = value
        return value

    def company_export_name(self, region: str) -> str:
        """GLB material name for a company livery region."""
        exports = self._resolve_company.get("export_names") or {}
        if region not in exports:
            raise ConfigError(
                f"{self.path}: company region '{region}' has no export name "
                f"(allowed: {', '.join(sorted(exports))})"
            )
        return exports[region]

    def company_category(self, region: str) -> str:
        params = self._resolve_company.get("params") or {}
        if region not in params:
            raise ConfigError(f"{self.path}: company region '{region}' is not a palette parameter")
        return params[region]

    @property
    def vertex_colour_material(self) -> str:
        return "vertex_colour"

    @property
    def water_material(self) -> str:
        return "water"


def load_world(path: Path) -> dict:
    """Parsed `world.toml` as a dict (the whole document)."""
    if not path.is_file():
        raise ConfigError(f"missing world configuration at {path}")
    with path.open("rb") as handle:
        try:
            return tomllib.load(handle)
        except tomllib.TOMLDecodeError as exc:
            raise ConfigError(f"{path}: {exc}") from exc


class WorldScale:
    """Tile-space scale conventions read from world.toml — never hard-coded."""

    def __init__(self, data: dict):
        world = data.get("world") or {}
        for key in ("tile_size", "height_step"):
            if key not in world:
                raise ConfigError(f"world.toml [world] is missing '{key}'")
        self.tile_size = float(world["tile_size"])
        self.height_step = float(world["height_step"])
        self.camera = data.get("camera") or {}

    def tiles(self, n: float) -> float:
        """Convert a measurement expressed in tile units to Blender metres."""
        return n * self.tile_size
