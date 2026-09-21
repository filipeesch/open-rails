class_name TestViewCamera
extends TestBase

## Tasks 4.1 – 4.6: the orthographic isometric camera rig.
##
## The rig states its own view: `view_transform()`, `projection()`,
## `screen_to_ray()` and `project_point()` are the arithmetic the Camera3D is
## handed, so these cases measure the view itself rather than a screenshot of it.
## Pitch is the one number the whole visual language rests on, so nearly every
## case here re-reads it after driving a control.

var _view: TestView


func teardown() -> void:
	if _view != null:
		_view.dispose()
		_view = null


# --- 4.1 the canonical view -------------------------------------------------

func test_the_default_view_is_the_canonical_isometric() -> void:
	_view = TestView.stage()
	var rig := _view.rig
	var grid := _view.grid()
	check_eq(rig.camera.projection, Camera3D.PROJECTION_ORTHOGONAL, "the view is orthographic")
	check_near(rig.ortho_size, WorldConstants.CAMERA_ZOOM_DEFAULT, "at the canonical zoom", 0.0001)
	check_near(rig.yaw_degrees, WorldConstants.CAMERA_DEFAULT_YAW, "at the canonical yaw", 0.0001)
	check_near(rig.pitch_degrees(), WorldConstants.CAMERA_FIXED_PITCH,
		"and the canonical pitch, measured back out of the basis", 0.0001)
	check_near(rig.camera.size, rig.ortho_size, "the camera is set to the size the rig holds", 0.0001)
	_check_camera_holds_the_rigs_view(rig)
	check_near(rig.target.x, float(grid.width) * 0.5, "the view opens on the middle of the map", 0.0001)
	check_near(rig.target.z, float(grid.height) * 0.5, "on both axes", 0.0001)
	var centre := rig.project_point(rig.target, _view.rect())
	check_near(centre.x, 640.0, "and that point is dead centre on screen", 0.01)
	check_near(centre.y, 360.0, "on both axes", 0.01)


func test_orthographic_size_is_the_tiles_visible_down_the_screen() -> void:
	_view = TestView.stage()
	var rig := _view.rig
	var rect := _view.rect()
	var view := rig.view_transform()
	var top := rig.project_point(rig.target + view.basis.y * rig.ortho_size * 0.5, rect).y
	var bottom := rig.project_point(rig.target - view.basis.y * rig.ortho_size * 0.5, rect).y
	check_near(bottom - top, rect.size.y,
		"one orthographic size is exactly the height of the viewport: 28 tiles, 28 tiles down", 0.5)
	var aspect := rect.size.x / rect.size.y
	var right := rig.project_point(rig.target + view.basis.x * rig.ortho_size * aspect * 0.5, rect)
	var left := rig.project_point(rig.target - view.basis.x * rig.ortho_size * aspect * 0.5, rect)
	check_near(right.x - left.x, rect.size.x, "and the width follows the viewport's aspect", 1.0)
	check_near(right.y - left.y, 0.0, "a sideways move in view space stays on one screen row", 0.01)
	check_eq(rig.lod_level(), 1, "at 28 tiles across the rig reports the middle LOD")


# --- 4.2 smoothing, and snapping to exact detents --------------------------

func test_panning_settles_on_the_commanded_target_without_drift() -> void:
	_view = TestView.stage()
	var rig := _view.rig
	var start := rig.target
	rig.pan_tiles(Vector2(6.0, -4.0))
	check_near(rig.desired_target.x, start.x + 6.0, "the command is recorded", 0.0001)
	check_near(rig.desired_target.z, start.z - 4.0, "on both axes", 0.0001)
	rig.tick(TestView.FRAME)
	check_neq(rig.target, rig.desired_target, "the view is eased to it, not teleported")
	check_lt(absf(rig.target.x - start.x), absf(rig.desired_target.x - start.x) + 0.001,
		"and it approaches without overshooting")
	var travelled := 0.0
	for frame in 90:
		var before := rig.target.x
		rig.tick(TestView.FRAME)
		travelled += rig.target.x - before
	check_near(rig.target.x, rig.desired_target.x, "after a second it has arrived", 0.01)
	check_near(rig.target.z, rig.desired_target.z, "on both axes", 0.01)
	check_gt(travelled, 0.0, "and it moved the whole way in one direction")
	var arrived := rig.target
	for frame in 240:
		rig.tick(TestView.FRAME)
	check_near(rig.target.x, arrived.x, "four idle seconds later it has not crept", 0.001)
	check_near(rig.target.z, arrived.z, "in either axis", 0.001)


