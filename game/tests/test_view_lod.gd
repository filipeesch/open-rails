class_name TestViewLod
extends TestBase

## Tasks 5.1 – 5.2: LOD selection from the camera's orthographic size, and the
## animation tiers that ride along with it.
##
## A tier is only real if it changes the picture, so nothing here asserts an
## internal level index on its own.  What gets measured is what the renderer and
## the effect pool report: which named LOD body an asset is drawing, how many mesh
## bodies are left visible, how many triangles are behind them (read back out of
## the imported meshes and checked against the geometry the asset compiler
## declared for that level), how many names are on screen, how many puffs a chimney
## fired and how often train bodies were repositioned.
##
## The other half of the job is the promise that none of it reaches the game:
## presentation may look at the simulation and must never feed it.  The last case
## drives the shipped loop twice over the same coal line at opposite tiers — one
## with full animation, one with it suspended — and requires the two worlds to
## agree exactly.  It is worth knowing that the effect pool fires `randf()`, the
## engine's global stream: presentation is burning randomness in there that the
## simulation must never notice.

const NEAR_ZOOM := WorldConstants.CAMERA_ZOOM_CLOSE
const MEDIUM_ZOOM := WorldConstants.CAMERA_ZOOM_DEFAULT
const FAR_ZOOM := WorldConstants.CAMERA_ZOOM_FAR
## Frames a single emission measurement runs.  The simulation is parked while it
## does, so a chimney fires on a known number of frames and the counts come out
## exact rather than merely ordered.
const RATE_FRAMES := 20
## Presentation frames to park the view at the far tier and let the sky empty
## itself.  Long enough that a whole smoke life fits inside it at the reduced
## cadence, with room to spare.
const DRAIN_FRAMES := 800
## Presentation frames each identity run is driven for.  Long enough for the two
## cameras to disagree about what to draw — which is the whole point of the pair —
## and the simulation result they are compared on is earned separately, on the
## clock, because a loaded leg across the valley outlasts any frame budget.
const IDENTITY_TICKS := 1500

var _view: TestView


func teardown() -> void:
	if _view != null:
		_view.dispose()
		_view = null


# --- 5.1 the selection, and what it selects ---------------------------------

func test_the_tier_is_cut_on_tiles_visible_at_the_documented_bounds() -> void:
	check_eq(IsoCameraRig.lod_for_tiles(NEAR_ZOOM), IsoCameraRig.LOD_NEAR,
		"the closest zoom is LOD0, the inspection mesh")
	check_eq(IsoCameraRig.lod_for_tiles(IsoCameraRig.LOD_NEAR_MAX_TILES), IsoCameraRig.LOD_NEAR,
		"exactly on the near bound the cheaper body has not been asked for yet")
	check_eq(IsoCameraRig.lod_for_tiles(IsoCameraRig.LOD_NEAR_MAX_TILES + 0.01), IsoCameraRig.LOD_MEDIUM,
		"one tile past it the part list stops being worth its draw calls")
	check_eq(IsoCameraRig.lod_for_tiles(MEDIUM_ZOOM), IsoCameraRig.LOD_MEDIUM,
		"the shipped working zoom is the middle tier: LOD1 at ordinary play")
	check_eq(IsoCameraRig.lod_for_tiles(IsoCameraRig.LOD_MEDIUM_MAX_TILES), IsoCameraRig.LOD_MEDIUM,
		"the far bound holds the middle tier right up to itself")
	check_eq(IsoCameraRig.lod_for_tiles(IsoCameraRig.LOD_MEDIUM_MAX_TILES + 0.01), IsoCameraRig.LOD_FAR,
		"one tile past that, only the silhouette reads")
	check_eq(IsoCameraRig.lod_for_tiles(FAR_ZOOM), IsoCameraRig.LOD_FAR,
		"the far end of the zoom range is LOD2")
	check_lt(IsoCameraRig.LOD_NEAR_MAX_TILES, IsoCameraRig.LOD_MEDIUM_MAX_TILES,
		"the two bounds are in order")
	check_le(IsoCameraRig.LOD_MEDIUM_MAX_TILES, FAR_ZOOM,
		"and the far tier is reachable inside the camera's own range, not past it")


func test_the_renderer_reads_the_tier_from_the_rig_it_was_handed() -> void:
	_view = TestView.stage()
	var rig := _view.rig
	var renderer := _view.entities
	for commanded in [[NEAR_ZOOM, IsoCameraRig.LOD_NEAR], [MEDIUM_ZOOM, IsoCameraRig.LOD_MEDIUM],
			[FAR_ZOOM, IsoCameraRig.LOD_FAR]]:
		# Driven through `set_zoom` and its easing, the way a wheel turn drives it:
		# the tier under test is the one the rig settles on, not a number the case
		# wrote into a renderer.
		var tiles := _view.zoom_to(float(commanded[0]))
		renderer.tick()
		check_near(renderer.zoom_tiles(), tiles, "the renderer asks the rig how far out it is", 0.001)
		check_eq(renderer.lod_level(), int(commanded[1]), "and resolves that zoom to the tier the rig names")
		check_eq(renderer.lod_level(), rig.lod_level(), "renderer and rig never disagree")
	check_eq(_view.effects.lod_level(), rig.lod_level(),
		"the effect pool reads the same one number rather than keeping its own")


