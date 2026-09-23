# Workflow: validate-release

The pre-tag gate for a milestone/V1: prove the build is healthy by the
spec's own definitions, not by vibes.

## Read first (skills)
`testing` · `performance` · `diagnostics` · `asset-validation` ·
`godot-project` · `save-load` + `.agents/references/performance-budgets.md`.

## Steps
1. **Clean rebuild.** From a fresh checkout (or clean `game/generated/`,
   `build/`):
   - `python tools/rr.py constants` then `python tools/rr.py check`
     (imports clean, no constants drift)
   - `python tools/rr.py art build --all --jobs 3` → every asset builds or
     is legitimately cached
   - `python tools/rr.py art validate --all` → exit 0, whole asset set
     passing.
2. **Full test suite.** `python tools/rr.py test` — green, headless,
   inside the recorded regression bound in
   `.agents/references/performance-budgets.md` (under 150 s; measured 86.5 s),
   every required area covered (spec §106 list) and the
   mandatory integration scenario (build rail → stations → train → hoppers
   → route → advance → coal moved → plant received → revenue up) passing.
   Any failure = stop; do not proceed with a red suite.
3. **Play the V1-complete checklist** (`rr.py game run`), as a new player
   would, no console:
   launch → New Sandbox → navigate camera → inspect towns/industries →
   build rail → build stations → buy locomotive → add wagons → create route
   → watch travel → watch load/unload → see revenue → open finances →
   build more → save → quit → load → continue. Also: Ctrl+K search focuses
   entities; `F3` overlay populated; two Escapes leave build mode; invalid
   builds explain themselves.
4. **Scale gate.** `python tools/rr.py stress --ticks 2000` completes,
   all 100 trains report a status, run twice with the same seed for
   identical placements.
5. **Performance report.** Measure against budgets (60 FPS @1080p
   integrated target, RAM < 700 MB, GPU < 512 MB, sim well inside tick
   budget) with `F3`/stress numbers; write `build/perf-report.md` with
   hardware/renderer line; anything unmeasured is marked "not measured" —
   never claimed.
6. **Durability.** Save → corrupt-proofing sanity (kill during save;
   previous save intact); save/load round trip preserves ids and
   playability; an old-version save migrates (fixture).
7. **Quality-bar sweep** (spec §117) — checklist reviewed against the
   running build: camera polish, previews, animation, rotation-clean
   geometry, UI restraint, discoverability, self-explaining errors.
8. **Record the verdict**: suite output, stress summary, perf report link,
   checklist gaps; gaps become fixes or explicitly-deferred items (never
   silent).

## Done when
Every step is green or has a recorded, agreed exception. The stress test
reveals no architectural failure, and the integration scenario is the last
thing run before tagging.
