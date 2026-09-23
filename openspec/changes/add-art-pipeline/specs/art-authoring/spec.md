# Spec Delta

## Purpose

Defines how a 3D asset is described as reproducible source — its package format, shared scale conventions, the Railroad Art primitive library, the material palette, LOD levels and the animation state contract.

## ADDED Requirements

### Requirement: Asset package format
Every authored 3D asset SHALL live in `art/assets/<category>/<id>/` containing an `asset.py` builder and an `asset.toml` metadata file declaring at minimum `id`, `type`, `footprint`, `lod_class` and, where relevant, animation and company-colour sections. `.blend` files SHALL NOT be canonical sources, and any temporary `.blend` produced for debugging SHALL live in a disposable directory.

#### Scenario: Asset folder is self-describing
- **WHEN** the build system scans `art/assets/`
- **THEN** every asset directory yields an id, a type, a footprint and a LOD class without executing the builder

#### Scenario: Blend files are never sources
- **WHEN** the build system encounters a `.blend` file inside `art/assets/`
- **THEN** the build fails and names the offending path

### Requirement: Shared scale conventions
All assets SHALL be authored against the world configuration's `TILE_SIZE` and `HEIGHT_STEP` values read from `art/config/`, and each asset's declared footprint SHALL be interpretable in tile units. An asset script SHALL NOT hard-code its own notion of a tile.

#### Scenario: Footprint matches authored geometry
- **WHEN** an asset whose `footprint` declares `[1.0, 0.45]` is built
- **THEN** the resulting mesh's largest horizontal extent is within five percent of that footprint

#### Scenario: Scale is read from configuration
- **WHEN** `art/config/world.toml` changes `TILE_SIZE`
- **THEN** rebuilt assets change proportionally without any asset script being edited

### Requirement: Railroad Art primitive library
The system SHALL provide `art/railroad_art/` with reusable high-level primitives covering at least chunky boxes, beveled boxes, simple cylinders, roofs, pipes, wheels, frames, boilers, cabs and chimneys, plus vertex-colour assignment, placement helpers, LOD assembly and export. Common asset construction SHALL be expressible through these primitives, with low-level `bpy` reserved for cases the abstraction cannot express.

#### Scenario: A locomotive is built from primitives only
- **WHEN** the steam locomotive asset is authored
- **THEN** its builder calls only Railroad Art primitives for frame, boiler, cab, chimney and wheel sets
- **AND** it contains no direct mesh-data manipulation for those parts

#### Scenario: Primitives are reusable across asset kinds
- **WHEN** a house and a coal mine are authored
- **THEN** both consume the same box, roof and colour primitives from the shared library

### Requirement: Canonical material palette
The palette SHALL define the categories grass, earth, stone, brick red, brick brown, roof red, roof dark, wood light, wood dark, iron, steel, glass fake, water, company primary and company secondary. Opaque geometry SHALL be rendered by a shared vertex-colour material rather than per-asset materials, company-coloured sections SHALL use a separate shared parameterised material, and any material outside the palette SHALL fail the build.

#### Scenario: Palette violation blocks the build
- **WHEN** an asset script assigns a material whose name is not in the palette
- **THEN** validation fails and names the disallowed material

#### Scenario: Opaque assets share one material
- **WHEN** the material slots of a generated house GLB are inspected
- **THEN** every opaque surface uses the shared vertex-colour material
- **AND** the asset defines no unique material of its own

#### Scenario: Company colours remain runtime-tintable
- **WHEN** an asset declares company primary or secondary regions
- **THEN** those faces reference the company-colour material rather than baked colours

### Requirement: LOD levels
Every substantial asset SHALL export LOD0, LOD1 and LOD2 meshes, preserving detail at LOD0, major geometry at LOD1 and silhouette plus colour at LOD2. Small props MAY export fewer levels. Each LOD's triangle count SHALL stay within the budget declared for its `lod_class`.

#### Scenario: LOD set is exported
- **WHEN** the station asset is built
- **THEN** the GLB contains three named LOD meshes
- **AND** triangle counts decrease monotonically from LOD0 to LOD2

#### Scenario: Triangle budget is enforced
- **WHEN** a wagon asset's LOD0 exceeds 4,000 triangles
- **THEN** validation fails and reports the actual count against the budget

### Requirement: Animation state contract
Assets MAY author mechanical animations, and any authored action SHALL be published in the generated manifest as a mapping from canonical runtime states — `idle`, `moving`, `working`, `loading`, `unloading` — to the concrete action name, with `null` where a state is not implemented. Transient effects such as smoke, steam, sparks, dust and selection glow SHALL NOT be baked into GLB animations.

#### Scenario: Runtime reads animation names from metadata
- **WHEN** a runtime consumer needs the locomotive's moving animation
- **THEN** it resolves the name from the generated manifest rather than from a hard-coded string

#### Scenario: Unknown canonical state is rejected
- **WHEN** an asset manifest maps a state outside the canonical list
- **THEN** validation fails and lists the permitted states

#### Scenario: A named state has something to play it
- **WHEN** a shipped content definition names the animation state its asset draws with
- **THEN** the built asset resolves that state to a concrete action, and a runtime consumer plays it while the asset is on screen

### Requirement: Named attachment points
An asset that other assets or effects must attach to SHALL expose named attachment points in its manifest — for example chimney smoke origin, coupling points and cargo loading points — expressed in the asset's local space.

#### Scenario: Coupling points are published
- **WHEN** the locomotive and wagon assets are built
- **THEN** their manifests list coupling attachment points with local-space coordinates

#### Scenario: A published smoke origin is where the smoke starts
- **WHEN** a rolling locomotive emits smoke that the effect pool draws
- **THEN** the plume starts at the manifest's smoke origin carried by the body being drawn, not at a height guessed from the ground under the train