func test_a_station_draws_exactly_one_named_lod_body_per_tier() -> void:
	_view = TestView.stage()
	var station_id := _line_station()
	var node := _view.entities.station_node(station_id)
	check_true(node != null, "the colliery station has a body to degrade")
	# A GLB imports every level it carries visible, so an unmanaged renderer draws
	# all three at once; the manifest says what each of them costs.
	var shipped: Array[String] = ["LOD0", "LOD1", "LOD2"]
	check_eq(_lod_body_names(node), shipped,
		"the asset compiler shipped this station three bodies")
	var declared := {
		IsoCameraRig.LOD_NEAR: _manifest_triangles("small_station", IsoCameraRig.LOD_NEAR),
		IsoCameraRig.LOD_MEDIUM: _manifest_triangles("small_station", IsoCameraRig.LOD_MEDIUM),
		IsoCameraRig.LOD_FAR: _manifest_triangles("small_station", IsoCameraRig.LOD_FAR),
	}
	check_gt(float(declared[IsoCameraRig.LOD_NEAR]), float(declared[IsoCameraRig.LOD_MEDIUM]),
		"the compiler's own numbers say the levels get cheaper")
	check_gt(float(declared[IsoCameraRig.LOD_MEDIUM]), float(declared[IsoCameraRig.LOD_FAR]),
		"monotonically so")
	for level in [IsoCameraRig.LOD_NEAR, IsoCameraRig.LOD_MEDIUM, IsoCameraRig.LOD_FAR]:
		_view.zoom_to(_zoom_for_level(int(level)))
		_view.entities.tick()
		var drawn := EntityRenderer.drawn_geometry(node)
		var expected: Array[String] = ["LOD%d" % int(level)]
		check_eq(_visible_lod_bodies(node), expected,
			"at tier %s the station draws its LOD%s body and hides the other two" % [level, level])
		check_eq(int(drawn["triangles"]), int(declared[level]),
			"and what is on screen is exactly the geometry that level declares")
		check_eq(int(drawn["drawables"]), 16 if int(level) == IsoCameraRig.LOD_NEAR else 1,
			"LOD0 is a sixteen-mesh part list, every level past it is a single body")


func test_progressively_higher_zoom_draws_progressively_less_of_the_valley() -> void:
	_view = TestView.stage()
	var line := TestSession.coal_line(_view.session)
	check_true(bool(line["ok"]),
			"a working line adds stations and a consist to what is on screen")
	# Look at the consist: an offscreen train is left unworked (§3.5), and this case
	# is about what a tier draws, not about what the view chose to throw away.
	_view.look_at_tile(Vector2i(_view.session.trains.position_tiles(int(line["train"]))))
	for frame in 3:
		_view.run_frame()
	var readings: Array[Dictionary] = []
	for commanded in [NEAR_ZOOM, MEDIUM_ZOOM, FAR_ZOOM]:
		_view.zoom_to(float(commanded))
		_view.run_frame()
		readings.append({
			"tier": _view.entities.lod_level(),
			"bodies": _view.entities.visible_body_count(),
			"triangles": _view.entities.drawn_triangle_total(),
			"labels": _view.entities.visible_label_count(),
		})
	check_eq(readings[0]["tier"], IsoCameraRig.LOD_NEAR, "the first reading is the closest view")
	check_eq(readings[1]["tier"], IsoCameraRig.LOD_MEDIUM, "the second the working zoom")
	check_eq(readings[2]["tier"], IsoCameraRig.LOD_FAR, "the last the overview")
	check_gt(float(readings[0]["bodies"]), float(readings[1]["bodies"]),
		"pulling back to the working zoom drops the part lists: fewer bodies drawn")
	check_eq(float(readings[1]["bodies"]), float(readings[2]["bodies"]),
		"one body per entity is already the floor, so the far tier buys triangles, not nodes")
	check_gt(float(readings[0]["triangles"]), float(readings[1]["triangles"]),
		"the geometry falls at the first step out")
	check_gt(float(readings[1]["triangles"]), float(readings[2]["triangles"]),
		"and again at the second: monotonic degradation, measured in triangles")
	check_gt(float(readings[2]["bodies"]), 20.0,
		"and the far tier still draws every one of them, it just draws them cheaply")
	check_gt(float(readings[2]["triangles"]), 500.0,
		"with real silhouette geometry left in the picture, not an emptied scene")
	check_eq(float(readings[2]["labels"]), 0.0,
		"at the overview every one of those bodies is on screen and none of them is named")


