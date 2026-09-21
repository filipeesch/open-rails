# Design

## Context

See `add-rail-construction/proposal.md` for motivation. The world grid, chunked rendering and selection exist from `add-world-and-camera`; `EconomyService` does not yet and is introduced here. Trains are not implemented, so the graph must be built correctly now without any train-side pressure to shortcut it.

## Goals / Non-Goals

**Goals:**
- A rail model expressive enough for 8-direction track and junctions, derived from per-cell data rather than maintained twice.
- Drag construction that feels like drawing a line, with the planner doing the work.
- Undo that is financially honest.

**Non-Goals:**
- No signals, no block reservation, no two-way/siding semantics, no bridges or tunnels.
- No train pathfinding reuse yet, though the query is written to serve it unchanged.

## Decisions

**Connections are a 4-bit-per-axis-free octant mask.** One byte per cell in `WorldGrid.rail`, bits `N, NE, E, SE, S, SW, W, NW`. The graph is derived: neighbours are computed from the mask, never stored. Two parallel representations were rejected because they drift. Straight-vs-diagonal cost is folded into the A* edge weight (diagonal moves cost √2, turns add a penalty) instead of separate track "types".

**`RailService` owns validity, `RailNetwork` owns data.** A single `can_connect(cell, dir) -> Reason` is the only validity authority; the planner, the tool and future bridges all call it, so a reason string never has to be reconstructed from a boolean. Errors are an enum with a `message()` mapping, which keeps the UI honest about "requires straight rail" style feedback.

**Planner is A\* over the walkable tile lattice, not only over existing rail.** Nodes are tiles; edges are the 8 directions with cost = base terrain cost + slope penalty + turn penalty − reuse bonus on cells already carrying rail. This lets the same query serve "connect to my existing network" and future train pathing. A Dijkstra-on-rail-graph-only planner was rejected because construction must plan across unbuilt terrain.

**Preview is computed on pointer-tile change, not every frame.** The result is cached against `(start, goal, network revision)` so dragging over the same tile is free; the expensive path runs at most once per tile change. This also satisfies "do not pathfind every tick".

**Undo is command objects holding an inverse plus a ledger reversal.** `UndoService` stores `{apply(), invert()}` pairs and calls `EconomyService.refund(transaction_id)`. Replaying the world forward was rejected as non-deterministic in the presence of trains, so undo is limited to the construction actions the spec lists and any action that a later change made unsafe is dropped from the stack.

**Track pieces are selected by mask lookup.** A 256-entry piece table indexed by the connection byte plus a slope variant index; unknown masks fall back to straight-and-isolated rather than crashing. Pieces are instanced into per-chunk `MultiMeshInstance3D`s, one per piece type, rebuilt only for dirty chunks. Per-tile `Node3D` track was rejected by the runtime rules.

**`EconomyService` starts minimal here** (cash, spend, refund, ledger, insufficient-funds reason) and is extended by `add-trains-routes-and-revenue` with monthly accounting. Introducing it as a stub with the real contract avoids a later rewrite of every caller.

## Risks / Trade-offs

- [Turn penalties make the planner's tie-breaking surprising] → expose weights in data and cover the documented preferences with unit tests (fewer turns wins at equal length).
- [Undo interacting with cargo already generated] → undo scope is deliberately restricted to build/remove rail and station build; anything semantically entangled is removed from the stack, per spec.
- [Diagonal rail complicates station alignment rules] → alignment validity is asked of `RailService`, so station placement inherits one definition instead of inventing its own.

## Migration Plan

Additive: new domain services plus a rail tool panel. Rollback removes the tool and `rail/` code; `WorldGrid.rail` stays as an unused array.

## Open Questions

- Yellow "valid but expensive" threshold: expressed as a multiple of the cheapest possible route, pinned in data during implementation.
