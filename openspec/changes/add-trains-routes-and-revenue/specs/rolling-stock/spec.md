# Spec Delta

## Purpose

Defines data-driven locomotives and wagons, how a consist is composed and priced, and how a train is purchased and spawned from a station.

## ADDED Requirements

### Requirement: Rolling stock is defined in data
Locomotives and wagons SHALL be defined as external data carrying identifier, display name, asset identifier, price, running cost and role-specific attributes — maximum speed, power and weight for locomotives; cargo type, capacity and weight for wagons. Adding rolling stock SHALL NOT require modifying the train engine.

#### Scenario: V1 stock exists in data
- **WHEN** rolling stock definitions are loaded
- **THEN** one 4-4-0 steam locomotive and Passenger Coach, Mail Car and Coal Hopper wagons exist

#### Scenario: A new wagon needs no code change
- **WHEN** a new wagon JSON definition is added to data
- **THEN** it becomes selectable in the consist editor without any change to train code

### Requirement: Train purchase requires a starting station
A train SHALL only be purchasable from a station, SHALL require at least a locomotive, SHALL charge the locomotive and wagon prices as one purchase transaction through `EconomyService`, and SHALL spawn at the chosen station's rail access point. Insufficient funds SHALL block the purchase with a reason.

#### Scenario: Purchase without a station is impossible
- **WHEN** no station exists
- **THEN** the new-train flow offers no starting station and no train can be purchased

#### Scenario: Purchase spawns at the station
- **WHEN** a train is bought at Riverside station
- **THEN** the train exists at that station's rail position ready to run its route

### Requirement: Consist composition controls
The consist editor SHALL support adding, removing and reordering wagons behind the locomotive and SHALL reject removal of the locomotive while the train exists.

#### Scenario: Wagons reorder visually and logically
- **WHEN** the player moves a mail car ahead of a passenger coach
- **THEN** the consist order reflects the change and capacity totals are unchanged

### Requirement: Live consist statistics
While editing, the system SHALL report total capacity per cargo type, total weight, estimated maximum speed, purchase cost and running cost, derived from the current consist.

#### Scenario: Heavier consist is slower
- **WHEN** wagons are added beyond the locomotive's economical hauling capacity
- **THEN** the estimated maximum speed decreases relative to the lighter consist

#### Scenario: Cost updates on every edit
- **WHEN** a coal hopper is added to the consist
- **THEN** the displayed purchase cost and running cost include that wagon

### Requirement: Cargo capacity is enforced per type
A train SHALL only carry cargo in wagons suited to it and SHALL never exceed a wagon's declared capacity, with unusable cargo at a stop remaining in the station.

#### Scenario: Wrong wagon type is not loaded
- **WHEN** a train with no hopper attempts to load coal
- **THEN** the coal stays at the station and nothing is loaded

### Requirement: Company-coloured rolling stock
Rolling stock assets SHALL render the company's primary and secondary colours using the shared parameterised material rather than an asset-specific material.

#### Scenario: Two liveries from one asset
- **WHEN** two companies with different colours run the same locomotive model
- **THEN** both render from the same generated model with different company colour parameters

### Requirement: Rolling stock data names its length between couplers
Each locomotive and wagon definition SHALL state the vehicle's length between its own couplers, in tiles, so that a consist's length is a figure the simulation owns; a definition that omits it SHALL fall back to a stated default rather than being dropped.

#### Scenario: The halt knows how long the train is
- **WHEN** a route measures how far up the line its train has to pull up
- **THEN** the figure comes from the definitions of the vehicles in that consist and the slack between them

#### Scenario: A missing length degrades rather than disappears
- **WHEN** a definition ships without a length
- **THEN** the vehicle is still registered and counted with the default length