func test_a_consist_sheds_its_wheels_and_rods_as_the_view_pulls_back() -> void:
	_view = TestView.stage()
	var line := TestSession.coal_line(_view.session)
	check_true(bool(line["ok"]), "a consist to degrade")
	var train_id := int(line["train"])
	_view.look_at_tile(Vector2i(_view.session.trains.position_tiles(train_id)))
	for frame in 4:
		_view.run_frame()
	var node := _view.entities.train_node(train_id)
	check_true(node != null, "the consist has a node of its own")
	for level in [IsoCameraRig.LOD_NEAR, IsoCameraRig.LOD_MEDIUM, IsoCameraRig.LOD_FAR]:
		_view.zoom_to(_zoom_for_level(int(level)))
		_view.entities.tick()
		var drawn := EntityRenderer.drawn_geometry(node)
		check_eq(int(drawn["triangles"]), _consist_triangles(train_id, int(level)),
			"tier %s draws the consist's declared LOD%s geometry and nothing else" % [level, level])
		# LOD0 is the only level that carries the moving parts at all: the wheels
		# and side rods are separate bodies, so hiding the level is what takes the
		# decoration off a train nobody can resolve anyway.
		var wheels := _visible_bodies_named_like(node, "wheel_")
		if int(level) == IsoCameraRig.LOD_NEAR:
			check_gt(float(wheels), 0.0, "close in the locomotive rolls on %d separate wheel bodies" % wheels)
		else:
			check_eq(float(wheels), 0.0, "at tier %s no wheel body is drawn" % level)


# --- 5.2 the animation tiers ----------------------------------------------

func test_a_chimney_fires_every_frame_near_and_every_other_frame_at_medium() -> void:
	_view = TestView.stage()
	var train_id := _run_until_moving()
	# Park the simulation and drive the pool alone: the train stays moving, so what
	# comes out of the chimney is the emission rate and nothing else.
	_view.rig.focus_tile(_view.session.trains.position_tiles(train_id), true)
	_view.zoom_to(NEAR_ZOOM)
	var near := _puffs_over(RATE_FRAMES)
	check_eq(float(near), float(RATE_FRAMES),
		"close in, one moving locomotive emits one puff per frame")
	_view.zoom_to(MEDIUM_ZOOM)
	var medium := _puffs_over(RATE_FRAMES)
	check_eq(float(medium), float(RATE_FRAMES) / float(EffectLayer.MEDIUM_RATE_DIVISOR),
		"at the working zoom the rate halves: a plume every other frame is the same plume")
	check_lt(float(medium), float(near), "and the medium tier is measurably quieter than the near one")
	_view.zoom_to(FAR_ZOOM)
	check_eq(float(_puffs_over(RATE_FRAMES)), 0.0, "in the overview a chimney fires nothing at all")
	check_true(_view.effects.animation_suspended(), "and the layer reports itself suspended")


func test_the_far_tier_clears_the_sky_and_borns_nothing_in_it() -> void:
	_view = TestView.stage()
	_view.zoom_to(NEAR_ZOOM)
	_view.effects.puff_at(Vector3(128.0, 1.0, 128.0), 8)
	check_eq(float(_view.effects.emitted_total()), 8.0, "eight puffs were born close in")
	for frame in 2:
		_view.effects.tick()
	check_eq(float(_view.effects.live_particles()), 8.0, "and all eight are live in the air")
	_view.zoom_to(FAR_ZOOM)
	var emitted := _view.effects.emitted_total()
	var stepped := _view.effects.step_count()
	for frame in DRAIN_FRAMES:
		_view.effects.tick()
	check_eq(_view.effects.emitted_total() - emitted, 0,
		"%d frames at the far tier added no particle" % DRAIN_FRAMES)
	check_eq(float(_view.effects.live_particles()), 0.0,
		"and the smoke already there aged out instead of hanging in the overview")
	var steps := _view.effects.step_count() - stepped
	check_gt(float(steps), 0.0, "the pool was still stepped, so nothing is frozen mid-plume")
	check_le(float(steps), float(DRAIN_FRAMES) / float(EffectLayer.FAR_UPDATE_INTERVAL) + 1.0,
		"but only on a cadence: %d steps across %d frames" % [steps, DRAIN_FRAMES])


func test_an_arrival_puff_is_refused_far_and_paid_for_near() -> void:
	_view = TestView.stage()
	var point := Vector3(120.0, 1.0, 120.0)
	_view.zoom_to(FAR_ZOOM)
	var before := _view.effects.emitted_total()
	_view.effects.puff_at(point, 6)
	check_eq(_view.effects.emitted_total() - before, 0,
		"an arrival in the overview draws nothing: the pool is shut, not merely throttled")
	_view.zoom_to(NEAR_ZOOM)
	before = _view.effects.emitted_total()
	_view.effects.puff_at(point, 6)
	check_eq(_view.effects.emitted_total() - before, 6, "the same arrival close in is six particles")


func test_train_bodies_are_repositioned_on_a_cadence_only_in_the_overview() -> void:
	_view = TestView.stage()
	var line := TestSession.coal_line(_view.session)
	check_true(bool(line["ok"]), "one train to update")
	# The cadence only matters for a consist the player can see; an offscreen one
	# is skipped whole, which is what the two cases below are for.
	_view.look_at_tile(Vector2i(_view.session.trains.position_tiles(int(line["train"]))))
	for level in [IsoCameraRig.LOD_NEAR, IsoCameraRig.LOD_MEDIUM]:
		_view.zoom_to(_zoom_for_level(int(level)))
		check_eq(float(_updates_over(6)), 6.0, "tier %s refreshes the consist on every frame" % level)
	_view.zoom_to(FAR_ZOOM)
	# Twelve frames hold exactly three of the four-frame cadence, whatever the
	# renderer's frame counter came in on: the cadence is the claim, not a phase.
	check_eq(float(_updates_over(12)), 3.0, "the overview pays for a third of the position updates")


