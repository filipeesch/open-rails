class_name TestConsistOnRail
extends TestBase

## Where a train is drawn against where its rails are.
##
## One path serves a whole train, and the two ways of drawing that fact both read as
## "nearly right" in a screenshot and are wrong on every curve.  Strung out along one
## root and turned as a unit, a consist is a plank: through a corner its tail cuts
## inside the rails and every wheel leaves the track it is supposed to be riding.
## Turned by a heading averaged over a tile either side of the engine, it is soup: a
## corner the rails kink through in a single step is drawn as a sweep no track has
## ever had.  And a height read off the cell the engine happens to be over leaves the
## whole train a full height step above or below the rails it is climbing.
##
## So each case here measures the drawn bodies against the rail graph — the cell a
## body lies in, the arm that cell carries, the cell at the end of it, the height of
## the surface along that arm — and never against the figures that placed them.  A
## renderer that agreed with its own inputs while drawing the train into a field would
## pass anything else.

## A consist measured in tile units has to be *on* the line, and a vehicle standing
## with its wheels on the rail is measured at its reference point: a tenth of a tile
## is already far more than the width of a rail.
const ON_LINE_TILES := 0.02
## How far a drawn vehicle may point away from the rail arm it stands on, in degrees.
## Anything over a couple of degrees is a heading made of arithmetic and not of track.
const ON_LINE_DEGREES := 1.5


## How close to the middle of its yard a train's middle has to stand to count as
## standing at the yard rather than somewhere along its frontage.
const HALT_CENTRE_TILES := 0.6

var _view: TestView


func setup() -> void:
	_view = null


func teardown() -> void:
	if _view != null:
		_view.dispose()
		_view = null


# --- on the line, the whole train at once -----------------------------------

func test_every_vehicle_of_a_running_train_stands_on_its_rails() -> void:
	## The shipped coal line, watched frame by frame across a leg.  This is the whole
	## complaint in one sentence: a train that is drawn half a tile off its lane looks
	## like a train driving through a field, and only the last vehicle of a long
	## consist is ever in the wrong place, so a case that looks at the engine alone
	## cannot see it.
	_view = TestView.stage()
	var line := TestSession.coal_line(_view.session)
	check_true(bool(line["ok"]), "a coal line to run a train over: " + String(line["reason"]))
	if not bool(line["ok"]):
		return
	var session := _view.session
	var train := int(line["train"])
	TestSession.run_until(session,
			func() -> bool: return session.trains.state_of(train) == session.trains.State.MOVING,
			TestSession.LEG_TICKS)
	var frames := 0
	var bodies_seen := 0
	for _round in 120:
		session.clock.step_ticks(4)
		_frame_follow(session, train)
		var root := _view.entities.train_node(train)
		if root == null:
			continue
		var bodies := _bodies(root)
		check_ge(float(bodies.size()), 3.0, "the consist is drawn body by body")
		for index in bodies.size():
			var at := _drawn_at(root, bodies[index])
			check_lt(_off_the_line(session, at), ON_LINE_TILES,
					"body %d sits on the line the rails occupy (frame %d)" % [index, _round])
			check_lt(_off_the_arm(session, at, _drawn_nose(bodies[index])), ON_LINE_DEGREES,
					"and body %d points down a rail it is standing on (frame %d)" % [index, _round])
			bodies_seen += 1
		frames += 1
		if session.trains.state_of(train) == session.trains.State.LOADING:
			break
	check_gt(float(frames), 20.0, "the leg was watched for a good part of its length")
	check_gt(float(bodies_seen), 60.0, "and every vehicle of the consist was measured")


func test_a_vehicle_is_never_drawn_on_ground_that_carries_no_rail() -> void:
	## The other half of the same measurement: not how far a body is from the line, but
	## whether the ground under it is track at all.  A coach standing in a field is the
	## sight a player remembers, whatever the arithmetic says.
	_view = TestView.stage()
	var line := TestSession.coal_line(_view.session)
	check_true(bool(line["ok"]), "a coal line to run a train over: " + String(line["reason"]))
	if not bool(line["ok"]):
		return
	var session := _view.session
	var train := int(line["train"])
	TestSession.run_until(session,
			func() -> bool: return session.trains.state_of(train) == session.trains.State.MOVING,
			TestSession.LEG_TICKS)
	var off_rail := 0
	var seen := 0
	for _round in 100:
		session.clock.step_ticks(4)
		_frame_follow(session, train)
		var root := _view.entities.train_node(train)
		if root == null:
			continue
		for body in _bodies(root):
			var at := _drawn_at(root, body)
			var tile := WorldCoords.world_to_tile_floor(at)
			if session.world.rail_mask_at(tile) == 0:
				off_rail += 1
			seen += 1
	check_gt(float(seen), 100.0, "every vehicle of every frame was counted")
	check_eq(off_rail, 0, "no vehicle was ever drawn on ground that carries no rail")


# --- the corner, taken one vehicle at a time -------------------------------