func test_snap_rotation_arrives_on_an_exact_45_degree_detent() -> void:
	_view = TestView.stage()
	var rig := _view.rig
	rig.snap_rotate(1.0)
	check_eq(rig.desired_yaw, 90.0, "one snap from the default yaw commands exactly ninety")
	_view.settle()
	check_near(rig.yaw_degrees, 90.0, "and the view arrives on it", 0.001)
	check_eq(rig.yaw_degrees, 90.0, "it lands on the detent exactly rather than almost on it")
	for step in 8:
		rig.snap_rotate(1.0)
	_view.settle()
	check_near(rig.yaw_degrees, 90.0, "eight snaps is a full turn: one detent from where it started", 0.001)
	check_ge(rig.desired_yaw, 0.0, "yaw stays wrapped into the positive range")
	check_lt(rig.desired_yaw, 360.0, "never above a full turn")
	rig.rotate_by(13.7)
	_view.settle(60)
	rig.snap_rotate(1.0)
	check_eq(rig.desired_yaw, 135.0, "from a hand-rotated yaw it takes the shortest path to the next detent")
	check_eq(fmod(rig.desired_yaw, WorldConstants.CAMERA_SNAP_DEGREES), 0.0,
		"the commanded angle is exactly on a detent, not close to one")
	_view.settle()
	check_near(rig.yaw_degrees, 135.0, "and it settles there", 0.001)
	check_near(rig.pitch_degrees(), WorldConstants.CAMERA_FIXED_PITCH, "rotation never touches the pitch", 0.0001)


# --- 4.3 logarithmic zoom --------------------------------------------------

func test_zoom_is_logarithmic_and_clamped_at_both_ends() -> void:
	_view = TestView.stage()
	var rig := _view.rig
	var sizes: Array[float] = []
	for step in 6:
		sizes.append(rig.desired_ortho_size)
		rig.zoom_by(1.0)
	var ratios: Array[float] = []
	for index in range(1, sizes.size()):
		ratios.append(sizes[index] / sizes[index - 1])
	check_gt(ratios[0], 1.0, "one wheel step out shows more of the map")
	var off := 0
	for index in range(1, ratios.size()):
		if absf(ratios[index] - ratios[0]) > 0.000001:
			off += 1
	check_eq(off, 0, "every step multiplies the size by the same factor: the zoom is logarithmic")
	for step in 60:
		rig.zoom_by(1.0)
	check_near(rig.desired_ortho_size, WorldConstants.CAMERA_ZOOM_FAR,
		"it stops at the far bound rather than flying off the map", 0.0001)
	_view.settle()
	check_near(rig.ortho_size, WorldConstants.CAMERA_ZOOM_FAR, "the view itself gets there too", 0.01)
	for step in 80:
		rig.zoom_by(-1.0)
	check_near(rig.desired_ortho_size, WorldConstants.CAMERA_ZOOM_CLOSE, "and at the close bound", 0.0001)
	_view.settle()
	check_near(rig.ortho_size, WorldConstants.CAMERA_ZOOM_CLOSE, "the view follows", 0.01)
	rig.set_zoom(5000.0)
	check_near(rig.desired_ortho_size, WorldConstants.CAMERA_ZOOM_FAR, "a commanded size over the range is clamped", 0.0001)
	rig.set_zoom(0.2)
	check_near(rig.desired_ortho_size, WorldConstants.CAMERA_ZOOM_CLOSE, "and one under it", 0.0001)