## What this layer labels is what it has to follow: a moving consist.  Place
## names — towns, yards, works — are §72's map labels and live in `MapLabels`,
## which is where their zoom bands and their selected exception are graded
## (`tests/test_map_labels.gd`); two systems naming the same yard would only
## double the text on screen.
func test_the_names_on_screen_follow_the_tier_and_the_view() -> void:
	_view = TestView.stage()
	var line := TestSession.coal_line(_view.session)
	var near_train := int(line["train"])
	var far_consist := _view.session.trains.purchase(int(line["plant_station"]), "steam_440",
			["passenger_coach"])
	check_true(bool(far_consist["ok"]), "a second consist waits at the other end of the line")
	var far_train := int(far_consist["id"])
	var apart := WorldCoords.distance_tiles(_view.session.trains.position_tiles(near_train),
		_view.session.trains.position_tiles(far_train))
	check_gt(apart, 8.0, "the two ends of the line are far enough apart for one to be off screen")
	_view.look_at_tile(Vector2i(_view.session.trains.position_tiles(near_train)))
	_view.zoom_to(NEAR_ZOOM)
	_view.entities.tick()
	check_true(_view.entities.labels_shown(), "at the near tier names are drawn")
	check_true(_view.entities.label_is_shown(_view.entities.train_node(near_train)),
		"the consist the view is centred on wears its name")
	check_false(_view.entities.label_is_shown(_view.entities.train_node(far_train)),
		"and the one off the other end of the line is off screen, so it wears nothing")
	_view.zoom_to(FAR_ZOOM)
	_view.entities.tick()
	check_false(_view.entities.labels_shown(), "the overview draws no names at all")
	check_eq(float(_view.entities.visible_label_count()), 0.0,
		"including the consist still dead centre in the picture")


# --- 3.4 wheels, read from the ground the train crossed -------------------

## A wheel that turns because time passes is a wheel on a parked train.  The
## compiler publishes each vehicle's wheel circumference, the asset's `moving` clip
## is exactly one revolution, and so the phase the renderer writes is travelled
## distance over circumference — nothing else.  Because the game's speed control
## changes how many ticks arrive per frame rather than how far a tick carries, a
## train at 2x covers twice the ground between draws and its wheels turn twice as
## far: the case below measures that with ticks, which is what speed is made of.
func test_the_wheels_turn_because_the_train_moved() -> void:
	_view = TestView.stage()
	var train_id := _run_until_moving()
	check_gt(_cruise_until_steady(train_id), 0.05, "the consist is at line speed first")
	_look_at_train(train_id)
	var first := _view.entities.wheel_phase(train_id)
	var travelled := _view.entities.wheel_distance(train_id)
	_view.run_frame(20)

	check_gt(_view.entities.wheel_distance(train_id) - travelled, 0.05,
			"the consist covered ground the renderer could see (%.3f tiles)" % (
			_view.entities.wheel_distance(train_id) - travelled))
	check_neq(_view.entities.wheel_phase(train_id), first, "and the crank angle followed it")
	check_ge(_view.entities.wheel_phase(train_id), 0.0, "a phase is a fraction of one turn")
	check_le(_view.entities.wheel_phase(train_id), 1.0, "and never more than one")
	check_gt(float(_view.entities.wheels_driven_last_tick()), 0.0,
			"the bodies were posed on the frame that decided it (%d)" % _view.entities.wheels_driven_last_tick())


func test_the_wheels_of_a_standing_train_do_not_turn() -> void:
	_view = TestView.stage()
	var line := TestSession.coal_line(_view.session)
	check_true(bool(line["ok"]), "a yard to wait in")
	var bought := _view.session.trains.purchase(int(line["plant_station"]), "steam_440", ["coal_hopper"])
	check_true(bool(bought["ok"]), "a consist with no route to run")
	var waiting := int(bought["id"])
	_view.look_at_tile(_view.session.stations.tile_of(int(line["plant_station"])))
	_view.zoom_to(MEDIUM_ZOOM)
	_view.run_frame(1)
	var phase := _view.entities.wheel_phase(waiting)
	check_near(_view.entities.wheel_distance(waiting), 0.0,
			"a train that has never moved has never rolled a wheel", 0.0001)

	for frame in 240:
		_view.session.advance_ticks(1)
		_view.rig.tick(TestView.FRAME)
		_view.entities.tick()

	check_near(_view.entities.wheel_distance(waiting), 0.0,
			"twelve seconds of frames added no travel to it", 0.0001)
	check_near(_view.entities.wheel_phase(waiting), phase,
			"and no crank angle either — the animation reads the ground, not the clock", 0.0001)