func test_a_consist_curves_one_vehicle_at_a_time() -> void:
	## A train bends once, where the track bends, and the bend travels along it.
	##
	## The engine is on the new bearing while the brake van is still on the old one —
	## that is what a train going round a corner actually looks like, and it is the
	## opposite of a consist bolted to one root and rotated about its own centre, which
	## turns every vehicle through the corner at the same instant and throws the tail off
	## the rails in the bargain.  So: the front and rear of the string disagree about
	## which way they are going, no two neighbours disagree by more than one rail arm,
	## and reading the vehicles in train order the direction changes once.
	var fixture := _corner_line()
	check_true(bool(fixture["ok"]), "an authored corner to run round: " + String(fixture["reason"]))
	if not bool(fixture["ok"]):
		return
	var session: GameSession = fixture["session"]
	var train := int(fixture["train"])
	TestSession.run_until(session,
			func() -> bool: return session.trains.state_of(train) == session.trains.State.MOVING,
			TestSession.LEG_TICKS)
	var spread := 0.0
	var worst_changes := 0
	var worst_pair := 0.0
	var worst_against_itself := 0.0
	var frames := 0
	for _tick in TestSession.LEG_TICKS:
		session.clock.step_ticks(1)
		_frame_follow(session, train)
		var root := _view.entities.train_node(train)
		if root == null:
			continue
		var noses := _noses(root)
		if noses.size() < 3:
			continue
		var between := _angle_between(noses[0], noses[noses.size() - 1])
		if between < 1.0:
			continue  # still on the straight, nothing to learn yet
		frames += 1
		spread = maxf(spread, between)
		var frames_along := session.trains.consist_frames(
				train, _view.entities.consist_offsets(train))
		if frames_along.size() != noses.size():
			continue
		var changes := 0
		var straight := 0.0
		var bent := 0.0
		for index in range(1, noses.size()):
			if _folds_back(frames_along[index - 1]["direction"], frames_along[index]["direction"]):
				continue  # a reversal inside the string, not a bend it is taking
			var pair := _angle_between(noses[index], noses[index - 1])
			worst_pair = maxf(worst_pair, pair)
			if pair > ON_LINE_DEGREES:
				changes += 1
				# Signed, because the law is about which way: a string going through one
				# corner bends one way, and a consist that bends one way and then the
				# other is drawing an S no track has.
				straight += absf(_signed_turn(noses[index - 1], noses[index]))
				bent += _signed_turn(noses[index - 1], noses[index])
		worst_changes = maxi(worst_changes, changes)
		# A string going through one corner bends one way.  Reading the turns as signed and
		# asking the whole of them to be no smaller than their sizes alone is what says none
		# of them went the other way — an S, which no track here has.
		worst_against_itself = maxf(worst_against_itself, straight - absf(bent))
		if session.trains.state_of(train) != session.trains.State.MOVING:
			break
	check_gt(float(frames), 10.0, "the string was watched while it was going through the bend")
	check_gt(spread, 40.0,
			"engine and brake van are on different bearings while the corner is between them (%.1f°)" % spread)
	check_le(worst_pair, 90.5,
			"and no pair of vehicles is turned further apart than the sharpest kink the rail"
			+	" pieces can make, a 90-degree corner (%.1f°)" % worst_pair)
	check_le(float(worst_changes), 2.0,
			"read in train order, the string changes direction where the rails do, once per turn (%d)" % worst_changes)
	check_near(worst_against_itself, 0.0,
			"every vehicle turns the same way through the corner — a bend that reverses is an"
			+	" S no track has (%.2f rad of it)" % worst_against_itself, 0.02)


func test_a_corner_is_kinked_as_the_rails_are_and_not_swept() -> void:
	## Rails built from cells kink at the cell centre — that is the only shape the
	## piece vocabulary has — so a wheel follows a kink too.  A heading averaged over
	## half a tile each side of the engine turns a corner into a curve the player can see
	## no track for, which is what "too smooth" is.  Every vehicle therefore has to be
	## drawn pointing along one of the eight bearings the rail actually offers.
	var fixture := _corner_line()
	check_true(bool(fixture["ok"]), "an authored corner to run round: " + String(fixture["reason"]))
	if not bool(fixture["ok"]):
		return
	var session: GameSession = fixture["session"]
	var train := int(fixture["train"])
	TestSession.run_until(session,
			func() -> bool: return session.trains.state_of(train) == session.trains.State.MOVING,
			TestSession.LEG_TICKS)
	var worst := 0.0
	var watched := 0
	for _tick in TestSession.LEG_TICKS:
		session.clock.step_ticks(1)
		_frame_follow(session, train)
		var root := _view.entities.train_node(train)
		if root == null:
			continue
		for body in _bodies(root):
			worst = maxf(worst, _off_a_bearing(_drawn_nose(body)))
			watched += 1
		if session.trains.state_of(train) != session.trains.State.MOVING:
			break
	check_gt(float(watched), 60.0, "the whole passage through the bend was measured")
	check_lt(worst, ON_LINE_DEGREES,
			"no vehicle was ever drawn between two rail bearings (%.2f° of the nearest)" % worst)


# --- the grade, under every wheel ------------------------------------------

