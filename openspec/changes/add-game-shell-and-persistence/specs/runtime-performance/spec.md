# Spec Delta

## Purpose

Defines how the game stays lightweight under large maps and many moving parts: LOD and animation LOD tiers, instancing and batching, a debug telemetry overlay and a synthetic stress world that proves scalability.

## ADDED Requirements

### Requirement: Spatial and animation LOD tiers
Substantial assets SHALL present LOD0 near the camera, LOD1 at normal gameplay distance and LOD2 at distant overview, and animation SHALL degrade by distance — full effects near, reduced effect rate at medium, reduced update frequency and no particles far.

#### Scenario: Distant trains stop emitting effects
- **WHEN** a train is beyond the far-distance threshold
- **THEN** its particle effects are disabled while its wheels update less frequently

#### Scenario: LOD selection follows distance
- **WHEN** the same asset is viewed at close, medium and far camera distances
- **THEN** progressively lower-detail meshes are used

### Requirement: Instancing and batching at scale
Static scenery SHALL render through multi-instance draws, static track SHALL be batched per chunk, and repeated buildings SHALL share instanced geometry rather than creating nodes per instance.

#### Scenario: Ten thousand instances stay bounded
- **WHEN** a stress world with 10,000 vegetation instances is presented
- **THEN** the draw-call contribution from vegetation remains bounded by chunk and mesh count rather than instance count

### Requirement: Debug overlay
Development builds SHALL expose an overlay on `F3` reporting FPS, frame time, draw calls, visible objects, visible trains, terrain chunks, rail chunks, simulation tick time, pathfinding time and a memory estimate.

#### Scenario: Overlay toggles
- **WHEN** the player presses `F3` twice
- **THEN** the overlay appears then disappears
- **AND** while visible every listed metric shows a value

### Requirement: Synthetic stress world
The repository SHALL provide a reproducible stress scenario containing approximately a 256 × 256 terrain, 5,000 town and scenery objects, 10,000 repeated vegetation instances, 2,000 rail tiles, 100 stations, 100 industries and 100 trains, and it SHALL be launchable from the development CLI.

#### Scenario: Stress world boots and runs
- **WHEN** the stress scenario is launched headlessly and simulated for a fixed number of ticks
- **THEN** all 100 trains report a status and the simulation completes without errors

#### Scenario: Stress scenario is reproducible
- **WHEN** the stress world is generated twice with the same seed
- **THEN** the resulting entity placements and consists are identical

### Requirement: Performance budgets are recorded and measured
The project SHALL record V1 budgets — 60 FPS at 1920 × 1080, normal RAM below 700 MB, GPU memory below 512 MB, and simulation comfortably inside the fixed-tick budget — and SHALL provide a measured report against them rather than an unverified claim.

#### Scenario: Report states measurements not claims
- **WHEN** a performance report is produced
- **THEN** each budget line shows a measured value with the environment it was measured on, or is marked not measured

### Requirement: Runtime anti-patterns are prohibited
The runtime SHALL NOT create a node per terrain tile, a material per building, a physics body per rail tile, animate offscreen decoration, pathfind every tick, or rebuild the whole terrain for a local change.

#### Scenario: Local track edit does not rebuild the world
- **WHEN** one tile of track is added on a 256 × 256 map
- **THEN** only the affected chunk geometry is rebuilt, verified by a rebuild counter

#### Scenario: Pathfinding is cached
- **WHEN** a train continues along an unchanged route for many ticks
- **THEN** no pathfinding query runs for that train during those ticks
