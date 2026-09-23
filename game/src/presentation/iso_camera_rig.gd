class_name IsoCameraRig
extends Node3D

## The only camera system in the game: an orthographic isometric rig.
##
## Yaw is free, pitch is fixed at the canonical 35.264° so the isometric
## language never breaks.  Zoom is orthographic size — which also makes it the
## LOD proxy every renderer reads, because "how far away am I" is exactly how
## much of the map is on screen.

signal view_changed(orthographic_size: float, yaw: float)

const PITCH_DEGREES := WorldConstants.CAMERA_FIXED_PITCH
const YAW_SNAP := WorldConstants.CAMERA_SNAP_DEGREES
const ZOOM_CLOSE := WorldConstants.CAMERA_ZOOM_CLOSE
const ZOOM_DEFAULT := WorldConstants.CAMERA_ZOOM_DEFAULT
const ZOOM_FAR := WorldConstants.CAMERA_ZOOM_FAR

# --- the three presentation tiers, measured in tiles visible ----------------
#
# Tier selection is cut here because the rig owns the only distance question the
# game asks: `ortho_size` is how many tiles fit down the screen, so a threshold
# is a statement about how big a train looks, not about where an eye is standing.
# Every consumer — entity bodies, labels, effects — asks `lod_for_tiles()` and
# nothing else decides, so zooming out can never desync one layer from another.

const LOD_NEAR := 0
const LOD_MEDIUM := 1
const LOD_FAR := 2

## Fourteen tiles down the screen and a locomotive is a quarter of the picture:
## every part the compiler left in LOD0 — rods, lamps, window frames — is still
## several pixels wide, so drawing the part list is the honest answer.
const LOD_NEAR_MAX_TILES := 14.0
## The shipped working zoom is 28, so ordinary play sits in this band.  A consist
## is a few dozen pixels long here: LOD1's single merged body carries the whole
## shape and LOD0's twenty-odd separate drawables buy nothing a player can see.
## Past this bound is the overview the zoom-out key runs to (96 tiles), where only
## the silhouette reads — LOD2, no labels, no particles.
const LOD_MEDIUM_MAX_TILES := 44.0

const PAN_SMOOTHING := 12.0
const ZOOM_SMOOTHING := 9.0
const YAW_SMOOTHING := 8.0
const EDGE_ZONE := 18.0
const ZOOM_WHEEL_STEP := 0.14
## A single zoom command (a keypress, a palette entry, a HUD button) is worth this
## many wheel notches, so every zoom in the game is measured in the one unit
## `zoom_by` understands instead of a private factor per call site.
const ZOOM_COMMAND_NOTCHES := 2.5
## Below this much remaining turn, the view lands on the commanded angle instead
## of closing the last fraction of a degree forever.
const ANGLE_LANDING := 0.0005
## Part of a follow gap closed per frame, on top of the normal chase rate.
const FOLLOW_CLOSURE := 0.5
## How far back along the view axis the camera sits.  Orthographic projection
## makes this a pure clipping choice: `near` is negative so the frustum reaches
## past the target and nothing about the image depends on the distance.
const VIEW_DISTANCE := 320.0

var world: WorldGrid
var camera: Camera3D

var target := Vector3.ZERO
var desired_target := Vector3.ZERO
var yaw_degrees := WorldConstants.CAMERA_DEFAULT_YAW
var desired_yaw := WorldConstants.CAMERA_DEFAULT_YAW
var ortho_size := ZOOM_DEFAULT
var desired_ortho_size := ZOOM_DEFAULT
var edge_pan_speed := 34.0

var _following_id: int = 0
var _follow_lookup: Callable = Callable()


func _init() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	camera.near = -240.0
	camera.far = 1200.0
	camera.cull_mask = 0xFFFFFFFF
	add_child(camera)


func attach_grid(grid: WorldGrid) -> void:
	world = grid
	var centre := Vector2(grid.width, grid.height) * 0.5
	target = Vector3(centre.x, _height_at(centre), centre.y)
	desired_target = target
	desired_yaw = _nearest_snap(yaw_degrees)


func configure(grid: WorldGrid) -> void:
	attach_grid(grid)
	_apply()


