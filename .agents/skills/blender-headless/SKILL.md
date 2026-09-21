# blender-headless

## Purpose
Owns every interaction with Blender as an offline asset compiler: process
invocation, Python execution inside Blender, temp directories, logging,
exit codes, parallel jobs, and toolchain environment configuration.

## When to use
Whenever Blender must run: building an asset, validating, previewing, or
debugging a `railroad_art` primitive. Also when a build fails and you need
to read the job log or re-run with diagnostics.

## Non-goals
Visual style, geometry choices, palette or scale — those are `art-style`,
`asset-scale`, `material-palette`. Never runtime behaviour: Blender does not
exist at runtime, and no game code may depend on it.

## Dependencies
- `tools/rr.py` (`art build|validate|preview|list`) and `tools/rr_common/`
  (`toolchain.py`, `config.py`) — stdlib-only.
- `art/railroad_art/` — imported only inside Blender's Python; never by the
  host interpreter.
- Blender 4.5 LTS+ (the installed binary may be newer — 5.x — so all `bpy`
  use stays inside the `railroad_art.blender_util` façade on stable APIs).

## Invariants
1. Blender is launched only as a background process from `rr.py`; humans and
   agents never open the Blender UI to produce an asset.
2. Each parallel job = its own Blender process, temp directory and log file;
   two processes never write the same final asset (per-asset lock file).
3. Final outputs are published atomically (`os.replace` from a staging dir)
   into `game/generated/`; nothing under `game/generated/` is a partial write.
4. `.blend` files are never sources and never committed; debug blends live in
   disposable temp directories only.
5. Every manifest records `blender_version`; a build is reproducible from
   `asset.py` + `asset.toml` + library + config alone.

## Public interfaces
- `python tools/rr.py art build <id>` / `art build --all --jobs N [--force]
  [--blender PATH] [--keep-temp]`
- `python tools/rr.py art validate <id>|--all`
- `python tools/rr.py art preview <id>`
- `python tools/rr.py art list`
- Env/pins: `RR_BLENDER`, `~/.rr/toolchain.json`, `--blender` flag.

## Implementation rules
- The orchestrator writes a throwaway runner script into the job temp dir that
  puts `art/` on `sys.path`, imports the asset module, calls `build(context)`
  and exports — keep it small enough to review inside the log.
- Cache decision happens **before** launching Blender: compare the recorded
  cache key (`sha256` of asset.py, asset.toml, the whole `railroad_art` tree,
  palette + world config, blender version, library version) stored in the
  generated manifest. Unchanged ⇒ report "cached", start no process.
- Default `--jobs` is 3 (effectively `min(3, cpu_count//2)`); don't raise it
  speculatively — Blender jobs thrash the cache and CPU.
- Surface failures usefully: non-zero exit, name the asset, print the log
  path. Use `--keep-temp` when iterating on a failing builder.
- Capture Blender's stdout/stderr per job into that job's log; never mix
  concurrent jobs into one stream.

## Validation
A healthy run: `python tools/rr.py art build --all --jobs 3` then
`python tools/rr.py art validate --all` both exit 0; re-running build reports
every asset cached and spawns no Blender process. A failing builder must
exit non-zero naming asset + log.

## Common mistakes
- Importing `railroad_art` (hence `bpy`) in host-side tooling — it only works
  inside Blender; use the pure-Python manifest/metadata module instead.
- Hand-launching `blender -b ...` "just this once" — bypasses locks, caching
  and logs; go through `rr.py`.
- Saving a `.blend` and editing it by hand — regeneration will wipe the work;
  edit `asset.py`.
- Forgetting `--force` after downgrading Blender while hashes match, then
  trusting stale output.

## Related skills
`asset-validation`, `gltf-export`, `lod-policy`, `art-style`,
`performance`, `diagnostics`.
