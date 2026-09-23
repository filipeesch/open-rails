class_name TestChromeLayout
extends TestBase

## Where the interface's bands actually land, in pixels, at the sizes the game ships at.
##
## This is the file that did not exist when the game was first played in a real
## window, and its absence is why two layout faults survived the whole suite.  The
## bottom toolbar was anchored to the bottom edge with an offset that put it a full
## band *below* the visible window — every button off-screen, and no test could see
## it, because a `Control` nobody has given a parent is a rectangle that never
## disagrees with anyone.  The code-built panels inside those bands were created in
## GDScript at the engine's default anchors and a size of zero, so each one
## collapsed onto its parent's top-left corner, which is where the date is drawn —
## so the ledger read as garbage.  Both faults are invisible to a unit test that
## asks a widget "what is your size" and gets back the number the widget itself
## decided.  What is graded here instead is the geometry the authored anchors and
## offsets *imply* at a given window size, which is the only question a player can
## tell the difference between.
##
## Nothing is added to a scene tree: a Control's anchors and offsets are data, and
## this arithmetic is the same arithmetic the layout pass performs.  Every size
## checked here is the design resolution or the documented minimum, not an
## abstraction over both.

const DESIGN_SIZE := Vector2(1920.0, 1080.0)
const MINIMUM_SIZE := Vector2(1280.0, 720.0)
const GAME_SCENE := preload("res://scenes/Game.tscn")
const GAME_ROOT_SCRIPT := preload("res://src/game_root.gd")

var _session: GameSession


func setup() -> void:
	_session = TestSession.create("founders_valley")


func teardown() -> void:
	if _session != null:
		TestSession.dispose(_session)
		_session = null


# --- the two authored bands ------------------------------------------------

func test_the_top_bar_is_one_band_across_the_top_and_no_taller() -> void:
	for size in [DESIGN_SIZE, MINIMUM_SIZE]:
		var bar := _authored_node("UI/TopBar")
		var rect := _implied_rect(bar, size)
		check_near(rect.position.x, 0.0, "the top bar runs from the left edge", 0.001)
		check_near(rect.position.y, 0.0, "and from the top edge", 0.001)
		check_near(rect.size.x, size.x, "the whole width, at %s" % _named(size), 0.001)
		check_near(rect.size.y, float(GameTheme.CHROME_BAND),
				"exactly one band deep, at %s" % _named(size), 0.001)
		bar.free()


func test_the_bottom_toolbar_is_on_the_bottom_edge_rather_than_below_it() -> void:
	for size in [DESIGN_SIZE, MINIMUM_SIZE]:
		var bar := _authored_node("UI/BottomToolbar")
		var rect := _implied_rect(bar, size)
		check_near(rect.size.y, float(GameTheme.CHROME_BAND),
				"the tool bar is one band deep, at %s" % _named(size), 0.001)
		check_near(rect.position.x, 0.0, "from the left edge", 0.001)
		check_near(rect.size.x, size.x, "to the right edge, at %s" % _named(size), 0.001)
		# The fault this line exists for: the band was anchored to the bottom edge
		# with no offset, so it started *at* the last pixel and ran the whole band
		# outside the window.  Five buttons, none of them reachable, in a scene that
		# loaded without complaint.
		check_near(rect.end.y, size.y, "and it ends on the last visible pixel, at %s" % _named(size), 0.001)
		check_lt(rect.position.y, size.y,
				"so at least some of it is on screen at %s" % _named(size))
		bar.free()


func test_the_two_bands_leave_the_valley_between_them_and_do_not_overlap() -> void:
	for size in [DESIGN_SIZE, MINIMUM_SIZE]:
		var top := _authored_node("UI/TopBar")
		var bottom := _authored_node("UI/BottomToolbar")
		var top_rect := _implied_rect(top, size)
		var bottom_rect := _implied_rect(bottom, size)
		check_le(top_rect.end.y, bottom_rect.position.y + 0.001,
				"the bands cannot be claiming the same pixel at %s" % _named(size))
		var free_ground := bottom_rect.position.y - top_rect.end.y
		check_gt(free_ground, size.y * 0.7,
				"and most of the window is still map at %s, not furniture" % _named(size))
		top.free()
		bottom.free()


func test_the_authored_band_depth_is_the_number_the_theme_says() -> void:
	# The scene file spells the depth out as a literal and the code reads it from
	# `GameTheme`.  Two places for one fact is drift waiting to happen — a band
	# that grows in code and not in the scene puts the labels under the bar — so
	# the drift itself is what fails here.
	var bar := _authored_node("UI/TopBar")
	var toolbar := _authored_node("UI/BottomToolbar")
	check_near(_implied_rect(bar, DESIGN_SIZE).size.y, float(GameTheme.CHROME_BAND),
			"the top band in the scene is as deep as the theme says", 0.001)
	check_near(_implied_rect(toolbar, DESIGN_SIZE).size.y, float(GameTheme.CHROME_BAND),
			"and so is the bottom one", 0.001)
	bar.free()
	toolbar.free()


