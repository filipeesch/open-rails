"""Locating and launching the Godot and Blender toolchains."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

GODOT_ENV = "RR_GODOT"
BLENDER_ENV = "RR_BLENDER"

GODOT_CANDIDATES = (
    "godot",
    "godot4",
    "Godot",
)
GODOT_APP_CANDIDATES = (
    "~/Applications/Godot.app/Contents/MacOS/Godot",
    "/Applications/Godot.app/Contents/MacOS/Godot",
    "~/Applications/Godot.app/Contents/MacOS/Godot",
)
BLENDER_CANDIDATES = (
    "blender",
    "/Applications/Blender.app/Contents/MacOS/Blender",
    "~/Applications/Blender.app/Contents/MacOS/Blender",
)

DOWNLOAD_HINT = (
    "Download Godot 4.7.2-stable from "
    "https://github.com/godotengine/godot/releases/tag/4.7.2-stable "
    "or export RR_GODOT=/path/to/Godot"
)


class ToolchainNotFound(RuntimeError):
    pass


@dataclass
class CommandResult:
    code: int
    stdout: str
    stderr: str


def _which(name: str) -> str | None:
    found = shutil.which(name)
    return found


def _candidate_paths(explicit: str | None, env_var: str, candidates: tuple[str, ...]) -> list[str]:
    out: list[str] = []
    if explicit:
        out.append(explicit)
    env_value = os.environ.get(env_var)
    if env_value:
        out.append(env_value)
    local = Path("~/.rr/toolchain.json").expanduser()
    if local.exists():
        try:
            import json

            data = json.loads(local.read_text())
            key = "godot" if env_var == GODOT_ENV else "blender"
            if isinstance(data, dict) and data.get(key):
                out.append(str(data[key]))
        except Exception:  # pragma: no cover - best effort only
            pass
    out.extend(candidates)
    resolved: list[str] = []
    for entry in out:
        if not entry:
            continue
        resolved.append(str(Path(entry).expanduser()))
    return resolved


def _explicit_is_broken(explicit: str | None, env_var: str) -> str | None:
    """An override the user named on purpose must not fail quietly.

    Falling back to the search path after `--godot /nope/Godot` would run a
    different engine than the one that was asked for, and report success.
    """
    flag = "godot" if env_var == GODOT_ENV else "blender"
    for source, value in ((f"--{flag}", explicit), (env_var, os.environ.get(env_var))):
        if not value:
            continue
        path = Path(value).expanduser()
        if path.exists():
            return None
        return (
            f"{source} points at '{value}', which does not exist.\n"
            f"  resolved to: {path}\n"
            "  Unset it to fall back to the search path."
        )
    return None


def find_godot(explicit: str | None = None) -> str:
    broken = _explicit_is_broken(explicit, GODOT_ENV)
    if broken:
        raise ToolchainNotFound(broken)
    tried: list[str] = []
    for candidate in _candidate_paths(explicit, GODOT_ENV, GODOT_CANDIDATES):
        tried.append(candidate)
        path = Path(candidate)
        if path.is_absolute():
            if path.exists():
                return str(path)
            continue
        found = _which(candidate)
        if found:
            return found
    for candidate in GODOT_APP_CANDIDATES:
        path = Path(candidate).expanduser()
        tried.append(str(path))
        if path.exists():
            return str(path)
    raise ToolchainNotFound(
        "Godot not found.\n"
        f"  environment variable: {GODOT_ENV}\n"
        f"  searched: {', '.join(dict.fromkeys(tried))}\n"
        f"  {DOWNLOAD_HINT}"
    )


def find_blender(explicit: str | None = None) -> str:
    broken = _explicit_is_broken(explicit, BLENDER_ENV)
    if broken:
        raise ToolchainNotFound(broken)
    tried: list[str] = []
    for candidate in _candidate_paths(explicit, BLENDER_ENV, BLENDER_CANDIDATES):
        tried.append(candidate)
        path = Path(candidate)
        if path.is_absolute():
            if path.exists():
                return str(path)
            continue
        found = _which(candidate)
        if found:
            return found
    raise ToolchainNotFound(
        "Blender not found.\n"
        f"  environment variable: {BLENDER_ENV}\n"
        f"  searched: {', '.join(dict.fromkeys(tried))}\n"
        "  Install Blender 4.5 LTS or later, or export "
        "RR_BLENDER=/path/to/blender"
    )


def version_of(executable: str) -> str:
    try:
        result = subprocess.run(
            [executable, "--version"], capture_output=True, text=True, timeout=60, check=False
        )
    except (OSError, subprocess.TimeoutExpired):
        return "unknown"
    text = (result.stdout or result.stderr or "").strip().splitlines()
    return text[0] if text else "unknown"


def run(
    executable: str,
    argv: list[str],
    cwd: Path | None = None,
    stream: bool = False,
    capture: bool = False,
    env: dict[str, str] | None = None,
    timeout: float | None = None,
) -> CommandResult:
    """Launch a tool.  Returns exit code plus captured output when requested."""
    merged_env = dict(os.environ)
    if env:
        merged_env.update(env)
    if stream:
        completed = subprocess.run(
            [executable, *argv], cwd=str(cwd) if cwd else None, env=merged_env,
            capture_output=True, text=True, timeout=timeout, check=False,
        )
        if completed.stdout:
            print(completed.stdout, end="" if completed.stdout.endswith("\n") else "\n")
        if completed.stderr:
            print(completed.stderr, end="" if completed.stderr.endswith("\n") else "\n", file=sys.stderr)
        return CommandResult(completed.returncode, completed.stdout or "", completed.stderr or "")
    completed = subprocess.run(
        [executable, *argv], cwd=str(cwd) if cwd else None, env=merged_env,
        capture_output=True, text=True, timeout=timeout, check=False,
    )
    return CommandResult(completed.returncode, completed.stdout or "", completed.stderr or "")


import sys  # noqa: E402  (imported late to keep module import side-effect free)
