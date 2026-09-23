class_name TestTravelScale
extends TestBase

## Where the world's units meet: what a kilometre an hour is worth in tiles, and
## which way a model has to be turned to look like it is travelling down them.
##
## Both faults this file exists for were invisible to the eye in a test and
## obvious in the game.  A consist crossed the valley at twenty of its own body
## lengths a second — a 14 m locomotive doing a little under a thousand
## kilometres an hour while the panel said 78 — because the number that converted
## km/h into tiles per tick had been tuned by feel and met nothing.  And rolling
## stock was turned by a yaw derived for a model whose forward is +Z, when every
## piece of it is built forward along +X, so each train was drawn broadside to its
## own rails and each station was turned to the camera instead of to its line.
##
## So nothing here asks whether a speed looks right.  Each case takes a figure the
## game states in one unit and measures it in the other: the panel against the
## ground covered, the yaw against the direction actually travelled, the platform
## edge against the lane the trains run in.


var _valley: GameSession
var _yard: GameSession
var _view: TestView


func setup() -> void:
	_valley = TestSession.create()
	_yard = TestConstruction.blank_session()


func teardown() -> void:
	if _view != null:
		_view.dispose()
		_view = null
	TestSession.dispose(_valley)
	_valley = null
	TestConstruction.dispose(_yard)
	_yard = null


# --- the speed, in the units it claims ---------------------------------------

func test_a_kilometre_an_hour_is_the_ground_it_covers_on_this_map() -> void:
	## The one conversion between the unit the player is shown and the unit the
	## movement code spends, worked from the two facts it depends on: a tile is
	## `TILE_METRES` across and the clock steps `TICK_RATE` of them a second.
	var metres_per_second := 1000.0 / 3600.0
	var implied := metres_per_second / WorldConstants.TILE_METRES / SimulationClock.TICK_RATE
	check_near(TrainService.KMH_TO_TILE_PER_TICK, implied,
			"one km/h is the stride the world's scale says it is", 1e-12)
	var ticks_for_a_tile := 1.0 / TrainService.KMH_TO_TILE_PER_TICK
	var kmh_for_a_tile_per_tick := WorldConstants.TILE_METRES * SimulationClock.TICK_RATE * 3.6
	check_near(TrainService.KMH_TO_TILE_PER_TICK * kmh_for_a_tile_per_tick, 1.0,
			"and a tile a tick — %d of them a second, %s m of them — is worth the "
			% [int(SimulationClock.TICK_RATE), str(WorldConstants.TILE_METRES)]
			+ "speed it says it is", 1e-9)
	check_gt(ticks_for_a_tile, 100.0,
			"so a kilometre an hour takes minutes of ticks, not a stride of them")


func test_the_speed_a_train_reports_is_the_ground_it_covers() -> void:
	## The number beside a train's name and the distance it puts behind it are read
	## out of different places — one derived from a rate, the other measured off the
	## path — so they can disagree without anything raising an error.  This is the
	## case that stops the conversion being tuned twice.
	var line := TestSession.coal_line(_valley)
	check_true(bool(line["ok"]), "a coal line to run a consist over: " + String(line["reason"]))
	if not bool(line["ok"]):
		return
	var train := int(line["train"])
	var near_top := _valley.trains.top_speed_tiles_per_tick(train) * 0.98
	TestSession.run_until(_valley,
			func() -> bool: return _valley.trains.speed_tiles_per_tick(train) >= near_top,
			TestSession.LEG_TICKS)
	var rate := _valley.trains.speed_tiles_per_tick(train)
	check_gt(rate, 0.0, "the consist is running by the time it is measured")
	var from := _valley.trains.position_tiles(train)
	_valley.clock.step_ticks(10)
	var to := _valley.trains.position_tiles(train)
	# Ten ticks of a moving train, loose enough for the curve the line bends through
	# and tight enough that a conversion tuned twice could not hide inside it.
	var measured := from.distance_to(to) / 10.0
	check_near(rate, measured,
			"the reported rate is the ground covered (%.5f tiles/tick against %.5f)" % [rate, measured],
			maxf(rate * 0.1, 0.001))
	var implied_kmh := measured * WorldConstants.TILE_METRES * SimulationClock.TICK_RATE * 3.6
	check_near(_valley.trains.speed_kmh(train), implied_kmh,
			"and the km/h on the panel is that distance in km/h (%.1f against %.1f)" % [
				_valley.trains.speed_kmh(train), implied_kmh],
			maxf(implied_kmh * 0.1, 1.0))


