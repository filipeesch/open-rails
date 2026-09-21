# Spec Delta

## Purpose

Defines the world's economic sources and sinks — towns generating passengers and mail, industries producing or consuming cargo — and the data-driven framework that lets future chains exist without changing the cargo system.

## ADDED Requirements

### Requirement: Towns as economic entities
Each town SHALL expose a stable identifier, name, population, position, passenger generation rate and mail generation rate, and SHALL be defined in data rather than in code. Towns SHALL NOT grow dynamically in V1.

#### Scenario: Town generates two cargo streams
- **WHEN** a town with passenger and mail generation is simulated for one month
- **THEN** quantities for both streams are produced from that town equal to its declared monthly rates

#### Scenario: Population does not change
- **WHEN** a town is simulated for twelve months with profitable service
- **THEN** its population is unchanged

### Requirement: Industry production and storage
A producing industry SHALL declare a production rate, a storage capacity and a current inventory, and SHALL accumulate produced cargo at its rate up to capacity. Reaching capacity SHALL stop accumulation and SHALL be reportable so the player can be notified.

#### Scenario: Coal mine accumulates at its rate
- **WHEN** a mine rated at 20 units per month is simulated for one month with no pickup
- **THEN** its inventory grows by 20 units

#### Scenario: Storage saturates
- **WHEN** a mine with capacity 60 and inventory 55 runs a further month
- **THEN** its inventory ends at 60 and the mine reports being full

### Requirement: Industry consumption
A consuming industry SHALL declare the cargo it accepts, a consumption capacity and the quantity received in the current month, and SHALL record delivered cargo rather than rejecting it.

#### Scenario: Power plant records delivered coal
- **WHEN** 30 units of coal are delivered to a power plant
- **THEN** the plant's received-this-month value reflects the delivery

### Requirement: Data-driven industry chain framework
Industry definitions SHALL be data that names produced or accepted cargo by identifier with quantities and rates, and SHALL support an industry with multiple accepted inputs and multiple outputs. Adding a new cargo type or chain SHALL NOT require modifying the transport or cargo systems.

#### Scenario: A steel mill is expressible in data
- **WHEN** an industry definition declares coal and iron as inputs and steel as an output
- **THEN** the framework accepts and simulates it without changes to cargo transport code

### Requirement: Shipped Founder's Valley map
The game SHALL ship one hand-authored 256 × 256 sandbox map containing exactly 2 towns, 2 coal mines, 2 power plants, water, forests, hills and open plains, with layout offering several viable railway designs. Procedural generation SHALL NOT be required.

#### Scenario: Map loads with declared content
- **WHEN** Founder's Valley is loaded
- **THEN** two towns, two coal mines and two power plants exist at authored positions on a 256 × 256 grid

#### Scenario: Map has varied terrain
- **WHEN** the map's terrain types are enumerated
- **THEN** water, forest, hill and plain tiles are all present

#### Scenario: A profitable first line is affordable
- **WHEN** a sandbox starts on Founder's Valley with the configured starting cash
- **THEN** funding a mine-to-plant railway, a station pair and one train is affordable
