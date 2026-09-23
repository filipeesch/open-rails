class_name TestTrainPanels
extends TestBase

## The train loop, seen through the panels a player actually opens.
##
## Every case builds the real panel class the way the shipped game builds it —
## by code, wired through `attach` — drives it with the same signals a click or
## a domain event drives it with, and reads back what the panel ends up saying.
## The point of every case is the same from different angles: the panel must
## *report* the domain and nothing else.  A figure the panel computed for
## itself, a row that outlived the train it described, a "live" sheet that only
## updates when someone reopens it — each is a lie the player would pay for.

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


# --- 3.1 the trains drawer --------------------------------------------------

func test_the_drawer_lists_every_figure_a_train_row_promises() -> void:
	## Name, locomotive, speed, cargo, route, monthly profit and status — the
	## row must show each of them, and every figure it shows must be the
	## domain's own value rendered through the one formatter that figure has.
	var drawer := TripPanel.new()
	drawer.attach(view.session, input, view.selection, view.rig)
	input.open_panel(InputController.PANEL_TRIPS)
	check_true(drawer.is_open(), "the Trains entry on the toolbar opens the drawer")
	drawer.refresh_now()
	var train := int(line["train"])
	var row := _row_for(drawer, train)
	if row == null:
		drawer.free()
		return

	var text := _labels_of(row)
	check_has(text, view.session.trains.name_of(train), "the row names its train")
	check_has(text, "4-4-0 American", "and says which locomotive is hauling it")
	check_has(text, "Carrying Coal", "and what it can carry")
	check_has(text, session().stations.name_of(int(line["plant_station"])),
			"and the route it runs")
	check_has(text, "Profit this month", "and the month's profit line")
	check_has(text, GameTheme.signed_money(view.session.trains.monthly_profit(train)),
			"stated in the ledger's own money format, at the domain's own figure")
	var seen_moving_speed := false
	for _chunk in 10:
		view.session.clock.step_ticks(200)
		drawer.refresh_now()
		text = _labels_of(row)
		check_has(text, view.session.trains.state_label(train).to_upper(),
				"the status stamp is the domain's current state")
		check_has(text, GameTheme.kmh(view.session.trains.speed_kmh(train)),
				"the speed is TrainService.speed_kmh rendered, never re-derived")
		if view.session.trains.speed_kmh(train) > 0.0:
			seen_moving_speed = true
	check_true(seen_moving_speed, "the train runs while the drawer watches it — the "
			+ "speed figure leaves zero and the row followed")
	var count := ""
	for other in view.session.trains.trains():
		count += " " + view.session.trains.state_label(other)
	check_has(_labels_of(drawer), "1 train", "the header counts what the list holds: " + count)
	drawer.free()


func test_a_row_click_selects_the_train_and_opens_the_inspector() -> void:
	## The row is a handle onto the world: clicking it selects the train, and
	## selection is what opens the inspector.  A left click must do that; a
	## right click must not, and no click may touch the simulation.
	var drawer := TripPanel.new()
	drawer.attach(view.session, input, view.selection, view.rig)
	var inspector := ContextInspector.new()
	inspector.attach(view.session, view.selection, view.rig)
	input.open_panel(InputController.PANEL_TRIPS)
	drawer.refresh_now()
	var train := int(line["train"])
	var row := _row_for(drawer, train)
	var cash_before := view.session.economy.cash
	var ticks_before: int = view.session.clock.tick_count

	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	row._on_gui_input(right)
	check_false(view.selection.has_selection(), "a right click is not a selection")

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	row._on_gui_input(click)
	check_eq(view.selection.selected_kind, SelectionService.KIND_TRAIN,
			"a left click on the row selects a train")
	check_eq(view.selection.selected_id, train, "and this train, not another")
	check_true(inspector.has_selection(), "the inspector woke with the selection")
	check_true(inspector.visible, "on screen, not merely populated")
	check_eq(inspector.inspected(), "train", "answering for the train the row named")
	check_has(_button_labels(inspector.column), "Open route",
			"offering the route action a train sheet is supposed to offer")
	check_near(view.session.economy.cash, cash_before, "the click spent nothing")
	check_eq(view.session.clock.tick_count, ticks_before, "and advanced nothing")
	inspector.free()
	drawer.free()