func test_a_train_crosses_the_view_in_seconds_a_player_can_watch() -> void:
	## Speed is only meaningful against the size of the thing moving.  A consist is
	## bound here in its own body lengths, which is the measure the eye actually
	## uses, and in seconds across the working view, which is the measure the player
	## does.
	var line := TestSession.coal_line(_valley)
	check_true(bool(line["ok"]), "a working line: " + String(line["reason"]))
	if not bool(line["ok"]):
		return
	var train := int(line["train"])
	var tiles_per_second := _valley.trains.top_speed_tiles_per_tick(train) * SimulationClock.TICK_RATE
	var body := _asset_length("steam_440")
	var lengths_per_second := tiles_per_second / body
	check_gt(lengths_per_second, 0.4,
			"at full rate a consist is visibly moving, not parked (%.2f lengths/s)" % lengths_per_second)
	check_le(lengths_per_second, 3.0,
			"and it never crosses the world in a blur (%.2f lengths/s)" % lengths_per_second)
	var seconds_across_view := WorldConstants.CAMERA_ZOOM_DEFAULT / tiles_per_second
	check_ge(seconds_across_view, 8.0,
			"a consist spends at least eight seconds inside the working view (%.1f)" % seconds_across_view)
	check_le(seconds_across_view, 120.0,
			"without crawling across it either (%.1f)" % seconds_across_view)


# --- which way a thing is turned ---------------------------------------------

func test_turning_a_model_to_a_direction_points_its_nose_down_it() -> void:
	## Rolling stock and stations are authored forward along local +X with the axle
	## on Y, so the yaw that lays a model along a tile-space direction `d` is the one
	## that carries +X onto `d`.  Derived the other way round it carries +Z there
	## instead, which turns every train broadside and every platform away from its
	## own rails.
	for direction in range(RailDirections.COUNT):
		var step := RailDirections.offset(direction)
		# A tile-space offset is a whole-tile step, so a diagonal's is (1, 1) and
		# the axis it names is the normalised one.
		var wanted := Vector2(float(step.x), float(step.y)).normalized()
		var yaw := WorldCoords.yaw_for_direction(wanted)
		var nose := Vector2(cos(yaw), -sin(yaw))
		check_near(nose.dot(wanted), 1.0,
				"'%s' points the model's own forward down the rails" % RailDirections.name_of(direction),
				0.0001)
		# The model's track side is its local +Z, which is what a station's platform
		# edge is measured from.
		var sideways := Vector2(sin(yaw), cos(yaw))
		check_near(sideways.x, -wanted.y, "and its +Z stands across the line", 0.0001)
		check_near(sideways.y, wanted.x, "squarely across it", 0.0001)
	check_near(WorldCoords.yaw_for_direction(Vector2.ZERO), 0.0,
			"a direction nobody travelled along turns nothing", 0.0001)


