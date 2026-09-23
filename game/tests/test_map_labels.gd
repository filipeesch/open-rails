class_name TestMapLabels
extends TestBase

## Spec §72: map labels are zoom-dependent, they live on one pooled screen-space
## layer, and a close view keeps only what the player selected.
##
## Two promises are being graded here.  The first is the visible one — which
## names appear at which distance — and it is graded against the rig's own
## settled zoom, never a number written into the label layer.  The second is the
## one that decides whether the feature is allowed to exist at all: the layer is
## a *pool*.  A valley with forty named places must not own forty `Label` nodes,
## because §112's whole argument against a node per thing applies to text as much
## as to tiles.  So a case counts the layer's children before and after a scan
## over more places than the pool can show, and the count has to be a constant.

const ZOOM_FAR_VIEW := 96.0
const ZOOM_MEDIUM_VIEW := 28.0
const ZOOM_CLOSE_VIEW := 4.0
## Enough yards, towns and works to overflow the pool, so the bound is tested
## against a candidate list that actually needs bounding.
const STATIONS_TO_BUILD := 26
const TOWNS_TO_BUILD := 12

var _view: TestView
var _labels: MapLabels


func setup() -> void:
	_view = TestView.stage("founders_valley")
	_labels = MapLabels.new()
	_labels.attach(_view.session, _view.rig)
	_labels.attach_selection(_view.selection)
	_labels.viewport_size = TestView.VIEWPORT_SIZE


func teardown() -> void:
	if _labels != null:
		_labels.free()
		_labels = null
	if _view != null:
		_view.dispose()
		_view = null


# --- the bands ---------------------------------------------------------------

func test_far_zoom_names_the_towns_and_the_works_and_nothing_else() -> void:
	var yard := _build_a_yard()
	var mine := TestSession.industry_by_definition(_view.session, "coal_mine")
	var mine_tile := _view.session.industries.tile_of(mine)
	var town := _town_nearest(mine_tile)
	_view.look_at_tile(mine_tile)
	_view.zoom_to(ZOOM_FAR_VIEW)
	_labels.refresh()

	check_true(_labels.is_showing(mine), "a work is named from far out: §72's far row carries major industries")
	check_true(_labels.is_showing(town), "and so is the town beside it")
	check_has(_labels.text_of(town), "Marlow", "and it is the valley's own town, not a fixture")
	check_false(_labels.is_showing(yard), "but a yard is not: the far row does not list yards")


func test_medium_zoom_adds_the_yards() -> void:
	var yard := _build_a_yard()
	_view.look_at_tile(_view.session.stations.tile_of(yard))
	_view.zoom_to(ZOOM_MEDIUM_VIEW)
	_labels.refresh()

	check_true(_labels.is_showing(yard), "at medium zoom the yards are named too")
	check_ge(_labels.shown_count(), 2, "alongside the places the far view already named")


func test_close_zoom_withholds_every_name_the_player_did_not_ask_for() -> void:
	var yard := _build_a_yard()
	var town := _first_town()
	_view.look_at_tile(_view.session.stations.tile_of(yard))
	_view.zoom_to(ZOOM_CLOSE_VIEW)
	_labels.refresh()

	check_eq(_labels.shown_count(), 0,
			"a close view carries no labels at all, so it is not covered in text")
	check_false(_labels.is_showing(yard), "not the yard under the camera")
	check_false(_labels.is_showing(town), "and not the town beyond it")


func test_the_thing_the_player_selected_keeps_its_name_close_in() -> void:
	var yard := _build_a_yard()
	_view.look_at_tile(_view.session.stations.tile_of(yard))
	_view.zoom_to(ZOOM_CLOSE_VIEW)
	_labels.refresh()
	check_false(_labels.is_showing(yard), "unselected, it is unnamed at this zoom")

	_view.selection.select(SelectionService.KIND_STATION, yard,
			_view.session.stations.tile_of(yard))
	_labels.refresh()

	check_true(_labels.is_showing(yard), "selected, the same yard keeps its name at the same zoom")
	check_has(_labels.text_of(yard), "Marlow Yard", "and the label carries the yard's own name")


# --- the pool ----------------------------------------------------------------

