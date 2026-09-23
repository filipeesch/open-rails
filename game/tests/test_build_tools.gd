class_name TestBuildTools
extends TestBase

## Build mode as the player perceives it (spec 2.1 and 2.2): a palette of
## exactly the three tools a builder has, a pointer whose glyph says which one
## is in hand, a readout beside the cursor that quotes the domain's own verdict
## — and an Escape that gives up the half-done job before it gives up the mode.
##
## Everything runs with the panels orphaned, driven by signals the same events
## the window would send; nothing here needs a screen.

var view: TestView
var input: InputController
var notices: Array[String] = []


func setup() -> void:
	view = TestView.stage()
	input = InputController.new()
	input.attach(view.session, view.rig, view.selection)
	view.session.notice.connect(
		func(message: String, _severity: String) -> void: notices.append(message))
	notices = []


func teardown() -> void:
	input.free()
	view.dispose()
	view = null
	input = null
	notices = []


func test_the_build_palette_lists_exactly_rail_station_and_remove() -> void:
	var panel := ToolPanel.new()
	panel.attach(view.session, input)

	input.arm_rail()
	check_true(panel.visible, "arming a build tool opens the tool panel")
	var labels: PackedStringArray = []
	for child in panel.palette_box.get_children():
		labels.append(String((child as Button).text))
	check_eq(labels.size(), 3, "build mode offers exactly three tools")
	check_true(labels.has("Rail"), "one lays rail")
	check_true(labels.has("Station"), "one places stations")
	check_true(labels.has("Remove"), "one lifts it again")

	panel.remove_button.pressed.emit()
	check_eq(input.tool, InputController.TOOL_REMOVE, "the palette button arms the remove tool")
	check_true(panel.remove_button.button_pressed, "and the palette marks which tool is in hand")
	check_false(panel.rail_button.button_pressed, "the tool it replaced is no longer marked")

	panel.remove_button.pressed.emit()
	check_eq(input.tool, InputController.TOOL_NONE, "pressing the marked button puts the tool down")
	check_false(panel.visible, "and the drawer closes with it")
	panel.free()


func test_the_remove_tool_lifts_one_tile_and_pays_half_back() -> void:
	var line := TestSession.coal_line(view.session)
	check_true(bool(line["ok"]), "a coal line to shorten: " + String(line["reason"]))
	var panel := ToolPanel.new()
	panel.attach(view.session, input)
	input.arm_tool(InputController.TOOL_REMOVE)

	var path := view.session.routes.path_of(int(line["route"]))
	# A quarter of the way round the loop is mid-leg, clear of the station
	# access tiles that `removal_block` will not give up.
	var cut := Vector2i(int(path[maxi(1, path.size() / 4)].x),
			int(path[maxi(1, path.size() / 4)].y))
	check_true(view.session.rail.network.has_rail(cut), "the tile picked is laid track")

	input._update_ghost_at_mouse(_screen_of(cut))
	var tiles: Array[Vector2i] = [cut]
	var refund := view.session.builder.refund_for(tiles)
	check_eq(panel.state(), "ok", "the ghost says the tile may go")
	check_near(panel.cost(), -refund, "and prices it as money coming back, not a charge", 0.001)

	var cash_before: float = view.session.economy.cash
	var ledger_before: int = view.session.economy.recent(1).size()
	input.build_at(cut)

	check_false(view.session.rail.network.has_rail(cut), "the click lifts the tile")
	check_near(view.session.economy.cash - cash_before, refund,
			"and pays the standard half back", 0.001)
	var entries: Array = view.session.economy.recent(ledger_before + 1)
	var newest: EconomyService.Transaction = entries[0]
	check_true(newest.amount > 0.0, "the ledger records the lift as income")
	check_true(newest.description.contains("Removed 1 tile"),
			"and names what came off the ground")
	panel.free()


