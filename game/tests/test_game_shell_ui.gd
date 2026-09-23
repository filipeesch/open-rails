class_name TestGameShellUi
extends TestBase

## The shell is a set of thin readers over the domain.
##
## Every case here builds the same panel the game builds, drives it through the
## same signals a player drives it through, and reads back what the panel ends up
## saying.  No rendering and no scene tree are involved: if a number is only right
## when a viewport exists, that is a bug in the panel, not in the test.

var view: TestView
var input: InputController
var line: Dictionary


func setup() -> void:
	view = TestView.stage()
	input = InputController.new()
	input.attach(view.session, view.rig, view.selection)
	line = TestSession.coal_line(view.session)
	check_true(bool(line["ok"]), "a working valley to look at: " + String(line["reason"]))


func teardown() -> void:
	input.free()
	view.dispose()
	view = null
	input = null
	line = {}


# --- 1.4 top bar -----------------------------------------------------------

func test_the_top_bar_reports_what_the_domain_told_it() -> void:
	var hud := Hud.new()
	hud.attach(view.session)
	check_has(hud.cash_label.text, "$", "the bar opens showing a cash figure")
	check_has(hud.date_label.text, "1850", "and the date it is in")
	check_eq(hud.speed_buttons.size(), 4, "with one button per dial position")
	var cash_before := view.session.economy.cash
	var date_before := hud.date_label.text

	view.session.clock.step_ticks((view.session.clock.ticks_per_day * 30) * 4)

	check_neq(hud.date_label.text, date_before, "a month of ticks moved the date, unasked")
	check_neq(float(view.session.economy.cash), cash_before, "and money moved")
	check_eq(hud.cash_label.text, GameTheme.money_compact(view.session.economy.cash),
			"the bar shows the cash the ledger actually holds")
	check_eq(hud.profit_label.text, "%s/mo" % GameTheme.signed_money(
			float(view.session.economy.current_month_totals()["profit"])),
			"the profit chip states the figure the ledger holds, unit and all")
	check_true(not hud.profit_label.text.begins_with("…"),
			"and it is that figure rather than the string the label was built with")

	view.session.clock.set_speed_index(2)
	hud._refresh()
	var lit := 0
	var lit_index := -1
	for index in hud.speed_buttons.size():
		if hud.speed_buttons[index].button_pressed:
			lit += 1
			lit_index = index
	check_eq(lit, 1, "exactly one dial position reads as in force")
	check_eq(lit_index, 2, "and it is the position the clock is actually running at")
	hud.free()


func test_the_top_bar_marks_a_losing_company_as_losing() -> void:
	var hud := Hud.new()
	hud.attach(view.session)
	view.session.economy.spend(12000.0, EconomyService.CATEGORY_MAINTENANCE, "Bills")
	check_eq(hud.cash_label.text, GameTheme.money_compact(view.session.economy.cash),
			"a payment is on the bar the moment it is charged")
	view.session.clock.step_ticks(view.session.clock.ticks_per_day * 30 + 6)
	check_has(hud.profit_label.text, "-", "a month of loss reads as a loss")
	hud.free()


func test_the_profit_bar_carries_a_number_from_the_very_first_frame() -> void:
	# The bar is change-driven, and every field's "last seen" figure starts at the
	# value the first answer may itself have: 0, and "".  Compared bare, that first
	# answer is never noticed as a change, and the game was played with the label's
	# construction string on the top bar for its whole life because nothing had ever
	# been worth writing.  A placeholder is allowed to exist for one frame, not for a
	# sandbox.  What is graded is therefore the placeholder's absence and the sign of
	# the figure — the number itself belongs to the valley, and this fixture's valley
	# runs a coal line, so it is not level.
	var hud := Hud.new()
	hud.attach(view.session)
	var profit := float(view.session.economy.current_month_totals()["profit"])
	check_neq(hud.profit_label.text, "…/mo", "the construction string is not on screen")
	check_true(not hud.profit_label.text.begins_with("…"),
			"nothing of the placeholder survives the first refresh")
	check_has(hud.profit_label.text, "/mo", "the field is a rate, as the bar promises")
	if profit < 0.0:
		check_true(hud.profit_label.text.begins_with("-"),
				"a valley running in the red is shown with a minus: %s for %s" % [
					hud.profit_label.text, GameTheme.money(profit)])
	else:
		check_true(hud.profit_label.text.begins_with("+"),
				"a valley level or ahead is shown with a plus: %s for %s" % [
					hud.profit_label.text, GameTheme.money(profit)])
	check_eq(hud.date_label.text, view.session.clock.date.display(),
			"the date is there before anything has ever changed")
	check_eq(hud.cash_label.text, GameTheme.money_compact(view.session.economy.cash),
			"and so is the opening balance")
	hud.free()


