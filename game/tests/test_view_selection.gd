class_name TestViewSelection
extends TestBase

## Tasks 5.1 – 5.5 (selection by ray march, with no physics anywhere in the
## path) and 6.1 (the presentation layer assembled the way the shipped game
## assembles it, over the full 256 × 256 world).
##
## Every pick here goes through the same entry point the player's mouse does:
## `pick_tile(screen)`, `point_at(screen)`, `select_at_screen(screen)`, with the
## viewport size authored on the service because the harness has no window.
## There is no test-only picking code that can be right while the game's is wrong.

## Reference pick: solved tile by tile rather than marched, so the thing the
## service is graded against is not another march.  A tile top is a horizontal
## plane and the ray's height is linear along it, so where the two meet is
## arithmetic; walking boundary to boundary takes the first meeting exactly.
const REFERENCE_LIMIT := 620.0
const REFERENCE_FLOOR := -4.0
## A march that stops at its first step: what the service would do without the
## refine, kept as the counter-example.
const NAIVE_STEP := 0.5
## A contact this close to a tile edge is a coin toss for any implementation, so
## those pixels are counted rather than graded.
const MARGIN_TILES := 0.05
const COLUMNS_TO_WALK := 1400
const MIN_FIRM_PIXELS := 15
const MAX_TOSS_PIXELS := 6

var _view: TestView


func teardown() -> void:
	if _view != null:
		_view.dispose()
		_view = null


# --- 5.1 march and refine --------------------------------------------------

func test_a_pixel_on_flat_ground_picks_the_tile_it_shows() -> void:
	_view = TestView.stage_blank(64, 64)
	var grid := _view.grid()
	var wrong := 0
	var checked := 0
	for offset_x in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		for offset_y in [-6.0, 0.0, 6.0]:
			var tile := Vector2i(32 + int(offset_x), 32 + int(offset_y))
			var pixel := _view.screen_of_tile(tile)
			var picked := _view.selection.pick_tile(pixel)
			checked += 1
			if picked != tile:
				wrong += 1
			# The answer must survive the trip back: the tile picked is the one
			# whose surface sits at that pixel.
			var back := _view.rig.project_point(_view.surface_point(picked), _view.rect())
			if back.distance_to(pixel) > 0.75:
				wrong += 1
	check_eq(checked, 15, "fifteen pixels were picked")
	check_eq(wrong, 0, "every pixel resolved to the tile under it, and back again")
	check_eq(grid.elevation_at(Vector2i(10, 10)), 0.0, "this fixture is flat at the datum")


func test_a_pixel_on_a_slope_picks_the_tile_under_it_not_one_step_past_it() -> void:
	_view = TestView.stage_blank(64, 64)
	var grid := _view.grid()
	for y in grid.height:
		for x in grid.width:
			grid.set_height(Vector2i(x, y), clampi(int(float(x) / 2.0), 0, 24))
	_view.drain_rebuilds()
	_view.look_at_tile(Vector2i(32, 30))

	check_lt(SelectionService.REFINE_SETTLE, 0.05,
		"the seam rule pushes a finished hit well under a tile of ground, never across an edge")

	var disagreements := 0
	var naive_errors := 0
	var firm := 0
	var coin_toss := 0
	# A pointer sweep straight across the slope, not just tile centres: the refine
	# only matters for the pixels whose crossing falls near a tile boundary, and a
	# sweep is what a moving mouse actually produces.
	for column in 24:
		var pixel := Vector2(568.0 + float(column) * 8.0, 330.0)
		var ray := _view.selection.pick_ray(pixel)
		check_false(ray.is_empty(), "a pointer ray exists at every pixel")
		var answer := _contact_tile(ray)
		var reference: Vector2i = answer["tile"]
		var origin: Vector3 = ray["origin"]
		var direction: Vector3 = ray["direction"]
		var picked := _view.selection.pick_at(origin, direction)
		if float(answer["margin"]) < MARGIN_TILES:
			coin_toss += 1
			continue
		firm += 1
		if picked != reference:
			disagreements += 1
		var touch: Vector3 = answer["point"]
		check_le(absf(touch.y - grid.elevation_at(picked)), 0.001,
			"the tile answered for is ground at the height the ray met")
		if _naive_march_tile(ray) != reference:
			naive_errors += 1
	check_ge(float(firm), float(MIN_FIRM_PIXELS), "most of the sweep landed firmly inside a tile")
	check_le(float(coin_toss), float(MAX_TOSS_PIXELS),
		"a handful of pixels touch the ground on a tile edge, where no march can be right")
	check_eq(disagreements, 0,
		"every firm pixel agrees with the heightfield solved exactly, tile by tile")
	check_gt(float(naive_errors), 0.0,
		"a march that stops at its first step gets at least one of them wrong: that is what the refine is for")
	for tile in [Vector2i(26, 30), Vector2i(32, 30), Vector2i(38, 30)]:
		check_eq(_view.selection.pick_tile(_view.screen_of_tile(tile)), tile,
			"and the middle of a slope tile still resolves to that tile")