func test_the_remove_tool_refuses_a_stations_access_rail_and_says_so() -> void:
	var line := TestSession.coal_line(view.session)
	check_true(bool(line["ok"]), "a line with stations on it: " + String(line["reason"]))
	var panel := ToolPanel.new()
	panel.attach(view.session, input)
	input.arm_tool(InputController.TOOL_REMOVE)

	var path := view.session.routes.path_of(int(line["route"]))
	# Halfway round the loop the path arrives at the plant's own access tile —
	# the one kind of rail the domain will not surrender.
	var guarded := Vector2i(int(path[path.size() / 2].x), int(path[path.size() / 2].y))
	check_true(view.session.rail.network.has_rail(guarded), "the tile picked is laid track")

	input._update_ghost_at_mouse(_screen_of(guarded))
	check_eq(panel.state(), "invalid", "the ghost refuses the station's access rail")
	check_true(panel.cost_label.text.contains("uses this track for rail access"),
			"and says the domain's reason, not a generic no: " + panel.cost_label.text)
	check_true(panel.cost_label.text.contains("'"), "naming the station that depends on it")

	var cash_before: float = view.session.economy.cash
	input.build_at(guarded)
	check_true(view.session.rail.network.has_rail(guarded), "the click lifts nothing")
	check_near(view.session.economy.cash, cash_before,
			"and a refused removal moves no money", 0.001)
	var last_notice := notices[notices.size() - 1]
	check_true(last_notice.contains("uses this track for rail access"),
			"the refusal is spoken as plainly as it was ghosted")
	panel.free()


func test_escape_gives_up_the_half_built_line_before_it_leaves_build_mode() -> void:
	# Spec 2.1: one press cancels the operation before it exits build mode — a
	# player who hit Escape at a survey point wants out of the line, not out of
	# construction.
	input.arm_rail()
	input.rail_start = Vector2i(40, 40)

	input.cancel()
	check_eq(input.tool, InputController.TOOL_RAIL, "the rail tool is still in hand")
	check_eq(input.rail_start, Vector2i(-1, -1), "but the half-started run is gone")
	var last_notice := notices[notices.size() - 1]
	check_true(last_notice.contains("cancelled"), "and the game says what was cancelled")

	input.cancel()
	check_eq(input.tool, InputController.TOOL_NONE, "the second press is the way out")


func test_the_pointer_shows_a_plus_for_build_and_a_cross_for_removal() -> void:
	var cursor := CursorState.new()
	cursor.attach(input)
	check_eq(cursor.state(), CursorState.STATE_NORMAL, "at rest the pointer is the player's own")
	check_eq(cursor.applied(), CursorState.SHAPE_ARROW, "with the system arrow")

	input.arm_rail()
	check_eq(cursor.state(), CursorState.STATE_BUILD, "arming a builder changes the pointer")
	input.arm_tool(InputController.TOOL_REMOVE)
	check_eq(cursor.state(), CursorState.STATE_REMOVE, "and switching tools changes it again")

	input.cancel()
	check_eq(cursor.state(), CursorState.STATE_NORMAL, "Escape hands the arrow back")
	check_eq(cursor.applied(), CursorState.SHAPE_ARROW, "the restore is recorded, not just asked for")

	# Distinguishable at a glance, verified as pixels: the cross reaches the
	# corners the plus leaves empty, so the two can never be confused.
	var build := CursorState.shape_image(CursorState.SHAPE_BUILD)
	var removal := CursorState.shape_image(CursorState.SHAPE_REMOVE)
	check_true(build != null and removal != null, "both glyphs are drawn")
	var centre := CursorState.SIDE / 2
	check_true(build.get_image().get_pixel(centre, centre).a > 0.0,
			"both point at the tile in hand")
	check_near(removal.get_image().get_pixel(2, 2).a, 1.0, "the cross reaches its corners", 0.001)
	check_near(build.get_image().get_pixel(2, 2).a, 0.0, "the plus leaves them empty", 0.001)
	check_true(CursorState.shape_image(CursorState.SHAPE_ARROW) == null,
			"the normal state restores the system arrow rather than drawing its own")
	cursor.free()


