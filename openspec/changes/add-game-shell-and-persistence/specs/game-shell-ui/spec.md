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
The in-game interface SHALL keep the map as nearly the entire screen with a permanent top bar showing date, cash, monthly profit and speed controls, and a permanent bottom toolbar offering Build, Stations, Trains, Company and World. Each entry SHALL perform its own named act: the tool entries arm their tool and the panel entries open the screen they name. Large permanent sidebars SHALL NOT be used.

#### Scenario: Top bar reflects money changes
- **WHEN** a delivery pays revenue
- **THEN** the displayed cash and monthly profit update without reopening any panel

#### Scenario: Speed controls are always reachable
- **WHEN** the player is anywhere in the UI
- **THEN** pause, 1x, 2x and 4x can be activated

#### Scenario: World opens the valley screen
- **WHEN** the player presses World
- **THEN** a screen lists every town with its population, its monthly generation and whether a station reaches it, and every industry with what it produces or takes and its stock on hand

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
`Ctrl+K` SHALL open a palette searching stations, trains, towns and industries and offering commands such as build rail, new train, save game and finance. Choosing a world entity SHALL focus the camera on it. The palette's list SHALL describe the world currently in play, so an entity that no longer exists is not offered. Enter SHALL run the topmost match, and a command that writes or reads disk SHALL report the verdict it was given rather than announcing success.

#### Scenario: Search result focuses the map
- **WHEN** the player selects a town from search results
- **THEN** the camera focuses that town

#### Scenario: Enter takes the top match
- **WHEN** the player types a few letters and presses Enter without clicking a row
- **THEN** the first result is performed

#### Scenario: A demolished yard leaves the list
- **WHEN** a station the palette was offering is removed
- **THEN** the palette no longer offers to focus it

#### Scenario: A refused load is not reported as a load
- **WHEN** the load command is given a file it cannot read
- **THEN** the game states what failed and does not claim the valley was loaded

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
The game SHALL expose master, music and effects volume, resolution, fullscreen, UI scale, camera pan speed, rotation speed, zoom speed and edge scrolling. UI scale SHALL support 100, 125, 150, 175 and 200 percent, the minimum supported resolution SHALL be 1280 × 720 and the primary design resolution SHALL be 1920 × 1080. Settings SHALL persist between sessions. The screen SHALL be reachable from the
valley by a key as well as by name, and Escape SHALL dismiss it first while it is
open.

#### Scenario: UI scale is applied immediately
- **WHEN** the player changes UI scale to 150 percent
- **THEN** interface elements resize without a restart

#### Scenario: Critical feedback is not colour-only
- **WHEN** an invalid construction is shown
- **THEN** the feedback combines colour with an icon or text

#### Scenario: Options are reachable from the valley
- **WHEN** the player is in play and presses the options key
- **THEN** the options screen opens over the valley, and Escape puts it down again without touching the tool or the panels beneath it

### Requirement: UI observes simulation through events
UI SHALL reflect state by subscribing to domain events and reading service queries, and simulation SHALL NOT invoke UI components.

#### Scenario: No upward coupling
- **WHEN** the domain test suite runs without any UI loaded
- **THEN** a full gameplay month executes without error

### Requirement: Every control performs its own label
Every control the interface builds SHALL do the act its own text, tooltip or advertised key promises, and a control whose verb belongs to another screen or to the camera SHALL be wired by the composition root that owns both. A control that cannot perform its act SHALL NOT be built. Pressing any control in the shipped interface SHALL be covered by a test that presses it and reads the state it claims to change.

#### Scenario: A build-ready readout offers a build that builds
- **WHEN** a tool is armed, the ghost stands on a place that can take it and the player presses the readout's button
- **THEN** the construction is committed at the ghost's tile, and the button is labelled as a build only while it is one

#### Scenario: No button ships wired to nothing
- **WHEN** the shipped screens are walked for every control they build
- **THEN** each control is connected to a handler, and no handler is empty

#### Scenario: Escape is one ladder, not several
- **WHEN** the player presses Escape with the options screen, a drawer and a tool all standing
- **THEN** the topmost of them is put down, one press per layer, and a drawer's own close control leaves the shared panel state agreeing that it is closed

### Requirement: Advertised shortcuts are read from the bindings
Any key or shortcut shown to the player SHALL be derived from the InputMap action that performs the act, not from text remembered by the widget. Where an action has no binding the control SHALL show no shortcut at all rather than an invented one, and no action SHALL be bound to a key the interface engine consumes for its own use.

#### Scenario: A tooltip's letter is the bound letter
- **WHEN** a control advertises a shortcut and the binding is read from the engine
- **THEN** the shown letter and the bound letter are the same

#### Scenario: An unbound verb says nothing
- **WHEN** a toolbar entry's action has no key bound to it
- **THEN** its tooltip names the act and no key
