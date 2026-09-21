# Spec Delta

## Purpose

Defines the fixed-step simulation clock, the selectable game speeds and the in-game calendar that production, accounting and cargo ageing are measured against.

## ADDED Requirements

### Requirement: Fixed-step simulation independent of rendering
Simulation SHALL advance in fixed ticks at a target of 20 Hz decoupled from the render frame rate, accumulating leftover time so that a varying frame rate does not change simulated outcomes over the same number of ticks.

#### Scenario: Frame rate does not change tick count
- **WHEN** the same scenario runs over one second of real time at 30 and at 120 render frames per second
- **THEN** the number of simulation ticks executed is the same within the configured tolerance

#### Scenario: Tick order is stable
- **WHEN** a tick runs
- **THEN** subsystems are updated in a fixed documented order so behaviour is reproducible

### Requirement: Game speeds
The player SHALL be able to select Paused, 1x, 2x and 4x. Paused SHALL stop all simulation progression while leaving camera and UI fully responsive.

#### Scenario: Pause freezes simulation but not the camera
- **WHEN** the game is paused
- **THEN** no train moves and no month advances
- **AND** the player can still pan, zoom, rotate and select

#### Scenario: Higher speed advances proportionally
- **WHEN** the speed is set to 4x
- **THEN** ticks are consumed at four times the 1x rate

### Requirement: Calendar progression
The simulation SHALL maintain a day, month and year calendar starting in January 1850, advancing days as ticks accumulate at the configured ratio and rolling over month and year boundaries.

#### Scenario: Month rolls into the next
- **WHEN** enough ticks accumulate to complete January 1850
- **THEN** the date becomes February 1850

#### Scenario: Year rolls over
- **WHEN** enough ticks accumulate to complete 1850
- **THEN** the date becomes January 1851

### Requirement: Month boundary event
The clock SHALL emit a `month_changed` event exactly once per calendar month, and production, allocation, accounting and recurring charges SHALL be driven by that event rather than by polling the date.

#### Scenario: One event per month
- **WHEN** a full calendar month is simulated
- **THEN** exactly one `month_changed` event is emitted

#### Scenario: Subsystems react through events
- **WHEN** a month boundary occurs
- **THEN** production and accounting respond to the emitted event rather than reading the clock every tick

### Requirement: Tunable time ratio
The mapping from real time to calendar time SHALL be a single configuration value, chosen so typical routes remain visually understandable at 1x, and changing it SHALL NOT require code changes.

#### Scenario: Adjusting the ratio only changes pacing
- **WHEN** the configured real-to-calendar ratio is halved
- **THEN** months arrive twice as fast and simulated train behaviour per tick is unchanged
