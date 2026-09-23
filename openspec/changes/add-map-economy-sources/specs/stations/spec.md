# Spec Delta

## Purpose

Defines the single V1 station class: where it may be built, how its catchment decides which sources it serves, and how it stores cargo awaiting transport.

## ADDED Requirements

### Requirement: Station placement requires valid rail access
A station SHALL require a footprint on buildable land and a rail cell providing rail access with an allowed alignment, found within the station class's `rail_search_radius` rings **outside its footprint**. Placement SHALL be rejected with a specific reason when no qualifying rail lies beside the yard, when the footprint overlaps water or occupied land, or when the required alignment is absent. Where more than one cell qualifies, the one nearest the yard's centre line SHALL be chosen. The chosen cell SHALL be stored with the station and read back by every consumer, so placement, simulation and drawing all mean the same rails.

#### Scenario: No adjacent rail explains itself
- **WHEN** the player attempts to place a station with no adjacent rail
- **THEN** placement is rejected with a reason naming missing rail access

#### Scenario: Curved rail is rejected when straight is required
- **WHEN** the only adjacent rail is a curve and the station requires a straight alignment
- **THEN** placement is rejected with a reason naming the required straight rail

#### Scenario: A yard that only overlooks the line is refused
- **WHEN** a station's nearest qualifying rail is separated from its footprint by a gap of open ground beyond its search radius
- **THEN** placement is rejected, and the reason says the line has to run beside the yard

### Requirement: A station is drawn against the rails it serves
A station's model SHALL be placed so its track-side edge lies on the lane of its access cell, kept within the ground its footprint claimed, and SHALL be turned to the direction of that run rather than to the camera. A station restored from a save SHALL be drawn at the same place and angle as when it was built.

#### Scenario: The platform stands at the rails
- **WHEN** a yard is built beside a straight run
- **THEN** the model's track-side edge lies on that run's lane, no part of the platform overhangs ground the player did not buy, and the yard lies behind the deck

#### Scenario: A yard on an east-west run is square to the rails
- **WHEN** a station is drawn against an axis-aligned run
- **THEN** its yaw is the run's direction, so on an east-west line it is a multiple of ninety degrees and not the projection's fixed forty-five

### Requirement: Station placement preview
Before commitment the system SHALL display footprint, required rail alignment, catchment drawn on the terrain, which towns and industries are covered, the estimated cargo available per month and the cost. Commitment SHALL be blocked whenever the preview is invalid, and valid placement SHALL charge through `EconomyService`.

#### Scenario: Coverage is legible before building
- **WHEN** the player hovers a station ghost over a town and a coal mine within range
- **THEN** both sources are highlighted and the expected monthly passengers, mail and coal are shown with the cost

#### Scenario: Invalid ghost cannot be purchased
- **WHEN** the player confirms placement while the ghost is invalid
- **THEN** nothing is built and no cost is charged

### Requirement: Catchment coverage
Each station SHALL have a catchment with an initial radius of 4 tiles measured from the middle of the yard's ground, and SHALL report every town and industry whose position lies within it. The covered cells SHALL be visualised on the terrain surface while the yard is being placed — the ghost is where a player decides whether the reach is worth paying for — and the sources it covers SHALL be named in the yard's own readout once it is built.

#### Scenario: Source inside radius is covered
- **WHEN** a coal mine lies 3 tiles from a station
- **THEN** that mine is reported as covered by the station

#### Scenario: Source outside radius is not covered
- **WHEN** a town lies 6 tiles from every station
- **THEN** no station reports covering that town

### Requirement: Station inventory
Each station SHALL hold a per-cargo quantity waiting for transport, SHALL accept deliveries of cargo its covered sources produce and SHALL release cargo loaded by a train, and SHALL report totals per cargo type.

#### Scenario: Generated cargo becomes waiting stock
- **WHEN** a month passes with a covered mine producing coal into one station
- **THEN** that station's waiting coal increases by the allocated amount

#### Scenario: Loading reduces station stock
- **WHEN** a train loads 20 coal from a station holding 42
- **THEN** the station reports 22 waiting coal

### Requirement: Station identity and renaming
Each station SHALL have a stable identifier and a display name defaulting to the nearest place name, and the player SHALL be able to rename it. Renaming SHALL NOT change its identifier.

#### Scenario: Rename preserves identity
- **WHEN** the player renames a station that a train route references
- **THEN** the route still references the same station identifier

### Requirement: A yard names the cell a train stands on
Each station SHALL expose the rail cell its trains stand on — the one abreast the middle of the yard's own purchased ground, reachable along the line from the cell the yard couples to — as a fact of the yard, so routes, halts and the drawing of a standing train all answer the same question with the same cell. Where no such cell carries rail, the yard SHALL report the cell it couples to.

#### Scenario: A wharf's berth is beside its deck
- **WHEN** a yard is built at the end of a line, coupling to the only straight cell beside a longer frontage
- **THEN** its berth is the cell abreast the middle of the frontage, on rail

#### Scenario: Two trains on one yard
- **WHEN** two consists are standing at the same yard
- **THEN** both are asked for, and answer with, the same berth cell