## The dwell is the case the spec names: a consist sitting in a station being
## loaded holds one crank angle until the brakes release, and starts turning again
## the moment it rolls out.  How long forty units of coal takes to load is the
## simulation's business, so the watch is stepped in ticks and covers several
## dwells on the loop instead of betting the case on the length of one.
func test_the_wheels_rest_while_the_train_dwells_in_a_station() -> void:
	_view = TestView.stage()
	var train_id := _run_until_moving()
	_look_at_train(train_id)
	var trains: TrainService = _view.session.trains

	var episodes := 0
	var dwell_frames := 0
	var frames := 0
	var worst_travel := 0.0
	var worst_drift := 0.0
	while frames < 8000 and episodes < 3:
		if not _is_dwelling(trains, train_id):
			_view.run_frame(1)
			frames += 1
			continue
		var entry_distance := _view.entities.wheel_distance(train_id)
		var entry_phase := _view.entities.wheel_phase(train_id)
		check_gt(entry_distance, 0.0, "an arriving consist has covered ground, so its wheels are mid-turn")
		var episode := 0
		while episode < 800 and _is_dwelling(trains, train_id):
			_view.run_frame(1)
			episode += 1
			frames += 1
			if not _is_dwelling(trains, train_id):
				break  # the tick that released the brakes belongs to the next leg
			worst_travel = maxf(worst_travel, _view.entities.wheel_distance(train_id) - entry_distance)
			worst_drift = maxf(worst_drift, absf(_view.entities.wheel_phase(train_id) - entry_phase))
		episodes += 1
		dwell_frames += episode

	check_eq(float(episodes), 3.0, "the train worked at three stations during the watch")
	check_ge(float(dwell_frames), 12.0, "and dwelled long enough to be worth watching (%d frames)" % dwell_frames)
	check_near(worst_travel, 0.0, "not one frame of any dwell covered any ground", 0.0001)
	check_near(worst_drift, 0.0, "and not one frame of any dwell moved a crank", 0.0001)

	_view.run_frame(20)
	check_true(trains.state_of(train_id) == trains.State.MOVING, "it is under way again")
	check_gt(_view.entities.wheel_distance(train_id), 0.0, "and its wheels have turned since")


## Speed in this game is how many ticks arrive between two frames, not how far a
## tick carries, so a consist running at 2x crosses twice the ground between draws
## and its wheels turn twice as far: measuring ground is measuring the wheel angle
## for every speed the game can be set to.
func test_twice_the_ground_turns_the_wheels_twice_as_far() -> void:
	_view = TestView.stage()
	var train_id := _run_until_moving()
	var line_speed := _cruise_until_steady(train_id)
	check_gt(line_speed, 0.05,
			"the wheels are compared over two stretches at a steady %.3f tiles a tick" % line_speed)
	_look_at_train(train_id)
	var base := _view.entities.wheel_distance(train_id)
	_view.run_frame(2)
	var first := _view.entities.wheel_distance(train_id) - base
	_view.run_frame(4)
	var second := _view.entities.wheel_distance(train_id) - base - first
	check_gt(first, 0.0, "the consist is rolling, so distance accrues between draws")
	check_near(second / first, 2.0,
			"twice the ground is twice the wheel travel (%.3f vs %.3f tiles)" % [first, second], 0.15)


func test_a_consist_rebuilt_mid_run_keeps_its_crank_angle() -> void:
	_view = TestView.stage()
	var train_id := _run_until_moving()
	_look_at_train(train_id)
	_view.run_frame(30)
	var phase := _view.entities.wheel_phase(train_id)
	var travelled := _view.entities.wheel_distance(train_id)
	var before := _view.entities.wheels_driven_last_tick()

	check_true(bool(_view.session.trains.add_wagon(train_id, "coal_hopper")["ok"]),
			"the yard bolts another wagon on")
	_view.entities.tick()

	check_gt(travelled, 0.0, "and there is ground behind it to measure against")
	check_near(_view.entities.wheel_distance(train_id), travelled,
			"rebuilding the consist is not the train moving", 0.0001)
	check_near(_view.entities.wheel_phase(train_id), phase,
			"and the new bodies are posed at the angle the wheels already held", 0.0001)
	check_gt(float(_view.entities.wheels_driven_last_tick()), float(before - 1),
			"the new bodies were posed, not left at zero")


# --- 3.5 what the view refuses to draw ------------------------------------

## Suspension is the presentation's own budget, so it is measured in the
## presentation's own work: the offscreen consist's node is not repositioned, not
## rotated, not animated.  Where it actually is stays a question for the
## simulation, which is why the second case below is about money.
func test_a_consist_off_the_edge_of_the_screen_stops_being_worked_on() -> void:
	_view = TestView.stage()
	var line := TestSession.coal_line(_view.session)
	var running := int(line["train"])
	var parked_train := _a_train_that_waits(_view.session, int(line["plant_station"]))
	_view.look_at_tile(Vector2i(_view.session.trains.position_tiles(parked_train)))
	_view.zoom_to(MEDIUM_ZOOM)
	_view.settle()
	_view.entities.tick()

	check_false(_view.entities.is_train_suspended(parked_train),
			"the consist in the middle of the picture is drawn")
	check_gt(float(_view.entities.suspended_train_count()), 0.0,
			"and the renderer says how many it left alone (%d)" % _view.entities.suspended_train_count())
	var quiet := _view.entities.train_node(running).position
	_view.session.advance_ticks(600)
	for frame in 6:
		_view.rig.tick(TestView.FRAME)
		_view.entities.tick()

	check_true(_view.entities.is_train_suspended(running),
			"the line it runs on is nowhere near this view")
	var stayed := _view.entities.train_node(running).position
	check_near(stayed.x, quiet.x, "its body was not moved", 0.000001)
	check_near(stayed.y, quiet.y, "not lifted", 0.000001)
	check_near(stayed.z, quiet.z, "not turned", 0.000001)
	var live := _view.session.trains.position_tiles(running)
	check_neq(int(floori(live.x)), int(floori(quiet.x)),
			"while the simulation went on moving it to (%.1f, %.1f)" % [live.x, live.y])


