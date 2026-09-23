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

#### Scenario: Braking short of a stop never halts the train
- **WHEN** a train is inside its own braking distance of its next stop
- **THEN** it sheds speed towards a crawl proportional to its own maximum, and reaches the stop rather than freezing beside it

### Requirement: Stated speed and drawn speed are one quantity
A train's speed SHALL be authored in km/h and converted to map units through the world's metres-per-tile and the clock's tick rate, so the figure an inspector reports and the ground the model covers are the same measurement. Acceleration, braking and any minimum crawl SHALL be derived from the same scale. A rolling-stock model SHALL be turned to its direction of travel, and a consist SHALL be strung out behind its engine along the line.

#### Scenario: The reported speed is the ground covered
- **WHEN** a train reports a speed in km/h
- **THEN** the tiles it advances per tick are that speed divided by the tile's metres and the clock's rate, within a rounding tolerance

#### Scenario: A train crosses the view at a watchable pace
- **WHEN** a train runs at its consist's maximum speed at 1x
- **THEN** it covers between 0.4 and 3.0 of its own body lengths per second, and takes between 8 and 120 seconds to cross the default view

#### Scenario: A moving consist is turned down its rails
- **WHEN** a running train is drawn
- **THEN** the nose of its locomotive model points along the direction it displaced over the last ticks, and its wagons hang behind it along that axis

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

### Requirement: A halt is measured in trains
A stopped train SHALL stand on rail, with the middle of its consist abreast the middle of the yard's own purchased ground and its engine no further than the end of that yard's platform, so that a train which arrives at a yard is visibly standing at the yard it came to serve. The halt SHALL be a fact of the simulation and not a trick of the drawing. Where the line runs out before the whole consist can be brought onto the deck — the stub of a wharf, the head of a pit branch — the train SHALL stop where the rail stops and lie as far alongside as the ballast reaches.

#### Scenario: A train at a wharf stands alongside its deck
- **WHEN** a train arrives at a yard whose rail access cell is the only straight cell at one end of a longer frontage
- **THEN** at least one vehicle's length of that yard's platform lies abreast the train

#### Scenario: The middle of the train is on the yard
- **WHEN** a train halts at a yard with line running on ahead of its engine
- **THEN** the middle of its consist stands abreast the middle of the yard's ground, within half a tile

#### Scenario: A halt is never short of or past the platform
- **WHEN** a train is asked where it halted at a yard
- **THEN** the point it stopped on lies within the length of that yard's platform

#### Scenario: A parked train and an arriving one stand in the same place
- **WHEN** a train is standing at a yard and when the same train arrives at it
- **THEN** both occupy the same halt, so nothing jumps as the train begins to move

### Requirement: A consist articulates along the line
Every vehicle of a drawn train SHALL be placed at its own point on the line, on its own tangent and at the height of the ground under its own wheels, so that the train follows a curve one vehicle at a time — the engine already on the new bearing while the brake van still rides the old one. A consist SHALL NOT be drawn as one rigid body rotated about a single point.

#### Scenario: Vehicles take a corner one after another
- **WHEN** a consist of three or more vehicles is drawn with a corner under its middle
- **THEN** the bearings of adjacent vehicles differ, and the sharpest difference between two of them is the kink the rail makes at a cell centre rather than a smooth sweep

#### Scenario: Every vehicle rides the rail it stands on
- **WHEN** any vehicle of a drawn consist is measured against the network
- **THEN** it lies on the nearest stretch of rail, and it is not lying across a line it could not be standing on

#### Scenario: A vehicle pitches to its own grade
- **WHEN** a consist straddles cells of different height
- **THEN** each vehicle is pitched by the rise between the two cells under it, read from the same rail-height authority the rails are drawn with

#### Scenario: A train waiting without a route is still a string of vehicles
- **WHEN** stock standing at a yard with nothing filed for it to run is drawn
- **THEN** its vehicles hang one behind another along the rails at their coupling distances, each standing on a rail, rather than all of them on the halt's own point

#### Scenario: A train turned round at a yard stays on the rail
- **WHEN** a consist is strung out through the reversal at the end of a single line
- **THEN** every vehicle still lies on the rail, nose-to-nose with the ones beyond the turnaround, because the line it came in on is the line it leaves by

### Requirement: Rolling stock definitions carry their length
Rolling stock definitions SHALL carry each vehicle's length between its couplers, and the length of a consist SHALL be derived from those figures and the coupling slack, so that the domain — which decides where a train stops — owns the fact of how long a train is without asking the artwork.

#### Scenario: The picture and the halt agree on the train
- **WHEN** the distances between the vehicles as drawn are compared with the offsets the simulation reports for the same consist
- **THEN** they are the same figures

#### Scenario: A longer train halts further up the line
- **WHEN** a consist is lengthened and its route is re-measured
- **THEN** its halt moves up the line by half the added length, as far as the rails ahead allow
