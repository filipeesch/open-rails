#!/usr/bin/env python3
"""Authors Founder's Valley, the shipped V1 sandbox map.

Run from the repository root:

    python3 tools/mapgen_founders_valley.py

The generator is deterministic — analytic smooth fields, no RNG — so
re-running it reproduces `game/data/maps/founders_valley.json` byte for byte.
The committed JSON is the source of truth afterwards: this script is how a
human re-tunes the valley, not something the game runs.

Design intent (spec §6): the layout deliberately contains several reasonable
railway layouts, and at least two disjoint mine-to-plant corridors exist so a
player is never forced into one answer.

  * heights       smooth ridges and a valley floor, quantised to HEIGHT_STEP
  * water         two lakes, never spanning the map (no bridges in V1)
  * forest        deterministic scatter on mild, moist ground
  * landmarks     2 towns, 2 coal mines, 2 power plants
  * scenery       an authored feature list (see FEATURES): trees, rocks and
                  bushes as data the runtime hashes onto the ground, never as
                  hand-typed coordinates by the thousand
"""

from __future__ import annotations

import json
import math
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT = REPO_ROOT / "game" / "data" / "maps" / "founders_valley.json"

WIDTH = 256
HEIGHT = 256
MAX_STEPS = 12          # heights are whole HEIGHT_STEP multiples
WATER_LEVEL = 1         # tiles at or below this step are water

TERRAIN_PLAIN = "plain"
TERRAIN_GRASS = "grass"
TERRAIN_FOREST = "forest"
TERRAIN_DIRT = "dirt"
TERRAIN_ROCK = "rock"
TERRAIN_WATER = "water"

TOWNS = [
    {
        "id": "town_marlow",
        "name": "Marlow",
        "population": 2400,
        "tile": [70, 152],
        "passengers_per_month": 30,
        "mail_per_month": 9,
    },
    {
        "id": "town_kestrel",
        "name": "Kestrel Brook",
        "population": 1500,
        "tile": [184, 74],
        "passengers_per_month": 18,
        "mail_per_month": 6,
    },
]

TOWNS = [
    {
        "id": "town_marlow",
        "name": "Marlow",
        "population": 2400,
        "tile": [70, 152],
        "passengers_per_month": 30,
        "mail_per_month": 9,
    },
    {
        "id": "town_kestrel",
        "name": "Kestrel Brook",
        "population": 1500,
        "tile": [184, 74],
        "passengers_per_month": 18,
        "mail_per_month": 6,
    },
]

INDUSTRIES = [
    {"id": "mine_west", "def": "coal_mine", "name": "Blackedge Colliery", "tile": [38, 96]},
    {"id": "mine_south", "def": "coal_mine", "name": "Deephilgans Pit", "tile": [146, 206]},
    {"id": "plant_central", "def": "power_plant", "name": "Valley Gate Works", "tile": [124, 118]},
    {"id": "plant_east", "def": "power_plant", "name": "Kestrel Riverside Works", "tile": [209, 162]},
]

# --- scenery ---------------------------------------------------------------
#
# Spec §11 wants trees, rocks and bushes across the valley.  They are authored
# here as a *feature list*, not as terrain: the ground type comes from the
# terrain layer, the scenery that stands on it comes from these rules.
#
#   scatter  one rule per ground type. `density` is the fraction of that ground
#            carrying scenery, `spacing` the lattice pitch that keeps two
#            instances of a rule out of the same spacing x spacing block (so
#            density can never exceed 1/spacing^2 — the loader refuses a rule
#            that asks for more).
#   placed   explicit cells for ground cover that is not a ground cover: the
#            orchard, the hedgerow, the crag.  These override scatter.
#
# `seed` is what makes the woods reproducible.  MapFeatures derives every
# placement from a hash of (seed, tile, rule) — no RNG anywhere — so re-running
# this generator, or booting the game twice, yields the same trees.  Changing
# the seed re-tunes every wood on the map, and the golden scenery counts in
# game/tests/test_scenery_world.gd move with it.
FEATURES = {
    "seed": 90210,
    # A town is settled ground; nothing is planted within this many tiles of a
    # town or industry tile, so the ground beside a platform stays buildable.
    "settlement_clear_radius": 6,
    "scatter": [
        {"terrain": "forest", "scenery": "tree", "density": 0.25, "spacing": 2},
        {"terrain": "rock", "scenery": "rock", "density": 0.10, "spacing": 3},
        {"terrain": "grass", "scenery": "bush", "density": 0.02, "spacing": 3},
        {"terrain": "dirt", "scenery": "bush", "density": 0.01, "spacing": 4},
    ],
    "placed": [
        {"name": "Marlow Orchard", "scenery": "tree", "tiles": [
            [62, 144], [64, 144], [66, 144],
            [62, 146], [64, 146], [66, 146],
            [62, 148], [64, 148], [66, 148],
        ]},
        {"name": "Marlow Hedgerow", "scenery": "bush", "tiles": [
            [62, 142], [64, 142], [66, 142], [68, 142], [70, 142],
            [72, 142], [74, 142], [76, 142], [78, 142],
        ]},
        {"name": "Kestrel Copse", "scenery": "tree", "tiles": [
            [170, 60], [172, 61], [171, 63], [174, 59], [173, 62], [176, 64],
        ]},
        {"name": "Copse Undergrowth", "scenery": "bush", "tiles": [
            [177, 60], [175, 63], [178, 62],
        ]},
        {"name": "The Fangs", "scenery": "rock", "tiles": [
            [28, 5], [31, 4], [36, 6], [29, 10], [34, 11],
            [38, 8], [26, 13], [33, 16], [37, 18], [30, 20],
        ]},
        {"name": "Slough Alders", "scenery": "tree", "tiles": [
            [24, 208], [24, 220], [27, 205], [27, 223], [57, 202], [57, 226],
        ]},
    ],
}