func test_the_drawer_searches_by_name_cargo_and_status() -> void:
	## Search and filter are the claim: one box, matching name, status, station
	## or cargo, hiding the rows that do not match without removing them — and
	## nothing about the drawer is a window, a dialog or a mode.
	var drawer := TripPanel.new()
	drawer.attach(view.session, input, view.selection, view.rig)
	input.open_panel(InputController.PANEL_TRIPS)
	var hopper := int(line["train"])
	view.session.trains.purchase(int(line["plant_station"]), "steam_440", ["mail_car"])
	drawer.refresh_now()
	var rows := _rows_of(drawer)
	check_eq(rows.size(), 2, "a train bought while the drawer was open appeared by itself")
	for row in rows:
		check_true(row.visible, "with no filter every row shows")

	drawer._filter_field.text_changed.emit("mail")
	drawer.refresh_now()
	check_false(_row_for(drawer, hopper).visible, "a cargo filter hides the coal consist")
	check_true(_rows_of(drawer)[1].visible, "and keeps the mail one")
	drawer._filter_field.text_changed.emit("valley gate")
	drawer.refresh_now()
	check_true(_row_for(drawer, hopper).visible,
			"the same box finds a consist by the station its route runs to")
	view.session.clock.step_ticks(1200)
	drawer.refresh_now()
	var status := view.session.trains.state_label(hopper).to_lower()
	drawer._filter_field.text_changed.emit(status)
	drawer.refresh_now()
	check_true(_row_for(drawer, hopper).visible, "and by the status it reports")
	check_false(_rows_of(drawer)[1].visible,
			"a parked consist does not answer to a running word")
	drawer._filter_field.text_changed.emit("no such train")
	drawer.refresh_now()
	for row in _rows_of(drawer):
		check_false(row.visible, "a query nothing matches hides every row")
	drawer._filter_field.text_changed.emit("")
	drawer.refresh_now()
	for row in _rows_of(drawer):
		check_true(row.visible, "and clearing it brings them all back")

	drawer._filter_field.text_changed.emit("no such train")
	drawer.refresh_now()
	input.open_panel(InputController.PANEL_COMPANY)
	check_false(drawer.is_open(), "asking for another panel steps this drawer out of the band")
	check_eq(input.active_panel, InputController.PANEL_COMPANY,
			"stepping aside does not overwrite the panel the player just chose")
	check_eq(drawer.find_children("*", "AcceptDialog", true, false).size(), 0,
			"the drawer owns no dialog — the valley keeps running behind it")
	check_eq(drawer.find_children("*", "ConfirmationDialog", true, false).size(), 0,
			"and no confirmation gate either")
	drawer.free()


# --- 3.2 the consist editor --------------------------------------------------

