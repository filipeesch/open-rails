# Spec Delta

## Purpose

Defines loading and unloading at route stops, dwell timing, delivery quality decay and the revenue recognised when cargo reaches a destination.

## ADDED Requirements

### Requirement: Loading at a stop
When a train arrives at a stop configured to load a cargo, the system SHALL transfer cargo from that station's inventory into wagons able to carry it, up to the wagon capacity, and the transfer SHALL reduce the station inventory by exactly the amount loaded.

#### Scenario: Load is capped by capacity
- **WHEN** a train with 40 coal capacity arrives at a station holding 60 coal
- **THEN** 40 units move to the train and 20 remain at the station

#### Scenario: Nothing is invented
- **WHEN** a stop configured to load mail holds none
- **THEN** the train's mail load is unchanged

### Requirement: Unloading at a stop
When a train arrives at a stop configured to unload, the system SHALL transfer cargo the destination accepts, SHALL deliver it into the destination station or the accepting industry, and SHALL reject cargo the destination does not accept, leaving it aboard.

#### Scenario: Coal delivered to a power plant
- **WHEN** a train unloads 30 coal at a station covering a power plant
- **THEN** the plant records 30 coal received and the train's coal load decreases by 30

#### Scenario: Wrong destination keeps cargo aboard
- **WHEN** a train unloads coal at a station covering no coal consumer
- **THEN** the coal remains on the train

### Requirement: Dwell time scales with cargo
Loading and unloading SHALL take time proportional to the quantity handled, with a defined minimum dwell, and the train SHALL not depart before handling completes.

#### Scenario: Bigger handling takes longer
- **WHEN** one train loads 10 units and another loads 40 units of the same cargo
- **THEN** the larger operation holds the train for a longer number of ticks

### Requirement: Delivery quality decays with age
Cargo batches SHALL carry a creation time, and time-sensitive cargos SHALL have a delivery quality that decreases the longer they have existed, while coal SHALL have little or no decay. Quality SHALL be clamped to a configured floor.

#### Scenario: Old passengers are worth less
- **WHEN** a passenger batch delivered after a long delay is compared with an identical fresh batch
- **THEN** the aged batch yields lower revenue

#### Scenario: Coal is insensitive to delay
- **WHEN** a coal batch is held for several months before delivery
- **THEN** its revenue is materially unaffected

### Requirement: Revenue formula
Delivery SHALL produce revenue of `quantity × cargo base rate × transport distance × delivery quality`, where transport distance is the rail distance between the batch origin station and the delivery station, with all coefficients drawn from configuration.

#### Scenario: Revenue is proportional to distance
- **WHEN** the same coal quantity is delivered over twice the rail distance
- **THEN** the recognised revenue is approximately double

#### Scenario: Coefficients come from data
- **WHEN** a cargo's base rate in data is doubled
- **THEN** recognised revenue for that cargo doubles without code changes

### Requirement: Delivery is a ledger event
Every delivery SHALL record revenue in the company ledger as an explicit transaction carrying date, amount and a description naming the cargo, quantity and route, and SHALL emit a delivery event the UI can react to.

#### Scenario: Delivery appears in the ledger
- **WHEN** a coal delivery completes
- **THEN** a ledger entry exists for that amount describing the cargo and destination
