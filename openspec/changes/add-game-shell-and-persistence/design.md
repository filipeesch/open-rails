# Design

## Context

See `add-game-shell-and-persistence/proposal.md` for motivation. All domain services exist and the core loop already runs headless. What is missing is the player's path from launch to load, plus durability and proof of scale. Godot's Compatibility renderer, the existing `GameSession` composition root and the domain event set constrain the UI design; the specification forbids simulation→UI calls and large permanent sidebars.

## Goals / Non-Goals

**Goals:**
- A first-time player completes the whole V1 checklist unaided.
- Saves that survive a crash mid-write and a schema bump.
- Measurable evidence — counters and a stress world — rather than a feeling of speed.

**Non-Goals:**
- No graphics options beyond the listed set, no mod support, no controller remapping UI, no new gameplay rules.
- No new rendering features; polish uses existing palette, lighting and instancing.

## Decisions

**Screens as separate scenes under a `ScreenRoot`** — `MainMenu.tscn`, `NewSandbox.tscn`, `Game.tscn` — with `GameSession` created by `Game.tscn` and destroyed on exit, rather than a persistent autoload that survives scene changes. Autoload persistence leaks simulation state between sessions and makes "load" ambiguous. Application-level settings may remain an autoload.

**UI reads through services and events only.** `GameSession` exposes typed signals (`money_changed`, `train_arrived`, `month_changed`, …) and query methods; each panel subscribes to what it renders. A shared `NotificationBus` carries transient messages so no service references a UI node — enforced by the domain test suite running with no UI loaded.

**Saves are JSON with per-entity `to_dict`/`from_dict` on the services themselves**, `save_version` and `game_version` in a header, and a migration function chain applied sequentially. JSON was chosen over `Resource` `.tres` because a versioned text schema is diffable, greppable and testable in the headless runner, which the specification's round-trip requirement demands. Writes go temp → parse-back validation → rename, and `Load` refuses a newer `save_version` rather than guessing.

**Labels are one pooled `Control` layer with projected positions**, not `Label3D` per entity: 100 stations and 100 trains as 3D text nodes would break the node budget, and zoom-dependent visibility is a simple threshold on orthographic size.

**Settings persist in `user://settings.cfg`** through `ConfigFile`, with UI scale applied via the window's `content_scale_factor` rather than per-widget font sizes.

**`Ctrl+K` palette is a modal overlay reading a command registry** contributed to by each subsystem, so palette entries cannot drift from the actions they trigger.

**LOD and animation LOD are driven by the camera's orthographic size** as the single distance proxy, plus per-train distance-to-camera bucketing for animation rate, with offscreen trains suspending visual updates through a projection test in the rig itself (`_is_framed` in `entity_renderer.gd`): each train is projected through the camera and held visible only while it sits in the frustum or a padded screen rectangle. `VisibleOnScreenNotifier3D` was rejected — under an orthographic isometric rig its AABB test is useless for a low, wide consist, which reads as onscreen from angles that show none of it. Per-object distance queries every frame were rejected as an O(entities) cost.

**The debug overlay reads Godot `Performance` monitors plus our own service counters** (terrain chunk rebuilds, rail chunk rebuilds, pathfinding time, tick time) rather than a profiler, so numbers are available in a normal dev build.

## Risks / Trade-offs

- [Every service signal could thrash UI layout] → panels refresh on a throttled tick (once per 0.1 s) rather than per signal.
- [Autosave on a large map could stall the frame] → autosave is triggered on month boundaries and writes off the render tick with the same atomic writer used for manual saves.
- [Stress world results are hardware-specific] → numbers are reported with the hardware and renderer recorded, and unmeasured budgets stay explicitly unmeasured.

## Migration Plan

Additive scenes and services plus a `save_version: 1` schema baseline. Rollback removes UI scenes and save files without touching simulation.

## Open Questions

- Whether the main menu shows a background diorama — presentation-only, decided after the shell works.
