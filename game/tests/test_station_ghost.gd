extends TestBase

## The station ghost as the player reads it on the map (spec: "Coverage is legible
## before building").  A station is bought for the ground it reaches, so the
## preview has to answer four questions before a cent moves: which cells would be
## occupied, how far its reach runs, which places actually sit inside it, and what
## they are worth a month — plus the price.
##
## Everything here is checked against a world in which nothing has been built,
## because a ghost that only tells the truth after the purchase is a receipt.


const MARLOW := "marlow"
const TOWN_CARGOS := ["passengers", "mail"]

var view: TestView
var input: InputController
var ghost: StationGhost


func setup() -> void:
	view = TestView.stage()
	input = InputController.new()
	input.attach(view.session, view.rig, view.selection)
	ghost = StationGhost.new()
	view.host.add_child(ghost)
	ghost.attach(view.session, input)


func teardown() -> void:
	# The host owns the ghost: freeing it is the test's leak check.
	input.free()
	view.dispose()
	view = null
	input = null
	ghost = null


# --- the spec's scenario: legible coverage ----------------------------------

func test_a_ghost_over_a_town_shows_yard_reach_yield_and_price_before_anything_exists() -> void:
	var town := TestSession.town_containing(view.session, MARLOW)
	var square := view.session.towns.tile_of(town)
	var anchor := _covering_anchor(square)
	check_neq(anchor, Vector2i(-1, -1), "ground beside Marlow accepts a yard that serves it")

	var stations := view.session.stations.count()
	var cash := view.session.economy.cash
	var entries := view.session.economy.ledger().size()
	input.arm_station()
	_hover(anchor)

	check_true(ghost.is_shown(), "the ghost is on the ground while the tool is in hand")
	check_eq(ghost.validity(), "ok", "on legal ground the domain's word is ok")
	var cells := WorldCoords.tiles_in_span(anchor, view.session.stations.station_def("small_station").footprint)
	check_eq(_sorted_cells(ghost.footprint_cells()), _sorted_cells(cells),
			"the yard drawn is the yard the anchor occupies")
	check_gt(float(ghost.catchment_cells().size()), 0.0, "the reach is drawn too, not just the yard")
	check_true(ghost.covered_cells().has(square),
			"the town inside the reach is marked before a station exists to serve it")
	check_gt(float(ghost.monthly_expectation().size()), 0.0, "and the ghost already says what it is worth")
	for cargo_id in TOWN_CARGOS:
		check_gt(float(ghost.monthly_expectation().get(cargo_id, 0.0)), 0.0,
				"%s are counted in the monthly promise" % cargo_id)
	check_near(ghost.cost(), view.session.builder.station_cost("small_station"),
			"the price beside the ghost is the domain's price")

	check_eq(view.session.stations.count(), stations, "hovering built nothing")
	check_near(view.session.economy.cash, cash, "and charged nothing")
	check_eq(view.session.economy.ledger().size(), entries, "with no ledger entry either")


func test_the_monthly_promise_is_the_covered_places_own_declared_output() -> void:
	var mine := TestSession.industry_by_definition(view.session, "coal_mine")
	var pit := view.session.industries.tile_of(mine)
	var anchor := _covering_anchor(pit)
	check_neq(anchor, Vector2i(-1, -1), "ground beside the colliery accepts a yard that serves it")
	input.arm_station()
	_hover(anchor)

	check_true(ghost.covered_cells().has(pit), "the colliery itself is marked")
	var promised := ghost.monthly_expectation()
	check_eq(promised.keys().size(), 1, "a yard serving only a mine promises one cargo")
	var expected := 0.0
	for entry in view.session.cargo.collect_sources():
		if ghost.covered_cells().has(Vector2i(entry["tile"])):
			expected += float(entry["rate"])
	check_near(float(promised.get("coal", 0.0)), expected,
			"the ghost's coal per month is the mine's declared output, summed independently")
	check_gt(expected, 0.0, "and the mine really does declare some")

	var readout := GhostReadout.new()
	readout.attach(view.session, input)
	_hover(anchor)
	check_has(readout.reach_label.text, "Reaches 1 place", "the readout counts the place it reaches")
	check_has(readout.reach_label.text, "Coal", "by the cargo's own display name")
	check_has(readout.reach_label.text, "20", "at the monthly figure the domain summed")
	readout.free()