func tick(delta: float) -> void:
	if _following_id != 0 and _follow_lookup.is_valid():
		var tile: Vector2 = _follow_lookup.call(_following_id)
		desired_target = Vector3(tile.x, _height_at(tile), tile.y)
	var weight := clampf(PAN_SMOOTHING * delta, 0.0, 1.0)
	if _following_id != 0:
		# A followed view is a locked view.  A fixed chase rate is fine at 1x and
		# leaves the consist walking off the edge at 4x, so the chase also closes
		# a fraction of whatever gap is left: smooth when it is tracking, firm
		# when the train or the clock has pulled away from it.
		weight = clampf(maxf(weight, target.distance_to(desired_target) * FOLLOW_CLOSURE), 0.0, 1.0)
	target = target.lerp(desired_target, weight)
	ortho_size = exp(lerpf(log(ortho_size), log(desired_ortho_size), clampf(ZOOM_SMOOTHING * delta, 0.0, 1.0)))
	yaw_degrees = _approach_angle(yaw_degrees, desired_yaw, YAW_SMOOTHING * delta)
	_apply()


func _apply() -> void:
	camera.size = ortho_size
	# The view is solved as pure arithmetic and written straight to the camera's
	# own transform.  `look_at_from_position` needs the node to be in a scene, and
	# a rig that cannot state its own transform outside a scene tree cannot be
	# tested, measured or rendered offscreen either.  The rig node itself never
	# moves, so its local transform is the world transform.
	camera.transform = view_transform()
	view_changed.emit(ortho_size, yaw_degrees)


## Where the camera is and which way it looks, derived from `target` and yaw
## alone.  Pitch comes from the canonical constant and nothing else.
func view_transform() -> Transform3D:
	var radians := deg_to_rad(yaw_degrees)
	var pitch := deg_to_rad(PITCH_DEGREES)
	var direction := Vector3(
		sin(radians) * cos(pitch),
		sin(pitch),
		cos(radians) * cos(pitch))
	return Transform3D(Basis.looking_at(direction * -1.0), target + direction * VIEW_DISTANCE)


## The pitch the view actually holds, measured back out of the basis rather than
## read from the constant.  Every control must leave this at 35.264.
func pitch_degrees() -> float:
	var forward := view_transform().basis.z * -1.0
	return -rad_to_deg(asin(clampf(forward.y, -1.0, 1.0)))


## The orthographic frustum for a viewport, in the same convention as
## `Camera3D.PROJECTION_ORTHOGONAL`: `size` is the vertical extent and the width
## follows the viewport's aspect.
func projection(viewport_size: Vector2) -> Projection:
	var half := _half_extents(viewport_size)
	return Projection.create_orthogonal(-half.x, half.x, half.y, -half.y, camera.near, camera.far)


func _half_extents(viewport_size: Vector2) -> Vector2:
	var half_y := ortho_size * 0.5
	var aspect := 1.0
	if viewport_size.y > 0.0:
		aspect = viewport_size.x / viewport_size.y
	return Vector2(half_y * aspect, half_y)


# --- controls -------------------------------------------------------------

## Screen-space pan in (x, y) pixels-per-second-ish units, rotated into world
## space so "up" always means "away from the player".
func pan(screen_delta: Vector2, delta_scale: float = 1.0) -> void:
	var radians := deg_to_rad(yaw_degrees)
	var forward := Vector3(-sin(radians), 0.0, -cos(radians))
	var right := Vector3(cos(radians), 0.0, -sin(radians))
	var scale := ortho_size * 0.0016 * delta_scale
	desired_target += right * screen_delta.x * scale + forward * (-screen_delta.y) * scale
	_clamp_target()
	_following_id = 0


func pan_tiles(delta: Vector2) -> void:
	desired_target.x += delta.x
	desired_target.z += delta.y
	_clamp_target()
	_following_id = 0


## Continuous rotation from a right-drag.
func rotate_by(degrees: float) -> void:
	desired_yaw = wrapf(desired_yaw + degrees, 0.0, 360.0)


## Q/E snap rotation: the shortest path to the next 45° detent.
func snap_rotate(direction: float = 1.0) -> void:
	desired_yaw = wrapf(_nearest_snap(desired_yaw) + YAW_SNAP * direction, 0.0, 360.0)


func reset_view() -> void:
	desired_yaw = WorldConstants.CAMERA_DEFAULT_YAW
	desired_ortho_size = ZOOM_DEFAULT
	if world != null:
		var centre := Vector2(world.width, world.height) * 0.5
		desired_target = Vector3(centre.x, _height_at(centre), centre.y)
	_following_id = 0


