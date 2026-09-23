# Design

## Context

See `add-map-economy-sources/proposal.md` for motivation. The world grid, rail graph and `EconomyService` skeleton exist. The clock does not yet emit month boundaries, so this change defines the month-driven hooks the clock will drive. The central correctness hazard is cargo duplication when several stations cover one source.

## Goals / Non-Goals

**Goals:**
- Sources, sinks and stations that a test can drive month-by-month with exact expected quantities.
- Cargo allocation that is provably conserved.
- A shipped map authored as data, reviewable in a diff.

**Non-Goals:**
- No transport, no trains, no revenue — cargo accumulates and waits.
- No town growth, no industry chains beyond coal, no visual city generation.

## Decisions

**Definitions are JSON in `game/data/`, loaded once into immutable definition records.** `TownDef`, `IndustryDef`, `CargoDef` and `StationDef` are parsed by a `DataRegistry` at session start; instances hold only runtime state. Godot `Resource` `.tres` files were rejected because JSON diffs cleanly, is trivially authored by scripts and agents, and matches the specification's own example.

**Industry behaviour is a data-described producer/consumer, not a subclass per industry.** Each definition carries `produces: [{cargo, rate, capacity}]` and `accepts: [{cargo, capacity}]`. A single `IndustryService` steps the lists. Subclasses (`CoalMine`, `PowerPlant`) were rejected because the spec requires iron + coal → steel without touching the cargo system.

**Catchment is computed once per station against a spatial index.** Stations query a uniform grid bucket of source positions; results are cached and invalidated when a station is added or removed. Per-tick distance scans were rejected as O(stations × sources) every tick.

**Rail access is one stored cell, found by rings outward from the footprint.** `find_rail_access` walks `rail_search_radius` rings *outside* the footprint (the shipped class asks for 1: a yard couples to ground beside it), keeps cells that carry rail and — for a depot — a straight run, and scores the survivors by how far they lie off the yard's centre line before ring distance. The winner is saved on the instance as `access_tile`, and both `rail_access_tile()` (simulation) and `rail_access()` (presentation) read it back. The alternative — the original square scan taking the nearest rail within `2 * radius + 3` and never filtering by the radius at all — coupled yards to track two and a half tiles off, and every drawing built on top of that answer came out adrift from the line it served. A consequence worth knowing: a qualifying run must run parallel to a side of the footprint, so a perpendicular stub touching a yard corner can never satisfy a straight-rail station.

**Where a station is drawn is derived from that cell, once.** `EntityRenderer.station_transform()` is a pure static: it puts the model's track-side edge — read out of the built manifest, not guessed — on the access lane, keeps the body inside the ground the footprint claimed, and turns the yard to the run's direction. Billboarding the yard to the camera's fixed 45° yaw was the original behaviour, and it is what made every station look mis-placed: a platform turned across an east-west line is a platform no train can stop at. Because it is static and pure, placement geometry is testable without a scene tree, and the build path and the save-reload path cannot drift.

**Allocation runs per source, per month, and is the only place cargo enters a station.** For each source: gather covering stations, weight by `1 / (distance + 1)`, distribute integer units largest-remainder so the sum equals production exactly, and never emit cargo for an uncovered source. Conservation is asserted directly in a test. Fractional remainders accumulate per source in a float accumulator so long-run totals match declared rates.

**Cargo lives as batches keyed by `(station, cargo_type, origin_key)` in a flat `Array` plus a lookup dictionary.** Aggregation on arrival keeps batch count bounded by source/station pairs rather than by units, satisfying "no one object per passenger".

**Map data is one JSON document per map** containing a compact run-length encoded height/terrain layer plus explicit town, industry and scenery placement lists. RLE keeps the file reviewable while still authoring 65,536 tiles; a binary asset was rejected for diffability. The Founder's Valley document is generated once by a small authored script and then committed as data so it is stable.

**Sources register into the occupancy grid so selection and station coverage share one lookup.** Station coverage reads source positions from `SourceIndex`, not from scene nodes.

## Risks / Trade-offs

- [RLE map authored by script risks looking synthetic] → heights and features are hand-tuned through the generator's parameters, and the several-viable-layouts requirement is checked by a test asserting two disjoint mine-to-plant corridors exist.
- [Allocation weights by distance can make one station useless] → accepted for V1; the spec asks for distance-weighted distribution and the weights are data.
- [Largest-remainder rounding hides bias] → the conservation assertion catches total drift; per-station fairness is left to balancing later.

## Migration Plan

Additive. New data tree and four domain services wired into `GameSession`. Rollback removes them; the rail and world layers are untouched.

## Open Questions

- Whether town buildings are placed as authored scenery or generated around the town centre — presentation-only, resolved in `add-game-shell-and-persistence`.
