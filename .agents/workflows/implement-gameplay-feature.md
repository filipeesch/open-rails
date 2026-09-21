# Workflow: implement-gameplay-feature

The standard path for any change to `game/src/domain/` — a new rule, service
behaviour, or system — from spec/openspec through green tests.

## Read first (skills)
`godot-project` · `testing` · `economy` · `simulation-clock` ·
`data-contracts` · `save-load` · `performance` + whichever system skills
the feature touches (`rail-*`, `station-*`, `train-*`, `route-*`,
`cargo-system`, `industry-system`, `town-system`).

## Steps
1. **Anchor to the plan.** Find the behaviour in `docs/requirements/v1.md`
   and the matching `openspec/changes/*/` (spec delta + design.md
   decisions). If it's a genuinely new idea, propose it via the OpenSpec
   flow first (`openspec-propose` skill) — don't smuggle scope; check the
   §115 out-of-scope list before writing anything.
2. **Decide data vs code.** Rates, prices, thresholds → `game/data/` JSON
   with `DataRegistry` validation (`data-contracts`). Rules → GDScript
   services.
3. **Place it in the layering.** Domain logic in the owning service;
   cross-system reaction through typed signals (`track_changed`,
   `money_changed`, `month_changed`, …). Never call into presentation or
   UI from domain code; never read nodes.
4. **Respect the money boundary.** If it costs or earns, go through
   `EconomyService` with a new/existing category — one transaction per
   player action, refundable if undoable (`economy` skill).
5. **Respect the clock.** Fixed-step logic only; monthly work subscribes to
   `month_changed`; no wall-clock, no unseeded `randf()`.
6. **Persist it.** Add fields to the service `to_dict/from_dict`, bump
   `save_version`, register the migration, extend the save schema test
   (`save-load`).
7. **Write tests first or alongside** (`testing`): exact assertions on a
   headless isolated `GameSession`; cover the new rule plus its interaction
   with the mandatory integration scenario. `python tools/rr.py test
   --filter <area>` while iterating.
8. **Performance pass.** If anything runs per tick or per entity: state the
   scaling property, add a counter (`diagnostics`), prove bounded rebuilds/
   queries; run `python tools/rr.py stress --ticks 2000` when it touches
   trains/rail/chunks.
9. **Check.** `python tools/rr.py check` (imports + constants) and full
   `python tools/rr.py test` green before declaring done.
10. **Update knowledge.** If decisions were made, they land in the
    openspec change's design.md and, when durable, the relevant skill /
    reference file here.

## Done when
Spec scenario/tests pass headlessly, saves round-trip with the new state,
no UI coupling, money in the ledger, stress unaffected, docs updated.
