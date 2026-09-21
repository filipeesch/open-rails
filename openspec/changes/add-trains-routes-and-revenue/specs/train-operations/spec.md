# Spec Delta

## Purpose

Defines deterministic train movement along the rail graph, the train's simulation state, dwell behaviour and the coupling between travelled distance and mechanical animation.

## ADDED Requirements

### Requirement: Movement is deterministic along the rail graph
Trains SHALL move by advancing along rail cells and connections without physics simulation, and a train's state SHALL expose its current track cell, position along the segment, speed, route, destination stop, path and cargo. Given the same starting state, route and tick count, the resulting position SHALL be identical.

#### Scenario: Same seed gives same arrival
- **WHEN** two identical simulations advance a train 200 ticks
- **THEN** both trains occupy the same cell and segment position

#### Scenario: Train follows its path cell by cell
- **WHEN** a train crosses a segment boundary
- **THEN** its current cell advances to the next cell on its path and its speed is preserved

### Requirement: No collision or signalling in V1
Trains SHALL NOT collide, block one another or reserve track, and two trains SHALL be able to occupy the same cell simultaneously.

#### Scenario: Opposing trains pass
- **WHEN** two trains travel toward each other on the same line
- **THEN** both continue and pass through each other without stopping

### Requirement: Speed limited by consist and grade
A train's attainable speed SHALL be limited by its locomotive's maximum speed, reduced by consist weight and by ascending grade, and SHALL never exceed the configured maximum.

#### Scenario: Steep climb slows the train
- **WHEN** a loaded train enters a one-step-per-cell ascending grade
- **THEN** its speed settles below its flat-track maximum for the duration of the climb

### Requirement: Wheel phase derives from travelled distance
Mechanical animation SHALL be driven by a wheel phase computed as distance travelled divided by wheel circumference, so wheels never appear to slide, and repeating rod animations SHALL use the same normalised phase.

#### Scenario: Stationary train has static wheels
- **WHEN** a train is dwell-loading at a station
- **THEN** its wheel phase does not advance

#### Scenario: Faster train spins wheels faster
- **WHEN** a train doubles its speed
- **THEN** its wheel phase advances at twice the previous rate

### Requirement: Animation must never drive simulation
Simulation progression SHALL continue unchanged when visual animation is reduced or suspended, including when a train is offscreen or at a distance.

#### Scenario: Offscreen train still arrives
- **WHEN** a train travels entirely offscreen with its visual animation suspended
- **THEN** it still reaches its destination, loads and earns revenue

### Requirement: Train selection and follow affordances
A train SHALL be selectable and expose its speed, cargo load, route and current-month revenue to the inspector, plus a follow action handled by the camera system.

#### Scenario: Inspector shows live load
- **WHEN** a selected train is loading coal
- **THEN** the displayed load rises toward its capacity without any manual refresh

### Requirement: Train status is observable
Each train SHALL report a current operational status drawn from a fixed set — such as heading to stop, loading, unloading, waiting, and no path — so UI and notifications can explain what it is doing.

#### Scenario: Unreachable route surfaces as status
- **WHEN** a train's route becomes unreachable because track was removed
- **THEN** the train reports a no-path status and the reason is readable by the UI