func test_a_running_train_is_drawn_the_way_it_is_travelling() -> void:
	_view = TestView.stage()
	var line := TestSession.coal_line(_view.session)
	check_true(bool(line["ok"]), "a coal line running under a camera: " + String(line["reason"]))
	if not bool(line["ok"]):
		return
	var session := _view.session
	var train := int(line["train"])
	var at_top := session.trains.top_speed_tiles_per_tick(train) * 0.8
	TestSession.run_until(session,
			func() -> bool: return session.trains.speed_tiles_per_tick(train) >= at_top,
			TestSession.LEG_TICKS)
	var before := session.trains.position_tiles(train)
	session.clock.step_ticks(10)
	var travel := session.trains.position_tiles(train) - before
	check_gt(travel.length(), 0.1, "and it covered ground while it was watched")
	if travel.length() < 0.1:
		return
	var direction := travel.normalized()
	var node := _view.entities.train_node(train)
	check_true(node != null, "the consist has a body on screen")
	if node == null:
		return
	_view.look_at_tile(Vector2i(floori(before.x), floori(before.y)))
	_view.entities.tick()
	var bodies := _consist_bodies(node)
	check_ge(float(bodies.size()), 3.0, "the consist is strung out body by body")
	if bodies.size() < 3:
		return
	var engine: Node3D = bodies[0]
	# The engine's own forward, taken off the body the renderer turned.  A consist is
	# no longer one rigid sprite, so "which way the train is going" is a question
	# about the vehicle at the front, and the answer is read out of its basis: local
	# +X under a yaw about Y lands on (cos θ, −sin θ) in tile space.
	var nose := Vector2(engine.transform.basis.x.x, engine.transform.basis.x.z).normalized()
	check_near(nose.dot(direction), 1.0,
			"the drawn engine faces the way it moved (%.3f of the way)" % nose.dot(direction), 0.02)
	var heading_degrees := WorldCoords.yaw_degrees_for_direction(direction)
	check_near(session.trains.heading(train), heading_degrees,
			"and the simulation's own heading agrees with the ground it measured (%.1f against %.1f)" % [
				session.trains.heading(train), heading_degrees], 0.6)
	# What crosses a stop marker is a coupler, not the middle of a boiler: the point
	# the simulation moves is the engine's front coupler, and that is the one place
	# the drawing and the domain have to agree on to the digit.
	var reach := _front_reach(session, train)
	var coupler := Vector2(node.position.x, node.position.z) + Vector2(engine.position.x, engine.position.z) \
			+ nose * reach
	check_lt(coupler.distance_to(session.trains.position_tiles(train)), 0.02,
			"the nose is on the point the simulation is moving, not a body length off it")
	# What the rest of the consist does — every vehicle on its own stretch of rail,
	# each turned to its own bearing — is the law of `test_consist_on_rail.gd`, not a
	# corollary of this one.  What this case insists on is that the direction belongs to
	# the engine's own body and not to the node the train hangs from: a consist whose
	# parent carries the turn is one sprite, and one sprite cannot follow a line.
	check_near(float(node.rotation.y), 0.0,
			"the train's own node turns nothing: the vehicle carries its direction", 0.0001)


# --- a yard against its line -------------------------------------------------

func test_a_station_couples_to_the_line_beside_its_yard() -> void:
	## The ground a yard couples to is the ground beside its platform.  A station
	## that claims track two rows away is drawn — or is not — wherever that put the
	## model, and the player is left with a yard standing in a field.
	var run := TestConstruction.east_run(Vector2i(30, 40), 5)
	var laid := _yard.builder.build_track_run(run)
	check_true(bool(laid["ok"]), "a straight run through the blank: " + String(laid["reason"]))
	var anchor := Vector2i(31, 41)
	check_eq(_yard.stations.placement_reason("small_station", anchor), "",
			"a yard standing against the line is buildable")
	var built := _yard.builder.build_station("small_station", anchor, "Test Yard")
	check_true(bool(built["ok"]), "and it commits: " + String(built["reason"]))
	if not bool(built["ok"]):
		return
	var station := int(built["id"])
	var access := _yard.stations.rail_access(station)
	var tile: Vector2i = access["tile"]
	check_true(run.has(tile), "it coupled to a cell of the line it stands beside")
	check_eq(_rings_from_yard(anchor, Vector2i(3, 2), tile), 1,
			"the cell it coupled to touches the yard, it is not somewhere out past it")
	check_near(Vector2(access["direction"]).dot(Vector2(1.0, 0.0)), 1.0,
			"and it faces down the line it coupled to", 0.0001)


func test_a_station_that_only_overlooks_the_line_is_refused() -> void:
	var run := TestConstruction.east_run(Vector2i(30, 40), 5)
	check_true(bool(_yard.builder.build_track_run(run)["ok"]), "a straight run through the blank")
	var anchor := Vector2i(31, 43)
	var reason := _yard.stations.placement_reason("small_station", anchor)
	check_neq(reason, "", "a yard with a gap of open ground to the line is refused")
	check_has(reason.to_lower(), "beside", "and the refusal says the line has to be beside it")