## Command a zoom, optionally keeping the world point under the cursor pinned.
## `anchor` is the terrain intersection in world XZ — the tile the pointer is
## over — and `viewport_rect` says which viewport it was picked from.
func set_zoom(tiles_visible: float, anchor: Vector2 = Vector2.INF, viewport_rect: Rect2 = Rect2()) -> void:
	var previous := desired_ortho_size
	var commanded := clampf(tiles_visible, ZOOM_CLOSE, ZOOM_FAR)
	desired_ortho_size = commanded
	# `Vector2.INF` is the caller's way of saying "no anchor" — it is what the
	# input controller passes when its pointer is not over the map.  It has to be
	# tested for rather than compared against, or the anchor arithmetic below runs
	# with infinities and leaves the target undefined.
	if not is_finite(anchor.x) or not is_finite(anchor.y):
		return
	if anchor.x < 0.0 or anchor.y < 0.0:
		return
	if viewport_rect.size.x <= 0.0 or viewport_rect.size.y <= 0.0:
		return
	if previous <= 0.0001:
		return
	# Cursor-anchored zoom, solved rather than nudged.  Under an orthographic
	# camera a world offset from the target appears divided by the orthographic
	# size, so scaling the target-to-anchor offset by the same ratio as the size
	# puts the anchor back at exactly the pixel it came from.  Zoom is not a pan:
	# it leaves follow mode alone.
	var ratio := commanded / previous
	var anchor_point := anchor_to_world(anchor)
	desired_target = anchor_point + (desired_target - anchor_point) * ratio
	_clamp_target()


## Turn the zoom handle by `steps` wheel notches.  The argument is stated in the
## rig's own unit, so a positive `steps` *widens* the view — more of the valley in
## frame, ground shrinking — and a negative one brings the ground closer.  Input
## handlers that mean "closer" pass a negative number; `zoom_in` is the name to
## reach for when there is no wheel-notch arithmetic to keep.
func zoom_by(steps: float, anchor: Vector2 = Vector2.INF, viewport_rect: Rect2 = Rect2()) -> void:
	var factor := exp(steps * ZOOM_WHEEL_STEP)
	set_zoom(desired_ortho_size * factor, anchor, viewport_rect)


func zoom_in() -> void:
	zoom_by(-ZOOM_COMMAND_NOTCHES)


func zoom_out() -> void:
	zoom_by(ZOOM_COMMAND_NOTCHES)


func focus_tile(tile: Vector2, instant: bool = false) -> void:
	desired_target = Vector3(tile.x, _height_at(tile), tile.y)
	_following_id = 0
	if instant:
		target = desired_target


func follow_train(train_id: int, lookup: Callable) -> void:
	_following_id = train_id
	_follow_lookup = lookup


func is_following() -> bool:
	return _following_id != 0


func stop_following() -> void:
	_following_id = 0


# --- projections ----------------------------------------------------------

func orthographic_tiles() -> float:
	return ortho_size


## Which tier a given zoom asks for.  Static because the answer depends on the
## commanded size alone, never on a rig instance: a renderer that has not been
## given a rig yet can still resolve a zoom against the same numbers.
static func lod_for_tiles(tiles_visible: float) -> int:
	if tiles_visible <= LOD_NEAR_MAX_TILES:
		return LOD_NEAR
	if tiles_visible <= LOD_MEDIUM_MAX_TILES:
		return LOD_MEDIUM
	return LOD_FAR


func lod_level() -> int:
	return lod_for_tiles(ortho_size)


func tile_to_world(tile: Vector2) -> Vector3:
	return Vector3(tile.x + 0.5, _height_at(tile + Vector2(0.5, 0.5)), tile.y + 0.5)


func anchor_to_world(anchor: Vector2) -> Vector3:
	return Vector3(anchor.x, _height_at(anchor), anchor.y)


func _height_at(point: Vector2) -> float:
	if world == null:
		return 0.0
	var tile := Vector2i(clampi(floori(point.x), 0, world.width - 1), clampi(floori(point.y), 0, world.height - 1))
	return world.elevation_at(tile)


