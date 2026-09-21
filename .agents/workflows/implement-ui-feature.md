# Workflow: implement-ui-feature

The standard path for anything under `game/src/ui/` or `game/scenes/` that
the player sees and touches.

## Read first (skills)
`ux-principles` · `ui-components` · `ui-layout` reference ·
`build-mode-ux` (if tool-adjacent) · `input-navigation` (if a binding is
needed) · `camera-navigation` (if the view must move) + the domain skill
whose data the panel shows.

## Steps
1. **Fit it into the existing furniture.** Where must it live? Top bar /
   bottom toolbar / right inspector / left tool panel / drawer /
   notifications / `Ctrl+K` palette — see `.agents/references/ui-layout.md`.
   If it doesn't fit, that's a design discussion (ux-principles), not an
   implementation detail. No large permanent sidebars.
2. **Design the data flow first.** Reads: service queries + domain signal
   subscriptions, refresh throttled to 0.1 s. Writes: service API calls
   only. The panel never touches simulation internals and never moves the
   camera directly — it calls `CameraRig.focus_entity(...)`.
3. **Compose from `ui-components`** against the shared Theme; use the money
  /date formatters (`Jan 1850`, `$428,320`, `+$12,430/mo`). SVG icons;
   colour + icon + text for any validation meaning.
4. **Interaction rules checklist:**
   preview before commit (builds), Escape ladder respected, hover ≠
   selection, notifications instead of modals, empty states designed,
   list-of-world-entities rows focus the camera.
5. **Bindings.** New shortcut? Add the action in `game/project.godot`
   first, then handle by action name (`input-navigation`).
6. **Scales.** Verify layout at 1280×720 and 1920×1080 with UI scale 100%
   and 200% (`content_scale_factor`).
7. **Tests.** Domain stays runnable headless — add/extend a
   `game/tests/**/test_*.gd` that executes the same underlying flow with
   **no UI loaded** (the coupling guard); UI logic that must be tested goes
   behind plain script classes. `python tools/rr.py test`.
8. **Play-check.** `python tools/rr.py game run`: exercise the checklist —
   pause/1×/2×/4× still reachable, Escape still backs out, no map-covering
   panel when nothing is selected.
9. **Check & document.** `python tools/rr.py check` green; layout facts
   that are new go into `ui-layout.md`; new components go into
   `ui-components`.

## Done when
The feature works from the player's keyboard alone, obeys the nine ux
invariants, domain tests pass with UI absent, and no widget bypasses the
Theme.
