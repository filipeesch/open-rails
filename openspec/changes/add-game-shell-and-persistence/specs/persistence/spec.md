# Spec Delta

## Purpose

Defines saving and loading a sandbox: the versioned save schema, atomic and corruption-resistant writes, autosave behaviour and migration of older saves.

## ADDED Requirements

### Requirement: Manual save and load
The game SHALL support saving the current sandbox to a named slot and loading it back, restoring the company, world, track network, stations, trains, routes, cargo, industries, towns and clock exactly.

#### Scenario: Round trip restores playability
- **WHEN** a game is saved, loaded and then advanced one month
- **THEN** trains continue on their routes and production and revenue proceed from the restored state

#### Scenario: Save from the palette
- **WHEN** the player invokes the save command from the palette
- **THEN** the game saves and reports completion through a notification

### Requirement: Autosave and continue
The game SHALL create autosaves during play at a configured interval, expose them as the Continue target on the main menu and as the Load Game target, and retain a bounded number of autosaves.

#### Scenario: Autosave interval produces a save
- **WHEN** the configured number of months elapses during play
- **THEN** an autosave exists describing that moment

#### Scenario: Oldest autosave is pruned
- **WHEN** more autosaves are produced than the configured retention
- **THEN** the oldest is removed and the newest is intact

### Requirement: Versioned save schema
Every save SHALL record a save schema version and the game version that produced it, and the schema SHALL cover clock, company, world, tracks, stations, trains, routes, cargo, industries and towns.

#### Scenario: Version is always present
- **WHEN** any save file is read
- **THEN** a save schema version and game version are present

#### Scenario: Unknown future version is refused safely
- **WHEN** a save with an unsupported newer schema version is loaded
- **THEN** loading is refused with an explanatory message and the existing game state is left intact

### Requirement: Atomic writes
Saving SHALL write to a temporary file, validate the result and only then rename it into place, so an interrupted write cannot corrupt an existing save.

#### Scenario: Interrupted write preserves the old save
- **WHEN** a save is interrupted before completion
- **THEN** the previous save file remains readable and unchanged

### Requirement: Migration path
Loading SHALL run registered migration functions for any save older than the current schema version, and a save produced by the previous version SHALL load into current behaviour.

#### Scenario: Older save migrates
- **WHEN** a save one schema version behind the current one is loaded
- **THEN** its data is migrated and the game is playable

#### Scenario: Missing migration is explicit
- **WHEN** a save requires a migration that is not registered
- **THEN** loading fails with a message naming the version range it cannot handle

### Requirement: Save integrity reporting
A load SHALL verify referenced identifiers and cross-references — routes to stations, trains to routes, stations to rail cells — and SHALL report structural problems rather than silently producing a broken game.

#### Scenario: Broken reference is reported
- **WHEN** a save references a route stop whose station is absent from the file
- **THEN** the load reports the inconsistency instead of crashing
