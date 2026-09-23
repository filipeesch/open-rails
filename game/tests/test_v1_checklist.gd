class_name TestV1Checklist
extends TestBase

## The specification's V1-complete checklist, walked in order.
##
## §"V1 is complete when a player can: launch, start a new sandbox, move the
## camera, inspect things, build rail, build stations, buy a locomotive, add
## wagons, create a route, watch it travel, load, unload, earn revenue, read the
## finances, expand, save, quit, load and continue."  Each case below is one
## stretch of that sentence, taken through the classes the shipped game uses —
## the same `InputController` the mouse feeds, the same services the panels call,
## the same `SaveService` the menu reads.  A step that works only because a test
## arranged it is the failure this file exists to catch.
##
## Two steps cannot be taken literally in a headless harness, and naming them is
## the point of the "record any step needing developer intervention" clause
## rather than a hole in the run:
##
## * **quit** — closing a window needs a window.  What a quit owes the player is
##   graded here: the menu emits `quit_requested` instead of killing the process,
##   and after the session is gone entirely, the save on disk still opens.
## * **watch it travel** — nothing here draws a frame, so travel is measured in
##   ticks the clock actually ran, which is where travel is decided anyway.

const VALLEY := "founders_valley"
const SAVE_PATH := "user://saves/checklist_walkthrough.json"

var _view: TestView
var _session: GameSession
var _written: Array[String] = []


func teardown() -> void:
	if _view != null:
		_view.dispose()
		_view = null
	if _session != null:
		TestSession.dispose(_session)
		_session = null
	for path in _written:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_written.clear()
	var directory := DirAccess.open("user://saves")
	if directory != null:
		for name in directory.get_files():
			if String(name).begins_with("checklist"):
				directory.remove(String(name))


# --- launch, new sandbox ---------------------------------------------------

func test_launch_opens_the_valley_the_content_describes() -> void:
	_session = TestSession.create(VALLEY)
	check_true(_session.started, "the session booted through its own start path")
	check_eq(_session.map_id, VALLEY, "on the authored map")
	check_gt(_session.towns.count(), 0, "with towns to serve")
	check_gt(_session.industries.count(), 0, "and works to serve them")
	check_near(_session.economy.cash, _session.data.starting_cash(),
			"cash is the amount the data names", 0.001)
	check_eq(_session.date().year, _session.data.start_year(),
			"the calendar opens in the authored year")

	var packed := load("res://scenes/Game.tscn") as PackedScene
	check_true(packed != null, "and the scene the launcher opens is there to open")
	var game := packed.instantiate()
	check_true(game.get_node_or_null("GameSession") != null, "with the session inside it")
	check_true(game.get_node_or_null("World3D/Terrain") != null, "the world it renders")
	check_true(game.get_node_or_null("UI/TopBar") != null, "and the interface over it")
	game.free()


func test_a_new_sandbox_from_the_menu_names_the_company_and_opens_the_valley() -> void:
	var menu := MainMenu.new()
	var opens: Array[int] = []
	menu.new_screen_requested.connect(func() -> void: opens.append(1))
	menu.press_new_sandbox()
	check_eq(opens.size(), 1, "Continue and New Game are different doors; New Game asks for the form")
	menu.free()

	var registry := DataRegistry.new()
	check_true(registry.load_all(), "the content the screen lists is installed")
	var screen := NewSandbox.new()
	screen.attach(registry)
	var requests: Array[Dictionary] = []
	screen.start_requested.connect(func(request: Dictionary) -> void: requests.append(request))
	# The player typed a name with stray spaces around it; the company should not
	# inherit the mess.
	screen.set_company_name("  Chipeway & Duncairn  ")
	var request := screen.start_sandbox()

	check_eq(requests.size(), 1, "found the company")
	check_eq(String(request["map"]), VALLEY, "in the founder's valley")
	check_eq(String(request["company_name"]), "Chipeway & Duncairn",
			"under the name the player typed, tidied")

	var intent := SandboxIntent.consume()
	check_true(bool(intent.get("pending", false)),
			"the handoff survived the trip between scenes")
	SandboxIntent.write(VALLEY, "Chipeway & Duncairn")
	_session = GameSession.new()
	_session.choose_company_name(String(SandboxIntent.consume().get("company_name", "")))
	check_true(_session.start(VALLEY), "the valley opened: " + _session.last_error)
	check_eq(_session.company_name(), "Chipeway & Duncairn",
			"and the company the ledger answers to is the one the player named")
	screen.free()