func test_the_platform_stands_at_the_rails_it_serves() -> void:
	## Placement is graded against the model's own dimensions, read out of the
	## manifest it was built to: the track-side edge on the lane, the yard parallel
	## to the line, and no part of the platform overhanging ground nobody bought.
	var run := TestConstruction.east_run(Vector2i(30, 40), 5)
	check_true(bool(_yard.builder.build_track_run(run)["ok"]), "a straight run through the blank")
	var anchor := Vector2i(31, 41)
	var built := _yard.builder.build_station("small_station", anchor, "Test Yard")
	check_true(bool(built["ok"]), "and a yard beside it: " + String(built["reason"]))
	if not bool(built["ok"]):
		return
	var station := int(built["id"])
	var renderer := EntityRenderer.new()
	var reach: Array = renderer.platform_reach("small_station")
	check_gt(float(reach[0]), 0.0, "the manifest says where the rails run past this model")
	var spot := EntityRenderer.station_transform(_yard.stations.station(station),
			_yard.stations.rail_access(station), float(reach[0]), float(reach[1]))
	var at: Vector2 = spot["position"]
	var yaw := float(spot["yaw"])
	var down_line: Vector2 = spot["direction"]
	var off_line := Vector2(-down_line.y, down_line.x)
	var lane := Vector2(_yard.stations.rail_access(station)["tile"]) + Vector2(0.5, 0.5)

	# The platform's track-side edge, measured where the art puts it.
	var edge := at + off_line * float(reach[0])
	check_near((edge - lane).dot(off_line), 0.0,
			"the platform edge lies on the lane the trains run in", 0.0001)
	# Turned to the line, which is the same statement as the edge being parallel to it.
	check_near(yaw, WorldCoords.yaw_for_direction(down_line), "the yard is turned to its run", 0.0001)
	check_near(absf(down_line.dot(Vector2(1.0, 0.0))), 1.0, "along an east-west line", 0.0001)

	# Everything inside the ground the footprint claimed.
	var claimed_anchor: Vector2i = _yard.stations.station(station)["anchor"]
	var size: Vector2i = _yard.stations.station(station)["footprint"]
	var west := float(claimed_anchor.x)
	var north := float(claimed_anchor.y)
	var east := float(claimed_anchor.x + size.x)
	var south := float(claimed_anchor.y + size.y)
	check_ge(at.x, west, "the model stands on ground the player bought")
	check_le(at.x, east, "inside its eastern edge")
	check_ge(at.y, north, "inside its northern edge")
	check_le(at.y, south, "and inside its southern edge")
	var reach_along := (absf(down_line.x) * float(size.x) + absf(down_line.y) * float(size.y)) * 0.5
	var centre_along := (Vector2(claimed_anchor) + Vector2(size) * 0.5).dot(down_line)
	var placed_along := at.dot(down_line)
	check_ge(placed_along - float(reach[1]), centre_along - reach_along - 0.0001,
			"no end of the platform hangs over the boundary")
	check_le(placed_along + float(reach[1]), centre_along + reach_along + 0.0001,
			"nor does the other")
	# A platform has its deck on one side of its own origin, so lying against the
	# rails it either faces its yard or turns its back on the line, never both.
	# Which of the two it is follows from the yaw, and the right answer is that the
	# ground the player bought lies behind the deck.
	var to_yard := Vector2(claimed_anchor) + Vector2(size) * 0.5 - at
	check_lt(to_yard.dot(off_line), 0.0,
			"the yard lies behind the deck, not in front of the rails it serves")


func test_a_station_is_turned_to_its_line_and_not_to_the_projection() -> void:
	## The fault this pins: a yard turned to the isometric projection's fixed forty-
	## five degrees.  A platform is not a billboard — it serves the line it stands
	## against, so its yaw is the line's, and on an east-west run that can only ever
	## be a multiple of ninety degrees while the projection sits at forty-five.
	_view = TestView.stage_blank(128, 128)
	var run := TestConstruction.east_run(Vector2i(30, 40), 5)
	check_true(bool(_view.session.builder.build_track_run(run)["ok"]),
			"a straight run laid through the blank view")
	var built := _view.session.builder.build_station("small_station", Vector2i(31, 41), "Sightline Yard")
	check_true(bool(built["ok"]), "and a yard beside it: " + String(built["reason"]))
	if not bool(built["ok"]):
		return
	var station := int(built["id"])
	_view.entities.tick()
	var node := _view.entities.station_node(station)
	check_true(node != null, "the yard has a body in the world")
	if node == null:
		return
	var yaw_degrees := absf(rad_to_deg(node.rotation.y))
	check_near(fmod(yaw_degrees, 90.0), 0.0,
			"the platform lies along the line (%.1f degrees)" % yaw_degrees, 0.001)
	# The axis is read off the rail that was laid, not out of the station service,
	# so the case cannot pass by agreeing with the thing it is checking.  A nose
	# pointing down an east-west run has no component across it.
	var nose := Vector2(cos(node.rotation.y), -sin(node.rotation.y))
	check_near(absf(nose.x), 1.0, "the yard is turned down the east-west run", 0.0001)
	check_near(nose.y, 0.0, "which is a square angle to the rails", 0.0001)
	var renderer := _view.entities
	var reach: Array = renderer.platform_reach("small_station")
	var spot := EntityRenderer.station_transform(_view.session.stations.station(station),
			_view.session.stations.rail_access(station), float(reach[0]), float(reach[1]))
	var at: Vector2 = spot["position"]
	check_near(node.position.x, at.x, "the drawn yard stands where the placement put it", 0.0001)
	check_near(node.position.z, at.y, "across the tiles too", 0.0001)
	check_near(node.rotation.y, float(spot["yaw"]), "and faces the way it was turned", 0.0001)