func test_a_month_that_is_exactly_level_is_written_out_as_level() -> void:
	# The case the fix was aimed at, in the one state that triggers it: an empty grid
	# earns and spends nothing, so its profit is exactly the sentinel the change test
	# compared against, and the old code judged "no change" and left the placeholder
	# on screen forever.
	var blank := GameSession.new()
	blank.start_blank(16, 16)
	var hud := Hud.new()
	hud.attach(blank)
	check_near(float(blank.economy.current_month_totals()["profit"]), 0.0,
			"a bare grid is level to the cent", 0.001)
	check_eq(hud.profit_label.text, "+$0/mo",
			"and the bar says so, rather than trailing off where the number should be")
	check_neq(hud.cash_label.text, "", "the opening balance is on the bar unasked too")
	hud.free()
	TestSession.dispose(blank)


# --- 1.5 bottom toolbar ----------------------------------------------------

func test_the_toolbar_offers_exactly_what_it_arms_and_holds_nothing_else() -> void:
	var toolbar := BottomToolbar.new()
	toolbar.attach(view.session, input)
	var buttons := toolbar.find_children("*", "Button", true, false)
	check_eq(buttons.size(), 5, "five entries and no permanent sidebar of extras")
	var labels := ""
	for button in buttons:
		labels += String(button.text) + "|"
	for wanted in ["Build", "Stations", "Trains", "Company", "World"]:
		check_has(labels, wanted, "the toolbar offers %s" % wanted)
	check_eq(toolbar.find_children("*", "VBoxContainer", true, false).size(), 0,
			"it is one row of buttons: no panel lives inside it")

	_press_named(buttons, "Build")
	check_eq(input.tool, InputController.TOOL_RAIL, "pressing Build arms the rail tool")
	_press_named(buttons, "Stations")
	check_eq(input.tool, InputController.TOOL_STATION, "and Stations arms the station tool")
	_press_named(buttons, "Trains")
	check_eq(input.active_panel, InputController.PANEL_TRIPS, "Trains opens the trains panel")
	_press_named(buttons, "Company")
	check_eq(input.active_panel, InputController.PANEL_COMPANY, "Company opens the finances")
	check_eq(input.tool, InputController.TOOL_STATION,
			"a panel is an overlay, not an escape: opening the books does not
			quietly cancel the line the player was laying")
	toolbar.free()


# --- 1.6 context inspector -------------------------------------------------

func test_the_inspector_answers_for_what_is_selected_and_says_nothing_for_nothing() -> void:
	var inspector := ContextInspector.new()
	inspector.attach(view.session, view.selection, view.rig)
	check_false(inspector.has_selection(), "with nothing selected there is nothing to answer for")
	check_false(inspector.visible, "and the sheet is not on screen")
	check_eq(inspector.column.get_child_count(), 0, "and it holds no widget at all")

	var mine_station := int(line["mine_station"])
	view.selection.select_station(mine_station)
	check_eq(inspector.inspected(), "station", "a station selection opens the station sheet")
	check_eq(inspector.inspected_id(), mine_station, "named for the station it is showing")
	var station_actions := _button_labels(inspector.column)
	check_has(station_actions, "Buy a train here", "which offers the action a platform needs")
	check_has(station_actions, "Rename", "and the rename the player expects")
	check_has(station_actions, "Focus", "and a way to fly to it")

	var train := int(line["train"])
	view.selection.select_train(train)
	check_eq(inspector.inspected(), "train", "a train selection replaces it with the train sheet")
	var train_actions := _button_labels(inspector.column)
	check_has(train_actions, "Open route", "the train sheet offers its route")
	check_has(train_actions, "Follow (F)", "and following it")
	check_false(_button_labels(inspector.column).contains("Buy a train here"),
		"the station sheet was put down, not left underneath")

	view.selection.clear_selection()
	check_false(inspector.has_selection(), "and it goes away when the selection goes")
	check_false(inspector.visible, "off screen, in the same step")
	check_eq(inspector.column.get_child_count(), 0, "leaving no stale widgets behind")
	inspector.free()


func test_the_inspector_names_the_buyer_a_platform_serves() -> void:
	## A destination station with a works in its catchment is the whole business
	## case for the line.  The inspector has to say who the customer is.
	var inspector := ContextInspector.new()
	inspector.attach(view.session, view.selection, view.rig)
	view.selection.select_station(int(line["plant_station"]))
	var body := _label_text(inspector.column)
	check_has(body, "Delivers to", "the station sheet lists where cargo would go")
	check_has(body, "Valley Gate Works", "naming the works that stands in the catchment")
	inspector.free()


# --- 2.5 notifications -----------------------------------------------------

func test_a_refusal_speaks_in_the_corner_instead_of_stopping_the_game() -> void:
	var notices := NotificationCenter.new()
	notices.attach(view.session)
	check_eq(notices.visible_count(), 0, "the valley starts quiet")

	view.session.economy.spend_allowing_deficit(view.session.economy.cash + 900000.0,
			EconomyService.CATEGORY_TRACK, "test: emptied the till")
	var refused := view.session.trains.purchase(int(line["mine_station"]), "steam_440", ["coal_hopper"])
	check_false(bool(refused["ok"]), "the purchase was refused")
	check_gt(float(notices.visible_count()), 0.0, "and the refusal said so out loud")
	var refusal := _label_text(notices).to_lower()
	check_has(refusal, "needed", "naming the sum the till cannot cover")
	check_has(refusal, "$", "and showing it as money, not as a shrug")

	for push in 9:
		notices.push("Notice %d" % push, "info")
	check_le(float(notices.visible_count()), float(NotificationCenter.MAX_VISIBLE),
			"and the stack never grows past the visible budget")
	check_eq(notices.find_children("*", "AcceptDialog", true, false).size(), 0,
			"nothing here is modal: the game keeps running underneath")
	check_eq(notices.find_children("*", "ConfirmationDialog", true, false).size(), 0,
			"and no confirmation gate was thrown in front of the player")
	notices.free()


# --- 2.6 command palette ---------------------------------------------------

func test_the_palette_finds_a_town_and_puts_the_camera_on_it() -> void:
	var palette := CommandPalette.new()
	palette.attach(view.session, input, view.rig, view.selection)
	var entries := palette.entries()
	check_gt(float(entries.size()), 10.0, "the registry has actions and entities in it")
	var town_index := _index_naming(entries, "Marlow")
	check_gt(float(town_index), -1.0, "and a town can be found by name")

	var marlow_id := 0
	for town_id in view.session.towns.towns():
		if view.session.towns.name_of(town_id) == "Marlow":
			marlow_id = town_id
	check_neq(marlow_id, 0, "the valley's first town is in the registry under its own name")
	var expected := WorldCoords.tile_to_world(view.session.towns.tile_of(marlow_id))
	palette.activate_entry(town_index)
	check_lt(view.rig.desired_target.distance_to(expected), 2.5,
			"choosing it moves the camera over the town")
	check_false(palette.is_open(), "and the palette gets out of the way afterwards")
	palette.free()


func test_the_palette_is_a_command_registry_not_just_a_search_box() -> void:
	var palette := CommandPalette.new()
	palette.attach(view.session, input, view.rig, view.selection)
	var invoked: Array[String] = []
	palette.command_invoked.connect(func(id: String) -> void: invoked.append(id))

	palette.activate_entry(_index_naming(palette.entries(), "Pause simulation"))
	check_eq(view.session.clock.speed_index, 0, "the pause command pauses")
	palette.activate_entry(_index_naming(palette.entries(), "Lay rail"))
	check_eq(input.tool, InputController.TOOL_RAIL, "the build command arms the tool")
	palette.activate_entry(_index_naming(palette.entries(), "Rotate camera right"))
	check_near(view.rig.desired_yaw, 90.0, "and a camera command turns the view", 0.001)
	check_eq(invoked.size(), 3, "every activation announced itself")
	palette.free()


# --- 5.3 debug overlay -----------------------------------------------------

func test_the_debug_overlay_answers_every_question_the_profiler_asks() -> void:
	var overlay := DebugOverlay.new()
	overlay.attach(view.session, view.renderer, null)
	check_false(overlay.is_enabled(), "it starts hidden — it is a developer tool")
	overlay.toggle()
	check_true(overlay.is_enabled(), "F3 opens it")
	var report := overlay.label.text
	check_has(report, "FPS", "frame rate and frame time")
	check_has(report, "draw calls", "draw calls and primitives")
	check_has(report, "tick avg", "tick time against its budget")
	check_has(report, "speed", "the clock: speed, tick, date")
	check_has(report, "trains", "what is in the world")
	check_has(report, "terrain chunks", "terrain chunks, triangles and rebuilds")
	check_has(report, "path finds", "pathfinding calls and time")
	check_has(report, "scene nodes", "the node count, because per-tile nodes are forbidden")
	check_has(report, "ledger consistent", "and whether the books still add up")
	check_has(report, "1850", "with no field left blank")
	overlay.toggle()
	check_false(overlay.is_enabled(), "and F3 closes it again")
	overlay.free()


# --- helpers ---------------------------------------------------------------

func _press_named(buttons: Array[Node], label: String) -> void:
	for button in buttons:
		if String(button.text) == label:
			var as_button := button as Button
			as_button.pressed.emit()
			return
	check_true(false, "no button named %s was built" % label)


func _button_labels(root: Node) -> String:
	var joined := ""
	for button in root.find_children("*", "Button", true, false):
		joined += String((button as Button).text) + "|"
	return joined


func _label_text(root: Node) -> String:
	var joined := ""
	for label in root.find_children("*", "Label", true, false):
		joined += String((label as Label).text) + "\n"
	return joined


func _index_naming(entries: PackedStringArray, wanted: String) -> int:
	for index in entries.size():
		if String(entries[index]).to_lower().contains(wanted.to_lower()):
			return index
	check_true(false, "nothing in the palette is named %s" % wanted)
	return -1
