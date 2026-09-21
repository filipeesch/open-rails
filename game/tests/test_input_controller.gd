class_name TestInputController
extends TestBase

## The Escape ladder.
##
## Escape is the one key a player hits when they are already unsure, so its
## contract has to be dead simple: it backs out of exactly one level per press —
## the armed tool first, then the open panel, then the selection — and it never
## touches the simulation on the way.

var view: TestView
var controller: InputController
var _changes := 0


func setup() -> void:
	view = TestView.stage()
	controller = InputController.new()
	controller.attach(view.session, view.rig, view.selection)
	view.selection.selection_changed.connect(
		func(_kind: String, _id: int, _tile: Vector2i) -> void: _changes += 1)
	_changes = 0


func teardown() -> void:
	controller.free()
	view.dispose()
	controller = null
	view = null


func test_escape_backs_out_of_the_armed_tool_before_it_touches_the_selection() -> void:
	var selected := _select_a_station()
	controller.rail_start = Vector2i(20, 20)

	controller.arm_tool(InputController.TOOL_RAIL)
	check_eq(controller.tool, InputController.TOOL_RAIL, "the rail tool is armed")

	controller.cancel()
	check_eq(controller.tool, InputController.TOOL_NONE, "one press puts the tool down")
	check_eq(controller.rail_start, Vector2i(-1, -1), "and forgets the half-started run")
	check_eq(view.selection.selected_id, selected, "but it does not steal the selection as well")
	check_eq(_changes, 0, "and it says nothing to the UI about selection")

	controller.cancel()
	check_false(view.selection.has_selection(), "the next press is the one that lets go of it")
	check_eq(view.selection.selected_tile, Vector2i(-1, -1), "with no tile left highlighted")
	check_eq(_changes, 1, "and the UI is told exactly once")


func test_escape_closes_the_open_panel_before_it_lets_go_of_the_selection() -> void:
	var selected := _select_a_station()
	var panels: Array[String] = []
	controller.panel_requested.connect(func(panel: String) -> void: panels.append(panel))
	controller.active_panel = InputController.PANEL_TRIPS

	controller.cancel()
	check_eq(controller.active_panel, "", "the trips panel is closed")
	check_eq(panels.size(), 1, "and the HUD is told to close it")
	check_eq(panels[0], "", "with the empty name, meaning nothing is open")
	check_eq(view.selection.selected_id, selected, "the thing the panel was opened about stays selected")

	controller.cancel()
	check_false(view.selection.has_selection(), "only the following press clears the selection")


func test_escape_with_nothing_pending_leaves_the_simulation_alone() -> void:
	var clock: int = view.session.clock.tick_count
	var cash: float = view.session.economy.cash
	var month := _month_key()

	controller.cancel()
	controller.cancel()
	controller.cancel()

	check_eq(view.session.clock.tick_count, clock, "three presses advanced no simulation")
	check_near(view.session.economy.cash, cash, "and charged nothing")
	check_eq(_month_key(), month, "and crossed no month")
	check_eq(controller.tool, InputController.TOOL_NONE, "the tool state is still at rest")
	check_eq(_changes, 0, "with nothing to clear, no event was invented")


## A station is the one selection this suite can name exactly: the tile under a
## cursor depends on the map, the station id does not.
func _select_a_station() -> int:
	var l := TestSession.coal_line(view.session)
	check_true(bool(l["ok"]), "there is a station to point at: " + String(l["reason"]))
	view.selection.select_station(int(l["mine_station"]))
	check_true(view.selection.has_selection(), "the station is selected before the first press")
	_changes = 0
	return int(l["mine_station"])


func _month_key() -> String:
	return "%d-%02d" % [view.session.clock.date.year, view.session.clock.date.month]


func test_pausing_stops_the_valley_but_not_the_player() -> void:
	## Pause freezes the simulation, not the game.  Trains and the calendar hold
	## their place while the camera, the pointer and the panels keep answering —
	## otherwise a player cannot plan an edit, which is the whole point of pausing.
	var l := TestSession.coal_line(view.session)
	check_true(bool(l["ok"]), "a train is running to be stopped: " + String(l["reason"]))
	var train := int(l["train"])
	for frame in 120:
		view.session.clock.feed(1.0 / 60.0)
	check_near(view.session.clock.speed(), 1.0, "the clock is running before it is stopped", 0.001)
	var position_before := view.session.trains.position_tiles(train)

	view.session.clock.set_speed_index(0)
	check_true(view.session.clock.is_paused(), "the clock is stopped")
	var ticks: int = view.session.clock.tick_count
	var month := _month_key()
	for frame in 240:
		view.session.clock.feed(1.0 / 60.0)

	check_eq(view.session.clock.tick_count, ticks, "four seconds of real time advanced no simulation")
	check_eq(_month_key(), month, "the calendar stands still")
	check_near(view.session.trains.position_tiles(train).distance_to(position_before), 0.0,
			"and the train holds the place it was stopped in", 0.0001)

	var target_before := view.rig.target
	view.rig.pan_tiles(Vector2(8.0, 0.0))
	view.settle()
	check_gt(view.rig.target.distance_to(target_before), 4.0,
			"the camera still pans across the frozen valley")
	var size_before := view.rig.ortho_size
	view.rig.zoom_by(-2.0)
	view.settle()
	check_neq(view.rig.ortho_size, size_before, "and still zooms")

	view.selection.select_station(int(l["mine_station"]))
	check_eq(view.selection.selected_id, int(l["mine_station"]), "a station still selects")
	controller.open_panel(InputController.PANEL_TRIPS)
	check_eq(controller.active_panel, InputController.PANEL_TRIPS, "and a panel still opens")
	check_eq(view.session.clock.tick_count, ticks, "none of that woke the simulation")
