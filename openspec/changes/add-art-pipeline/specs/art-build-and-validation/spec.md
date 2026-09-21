# Spec Delta

## Purpose

Defines how an asset description becomes a runtime GLB: headless Blender execution, parallel isolated jobs, atomic publication, input-hash caching, manifest generation, automated validation and preview rendering.

## ADDED Requirements

### Requirement: Headless asset build
The system SHALL build a named asset, or every discovered asset, from the command line without opening a Blender user interface, producing `game/generated/models/<id>.glb` and `game/generated/manifests/<id>.json`. A build SHALL be reproducible: the same source and configuration SHALL produce equivalent output.

#### Scenario: Single asset build
- **WHEN** `python tools/rr.py art build steam_440` runs
- **THEN** `game/generated/models/steam_440.glb` and `game/generated/manifests/steam_440.json` both exist
- **AND** the command exits 0

#### Scenario: Build failure is surfaced
- **WHEN** an asset builder raises inside Blender
- **THEN** the command exits non-zero, names the asset and reports the Blender log location

### Requirement: Parallel isolated build jobs
`art build --all --jobs N` SHALL run up to N simultaneous builds, each in a separate Blender process with its own temporary directory and its own log file. Two processes SHALL NEVER write to the same final asset concurrently, and final outputs SHALL be published by an atomic move from a staging location.

#### Scenario: Parallel run produces the same results as serial
- **WHEN** `art build --all --jobs 3` completes on the full asset set
- **THEN** every asset is present in `game/generated/`
- **AND** no generated file is truncated or partially written

#### Scenario: Jobs are isolated
- **WHEN** a parallel build is running
- **THEN** each job's temporary directory and log file are distinct from every other job's

### Requirement: Input-hash build cache
Each build SHALL record source hash, asset configuration hash, Railroad Art version, Blender version and build timestamp. When none of the inputs changed since the recorded build, the build SHALL be skipped and reported as cached rather than silently re-run.

#### Scenario: Unchanged inputs skip the rebuild
- **WHEN** `art build --all` runs twice with no source edits
- **THEN** the second run reports every asset as cached and starts no Blender process

#### Scenario: Editing a library primitive invalidates dependents
- **WHEN** a shared Railroad Art primitive changes and `art build --all` runs
- **THEN** assets whose output depends on that primitive rebuild

### Requirement: Generated manifest contract
Each generated manifest SHALL be valid JSON describing the asset: id, type, lod class, footprint, LOD triangle counts, materials used, attachment points and the canonical animation state mapping. The runtime SHALL treat the manifest as the authoritative description of a generated model.

#### Scenario: Manifest describes the generated model
- **WHEN** a manifest is read after a successful build
- **THEN** it lists triangle counts per LOD, the materials referenced and the animation state map

#### Scenario: Broken manifest fails validation
- **WHEN** a manifest is missing, is not valid JSON, or references a model file that does not exist
- **THEN** `art validate` fails and names the asset

### Requirement: Automated asset validation
The system SHALL validate a built asset without a UI and SHALL detect Blender errors, a missing GLB, disallowed materials, incorrect scale, excess triangle count, missing required animation, incorrect origin and a broken manifest. Validation failure SHALL exit non-zero and identify the specific check that failed.

#### Scenario: Incorrect origin is caught
- **WHEN** an asset's geometry is authored far from its local origin
- **THEN** `art validate <id>` fails naming the origin check and the measured offset

#### Scenario: Valid asset passes every check
- **WHEN** `art validate --all` runs over a healthy asset set
- **THEN** every asset reports pass and the command exits 0

### Requirement: Validation preview renders
The system SHALL render each important asset from eight horizontal angles at 45° intervals, at both close and normal zoom, into `build/previews/<id>/`. Preview renders SHALL be review artefacts and SHALL NOT be referenced by the runtime.

#### Scenario: Preview grid is produced
- **WHEN** `python tools/rr.py art preview steam_440` runs
- **THEN** sixteen preview images exist covering all eight angles at both zoom levels

#### Scenario: Previews are not runtime assets
- **WHEN** the runtime asset manifest set is enumerated
- **THEN** no path under `build/previews/` is referenced

### Requirement: Milestone asset set
The pipeline SHALL produce, without hand-modelling, at least one tree, one house, one coal mine, one station, one steam locomotive and one wagon, each passing validation.

#### Scenario: Full set builds from a clean checkout
- **WHEN** `art build --all` and `art validate --all` run on a clean checkout with only the pipeline sources present
- **THEN** all six assets are generated and validated successfully