func test_the_layer_owns_one_pool_of_labels_however_many_places_exist() -> void:
	var overflow := TestView.stage_blank(128, 128)
	var crowded := MapLabels.new()
	crowded.attach(overflow.session, overflow.rig)
	crowded.viewport_size = TestView.VIEWPORT_SIZE
	var built := _crowd_the_valley(overflow)
	var places := built + _seed_towns(overflow, TOWNS_TO_BUILD) \
			+ overflow.session.industries.count()
	check_gt(places, MapLabels.POOL_SIZE,
			"the fixture has more named places than the pool has slots, so the bound is real")

	var nodes_before := crowded.label_nodes()
	overflow.look_at_tile(Vector2i(64, 20))
	overflow.zoom_to(ZOOM_MEDIUM_VIEW)
	crowded.refresh_now()

	check_eq(nodes_before, MapLabels.POOL_SIZE, "the pool is built once, at its cap")
	check_eq(crowded.label_nodes(), MapLabels.POOL_SIZE,
			"and scanning %d places added no node" % places)
	check_le(crowded.shown_count(), MapLabels.POOL_SIZE,
			"at most one label per pool slot is claimed, however many places qualify")
	check_gt(crowded.shown_count(), 0, "and the pool is not simply empty")

	crowded.free()
	overflow.dispose()


func test_a_label_sits_over_the_place_it_names() -> void:
	var town := _first_town()
	var tile := _view.session.towns.tile_of(town)
	_view.look_at_tile(tile)
	_view.zoom_to(ZOOM_FAR_VIEW)
	_labels.refresh()

	var shown := _labels.visible_labels()
	check_gt(shown.size(), 0, "the far view shows names")
	var entry := _entry_for(shown, town)
	check_true(not entry.is_empty(), "the town is among them")

	var expected := _view.rig.world_to_screen(
			_view.rig.tile_to_world(Vector2(tile.x + 0.5, tile.y + 0.5)), _view.rect())
	check_near((entry["screen"] as Vector2).distance_to(expected), 0.0,
			"the label's screen position is where the rig says the town is", 1.0)
	# …and in absolute pixels, which is the claim that actually reaches a screen. The
	# two lines above agree by construction: whatever unit the rig answers in, the
	# label agrees with it. A rig returning a fraction of the viewport rather than a
	# pixel put every name in the valley at the top-left corner — on top of the date
	# in the top bar — and this file stayed green, because nothing asked where the
	# name landed in the pixels a player reads.
	var centre := _view.rect().size * 0.5
	check_lt((entry["screen"] as Vector2).distance_to(centre), 6.0,
			"a town the camera is aimed at is named at the middle of the window")

	var painted := _first_visible_label()
	check_true(painted != null, "a pooled label was painted")
	check_true(painted.visible, "and it is the visible kind")
	check_has(painted.text, _view.session.towns.name_of(town), "with the town's name on it")
	# The rig projects in 32-bit floats and this expectation is 64-bit, so a
	# hundredth of a pixel is the tightest honest tolerance here.
	check_near(painted.position.y, expected.y + MapLabels.LEADING.y,
			"sitting above the tile it names, not on top of it", 0.01)
	# The one claim a player actually makes about a name: which pixels it covers.
	# Measured from the node, not from the layer's own numbers.
	var painted_centre_x := painted.position.x + painted.get_minimum_size().x * 0.5
	check_lt(painted_centre_x - centre.x, 60.0,
			"the painted name is over the map, not stacked against the left edge of the window")


func test_a_place_the_player_cannot_see_is_named_nowhere() -> void:
	var towns: Array[int] = _view.session.towns.towns()
	check_ge(towns.size(), 2, "the authored valley has two towns a view can separate")
	var here := towns[0]
	var there := towns[1]
	_view.look_at_tile(_view.session.towns.tile_of(here))
	_view.zoom_to(ZOOM_MEDIUM_VIEW)
	_labels.refresh()

	check_true(_labels.is_showing(here), "the town the camera is aimed at is named")
	check_false(_labels.is_showing(there),
			"and the town across the valley is not: a name for ground nobody is looking at "
			+ "has nowhere honest to go, so it used to pile up in the corner of the window")

	# The other half of the same promise: a name that is shown is inside the frame
	# the chrome leaves free.  Names used to be allowed anywhere in the window, and
	# the top bar and the tool bar both claimed the same pixels.
	var frame := Rect2(
			Vector2(MapLabels.INSIDE_SIDE, MapLabels.INSIDE_TOP),
			TestView.VIEWPORT_SIZE - Vector2(MapLabels.INSIDE_SIDE * 2.0,
					MapLabels.INSIDE_TOP + MapLabels.INSIDE_BOTTOM))
	var named := _labels.visible_labels()
	check_gt(named.size(), 0, "and there is something to check")
	for entry in named:
		check_true(frame.has_point(entry["screen"] as Vector2),
				"%s is named inside the map, clear of the top bar and the tool bar" % entry["text"])