func test_the_reach_is_drawn_on_the_ground_it_covers() -> void:
	var town := TestSession.town_containing(view.session, MARLOW)
	var square := view.session.towns.tile_of(town)
	var anchor := _covering_anchor(square, true)
	check_neq(anchor, Vector2i(-1, -1), "and some of that ground has a valley in it")
	input.arm_station()
	_hover(anchor)

	# The band is the reach minus the yard, which is drawn separately; the ground
	# it is compared against has to be the same set of cells.
	var ground := {}
	for cell in ghost.catchment_cells():
		if ghost.footprint_cells().has(cell):
			continue
		ground[_rounded(view.session.world.elevation_at(cell))] = true
	var mesh := ghost.band_mesh(StationGhost.BAND_CATCHMENT)
	check_true(mesh != null, "the reach is geometry, not a promise in a label")
	var drawn := {}
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex in vertices:
		drawn[_rounded(vertex.y - StationGhost.LIFT_CATCHMENT)] = true
	check_eq(_sorted_values(drawn), _sorted_values(ground),
			"every drawn height is the height of ground the band covers, and every ground height is drawn")
	check_gt(float(drawn.size()), 1.0,
			"over hills and hollows the band is not one flat sheet floating above them")


# --- what a refusal looks like ---------------------------------------------

func test_a_refused_spot_shows_the_yard_it_denies_with_the_domain_s_reason() -> void:
	var town := TestSession.town_containing(view.session, MARLOW)
	var square := view.session.towns.tile_of(town)
	var anchor := square - Vector2i(1, 2)
	# Give the site its rail access first.  Placement asks about the line before it
	# asks about the ground, so without a spur the sentence that surfaces would be
	# the missing rail and this case would prove nothing about developed ground.
	TestSession.lay_spur(view.session, Vector2i(square.x, square.y - 3))
	var cash := view.session.economy.cash
	var entries := view.session.economy.ledger().size()
	input.arm_station()
	var cursor := _hover(anchor)

	check_true(ghost.is_shown(), "a refused spot still shows a ghost — the player must see where")
	check_eq(ghost.validity(), "invalid", "and the domain's word for it is invalid")
	check_eq(ghost.footprint_cells().size(), 6, "the shape that is denied is still drawn, in red")
	check_has(ghost.reason().to_lower(), "developed ground", "the reason names what is in the way")
	check_true(ghost.catchment_cells().is_empty(), "but it promises no reach it would not have")
	check_true(ghost.covered_cells().is_empty(), "no covered places")
	check_true(ghost.monthly_expectation().is_empty(), "and no monthly yield")
	check_near(ghost.cost(), view.session.builder.station_cost("small_station"),
			"the price is still quoted, because the shelf price does not depend on the ground")

	input.build_at(cursor)
	check_eq(view.session.stations.count(), 0, "confirming an invalid ghost builds nothing")
	check_near(view.session.economy.cash, cash, "and takes no money")
	check_eq(view.session.economy.ledger().size(), entries, "and writes no ledger entry")


func test_a_yard_beyond_the_cash_is_priced_dear_rather_than_refused() -> void:
	var town := TestSession.town_containing(view.session, MARLOW)
	var square := view.session.towns.tile_of(town)
	var anchor := _covering_anchor(square)
	check_neq(anchor, Vector2i(-1, -1), "the ground itself is legal")
	view.session.economy.configure(1000.0, view.session.clock.date, view.session.company_name())
	input.arm_station()
	var cursor := _hover(anchor)

	check_eq(ghost.validity(), "expensive", "a yard the treasury cannot cover is dear, not illegal")
	check_has(ghost.reason().to_lower(), "cash", "and the reason says money, not ground")
	check_eq(ghost.footprint_cells().size(), 6, "the yard is still drawn")
	check_gt(float(ghost.catchment_cells().size()), 0.0, "with its reach")
	check_gt(float(ghost.covered_cells().size()), 0.0, "and the places it would serve")
	check_near(ghost.cost(), 20000.0, "priced as always")

	input.build_at(cursor)
	check_eq(view.session.stations.count(), 0, "and the click is still refused")
	check_near(view.session.economy.cash, 1000.0, "without a partial charge")


# --- the click and the ghost agree -----------------------------------------