func test_an_offscreen_train_still_arrives_loads_and_earns() -> void:
	_view = TestView.stage()
	var line := TestSession.coal_line(_view.session)
	var running := int(line["train"])
	var corner := _the_far_corner_of_the_valley(_view.session,
			_view.session.stations.tile_of(int(line["mine_station"])))
	_view.look_at_tile(corner)
	_view.zoom_to(MEDIUM_ZOOM)
	_view.settle()
	_view.entities.tick()
	check_true(_view.entities.is_train_suspended(running),
			"the camera is parked on ground no railway reaches")

	var before := _view.session.cargo.delivered_total()
	var revenue := _view.session.cargo.revenue_total()
	var cash := _view.session.economy.cash
	TestSession.run_until(_view.session,
			func() -> bool: return _view.session.cargo.delivered_total() > before,
			TestSession.DELIVERY_TICKS)
	for frame in 10:
		_view.rig.tick(TestView.FRAME)
		_view.entities.tick()

	check_gt(_view.session.cargo.delivered_total(), before,
			"coal was loaded, hauled and delivered without a single pixel of it")
	check_gt(_view.session.cargo.revenue_total(), revenue, "and the railroad was paid")
	check_gt(_view.session.economy.cash, cash, "which the company noticed")
	check_neq(_view.session.trains.state_label(running), "", "it never stopped reporting a status")
	check_false(_view.entities.train_node(running).visible,
			"all of it happened with the consist left invisible")

	# Bringing it back into view must show the truth, not where the last drawn
	# frame left it: the simulation is the only authority on position.
	var live := _view.session.trains.position_tiles(running)
	_view.look_at_tile(Vector2i(floori(live.x), floori(live.y)))
	_view.settle()
	_view.entities.tick()
	check_false(_view.entities.is_train_suspended(running), "scrolled back, it is drawn again")
	var shown := _view.entities.train_node(running).position
	check_near(shown.x, live.x, "and it is exactly where the simulation put it", 0.001)
	check_near(shown.z, live.y, "in both axes", 0.001)


# --- 5.2 the promise: none of it reaches the simulation -------------------

func test_suspending_the_animation_changes_nothing_the_simulation_decides() -> void:
	var animated := TestView.stage()
	var suspended := TestView.stage()
	var animated_line := TestSession.coal_line(animated.session)
	var suspended_line := TestSession.coal_line(suspended.session)
	check_true(bool(animated_line["ok"]), "the first run has a coal line to simulate")
	check_true(bool(suspended_line["ok"]), "and so has the second")
	var train_id := int(animated_line["train"])
	var quiet_train_id := int(suspended_line["train"])

	# The same loop, the same follow, the same number of frames: the only thing
	# that differs is where the camera ended up, and therefore what the
	# presentation layers decided to draw.
	animated.rig.follow_train(train_id, Callable(animated.session.trains, "position_tiles"))
	animated.zoom_to(NEAR_ZOOM)
	suspended.rig.follow_train(quiet_train_id, Callable(suspended.session.trains, "position_tiles"))
	suspended.zoom_to(FAR_ZOOM)
	for frame in IDENTITY_TICKS:
		animated.run_frame()
		suspended.run_frame()
	# The frames above are the presentation comparison; the ledger comparison needs
	# a delivery, and a loaded leg across the valley takes longer than a frame
	# budget is worth.  Both clocks are stepped by the same amount, so the tick
	# equality checked below is still exact rather than merely close.
	animated.session.clock.step_ticks(TestSession.DELIVERY_TICKS)
	suspended.session.clock.step_ticks(TestSession.DELIVERY_TICKS)

	# Without these the identity below would be vacuous: two runs that drew
	# nothing at all would agree for the wrong reason.
	check_eq(animated.rig.lod_level(), IsoCameraRig.LOD_NEAR, "the first run stayed at the near tier")
	check_eq(suspended.rig.lod_level(), IsoCameraRig.LOD_FAR, "the second stayed at the far one")
	check_false(animated.effects.animation_suspended(), "its animation was running")
	check_true(suspended.effects.animation_suspended(), "the other one's was suspended")
	check_gt(float(animated.effects.emitted_total()), 0.0, "and the running one emitted particles")
	check_eq(float(suspended.effects.emitted_total()), 0.0, "while the suspended one emitted none")
	check_gt(float(animated.entities.drawn_triangle_total()), float(suspended.entities.drawn_triangle_total()),
		"the near run drew more geometry than the far run")
	check_true(animated.entities.labels_shown(), "and its tier still allows names")
	check_false(suspended.entities.labels_shown(), "while the overview withdraws them")
	check_eq(float(suspended.entities.visible_label_count()), 0.0, "and none are on screen")

	var left: GameSession = animated.session
	var right: GameSession = suspended.session
	check_eq(right.clock.tick_count, left.clock.tick_count, "both ran the same number of ticks")
	check_gt(float(left.cargo.delivery_count()), 0.0,
		"the near run delivered cargo, so there is a result to compare")
	check_eq(right.cargo.delivery_count(), left.cargo.delivery_count(), "the same number of deliveries")
	check_near(right.cargo.delivered_total(), left.cargo.delivered_total(),
		"the suspended run delivered exactly the same tonnage", 0.0001)
	check_near(right.cargo.revenue_total(), left.cargo.revenue_total(),
		"earned exactly the same for it", 0.0001)
	check_near(right.economy.cash, left.economy.cash, "and holds exactly the same money", 0.0001)
	check_eq(right.economy.ledger().size(), left.economy.ledger().size(),
		"the ledger has the same number of entries")
	check_near(_ledger_sum(right), _ledger_sum(left), "and the same value in them", 0.0001)
	check_true(right.economy.is_consistent(), "each run's own books still balance")
	check_near(right.trains.progress_fraction(quiet_train_id), left.trains.progress_fraction(train_id),
		"the train is the same fraction of the way along its route", 0.0001)
	var position := left.trains.position_tiles(train_id)
	var quiet_position := right.trains.position_tiles(quiet_train_id)
	check_near(quiet_position.x, position.x, "the train is at the same place to four decimals", 0.0001)
	check_near(quiet_position.y, position.y, "on both axes", 0.0001)
	check_eq(right.trains.state_of(quiet_train_id), left.trains.state_of(train_id),
		"and it is doing the same thing: loading, moving or waiting")
	check_near(right.trains.speed_tiles_per_tick(quiet_train_id), left.trains.speed_tiles_per_tick(train_id),
		"at the same speed", 0.0001)
	check_eq(_digest(right), _digest(left),
		"every cargo figure, train batch and station inventory agrees, line for line")
	animated.dispose()
	suspended.dispose()


