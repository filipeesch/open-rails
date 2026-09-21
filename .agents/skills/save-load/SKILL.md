# save-load

## Purpose
Owns durability: the versioned JSON save schema, per-entity
`to_dict`/`from_dict`, atomic writes, autosave/continue, and migration of
older saves — so quit-and-resume never loses or corrupts a game.

## When to use
Adding any persistent state, touching the save schema, save/load round-trip
bugs, autosave behaviour, or load-time integrity errors.

## Non-goals
Settings persistence (`user://settings.cfg`, owned by `godot-project`/
settings), map authoring data (`data-contracts`), main-menu flow (UI).

## Dependencies
- Saves live under `user://saves/`; header carries `save_version` and
  `game_version`; schema covers clock, company, world (heights/RLE layer +
  occupancy/rail), tracks, stations, trains, routes, cargo, industries,
  towns.
- Every service implements `to_dict()` / `from_dict()` itself (services
  know their state); `SaveService` composes and migrates.
- `main_menu`'s Continue targets the newest autosave.

## Invariants
1. Saves are **JSON**: diffable, greppable, headless-testable (design
   decision over `.tres`). Text format, stable key order for clean diffs.
2. Atomic publication: write temp file → parse-back validate → rename; an
   interrupted write leaves the previous save intact and readable.
3. Loading refuses a newer `save_version` with an explanation and leaves
   current state untouched; a save older than current runs the registered
   migration chain sequentially; a missing migration fails with a message
   naming the version range — never guess.
4. Round-trip is exact: stable 64-bit entity ids survive; routes→stations,
   trains→routes, stations→rail-cell cross-references are verified at load
   and structural problems reported, not silently repaired.
5. Autosave triggers on month boundaries, writes off the render tick with
   the same atomic writer, retains a bounded number of autosaves (oldest
   pruned — retention count is data; project decision: 5).
6. Quick save is optional in V1; if wired, it's the `Ctrl+K` palette
   "Save game" command + notification.

## Public interfaces
`SaveService`:
- `save(slot_name) -> ok`, `load(slot_name) -> ok | error reason`
- `autosave()`, `latest_autosave()`, `list_saves()`
- `register_migration(from_version, fn)`; `MIGRATIONS: Array`
- integrity pass after parse: `verify_refs(save) -> Array[String]` problems.

## Implementation rules
- New persistent field ⇒ add to the service's `to_dict/from_dict`, bump
  `save_version`, register the migration, add a round-trip test — all in
  the same change.
- Migrations are pure functions old_dict → new_dict; they never touch live
  services.
- Save on the **same data the simulation reads** — the domain is the
  source; never serialize presentation nodes.
- Save files stay human-readable; ids as integers, tiles as `[x, y]`.

## Validation
Tests (mandatory): save→load→advance one month → trains continue, revenue
proceeds; ids preserved across round-trip; interrupted write keeps old
file; future version refused; one-version-old save migrates; route stop
referencing an absent station reported. `python tools/rr.py test
--filter save` green.

## Common mistakes
- Serialising a train's node path or Godot instance id (always stable
  domain ids).
- Bumping the schema without a migration (breaks every existing save).
- `DirAccess.rename_absolute` over the live file without the parse-back
  validate step.
- Autosaving on the render frame for a big map (stutter) — do it off-tick.

## Related skills
`economy`, `route-system`, `train-system`, `cargo-system`, `terrain-system`,
`godot-project`, `testing`, `ux-principles` (notifications, no modal).
