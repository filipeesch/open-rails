# input-navigation

## Purpose
Owns the input map and navigation affordances: which physical keys and
mouse gestures do what, and how focus/follow/selection interactions feel.
One place defines bindings; features consume action names.

## When to use
Adding a shortcut, resolving a binding conflict, wiring camera-related
input, double-click/F focus, follow-mode entry/cancel, or hover vs click
distinction.

## Non-goals
Camera motion maths (`camera-navigation` owns it), selection resolution
maths (`iso-world`), tool behaviour (`build-mode-ux`).

## Dependencies
- `game/project.godot` input actions — the current set:
  `cam_pan_up/down/left/right` (WASD), `cam_rotate_cw/ccw` (E/Q),
  `cam_reset` (Home), `focus_selected` (F), `undo` (Ctrl+Z),
  `settings_panel` (O), `command_palette` (Ctrl+K), `debug_overlay` (F3, F4),
  `tool_cancel` (Escape),
  `speed_pause` (Space), `speed_1x` (1), `speed_2x` (2), `speed_4x` (3),
  `cam_zoom_in` (= and keypad +), `cam_zoom_out` (- and keypad -),
  `build_mode` (B), `company_panel` (C), `panel_trips` (T).
  Where two keys are listed, both are bound: the docs and the code drifted apart
  once already, so the manual's key and the engine's key are both honoured.
  `cam_reset` used to be bound to `Tab` as well as `Home`, and the `Tab` half
  never arrived: `Tab` is the engine's own focus-walk key, and every control in
  this interface takes focus, so a button that had been clicked once swallowed the
  press before the valley ever saw it. **Never bind a verb to a key the interface
  engine consumes for itself** — `Tab`, and the arrows while a control holds focus.
  A binding that cannot arrive is a shortcut that lies.
- Mouse: wheel = zoom, middle drag = pan, right drag = rotate;
  double-click entity = focus.
- Trackpad, which is not a mouse and sends no wheel buttons: two-finger scroll
  arrives as `InputEventPanGesture` (pan) and a pinch as
  `InputEventMagnifyGesture` (zoom). A listener for `MOUSE_BUTTON_WHEEL_*` alone
  cannot be zoomed from a laptop's own touchpad at all.
- Every advertised shortcut is spelled out of the `InputMap` by `KeyHints`
  (`key_for`, `keys_for`, `hint_suffix`) — no widget writes a key letter by hand.  `hint_suffix` returns the empty string when the action has no binding, so an
  unbound verb falls silent instead of inventing a letter; a tooltip assembled
  from a remembered string is the drift that this rule exists to stop.
- Player-tunable pan/rotation/zoom speeds from Settings.

## Invariants
1. All input goes through named actions; code never checks raw keycodes.
   The one exception is a trackpad gesture, which has no key and no button to
   name; it is read in `InputController._unhandled_input` and nothing else.
2. Camera actions are handled only by the camera system; UI features
   request camera moves, they don't bind camera keys themselves.
3. Escape priority ladder: options screen → active tool operation → build mode →
   selection. Exactly one stage per press. The options screen is the top rung
   because it is modal — it sits in the modal layer over everything, and the
   shared `active_panel` never names it, so a ladder that started with the panels
   would leave a full-screen sheet standing with nothing left to dismiss it.
4. Pause freezes simulation but camera and UI stay responsive; speed
   controls are reachable from anywhere in the UI.
5. Double-click focuses an entity; `F` focuses the current selection;
   `F3` toggles the debug overlay; a train's Follow action tracks the train
   preserving zoom+rotation until a manual pan cancels it.
6. Hover resolves through the same pointer→entity path as selection, must
   cost nothing (every pointer move), and never mutates selection.

## Public interfaces
- Action-name registry is `project.godot` (the source of truth); a lookup
  helper returns action → display label for the settings/help screens.
- `InputRouter` (thin): maps mouse gestures to camera system calls
  (`begin_pan`, `begin_rotate`, `zoom_at_cursor`, `focus_at_cursor`).
- Follow: `camera.follow_train(id)` / auto-cancel on pan (camera-internal).

## Implementation rules
- New binding? Add the action in `project.godot` first; document it here;
  it appears in settings/help automatically.
- Mouse-button capture during drags must not eat UI clicks (UI has input
  priority over the map layer).
- Keep edge scrolling as a setting (on/off) in the same input path.
- V1 is desktop-first; no controller remapping UI (out of scope for the
  shell change).

## Validation
Binding audit: every action in `project.godot` is handled somewhere; every
handler uses an action name; every shortcut a widget advertises is present in
the `InputMap` — `tests/test_input_bindings.gd` asserts all three, including
that the tooltips on the bottom toolbar name a key the engine answers to.  The same file also asserts the negative: that a verb does not claim a key the
  interface engine eats for its own navigation.
Manual sweep: all camera controls at each zoom band, on a trackpad as well as a
mouse; Space/1/2/3 speed transitions; Ctrl+Z right after a commit; Escape
ladder; hover cost visible in `F3` frame time.

## Common mistakes
- Handling `KEY_W` directly in a panel.
- Binding the zoom to the mouse wheel only. A laptop touchpad never sends
  `MOUSE_BUTTON_WHEEL_*`; it sends pan and magnify gestures, so the camera reads
  as dead on the machine the game is being played on.
- Printing a key letter in a tooltip or a help row by hand. Bindings move in
  `project.godot` and the string stays behind, teaching the player a thing that
  then fails; ask `KeyHints` instead, which returns "" when there is no key.
- Rotating while a tool drag is in flight from the same right-drag (gesture
  ownership unclear — tool owns the click, camera owns the drag).
- Follow mode surviving a manual pan.
- Hover doing a pathfinding/reachability query (cost rule).

## Related skills
`camera-navigation`, `build-mode-ux`, `iso-world`, `ux-principles`,
`godot-project`, `diagnostics` (F3).