# --- helpers --------------------------------------------------------------

## Builds the shipped coal line and returns the station at the colliery end.
func _line_station() -> int:
	var line := TestSession.coal_line(_view.session)
	check_true(bool(line["ok"]), "the valley can run a coal line for these cases to look at")
	return int(line["mine_station"])


func _zoom_for_level(level: int) -> float:
	match level:
		IsoCameraRig.LOD_NEAR:
			return NEAR_ZOOM
		IsoCameraRig.LOD_MEDIUM:
			return MEDIUM_ZOOM
		_:
			return FAR_ZOOM


## Steps the real loop until the train is genuinely under way, and hands back its
## id.  How long a loaded hopper takes to leave a colliery is not a fact a case
## should be built on a guess of.
func _run_until_moving() -> int:
	var line := TestSession.coal_line(_view.session)
	check_true(bool(line["ok"]), "a working coal line gives the effect layer something to plume")
	var train_id := int(line["train"])
	var trains: TrainService = _view.session.trains
	var frames := 0
	# "MOVING" and "rolling" are different moments: the state flips the moment the
	# brakes come off and the speed builds after it, and an emitter at rest is a
	# chimney that draws nothing.
	while frames < 4000 and not _is_rolling(trains, train_id):
		_view.run_frame()
		frames += 1
	check_lt(float(frames), 4000.0, "the consist got under way inside the budget")
	check_true(_is_rolling(trains, train_id), "and it is rolling fast enough to smoke")
	return train_id


func _is_rolling(trains: TrainService, train_id: int) -> bool:
	return trains.state_of(train_id) == trains.State.MOVING \
		and trains.speed_tiles_per_tick(train_id) > 0.02


## Puffs the pool was fed over the next `frames` presentation frames, with the
## simulation parked.
func _puffs_over(frames: int) -> int:
	var before := _view.effects.emitted_total()
	for frame in frames:
		_view.effects.tick()
	return _view.effects.emitted_total() - before


## Train bodies the renderer repositioned over the next `frames` presentation
## frames.
func _updates_over(frames: int) -> int:
	var total := 0
	for frame in frames:
		_view.entities.tick()
		total += _view.entities.entity_updates_last_frame()
	return total


## The triangles the asset compiler declared for one LOD of an asset.
func _manifest_triangles(asset_id: String, level: int) -> int:
	var manifest := _view.entities.catalog.manifest(asset_id)
	check_true(not manifest.is_empty(), "the compiler left a manifest for %s" % asset_id)
	var levels := manifest.get("lod_triangles") as Dictionary
	check_true(levels != null, "%s's manifest declares per-LOD triangle counts" % asset_id)
	var key := "LOD%d" % level
	check_true(levels.has(key), "%s declares %s" % [asset_id, key])
	return int(levels[key])


func _consist_triangles(train_id: int, level: int) -> int:
	var total := 0
	for stock_id in _view.session.trains.stock_of(train_id):
		var def := _view.session.data.stock(stock_id)
		total += _manifest_triangles(def.asset, level)
	return total