func test_the_yard_quoted_figures_are_the_domains_own_rating() -> void:
	## Price, capacity, weight, estimated speed and running cost must be
	## `preview_consist`'s answer for the very consist the form is showing —
	## not the panel's arithmetic about a consist of its own guessing.
	var yard := TrainYard.new()
	yard.attach(view.session, view.rig)
	var cash_before := view.session.economy.cash
	var ledger_before := view.session.economy.ledger().size()
	yard.refresh()
	var stock := _form_stock(yard)
	var preview: Dictionary = view.session.trains.preview_consist(stock)
	check_has(yard._price_label.text, "Price " + GameTheme.money(float(preview["price"])),
			"the price line is the domain's price for this consist")
	check_has(yard._spec_label.text, GameTheme.tons(float(preview["weight_tons"])),
			"the weight is the domain's")
	check_has(yard._spec_label.text, GameTheme.kmh(float(preview["max_speed_kmh"])),
			"the estimated speed is the domain's")
	check_has(yard._spec_label.text, GameTheme.money(float(preview["running_cost_month"])) + "/mo",
			"the monthly upkeep is the domain's")
	var capacity: Dictionary = preview["capacity"] as Dictionary
	check_false(capacity.is_empty(), "the default order includes a wagon, so there is capacity to show")
	for cargo_id in capacity.keys():
		check_has(yard._capacity_label.text, session().data.cargo_display(String(cargo_id)),
				"every cargo the consist rates for is named on the capacity line")
	check_eq(yard._cash_label.text, "Cash on hand " + GameTheme.money(cash_before),
			"the till line is the till's actual balance")
	check_false(yard._buy_button.disabled, "with a station and cash the order can be placed")
	check_near(view.session.economy.cash, cash_before, "reading the form spent nothing")
	check_eq(view.session.economy.ledger().size(), ledger_before, "and wrote no ledger row")
	check_true(view.session.economy.is_consistent(), "the books still add up")
	yard.free()


func test_adding_a_wagon_moves_every_figure_the_yard_shows() -> void:
	## The claim is *every* statistic.  One spinner click must move capacity,
	## weight, estimated speed, price and running cost together, each to the
	## value the domain now rates the bigger consist at.
	var yard := TrainYard.new()
	yard.attach(view.session, view.rig)
	yard.refresh()
	var stock := _form_stock(yard)
	var old_preview: Dictionary = view.session.trains.preview_consist(stock)
	var old_text := yard._capacity_label.text + "|" + yard._spec_label.text + "|" + yard._price_label.text
	var counts: Dictionary = yard._counts
	check_gt(float(counts.size()), 0.0, "the form offers the shipped wagons")
	var chosen := ""
	for key in counts.keys():
		chosen = String(key)
		if int((counts[key] as SpinBox).value) > 0:
			break
	check_neq(chosen, "", "some wagon is on the order to begin with")
	var wagon_def := session().data.stock(chosen)
	check_true(wagon_def != null, "and it is a defined piece of stock")

	# A headless control stays quiet about code-set values the same way a
	# button stays quiet about a code-set press: the engine emits these from
	# interaction, so the test emits what the player's click would.
	var spinner: SpinBox = counts[chosen]
	spinner.value += 1.0
	spinner.value_changed.emit(spinner.value)
	yard.refresh()
	var grown := _form_stock(yard)
	check_eq(grown.size(), stock.size() + 1, "the order now names one more wagon")
	var new_preview: Dictionary = view.session.trains.preview_consist(grown)
	var new_text := yard._capacity_label.text + "|" + yard._spec_label.text + "|" + yard._price_label.text
	check_neq(new_text, old_text, "the form visibly moved")
	check_near(float(new_preview["price"]) - float(old_preview["price"]), wagon_def.price,
			"price rose by exactly the wagon's own price", 0.001)
	check_near(float(new_preview["running_cost_month"]) - float(old_preview["running_cost_month"]),
			wagon_def.running_cost_month, "upkeep rose by exactly the wagon's own upkeep", 0.001)
	check_near(float(new_preview["weight_tons"]) - float(old_preview["weight_tons"]),
			wagon_def.weight_tons, "weight rose by exactly the wagon's own weight", 0.001)
	check_lt(float(new_preview["max_speed_kmh"]), float(old_preview["max_speed_kmh"]),
			"and the extra weight slows the estimated speed")
	var old_capacity: Dictionary = old_preview["capacity"] as Dictionary
	var new_capacity: Dictionary = new_preview["capacity"] as Dictionary
	check_gt(float(new_capacity.get(wagon_def.cargo, 0.0)),
			float(old_capacity.get(wagon_def.cargo, 0.0)),
			"the capacity for the wagon's cargo grew")
	check_has(yard._price_label.text, "Price " + GameTheme.money(float(new_preview["price"])),
			"the price line now says the new price")
	check_has(yard._spec_label.text, GameTheme.tons(float(new_preview["weight_tons"])),
			"the spec line says the new weight")
	check_has(yard._spec_label.text, GameTheme.kmh(float(new_preview["max_speed_kmh"])),
			"the spec line says the new estimated speed")
	check_has(yard._spec_label.text, GameTheme.money(float(new_preview["running_cost_month"])),
			"the spec line says the new upkeep")
	check_has(yard._capacity_label.text, session().data.cargo_display(String(wagon_def.cargo)),
			"the capacity line still names the cargo it grew")
	yard.free()