func test_the_detail_line_is_the_number_the_spec_shows() -> void:
	var yard := _build_a_yard()
	_view.session.stations.add_cargo(yard, "passengers", 37.0)
	_view.look_at_tile(_view.session.stations.tile_of(yard))
	_view.zoom_to(ZOOM_MEDIUM_VIEW)
	_labels.refresh()

	var painted := _label_for(yard)
	check_true(painted != null, "the yard is labelled")
	check_has(painted.text, "37 cargo waiting",
			"and §71's example line — the name plus what is waiting — is what it says")


func test_no_place_is_named_twice_on_the_map() -> void:
	var yard := _build_a_yard()
	var line := TestSession.coal_line(_view.session)
	check_true(bool(line["ok"]), "a consist to be the one thing named twice-over: " + String(line["reason"]))
	_view.look_at_tile(_view.session.stations.tile_of(yard))
	_view.zoom_to(ZOOM_MEDIUM_VIEW)
	_labels.refresh_now()
	_view.entities.tick()

	check_true(_labels.is_showing(yard), "the yard's name is the map layer's to draw")
	check_eq(_view.entities.label_count(), 1,
			"the entity renderer names only the train it has to follow, never a place")
	check_eq(float(_view.entities.visible_label_count()), 1.0, "and that one name is on screen")


func test_the_shipped_scene_gives_the_names_and_the_pointer_their_own_layers() -> void:
	var packed := load("res://scenes/Game.tscn") as PackedScene
	check_true(packed != null, "the game scene loads")
	var game := packed.instantiate()
	var labels_layer := game.get_node_or_null("UI/MapLabels")
	var tip_layer := game.get_node_or_null("UI/Tooltips")
	check_true(labels_layer is Control, "the map names draw on their own UI layer")
	check_true(tip_layer is Control, "and the pointer's tip draws on its own, above them")
	check_eq((labels_layer as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE,
			"neither layer steals a click from the valley underneath")
	check_eq((tip_layer as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE,
			"a tooltip you can click through is a tooltip that never blocks a build")
	game.free()


# --- helpers -----------------------------------------------------------------

func _build_a_yard() -> int:
	var mine := TestSession.industry_by_definition(_view.session, "coal_mine")
	var tile := _view.session.industries.tile_of(mine)
	var yard := TestSession.serve(_view.session, tile, "Marlow Yard")
	check_gt(yard, 0, "a yard at the colliery is a fixture this file depends on")
	return yard


func _town_nearest(tile: Vector2i) -> int:
	var best := 0
	var best_distance := 1 << 30
	for town_id in _view.session.towns.towns():
		var distance := (_view.session.towns.tile_of(town_id) - tile).length_squared()
		if distance < best_distance:
			best_distance = distance
			best = town_id
	check_gt(best, 0, "the authored valley has a town beside the works")
	return best


func _first_town() -> int:
	var towns: Array[int] = _view.session.towns.towns()
	check_gt(towns.size(), 0, "the authored valley has towns to name")
	return towns[0]


## Yards along one through-line, spaced so their footprints can stand.
func _crowd_the_valley(view: TestView) -> int:
	var run: Array[Vector2i] = []
	for x in range(8, 120):
		run.append(Vector2i(x, 20))
	check_true(bool(view.session.builder.build_track_run(run)["ok"]),
			"the crowded fixture has a line to stand beside")
	var built := 0
	for index in STATIONS_TO_BUILD:
		# One row off the line: a yard couples to the ground its platform stands
		# against, so a yard set back from the rails is not a yard the game accepts.
		var anchor := Vector2i(10 + index * 4, 18)
		var reason := view.session.stations.placement_reason("small_station", anchor)
		if reason != "":
			continue
		var made := view.session.stations.build("small_station", anchor, "Yard %d" % index)
		if bool(made["ok"]):
			built += 1
	check_ge(built, STATIONS_TO_BUILD - 2,
			"the yards the fixture asked for were placed (%d stood)" % built)
	return built


func _seed_towns(view: TestView, count: int) -> int:
	var entries: Array = []
	for index in count:
		entries.append({
			"id": view.session.ids.next_id(),
			"name": "Fixture Town %d" % index,
			"population": 800,
			"x": 20 + index * 8,
			"y": 60,
			"passengers_per_month": 12.0,
			"mail_per_month": 6.0,
		})
	view.session.towns.from_dict({"towns": entries})
	return count


func _entry_for(shown: Array[Dictionary], entity_id: int) -> Dictionary:
	for entry in shown:
		if int(entry["id"]) == entity_id:
			return entry
	return {}


func _first_visible_label() -> Label:
	for child in _labels.get_children():
		if child is Label and (child as Label).visible:
			return child as Label
	return null


func _label_for(entity_id: int) -> Label:
	for child in _labels.get_children():
		if not (child is Label) or not (child as Label).visible:
			continue
		if (child as Label).text.begins_with(_view.session.stations.name_of(entity_id)):
			return child as Label
	return null
