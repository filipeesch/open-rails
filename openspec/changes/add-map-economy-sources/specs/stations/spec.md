# Spec Delta

## Purpose

Defines the single V1 station class: where it may be built, how its catchment decides which sources it serves, and how it stores cargo awaiting transport.

## ADDED Requirements

### Requirement: Station placement requires valid rail access
A station SHALL require a footprint on buildable land and a rail cell providing rail access with an allowed alignment. Placement SHALL be rejected with a specific reason when no qualifying rail is adjacent, when the footprint overlaps water or occupied land, or when the required alignment is absent.

#### Scenario: No adjacent rail explains itself
- **WHEN** the player attempts to place a station with no adjacent rail
- **THEN** placement is rejected with a reason naming missing rail access

#### Scenario: Curved rail is rejected when straight is required
- **WHEN** the only adjacent rail is a curve and the station requires a straight alignment
- **THEN** placement is rejected with a reason naming the required straight rail

### Requirement: Station placement preview
Before commitment the system SHALL display footprint, required rail alignment, catchment drawn on the terrain, which towns and industries are covered, the estimated cargo available per month and the cost. Commitment SHALL be blocked whenever the preview is invalid, and valid placement SHALL charge through `EconomyService`.

#### Scenario: Coverage is legible before building
- **WHEN** the player hovers a station ghost over a town and a coal mine within range
- **THEN** both sources are highlighted and the expected monthly passengers, mail and coal are shown with the cost

#### Scenario: Invalid ghost cannot be purchased
- **WHEN** the player confirms placement while the ghost is invalid
- **THEN** nothing is built and no cost is charged

### Requirement: Catchment coverage
Each station SHALL have a catchment with an initial radius of 4 tiles measured from the station, SHALL report every town and industry whose position lies within it, and SHALL visualise the boundary on the terrain surface.

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
