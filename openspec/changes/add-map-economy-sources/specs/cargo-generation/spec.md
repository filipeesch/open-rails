# Spec Delta

## Purpose

Defines how world sources turn into transportable cargo over simulated time, how a source's output is shared between overlapping stations without duplication, and the batch structure that carries revenue-relevant history.

## ADDED Requirements

### Requirement: Cargo types are data-defined
Cargo SHALL be defined in data with an identifier, display name, base revenue rate and time sensitivity, and the V1 set SHALL contain passengers, mail and coal with those properties. New cargo types SHALL be addable without modifying the transport system.

#### Scenario: Coal is minimally time sensitive
- **WHEN** cargo definitions are loaded
- **THEN** coal has a materially lower time sensitivity than passengers and mail

#### Scenario: A new cargo type requires no transport change
- **WHEN** a fourth cargo definition is added to data
- **THEN** it can be produced, stored and allocated without any change to transport code

### Requirement: Monthly cargo generation
Cargo SHALL be generated on month boundaries from each source's declared monthly rate, with production from a producing industry drawn from its accumulated inventory and production from a town created from its generation rates.

#### Scenario: Town output appears on month change
- **WHEN** the simulation advances one month
- **THEN** each town has contributed its declared passenger and mail quantities

### Requirement: Distribution without duplication
Cargo produced by a source SHALL be distributed once across the eligible stations covering it, weighted by distance so nearer stations receive proportionally more, and the sum of allocated quantities SHALL equal the produced quantity regardless of how many stations overlap the source.

#### Scenario: Single covering station receives everything
- **WHEN** exactly one station covers a mine producing 20 coal
- **THEN** that station receives all 20 units

#### Scenario: Overlapping stations split the source
- **WHEN** two stations cover the same town that generates 30 passengers
- **THEN** the two stations' combined allocation is exactly 30 passengers
- **AND** the nearer station receives the larger share

#### Scenario: Uncovered source produces nothing usable
- **WHEN** no station covers a coal mine
- **THEN** the mine's inventory grows and no station receives its cargo

### Requirement: Cargo batches rather than individuals
Cargo SHALL be stored as batches carrying cargo type, quantity, origin, destination and creation time, aggregated where compatible, and the system SHALL NOT instantiate one object per passenger or per unit.

#### Scenario: Compatible cargo aggregates
- **WHEN** two allocations of the same cargo type arrive at one station from the same origin
- **THEN** they are represented as one batch with combined quantity and the earliest creation time

#### Scenario: Batch count is independent of tonnage
- **WHEN** a town generates 400 passengers in a month
- **THEN** the number of batch records stays bounded by origin and destination combinations rather than by quantity

### Requirement: Deterministic generation for tests
Cargo generation and allocation SHALL be deterministic for a given world state, month and configuration, so simulation tests can assert exact quantities.

#### Scenario: Same inputs give same allocation
- **WHEN** the same world state advances one month twice from equivalent starting states
- **THEN** every station's allocation is identical between runs
