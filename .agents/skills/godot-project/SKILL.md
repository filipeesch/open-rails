# godot-project

## Purpose
Owns the Godot project itself: layout of `game/`, project settings, scene
conventions, script organisation, resource/autoloading policy, and how
generated content is consumed.

## When to use
Creating scenes or scripts under `game/`, touching `project.godot`
(input map, rendering, display), wiring `GameSession`, or adding an asset
consumer.

## Non-goals
Simulation rules (per-system skills), UI design law (`ux-principles`),
rendering strategy (`runtime-rendering`), test authoring detail (`testing`).

## Dependencies
- Godot **4.7.2 Standard**, GDScript only, renderer `gl_compatibility`
  (already set; never switch to Forward+ in V1).
- Main scene `res://scenes/Game.tscn`; screens `MainMenu.tscn`,
  `NewSandbox.tscn` under `game/scenes/` behind a `ScreenRoot`.
- Source tree: `game/src/domain/` (simulation), `game/src/presentation/`,
  `game/src/ui/`, `game/src/infrastructure/`; data in `game/data/`;
  generated GLB/manifests in `game/generated/` (build output, never
  hand-edited).
- `tools/rr.py game run | test | check` are the only ways to launch/import.

## Invariants
1. Domain scripts never reference presentation or UI classes; the dependency
   arrow is presentation → domain only. The domain suite runs with no UI.
2. `GameSession` (a plain `Node`) is the composition root, created by
   `Game.tscn` and freed on exit; simulation state never lives in autoloads.
   Application settings may be an autoload.
3. World scale constants come from generated `world_constants.gd`
   (`WorldConstants`); hand-edited literals fail `rr.py check` drift.
4. Input actions are defined in `project.godot` (`cam_pan_*`,
   `cam_rotate_cw/ccw`, `cam_reset`, `focus_selected`, `undo`,
   `command_palette`, `debug_overlay`, `tool_cancel`, `speed_*`) — code uses
   action names, never raw keycodes.
5. `game/generated/` content is consumed via the manifest adapter; no scene
   deep-links into GLB internals.
6. Window stretch is `canvas_items`/`keep` at 1920×1080 design size.

## Public interfaces
- Scene skeleton (Game.tscn): `World3D` {Terrain, Rail, Buildings, Trains,
  Effects, CameraRig}, `UI` {TopBar, BottomToolbar, ContextInspector,
  ToolPanel, Notifications, ModalLayer}, `GameSession`.
- Naming: scripts `snake_case.gd`, classes `PascalCase`, scenes
  `PascalCase.tscn`, signals past-tense (`train_arrived`).
- Class naming for services: `<Family>Service`; definitions `<Kind>Def`.

## Implementation rules
- Keep `.uid` files with their scripts (Godot 4.4+ companion files).
- No logic in `_process` for domain objects; simulation steps from
  `SimulationClock`'s fixed tick (see `simulation-clock`).
- Screens are separate scenes; `GameSession` is never reused across scene
  changes.
- Add third-party add-ons only after review — the project runs without
  vendored dependencies (tests are an in-repo ~200-line runner).
- Project setting changes (input, display, rendering) land with a note in the
  PR referencing the spec section they implement.

## Validation
`python tools/rr.py check` runs a full headless import and fails on any
`SCRIPT ERROR` plus world-constants drift; `python tools/rr.py test` boots
the domain side without a window. Both green before merge.

## Common mistakes
- Making a gameplay Autoload "for convenience" (breaks isolated test
  sessions).
- Switching the renderer to Forward+ to get one effect (spec forbids the
  dependency).
- Editing `game/generated/` files or committing them.
- `preload`ing UI scenes from domain scripts — imports alone break the
  no-UI domain run.

## Related skills
`iso-world`, `runtime-rendering`, `ui-components`, `testing`,
`simulation-clock`, `data-contracts`.
