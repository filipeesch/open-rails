# Spec Delta

## Purpose

Defines a train route as an ordered set of station stops with per-stop loading instructions, how stops are picked on the map, and how routes validate and recalculate against the rail network.

## ADDED Requirements

### Requirement: Route is an ordered stop list
A route SHALL consist of an ordered list of at least two station stops, each with the cargo it loads and the cargo it unloads, and the train SHALL execute the list cyclically until the route is edited.

#### Scenario: Two-stop route loops
- **WHEN** a route has a loading stop and a delivery stop
- **THEN** the train returns to the first stop after completing the last

#### Scenario: Stop order is respected
- **WHEN** a route lists stops A, B and C
- **THEN** the train visits them in that order

### Requirement: Adding a stop by picking on the map
Adding a stop SHALL enter a station-picking mode on the map where the player clicks the desired station, and the player SHALL NOT be required to choose a station from a list. Stations not reachable over rail from the current route SHALL be shown as invalid at pick time.

#### Scenario: Clicking a valid station adds it
- **WHEN** the player picks a reachable station during stop-picking
- **THEN** that station is appended to the route

#### Scenario: Unreachable station is rejected with a reason
- **WHEN** the player picks a station on a disconnected network
- **THEN** the stop is not added and the reason states it is unreachable

### Requirement: Route stop editing
The route editor SHALL support adding, removing and reordering stops and configuring per-stop loading and unloading, and SHALL show live reachability of the resulting route.

#### Scenario: Reordering revalidates the path
- **WHEN** the player reorders stops into a sequence that is still connected
- **THEN** the route's path is recomputed and remains valid

### Requirement: Recalculation on network change
When the rail network changes, every affected route SHALL recompute its path; a route that becomes impossible SHALL keep its definition, mark itself invalid and surface a notification naming the train and the unreachable station.

#### Scenario: Track removal invalidates dependent route
- **WHEN** the only track between two route stops is removed
- **THEN** the route reports invalid, the train reports no path and a notification identifies the affected train

#### Scenario: Rebuilding restores the route
- **WHEN** track reconnecting the same stops is built
- **THEN** the route becomes valid again without the player recreating it

### Requirement: Loading configuration per stop
Each stop SHALL specify which cargo it loads and which it unloads, and only cargo present at the stop or accepted there SHALL be selectable.

#### Scenario: Loading a cargo the stop lacks is shown as unavailable
- **WHEN** a stop has no coal available
- **THEN** configuring that stop to load coal reports that no coal is available rather than silently loading nothing

### Requirement: A leg is measured between the places trains stand
Each leg of a route SHALL be measured between the cells the trains stand on at its two yards — their berths — and not between the cells the yards couple to, which are different cells wherever a yard's frontage is longer than the straight stretch beside it. Halts SHALL be pulled up the line by half the flying train's length, bounded by the rail running ahead of the engine, so the middle of the train arrives on the yard.

#### Scenario: A leg does not stop its train a platform short
- **WHEN** a route's first stop is a yard whose coupling cell lies at one end of its frontage
- **THEN** the path runs to the berth beside the middle of that ground rather than stopping at the coupling cell

#### Scenario: Only a turnaround is pulled up
- **WHEN** a stop is one the line carries straight through rather than turns round at
- **THEN** its halt stays on the marker the two legs meet at, since a train cannot be stopped on a point it runs over

#### Scenario: A restored route is measured with its train
- **WHEN** a save is loaded, whose routes are rebuilt before the trains that fly them
- **THEN** every route's halts are measured again once the consists are known, and a restored train stands exactly where it stood when it was saved