func test_the_drawer_and_the_inspector_stand_clear_of_both_bands() -> void:
	for size in [DESIGN_SIZE, MINIMUM_SIZE]:
		for path in ["UI/ToolPanel", "UI/ContextInspector"]:
			var panel := _authored_node(String(path))
			var rect := _implied_rect(panel, size)
			check_ge(rect.position.y, float(GameTheme.CHROME_BAND),
					"%s starts below the ledger band at %s" % [path, _named(size)])
			check_le(rect.end.y, size.y - float(GameTheme.CHROME_BAND) + 0.001,
					"%s stops above the tool bar at %s" % [path, _named(size)])
			check_true(Rect2(Vector2.ZERO, size).encloses(rect),
					"%s is wholly inside the window at %s" % [path, _named(size)])
			panel.free()
		# The label layer keeps its own insets for the same reason, and they are
		# only meaningful if they are at least as generous as the bands.
		check_ge(float(MapLabels.INSIDE_TOP), float(GameTheme.CHROME_BAND),
				"a map name clears the top band by at least its own depth")
		check_ge(float(MapLabels.INSIDE_BOTTOM), float(GameTheme.CHROME_BAND),
				"and the bottom band by at least the same")


# --- the panels the code builds -------------------------------------------

func test_a_panel_built_in_code_fills_the_band_it_is_put_into() -> void:
	# The engine gives a `Control` created in GDScript top-left anchors and a size
	# of zero.  Parented into a band that spans the window, it clamps to its own
	# minimum size in the parent's corner — the HUD landing on the date it is
	# supposed to be drawing.  `game_root` has one helper for this and every code-
	# built panel goes through it, so the helper's promise is the layout's promise.
	var root = GAME_ROOT_SCRIPT.new()
	var panel := Control.new()
	root._fills_band(panel)
	check_near(panel.anchor_left, 0.0, "the helper anchors the left edge to the start", 0.001)
	check_near(panel.anchor_top, 0.0, "and the top", 0.001)
	check_near(panel.anchor_right, 1.0, "and the right to the end", 0.001)
	check_near(panel.anchor_bottom, 1.0, "and the bottom", 0.001)
	for size in [DESIGN_SIZE, MINIMUM_SIZE]:
		var rect := _implied_rect(panel, size)
		check_true(rect.is_equal_approx(Rect2(Vector2.ZERO, size)),
				"so the panel covers the band it was put in, at %s" % _named(size))
	panel.free()
	root.free()


func test_the_toast_box_reads_above_the_tool_bar_and_lets_the_cursor_through() -> void:
	for size in [DESIGN_SIZE, MINIMUM_SIZE]:
		var box := NotificationCenter.new()
		box.attach(_session)
		var rect := _implied_rect(box, size)
		check_true(rect.size.y > 0.0,
				("a toast box built in code has a height at %s, rather than collapsing "
				+ "to nothing in its parent's corner") % _named(size))
		check_true(Rect2(Vector2.ZERO, size).encloses(rect),
				"and the whole column is inside the window at %s" % _named(size))
		# Toasts are the one thing that must never eat camera input, and the box is
		# 320 x 216 px of window standing where the player is about to click.
		check_eq(box.mouse_filter, Control.MOUSE_FILTER_IGNORE,
				"a toast never swallows the input behind it")
		var band_top: float = size.y - float(GameTheme.CHROME_BAND)
		check_le(rect.end.y, band_top + 0.001,
				"the column stands clear of the tool bar at %s" % _named(size))
		var drawer := _authored_node("UI/ToolPanel")
		var drawer_rect := _implied_rect(drawer, size)
		check_ge(rect.position.x, drawer_rect.end.x,
				"and clear of the tool drawer, so the two never claim one pixel at %s"
				% _named(size))
		drawer.free()
		box.free()


# --- fixtures -------------------------------------------------------------

func _authored_node(path: String) -> Control:
	var scene := GAME_SCENE.instantiate()
	var control := scene.get_node_or_null(path) as Control
	check_true(control != null, "%s is in the scene and is a Control" % path)
	if control == null:
		# The case is already failing; hand back an unplaced Control so the rest of
		# the assertions report where else it would have gone wrong rather than
		# aborting the file on a null dereference.
		scene.free()
		return Control.new()
	# `instantiate()` without a parent runs no `_ready`, which is exactly what is
	# wanted: the anchors and offsets below are the ones the scene file states,
	# untouched by any layout pass — which is the fact under test.
	# Detach from whoever owns it in the scene so freeing the scene below cannot
	# free the node this case is still holding.
	control.get_parent().remove_child(control)
	scene.free()
	return control


## The rectangle a Control occupies inside a parent of `parent_size`, given the
## anchors and offsets it states.  This is the layout pass's own arithmetic, and
## the only layout question that can be answered without a window.
func _implied_rect(control: Control, parent_size: Vector2) -> Rect2:
	var left := control.anchor_left * parent_size.x + control.offset_left
	var top := control.anchor_top * parent_size.y + control.offset_top
	var right := control.anchor_right * parent_size.x + control.offset_right
	var bottom := control.anchor_bottom * parent_size.y + control.offset_bottom
	return Rect2(Vector2(left, top), Vector2(right - left, bottom - top))


func _named(size: Vector2) -> String:
	if size.is_equal_approx(DESIGN_SIZE):
		return "the design resolution"
	return "the documented minimum"
