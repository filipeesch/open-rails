# Spec Delta

## Purpose

Defines the player-facing shell — menus, HUD, toolbar, inspector, tools, search, labels, notifications and settings — and the interaction rules keeping the map as the primary surface.

## ADDED Requirements

### Requirement: Main menu
The game SHALL present a main menu offering Continue, New Sandbox, Load Game, Settings and Quit. Continue SHALL be disabled when no autosave exists.

#### Scenario: Continue disabled without an autosave
- **WHEN** the menu is opened on a fresh install
- **THEN** Continue is present but disabled and the other entries are usable

#### Scenario: Continue resumes the last autosave
- **WHEN** an autosave exists and the player chooses Continue
- **THEN** the game loads that save at the state it recorded

### Requirement: New sandbox screen
The game SHALL provide a New Sandbox screen selecting Founder's Valley, accepting a company name, showing the starting year 1850 and starting the game on activation.

#### Scenario: Blank company name still starts a game
- **WHEN** the player starts without typing a company name
- **THEN** a generated default name is used and the sandbox begins

### Requirement: Permanent top bar and bottom toolbar
The in-game interface SHALL keep the map as nearly the entire screen with a permanent top bar showing date, cash, monthly profit and speed controls, and a permanent bottom toolbar offering Build, Stations, Trains, Company and World. Large permanent sidebars SHALL NOT be used.

#### Scenario: Top bar reflects money changes
- **WHEN** a delivery pays revenue
- **THEN** the displayed cash and monthly profit update without reopening any panel

#### Scenario: Speed controls are always reachable
- **WHEN** the player is anywhere in the UI
- **THEN** pause, 1x, 2x and 4x can be activated

### Requirement: Context inspector
A right-side inspector SHALL appear only when something is selected and SHALL present train, station, industry or town context appropriate to the selection, including actions such as editing a consist, opening the route, following a train and renaming a station.

#### Scenario: Train selection shows train context
- **WHEN** a train is selected
- **THEN** the inspector shows model, speed, cargo load, route and current-month revenue

#### Scenario: Empty selection hides the inspector
- **WHEN** nothing is selected
- **THEN** no inspector panel occupies screen space

### Requirement: Build mode and escape back-out
Selecting Build SHALL open a left tool palette offering Rail, Station and Remove and change the cursor state. Escape SHALL cancel the current operation, and a second Escape SHALL exit build mode.

#### Scenario: Two escapes leave build mode
- **WHEN** the player presses Escape during an active rail drag and Escape again
- **THEN** the drag is cancelled first and build mode exits on the second press

### Requirement: Ghost previews and explained failures
Every construction action SHALL show ghost geometry with cost and validity before commitment, and an invalid action SHALL explain its reason adjacent to the cursor in specific terms rather than reporting a generic failure.

#### Scenario: Specific reason is displayed
- **WHEN** a station ghost sits beside curved rail while straight rail is required
- **THEN** the message states that straight rail is required

### Requirement: Search and command palette
`Ctrl+K` SHALL open a palette searching stations, trains, towns and industries and offering commands such as build rail, new train, save game and finance. Choosing a world entity SHALL focus the camera on it.

#### Scenario: Search result focuses the map
- **WHEN** the player selects a town from search results
- **THEN** the camera focuses that town

### Requirement: Hover tooltips and zoom-dependent labels
Hover SHALL show lightweight information for trains, industries and stations without replacing selection, and map labels SHALL appear by zoom level — towns and major industries when far, towns plus stations and industries at medium, reduced to selected entities when close.

#### Scenario: Labels clear out at close zoom
- **WHEN** the player zooms to the closest level with nothing selected
- **THEN** unselected map labels are hidden

### Requirement: Non-blocking notifications
The game SHALL surface non-blocking notifications for events such as unreachable destinations, insufficient funds, full industry storage and save completion, avoiding modal alerts during normal play, and errors relating to a selected object SHALL also appear in its inspector.

#### Scenario: Insufficient funds notifies rather than blocks
- **WHEN** a purchase is refused for lack of cash
- **THEN** a dismissible notification appears and the player can continue acting immediately

### Requirement: Settings and UI scaling
The game SHALL expose master, music and effects volume, resolution, fullscreen, UI scale, camera pan speed, rotation speed, zoom speed and edge scrolling. UI scale SHALL support 100, 125, 150, 175 and 200 percent, the minimum supported resolution SHALL be 1280 × 720 and the primary design resolution SHALL be 1920 × 1080. Settings SHALL persist between sessions.

#### Scenario: UI scale is applied immediately
- **WHEN** the player changes UI scale to 150 percent
- **THEN** interface elements resize without a restart

#### Scenario: Critical feedback is not colour-only
- **WHEN** an invalid construction is shown
- **THEN** the feedback combines colour with an icon or text

### Requirement: UI observes simulation through events
UI SHALL reflect state by subscribing to domain events and reading service queries, and simulation SHALL NOT invoke UI components.

#### Scenario: No upward coupling
- **WHEN** the domain test suite runs without any UI loaded
- **THEN** a full gameplay month executes without error