func test_buying_the_consist_the_yard_quoted_charges_the_ledger_exactly_that() -> void:
	## The order form is a promise about money.  Pressing Buy must spend exactly
	## the quoted price, through the ledger, in one named row — and put a train
	## on the rails whose consist matches the one that was quoted.
	var yard := TrainYard.new()
	yard.attach(view.session, view.rig)
	var notices: Array[String] = []
	session().notice.connect(func(message: String, _severity: String) -> void: notices.append(message))
	var bought: Array[int] = []
	yard.bought.connect(func(train_id: int) -> void: bought.append(train_id))
	yard.refresh()
	var stock := _form_stock(yard)
	var price := float(view.session.trains.preview_consist(stock)["price"])
	var cash_before := view.session.economy.cash
	_press_button(yard, "Buy train")
	check_eq(bought.size(), 1, "the purchase announced the train it created")
	var train := bought[0]
	var instance: Dictionary = view.session.trains.train(train)
	check_false(instance.is_empty(), "and that train exists")
	check_eq(view.session.trains.stock_of(train), stock,
			"with exactly the consist the form was showing")
	check_near(cash_before - view.session.economy.cash, price,
			"it cost exactly the quoted price", 0.001)
	var top: EconomyService.Transaction = view.session.economy.recent(1)[0]
	check_near(top.amount, -price, "the ledger row carries exactly that money", 0.001)
	check_has(top.description, "Train: 4-4-0 American", "named for what was bought")
	check_true(view.session.economy.is_consistent(), "opening balance plus the ledger still equals cash")
	var said := ""
	for notice in notices:
		said += notice + "\n"
	check_has(said, "Purchased", "and the player was told in plain words")
	yard.free()


# --- 3.3 the route drawer -----------------------------------------------------

func test_the_route_page_shows_the_stops_and_their_load_plan() -> void:
	## Stops in order, and per stop what to pick up and deliver — offered from
	## what the station actually has and what its catchment actually wants.
	var drawer := TripPanel.new()
	drawer.attach(view.session, input, view.selection, view.rig)
	session().stations.add_cargo(int(line["mine_station"]), "coal", 40.0)
	drawer.open_route_for(int(line["train"]))
	drawer.refresh_now()
	var text := _labels_of(drawer._route_editor)
	check_has(text, "Route", "the page says whose route it is")
	check_has(text, session().stations.name_of(int(line["mine_station"])), "stop one is the wharf")
	check_has(text, session().stations.name_of(int(line["plant_station"])), "stop two is the works")
	check_has(text, "2 stops", "and the length is the domain's stop count")
	var chips := drawer._route_editor.find_children("*", "CheckBox", true, false)
	var load_chip: CheckBox = null
	var unload_chip: CheckBox = null
	for chip in chips:
		if String((chip as CheckBox).text).contains("waiting"):
			load_chip = chip as CheckBox
		else:
			unload_chip = chip as CheckBox
	check_true(load_chip != null and unload_chip != null,
			"one chip to load coal at the pit, one to drop it at the works")
	check_has(load_chip.text, "40 waiting", "the load chip says what is standing there")
	check_true(load_chip.button_pressed, "and reflects the plan already committed")
	check_true(unload_chip.button_pressed, "as does the unload chip")

	load_chip.toggled.emit(false)
	drawer.refresh_now()
	check_false(load_chip.button_pressed, "switching the chip off reads off")
	check_false(_stop_plan(0, "load").has("coal"),
			"and the domain's stop list changed with it — the editor commits, it does not suggest")
	load_chip.toggled.emit(true)
	drawer.refresh_now()
	check_true(_stop_plan(0, "load").has("coal"), "and back on again the same way")
	drawer.free()