func test_a_train_on_a_grade_stands_on_its_own_stretch_of_rail() -> void:
	## Height, measured per vehicle instead of per train.
	##
	## The models are compiled with their wheels on the rail head at
	## `TrackPieces.RIDE_HEIGHT` above their own origin, so a vehicle set down on the
	## surface it runs over has its wheels on the rail by construction.  The surface
	## under a vehicle is the straight between the two cells it lies across — the same
	## straight the rails are drawn along — so each body has its own height, and one
	## height shared by the whole consist is a train floating over a rising line with
	## its tail buried in a falling one.
	var fixture := _grade_line()
	check_true(bool(fixture["ok"]), "an authored climb to run over: " + String(fixture["reason"]))
	if not bool(fixture["ok"]):
		return
	var session: GameSession = fixture["session"]
	var train := int(fixture["train"])
	var offsets: Array = _view.entities.consist_offsets(train)
	check_ge(float(offsets.size()), 3.0, "the renderer knows how its consist is strung out")
	TestSession.run_until(session,
			func() -> bool: return session.trains.state_of(train) == session.trains.State.MOVING,
			TestSession.LEG_TICKS)
	var on_a_grade := 0
	var frames := 0
	for _tick in TestSession.LEG_TICKS:
		session.clock.step_ticks(1)
		_frame_follow(session, train)
		var root := _view.entities.train_node(train)
		if root == null:
			continue
		var bodies := _bodies(root)
		if bodies.size() < 3 or offsets.size() != bodies.size():
			continue
		var frames_along := session.trains.consist_frames(train, offsets)
		if frames_along.size() != bodies.size():
			continue
		var heights := []
		var straddling := false
		for index in bodies.size():
			var step: Dictionary = frames_along[index]
			var expected := TrackPieces.surface(session.world, step["from_tile"], step["to_tile"],
					float(step["t"]))
			var drawn := root.position.y + bodies[index].position.y
			check_near(drawn, expected,
					"body %d stands on the surface its own point of the line is on" % index, 1e-4)
			heights.append(drawn)
			if session.world.elevation_at(step["from_tile"]) \
					!= session.world.elevation_at(step["to_tile"]):
				straddling = true
		if straddling:
			on_a_grade += 1
			var first := float(heights[0])
			var different := false
			for height in heights:
				if absf(float(height) - first) > 0.0001:
					different = true
			check_true(different,
					"a consist on a climb is not drawn all at one height")
		frames += 1
		if session.trains.state_of(train) != session.trains.State.MOVING:
			break
	check_gt(float(on_a_grade), 10.0, "the string was watched while it was climbing")
	check_gt(float(frames), 20.0, "and its height was measured across most of the run")


func test_a_climbing_vehicle_is_tilted_to_its_grade() -> void:
	## A locomotive crossing a height step with its boiler level is a model hovering at
	## one end and buried at the other, however right its centre is.  Its nose has to
	## point up the slope it is standing on, and the slope is the drawn line's own.
	var fixture := _grade_line()
	check_true(bool(fixture["ok"]), "an authored climb to run over: " + String(fixture["reason"]))
	if not bool(fixture["ok"]):
		return
	var session: GameSession = fixture["session"]
	var train := int(fixture["train"])
	TestSession.run_until(session,
			func() -> bool: return session.trains.state_of(train) == session.trains.State.MOVING,
			TestSession.LEG_TICKS)
	var offsets: Array = _view.entities.consist_offsets(train)
	var climbed := 0
	var levelled := 0
	var worst := 0.0
	for _tick in TestSession.LEG_TICKS:
		session.clock.step_ticks(1)
		_frame_follow(session, train)
		var root := _view.entities.train_node(train)
		if root == null:
			continue
		var bodies := _bodies(root)
		var frames_along := session.trains.consist_frames(train, offsets)
		if bodies.size() != frames_along.size() or bodies.size() != offsets.size():
			continue
		for index in bodies.size():
			var step: Dictionary = frames_along[index]
			# The frame walks the path forwards, so the surface climbs by `to` minus
			# `from` over `step`; a nose lying along that is raised by its sine.
			var rise := session.world.elevation_at(step["to_tile"]) \
					- session.world.elevation_at(step["from_tile"])
			var wanted := sin(atan2(rise, maxf(float(step["step"]), 0.0001)))
			var nose_y := bodies[index].transform.basis.x.y
			worst = maxf(worst, absf(nose_y - wanted))
			if absf(wanted) > 0.02:
				climbed += 1
			else:
				levelled += 1
			check_lt(absf(nose_y), 0.6, "no vehicle is ever drawn nose-diving through the ground")
		if session.trains.state_of(train) != session.trains.State.MOVING:
			break
	check_near(worst, 0.0,
			"every vehicle leans to the grade its own wheels are on, to a thousandth (%.4f)" % worst,
			0.002)
	check_gt(float(climbed), 10.0, "a consist crossing the steps leans into them")
	check_gt(float(levelled), 10.0, "and the same consist is level where the track is")


# --- the string itself ----------------------------------------------------

func test_the_nose_is_on_the_point_the_simulation_moves() -> void:
	## What a stop marker marks is the engine's front coupler, so that is the point the
	## drawing has to put a coupler on.  Half a tile out here and the train is correct in
	## every distance and every fare and visibly parked past its platform — the exact
	## fault this pins shut from the other side.
	var fixture := _corner_line()
	check_true(bool(fixture["ok"]), "an authored corner to run round: " + String(fixture["reason"]))
	if not bool(fixture["ok"]):
		return
	var session: GameSession = fixture["session"]
	var train := int(fixture["train"])
	var offsets: Array = _view.entities.consist_offsets(train)
	var engine_offset := float(offsets[0]) if not offsets.is_empty() else 0.0
	TestSession.run_until(session,
			func() -> bool: return session.trains.state_of(train) == session.trains.State.MOVING,
			TestSession.LEG_TICKS)
	var worst := 0.0
	for _tick in 400:
		session.clock.step_ticks(1)
		_frame_follow(session, train)
		var root := _view.entities.train_node(train)
		if root == null:
			continue
		var bodies := _bodies(root)
		if bodies.is_empty():
			continue
		var probe: Array = session.trains.consist_frames(train, [engine_offset, 0.0])
		if probe.size() == 2 \
			and _angle_between(probe[0]["direction"], probe[1]["direction"]) > ON_LINE_DEGREES:
			continue  # a corner inside the engine's own length: no rigid box holds the point there
		var nose := _drawn_nose(bodies[0])
		var coupler := _drawn_at(root, bodies[0]) + nose * engine_offset
		worst = maxf(worst, coupler.distance_to(session.trains.position_tiles(train)))
		if session.trains.state_of(train) != session.trains.State.MOVING:
			break
	check_lt(worst, 0.02,
			"the drawn engine's front coupler is the point the simulation is moving (%.4f tiles off at worst)" % worst)


