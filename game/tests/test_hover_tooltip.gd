class_name TestHoverTooltip
extends TestBase

## Spec §71: hover gives lightweight information and "should not replace
## selection for detailed information".
##
## The second half of that sentence is the dangerous half, because the obvious
## implementation — show the tooltip *by* selecting the hovered thing, so the
## inspector can supply the text — is the one that breaks the game.  Every sweep
## of the mouse across the valley would then rewrite the player's selection, the
## inspector, the camera target and a train-follow lock.  So the cases here drive
## the pointer through the real entry point (`SelectionService.point_at`), and
## the first thing they count afterwards is how often the selection moved: zero.
## The information half is graded against §71's own example line.

var _view: TestView
var _tip: HoverTooltip
var _selection_changes := 0


func setup() -> void:
	_view = TestView.stage("founders_valley")
	_tip = HoverTooltip.new()
	_tip.attach(_view.session, _view.selection)
	_tip.viewport_size = TestView.VIEWPORT_SIZE
	_view.selection.selection_changed.connect(
			func(_kind: String, _id: int, _tile: Vector2i) -> void: _selection_changes += 1)
	_selection_changes = 0


func teardown() -> void:
	if _tip != null:
		_tip.free()
		_tip = null
	if _view != null:
		_view.dispose()
		_view = null


func test_hovering_a_yard_names_it_and_says_what_waits() -> void:
	var yard := _yard_at_the_colliery()
	_view.session.stations.add_cargo(yard, "passengers", 37.0)
	_look_at(_view.session.stations.tile_of(yard))
	_view.selection.point_at(_view.screen_of_tile(_a_tile_the_station_owns(yard)))

	check_true(_tip.is_showing(), "the pointer over a yard raises the tip")
	check_eq(_tip.showing_kind(), SelectionService.KIND_STATION, "for the yard, not for the ground")
	check_has(_tip.text(), "Marlow Yard", "by the name the player gave it")
	check_has(_tip.text(), "37 cargo waiting", "and §71's own line: the name plus what is waiting")


func test_a_hover_never_selects_anything() -> void:
	var yard := _yard_at_the_colliery()
	_look_at(_view.session.stations.tile_of(yard))
	_view.selection.point_at(_view.screen_of_tile(_a_tile_the_station_owns(yard)))

	check_true(_tip.is_showing(), "the question was asked")
	check_false(_view.selection.has_selection(), "and no selection was made to answer it")
	check_eq(_selection_changes, 0, "the UI was never told to move its inspector")

	_view.selection.point_at(_view.screen_of_tile(_view.session.towns.tile_of(
			_view.session.towns.towns()[0])))
	check_eq(_selection_changes, 0, "asking about a town is no different")


func test_a_train_under_the_pointer_reports_its_status() -> void:
	var line := TestSession.coal_line(_view.session)
	check_true(bool(line["ok"]), "a working coal line is the fixture: " + String(line["reason"]))
	var train := int(line["train"])
	# A consist sits on its platform until its first load completes, and at the pace
	# the world's scale gives the train that outlasts any fixed count of ticks.  The
	# state the tooltip is meant to report is waited for, not assumed.
	TestSession.run_until(_view.session,
			func() -> bool: return _view.session.trains.state_label(train) == "Moving",
			TestSession.LEG_TICKS)
	# One read of where it stands, then the camera is let land there before the
	# pointer goes: the rig glides, and pointing while it is still travelling puts
	# the tile off the screen.
	var under := Vector2i(_view.session.trains.position_tiles(train))
	_look_at(under)
	_view.run_frame()
	_view.selection.point_at(_view.screen_of_tile(under))

	check_eq(_tip.showing_kind(), SelectionService.KIND_TRAIN,
			"a train is read before the track it stands on")
	check_has(_tip.text(), _view.session.trains.name_of(train), "named as the player named it")
	check_has(_tip.text(), _view.session.trains.state_label(train), "with the status it is in")
	check_has(_tip.text(), "km/h", "and how fast it is going")


func test_bare_ground_and_a_lonely_rail_are_not_worth_a_tooltip() -> void:
	var yard := _yard_at_the_colliery()
	_look_at(_view.session.stations.tile_of(yard))
	_view.selection.point_at(_view.screen_of_tile(_a_tile_the_station_owns(yard)))
	check_true(_tip.is_showing(), "the yard does raise it")

	var open_ground := _find_open_ground(_view.session.stations.tile_of(yard))
	_view.selection.point_at(_view.screen_of_tile(open_ground))
	check_false(_tip.is_showing(), "and the pointer moving onto bare grass puts it away")


func test_the_tip_is_kept_inside_the_view() -> void:
	var yard := _yard_at_the_colliery()
	_look_at(_view.session.stations.tile_of(yard))
	_view.selection.point_at(_view.screen_of_tile(_a_tile_the_station_owns(yard)))
	check_true(_tip.is_showing(), "the tip is up before it is pushed at a corner")

	var size := _tip.get_minimum_size()
	_tip.move_to(TestView.VIEWPORT_SIZE - Vector2(4.0, 4.0))
	check_le(_tip.position.x + size.x, TestView.VIEWPORT_SIZE.x,
			"against the right edge it flips to the other side of the cursor")
	check_le(_tip.position.y + size.y, TestView.VIEWPORT_SIZE.y, "and the same at the bottom")

	_tip.move_to(Vector2(2.0, 2.0))
	check_ge(_tip.position.x, 0.0, "top-left it stays on screen as well")
	check_ge(_tip.position.y, 0.0, "both ways")


# --- helpers -----------------------------------------------------------------

func _yard_at_the_colliery() -> int:
	var mine := TestSession.industry_by_definition(_view.session, "coal_mine")
	var tile := _view.session.industries.tile_of(mine)
	var yard := TestSession.serve(_view.session, tile, "Marlow Yard")
	check_gt(yard, 0, "a yard at the colliery is the fixture this file needs")
	return yard


## Point the rig at a tile so the pixel built from it is inside the view.
func _look_at(tile: Vector2i) -> void:
	_view.look_at_tile(tile)
	_view.zoom_to(18.0)


## A station covers a footprint, and only some of it is the tile the resolver
## reports; ask the grid which cells are the yard's and use one of those.
func _a_tile_the_station_owns(station_id: int) -> Vector2i:
	var anchor := _view.session.stations.tile_of(station_id)
	for dy in range(-1, 4):
		for dx in range(-2, 4):
			var tile := Vector2i(anchor.x + dx, anchor.y + dy)
			if _view.session.world.occupancy_at(tile) == WorldGrid.Occupancy.STATION \
					and _view.session.world.occupancy_entity(tile) == station_id:
				return tile
	return anchor


func _find_open_ground(near: Vector2i) -> Vector2i:
	for radius in range(4, 24):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var tile := Vector2i(near.x + dx, near.y + dy)
				if _view.session.world.occupancy_at(tile) != WorldGrid.Occupancy.NONE:
					continue
				if _view.session.world.has_rail_cell(tile):
					continue
				return tile
	return near + Vector2i(40, 40)
