# Proposal

## Why

The simulation can already play itself, but a player cannot. The specification's definition of V1 complete is an onboarding path — launch, start a sandbox, build, watch, earn, save, quit, load, continue — performed "with no developer intervention", and its quality bar demands polished camera feel, clear previews, self-explanatory errors and reliable saves. Milestones 8–10 close that gap and prove the architecture survives scale.

## What Changes

- Add the game shell: main menu (Continue/New Sandbox/Load Game/Settings/Quit), the New Sandbox screen, the permanent top bar (date, cash, monthly profit, speed controls) and bottom toolbar (Build, Stations, Trains, Company, World).
- Add the context inspector for trains, stations, industries and towns, hover tooltips, zoom-dependent map labels, non-blocking notifications and `Ctrl+K` search/command palette.
- Add build mode with the left tool palette (Rail, Station, Remove), ghost previews, and the two-stage Escape back-out.
- Add train follow mode and double-click/F focus integration.
- Add settings (audio, resolution, fullscreen, UI scale, camera speeds, edge scrolling) and UI scaling from 100 % to 200 % down to a 1280 × 720 minimum.
- Add versioned save/load with manual save, load, autosave and atomic write-then-validate-then-rename publication.
- Add LOD and animation LOD tiers, MultiMesh scenery, track chunk batching, the `F3` debug overlay and the synthetic stress world used to detect scalability failure.
- Add minimal spatial audio for UI, construction, locomotive movement, whistle, arrival and ambient world.

## Capabilities

### New Capabilities
- `game-shell-ui`: Menus, HUD, inspectors, tools, palette, labels, notifications, settings and the interaction rules that bind them to the map.
- `persistence`: Versioned save and load, autosave, atomic writes and migration handling.
- `runtime-performance`: LOD, instancing, batching, debug telemetry, stress world and measurable budgets.

### Modified Capabilities
_(none)_

## Impact

- New `game/src/ui/` hierarchy under the `Game.tscn` UI root, plus `game/scenes/menu/`.
- `GameSession` becomes the composition root owning all domain services and `SaveService`.
- Saves live under `user://saves/` with a versioned schema and migration registry.
- Depends on every earlier change; nothing may reach into simulation beyond service APIs and events.