func test_the_consist_neither_stretches_nor_folds_through_a_bend() -> void:
	## A train is a string of fixed lengths.  Round a corner the straight-line distance
	## between two vehicles can only come shorter than the rail between them — a string
	## cannot stretch — and it cannot come near zero, which is what a consist drawn by
	## rotating a rigid frame about the wrong point does to the vehicle on the inside.
	var fixture := _corner_line()
	check_true(bool(fixture["ok"]), "an authored corner to run round: " + String(fixture["reason"]))
	if not bool(fixture["ok"]):
		return
	var session: GameSession = fixture["session"]
	var train := int(fixture["train"])
	var offsets: Array = _view.entities.consist_offsets(train)
	check_ge(float(offsets.size()), 3.0, "the renderer knows how its consist is strung out")
	TestSession.run_until(session,
			func() -> bool: return session.trains.state_of(train) == session.trains.State.MOVING,
			TestSession.LEG_TICKS)
	var watched := 0
	for _tick in TestSession.LEG_TICKS:
		session.clock.step_ticks(1)
		_frame_follow(session, train)
		var root := _view.entities.train_node(train)
		if root == null:
			continue
		var bodies := _bodies(root)
		if bodies.size() != offsets.size():
			continue
		var frames_along := session.trains.consist_frames(train, offsets)
		if frames_along.size() != bodies.size():
			continue
		for index in range(1, bodies.size()):
			var arc := absf(float(offsets[index]) - float(offsets[index - 1]))
			var chord := _drawn_at(root, bodies[index]).distance_to(_drawn_at(root, bodies[index - 1]))
			check_le(chord, arc + 0.001,
					"vehicles %d and %d are no further apart than the rail between them" % [index - 1, index])
			if _folds_back(frames_along[index - 1]["direction"], frames_along[index]["direction"]):
				continue  # a yard that ends the line: its own case measures those frames
			check_ge(chord, arc * 0.6,
					"and never folded back on one another either (%.3f against %.3f)" % [chord, arc])
			watched += 1
		if session.trains.state_of(train) != session.trains.State.MOVING:
			break
	check_gt(float(watched), 30.0, "the string was measured through the bend and the straight alike")


func test_a_reversal_at_a_dead_end_folds_the_string_on_the_rails() -> void:
	## A yard standing beside a single track is a dead end, and a route into one goes in
	## over the same cells it comes out over: the line the simulation walks turns
	## straight back on itself at the access cell.  A V1 consist has no run-around — the
	## engine cannot change ends — so the string that comes out of that is folded, nose
	## to nose, and it unwinds one vehicle at a time as the fold passes each coupler.
	## That is a visible simplification and it is recorded as one.  What it may never do
	## is put a vehicle somewhere the rails are not: a reversal is the worst-case frame
	## for the height and bearing a body is drawn at, so it is measured, not excused.
	var fixture := _corner_line()
	check_true(bool(fixture["ok"]), "an authored dead end to reverse at: " + String(fixture["reason"]))
	if not bool(fixture["ok"]):
		return
	var session: GameSession = fixture["session"]
	var train := int(fixture["train"])
	var offsets: Array = _view.entities.consist_offsets(train)
	TestSession.run_until(session,
			func() -> bool: return session.trains.state_of(train) == session.trains.State.MOVING,
			TestSession.LEG_TICKS)
	var folded := 0
	var worst_off_line := 0.0
	var worst_bearing := 0.0
	var worst_turn := 180.0
	for _tick in TestSession.LEG_TICKS:
		session.clock.step_ticks(1)
		_frame_follow(session, train)
		var root := _view.entities.train_node(train)
		if root == null:
			continue
		var bodies := _bodies(root)
		var frames_along := session.trains.consist_frames(train, offsets)
		if bodies.size() != frames_along.size() or bodies.size() < 2:
			continue
		var noses := _noses(root)
		for index in bodies.size():
			var at := _drawn_at(root, bodies[index])
			worst_off_line = maxf(worst_off_line, _off_the_line(session, at))
			worst_bearing = maxf(worst_bearing, _off_the_arm(session, at, noses[index]))
		for index in range(1, bodies.size()):
			if not _folds_back(frames_along[index - 1]["direction"],
					frames_along[index]["direction"]):
				continue
			folded += 1
			# Nose to nose, exactly: a body that has swung part way round — or is still
			# pointing where the line it stands on does not go — is the fault here.
			worst_turn = minf(worst_turn, _angle_between(noses[index], noses[index - 1]))
		if session.trains.state_of(train) != session.trains.State.MOVING:
			break
	check_gt(float(folded), 10.0, "the reversal inside the string was watched, not avoided")
	check_gt(worst_turn, 170.0,
			"and the vehicles the fold runs through stand nose to nose (%.1f° at the least)" % worst_turn)
	check_lt(worst_off_line, ON_LINE_TILES,
			"while every vehicle of the folded string stays on the line (%.4f tiles at worst)" % worst_off_line)
	check_lt(worst_bearing, ON_LINE_DEGREES,
			"and every one of them points down a rail (%.1f° at worst)" % worst_bearing)


