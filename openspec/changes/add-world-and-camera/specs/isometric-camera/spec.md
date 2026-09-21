# Spec Delta

## Purpose

Defines the orthographic isometric camera — projection, orientation, zoom, pan, focus and follow — and the desktop control scheme through which the player manipulates the map directly rather than steering a floating camera.

## ADDED Requirements

### Requirement: Orthographic isometric projection
The camera SHALL use an orthographic projection with a default yaw of 45 degrees and a pitch fixed at 35.264 degrees, and SHALL support full 360-degree horizontal rotation. The pitch SHALL NOT change during V1 gameplay.

#### Scenario: Default orientation is canonical
- **WHEN** a game view is created
- **THEN** yaw is 45 degrees and pitch is 35.264 degrees with an orthographic projection

#### Scenario: Pitch cannot be altered by input
- **WHEN** the player performs every camera control
- **THEN** pitch remains 35.264 degrees

### Requirement: Smooth rotation with discrete snapping
Rotation from continuous input SHALL be smoothed rather than jumping, while explicit snap actions SHALL move yaw to the nearest 45-degree position.

#### Scenario: Drag rotation is smoothed
- **WHEN** the player drags to rotate by thirty degrees
- **THEN** yaw interpolates toward the target across frames rather than teleporting

#### Scenario: Snap key moves exactly forty-five degrees
- **WHEN** the player presses the rotate-clockwise key
- **THEN** yaw becomes the current yaw plus exactly 45 degrees modulo 360

### Requirement: Logarithmic orthographic zoom
Zoom SHALL modify orthographic size, SHALL be logarithmic rather than linear, and SHALL span at least a closest view of about 4 tiles, a default of about 28 tiles and a furthest view of about 96 tiles. Zoom SHALL be clamped to its configured range.

#### Scenario: Equal input produces equal ratios
- **WHEN** the player scrolls the same amount twice from different zoom levels
- **THEN** the orthographic size changes by a comparable ratio rather than a fixed additive step

#### Scenario: Zoom is clamped
- **WHEN** the player scrolls past the closest or furthest limit
- **THEN** orthographic size stops changing at the limit

### Requirement: Cursor-anchored zoom
Wheel zoom SHALL keep the world position under the cursor as close as practical to the same screen position before and after the zoom change.

#### Scenario: Terrain under cursor stays under cursor
- **WHEN** the player zooms in with the cursor over a specific tile
- **THEN** that tile remains under the cursor within a small screen-space tolerance

### Requirement: Desktop camera controls
The camera SHALL respond to the documented desktop scheme: mouse wheel zoom, middle-mouse drag pan, right-mouse drag horizontal rotation, `Q` rotate minus 45 degrees, `E` rotate plus 45 degrees, `Home` reset to the canonical isometric view, `WASD` pan, double-click on an entity to focus it and `F` to focus the selected entity.

#### Scenario: Home restores the canonical view
- **WHEN** the player presses `Home` after panning and rotating away
- **THEN** yaw returns to 45 degrees and the smoothed targets reset to the canonical view

#### Scenario: Double-click focuses an entity
- **WHEN** the player double-clicks a station
- **THEN** the camera pans smoothly until that station is centred

#### Scenario: Keyboard panning moves the view
- **WHEN** the player holds `W`
- **THEN** the camera target moves in the direction consistent with the current yaw

### Requirement: Focus and follow
The camera SHALL support focusing an entity and following a train, preserving the current zoom and rotation while following. Any manual pan SHALL cancel follow mode.

#### Scenario: Follow preserves zoom and rotation
- **WHEN** the player follows a moving train
- **THEN** the camera target tracks the train while orthographic size and yaw remain under player control only

#### Scenario: Manual pan cancels follow
- **WHEN** the player pans while following a train
- **THEN** follow mode ends and the camera stays where the player left it

### Requirement: Camera behaviour is centralised
Camera behaviour SHALL live only in the camera system; UI features that need camera movement SHALL request it through that system rather than implementing their own motion.

#### Scenario: UI moves the camera by request
- **WHEN** a search result focuses a station
- **THEN** the request goes through the camera system and no UI component writes camera transform values directly