func test_the_click_lands_the_yard_exactly_where_the_ghost_stood() -> void:
	var town := TestSession.town_containing(view.session, MARLOW)
	var square := view.session.towns.tile_of(town)
	var anchor := _covering_anchor(square)
	check_neq(anchor, Vector2i(-1, -1), "legal ground beside the town")
	input.arm_station()
	var cursor := _hover(anchor)

	var shown := _sorted_cells(ghost.footprint_cells())
	var promised := ghost.covered_cells().duplicate()
	input.build_at(cursor)
	check_eq(view.session.stations.count(), 1, "the click the ghost invited raised one yard")
	var station_id := int(view.session.stations.stations()[0])
	var instance := view.session.stations.station(station_id)
	check_eq(Vector2i(instance["anchor"]), anchor,
			"the yard went down on the very cells the ghost drew, not a step away")
	check_eq(_sorted_cells(WorldCoords.tiles_in_span(Vector2i(instance["anchor"]),
			Vector2i(instance["footprint"]))), shown,
			"cell for cell, the built footprint is the drawn one")
	var served: Array[Vector2i] = []
	for entry in view.session.stations.covered_sources(station_id):
		served.append(Vector2i(entry["tile"]))
	for place in promised:
		check_true(served.has(place),
				"every place the ghost marked is a place the built station really serves")


func test_the_ghost_quiets_when_the_tool_changes_and_redraws_only_when_the_answer_changes() -> void:
	var town := TestSession.town_containing(view.session, MARLOW)
	var square := view.session.towns.tile_of(town)
	var anchor := _covering_anchor(square)
	check_neq(anchor, Vector2i(-1, -1), "legal ground beside Marlow")

	input.arm_station()
	_hover(anchor)
	check_true(ghost.is_shown(), "the station tool draws it")
	var first := ghost.rebuilds()
	check_gt(float(first), 0.0, "the first look builds its geometry")

	_hover(anchor)
	_hover(anchor)
	check_eq(ghost.rebuilds(), first, "the same answer twice redraws nothing")

	_hover(anchor + Vector2i(3, 0))
	check_eq(ghost.rebuilds(), first + 1, "a different spot rebuilds it once")

	input.arm_rail()
	check_false(ghost.is_shown(), "put the station tool down and its ghost goes with it")
	check_true(ghost.footprint_cells().is_empty(), "and it stops reporting a yard it no longer draws")


func test_the_ghost_is_three_bands_on_one_material_with_nothing_to_collide() -> void:
	var town := TestSession.town_containing(view.session, MARLOW)
	var square := view.session.towns.tile_of(town)
	var anchor := _covering_anchor(square)
	input.arm_station()
	_hover(anchor)

	check_true(ghost.band_mesh(StationGhost.BAND_FOOTPRINT) != null, "the yard is drawn")
	check_true(ghost.band_mesh(StationGhost.BAND_COVERAGE) != null,
			"and so are the marks on the places it reaches")
	check_eq(TestView.count_mesh_drawables(ghost), 3,
			"the whole preview is three meshes, not a node per tile")
	check_eq(TestView.materials_in_use(ghost, {}).size(), 1,
			"and one shared translucent material does all three")
	check_eq(TestView.count_physics_objects(ghost), 0, "a preview has no shape to collide with")


# --- helpers --------------------------------------------------------------

## Point the pointer at the cell whose anchor is `anchor` — the cursor stands one
## cell right of the anchor, which is the rule the click uses too — and let the
## preview run.  Returns the cursor tile.
func _hover(anchor: Vector2i) -> Vector2i:
	var cursor := anchor + InputController.STATION_ANCHOR_OFFSET
	view.look_at_tile(cursor)
	input._update_ghost_at_mouse(view.screen_of_tile(cursor))
	return cursor


## A spot where a station may stand *and* which reaches `tile`, in one fixed
## order.  With `varied` the ground inside the catchment must run over more than
## one height — that is what makes a drape testable rather than assertable.
func _covering_anchor(tile: Vector2i, varied: bool = false) -> Vector2i:
	var spur := TestSession.lay_spur(view.session, Vector2i(tile.x, tile.y - 3))
	if not bool(spur["ok"]):
		return Vector2i(-1, -1)
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var anchor := Vector2i(tile.x + dx, tile.y + dy)
			var preview := view.session.builder.preview_station("small_station", anchor)
			if not bool(preview["ok"]) or not TestSession.preview_covers(preview, tile):
				continue
			if varied and not _varied_ground(Array(preview["catchment"])):
				continue
			return anchor
	return Vector2i(-1, -1)


func _varied_ground(cells: Array) -> bool:
	var heights := {}
	for cell in cells:
		heights[_rounded(view.session.world.elevation_at(Vector2i(cell)))] = true
	return heights.size() > 1


func _sorted_cells(cells: Array[Vector2i]) -> Array[String]:
	var names: Array[String] = []
	for cell in cells:
		names.append("%d:%d" % [cell.x, cell.y])
	names.sort()
	return names


func _sorted_values(values: Dictionary) -> Array[float]:
	var list: Array[float] = []
	for value in values.keys():
		list.append(float(value))
	list.sort()
	return list


func _rounded(value: float) -> float:
	return roundf(value * 1000.0) / 1000.0