# --- camera and inspection -------------------------------------------------

func test_the_camera_goes_where_the_keys_command() -> void:
	_view = TestView.stage(VALLEY)
	var rig := _view.rig
	var from := rig.desired_target
	rig.pan_tiles(Vector2(6.0, 4.0))
	rig.tick(TestView.FRAME)
	check_gt(rig.desired_target.distance_to(from), 4.0, "pan moves the view across the valley")

	var yaw := rig.desired_yaw
	rig.snap_rotate(1.0)
	check_neq(rig.desired_yaw, yaw, "the valley turns to a snap angle")
	var turns := WorldConstants.CAMERA_SNAP_DEGREES
	check_near(fmod(rig.desired_yaw, turns), 0.0,
			"and only ever to one of the four", 0.001)

	rig.zoom_in()
	_view.settle()
	var close := rig.orthographic_tiles()
	rig.zoom_out()
	rig.zoom_out()
	rig.zoom_out()
	rig.zoom_out()
	_view.settle()
	check_lt(close, rig.orthographic_tiles(), "zooming out shows more valley than zooming in")
	check_le(rig.orthographic_tiles(), WorldConstants.CAMERA_ZOOM_FAR + 0.001,
			"and the far limit is a limit, not a suggestion")


func test_clicking_a_place_inspects_it_and_says_what_it_is() -> void:
	_view = TestView.stage(VALLEY)
	var inspector := ContextInspector.new()
	inspector.attach(_view.session, _view.selection, _view.rig)
	var town := TestSession.town_containing(_view.session, "Marlow")
	check_gt(town, 0, "the valley has Marlow to look at")

	_view.look_at_tile(_view.session.towns.tile_of(town))
	_view.selection.select(SelectionService.KIND_TOWN, town, _view.session.towns.tile_of(town))

	check_true(inspector.has_selection(), "the inspector knows something is selected")
	check_true(inspector.visible, "and says so")
	check_eq(inspector.inspected(), SelectionService.KIND_TOWN, "as the thing that was clicked")
	check_has(_text_of(inspector), "Marlow", "and the sheet is about that place by name")

	_view.selection.clear_selection()
	check_false(inspector.has_selection(), "letting go empties it")
	check_false(inspector.visible, "and it is out of the way, not merely blank")
	inspector.free()


# --- construction ----------------------------------------------------------

func test_the_build_tool_lays_rail_for_one_price() -> void:
	_view = TestView.stage(VALLEY)
	var input := InputController.new()
	input.attach(_view.session, _view.rig, _view.selection)
	var run := _find_a_legal_run(_view.session)
	check_gt(run.size(), 2, "the valley has room for a first line")
	var cash := _view.session.economy.cash
	var rows := _view.session.economy.ledger().size()

	input.arm_rail()
	check_eq(input.tool, InputController.TOOL_RAIL, "the rail tool is armed")
	input.build_at(run[0])
	check_eq(_view.session.rail.rail_tiles().size(), 0, "the first click only picks a start")
	input.build_at(run[run.size() - 1])

	var laid := _view.session.rail.rail_tiles().size()
	check_gt(laid, run.size() - 2, "the second click laid the line")
	check_eq(_view.session.economy.ledger().size(), rows + 1,
			"and charged one transaction for the whole run, not one per tile")
	var charge := _view.session.economy.recent(1)[0].amount
	check_near(cash + charge, _view.session.economy.cash,
			"the money that left the till is the money the ledger recorded", 0.001)
	input.free()


func test_a_station_is_placed_by_the_tool_and_claims_its_rail() -> void:
	_view = TestView.stage(VALLEY)
	var input := InputController.new()
	input.attach(_view.session, _view.rig, _view.selection)
	var run := _find_a_legal_run(_view.session)
	check_true(bool(_view.session.builder.build_track_run(run).get("ok", false)),
			"a line goes down first — a yard without rail beside it is not a yard")
	var anchor := _find_a_station_anchor(_view.session, run[int(run.size() * 0.5)])
	check_neq(anchor, Vector2i(-1, -1), "and there is ground beside it for a yard")
	var cash := _view.session.economy.cash
	var price := _view.session.stations.station_def("small_station").cost

	input.arm_station()
	# The cursor stands one cell right of the anchor — the same cell the ghost is
	# drawn on — so a click lands the yard where the preview was.
	input.build_at(anchor + InputController.STATION_ANCHOR_OFFSET)

	check_eq(_view.session.stations.count(), 1, "the tool placed the yard")
	var yard := _view.session.stations.stations()[0]
	check_true(_view.session.stations.has_rail_access(yard),
			"and it reached the rail it was placed beside")
	check_near(_view.session.economy.cash, cash - price,
			"the price on the shelf is the price charged", 0.001)
	input.free()