# --- 5.2 picking what is there, without bodies ----------------------------

func test_a_station_click_selects_the_station_and_nothing_holds_a_body() -> void:
	_view = TestView.stage()
	var session := _view.session
	var mine := TestSession.industry_by_definition(session, "coal_mine")
	var station_id := TestSession.serve(session, session.industries.tile_of(mine), "Test Wharf")
	check_gt(station_id, 0, "a station was built beside the colliery")
	var station_tile: Vector2i = session.stations.tile_of(station_id)
	_view.look_at_tile(station_tile)
	var pixel := _view.screen_of_tile(station_tile)

	_view.selection.select_at_screen(pixel)
	check_eq(_view.selection.selected_kind, SelectionService.KIND_STATION, "the click selected a station")
	check_eq(_view.selection.selected_id, station_id, "and the right station, by its stable id")
	check_true(_view.selection.has_selection(), "so there is a selection")
	check_eq(_view.selection.selection_label(), session.stations.name_of(station_id),
		"the label the inspector shows is the station's own name")

	var hover_events: Array[Array] = []
	var cargo_events: Array[Array] = []
	var on_hover := func(tile: Vector2i) -> void:
		hover_events.append([tile])
	var on_cargo := func(station: int, summary: Array[Dictionary]) -> void:
		cargo_events.append([station, summary.size()])
	_view.selection.tile_hovered.connect(on_hover)
	_view.selection.hover_cargo.connect(on_cargo)
	_view.selection.point_at(pixel)
	check_eq(_view.selection.hovered_kind, SelectionService.KIND_STATION,
		"hover names it as a station before anything is clicked")
	check_eq(_view.selection.hovered_id, station_id, "with the same id")
	check_eq(hover_events.size(), 1, "and announces the tile once")
	check_eq(cargo_events.size(), 1, "hovering a station pulls up its inventory for the tooltip")

	check_eq(TestView.count_physics_objects(_view.host), 0,
		"none of this needed a physics body, a collider or a picking node")


# --- 5.3 trains come first ------------------------------------------------

