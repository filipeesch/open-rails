# ui-components

## Purpose
Owns reusable UI widgets — buttons, cards, inspectors, drawers, tooltips,
tabs, lists, numeric displays, empty states, notifications — all rendered
from one shared Godot `Theme`.

## When to use
Building any panel, list row, tooltip or HUD element; extending the theme.

## Non-goals
Interaction law (`ux-principles`), panel placement policy (`ui-layout`
reference), 3D selection highlighting (`runtime-effects`), camera
(`camera-navigation`).

## Dependencies
- One project-wide `Theme` resource (fonts, colours, corner radii, spacing
  scale) referenced by every Control; no widget sets ad-hoc styleboxes.
- Icons are SVG imported assets (resolution-independent across 720p→4K);
  SVG never depicts world buildings/trains.
- UI scale via `content_scale_factor` (100–200%) — widgets must not bake
  font pixel sizes.
- Data comes from `GameSession` service queries + domain signals; panels
  refresh on a 0.1 s throttle (design decision) — never per-signal relayout.

## Invariants
1. Every panel derives style from the shared Theme; visual drift between
   panels is a defect.
2. Controls never reach into simulation: they call service APIs and
   subscribe to signals; simulation never calls them (domain suite passes
   with no UI loaded).
3. Money/date/percent formatting goes through shared formatters
  (`$428,320`, `+$12,430/mo`, `Jan 1850`) — no per-panel string munging.
4. Lists of world entities appear only in the command palette/trains
   drawer, and selecting a row focuses the camera **via the camera
   system**.
5. Empty states are designed (icon + one-line hint + primary action), never
   a blank panel.
6. Every interactive element has hover/press/disabled states in the theme
   and works at 1280×720 with UI scale 100% and at 200% on 1080p.

## Public interfaces
Component set (scenes + scripts under `game/src/ui/components/`):
`RRButton`, `RRCard` (locomotive purchase cards: preview, name, price, max
speed, power, running cost), `RRInspector` (right-side context host),
`RRDrawer` (non-modal, e.g. Trains), `RRTooltip` (hover), `RRTabs`,
`RRListRow`, `RRMoney`, `RREmptyState`, `RRNotification` (+
`NotificationBus.push(text)` consumer).

## Implementation rules
- Compose; don't fork. Need a variant? Add a theme variant/style name, not
  a copy-paste scene.
- Drawers are non-modal and don't cover the map centre; inspector occupies
  the right band only while selection exists.
- Throttle refresh: subscribe, mark dirty, repaint on a shared 0.1 s timer.
- Keep signals one-way in (events) and API calls one-way out (commands).
- Consistent spacing/typography come from the theme's scales — hard-coded
  offsets in a scene are review flags.

## Validation
Theme audit: no Control outside the theme root carries a stylebox override.
Layout audit at 1280×720 / 1920×1080 / UI 200%: nothing clipped or
overlapping the toolbar. Notification overflow test: 10 queued notices stay
dismissible and non-blocking.

## Common mistakes
- A panel computing profit by re-reading the ledger itself (service owns
  aggregation; panel displays).
- Local fonts/colors "temporarily".
- Refreshing per `money_changed` signal → layout thrash; throttle.
- Implementing camera moves inside a row-click handler.

## Related skills
`ux-principles`, `ui-layout` reference, `godot-project`, `build-mode-ux`,
`input-navigation`, `economy` (formats), `runtime-effects` (selection
coordination).