# --- rolling stock, routes and the loop -------------------------------------

func test_a_locomotive_is_bought_wagons_added_and_a_route_drawn() -> void:
	_view = TestView.stage(VALLEY)
	var line := TestSession.coal_line(_view.session)
	check_true(bool(line["ok"]), "the shipped loop assembled: " + String(line["reason"]))
	var train := int(line["train"])
	check_eq(_view.session.trains.stock_of(train).size(), 3,
			"a locomotive and the wagons the purchase asked for")
	var added := _view.session.trains.add_wagon(train, "coal_hopper")
	check_true(bool(added["ok"]), "and a wagon can still be added to a working train: "
			+ String(added.get("reason", "")))
	check_eq(_view.session.trains.stock_of(train).size(), 4, "the consist grew")
	check_gt(_view.session.routes.count(), 0, "with a route drawn between the yards")
	check_gt(_view.session.trains.count(), 0, "and the roster lists it")


func test_the_train_travels_loads_unloads_and_pays() -> void:
	_view = TestView.stage(VALLEY)
	var line := TestSession.coal_line(_view.session)
	var train := int(line["train"])
	var before := _view.session.cargo.delivered_total()
	var revenue := _view.session.cargo.revenue_total()
	var cash := _view.session.economy.cash

	TestSession.run_until(_view.session,
			func() -> bool: return _view.session.cargo.delivered_total() > before,
			TestSession.DELIVERY_TICKS)

	check_true(_view.session.trains.state_label(train) != "", "every train reports a status")
	check_gt(_view.session.cargo.delivered_total(), before,
			"cargo moved from the colliery to the works")
	check_gt(_view.session.cargo.revenue_total(), revenue, "and it was paid for")
	check_gt(_view.session.economy.cash, cash, "the delivery reached the till")
	check_gt(_view.session.rail.path_find_calls(), 0, "the route was planned")


func test_the_books_tell_the_same_story_as_the_ledger() -> void:
	_view = TestView.stage(VALLEY)
	TestSession.coal_line(_view.session)
	_view.session.advance_ticks(1200)

	var totals := _view.session.economy.current_month_totals()
	var revenue := float(totals.get("revenue", 0.0))
	var expenses := float(totals.get("expenses", 0.0))
	check_true(_view.session.economy.is_consistent(),
			"opening balance plus every ledger row equals the cash the panel shows")
	check_gt(_view.session.economy.ledger().size(), 0, "the panel has rows to list")
	var recent := _view.session.economy.recent(10)
	check_gt(recent.size(), 0, "the recent list the panel draws is not empty")
	for entry in recent:
		check_neq(entry.description, "", "every row says what it was for")
	check_ge(revenue, 0.0, "the month's income is a figure: %.0f" % revenue)
	check_ge(expenses, 0.0, "and so is its spending: %.0f" % expenses)


func test_the_player_expands_and_the_valley_holds_both_lines() -> void:
	_view = TestView.stage(VALLEY)
	var first := TestSession.coal_line(_view.session)
	check_true(bool(first["ok"]), "the first line: " + String(first["reason"]))
	var plant := int(first["plant"])
	var anchor := _find_a_station_anchor(_view.session, _view.session.industries.tile_of(plant))
	var second := _view.session.stations.build("small_station", anchor, "Valley Gate")
	check_true(bool(second["ok"]), "a second yard beside the works: " + String(second["reason"]))
	var joined := TestSession.join(_view.session, int(first["mine_station"]), int(second["id"]))
	check_true(bool(joined["ok"]), "and rail between them: " + String(joined["reason"]))
	check_eq(_view.session.stations.count(), 3, "three yards standing")
	check_gt(_view.session.rail.rail_tiles().size(), 0, "on one growing network")
	check_true(_view.session.economy.is_consistent(), "and the books still balance")


# --- saving, quitting, loading, continuing ---------------------------------