func test_map_stop_picking_opens_a_route_stop_by_stop() -> void:
	## "Add stop on map" is the whole map-based picking flow: the tool arms, the
	## drawer says so, each picked station lands as a stop through the domain —
	## and the first two picks do not make the domain refuse every click.
	var drawer := TripPanel.new()
	drawer.attach(view.session, input, view.selection, view.rig)
	drawer.open_route_for(int(line["train"]))
	drawer.refresh_now()
	_press_button(drawer._route_editor, "Clear route")
	drawer.refresh_now()
	check_eq(view.session.trains.route_of(int(line["train"])), 0, "the route really went away")
	check_has(_labels_of(drawer._route_editor), "No route yet", "and the page says so")

	_press_button(drawer._route_editor, "Add stop on map")
	check_eq(input.tool, InputController.TOOL_STOP_PICK, "the pick tool is armed")
	drawer.refresh_now()
	check_has(_labels_of(drawer._route_editor), "Pick mode",
			"the drawer explains the mode it just asked for")
	input.station_picked.emit(int(line["mine_station"]))
	drawer.refresh_now()
	check_has(_labels_of(drawer._route_editor), "One stop picked",
			"the first pick is held, not refused — a route wants two stops")
	check_eq(view.session.trains.route_of(int(line["train"])), 0, "no route exists yet")
	input.station_picked.emit(int(line["mine_station"]))
	drawer.refresh_now()
	check_has(_labels_of(drawer._route_editor), "already a stop",
			"picking it twice says so out loud")
	input.station_picked.emit(int(line["plant_station"]))
	drawer.refresh_now()
	check_neq(view.session.trains.route_of(int(line["train"])), 0,
			"the second pick opens the route through the domain")
	check_has(_labels_of(drawer._route_editor), "2 stops", "and the page counts them")
	input.cancel()
	check_eq(input.tool, InputController.TOOL_NONE, "Esc leaves pick mode without a second thought")
	drawer.refresh_now()
	check_has(_labels_of(drawer._route_editor), "Add stop on map", "and the button puts itself back")
	drawer.free()


func test_the_route_page_reports_a_line_cut_under_it_unasked() -> void:
	## The drawer reflects reachability changes live: pull one rail tile out
	## from under a working route and, with the next paint the 0.1 s clock would
	## drive, the page has to say which stop can no longer be reached — and say
	## it stops the moment the line is repaired, unasked.
	var drawer := TripPanel.new()
	drawer.attach(view.session, input, view.selection, view.rig)
	var train := int(line["train"])
	drawer.open_route_for(train)
	drawer.refresh_now()
	var route_id := view.session.trains.route_of(train)
	var text := _labels_of(drawer._route_editor)
	check_has(text, "2 stops", "the line works to begin with")
	check_true(view.session.routes.is_valid(route_id), "and the domain agrees")

	var path := view.session.routes.path_of(route_id)
	# A quarter of the way round the loop is mid-leg, well clear of both
	# stations' access tiles — the only tiles `removal_block` will not give up.
	var cut := Vector2i(int(path[maxi(1, path.size() / 4)].x),
			int(path[maxi(1, path.size() / 4)].y))
	var tiles: Array[Vector2i] = [cut]
	check_true(bool(view.session.builder.remove_track(tiles)["ok"]),
			"a tile was pulled from under the middle of the line")
	drawer.refresh_now()
	text = _labels_of(drawer._route_editor)
	check_has(text, "Invalid route", "the page turned to the failure without being asked twice")
	check_has(text, "not reachable", "naming which stop the cut stranded")
	check_has(_labels_of(_row_for(drawer, train)), "NO PATH",
			"and the train row says the same thing in the same paint")

	var rejoined := TestSession.join(session(), int(line["mine_station"]), int(line["plant_station"]))
	check_true(bool(rejoined["ok"]), "the line was relaid: " + String(rejoined["reason"]))
	drawer.refresh_now()
	text = _labels_of(drawer._route_editor)
	check_false(text.contains("Invalid route"), "the failure line is gone")
	check_has(text, "2 stops", "and the working timetable is on the page again")
	check_true(view.session.routes.is_valid(route_id), "matching the domain exactly")
	drawer.free()