func _lod_body_names(root: Node) -> Array[String]:
	var found: Array[String] = []
	for child in root.get_children():
		if String(child.name).begins_with("LOD"):
			found.append(String(child.name))
	return found


## Which of an asset's LOD bodies the renderer has left switched on.
func _visible_lod_bodies(root: Node) -> Array[String]:
	var found: Array[String] = []
	for child in root.get_children():
		var body := child as Node3D
		if body != null and body.visible and String(body.name).begins_with("LOD"):
			found.append(String(body.name))
	return found


## Nodes under `root` still visible whose names start with `prefix` — the parts an
## asset carries only at its closest level.
func _visible_bodies_named_like(root: Node, prefix: String, seen: bool = true) -> int:
	var body := root as Node3D
	var visible := seen and (body == null or body.visible)
	var found := 0
	if visible and String(root.name).begins_with(prefix):
		found += 1
	for child in root.get_children():
		found += _visible_bodies_named_like(child, prefix, visible)
	return found



## A consist bought and left where it was bought: an idle train is a fixed point
## to aim a camera at.
## Point the camera at a running consist and let the rig actually get there:
## `look_at_tile` only sets a target and the pan is smooth, so a view asked to
## judge what it can see on the next frame is judging a camera still in transit.
## Run a consist up to its line speed and report the speed it settles at.  The
## brakes come off long before the regulator is open, and a case that compares two
## stretches of ground has to start after the ramp — hence stepping the real loop
## rather than assuming how many ticks a loaded hopper needs.
func _is_dwelling(trains: TrainService, train_id: int) -> bool:
	return trains.state_of(train_id) == trains.State.LOADING


func _cruise_until_steady(train_id: int) -> float:
	var trains: TrainService = _view.session.trains
	var speed := trains.speed_tiles_per_tick(train_id)
	for frame in 200:
		if trains.state_of(train_id) != trains.State.MOVING:
			break
		_view.run_frame(1)
		var next := trains.speed_tiles_per_tick(train_id)
		if absf(next - speed) < 0.0005:
			return next
		speed = next
	return speed


func _look_at_train(train_id: int) -> void:
	_view.zoom_to(MEDIUM_ZOOM)
	_view.look_at_tile(Vector2i(_view.session.trains.position_tiles(train_id)))
	# The same lock the player gets from "Follow (F)": a consist measured over
	# thirty ticks has travelled further than any view holds still, and a case
	# that watches a wheel from a camera the train has outgrown is watching a body
	# the renderer has deliberately stopped work on.
	_view.rig.follow_train(train_id, Callable(_view.session.trains, "position_tiles"))
	_view.settle()


func _a_train_that_waits(session: GameSession, station_id: int) -> int:
	var purchase := session.trains.purchase(station_id, "steam_440", ["coal_hopper"])
	return int(purchase.get("id", 0))


## The valley corner furthest from a tile, in tile units.  "Offscreen" needs a
## place that is definitely not near the action, and the map is the only thing
## large enough to guarantee it.
func _the_far_corner_of_the_valley(session: GameSession, near: Vector2i) -> Vector2i:
	var far := Vector2i(2, 2)
	var best := -1.0
	for candidate in [Vector2i(2, 2), Vector2i(2, 253), Vector2i(253, 2), Vector2i(253, 253)]:
		var distance := WorldCoords.distance_tiles(Vector2(near.x, near.y), Vector2(candidate.x, candidate.y))
		if distance > best:
			best = distance
			far = candidate
	return far


## A compact, order-dependent digest of everything the simulation has decided:
## the same shape the determinism suite compares, so a difference names itself.
func _digest(s: GameSession) -> String:
	var parts: PackedStringArray = []
	parts.append("tick=%d" % s.clock.tick_count)
	parts.append("date=%s" % s.clock.date.display())
	parts.append("cash=%.4f" % s.economy.cash)
	parts.append("ledger=%d:%.4f" % [s.economy.ledger().size(), _ledger_sum(s)])
	parts.append("cargo=%.4f/%.4f/%d" % [s.cargo.delivered_total(), s.cargo.revenue_total(),
			s.cargo.delivery_count()])
	for station_id in s.stations.stations():
		parts.append("st%d=%s" % [station_id, JSON.stringify(s.cargo.available_summary(station_id))])
	for train_id in s.trains.trains():
		var loads: Array[String] = []
		for cargo_id in s.trains.capacity_by_cargo(train_id):
			loads.append("%s %.4f" % [cargo_id, s.trains.loaded_for(train_id, cargo_id)])
		loads.sort()
		var at := s.trains.position_tiles(train_id)
		parts.append("tr%d=%s|%.6f|%.6f|%.6f|%s|%s" % [train_id, s.trains.state_label(train_id),
			at.x, at.y, s.trains.progress_fraction(train_id), ",".join(loads),
			JSON.stringify(s.trains.batches(train_id))])
	for industry_id in s.industries.industries():
		parts.append("in%d=%s" % [industry_id, JSON.stringify(s.industries.industry(industry_id).get("inventory", {}))])
	return "\n".join(parts)


func _ledger_sum(s: GameSession) -> float:
	var total := 0.0
	for transaction in s.economy.ledger():
		total += transaction.amount
	return total
