# build-mode-ux

## Purpose
Owns the construction interaction layer: build mode entry/exit, the left
tool palette, cursor states, ghost geometry, live validity/cost previews and
the explained-failure feedback that rides on top of any build tool.

## When to use
Working on Build/Stations tools, ghost rendering, tool palettes, preview
data binding, or Escape-flow behaviour.

## Non-goals
What a valid rail placement *is* (`rail-network` / `rail-builder`),
station coverage math (`station-system`), money (`economy`), generic
widgets (`ui-components`).

## Dependencies
- `iso-world` for the pointer tile + ground elevation (ghosts hug terrain).
- Tool backends: `RailBuilderTool`, station placement in `StationService`.
- `ux-principles` law (preview before commit; explain failures).
- Input: `tool_cancel` (Escape), Shift precision modifier.

## Invariants
1. `Build` opens the left tool palette: **Rail, Station, Remove** — and
   changes the cursor state visibly.
2. Escape cancels the current operation; a second Escape exits build mode.
   Escape never both.
3. Every construction shows a ghost with cost + validity before commit;
   valid = confirm builds & charges; invalid = confirm does nothing and
   charges nothing.
4. Invalid feedback appears adjacent to the cursor with colour + icon +
   text naming the specific reason.
5. Rail preview colours: green valid, yellow valid-but-expensive, red
   invalid; station ghosts additionally draw the catchment ring, footprint,
   required alignment, covered sources and estimated monthly cargo.
6. Tools own **no** validity or pricing logic — they bind previews to
   service answers (`can_connect`, `can_place`, costs from data).

## Public interfaces
`BuildModeController`:
- `enter()`, `exit()`, `select_tool(id)`, `cancel_operation() -> bool`
  (tool had an op) `else exit`
- ghost layer API: `show_ghost(asset_or_mask, tile)`,
  `set_validity(valid, reason)`, `set_highlight_ring(catchment)`
- preview data contract: `{cost, valid, reason, extra...}` produced by the
  active tool each pointer-tile change.

## Implementation rules
- Recompute previews only on pointer-tile change (backend caches by
  cursor+revision; the controller just rebinds labels).
- Ghost height samples `terrain_height_at(tile)`; ghosts on slopes follow
  the surface, never sit at y=0.
- Shift = precision single-tile placement for rail; keep it discoverable
  via the tool palette hint text.
- Removal preview highlights exactly what will disappear and shows the
  dependent-station refusal path verbatim from the service reason.
- Cursor states are distinct icons (build/remove/erase), never colour-only
  distinctions.

## Validation
Manual: enter Build → Rail drag → green/yellow/red transitions while
dragging across a hill and river; Escape twice leaves build mode; invalid
station ghost beside a curve reads "Requires straight rail"; confirm on
invalid costs $0. Automated: tool controller unit tests for escape
two-stage and validity binding (service stubbed).

## Common mistakes
- Computing "can I build here?" inside the tool (diverges from rules).
- Ghost floating over hills (no height sampling).
- Escape closing the whole palette mid-drag (wrong stage order).
- Preview re-running A* every frame instead of per tile change.

## Related skills
`rail-builder`, `station-system`, `iso-world`, `ux-principles`,
`ui-components`, `input-navigation`, `economy`.