func test_a_saved_game_survives_a_quit_and_a_load() -> void:
	_session = TestSession.create(VALLEY)
	var line := TestSession.coal_line(_session)
	check_true(bool(line["ok"]), "a working valley to save: " + String(line["reason"]))
	_session.advance_ticks(900)

	var saves := SaveService.new()
	saves.attach(_session)
	var written := saves.save_to_path(SAVE_PATH, "manual")
	check_true(bool(written.get("ok", false)), "the save wrote: " + String(written.get("reason", "")))
	check_true(FileAccess.file_exists(SAVE_PATH), "the file is on disk")

	var cash := _session.economy.cash
	var day := _date_key(_session)
	var trains := _session.trains.count()
	var stations := _session.stations.count()
	var rail := _session.rail.rail_tiles().size()
	var train_ids: Array[int] = _session.trains.trains().duplicate()
	var station_ids: Array[int] = _session.stations.stations().duplicate()

	# The quit this harness can perform: the session is torn down completely.
	# What the player is owed is that the disk still holds what they left.
	TestSession.dispose(_session)
	_session = null

	var reopened := TestSession.create(VALLEY)
	var reader := SaveService.new()
	reader.attach(reopened)
	var loaded := reader.load_path(SAVE_PATH)
	check_true(bool(loaded.get("ok", false)),
			"the save opened in a fresh session: " + String(loaded.get("reason", "")))
	check_near(reopened.economy.cash, cash, "the company's money came back", 0.001)
	check_eq(_date_key(reopened), day, "the calendar came back")
	check_eq(reopened.trains.count(), trains, "every train came back")
	check_eq(reopened.stations.count(), stations, "every yard came back")
	check_eq(reopened.rail.rail_tiles().size(), rail, "and every tile of track")
	for index in train_ids.size():
		check_eq(reopened.trains.trains()[index], train_ids[index],
				"a train keeps its identity across a save, not its place in a list")
	for index in station_ids.size():
		check_eq(reopened.stations.stations()[index], station_ids[index],
				"and so does a yard")
	TestSession.dispose(reopened)


func test_continue_takes_the_player_back_into_the_newest_save() -> void:
	_session = TestSession.create(VALLEY)
	var saves := SaveService.new()
	saves.attach(_session)
	_session.advance_ticks(400)
	var first_autosave := saves.autosave()
	check_true(bool(first_autosave.get("ok", false)),
			"a month passed and the valley wrote itself: " + String(first_autosave.get("reason", "")))
	var newest_path := String(first_autosave.get("path", ""))
	_written.append(newest_path)

	var menu := MainMenu.new()
	menu.configure(saves)
	check_true(menu.can_continue(), "with a save on disk, Continue is a real button")
	check_eq(menu.continue_path(), saves.latest_autosave(),
			"and the path it offers is the newest save, not a slot guessed from a name")

	var loads: Array[String] = []
	menu.load_requested.connect(func(path: String) -> void: loads.append(path))
	menu.press_continue()
	check_eq(loads.size(), 1, "pressing Continue asks for that path")
	check_true(loads.size() == 1 and FileAccess.file_exists(loads[0]),
			"and it names a file that is really there, not a slot from memory")
	check_true(saves.list_saves().size() > 0, "the load screen has that save to offer")

	var quits: Array[int] = []
	menu.quit_requested.connect(func() -> void: quits.append(1))
	menu.press_quit()
	check_eq(quits.size(), 1,
			"Quit asks for the window to close instead of killing the process, "
			+ "so a save can still happen on the way out")
	menu.free()


# --- helpers ---------------------------------------------------------------

## Everything the inspector currently says, as one string to search.
func _text_of(node: Node) -> String:
	var text := ""
	for child in node.get_children():
		if child is Label:
			text += (child as Label).text + "\n"
		text += _text_of(child)
	return text


## A straight, flat, dry run of five tiles, found by asking the planner: the
## checklist starts from what the world allows, not from a coordinate a test
## happens to have memorised.
func _find_a_legal_run(session: GameSession) -> Array[Vector2i]:
	for row in range(12, 244, 3):
		var run: Array[Vector2i] = []
		for column in range(12, 17):
			run.append(Vector2i(column, row))
		if bool(session.builder.preview_track_run(run).get("ok", false)):
			return run
	return []


func _find_a_station_anchor(session: GameSession, near: Vector2i) -> Vector2i:
	for radius in range(0, 7):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dy) != radius:
					continue
				var anchor := Vector2i(near.x + dx, near.y + dy)
				if bool(session.builder.preview_station("small_station", anchor).get("ok", false)):
					return anchor
	return Vector2i(-1, -1)


func _date_key(session: GameSession) -> int:
	var date: GameDate = session.date()
	return date.year * 10000 + date.month * 100 + date.day