func test_a_train_is_picked_before_what_it_is_standing_on() -> void:
	_view = TestView.stage()
	var session := _view.session
	var line := TestSession.coal_line(session)
	check_true(bool(line["ok"]), "a train on a working line is the thing to click")
	var train_id := int(line["train"])
	var trains: TrainService = session.trains
	var on_tile := Vector2i(trains.position_tiles(train_id))
	_view.look_at_tile(on_tile)

	var pixel := _view.rig.world_to_screen(_view.selection.train_anchor(train_id), _view.rect())
	pixel = pixel * TestView.VIEWPORT_SIZE
	var hit := _view.selection.resolve_entity(on_tile, pixel)
	check_eq(hit["kind"], SelectionService.KIND_TRAIN,
		"a pixel over a train resolves to the train, whatever is under it")
	check_eq(hit["id"], train_id, "and to that particular train")
	_view.selection.select_at_screen(pixel)
	check_eq(_view.selection.selected_kind, SelectionService.KIND_TRAIN, "the click selects it")
	check_eq(_view.selection.selected_id, train_id, "by id")

	var tile_hit := _view.selection.resolve_entity(on_tile, Vector2(-1.0, -1.0))
	check_eq(tile_hit["kind"], SelectionService.KIND_TRAIN, "a tile-space commit finds the train on it too")

	var elsewhere := _find_rail_tile_near(on_tile, 6)
	check_neq(elsewhere, Vector2i(-1, -1), "there is track nearby to click instead")
	var other := _view.selection.resolve_entity(elsewhere, _view.screen_of_tile(elsewhere))
	check_neq(other["kind"], SelectionService.KIND_TRAIN,
		"and away from the train the same code does not invent one")
	check_eq(other["kind"], SelectionService.KIND_RAIL, "out there it is the track itself")


# --- 5.4 state, signal, and clearing ---------------------------------------

func test_selection_state_and_signal_and_empty_ground_clears_it() -> void:
	_view = TestView.stage()
	var session := _view.session
	var selection := _view.selection
	var signals: Array[Array] = []
	var listener := func(kind: String, entity_id: int, tile: Vector2i) -> void:
		signals.append([kind, entity_id, tile])
	selection.selection_changed.connect(listener)

	var mine := TestSession.industry_by_definition(session, "coal_mine")
	var station_id := TestSession.serve(session, session.industries.tile_of(mine), "Test Wharf")
	selection.select_station(station_id)
	check_eq(selection.selected_kind, SelectionService.KIND_STATION, "selecting a station sets the kind")
	check_eq(selection.selected_id, station_id, "the id")
	check_eq(selection.selected_tile, session.stations.tile_of(station_id), "and its tile")
	check_eq(signals.size(), 1, "and announced it to whoever is listening")

	var empty_tile := _find_empty_tile(Vector2i(120, 120))
	check_neq(empty_tile, Vector2i(-1, -1), "the valley has bare ground to click")
	_view.look_at_tile(empty_tile)
	selection.select_at_screen(_view.screen_of_tile(empty_tile))
	check_false(selection.has_selection(), "clicking empty ground selects nothing")
	check_eq(selection.selected_kind, SelectionService.KIND_NONE, "the kind says so")
	check_eq(selection.selected_tile, Vector2i(-1, -1), "and no tile is held on to")
	check_eq(signals.size(), 2, "the clear was announced too")

	selection.select_station(station_id)
	check_true(selection.has_selection(), "a station can be selected again")
	selection.clear_selection()
	check_false(selection.has_selection(), "Escape's own call clears it as well")
	check_eq(selection.selected_kind, SelectionService.KIND_NONE, "to the same state")
	check_eq(signals.size(), 4, "every change reached the signal")


# --- 5.5 hover without selecting -------------------------------------------

func test_hover_names_an_industry_without_touching_the_selection() -> void:
	_view = TestView.stage()
	var session := _view.session
	var mine := TestSession.industry_by_definition(session, "coal_mine")
	var mine_tile: Vector2i = session.industries.tile_of(mine)
	_view.look_at_tile(mine_tile)

	var signals: Array[int] = []
	_view.selection.selection_changed.connect(func(_kind: String, _id: int, _tile: Vector2i) -> void:
		signals.append(1))
	_view.selection.point_at(_view.screen_of_tile(mine_tile))
	check_eq(_view.selection.hovered_kind, SelectionService.KIND_INDUSTRY,
		"the pointer over a colliery knows it is a colliery")
	check_eq(_view.selection.hovered_id, mine, "and which colliery it is")
	check_false(_view.selection.has_selection(), "but nothing is selected")
	check_eq(_view.selection.hovered_tile, mine_tile, "the hover tile is the one pointed at")
	check_eq(signals.size(), 0, "hovering never emitted a selection change")

	_view.selection.point_at(_view.screen_of_tile(mine_tile + Vector2i(30, 0)))
	check_neq(_view.selection.hovered_kind, SelectionService.KIND_INDUSTRY,
		"moving the pointer off it stops naming an industry")
	_view.selection.clear_hover()
	check_eq(_view.selection.hovered_kind, SelectionService.KIND_NONE, "and leaving the window clears the hover")
	check_eq(_view.selection.hovered_tile, Vector2i(-1, -1), "with the tile it was on")


