# Spec Delta

## Purpose

Defines the logical rail network: per-cell eight-direction connections, the graph derived from them, traversal and path queries, and the terrain rules that decide whether a connection may exist.

## ADDED Requirements

### Requirement: Rail cells store eight-direction connections
Each rail cell SHALL store its connections as a bitmask over the eight directions `N, NE, E, SE, S, SW, W, NW`, and the rail graph SHALL be derived from those connections rather than maintained separately. Adding a connection SHALL automatically establish the reciprocal connection in the adjacent cell.

#### Scenario: Laying track creates reciprocal connections
- **WHEN** a rail cell gains an eastward connection into the neighbouring cell
- **THEN** the neighbouring cell reports a westward connection back

#### Scenario: Removing a cell clears its connections
- **WHEN** a rail cell is removed
- **THEN** no remaining cell reports a connection into it

### Requirement: Rail graph traversal and reachability
The system SHALL expose reachability between any two rail cells and a shortest-path query over the rail graph, using A* with a documented cost function. Rail cells shall be treated as an undirected graph in V1.

#### Scenario: Disconnected networks are reported unreachable
- **WHEN** reachability is queried between two cells on separate networks
- **THEN** the query reports no path rather than returning a partial route

#### Scenario: Path follows laid track
- **WHEN** a path is requested between two cells connected by an L-shaped line
- **THEN** every step of the returned path is an existing rail connection

### Requirement: All intersections are connected junctions
Where three or more connections meet in one cell, the cell SHALL behave as a connected junction available to any route, and trains SHALL be able to leave a junction along any of its connections. Grade-separated crossings SHALL NOT be representable in V1.

#### Scenario: Junction offers every branch
- **WHEN** a cell has connections to north, east and south
- **THEN** a route arriving from the north may continue east or south

### Requirement: Slope rule
A connection between adjacent rail cells SHALL be valid only when the elevation difference between them is at most one terrain height step. A steeper difference SHALL be reported invalid with a slope-specific reason.

#### Scenario: One-step climb is legal
- **WHEN** rail connects two cells whose heights differ by exactly one height step
- **THEN** the connection is valid

#### Scenario: Two-step climb is illegal
- **WHEN** rail would connect cells whose heights differ by two height steps
- **THEN** the connection is invalid and the reason identifies excessive slope

### Requirement: Water and blocked terrain reject rail
A rail connection SHALL be invalid where either endpoint cell is water or where the cell is already occupied by an incompatible entity, and each rejection SHALL carry a distinct reason usable directly in player-facing feedback.

#### Scenario: Water rejection is distinguishable
- **WHEN** rail is proposed onto a water cell
- **THEN** the returned reason identifies water rather than a generic failure

### Requirement: Network change notification
Whenever the network changes, the system SHALL emit a `track_changed` event identifying the affected tiles, so renderers and route owners can respond without polling.

#### Scenario: Commit reports changed tiles
- **WHEN** a multi-tile rail segment is committed
- **THEN** a single change event lists every tile whose connections changed
