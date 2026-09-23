# Spec Delta

## Purpose

Establishes the repository skeleton, the Godot project bootstrap, the single development CLI and the shared conventions that every later game, art and tooling change must build on.

## ADDED Requirements

### Requirement: Canonical repository layout
The repository SHALL expose the directory layout defined by the V1 specification, and each area SHALL own exactly one kind of content: `game/` for the Godot project, `art/` for asset sources and the Railroad Art library, `tools/` for the development CLI, `docs/` for specifications, `.agents/` for agent knowledge and `build/` for disposable output. Generated runtime assets SHALL live under `game/generated/` and SHALL NOT be hand-edited.

#### Scenario: Layout is present and discoverable
- **WHEN** a contributor or agent lists the repository root
- **THEN** `game/`, `art/`, `tools/`, `docs/`, `.agents/` and `build/` all exist
- **AND** `game/src/` contains `domain/`, `presentation/`, `ui/` and `infrastructure/`

#### Scenario: Generated output is not treated as source
- **WHEN** the repository ignore rules are evaluated against `game/generated/` and `build/`
- **THEN** both are excluded from version control

### Requirement: Bootable Godot project
The system SHALL provide a Godot 4.7.2 Standard project configured for the Compatibility renderer with GDScript as the only runtime language, and it SHALL launch to a defined main scene without errors.

#### Scenario: Project loads headlessly without script errors
- **WHEN** `python tools/rr.py check` imports every runtime script through the Godot binary in headless mode
- **THEN** the run exits with status 0 and reports no script parse or load errors

#### Scenario: Renderer is Compatibility
- **WHEN** `game/project.godot` is read
- **THEN** the rendering method is set to the Compatibility/mobile-compatible backend rather than Forward+

### Requirement: Single development CLI
The repository SHALL provide exactly one development entry point, `python tools/rr.py`, supporting at least `game run`, `test`, `art build`, `art validate`, `art preview` and `check`. Every command SHALL return exit status 0 on success and non-zero on failure, and agents SHALL use these same commands rather than ad-hoc invocations.

#### Scenario: Help lists the command surface
- **WHEN** a user runs `python tools/rr.py --help`
- **THEN** `game`, `test`, `art` and `check` are listed with a one-line description each

#### Scenario: Unknown command fails loudly
- **WHEN** a user runs `python tools/rr.py nonsense`
- **THEN** the CLI exits non-zero and prints which commands exist

### Requirement: Headless simulation test runner
The system SHALL run domain simulation tests without creating a rendering context, and SHALL report per-test results with an aggregate pass/fail exit status.

#### Scenario: Tests run with no display server
- **WHEN** `python tools/rr.py test` executes
- **THEN** tests run without opening a window
- **AND** the process exits non-zero if any test fails

#### Scenario: A failing assertion is attributable
- **WHEN** a test asserts a false expectation
- **THEN** the runner output names the test and the expected versus observed value

### Requirement: Toolchain discovery
The CLI SHALL locate the Godot and Blender executables from documented sources — explicit path flag, then environment variable, then conventional install locations — and SHALL fail with an actionable message naming the variables and paths it tried when neither is found.

#### Scenario: Environment override is honoured
- **WHEN** `RR_GODOT` points at a Godot binary and `python tools/rr.py check` runs
- **THEN** that binary is used and the detected version is printed

#### Scenario: Missing toolchain explains itself
- **WHEN** no Blender can be located and `python tools/rr.py art build --all` runs
- **THEN** the command exits non-zero and names `RR_BLENDER` and the searched paths

### Requirement: Single shared world-constants source
The world's scale SHALL be authored once, in `art/config/world.toml`, and generated into `game/src/domain/world/world_constants.gd` for the runtime — `TILE_SIZE = 1.0`, `HEIGHT_STEP = 0.25`, the metric anchor `TILE_METRES = 16.0` that every physical quantity (speed, gradient) is converted through, chunk and map sizes, camera angles and zoom band. No asset script or gameplay module SHALL re-declare any of them, and drift between the two SHALL fail `rr.py check`.

#### Scenario: Art and runtime agree on scale
- **WHEN** `python tools/rr.py check` compares the art-side and runtime-side world constants
- **THEN** both report `TILE_SIZE = 1.0` and `HEIGHT_STEP = 0.25`

#### Scenario: Drift is detected
- **WHEN** a contributor changes one side of the shared configuration without regenerating the other
- **THEN** `python tools/rr.py check` exits non-zero and reports the mismatched constant

### Requirement: Agent knowledge base
The repository SHALL document reusable project knowledge as `.agents/skills/<name>/SKILL.md` files following the prescribed section structure, shared facts under `.agents/references/` and composed procedures under `.agents/workflows/`.

#### Scenario: Skill documents follow the required structure
- **WHEN** any `SKILL.md` under `.agents/skills/` is inspected
- **THEN** it contains Purpose, When to use, Non-goals, Invariants and Implementation rules sections

#### Scenario: Required knowledge areas are covered
- **WHEN** the skill inventory is listed
- **THEN** at least the art-style, asset-scale, material-palette, camera-navigation, iso-world, rail-network, train-system, economy, ux-principles, data-contracts and testing documents exist