# --- 6.1 boot -------------------------------------------------------------

func test_the_world_boots_headless_with_its_presentation_and_a_working_pointer() -> void:
	var started := Time.get_ticks_msec()
	_view = TestView.stage()
	var session := _view.session
	check_true(session.started, "the composition root started")
	check_eq(session.world.width, 256, "over the whole authored valley")
	check_eq(session.world.height, 256, "in both directions")

	for frame in 4:
		session.advance_ticks(1)
		_view.rig.tick(TestView.FRAME)
		_view.renderer.tick()
		_view.entities.tick()
		_view.effects.tick()
	check_eq(_view.renderer.live_chunk_nodes(), 64, "the terrain renderer built its 64 chunks")
	var nodes := TestView.count_nodes(_view.host)
	check_lt(float(nodes), 1000.0, "and the whole scene graph is far under a node per tile")

	var instances := 0
	var shells := 0
	for child in _view.entities.get_children():
		if child is CanvasLayer:
			continue
		instances += 1
		if TestView.count_mesh_drawables(child) == 0:
			shells += 1
	check_gt(float(instances), 5.0, "the valley's buildings got nodes of their own")
	check_eq(shells, 0, "and every one of them holds geometry rather than being an empty shell")

	var centre := _view.centre_pixel()
	var picked := _view.selection.pick_tile(centre)
	check_neq(picked, Vector2i(-1, -1), "the pointer at the centre of the screen hits the world")
	check_true(session.world.in_bounds(picked), "inside the map")
	check_near(_view.renderer.sample_height(_view.surface_point(picked)),
		session.world.elevation_at(picked), "the tile the pointer found is the one the renderer draws", 0.0001)
	var resolved := _view.selection.resolve_entity(picked, centre)
	check_neq(resolved["kind"], SelectionService.KIND_NONE, "and resolving that pixel names something")
	check_lt(float(Time.get_ticks_msec() - started), 4000.0,
		"the whole boot and its first frames fit comfortably inside the suite")


# --- helpers ---------------------------------------------------------------

## Where a ray first meets the heightfield, solved rather than marched.  Inside a
## tile the surface is a flat plane and the ray travels in a straight line, so the
## length at which they meet is arithmetic; and because x and z each cross tile
## edges in one direction, the tiles the ray passes over can be enumerated
## straight from their indices — no accumulated position to drift.  The first tile
## that catches the ray is the surface the pixel is showing.
##
## Returns that tile, the meeting point, and how far the meeting sits from a tile
## edge: the answer on an edge is a coin toss for any implementation, so the
## caller declines to grade those pixels rather than assert a tie rule.
func _contact_tile(ray: Dictionary) -> Dictionary:
	var grid := _view.grid()
	var origin: Vector3 = ray["origin"]
	var direction: Vector3 = ray["direction"]
	if direction.y >= -0.000001 or absf(direction.x) <= 0.000001 or absf(direction.z) <= 0.000001:
		return _no_contact()
	var horizon := minf(REFERENCE_LIMIT, (REFERENCE_FLOOR - origin.y) / direction.y)
	var column_step := 1
	if direction.x < 0.0:
		column_step = -1
	var column := floori(origin.x)
	for _crossing in COLUMNS_TO_WALK:
		var span := _intersect(_line_span(origin.x, direction.x, column), Vector2(0.0, horizon))
		if span.x > horizon:
			return _no_contact()
		if span.y >= span.x:
			var row_step := 1
			if direction.z < 0.0:
				row_step = -1
			var row := floori((origin + direction * span.x).z)
			var last_row := floori((origin + direction * span.y).z)
			while true:
				var answer := _meet_tile(grid, Vector2i(column, row), origin, direction,
					_intersect(span, _line_span(origin.z, direction.z, row)))
				if not answer.is_empty():
					return answer
				if row == last_row:
					break
				row += row_step
		column += column_step
	return _no_contact()


