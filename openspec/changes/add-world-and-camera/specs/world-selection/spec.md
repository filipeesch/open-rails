# Spec Delta

## Purpose

Defines how a pointer position resolves to a world entity — through terrain intersection and the occupancy grid rather than physics bodies — and what the player receives once something is selected.

## ADDED Requirements

### Requirement: Pointer-to-tile resolution without physics
For static world entities the system SHALL resolve a screen position by casting a ray onto the terrain heightfield, converting the intersection to a tile coordinate and reading the occupancy grid to obtain an entity identifier. Static entities SHALL NOT require physics bodies for selection.

#### Scenario: Selecting a station by clicking it
- **WHEN** the player clicks a station building on screen
- **THEN** the system resolves the clicked tile, reads its occupancy and selects the station owning that tile

#### Scenario: Empty ground selects nothing
- **WHEN** the player clicks terrain with no occupying entity
- **THEN** the selection is cleared rather than retaining the previous entity

#### Scenario: Sloped terrain still resolves
- **WHEN** the player clicks a hillside tile
- **THEN** the resolved tile is the tile visually under the cursor, accounting for its elevation

### Requirement: Dynamic train hit testing
Trains SHALL be selectable without physics bodies, using lightweight selection volumes or screen-space hit testing, and a train under the cursor SHALL take precedence over the terrain tile behind it.

#### Scenario: Train takes precedence over ground
- **WHEN** a train is visually in front of plain track and the player clicks it
- **THEN** the train is selected rather than the rail tile beneath it

### Requirement: Selection feedback and context
A selected entity SHALL receive a subtle outline or highlight, SHALL populate contextual information for the inspector, and SHALL expose map focus actions. Selection state SHALL be readable by UI and presentation without either mutating simulation state.

#### Scenario: Selection publishes context data
- **WHEN** an industry becomes selected
- **THEN** a selection change is published carrying the entity kind and identifier
- **AND** the highlight is visible on that entity

#### Scenario: Escape clears selection
- **WHEN** the player presses Escape with an entity selected and no operation in progress
- **THEN** the selection and its highlight are cleared

### Requirement: Hover resolves through the same path
Hover information SHALL be produced by the same pointer-to-entity resolution as selection, at a cost low enough to run every pointer move.

#### Scenario: Hover identifies an industry
- **WHEN** the pointer rests over a coal mine
- **THEN** hover data naming the industry and its output is available within the same frame
- **AND** no selection change occurs
