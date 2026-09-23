# Spec Delta

## Purpose

Defines the authoritative tile-based world state — terrain, height, occupancy and rail stored as compact data — plus the coordinate conventions and stable entity identities every other system reads.

## ADDED Requirements

### Requirement: Compact tile world state
The world SHALL store terrain type, height, occupancy and rail data for every tile in compact indexed arrays rather than in scene nodes, and the tile count SHALL NOT influence the number of Godot nodes used to hold world state. Access by tile coordinate SHALL be a direct index computation, not a search.

#### Scenario: A 256 by 256 map allocates no per-tile nodes
- **WHEN** a 256 × 256 world is created
- **THEN** 65,536 tiles are readable by coordinate
- **AND** the number of scene nodes owned by the world model stays constant regardless of map size

#### Scenario: Out-of-bounds queries are rejected deterministically
- **WHEN** a tile outside the map bounds is queried
- **THEN** the query reports the tile as out of bounds rather than returning another tile's data

### Requirement: World coordinate conventions
The system SHALL treat `Vector2i` tile coordinates as canonical, with `TILE_SIZE = 1.0` and `HEIGHT_STEP = 0.25` read from shared world configuration, and SHALL provide conversions between tile coordinates and world-space positions in both directions, including height. The tile-space direction a model or camera faces SHALL be turned into a scene yaw by one shared convention (`WorldCoords.yaw_for_direction`), so no second module re-derives the sign of the Z axis for itself.

#### Scenario: Round-trip conversion is stable
- **WHEN** a tile coordinate is converted to world space and back
- **THEN** the original tile coordinate is recovered exactly

#### Scenario: Height is quantised to steps
- **WHEN** a tile's height is read as world elevation
- **THEN** the value is an exact multiple of `HEIGHT_STEP`

### Requirement: Occupancy and entity identity
Each tile SHALL expose which kind of entity occupies it and which stable entity ID owns it. Town, industry, station and train identifiers SHALL be stable 64-bit values that survive save, load and network mutation, and no system SHALL persist a reference expressed as a scene node path.

#### Scenario: Occupancy resolves to an entity
- **WHEN** a station occupies a tile
- **THEN** that tile reports a station occupancy kind and the station's stable ID

#### Scenario: Identifiers survive a save round trip
- **WHEN** a world is saved and reloaded
- **THEN** every entity retains the identifier it held before saving

### Requirement: Terrain change notification
When terrain or occupancy data changes, the world SHALL emit a change notification identifying the affected tiles, so presentation systems rebuild only what changed.

#### Scenario: Local change reports a small region
- **WHEN** a rail tile is added
- **THEN** the change notification identifies that tile and any chunk containing it
- **AND** tiles outside the affected chunk are not reported

### Requirement: Water is impassable to rail
A tile flagged as water SHALL be reported as invalid for rail construction and SHALL be indistinguishable from other blocking terrain to callers asking only whether construction is allowed.

#### Scenario: Water blocks a rail placement
- **WHEN** a caller asks whether rail may be placed on a water tile
- **THEN** the answer is no, with a water-specific reason