func test_a_train_standing_in_a_yard_is_on_its_rails_too() -> void:
	## Before a route has ever moved it, a consist sits in the yard it was bought in, and
	## that is the first thing a player sees of a train.  Parked stock has to be on the
	## rails and pointing down them exactly as running stock does — and it has to be
	## strung out behind the engine, not piled on it.
	var fixture := _corner_line()
	check_true(bool(fixture["ok"]), "an authored corner to run round: " + String(fixture["reason"]))
	if not bool(fixture["ok"]):
		return
	var session: GameSession = fixture["session"]
	var train := int(fixture["train"])
	_frame_follow(session, train)
	var root := _view.entities.train_node(train)
	check_true(root != null, "the consist has bodies before it has ever moved")
	if root == null:
		return
	var bodies := _bodies(root)
	check_ge(float(bodies.size()), 3.0, "every vehicle of it is drawn")
	var access: Dictionary = session.stations.rail_access(session.trains.home_station(train))
	var lane: Vector2 = WorldCoords.tile_to_world_xz(access["tile"])
	var run: Vector2 = access.get("direction", Vector2.RIGHT)
	if run == Vector2.ZERO:
		run = Vector2.RIGHT
	for index in bodies.size():
		var at := _drawn_at(root, bodies[index])
		check_lt(_off_the_line(session, at), ON_LINE_TILES,
				"body %d of parked stock stands on the line" % index)
		check_lt(_off_the_arm(session, at, _drawn_nose(bodies[index])), ON_LINE_DEGREES,
				"and body %d points down a rail" % index)
		if index > 0:
			var apart := at.distance_to(_drawn_at(root, bodies[index - 1]))
			var offsets := _view.entities.consist_offsets(train)
			var coupled := absf(float(offsets[index]) - float(offsets[index - 1]))
			check_near(apart, coupled, "and body %d hangs %0.2f tiles off the one ahead of it" % [index, coupled], 0.02)


func test_a_consist_waiting_without_a_route_is_a_string_of_vehicles() -> void:
	## The first train a player ever sees is stock bought and standing at a yard with
	## nothing filed for it to run — and with no path to measure from, every vehicle
	## used to be set down on the halt's own point: a pile of locomotives on one set of
	## rails.  Waiting is a pose too, and the ground it is posed on is the yard's own.
	var fixture := _corner_line()
	check_true(bool(fixture["ok"]), "a yard and a consist to wait with: " + String(fixture["reason"]))
	if not bool(fixture["ok"]):
		return
	var session: GameSession = fixture["session"]
	var train := int(fixture["train"])
	session.trains.clear_route(train)
	var track: PackedVector2Array = session.trains.train(train)["path"]
	check_lt(float(track.size()), 2.0, "the consist has no route left to run")
	_frame_follow(session, train)
	var root := _view.entities.train_node(train)
	check_true(root != null, "and the waiting consist is drawn")
	if root == null:
		return
	var offsets: Array = _view.entities.consist_offsets(train)
	var bodies := _bodies(root)
	check_ge(float(bodies.size()), 3.0, "every vehicle of it")
	for index in bodies.size():
		var at := _drawn_at(root, bodies[index])
		check_lt(_off_the_line(session, at), ON_LINE_TILES,
				"body %d of a waiting train hangs on a rail" % index)
		var pointing := "and points down the line it is standing on"
		if index > 0:
			pointing = "and body %d points down a line too" % index
		check_lt(_off_the_arm(session, at, _drawn_nose(bodies[index])), ON_LINE_DEGREES, pointing)
		if index > 0:
			var apart := at.distance_to(_drawn_at(root, bodies[index - 1]))
			var coupled := absf(float(offsets[index]) - float(offsets[index - 1]))
			check_gt(apart, coupled * 0.5,
					("and body %d is its own vehicle away from the one ahead, not "
							+ "stacked on it (%.2f apart)") % [index, apart])
			check_near(apart, coupled,
					"body %d hangs %0.2f tiles off the one ahead of it" % [index, coupled], 0.06)


# --- standing at a platform -----------------------------------------------