## Where a world point lands on screen, in **pixels local to `viewport_rect`** —
## the unit every drawing layer works in, because a `Control` is positioned in
## pixels.  Points outside the rectangle return coordinates outside `0..size`,
## which is exactly how a caller decides that a place is offscreen: the numbers
## are pixel distances, so `screen.x > size.x` means "over the right edge", not
## "1.4 of a viewport away".
##
## A point behind the camera has no position on screen, and returns `Vector2.INF`
## rather than a mirrored lie: an orthographic camera still projects it, to the
## wrong side of the view, and a label placed there would name a place the player
## cannot see.  Callers test for it with `is_finite()`.
func world_to_screen(point: Vector3, viewport_rect: Rect2) -> Vector2:
	if viewport_rect.size.x <= 0.0 or viewport_rect.size.y <= 0.0:
		return Vector2.ZERO
	if _behind_view(point):
		return Vector2.INF
	# In a scene the camera's own matrix is authoritative; out of one — a headless
	# test, an offscreen pass — the identical arithmetic takes over, so the rig
	# can be measured instead of only looked at.
	var pixels := Vector2.ZERO
	if camera.is_inside_tree():
		pixels = camera.unproject_position(point)
	else:
		pixels = project_point(point, viewport_rect)
	return Vector2(pixels.x - viewport_rect.position.x, pixels.y - viewport_rect.position.y)


## Whether a world point stands behind the lens.  A camera looks down its own -Z,
## so a positive depth measured along its backward axis is behind it — and Godot
## exposes no `is_point_behind_camera` on `Camera3D` to be asked instead.  The rig's
## own transform answers, which is what lets the headless branch below make exactly
## the same promise as the live one.
func _behind_view(point: Vector3) -> bool:
	var view := view_transform()
	return view.basis.z.dot(point - view.origin) > 0.0


## The same position as a fraction of the viewport: `(0.5, 0.5)` is the middle of
## the frame, and a value outside `0..1` is offscreen.  This is what a hit test
## wants when it compares a pick radius in viewport terms; a thing that *draws*
## wants `world_to_screen`.
func viewport_fraction(point: Vector3, viewport_rect: Rect2) -> Vector2:
	if viewport_rect.size.x <= 0.0 or viewport_rect.size.y <= 0.0:
		return Vector2.ZERO
	var local := world_to_screen(point, viewport_rect)
	if not is_finite(local.x) or not is_finite(local.y):
		return local
	return Vector2(local.x / viewport_rect.size.x, local.y / viewport_rect.size.y)


## Pixel position of a world point inside `viewport_rect`, the exact inverse of
## `screen_to_ray`.
func project_point(point: Vector3, viewport_rect: Rect2) -> Vector2:
	if viewport_rect.size.x <= 0.0 or viewport_rect.size.y <= 0.0:
		return Vector2.ZERO
	var view := view_transform()
	var local := view.affine_inverse() * point
	var half := _half_extents(viewport_rect.size)
	return Vector2(
		viewport_rect.position.x + (local.x / half.x * 0.5 + 0.5) * viewport_rect.size.x,
		viewport_rect.position.y + (0.5 - local.y / half.y * 0.5) * viewport_rect.size.y)


## The camera ray behind a viewport pixel, as `{"origin": Vector3, "direction":
## Vector3}`.  Orthographic, so every ray is parallel to the view axis and only
## the origin moves; that is what makes a heightfield march cheap.
func screen_to_ray(screen: Vector2, viewport_rect: Rect2) -> Dictionary:
	if viewport_rect.size.x <= 0.0 or viewport_rect.size.y <= 0.0:
		return {}
	var view := view_transform()
	var half := _half_extents(viewport_rect.size)
	var across := (screen.x - viewport_rect.position.x) / viewport_rect.size.x * 2.0 - 1.0
	var down := 1.0 - (screen.y - viewport_rect.position.y) / viewport_rect.size.y * 2.0
	return {
		"origin": view * Vector3(across * half.x, down * half.y, 0.0),
		"direction": view.basis.z * -1.0,
	}


func camera3d() -> Camera3D:
	return camera


func _clamp_target() -> void:
	if world == null:
		return
	var margin := ortho_size * 0.5
	desired_target.x = clampf(desired_target.x, -margin, float(world.width) + margin)
	desired_target.z = clampf(desired_target.z, -margin, float(world.height) + margin)


func _nearest_snap(angle: float) -> float:
	return wrapf(roundf(angle / YAW_SNAP) * YAW_SNAP, 0.0, 360.0)


func _approach_angle(from: float, to: float, weight: float) -> float:
	var difference := wrapf(to - from + 180.0, 0.0, 360.0) - 180.0
	# A detent you never quite reach is not a detent: an exponential approach
	# leaves the view a hundredth of a degree off square forever.  Close enough is
	# landed on exactly, which is what makes a snapped view truly axis-aligned.
	if absf(difference) < ANGLE_LANDING:
		return to
	return wrapf(from + difference * clampf(weight, 0.0, 1.0), 0.0, 360.0)
