# UI Layout

Concrete layout facts from spec §56–§73 and the `game-shell-ui` spec delta.

## Screens and shell

- Scenes under a `ScreenRoot`: `MainMenu.tscn`, `NewSandbox.tscn`,
  `Game.tscn` (main scene, `game/scenes/Game.tscn`). `GameSession` is created
  by `Game.tscn` and destroyed on exit (design decision — no persistent
  autoload for simulation state).
- Main menu entries: Continue, New Sandbox, Load Game, Settings, Quit.
  Continue is disabled when no autosave exists.
- New Sandbox: map = Founder's Valley, company name text field, starting year
  1850, Start button. Blank name → generated default name.

## In-game composition (Game.tscn)

```
Game
├── World3D (Terrain, Rail, Buildings, Trains, Effects, CameraRig)
├── UI (TopBar, BottomToolbar, ContextInspector, ToolPanel, Notifications, ModalLayer)
└── GameSession
```

The map occupies almost the entire screen. No large permanent sidebars.

- **TopBar (permanent):** `Jan 1850   $428,320   +$12,430/mo   ⏸ 1× 2× 4×`
  — date, cash, monthly profit, speed controls. Speed keys (implemented in
  `game/project.godot`): Space = pause, `1` = 1×, `2` = 2×, `3` = 4×.
- **BottomToolbar (permanent):** `[Build] [Stations] [Trains] [Company] [World]`.
- **ContextInspector:** right side, appears only when something is selected.
  Train view: name/model, speed, cargo `Coal 24/40`, route stop list, this
  month's revenue, actions `[Edit consist] [Route] [Follow]`. Station view:
  coverage list, waiting cargo per type, this month's revenue,
  `[Routes] [Rename]`. Industry view: production/month, stored, transported
  %, served-by.
- **ToolPanel (left):** only during tool operations. Build palette = Rail,
  Station, Remove. Escape cancels the current operation; a second Escape
  exits build mode.
- **Notifications:** small, non-blocking, dismissible (insufficient funds,
  unreachable destination, industry storage full, "Game saved"). Errors on a
  selected object also appear in its inspector. Avoid modal alerts in normal
  play; `ModalLayer` is reserved for genuinely modal things (save dialog).

## Cross-cutting rules

- `Ctrl+K` command palette: searches stations, trains, towns, industries;
  runs commands (Build rail, New train, Save game, Finance). Selecting an
  entity focuses the camera **through the camera system** — UI never writes
  camera transforms.
- Hover tooltips are lightweight (e.g. `Train #12 / Coal 31/40 / 54 km/h`),
  produced by the same pointer→entity path as selection; hover never replaces
  selection.
- Zoom-dependent labels: far = town names + major industries; medium = towns,
  stations, industries; close = only selected entities. Labels live in one
  pooled `Control` layer with projected positions, not `Label3D` per entity.
- Invalid build feedback combines **colour + icon + text** — never colour
  only; names the specific reason ("Requires straight rail", not "Invalid
  placement").
- UI reads state via service queries + domain events (`money_changed`,
  `month_changed`, `train_arrived`, …); simulation never calls UI. Panels
  refresh on a 0.1 s throttle, not per signal (design decision).

## Scaling and resolutions

- UI scale: 100 / 125 / 150 / 175 / 200 %, applied via
  `content_scale_factor`; takes effect without restart.
- Minimum supported resolution 1280×720; primary design resolution
  1920×1080. Window stretch is `canvas_items`/`keep` (already in
  `project.godot`).
- Icons are SVG where practical (resolution-independent); 3D world objects
  stay 3D — SVG is never used for buildings or trains.
- Visual tone: modern but restrained — clear typography, few strong colours,
  soft panels, subtle shadows, consistent spacing, dense but uncluttered;
  not a mobile dashboard; all panels share one Godot `Theme` resource.

## Settings exposed (spec §114)

Master/music/effects volume, resolution, fullscreen, UI scale, camera pan /
rotation / zoom speeds, edge scrolling. Persisted in `user://settings.cfg`
via `ConfigFile`.