func test_a_yard_read_back_from_a_save_is_laid_as_the_live_one_was() -> void:
	## Two passes draw a yard: a signal when it is built, and a sweep of
	## everything already there when a renderer attaches to a session — which is
	## what loading a save amounts to.  Both funnel through `station_transform`,
	## and this is the case that says so: a valley that came back from disk must
	## not find its platforms drifted off the rails it was built against.
	_view = TestView.stage_blank(128, 128)
	var run := TestConstruction.east_run(Vector2i(30, 40), 5)
	check_true(bool(_view.session.builder.build_track_run(run)["ok"]),
			"a straight run laid through the blank view")
	var built := _view.session.builder.build_station("small_station", Vector2i(31, 41), "Depot Yard")
	check_true(bool(built["ok"]), "and a yard beside it: " + String(built["reason"]))
	if not bool(built["ok"]):
		return
	var station := int(built["id"])
	var live := _view.entities.station_node(station)
	check_true(live != null, "the live yard was drawn when it was built")
	if live == null:
		return
	var late := EntityRenderer.new()
	late.attach(_view.session, _view.rig)
	var drawn := late.station_node(station)
	check_true(drawn != null, "a renderer arriving later draws the yard it finds there")
	if drawn == null:
		late.free()
		return
	check_near(drawn.position.x, live.position.x, "the yard reloaded stands on the same ground", 0.0001)
	check_near(drawn.position.z, live.position.z, "in both tile axes", 0.0001)
	check_near(drawn.rotation.y, live.rotation.y, "and is turned the same way to its line", 0.0001)
	late.free()


# --- helpers -----------------------------------------------------------------

## How far the engine's front coupler stands out from its own origin, read off the
## built manifest: the same figure the renderer strings the consist from, and the
## distance between the nose and the point the simulation moves.
func _front_reach(session: GameSession, train_id: int) -> float:
	var stock_ids := session.trains.stock_of(train_id)
	check_gt(float(stock_ids.size()), 0.0, "the consist has an engine to measure")
	if stock_ids.is_empty():
		return 0.5
	var def := session.data.stock(String(stock_ids[0]))
	var asset := def.asset if def != null else String(stock_ids[0])
	var attachments: Dictionary = ModelCatalog.new().manifest(asset).get("attachments", {})
	var coupler: Array = attachments.get("coupler_front", [])
	check_ge(float(coupler.size()), 1.0, "'%s' declares a front coupler to measure from" % asset)
	return absf(float(coupler[0])) if not coupler.is_empty() else 0.5


func _asset_length(asset_id: String) -> float:
	var footprint: Array = ModelCatalog.new().manifest(asset_id).get("footprint", [])
	check_ge(float(footprint.size()), 1.0, "'%s' declares a footprint to measure against" % asset_id)
	if footprint.is_empty():
		return 1.0
	return float(footprint[0])


## How many rings of ground lie between a yard's footprint and a tile: 0 for a
## cell inside it, 1 for one the platform stands against.
func _rings_from_yard(anchor: Vector2i, size: Vector2i, tile: Vector2i) -> int:
	var dx := maxi(anchor.x - tile.x, tile.x - (anchor.x + size.x - 1))
	var dy := maxi(anchor.y - tile.y, tile.y - (anchor.y + size.y - 1))
	return maxi(0, maxi(dx, dy))


func _consist_bodies(root: Node) -> Array[Node3D]:
	var bodies: Array[Node3D] = []
	for child in root.get_children():
		if String(child.name).begins_with("Stock_"):
			bodies.append(child as Node3D)
	return bodies
