# ux-principles

## Purpose
The project-wide interaction law. Every UI or map-interaction feature is
designed against these rules; they resolve debates before code is written.

## When to use
Designing any feature that touches the player; reviewing UI PRs; choosing
between a modal and a notification, a dropdown and a map click.

## Non-goals
Concrete widget code (`ui-components`), tool behaviour (`build-mode-ux`),
keybinding table (`input-navigation`), panel geometry (`ui-layout`
reference).

## Dependencies
- `.agents/references/ui-layout.md` (what exists where).
- Events: UI consumes `money_changed`, `month_changed`, `train_arrived`, …;
  simulation never calls UI (`godot-project` invariant).

## Invariants
The law — every point is checkable at review:
1. **The map is the primary surface.** The map occupies almost the whole
   screen; no large permanent sidebars; tool options only during tools;
   inspector only while something is selected.
2. **Prefer direct manipulation.** Interact with the world, don't select it
   from lists: add a route stop by clicking the station; inspect by
   clicking the train; centre by clicking a search result. Dropdowns are
   for small enums only.
3. **Preview consequences before commit.** Ghost geometry, cost, validity,
   coverage — always before purchase. Never "buy, then discover invalid".
4. **Explain invalid actions.** Specific, adjacent to the cursor:
   "Cannot build station — Requires straight rail", never "Invalid
   placement"; feedback is colour + icon + text, never colour alone.
5. **Avoid blocking modals.** Non-blocking, dismissible notifications for
   insufficient funds, unreachable, storage full, saved. Errors on the
   selected entity also appear in its inspector.
6. **Escape always backs out** — operation first, then mode (two Escapes
   leave build mode).
7. **Keep actions reversible when practical** — construction undo exists
   and is financially honest; anything irreversible is previewed hard.
8. **Visible feedback during long interactions** (drags, planning, dwell).
9. Hover is lightweight context and never replaces selection; selection is
   contextual (same right-side inspector region for everything).
10. **A control's label is a promise** — pressing it must do the thing the
    label names, and nothing else. Three breach shapes to look for: wired to
    nothing (or a `pass` handler); a state-holding toggle standing in for a
    momentary verb (the control stays lit after the act, so the player reads
    it as a mode); label written by one function, behaviour by another.
11. **A screen does not reach into another screen** — a verb that lives in a
    sibling screen is emitted as a signal and wired by the composition root,
    never by digging through the tree or a node group.

## Public interfaces
No code. Design-review checklist derived from the law:
map-share %, direct-manipulation used?, preview-before-commit?, error
specificity, escape path, reversibility, feedback during waits.

## Implementation rules
- New panel? Justify why it isn't the inspector, the toolbar, or the map.
- New alert? Default to notification; modal requires a stated reason.
- New list of world entities? It should focus the camera on selection, not
  replace clicking the world (search/palette is the one sanctioned list).
- Copy tone: short, concrete, names the thing ("Coal Mine inventory full").
- Every control gets a test that **presses** it and asserts a state change in
  the thing it claims to act on. A label is not evidence; a signal emitted
  into an empty room is not evidence.
- `GameTheme.button_for` for verbs, `GameTheme.toggle` only for controls that
  hold a state the player can read back. Wrong factory = lying control.
- Cross-screen verbs: the screen emits, `src/game_root.gd` wires. Grep the
  root for the signal name before claiming a button works.

## Validation
Walkthrough test against the spec's V1-complete checklist: a new player
performs launch → build → route → earn → save → load unaided. UI PR review:
each of the eleven invariants pass/fail recorded; failures fixed or waived in
writing.

## Common mistakes
- "Confirm purchase?" modal for a fully previewed, undoable action.
- Choosing stations from a dropdown because it's easier than pick mode.
- Red-only invalid feedback (colour-blind failure).
- Tooltips that hold the only copy of an error message.
- Counting `signal_x.connect(...)` as proof a button works: check that the
  connect target is not a field nobody ever sets, and that the handler is not
  `pass`.
- A button whose label is rewritten by the state-refresh function while its
  handler reads a different variable — the two drift and the button starts
  promising the opposite of what it does.

## Related skills
`ui-components`, `build-mode-ux`, `input-navigation`, `camera-navigation`,
`route-system`, `diagnostics` (notifications plumbing), `ui-layout`
reference.
