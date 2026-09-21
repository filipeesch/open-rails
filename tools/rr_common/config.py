"""Reads the canonical world configuration shared by art and runtime."""

from __future__ import annotations

import tomllib
from pathlib import Path
from typing import Any

CONFIG_RELATIVE = Path("art") / "config" / "world.toml"


class ConfigError(RuntimeError):
    pass


def config_path(repo_root: Path) -> Path:
    return repo_root / CONFIG_RELATIVE


def load(repo_root: Path) -> dict[str, Any]:
    path = config_path(repo_root)
    if not path.exists():
        raise ConfigError(f"missing world configuration at {path}")
    with path.open("rb") as handle:
        try:
            return tomllib.load(handle)
        except tomllib.TOMLDecodeError as exc:  # pragma: no cover - authored file
            raise ConfigError(f"{path}: {exc}") from exc


def world(repo_root: Path) -> dict[str, Any]:
    data = load(repo_root)
    if "world" not in data:
        raise ConfigError(f"{config_path(repo_root)}: missing [world] table")
    return data["world"]


def section(repo_root: Path, name: str) -> dict[str, Any]:
    data = load(repo_root)
    return data.get(name, {})