def ridge(x: float, y: float) -> float:
    """A long ridge running north-west to south-east, plus a western escarpment."""
    along = (x + y) / math.sqrt(2.0)
    ridge_line = 150.0 + 42.0 * math.sin(along / 74.0)
    ridge_body = math.exp(-((y - ridge_line) ** 2) / (2.0 * 26.0**2))
    west = math.exp(-((x - 30.0) ** 2) / (2.0 * 22.0**2))
    return 7.0 * ridge_body + 4.5 * west


def hills(x: float, y: float) -> float:
    total = 0.0
    for (cx, cy, amp, spread) in (
        (60.0, 40.0, 3.2, 24.0),
        (200.0, 200.0, 2.6, 30.0),
        (150.0, 30.0, 2.0, 18.0),
        (228.0, 96.0, 2.4, 20.0),
    ):
        total += amp * math.exp(-(((x - cx) ** 2 + (y - cy) ** 2) / (2.0 * spread**2)))
    return total


def moisture(x: float, y: float) -> float:
    return 0.5 + 0.5 * math.sin(x / 61.0) * math.cos(y / 47.0)


def lake(x: float, y: float, cx: float, cy: float, rx: float, ry: float, depth: float) -> float:
    value = 1.0 - ((x - cx) / rx) ** 2 - ((y - cy) / ry) ** 2
    return depth * max(0.0, value)


LAKES = (
    # (centre_x, centre_y, radius_x, radius_y, depth)
    (212.0, 42.0, 26.0, 17.0, 3.4),   # Kestrel Mere, north-east
    (44.0, 214.0, 22.0, 15.0, 3.0),   # Marlow Slough, south-west
    (96.0, 34.0, 9.0, 6.0, 2.4),      # a small tarn to route around
)


def height_field(x: float, y: float) -> float:
    base = 2.2 + ridge(x, y) + hills(x, y)
    base += 0.55 * math.sin(x / 33.0) * math.cos(y / 29.0)
    for lake_spec in LAKES:
        base -= lake(x, y, *lake_spec)
    return max(0.0, base)


def classify(height: float, moist: float, near_town: bool) -> str:
    if height <= WATER_LEVEL:
        return TERRAIN_WATER
    if height >= 10.0:
        return TERRAIN_ROCK
    if near_town:
        return TERRAIN_PLAIN
    if height >= 8.0:
        return TERRAIN_DIRT if moist < 0.45 else TERRAIN_ROCK
    if moist > 0.62:
        return TERRAIN_FOREST
    if moist < 0.30:
        return TERRAIN_DIRT
    return TERRAIN_GRASS if moist > 0.45 else TERRAIN_PLAIN


def near_town_area(x: int, y: int) -> bool:
    for town in TOWNS:
        tx, ty = town["tile"]
        if abs(x - tx) <= 9 and abs(y - ty) <= 9:
            return True
    return False


def quantise(value: float) -> int:
    return max(0, min(MAX_STEPS, int(math.floor(value + 0.5))))


def rle(values: list) -> list:
    out = []
    previous = values[0]
    count = 1
    for value in values[1:]:
        if value == previous:
            count += 1
        else:
            out.append([previous, count])
            previous = value
            count = 1
    out.append([previous, count])
    return out


def build() -> dict:
    heights: list[int] = []
    terrain: list[str] = []
    for y in range(HEIGHT):
        for x in range(WIDTH):
            raw = height_field(float(x), float(y))
            step = quantise(raw)
            kind = classify(float(step), moisture(float(x), float(y)), near_town_area(x, y))
            if kind == TERRAIN_WATER and step > WATER_LEVEL:
                step = WATER_LEVEL
            heights.append(step)
            terrain.append(kind)

    flattened: list[dict] = []
    for spec in INDUSTRIES:
        flattened.append({
            "id": spec["id"],
            "definition": spec["def"],
            "name": spec["name"],
            "tile": spec["tile"],
        })

    return {
        "id": "founders_valley",
        "display_name": "Founder's Valley",
        "width": WIDTH,
        "height": HEIGHT,
        "terrain_names": {
            TERRAIN_PLAIN: "Open plain",
            TERRAIN_GRASS: "Grass",
            TERRAIN_FOREST: "Forest",
            TERRAIN_DIRT: "Dirt",
            TERRAIN_ROCK: "Rock",
            TERRAIN_WATER: "Water",
        },
        "heights": {"encoding": "rle", "run_length": rle(heights)},
        "terrain": {"encoding": "rle", "run_length": rle(terrain)},
        "towns": TOWNS,
        "industries": flattened,
        "features": FEATURES,
        "notes": "Generated by tools/mapgen_founders_valley.py; edit the generator, not this file.",
    }


def main() -> int:
    document = build()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(document, separators=(",", ":")) + "\n")
    water = document["terrain"]["run_length"]
    counts: dict[str, int] = {}
    for name, count in water:
        counts[name] = counts.get(name, 0) + count
    print(f"wrote {OUTPUT.relative_to(REPO_ROOT)} ({OUTPUT.stat().st_size // 1024} KiB)")
    for name in (TERRAIN_PLAIN, TERRAIN_GRASS, TERRAIN_FOREST, TERRAIN_DIRT, TERRAIN_ROCK, TERRAIN_WATER):
        print(f"  {name:<7} {counts.get(name, 0):>6} tiles")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