func test_a_third_station_on_the_line_shows_up_reachable_and_becomes_a_stop() -> void:
	## Map-based picking has a drawer-side twin: the reachable list, drawn from
	## `RouteService.reachable_stations` and rebuilt the moment one appears —
	## because the only stops an editor may offer are stops the line can reach.
	var drawer := TripPanel.new()
	drawer.attach(view.session, input, view.selection, view.rig)
	var train := int(line["train"])
	drawer.open_route_for(train)
	drawer.refresh_now()
	var path := view.session.routes.path_of(view.session.trains.route_of(train))
	var near := Vector2i(int(path[1].x), int(path[1].y))
	var third := TestSession.station_for_tile(session(), near, "Newlay Halt", false)
	check_neq(third, 0, "a third platform can stand on this line")
	if third == 0:
		drawer.free()
		return
	drawer.refresh_now()
	var add := _button_named(drawer._route_editor, "Newlay Halt")
	check_true(add != null, "it appeared in the reachable list without being asked")
	if add == null:
		drawer.free()
		return
	add.pressed.emit()
	drawer.refresh_now()
	check_has(_labels_of(drawer._route_editor), "3 stops", "pressing it added it, through the domain")
	var stops := Array(session().routes.stops(view.session.trains.route_of(train)))
	check_eq(stops.size(), 3, "the domain's stop list grew with it")
	drawer._route_editor._remove_stop(2)
	drawer.refresh_now()
	check_has(_labels_of(drawer._route_editor), "2 stops", "and a stop taken off shrinks it again")
	check_true(_button_named(drawer._route_editor, "Newlay Halt") != null,
			"the dropped stop is offered as reachable again the same paint")

	# Down to a single stop the editor cannot hold a timetable: the claim is
	# that every edit commits the moment it happens, so shrinking below two
	# must take the old route down rather than leave a train running a route
	# the page no longer shows.
	drawer._route_editor._remove_stop(1)
	drawer.refresh_now()
	check_eq(view.session.trains.route_of(train), 0,
			"a one-stop draft takes the stale timetable down with it")
	var text := _labels_of(drawer._route_editor)
	check_has(text, "One stop picked",
			"the page says the truth: one stop held, nothing running to hold it")
	check_false(text.contains("2 stops"),
			"the timetable the player just destroyed is off the page too")
	var clear := _button_named(drawer._route_editor, "Clear route")
	check_true(clear != null and clear.disabled,
			"and there is no route left to clear")
	var readd := _button_named(drawer._route_editor, "Valley Gate Works")
	check_true(readd != null, "the stranded works is reachable and offered again")
	if readd != null:
		readd.pressed.emit()
		drawer.refresh_now()
		check_neq(view.session.trains.route_of(train), 0, "picking it reopens a real route")
		check_has(_labels_of(drawer._route_editor), "2 stops", "with both stops on the page")
	drawer.free()


# --- 3.4 the company's books --------------------------------------------------

