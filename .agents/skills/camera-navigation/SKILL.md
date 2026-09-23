# camera-navigation

## Purpose
Owns the orthographic isometric camera — projection, orientation, zoom, pan,
rotation, focus, follow and smoothing. It is the only camera system in the
project; every camera movement anywhere goes through it.

## When to use
Any change to camera feel or controls, any feature that wants to move the
view (focus a search result, follow a train, reset after load).

## Non-goals
Selection/pointer resolution (`iso-world`), UI layout (`ui-layout`
reference), zoom-dependent label *content* (labels read camera state but
this skill doesn't own the panels).

## Dependencies
- Constants from `WorldConstants`: default yaw 45°, fixed pitch 35.264°,
  zoom close/default/far = 4/28/96 tiles, snap 45°.
- `WorldCoords` plane-intersection helper for cursor-anchored zoom.
- Input, all of it arriving through `InputController` and reaching the rig as
  one of three verbs (pan, rotate, zoom): wheel zoom, two-finger trackpad
  scroll (pan), pinch (zoom), middle-drag pan, right-drag rotate,
  `Q`/`E` ±45° snaps, `Home`/`Tab` reset, WASD pan, double-click focus entity,
  `F` focus selection, `cam_zoom_in` (`=`/keypad +) and `cam_zoom_out`
  (`-`/keypad −), each keypress spending exactly one wheel notch.
- `VisibleOnScreenNotifier3D`-driven presentation for follow targets.

## Invariants
1. Projection is orthographic; pitch is **fixed** at 35.264° — no input,
   feature or setting may change it in V1.
2. Yaw is free 0–360°; drag rotation is smoothed (never teleports); snap
  inputs change commanded yaw by exactly 45° mod 360.
3. Zoom modifies orthographic size logarithmically, clamped to the
   configured 4–96 tile band; equal wheel deltas ⇒ equal size ratios.
4. Wheel zoom keeps the world point under the cursor at the same screen
   position (solves the new target via plane intersection).  A pinch is the
   same zoom anchored the same way, and a two-finger scroll is the same pan a
   middle-drag performs — same vector in, same ground out, so a player moving
   from mouse to trackpad meets no second set of physics.
5. Zoom is stated in the rig's own unit: `zoom_by(steps)` grows the visible
   tile count for a positive `steps`, so "closer" is a negative number there.
   `zoom_in()` is the name that means closer; a handler that means closer and
   passes a positive `steps` inverts the control for the whole game.
6. Camera position derives from `target` + fixed offset scaled by
   orthographic size — zooming never moves the focus point.
7. Follow mode preserves zoom and yaw (player-controlled only); any manual
   pan cancels follow.
8. No UI or gameplay code writes camera transforms; they *request* via the
   camera system's API.

## Public interfaces
`CameraRig` (yaw node → pitch node → `Camera3D`):
- `focus_entity(entity_id)`, `focus_tile(tile)` — smooth pan to target.
- `follow_train(train_id)` / `cancel_follow()`.
- `reset_view()` — canonical yaw 45°, default zoom.
- Signals/queries: `orthographic_size`, `yaw`, `target` (read-only for
  consumers like labels and LOD tiers).

## Implementation rules
- Smoothing is critically-damped exponential interpolation of target, yaw
  and size toward **commanded** values; snap keys change the command, not
  the current value; add a snap-when-close epsilon.
- WASD pan directions are camera-relative (rotate by current yaw).
- Keep all feel constants (smoothing rates, pan speed, zoom speed) in the
  settings-exposed tuning data — players configure pan/rotation/zoom speed.
- Implement zoom anchoring once, here; never approximate it in a panel.

## Validation
Manual: Home restores yaw 45 + default zoom; E from 45° lands exactly 90°;
cursor over a hill tile, zoom in/out, tile stays under cursor within a few
pixels; follow a train then middle-drag — follow cancels; and the same three
verbs performed on a trackpad, which is the input most players own. Automated:
headless test asserts pitch constant under simulated input, that zoom clamps at
band edges, and — in `tests/test_input_bindings.gd` — that a pinch, a two-finger
scroll and the zoom keys each move the rig the way the wheel does.

## Common mistakes
- A panel tweening the camera itself (breaks the single-owner rule).
- Linear zoom steps — feels wrong at both ends; logarithmic is mandated.
- Rotating by setting yaw directly (janky); rotate the *commanded* value.
- Re-deriving the focus point during zoom (focus must stay put).

## Related skills
`iso-world`, `input-navigation`, `runtime-rendering`, `terrain-system`,
`ux-principles`, `ui-components`.
