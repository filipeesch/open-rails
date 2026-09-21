# Tasks

## 1. Asset metadata and configuration

- [x] 1.1 Write `art/config/material_palette.json` with the 15 canonical palette entries and shared vertex-colour material names, and verify the palette loader returns each entry
- [x] 1.2 Implement asset package discovery that reads `asset.toml` without importing `asset.py`, and verify a scan of a sample folder reports id, type, footprint and lod class
- [x] 1.3 Make discovery reject a `.blend` file inside `art/assets/` and verify a planted `.blend` produces a named build error

## 2. Railroad Art library

- [x] 2.1 Implement the `railroad_art` context: Blender scene bootstrap, unit scale from `world.toml`, vertex-colour writer and the shared-material resolver, and verify a headless build of an empty asset produces a valid GLB
- [x] 2.2 Implement box, beveled box, cylinder, roof, pipe and wheel primitives, and verify each yields a mesh whose bounds match requested dimensions within tolerance
- [x] 2.3 Implement vehicle composite helpers — frame, boiler, cab, chimney, driving and leading wheel sets — and verify a locomotive builds from helpers alone
- [x] 2.4 Implement company-colour assignment that tags faces with the shared parameterised material, and verify the exported GLB references it rather than a baked colour
- [x] 2.5 Implement LOD assembly with auto-reduction fallback and per-lod triangle accounting, and verify exported levels decrease monotonically
- [x] 2.6 Implement animation authoring that registers canonical-state actions and emits the manifest state map, and verify an asset with a `moving` action publishes it
- [x] 2.7 Implement named attachment points and verify they appear in the manifest with local-space coordinates

## 3. Build orchestrator

- [x] 3.1 Implement the Blender job runner generating a throwaway script in a per-job temp directory with its own log, and verify a failing builder surfaces its traceback in that log
- [x] 3.2 Implement `rr.py art build <id>` producing `game/generated/models/<id>.glb` and `game/generated/manifests/<id>.json` atomically via staging and `os.replace`, and verify both files exist after a successful build
- [x] 3.3 Implement the content-hash cache stored in the manifest and verify a second unchanged build reports cached and spawns no Blender process
- [x] 3.4 Implement `art build --all --jobs N` with process isolation and a per-asset lock, and verify a parallel full build produces the same file set as a serial build

## 4. Validation and preview

- [x] 4.1 Implement the validation checks — GLB presence, manifest integrity, scale versus footprint, origin, palette membership, triangle budget per lod class, required animation names — and verify each check fails with its own named message when fed a deliberately broken asset
- [x] 4.2 Wire `rr.py art validate <id>` and `--all` to the checks with non-zero exit on failure, and verify a healthy set exits 0
- [x] 4.3 Implement `rr.py art preview <id>` rendering eight 45-degree angles at close and normal zoom into `build/previews/<id>/`, and verify 16 images are produced

## 5. Milestone asset set

- [x] 5.1 Author `tree` and `house` assets through the library and verify both build and validate
- [x] 5.2 Author the `coal_mine` industry asset with a `working` animation and verify validation confirms the published animation name
- [x] 5.3 Author the `small_station` asset with platform, building and coupling attachments, and verify attachments are present in the manifest
- [x] 5.4 Author the `steam_440` locomotive with driving and leading wheels and a `moving` animation, and verify its wheel-phase metadata and triangle budget pass
- [x] 5.5 Author `passenger_coach`, `mail_car` and `coal_hopper` wagons and verify all three validate with correct cargo-appropriate footprints
- [x] 5.6 Run `art build --all` and `art validate --all` from a clean `game/generated/` and verify every discovered asset passes