func test_a_stopped_train_halts_beside_its_platform() -> void:
	## A yard is a length of deck beside a line, and the whole reason it exists is to
	## exchange cargo with a train standing alongside that deck.  Held to the cell the
	## yard couples to — which for a wharf at the end of a line is the only straight
	## cell, one end of a three-cell frontage — the engine stopped at the platform's
	## last handrail and its wagons lay back along the approach, off the deck they had
	## come to serve.  So a halt is measured in trains: the pull-up is half a consist,
	## and the middle of the train — where its traffic is — stands on the marker.
	_view = TestView.stage()
	var view := _view
	var line := TestSession.coal_line(view.session)
	check_true(bool(line["ok"]), "the authored coal line, to arrive on: " + String(line["reason"]))
	if not bool(line["ok"]):
		return
	var session: GameSession = view.session
	var train := int(line["train"])
	TestSession.run_until(session,
			func() -> bool: return session.trains.state_of(train) == session.trains.State.LOADING,
			TestSession.LEG_TICKS)
	var stops_seen := 0
	var previous_station := 0
	var shortest := 99.0
	for _tick in TestSession.LAP_TICKS:
		session.clock.step_ticks(1)
		if session.trains.state_of(train) != session.trains.State.LOADING:
			continue
		var station := session.trains.current_station(train)
		if station == previous_station:
			continue
		previous_station = station
		stops_seen += 1
		var access: Dictionary = session.stations.rail_access(station)
		var run: Vector2 = access["direction"]
		var centre := session.stations.centre_of(session.stations.station(station)["anchor"],
				session.stations.station(station)["footprint"])
		var coupler := session.trains.position_tiles(train)
		var deck := _deck_along_side(view, session, station, run)
		var along := coupler.dot(run)
		check_near(clampf(along, float(deck[0]), float(deck[1])), along,
				"the halt is on the platform, not short of it or past it at %s"
				% session.stations.name_of(station), 0.001)
		var cover := _deck_along_train(view, session, train, station, run)
		var span := _train_span_along(view, session, train, run)
		shortest = minf(shortest, cover)
		# Where the line runs on past the engine's nose, there was room to pull up,
		# and the train took it: its middle stands abreast its yard.  Where the line
		# ends — a wharf, a pit — the train stops where the ballast stops and lies as
		# far alongside as the rail reaches, which is the yard's limit and not the
		# halt's.
		var offsets: Array = view.entities.consist_offsets(train)
		var frames: Array = session.trains.consist_frames(train, offsets)
		check_false(frames.is_empty(), "and the consist has a stand on the ground at %s"
				% session.stations.name_of(station))
		if frames.is_empty():
			continue
		var nose: Vector2 = frames[0]["direction"]
		var ahead := WorldCoords.world_to_tile_floor(coupler + nose * 0.75)
		if session.world.rail_mask_at(ahead) == 0:
			continue
		var middle := (float(span["near"]) + float(span["far"])) * 0.5
		check_le(absf(middle - centre.dot(run)), HALT_CENTRE_TILES,
				"the middle of the train stands abreast the middle of the yard that "
				+ "stopped it, at %s (mid %.2f, yard %.2f)" % [
					session.stations.name_of(station), middle, centre.dot(run)])
	check_ge(float(stops_seen), 2.0, "both yards were arrived at, not just the first")
	check_ge(shortest, 1.0,
			"and at every halt a whole vehicle's length of deck lay abreast the train " 			+ "(%.2f at the least)" % shortest)


func test_a_route_stops_on_the_ground_its_yard_owns() -> void:
	## Where a train stops is a domain fact, not a drawing trick: the cell it stops on is
	## the one abreast the middle of the yard's own purchased ground, and it has to be
	## rail, inside that ground, and the same place whether the train is parked or has
	## just arrived.  A stop that is any of those things is a train standing in a field.
	var fixture := _authored_line([_elbow()], Vector2i(12, 21), Vector2i(22, 26))
	check_true(bool(fixture["ok"]), "an authored yard to stop at: " + String(fixture["reason"]))
	if not bool(fixture["ok"]):
		return
	var session: GameSession = fixture["session"]
	var train := int(fixture["train"])
	var station := int(fixture["from_station"])
	var instance := session.stations.station(station)
	var berth := session.stations.berth_tile(station)
	check_true(session.world.rail_mask_at(berth) != 0,
			"the yard's berth is a cell the rails run through, not the ground beside them")
	# The berth is a rail cell, so it stands beside the yard rather than inside it: what
	# has to lie within the purchased ground is where it falls along the line.
	var access: Dictionary = session.stations.rail_access(station)
	var run: Vector2 = access["direction"]
	var centre := session.stations.centre_of(instance["anchor"], instance["footprint"])
	var frontage := absf(run.x) * float(instance["footprint"].x) \
			+ absf(run.y) * float(instance["footprint"].y)
	check_le(absf((WorldCoords.tile_to_world_xz(berth) - centre).dot(run)), frontage * 0.5 + 0.5,
			"and it stands abreast the ground the yard bought, not past its end")
	var halt := session.trains.position_tiles(train)
	var marker := WorldCoords.tile_to_world_xz(berth)
	var reach := session.trains.consist_length(train) * 0.5
	check_le(halt.distance_to(marker), reach + 0.001,
			"a train that has never moved stands at its halt, within half a consist of " \
			+ "the yard's own cell (%.2f off)" % halt.distance_to(marker))
	var path: PackedVector2Array = session.trains.train(train)["path"]
	check_lt(path[0].distance_to(halt), 0.001,
			"the route runs to the halt, so the first stop is where the train stands")
	check_true(session.world.rail_mask_at(WorldCoords.world_to_tile_floor(halt)) != 0,
			"and the halt it stands on is a cell the rails run through")
	_frame_follow(session, train)
	var root := _view.entities.train_node(train)
	check_true(root != null, "and the parked consist is drawn there, at the platform")


## The deck's reach along the line, as `[near, far]` distances along the run — the same
## figures the yard is drawn with, asked of the same code, so a test cannot pass by
## disagreeing with the picture.
func _deck_along_side(view: TestView, session: GameSession, station_id: int, run: Vector2) -> Array:
	var reach: Array = view.entities.platform_reach(
			session.stations.def_of(station_id).asset)
	var spot: Dictionary = view.entities.station_transform(session.stations.station(station_id),
			session.stations.rail_access(station_id), float(reach[0]), float(reach[1]))
	var middle: Vector2 = spot["position"]
	var half := float(reach[1])
	return [middle.dot(run) - half, middle.dot(run) + half]


## How much deck lies abreast the drawn train, in tiles.
## How much deck lies abreast the drawn train, as a report: the cover in tiles,
## how many bodies were counted, and the spans both sides of the overlap.  A
## measurement that comes back zero has to say why, or a case reads as a fault in
## the halt when the ruler was the thing that was broken.
func _deck_along_train(view: TestView, session: GameSession, train_id: int, station_id: int,
		run: Vector2) -> float:
	var deck := _deck_along_side(view, session, station_id, run)
	var span := _train_span_along(view, session, train_id, run)
	var cover := maxf(0.0, minf(float(span["far"]), float(deck[1])) \
			- maxf(float(span["near"]), float(deck[0])))
	return cover


