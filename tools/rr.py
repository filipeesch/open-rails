#!/usr/bin/env python3
"""Development CLI for Open Rails.

One entry point for everything a human or an agent needs to do in this
repository.  Stdlib only: the CLI must run on a bare interpreter.

    python tools/rr.py game run
    python tools/rr.py test
    python tools/rr.py art build steam_440
    python tools/rr.py art build --all --jobs 3
    python tools/rr.py art validate --all
    python tools/rr.py art preview steam_440
    python tools/rr.py check
    python tools/rr.py stress
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
GAME_DIR = REPO_ROOT / "game"
ART_DIR = REPO_ROOT / "art"
TOOLS_DIR = REPO_ROOT / "tools"

sys.path.insert(0, str(TOOLS_DIR))

from rr_common import config  # noqa: E402
from rr_common import toolchain  # noqa: E402
from rr_common import worldgen_constants  # noqa: E402


def cmd_constants(args: argparse.Namespace) -> int:
    """Generate runtime world constants from art/config/world.toml."""
    if args.diff:
        return worldgen_constants.check(REPO_ROOT)
    return worldgen_constants.generate(REPO_ROOT)


def cmd_game_run(args: argparse.Namespace) -> int:
    godot = toolchain.find_godot(args.godot)
    extra = args.godot_args.split() if args.godot_args else []
    return toolchain.run(godot, ["--path", str(GAME_DIR)] + extra, cwd=GAME_DIR, stream=True).code


def cmd_test(args: argparse.Namespace) -> int:
    godot = toolchain.find_godot(args.godot)
    worldgen_constants.check(REPO_ROOT)
    argv = ["--headless", "--path", str(GAME_DIR), "--script", "res://tests/runner.gd"]
    if args.filter:
        argv += ["--", f"--filter={args.filter}"]
    result = toolchain.run(godot, argv, cwd=GAME_DIR, stream=True)
    return _report_script_errors(result, "test")


def _report_script_errors(result: toolchain.CommandResult, label: str) -> int:
    """Fail a run the engine raised script errors in, whatever it printed.

    Godot reports a script error on stderr and keeps going: the test runner never
    sees it, so a case that aborts halfway still reports the assertions it
    reached before the abort, and the suite prints PASS.  A green suite that
    stopped checking things mid-case is not green, and a stress run that threw
    while simulating is not a measurement.
    """
    seen: list[str] = []
    for line in (result.stdout + "\n" + result.stderr).splitlines():
        if "SCRIPT ERROR" in line:
            text = line.strip()
            if text not in seen:
                seen.append(text)
    if seen:
        print(f"{label}: FAIL  {len(seen)} distinct script error(s) raised while it ran")
        for text in seen[:12]:
            print(f"    {text}")
        if len(seen) > 12:
            print(f"    ... and {len(seen) - 12} more")
        return 1
    return result.code


# The rail height is fixed twice, in two languages: the renderer draws the rail
# head at `RIDE_HEIGHT` and the art compiler rests every compiled wheel at
# `RIDE_HEIGHT_TILES`.  No test reads both numbers — the simulation only ever
# consults the constant in its own module — so a drift between them is exactly
# the invisible "train floats over the rail" bug.  `rr.py check` is the pin.
# The values are read with a regex, never imported: conventions.py is Blender-
# only code and `check` stays stdlib-only.
_RIDE_HEIGHT_SOURCES = (
    (
        Path("game") / "src" / "presentation" / "track_pieces.gd",
        "RIDE_HEIGHT",
        r"^const\s+RIDE_HEIGHT\s*(?::[^=\n]*)?=\s*([-+0-9.eE]+)",
    ),
    (
        Path("art") / "railroad_art" / "conventions.py",
        "RIDE_HEIGHT_TILES",
        r"^RIDE_HEIGHT_TILES\s*(?::[^=\n]*)?=\s*([-+0-9.eE]+)",
    ),
)


def _check_rail_ride_height() -> str | None:
    """Return a failure line when the two rail-height authorities disagree."""
    found: list[tuple[str, str]] = []
    for rel, name, pattern in _RIDE_HEIGHT_SOURCES:
        try:
            text = (REPO_ROOT / rel).read_text(encoding="utf-8")
        except OSError:
            text = ""
        match = re.search(pattern, text, re.MULTILINE)
        if match is None:
            return (
                f"{rel} no longer declares {name}; `rr.py check` pins the two "
                "rail-height constants together and cannot read that side"
            )
        found.append((str(rel), match.group(1)))
    (gd_rel, gd_raw), (py_rel, py_raw) = found
    gd_val, py_val = float(gd_raw), float(py_raw)
    if gd_val == py_val:
        print(f"check: rail ride height agrees: RIDE_HEIGHT == RIDE_HEIGHT_TILES == {gd_raw}")
        return None
    bigger = f"{gd_rel} RIDE_HEIGHT" if gd_val > py_val else f"{py_rel} RIDE_HEIGHT_TILES"
    return (
        f"rail ride height mismatch: {gd_rel} RIDE_HEIGHT = {gd_raw} but "
        f"{py_rel} RIDE_HEIGHT_TILES = {py_raw}; {bigger} is the higher value — "
        "compiled wheels would rest above or below the drawn rail head"
    )


def cmd_check(args: argparse.Namespace) -> int:
    """Import every runtime script and verify shared conventions."""
    godot = toolchain.find_godot(args.godot)
    failures: list[str] = []

    drift = worldgen_constants.check(REPO_ROOT)
    if drift != 0:
        failures.append("world constants drifted from art/config/world.toml")

    ride = _check_rail_ride_height()
    if ride is not None:
        failures.append(ride)

    rc = toolchain.run(godot, ["--headless", "--path", str(GAME_DIR), "--import"], cwd=GAME_DIR, capture=True)
    if rc.code != 0:
        failures.append("project import failed")
    if "Can't load script" in rc.stdout + rc.stderr:
        failures.append("Godot could not load a script referenced by the project")
    rc = toolchain.run(godot, ["--headless", "--path", str(GAME_DIR), "--script", "res://tests/check_scripts.gd"], cwd=GAME_DIR, stream=True)
    if rc.code != 0:
        failures.append("runtime script import reported errors")
    if "Can't load script" in rc.stdout + rc.stderr:
        failures.append("a check target script is missing or unreadable")

    if failures:
        for line in failures:
            print(f"check: FAIL  {line}", file=sys.stderr)
        return 1
    print("check: OK")
    return 0


def cmd_art(args: argparse.Namespace) -> int:
    from rr_art import main as art_main  # imported late: optional Blender dependency

    return art_main(args)


def cmd_stress(args: argparse.Namespace) -> int:
    godot = toolchain.find_godot(args.godot)
    argv = ["--headless", "--path", str(GAME_DIR), "--script", "res://tests/stress_world.gd", "--", f"--ticks={args.ticks}"]
    result = toolchain.run(godot, argv, cwd=GAME_DIR, stream=True)
    return _report_script_errors(result, "stress")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="rr.py",
        description="Open Rails development CLI: the same commands humans and agents use.",
    )
    parser.add_argument("--godot", help="explicit path to the Godot executable")
    sub = parser.add_subparsers(dest="command", required=True)

    p_const = sub.add_parser("constants", help="generate/check runtime world constants")
    p_const.add_argument("--diff", action="store_true", help="report drift without writing")
    p_const.set_defaults(func=cmd_constants)

    p_game = sub.add_parser("game", help="run the game")
    pg = p_game.add_subparsers(dest="game_command", required=True)
    p_run = pg.add_parser("run", help="launch the main scene")
    p_run.add_argument("--godot-args", help="extra arguments forwarded to Godot")
    p_run.set_defaults(func=cmd_game_run)

    p_test = sub.add_parser("test", help="run the headless simulation test suite")
    p_test.add_argument("--filter", help="only run test files whose path contains this text")
    p_test.set_defaults(func=cmd_test)

    p_check = sub.add_parser("check", help="import all scripts and verify shared conventions")
    p_check.set_defaults(func=cmd_check)

    p_art = sub.add_parser("art", help="build, validate and preview 3D assets")
    p_art.add_argument("art_command", choices=["build", "validate", "preview", "list"])
    p_art.add_argument("asset", nargs="?", help="asset id, omit with --all")
    p_art.add_argument("--all", action="store_true", help="apply to every discovered asset")
    p_art.add_argument("--jobs", type=int, default=3, help="parallel Blender processes")
    p_art.add_argument("--blender", help="explicit path to the Blender executable")
    p_art.add_argument("--force", action="store_true", help="ignore the build cache")
    p_art.add_argument("--keep-temp", action="store_true", help="keep job temp directories")
    p_art.set_defaults(func=cmd_art)

    p_stress = sub.add_parser("stress", help="run the synthetic stress world headless")
    p_stress.add_argument("--ticks", type=int, default=2000, help="simulation ticks to run")
    p_stress.set_defaults(func=cmd_stress)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.func(args))
    except toolchain.ToolchainNotFound as exc:
        print(f"rr.py: {exc}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