func test_zoom_without_an_anchor_leaves_the_target_defined() -> void:
	_view = TestView.stage()
	var rig := _view.rig
	# The input controller passes `Vector2.INF` for "the pointer is not over the
	# map", and the keyboard shortcuts pass no anchor at all.  Both have to zoom
	# without taking the anchor arithmetic anywhere near an infinity.
	rig.zoom_in()
	check_true(is_finite(rig.desired_target.x), "zooming in keeps the target finite")
	check_true(is_finite(rig.desired_target.z), "on both axes")
	rig.zoom_by(2.0, Vector2.INF, _view.rect())
	check_true(is_finite(rig.desired_target.x), "a wheel step with no anchor keeps it finite")
	check_true(is_finite(rig.target.z), "and the animated view with it")
	rig.set_zoom(40.0, Vector2.INF, _view.rect())
	check_true(is_finite(rig.desired_target.x), "a commanded zoom with no anchor too")
	_view.settle()
	check_near(rig.ortho_size, 40.0, "and the size still changes as asked", 0.01)
	check_near(rig.target.x, rig.desired_target.x, "while the target stays where it was", 0.01)


# --- 4.4 cursor-anchored zoom ---------------------------------------------

func test_zooming_keeps_the_tile_under_the_cursor_at_its_pixel() -> void:
	_view = TestView.stage()
	var rig := _view.rig
	var anchor_tile := Vector2i(134, 119)
	var anchor := Vector2(float(anchor_tile.x) + 0.5, float(anchor_tile.y) + 0.5)
	var point := _view.surface_point(anchor_tile)
	var before := rig.project_point(point, _view.rect())
	rig.zoom_by(-3.0, anchor, _view.rect())
	_view.settle()
	check_lt(rig.ortho_size, WorldConstants.CAMERA_ZOOM_DEFAULT - 4.0, "the view did zoom in")
	var zoomed_in := rig.project_point(point, _view.rect())
	check_near(zoomed_in.x, before.x, "the tile under the cursor is still under the cursor", 1.0)
	check_near(zoomed_in.y, before.y, "on both axes", 1.0)
	rig.zoom_by(3.0, anchor, _view.rect())
	_view.settle()
	check_near(rig.ortho_size, WorldConstants.CAMERA_ZOOM_DEFAULT, "and back out to the scale it started at", 0.5)
	var zoomed_out := rig.project_point(point, _view.rect())
	check_near(zoomed_out.x, before.x, "the same tile is pinned to the same pixel after the round trip", 1.5)
	check_near(zoomed_out.y, before.y, "on both axes", 1.5)
	var picked := _view.selection.pick_tile(before)
	check_eq(picked, anchor_tile, "and the pick at that pixel is still the tile it was before the zoom")


# --- 4.5 every control keeps the pitch -------------------------------------

func test_every_documented_control_leaves_the_pitch_at_35_264() -> void:
	_view = TestView.stage()
	var rig := _view.rig
	var rect := _view.rect()
	var bindings: PackedStringArray = PackedStringArray([
		"pan", "edge_pan", "keys_pan", "rotate_drag", "snap_left", "snap_right",
		"wheel_in", "wheel_out", "zoom_keys", "reset", "focus", "follow",
	])
	for binding in bindings:
		_drive(rig, binding, rect)
		_view.settle(40)
		check_near(rig.pitch_degrees(), WorldConstants.CAMERA_FIXED_PITCH,
			"the pitch is unchanged after " + binding, 0.0001)
		check_ge(rig.yaw_degrees, 0.0, "yaw stays in range after " + binding)
		check_lt(rig.yaw_degrees, 360.0, "and stays wrapped after " + binding)
		check_ge(rig.ortho_size, WorldConstants.CAMERA_ZOOM_CLOSE - 0.001,
			"zoom stays inside its bounds after " + binding)
		check_le(rig.ortho_size, WorldConstants.CAMERA_ZOOM_FAR + 0.001,
			"at both ends after " + binding)
		check_true(is_finite(rig.target.x) and is_finite(rig.target.z),
			"the view target stays defined through " + binding)
	_check_camera_holds_the_rigs_view(rig)