## The drawn consist's extent along a line, as `{"near", "far", "drawn"}` in tile
## distances along `run`, and the halt's own marker included so a short train is not
## measured as a point.
func _train_span_along(view: TestView, session: GameSession, train_id: int,
		run: Vector2) -> Dictionary:
	# Stepping the clock moves the simulation; the picture only lands where the
	# simulation got to once the renderer has drawn a frame — and a renderer with a
	# camera pointed elsewhere suspends the consist it cannot see, its bodies left
	# standing where they were first made.  So look at the train and ask for the frame,
	# as the game loop does, and measure what it drew.
	view.look_at_tile(WorldCoords.world_to_tile_floor(session.trains.position_tiles(train_id)))
	view.entities.tick()
	var root := view.entities.train_node(train_id)
	var near := 999.0
	var far := -999.0
	var drawn := 0
	if root != null:
		for body in _bodies(root):
			var along := _drawn_at(root, body).dot(run)
			near = minf(near, along)
			far = maxf(far, along)
			drawn += 1
	var coupler := session.trains.position_tiles(train_id).dot(run)
	near = minf(near, coupler)
	far = maxf(far, coupler)
	return {"near": near, "far": far, "drawn": drawn}



# --- the fixtures ---------------------------------------------------------

## A blank world with one right-angle turn in it and a train running round the corner:
## the bend is authored rather than stumbled on, so a case that needs a curve has one
## at a known place, on known ground.
func _corner_line() -> Dictionary:
	return _authored_line([_elbow()], Vector2i(12, 21), Vector2i(22, 26))


## The same, on ground that steps up under the line: a consist three vehicles long
## spends most of its running with two cells of different height under it.
func _grade_line() -> Dictionary:
	## The ground is stepped before the line is laid over it, as a player would grade a
	## valley and then run a line along it — and so the rail is committed knowing the
	## slope it has to carry.
	return _authored_line([_straight_rise()], Vector2i(12, 21), Vector2i(28, 21),
			func(session: GameSession) -> void:
				for x in range(4, 21):
					TestConstruction.set_height_column(session, x, 0, 63, 4)
				for x in range(21, 60):
					TestConstruction.set_height_column(session, x, 0, 63, 5))


func _elbow() -> Array[Vector2i]:
	var run: Array[Vector2i] = []
	for x in range(10, 22):
		run.append(Vector2i(x, 20))
	for y in range(21, 31):
		run.append(Vector2i(21, y))
	return run


func _straight_rise() -> Array[Vector2i]:
	var run: Array[Vector2i] = []
	for x in range(8, 40):
		run.append(Vector2i(x, 20))
	return run


## Stages a blank view, lays a line, puts a yard at each end of it and a train on the
## route between them — the game's own calls, so what is measured is what a player
## would have built.
func _authored_line(runs: Array, from_hint: Vector2i, to_hint: Vector2i,
		prepare: Callable = Callable()) -> Dictionary:
	_view = TestView.stage_blank(64, 64)
	var session := _view.session
	if prepare.is_valid():
		prepare.call(session)
	var reason := ""
	for run in runs:
		var laid := session.builder.build_track_run(run)
		if not bool(laid["ok"]):
			reason = "rail refused: " + String(laid["reason"])
			return {"ok": false, "reason": reason, "session": session, "train": 0}
	var from_station := _yard(session, from_hint, "Lower Yard")
	var to_station := _yard(session, to_hint, "Upper Yard")
	if from_station == 0 or to_station == 0:
		return {"ok": false, "reason": "yards refused", "session": session, "train": 0}
	var bought := session.trains.purchase(from_station, "steam_440", ["coal_hopper", "coal_hopper"])
	if not bool(bought["ok"]):
		return {"ok": false, "reason": "train refused: " + String(bought["reason"]),
			"session": session, "train": 0}
	var train := int(bought["id"])
	var stops: Array[Dictionary] = [
		{"station_id": from_station, "load": [], "unload": []},
		{"station_id": to_station, "load": [], "unload": []},
	]
	var routed := session.trains.set_route(train, stops)
	if not bool(routed["ok"]):
		return {"ok": false, "reason": "route refused: " + String(routed["reason"]),
			"session": session, "train": train}
	return {"ok": true, "reason": "", "session": session, "train": train,
		"from_station": from_station, "to_station": to_station}


## A yard standing beside the line, at the anchor the case names or on the closest
## ground beside it that will hold one.  `TestSession.station_for_tile` hunts for a
## station that *serves* a source tile, and a bare geometry world has no town to
## serve; what these cases need is a yard whose platform edge is against the rail
## they are measuring, at a position the case can point at.
func _yard(session: GameSession, anchor: Vector2i, label: String) -> int:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var here := Vector2i(anchor.x + dx, anchor.y + dy)
			var built := session.builder.build_station("small_station", here, label)
			if bool(built["ok"]):
				return int(built["id"])
	return 0


## Bring the view round to the train and run the one frame that places it.  The renderer
## suspends what it cannot see, so a case that measures a consist has to be looking at
## it — and a case that never looked would be measuring the last frame it did.
func _frame_follow(session: GameSession, train_id: int) -> void:
	var at := session.trains.position_tiles(train_id)
	_view.look_at_tile(Vector2i(floori(at.x), floori(at.y)))
	_view.entities.tick()