## The meeting inside one tile's own span, if there is one.  A ray that is already
## under this tile's top where it enters has struck the tile's wall, which counts
## as meeting it at the entry.
func _meet_tile(grid: WorldGrid, tile: Vector2i, origin: Vector3, direction: Vector3,
		span: Vector2) -> Dictionary:
	if span.x > span.y or not grid.in_bounds(tile):
		return {}
	var meeting := maxf(span.x, (grid.elevation_at(tile) - origin.y) / direction.y)
	if meeting > span.y:
		return {}
	var hit := origin + direction * meeting
	return {"tile": WorldCoords.world_to_tile(hit + direction * SelectionService.REFINE_SETTLE),
		"margin": _edge_margin(hit), "point": hit}


## The ray lengths over which the ray is inside one tile column, or row: solving
## `line <= start + rate * length < line + 1` for the length.
func _line_span(start: float, rate: float, line: int) -> Vector2:
	var entry := float(line) - start
	var exit := float(line + 1) - start
	return Vector2(minf(entry / rate, exit / rate), maxf(entry / rate, exit / rate))


func _intersect(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(maxf(a.x, b.x), minf(a.y, b.y))


func _no_contact() -> Dictionary:
	return {"tile": Vector2i(-1, -1), "margin": 0.0, "point": Vector3.INF}


## How far a point sits from the nearest tile edge, in tiles.
func _edge_margin(point: Vector3) -> float:
	return minf(_edge_distance(point.x), _edge_distance(point.z))


func _edge_distance(value: float) -> float:
	var fraction := value - floorf(value)
	return minf(fraction, 1.0 - fraction)


## A march that answers with the first sample under ground and nothing else:
## half a tile down a ray this steep drops almost as fast as a terrace does, so
## the sample lands past the edge the ray actually crossed and the pick is a tile
## late.  This is the failure the service must not have.
func _naive_march_tile(ray: Dictionary) -> Vector2i:
	var grid := _view.grid()
	var origin: Vector3 = ray["origin"]
	var direction: Vector3 = ray["direction"]
	var walked := 0.0
	while walked < REFERENCE_LIMIT:
		var point := origin + direction * walked
		if point.y < REFERENCE_FLOOR:
			return Vector2i(-1, -1)
		var tile := WorldCoords.world_to_tile(point)
		if grid.in_bounds(tile) and point.y <= grid.elevation_at(tile):
			return tile
		walked += NAIVE_STEP
	return Vector2i(-1, -1)


func _find_rail_tile_near(anchor: Vector2i, outside: int) -> Vector2i:
	var grid := _view.grid()
	for radius in range(4, 30):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var tile := Vector2i(anchor.x + dx, anchor.y + dy)
				if not grid.in_bounds(tile) or not grid.is_rail(tile):
					continue
				if grid.occupancy_at(tile) != WorldGrid.Occupancy.RAIL:
					continue
				if maxi(absi(dx), absi(dy)) < outside:
					continue
				if _view.selection.train_at_screen(_view.screen_of_tile(tile)) != 0:
					continue
				return tile
	return Vector2i(-1, -1)


func _find_empty_tile(around: Vector2i) -> Vector2i:
	var grid := _view.grid()
	for radius in range(2, 40):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var tile := Vector2i(around.x + dx, around.y + dy)
				if not grid.in_bounds(tile):
					continue
				if grid.occupancy_at(tile) != WorldGrid.Occupancy.NONE or grid.is_rail(tile):
					continue
				if _view.selection.nearest_train(Vector2(float(tile.x) + 0.5, float(tile.y) + 0.5)) != 0:
					continue
				return tile
	return Vector2i(-1, -1)