func test_the_readout_counts_and_prices_the_ghost_where_the_cursor_is() -> void:
	var readout := GhostReadout.new()
	readout.attach(view.session, input)
	check_false(readout.visible, "with no tool armed there is nothing to read out")

	var run: Array[Vector2i] = []
	var plan := {}
	for probe in _flat_probes():
		var candidate: Array[Vector2i] = [probe, probe + Vector2i(1, 0), probe + Vector2i(2, 0)]
		var preview := view.session.builder.preview_rail(candidate[0], candidate[2])
		if bool(preview.get("ok", false)) and not bool(preview.get("expensive", false)):
			run = candidate
			plan = preview
			break
	check_eq(run.size(), 3, "a flat three-tile line exists to preview")

	input.arm_rail()
	input.rail_start = run[0]
	view.selection.hovered_tile = run[2]
	input._refresh_ghost()

	check_true(readout.visible, "the ghost brings the readout with it")
	check_eq(readout.count_label.text, "3 tiles", "the readout counts the geometry")
	check_eq(readout.cost_label.text, GameTheme.money(float(plan.get("cost", 0.0))),
			"and shows the planner's own price, not an estimate of it")
	check_eq(readout.status_label.text, "Legal here.", "with a verdict for the tile")

	var screen := _screen_of(run[1])
	input.cursor_moved.emit(screen)
	var wanted: Vector2 = screen + GhostReadout.OFFSET
	check_near(readout.global_position.distance_to(wanted), 0.0,
			"and it sits beside the cursor, not on top of the ghost", 0.01)

	input.cancel()
	check_false(readout.visible, "putting the tool away takes the readout with it")
	readout.free()


func test_a_station_ghost_states_the_straight_rail_requirement_next_to_the_cursor() -> void:
	# Spec 2.2's named case: a station ghost near rail that is not straight has
	# to say so in those words, beside the cursor — a "cannot build here" that
	# hides in a drawer is not an answer a player can act on.
	var readout := GhostReadout.new()
	readout.attach(view.session, input)
	input.arm_station()

	var site := Vector2i(-1, -1)
	var reason := ""
	for probe in _flat_probes():
		var anchor := probe - Vector2i(1, 0)
		var empty := view.session.builder.preview_station("small_station", anchor)
		if bool(empty.get("ok", false)):
			continue
		# A stub run along the yard's west side: the cells beside the yard are
		# dead ends, and the yard's own ground is where the platform would go.
		var stub: Array[Vector2i] = [probe + Vector2i(-2, 0), probe + Vector2i(-2, 1)]
		if not bool(view.session.builder.preview_track_run(stub).get("ok", false)):
			continue
		var third: Array[Vector2i] = [probe + Vector2i(-2, 2)]
		if not bool(view.session.builder.preview_track_run(third).get("ok", false)):
			continue
		# Lay the stub as committed code, then ask the domain — never the grid —
		# what it makes of a station next to it.
		view.session.builder.build_track_run(stub)
		var stubbed := view.session.builder.preview_station("small_station", anchor)
		var crooked := String(stubbed.get("reason", ""))
		if bool(stubbed.get("ok", false)) or not crooked.begins_with("Requires a straight rail run beside"):
			# Wrong ground: put the stub back and look elsewhere.
			view.session.undo.undo()
			continue
		# Accept only ground that becomes buildable when the stub is straightened
		# — otherwise some second complaint (water, town) would be judged next.
		view.session.builder.build_track_run(third)
		if bool(view.session.builder.preview_station("small_station", anchor).get("ok", false)):
			reason = crooked
			site = probe
			# Take the straightening back: the case must watch the cursor-side
			# ghost change state, not inherit the verdict from this probe.
			view.session.undo.undo()
			break
		view.session.undo.undo()
		view.session.undo.undo()

	check_true(site != Vector2i(-1, -1), "a stub of dead-end track was laid to stand beside")
	check_true(view.session.rail.network.has_rail(site + Vector2i(-2, 1)),
			"rail really is beside the yard, so the complaint cannot be about none")

	input._update_ghost_at_mouse(_screen_of(site))
	check_true(readout.visible, "the ghost readout speaks next to the cursor")
	check_eq(readout.count_label.text, "6 tiles", "it first says what the station would cover")
	check_eq(readout.status_label.text, reason,
			"the readout quotes the domain's sentence verbatim")
	check_true(readout.status_label.text.begins_with("Requires a straight rail run beside"),
			"the straight-rail requirement is stated as the straight-rail requirement")

	var straight: Array[Vector2i] = [site + Vector2i(-2, 2)]
	view.session.builder.build_track_run(straight)
	input._update_ghost_at_mouse(_screen_of(site))
	check_eq(readout.status_label.text, "Legal here.",
			"straighten the same rail and the same ghost flips unaided")
	readout.free()


