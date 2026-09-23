# Spec Delta

## Purpose

Defines how logical rail connections become visible track: choosing canonical 3D pieces from connectivity and batching them per render chunk so editing rebuilds only what changed.

## ADDED Requirements

### Requirement: Piece selection from connectivity
The renderer SHALL choose each track piece's geometry from the cell's connection bitmask, covering straight, diagonal, 45-degree curve, 90-degree curve where required, junction and slope pieces, and the chosen piece SHALL match the logical connections exactly.

#### Scenario: Two opposite connections yield a straight
- **WHEN** a cell has connections only to east and west
- **THEN** a straight piece aligned east-west is rendered

#### Scenario: Three or more connections yield a junction
- **WHEN** a cell has connections to north, east and south
- **THEN** a junction piece offering all three branches is rendered

#### Scenario: Elevation change yields a slope piece
- **WHEN** a cell connects to a neighbour one height step higher
- **THEN** the rendered piece ascends toward that neighbour

### Requirement: Track geometry follows terrain elevation
Rendered track SHALL sit on the terrain surface at its cell's elevation, and a slope piece SHALL connect the elevations of its two endpoints without intersecting the terrain.

#### Scenario: Track follows a hill
- **WHEN** a line climbs three height steps
- **THEN** each piece's endpoints match its cell elevations

### Requirement: Chunked batching of static track
Static track SHALL be batched per render chunk, and editing track SHALL rebuild only the chunks affected by the edit.

#### Scenario: Edit rebuilds affected chunks only
- **WHEN** a tile inside one chunk gains track
- **THEN** only that chunk's track batch is rebuilt
- **AND** no other chunk rebuilds

#### Scenario: Long line does not mean one node per tile
- **WHEN** a 500-tile railway is rendered
- **THEN** the number of track scene nodes scales with chunks, not with tiles

### Requirement: Track renders from state only
Track rendering SHALL read the logical rail network as its only source of truth, so that an identical network built by tests, by loading a save or by the player produces identical geometry.

#### Scenario: Rebuilt network reproduces geometry
- **WHEN** the same connection set is built twice through different paths
- **THEN** the resulting rendered piece selection is identical

### Requirement: One authority for the height of the rail
The height of the running surface — ballast top, tie head and rail head — SHALL be derived in one place and read from that place by both the rails and the rolling stock that rides them, so a train cannot be drawn floating above or sunk into the track beside it. The rail head SHALL be the height a compiled vehicle's wheels are authored to rest at.

#### Scenario: Wheels sit on the rail they are drawn with
- **WHEN** a vehicle is placed on a cell with a ballast lift under it
- **THEN** its wheels rest at the rail head that renderer drew for that same cell, to within a hair

#### Scenario: A lifted line carries its trains with it
- **WHEN** the ground under a line is raised by a construction lift
- **THEN** both the rails and the stock running over them rise by the same figures

#### Scenario: The two agree without being told twice
- **WHEN** the shared ride height is compared across the renderer and the domain
- **THEN** one value is defined and `rr.py check` reports that the readers agree with it