func test_the_books_show_the_month_the_ledger_reports() -> void:
	## Cash, monthly revenue, expenses and profit — each figure is
	## `current_month_totals()`'s own number in the ledger's own format, and
	## reading the books moves nothing.
	var books := CompanyPanel.new()
	books.attach(view.session, input)
	var cash_before := view.session.economy.cash
	var ticks_before: int = view.session.clock.tick_count
	input.open_panel(InputController.PANEL_COMPANY)
	check_true(books.is_open(), "the Company entry on the toolbar opens the books")
	books.refresh_now()
	var totals: Dictionary = session().economy.current_month_totals()
	check_eq(books.cash_label.text, GameTheme.money(session().economy.cash),
			"the cash line is the till")
	check_eq(books.revenue_label.text, GameTheme.money(float(totals["revenue"])),
			"the revenue line is the month's revenue rows")
	check_eq(books.expenses_label.text, GameTheme.money(float(totals["expenses"])),
			"the expenses line is the month's expense rows")
	check_eq(books.profit_label.text, GameTheme.signed_money(float(totals["profit"])),
			"and profit is their difference, as the ledger computes it")
	var spent := _labels_of(books)
	check_has(spent, "Company finances", "the sheet says what it is")
	check_has(spent, "Books for", "and for which month it speaks")
	check_has(spent, session().clock.date.display(), "naming the month the clock is in")
	## Building the coal line was real spending; the books must already carry it.
	check_gt(float(totals["expenses"]), 0.0, "construction shows up as an expense")
	check_near(view.session.economy.cash, cash_before, "opening the books spent nothing")
	check_eq(view.session.clock.tick_count, ticks_before, "and stopped nothing")
	books.free()


func test_the_transactions_the_books_list_are_the_ledger_verbatim() -> void:
	## Every listed entry must be a real ledger row — same description, same
	## signed amount, newest first — and a fresh payment must appear the moment
	## it is recorded, without the panel being reopened or recomputed against.
	var books := CompanyPanel.new()
	books.attach(view.session, input)
	input.open_panel(InputController.PANEL_COMPANY)
	books.refresh_now()
	var entries := session().economy.recent(CompanyPanel.VISIBLE_TRANSACTIONS)
	var rows := books.transactions_box.get_children()
	check_eq(float(rows.size()), float(entries.size()),
			"the sheet lists exactly the live recent ledger, one row per entry")
	for index in entries.size():
		var entry: EconomyService.Transaction = entries[index]
		var row_text := _labels_of(rows[index])
		check_has(row_text, entry.description, "row %d carries the ledger's own words" % index)
		check_has(row_text, GameTheme.money(entry.amount),
				"and the exact signed amount the ledger recorded")
	# Newest first: the coal line ends in a train purchase; it must be the top
	# of the sheet, and a fresh payment must jump above it unasked.
	var top: EconomyService.Transaction = entries[0]
	check_has(_labels_of(rows[0]), top.description, "the newest row is listed first")
	var bills := session().economy.spend(1000.0, EconomyService.CATEGORY_MAINTENANCE,
			"Panel test bills")
	books.refresh_now()
	var fresh := books.transactions_box.get_children()
	check_eq(float(fresh.size()), float(entries.size()) + 1.0, "a recorded payment joins the sheet")
	var new_text := _labels_of(fresh[0])
	check_has(new_text, "Panel test bills", "at the top, with the ledger's description")
	check_has(new_text, GameTheme.money(bills.amount), "and the ledger's exact amount")
	var totals: Dictionary = session().economy.current_month_totals()
	check_eq(books.expenses_label.text, GameTheme.money(float(totals["expenses"])),
			"the totals line moved with it — it is the same numbers, not an echo of them")
	check_eq(books.cash_label.text, GameTheme.money(session().economy.cash), "as is the cash line")
	check_true(session().economy.is_consistent(), "and the books still add up end to end")
	books.free()