func test_each_control_moves_what_the_binding_says_it_moves() -> void:
	_view = TestView.stage()
	var rig := _view.rig
	var rect := _view.rect()

	rig.reset_view()
	var centre := rig.target
	rig.pan(Vector2(120.0, 0.0), 1.0)
	check_neq(rig.desired_target, centre, "a horizontal drag pans the view")
	check_near(rig.desired_target.y, centre.y, "and never changes its height", 0.0001)

	rig.reset_view()
	rig.pan_tiles(Vector2(4.0, 4.0))
	check_near(rig.desired_target.x - rig.target.x, 4.0, "the pan keys are measured in tiles", 0.0001)
	check_near(rig.desired_target.z - rig.target.z, 4.0, "on both axes", 0.0001)

	rig.reset_view()
	_view.settle()
	check_near(rig.yaw_degrees, WorldConstants.CAMERA_DEFAULT_YAW, "reset returns the default yaw", 0.01)
	check_near(rig.ortho_size, WorldConstants.CAMERA_ZOOM_DEFAULT, "the default zoom", 0.01)
	check_near(rig.target.x, 128.0, "and the middle of the map", 0.5)

	rig.rotate_by(30.0)
	check_near(rig.desired_yaw, 75.0, "a right-drag rotates by exactly the angle dragged", 0.0001)
	rig.snap_rotate(-1.0)
	check_eq(rig.desired_yaw, 45.0, "Q snaps to the detent below")
	rig.snap_rotate(1.0)
	check_eq(rig.desired_yaw, 90.0, "E snaps to the detent above")

	rig.reset_view()
	var before_size := rig.desired_ortho_size
	rig.zoom_by(2.0, Vector2(128.0, 128.0), rect)
	check_gt(rig.desired_ortho_size, before_size, "the wheel away shows more map")
	rig.reset_view()
	before_size = rig.desired_ortho_size
	rig.zoom_by(-2.0, Vector2(128.0, 128.0), rect)
	check_lt(rig.desired_ortho_size, before_size, "the wheel in shows less")
	rig.reset_view()
	before_size = rig.desired_ortho_size
	rig.zoom_in()
	check_lt(rig.desired_ortho_size, before_size, "the zoom-in key gets closer")
	rig.zoom_out()
	rig.zoom_out()
	check_gt(rig.desired_ortho_size, before_size, "the zoom-out key gets further")

	rig.reset_view()
	rig.focus_tile(Vector2(70.0, 152.0), true)
	check_near(rig.target.x, 70.0, "focus jumps the view to the tile asked for", 0.0001)
	check_near(rig.target.z, 152.0, "on both axes", 0.0001)


# --- 4.6 focus and follow --------------------------------------------------

