# Spec Delta

## Purpose

Defines the player-facing act of building and removing railway: drag planning with continuous preview, cost and validity feedback, commit through the economy, and reversible construction.

## ADDED Requirements

### Requirement: Drag-based rail planning
The rail tool SHALL let the player click a start tile, move the cursor, receive a continuously updated route preview and confirm an endpoint, without requiring the player to place individual track tiles. Holding `Shift` SHALL enable precision placement of single tiles.

#### Scenario: Preview updates while dragging
- **WHEN** the player has chosen a start tile and moves the cursor across the map
- **THEN** a proposed track route is recomputed and displayed for the current cursor tile

#### Scenario: Shift places one tile
- **WHEN** the player holds `Shift` and clicks a tile
- **THEN** exactly that tile's track is placed and no multi-tile route is planned

### Requirement: Route planner preferences
The planner SHALL prefer shorter distance, fewer turns, gentler slopes, existing railway and lower construction cost, and SHALL reuse an existing connection where a proposed route meets built track.

#### Scenario: Existing track is reused
- **WHEN** a proposed route's endpoint lies on an existing network reachable from the start
- **THEN** the plan reuses the existing cells instead of proposing duplicate parallel track

#### Scenario: Fewer turns is preferred
- **WHEN** two plans of equal length differ only in turn count
- **THEN** the plan with fewer turns is proposed

### Requirement: Preview communicates cost, length and validity
The preview SHALL display total track length, total construction cost and validity, and SHALL colour the preview green when valid, yellow when valid but expensive and red when invalid. An invalid preview SHALL name the principal obstruction reason adjacent to the cursor.

#### Scenario: Valid cheap route is green
- **WHEN** a route is valid and its cost is below the expensive threshold
- **THEN** the preview is green and shows length and total cost

#### Scenario: Invalid route explains itself
- **WHEN** a route cannot be completed because it crosses water
- **THEN** the preview is red and the displayed reason identifies water, not a generic invalid placement

#### Scenario: No purchase before validity
- **WHEN** the player releases the drag over an invalid endpoint
- **THEN** nothing is built and no money is charged

### Requirement: Construction commit charges the economy
Committing a valid route SHALL charge construction cost through `EconomyService` as a single ledger transaction describing track construction, and SHALL refuse to commit when available cash is insufficient, reporting insufficient funds as the reason.

#### Scenario: Commit produces one ledger entry
- **WHEN** a 12-tile route is committed
- **THEN** one track-construction transaction for the total cost is recorded
- **AND** no system mutates cash directly

#### Scenario: Insufficient funds blocks construction
- **WHEN** the route cost exceeds available cash
- **THEN** nothing is built and a notification reports insufficient funds

#### Scenario: A single cell still pays
- **WHEN** the player lays one isolated cell of track
- **THEN** one transaction for at least the straight-cell rate is recorded
- **AND** laying the same two cells one at a time costs no less than laying them together

### Requirement: Rail removal
The Remove tool SHALL let the player delete built track, refunding salvage value for the cells lifted through `EconomyService` and charging no additional cost, and SHALL refuse removal of track a station currently depends on, explaining the dependency.

#### Scenario: Dependent track is protected
- **WHEN** the player removes the rail cell a station uses for rail access
- **THEN** the removal is refused and the reason names the dependent station

#### Scenario: Lifted track pays salvage
- **WHEN** the player lifts a cell of built track
- **THEN** one refund transaction is recorded for half the cost of the cells lifted
- **AND** a set of cells that is not a contiguous run is refunded for nothing

### Requirement: Undo of construction actions
`Ctrl+Z` SHALL undo recent rail build and rail remove actions, restoring both the network state and the associated financial transactions. Actions that are no longer semantically safe to reverse SHALL be dropped from the undo history rather than producing a corrupt state.

#### Scenario: Undo refunds a build
- **WHEN** the player builds a route and immediately presses `Ctrl+Z`
- **THEN** the track is gone, the construction transaction is reversed and cash is restored

#### Scenario: Undo history is bounded
- **WHEN** the player performs more construction actions than the history capacity
- **THEN** only the most recent actions remain undoable