# --- measuring a drawn body against the ground ----------------------------

func _bodies(root: Node) -> Array[Node3D]:
	var bodies: Array[Node3D] = []
	for child in root.get_children():
		if String(child.name).begins_with("Stock_"):
			bodies.append(child as Node3D)
	return bodies


func _noses(root: Node) -> Array[Vector2]:
	var noses: Array[Vector2] = []
	for body in _bodies(root):
		noses.append(_drawn_nose(body))
	return noses


## Where a body is drawn, in tile space.  The consist's root carries the train's
## position and no rotation of its own, so a body's place on the ground is the train's
## place plus its own offset — and nothing here needs a scene tree to say so.
func _drawn_at(root: Node3D, body: Node3D) -> Vector2:
	return Vector2(root.position.x + body.position.x, root.position.z + body.position.z)


## Which way a drawn body is pointing, off its own basis and not off an Euler angle: a
## vehicle on a grade is pitched as well as turned, and reading `rotation.y` back out of
## a pitched basis is how a heading test starts telling lies.
func _drawn_nose(body: Node3D) -> Vector2:
	var forward := body.transform.basis.x
	return Vector2(forward.x, forward.z).normalized()


func _angle_between(first: Vector2, second: Vector2) -> float:
	return rad_to_deg(acos(clampf(first.dot(second), -1.0, 1.0)))


## How far a point sits from the nearest stretch of line the rails actually occupy:
## the straight from one cell's lane to the lane of a cell it connects to.
func _off_the_line(session: GameSession, at: Vector2) -> float:
	var tile := WorldCoords.world_to_tile_floor(at)
	var best := 99.0
	for direction in RailDirections.directions_in(session.world.rail_mask_at(tile)):
		var from := WorldCoords.tile_to_world_xz(tile)
		var to := WorldCoords.tile_to_world_xz(tile + RailDirections.offset(direction))
		best = minf(best, _distance_to_segment(at, from, to))
	return best


## How far a vehicle's own direction is from the direction of some rail under it, in
## degrees.  Measured off the mask, so a consist drawn on a smooth curve of its own
## making scores badly even while it is exactly on the track.
## Which way the nearest stretch of rail runs, and how far the body is from it.
##
## Distance and bearing have to be asked of the same piece of line: a vehicle sitting
## with its origin just across a shared edge stands on the stretch that belongs to the
## cell behind it as much as the one under it, and reading only the arms of the cell its
## centre fell in reports a locomotive laid across the line at 90 degrees.  So the search
## takes the cell and its neighbours and answers for the stretch nearest the point.
func _off_the_arm(session: GameSession, at: Vector2, nose: Vector2) -> float:
	var arm := _nearest_rail_run(session, at)
	if arm == Vector2.INF:
		return 999.0
	return minf(_angle_between(arm, nose), _angle_between(-arm, nose))


func _nearest_rail_run(session: GameSession, at: Vector2) -> Vector2:
	var tile := WorldCoords.world_to_tile_floor(at)
	var best_run := Vector2.INF
	var best_distance := 99.0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var here := Vector2i(tile.x + dx, tile.y + dy)
			for direction in RailDirections.directions_in(session.world.rail_mask_at(here)):
				var from := WorldCoords.tile_to_world_xz(here)
				var to := WorldCoords.tile_to_world_xz(here + RailDirections.offset(direction))
				var distance := _distance_to_segment(at, from, to)
				if distance < best_distance:
					best_distance = distance
					best_run = (to - from).normalized()
	return best_run


## The same question asked of the whole map: which of the eight bearings the rails are
## ever built from is a drawn vehicle furthest from?
## Whether the line turns straight back on itself between two frames.
##
## A route into a yard standing beside a single track goes in over the same cells it
## comes out over, so the path the simulation walks reverses at the access cell.  Every
## law about a *string* — its length, one bend per corner, its nose on the point it is
## moving — is a law about a string lying along one line, and a reversal puts two lines
## under it at once.  Those frames have a case of their own; what they must never do is
## put a vehicle off the rails.
func _folds_back(a: Vector2, b: Vector2) -> bool:
	return a.dot(b) < -0.9



## Which way a vehicle turned relative to the one ahead of it, and by how much: the
## sign is the corner's own direction, so a string bending one way then the other shows
## up as turns of opposite sign rather than as a bigger number.
func _signed_turn(ahead: Vector2, behind: Vector2) -> float:
	return atan2(ahead.x * behind.y - ahead.y * behind.x, ahead.dot(behind))


func _off_a_bearing(nose: Vector2) -> float:
	var best := 999.0
	for direction in RailDirections.COUNT:
		var run := Vector2(RailDirections.offset(direction)).normalized()
		best = minf(best, minf(_angle_between(run, nose), 180.0 - _angle_between(run, nose)))
	return best


## How much the ground rises a short way ahead of a point, in the direction asked for:
## positive uphill, negative downhill, zero on level track.
func _rise_ahead(session: GameSession, tile: Vector2i, run: Vector2) -> float:
	var here := session.world.elevation_at(tile)
	var ahead := tile + Vector2i(roundi(run.x), roundi(run.y))
	if not session.world.in_bounds(ahead):
		return 0.0
	return session.world.elevation_at(ahead) - here


func _distance_to_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
	var span := to - from
	if span.length_squared() < 0.000001:
		return point.distance_to(from)
	var along := clampf((point - from).dot(span) / span.length_squared(), 0.0, 1.0)
	return (point - from - span * along).length()