func test_following_a_train_locks_the_view_and_a_pan_lets_go() -> void:
	_view = TestView.stage()
	var rig := _view.rig
	var line := TestSession.coal_line(_view.session)
	check_true(bool(line["ok"]), "a working coal line gives the rig something to follow")
	var train_id := int(line["train"])
	var trains: TrainService = _view.session.trains
	var start := trains.position_tiles(train_id)

	rig.focus_tile(Vector2(start.x, start.y), true)
	check_false(rig.is_following(), "focusing a tile is not following")
	rig.follow_train(train_id, Callable(trains, "position_tiles"))
	check_true(rig.is_following(), "following a train is reported as such")

	# The consist sits at the colliery until the mine has produced, the hopper has
	# loaded and the road is clear, so this runs the game's own loop — one tick,
	# one frame — until it actually moves rather than guessing how long that takes.
	var frames := 0
	var moved := start
	while frames < 5000 and moved.distance_to(start) < 4.0:
		_view.session.advance_ticks(1)
		rig.tick(TestView.FRAME)
		frames += 1
		moved = trains.position_tiles(train_id)
	check_lt(float(frames), 5000.0, "the train got under way inside two months of ticks")
	check_gt(moved.distance_to(start), 2.0, "and has travelled by the time the view has followed it")
	var offset := Vector2(rig.target.x - moved.x, rig.target.z - moved.y)
	check_lt(offset.length(), 2.0, "the view has kept itself on top of it")
	check_near(rig.yaw_degrees, WorldConstants.CAMERA_DEFAULT_YAW, "following leaves yaw alone", 0.0001)
	check_near(rig.ortho_size, WorldConstants.CAMERA_ZOOM_DEFAULT, "and leaves zoom alone", 0.0001)

	rig.zoom_by(1.0, Vector2(moved.x, moved.y), _view.rect())
	check_true(rig.is_following(), "zooming while following keeps following")
	for frame in 60:
		_view.session.advance_ticks(1)
		rig.tick(TestView.FRAME)
	offset = Vector2(rig.target.x - trains.position_tiles(train_id).x,
		rig.target.z - trains.position_tiles(train_id).y)
	check_lt(offset.length(), 2.0, "and the view is still on the train after the zoom")

	# Four times as many ticks per frame: the consist moves three and a half
	# times faster, and a locked view still has to stay locked.
	for frame in 60:
		_view.session.advance_ticks(4)
		rig.tick(TestView.FRAME)
	offset = Vector2(rig.target.x - trains.position_tiles(train_id).x,
		rig.target.z - trains.position_tiles(train_id).y)
	check_lt(offset.length(), 2.5, "at 4x speed the followed train is still under the view")

	rig.pan_tiles(Vector2(3.0, 0.0))
	check_false(rig.is_following(), "a manual pan cancels following")
	var held := rig.desired_target
	for frame in 60:
		_view.session.advance_ticks(1)
		rig.tick(TestView.FRAME)
	check_near(rig.desired_target.x, held.x, "the released view stays where the player left it", 0.0001)
	check_near(rig.desired_target.z, held.z, "while the train carries on without it", 0.0001)
	rig.stop_following()
	check_false(rig.is_following(), "and stopping a follow that already stopped is harmless")


# --- helpers ---------------------------------------------------------------

## The camera holds exactly the transform the rig computes: what the rig states
## is what the renderer draws.
func _check_camera_holds_the_rigs_view(rig: IsoCameraRig) -> void:
	var view := rig.view_transform()
	check_near(rig.camera.transform.origin.x, view.origin.x, "the camera sits where the rig says", 0.01)
	check_near(rig.camera.transform.origin.y, view.origin.y, "at the height it says", 0.01)
	check_near(rig.camera.transform.origin.z, view.origin.z, "and the distance it says", 0.01)
	check_near(rig.camera.transform.basis.z.dot(view.basis.z), 1.0, "and looks exactly where it says", 0.0001)


## One press of each documented binding, expressed as the call the input
## controller makes for it.
func _drive(rig: IsoCameraRig, binding: String, rect: Rect2) -> void:
	match binding:
		"pan":
			rig.pan(Vector2(90.0, -40.0), 1.0)
		"edge_pan":
			rig.pan(Vector2(18.0, 18.0) * 900.0 * TestView.FRAME, TestView.FRAME)
		"keys_pan":
			rig.pan_tiles(Vector2(2.0, -2.0))
		"rotate_drag":
			rig.rotate_by(37.0)
		"snap_left":
			rig.snap_rotate(-1.0)
		"snap_right":
			rig.snap_rotate(1.0)
		"wheel_in":
			rig.zoom_by(-2.0, Vector2(128.0, 128.0), rect)
		"wheel_out":
			rig.zoom_by(2.0, Vector2(130.0, 126.0), rect)
		"zoom_keys":
			rig.zoom_in()
			rig.zoom_out()
		"reset":
			rig.reset_view()
		"focus":
			rig.focus_tile(Vector2(100.0, 140.0))
		"follow":
			rig.follow_train(1, Callable())
			rig.tick(TestView.FRAME)
			rig.stop_following()
		_:
			push_warning("no driver for the binding " + binding)