## The rail preview has to be seen on the ground it would cover, in the colour the
## domain earned: a number beside the cursor says a line is legal, but only the
## ghost in the world shows a player where the line actually goes.
func test_the_rail_ghost_is_drawn_in_the_world_in_the_domain_s_own_colour() -> void:
	var rails := RailRenderer.new()
	view.host.add_child(rails)
	rails.attach(view.session.world, view.session.rail)
	rails.attach_build_controller(input)

	var start := Vector2i(-1, -1)
	for probe in _flat_probes():
		var run: Array[Vector2i] = [probe, probe + Vector2i(0, 1), probe + Vector2i(0, 2)]
		if bool(view.session.builder.preview_track_run(run).get("ok", false)):
			start = probe
			break
	check_true(start != Vector2i(-1, -1), "a stretch of ground accepts three tiles")
	var end := start + Vector2i(0, 2)

	input.arm_rail()
	input.build_at(start)
	var screen := _screen_of(end)
	view.selection.point_at(screen)
	input._update_ghost_at_mouse(screen)

	var plan := view.session.builder.preview_rail(start, end)
	check_true(bool(plan.get("ok", false)),
			"the line being previewed is legal: " + String(plan.get("reason", "")))
	check_eq(str(rails.ghost_tiles()), str(Array(plan["tiles"])),
			"the world draws exactly the cells the next click would lay")
	check_true(rails.ghost_geometry() != null, "as geometry, not only as a number in a panel")
	_colour_close(_ghost_colour(rails), RailRenderer.COLOUR_GHOST_OK,
			"a legal line is drawn in the green the domain asked for")
	check_true(rails.ghost_material.vertex_color_use_as_albedo,
			"the material reads the verdict baked into those vertices")
	check_eq(rails.ghost_material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA,
			"and it is see-through, because it is a promise about ground")

	# The other end of the palette, on ground that simply has nothing to lift.
	var bare := start + Vector2i(6, 0)
	check_false(view.session.rail.network.has_rail(bare), "the tile chosen carries no track")
	input.arm_tool(InputController.TOOL_REMOVE)
	var bare_screen := _screen_of(bare)
	view.selection.point_at(bare_screen)
	input._update_ghost_at_mouse(bare_screen)
	_colour_close(_ghost_colour(rails), RailRenderer.COLOUR_GHOST_BAD,
			"an invalid preview turns the same geometry red")

	# The station tool asks for a different picture entirely — a yard and its
	# reach — so the rail layer has to give the ground back rather than draw a
	# second, wrong ghost over it.
	input.arm_station()
	check_true(rails.ghost_geometry() == null,
			"a station's ghost is a yard and a reach, not a run of sleepers")


## Vertex colours are stored as bytes, so the tint that reaches the shader is the
## authored one rounded to 1/255.  Judged at that tolerance rather than asking the
## mesh for a float it cannot hold.
func _colour_close(colour: Color, expected: Color, message: String) -> void:
	check_near(colour.r, expected.r, "%s (red)" % message, 0.01)
	check_near(colour.g, expected.g, "%s (green)" % message, 0.01)
	check_near(colour.b, expected.b, "%s (blue)" % message, 0.01)
	check_near(colour.a, expected.a, "%s (alpha)" % message, 0.01)


## The colour the ghost's first vertex carries — the verdict as the GPU sees it.
func _ghost_colour(rails: RailRenderer) -> Color:
	var mesh := rails.ghost_geometry()
	if mesh == null:
		return Color(0, 0, 0, 0)
	return (mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray)[0]


## Screen pixels for the middle of a tile, by the rig's own projection — the
## exact inverse of `screen_to_ray`, which is what a pointer event travels.
## (`world_to_screen` returns the same position normalised to 0..1, not pixels;
## feeding that back into the picker would point at a different tile entirely.)
func _screen_of(tile: Vector2i) -> Vector2:
	return view.rig.project_point(
			view.rig.tile_to_world(Vector2(tile)), view.rect())


## A fixed ladder of probe tiles, in one deterministic order, well away from
## the coal line's own ground.  Cases stop at the first probe whose terrain the
## domain accepts; which probe wins is the suite's business, not the player's.
func _flat_probes() -> Array[Vector2i]:
	var probes: Array[Vector2i] = []
	for y in range(96, 132):
		for x in range(96, 132):
			probes.append(Vector2i(x, y))
	return probes