func test_the_books_open_only_for_company_and_cost_nothing_to_read() -> void:
	## One band, one drawer, no modals: Company opens the books, any other
	## panel choice closes them, and nothing about reading the finances
	## touches the simulation.
	var books := CompanyPanel.new()
	books.attach(view.session, input)
	var drawer := TripPanel.new()
	drawer.attach(view.session, input, view.selection, view.rig)
	input.open_panel(InputController.PANEL_TRIPS)
	check_false(books.is_open(), "the trains panel does not open the books")
	input.open_panel(InputController.PANEL_COMPANY)
	check_true(books.is_open(), "the company panel does")
	check_false(drawer.is_open(), "and the drawer steps out of the shared band")
	books.refresh_now()
	var cash := view.session.economy.cash
	var ticks: int = view.session.clock.tick_count
	input.cancel()
	check_false(books.is_open(), "Esc closes the books like any other panel")
	check_eq(input.active_panel, "", "and the controller agrees nothing is open")
	check_near(view.session.economy.cash, cash, "opening, reading and closing the books cost nothing")
	check_eq(view.session.clock.tick_count, ticks, "and froze nothing")
	check_eq(books.find_children("*", "AcceptDialog", true, false).size(), 0,
			"no dialog of any kind — the valley keeps running behind the books")
	check_eq(books.find_children("*", "ConfirmationDialog", true, false).size(), 0, "not even one")
	books.free()
	drawer.free()


# --- helpers --------------------------------------------------------------


func session() -> GameSession:
	return view.session


## The row for one train, found the way the panel keeps them: as TrainRow
## children of its list box.  Returning null is itself an assertion failure.
func _row_for(drawer: TripPanel, train_id: int) -> TrainRow:
	for child in drawer._list_box.get_children():
		var row := child as TrainRow
		if row != null and row.train_id == train_id:
			return row
	check_true(false, "the drawer built no row for train %d" % train_id)
	return null


func _rows_of(drawer: TripPanel) -> Array[TrainRow]:
	var rows: Array[TrainRow] = []
	for child in drawer._list_box.get_children():
		var row := child as TrainRow
		if row != null:
			rows.append(row)
	return rows


## The wagon list the order form is currently quoting: the selected locomotive
## plus each spinner's count.  Read from the form itself so the case rates the
## consist the panel claims to be showing, not one the test assumed.
func _form_stock(yard: TrainYard) -> Array[String]:
	var ids: Array[String] = []
	var loco_index := yard._loco_select.selected
	if loco_index >= 0:
		ids.append(String(yard._loco_select.get_item_metadata(loco_index)))
	for key in yard._counts.keys():
		var spinner: SpinBox = yard._counts[key]
		for _index in int(spinner.value):
			ids.append(String(key))
	return ids


func _stop_plan(stop_index: int, key: String) -> Array[String]:
	var train := int(line["train"])
	var stops := Array(session().routes.stops(session().trains.route_of(train)))
	return Array(stops[stop_index].get(key, []))


func _labels_of(root: Node) -> String:
	var joined := ""
	for label in root.find_children("*", "Label", true, false):
		joined += String((label as Label).text) + "\n"
	for button in root.find_children("*", "Button", true, false):
		joined += String((button as Button).text) + "\n"
	for chip in root.find_children("*", "CheckBox", true, false):
		joined += String((chip as CheckBox).text) + "\n"
	return joined


func _button_labels(root: Node) -> String:
	var joined := ""
	for button in root.find_children("*", "Button", true, false):
		joined += String((button as Button).text) + "|"
	return joined


func _button_named(root: Node, needle: String) -> Button:
	for button in root.find_children("*", "Button", true, false):
		if String((button as Button).text).contains(needle):
			return button as Button
	return null


func _press_button(root: Node, label: String) -> void:
	var button := _button_named(root, label)
	if button == null:
		check_true(false, "no button named %s was built" % label)
		return
	button.pressed.emit()
