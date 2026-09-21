# Spec Delta

## Purpose

Defines how world state becomes visible: chunked heightfield terrain with vertex colours, cheap water, and spatially grouped instanced scenery — derived from state and rebuilt only where state changed.

## ADDED Requirements

### Requirement: Chunked terrain meshes
Terrain SHALL be divided into render chunks of 32 × 32 tiles, each chunk normally producing exactly one mesh, so a 256 × 256 map renders as 64 chunks. Terrain SHALL be a heightfield without caves or overhangs.

#### Scenario: Chunk count follows map size
- **WHEN** a 256 × 256 world is presented
- **THEN** exactly 64 terrain chunks exist, each covering 32 × 32 tiles

#### Scenario: One mesh per chunk
- **WHEN** a chunk's terrain geometry is inspected
- **THEN** it is served by a single mesh rather than a mesh per tile

### Requirement: Vertex-colour terrain surfaces
Terrain surfaces SHALL express grass, dirt, rock and water colouring through vertex colours on shared materials rather than unique textures.

#### Scenario: Terrain uses shared materials only
- **WHEN** all terrain chunk materials are enumerated
- **THEN** the set contains only shared terrain materials
- **AND** no chunk material is unique to its chunk

### Requirement: Dirty-region geometry regeneration
Terrain geometry SHALL be regenerated only for chunks whose underlying terrain changed, and a local terrain edit SHALL NOT cause unrelated chunks to rebuild.

#### Scenario: Local edit rebuilds one chunk
- **WHEN** a single tile within one chunk changes height
- **THEN** only that chunk's geometry is regenerated
- **AND** the remaining 63 chunks report no rebuild

#### Scenario: Border edit rebuilds neighbours
- **WHEN** a tile on a chunk boundary changes
- **THEN** every chunk whose mesh edge depends on that tile is rebuilt
- **AND** no other chunk is rebuilt

### Requirement: Cheap water rendering
Water SHALL render as a simple coloured plane or chunked surface with optional lightweight movement, without reflection, refraction or simulation.

#### Scenario: Water adds no simulation cost
- **WHEN** a map containing lakes advances the simulation for one month with the camera looking away from the water
- **THEN** no water-related simulation work is performed

### Requirement: Instanced scenery
Trees, rocks, bushes, fences and telephone poles SHALL be rendered through instancing grouped by chunk, and repeated scenery SHALL NOT create one independently animated scene tree per instance.

#### Scenario: Repeated trees share instances
- **WHEN** a chunk containing a forest is presented
- **THEN** the trees are drawn from instanced geometry
- **AND** the scene tree count contributed by that forest is independent of tree count

#### Scenario: Static scenery is not animated
- **WHEN** scenery instances are on screen
- **THEN** no per-instance animation process runs for them

### Requirement: Terrain heightfield supports inspection sampling
The renderer SHALL expose terrain elevation at a world position so pointer interactions, previews and placement ghosts can sit on the ground surface.

#### Scenario: Ghost follows ground elevation
- **WHEN** a placement ghost is moved across a hill
- **THEN** its vertical position tracks the terrain elevation at its tile
