extends SceneTree

## Synthetic stress world for `python tools/rr.py stress --ticks N`.
##
## Boots a blank WorldGrid through the real composition root (`start_blank`) and
## fills it to the population the specification's V1 stress target names: about
## 2 000 rail tiles, 100 stations, 100 industries, 100 trains, roughly 5 000
## buildings and 10 000 vegetation instances — then advances the requested tick
## budget and reports what that cost.  Nothing about the shipped valley is
## loaded; this measures the simulation and the world model, not the content.
##
## Placement is seeded arithmetic, never `randf()`: the same seed must place the
## same entities, which is what `--verify-seed` checks by building the whole world
## twice in one process and comparing a checksum.  A stress world that could not
## be reproduced could not be compared between runs either, and a perf number you
## cannot reproduce is a story.
##
## Exit code is the CLI's: 0 only when the full tick budget ran, money
## reconciled, every train reported a status and the seed check passed.
## Wall-clock (`Time.get_ticks_*`) appears here for reporting only; simulation
## advance is whole integer ticks, as everywhere else.

const MAP_SIZE := 256
## Eight through-lines — four each way — spanning the map.  241 tiles apiece
## minus sixteen crossings is 1 928 cells: the specification's "approximately
## 2 000 rail tiles", and enough net for a hundred yards to reach.
const RAIL_OFFSET := 16
const RAIL_PITCH := 64
const RAIL_LINES_PER_AXIS := 4
const RAIL_FIRST := 8
const RAIL_LAST := 248
const STATIONS_PER_LINE := 25
const STATIONS_TOTAL := 100
const INDUSTRIES_TOTAL := 100
const TRAINS_TOTAL := 100
const BUILDING_TOTAL := 5000
const BUILDING_STEP_X := 2
const BUILDING_STEP_Y := 3
## A synthetic company needs the capital its world is about to spend: 100 yards,
## 100 consists and 1 928 tiles of track cost about 7.5 M, and a stress run that
## runs out of money measures refusals instead of movement.  The grant goes
## through `EconomyService`, so it is a ledger row like every other dollar.
const CAPITAL_GRANT := 12000000.0
## `MapFeatures` takes a cell when `hash(seed, block, salt) < density * 10000`,
## with one candidate per `spacing`² block.  Ground that is already spoken for —
## rail, yards, works, cleared country around each town — cannot carry a tree,
## so the density is tuned to what the lattice can actually fill: 16.4 % of
## 65 536 cells lands the specification's 10 000 vegetation instances.
const VEGETATION_DENSITY := 0.164
const VEGETATION_SEED := 4242

var _ticks := 2000
var _verify_seed := true
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_ticks = _read_ticks(args)
	_verify_seed = not args.has("--no-seed-check")

	var built := _build_world()
	if built == null:
		quit(1)
		return
	var session := built as GameSession

	# A stress run is a pure compute run: no autosave file writes mid-measurement.
	session.data.timing["autosave_every_months"] = 0
	var counts := _count_world(session)
	var checksum := _checksum(session)

	if _verify_seed:
		var twin := _build_world() as GameSession
		if twin == null:
			_failures.append("the world could not be built a second time")
		else:
			var twin_checksum := _checksum(twin)
			if twin_checksum != checksum:
				_failures.append("the same seed placed a different world (%d then %d)" % [
					checksum, twin_checksum])
			counts["second"] = _count_world(twin)
			twin.free()

	if not _failures.is_empty():
		for reason in _failures:
			print("stress: FAIL — " + reason)
		session.free()
		quit(1)
		return

	var sim_start_us := Time.get_ticks_usec()
	session.advance_ticks(_ticks)
	var sim_ms := float(Time.get_ticks_usec() - sim_start_us) / 1000.0

	var statuses := _status_histogram(session)
	print(_report(session, counts, checksum, statuses, sim_ms))

	var ok := session.clock.tick_count == _ticks
	if not ok:
		print("stress: FAIL — tick budget incomplete: %d of %d" % [
			session.clock.tick_count, _ticks])
	if not session.economy.is_consistent():
		ok = false
		print("stress: FAIL — money does not reconcile (opening + Σ ledger != cash)")
	if int(statuses["unnamed"]) > 0:
		ok = false
		print("stress: FAIL — %d trains reported no status" % int(statuses["unnamed"]))
	if int(counts["stations"]) != STATIONS_TOTAL or int(counts["industries"]) != INDUSTRIES_TOTAL \
			or int(counts["trains"]) != TRAINS_TOTAL:
		ok = false
		print("stress: FAIL — the world is not the population the budget names")
	print("stress: %s" % ("OK" if ok else "FAIL"))
	session.free()
	quit(0 if ok else 1)


# --- the world ------------------------------------------------------------

## One fully populated valley, or null.  Every step is the shipped one: rail
## through `RailService`, yards through `StationService`, industries through
## `IndustryService`, vegetation through `MapFeatures`.
func _build_world() -> GameSession:
	var session := GameSession.new()
	if not session.start_blank(MAP_SIZE, MAP_SIZE):
		print("stress: FAIL — blank boot failed: " + session.last_error)
		session.free()
		return null
	session.economy.earn(CAPITAL_GRANT, EconomyService.CATEGORY_REVENUE,
			"synthetic capital for the stress world")
	_build_rail_grid(session)
	_build_stations(session)
	_build_towns(session)
	_build_industries(session)
	_build_vegetation(session)
	_build_buildings(session)
	_build_trains(session)
	if not _failures.is_empty():
		for reason in _failures:
			print("stress: FAIL — " + reason)
		session.free()
		return null
	return session


## Horizontal lines first, then vertical: 8 lines of single track, built once.
func _build_rail_grid(session: GameSession) -> void:
	for axis in 2:
		for line in RAIL_LINES_PER_AXIS:
			var at := RAIL_OFFSET + line * RAIL_PITCH + RAIL_FIRST
			var run: Array[Vector2i] = []
			for step in RAIL_LAST - RAIL_FIRST + 1:
				run.append(Vector2i(RAIL_FIRST + step, at) if axis == 0
						else Vector2i(at, RAIL_FIRST + step))
			var laid := session.rail.build_segment(run)
			if not bool(laid["ok"]):
				_failures.append("rail line at %d refused: %s" % [at, laid["reason"]])
				return


## A hundred yards standing between the lines, each finding its own approach
## exactly as the build tool's ghost would.
##
## The yard is set one row off the line, so its front row touches the rail: a
## small station asks for a straight run one cell out (`rail_search_radius`), and
## a yard drawn any further away is a yard the ghost would have refused.
func _build_stations(session: GameSession) -> void:
	var made := 0
	for line in RAIL_LINES_PER_AXIS:
		if made >= STATIONS_TOTAL:
			return
		var rail_row := RAIL_OFFSET + line * RAIL_PITCH + RAIL_FIRST
		for index in STATIONS_PER_LINE:
			if made >= STATIONS_TOTAL:
				return
			var anchor := Vector2i(12 + index * 9, rail_row - 2)
			var reason := session.stations.placement_reason("small_station", anchor)
			if reason != "":
				_failures.append("station at %s refused: %s" % [anchor, reason])
				return
			var built := session.stations.build("small_station", anchor,
					"Stress Yard %d" % made)
			if not bool(built["ok"]):
				_failures.append("station build refused: " + String(built["reason"]))
				return
			made += 1


## Every yard gets a town in its catchment, so months move units and the ledger
## grows: a valley where nothing is carried measures nothing.
func _build_towns(session: GameSession) -> void:
	var entries: Array = []
	var index := 0
	for station_id in session.stations.stations():
		var yard: Vector2i = session.stations.tile_of(station_id)
		entries.append({
			"id": session.ids.next_id(),
			"name": "Stress Town %d" % index,
			"population": 1200,
			"x": yard.x,
			"y": yard.y + 2,
			# Rates sized so the trains can clear a month's cargo — a
			# storage-full valley measures refusal paths, not throughput.
			"passengers_per_month": 40.0,
			"mail_per_month": 24.0,
		})
		index += 1
	session.towns.from_dict({"towns": entries})
	session.cargo.allocate_sources()


## A hundred works sitting beside the vertical lines, half mines and half
## plants: the world model has to carry both producers and consumers, and the
## occupancy grid has to hold a hundred industry footprints.
func _build_industries(session: GameSession) -> void:
	var made := 0
	for line in RAIL_LINES_PER_AXIS:
		if made >= INDUSTRIES_TOTAL:
			return
		var rail_column := RAIL_OFFSET + line * RAIL_PITCH + RAIL_FIRST
		for index in 25:
			if made >= INDUSTRIES_TOTAL:
				return
			var tile := Vector2i(rail_column - 4, 20 + index * 9)
			var definition := "coal_mine" if made % 2 == 0 else "power_plant"
			var id := session.industries.add(definition, tile,
					"Stress Works %d" % made, session.ids.next_id())
			if id == 0:
				_failures.append("industry %s at %s was not placed" % [definition, tile])
				return
			session.world.set_occupancy(tile, WorldGrid.Occupancy.INDUSTRY, id)
			made += 1


## 5 000 house lots on a fixed lattice across the map's free ground.  They are
## occupancy records, not nodes — that distinction is the spec §112 promise this
## run exists to pay for: 5 000 more entities and zero extra scene nodes.
func _build_buildings(session: GameSession) -> void:
	var placed := 0
	for y in range(0, MAP_SIZE, BUILDING_STEP_Y):
		for x in range(0, MAP_SIZE, BUILDING_STEP_X):
			if placed >= BUILDING_TOTAL:
				return
			var tile := Vector2i(x, y)
			if not session.world.in_bounds(tile):
				continue
			if session.world.occupancy_at(tile) != WorldGrid.Occupancy.NONE:
				continue
			session.world.set_occupancy(tile, WorldGrid.Occupancy.BUILDING,
					session.ids.next_id())
			placed += 1
	if placed < BUILDING_TOTAL:
		_failures.append("only %d of %d house lots had free ground to stand on" % [
			placed, BUILDING_TOTAL])


## Ten thousand trees, planted by the same decoder that plants the shipped
## valley — the stress world earns its vegetation through the real code path, so
## a regression in the scatter rule shows up here too.
func _build_vegetation(session: GameSession) -> void:
	var anchors: Array[Vector2i] = []
	for town_id in session.towns.towns():
		anchors.append(session.towns.tile_of(town_id))
	var features := MapFeatures.from_dictionary({
		"seed": VEGETATION_SEED,
		"settlement_clear_radius": 3,
		"scatter": [{
			"terrain": "grass", "scenery": "tree",
			"density": VEGETATION_DENSITY, "spacing": 1,
		}],
	}, "stress world")
	for problem in features.errors:
		_failures.append("the vegetation rule was refused: " + String(problem))
	if not features.errors.is_empty():
		return
	features.place_onto(session.world, anchors)


## A hundred consists on a hundred circular routes, three yards each.  Every
## train in the valley has a plan, so every tick has movement, dwell scheduling
## and delivery work to do.
func _build_trains(session: GameSession) -> void:
	var yards: Array[int] = session.stations.stations()
	if yards.size() < 3:
		_failures.append("only %d yards were placed; a route needs three" % yards.size())
		return
	for index in TRAINS_TOTAL:
		var home := yards[index % yards.size()]
		var bought := session.trains.purchase(home, "steam_440",
				["passenger_coach", "mail_car"])
		if not bool(bought["ok"]):
			_failures.append("train purchase refused: " + String(bought["reason"]))
			return
		var stops: Array[Dictionary] = []
		for offset in 3:
			stops.append({
				"station_id": yards[(index + offset) % yards.size()],
				"load": ["passengers", "mail"],
				"unload": ["passengers", "mail"],
			})
		var routed := session.trains.set_route(int(bought["id"]), stops)
		if not bool(routed["ok"]):
			_failures.append("route refused: " + String(routed["reason"]))
			return


# --- the report -----------------------------------------------------------

func _report(session: GameSession, counts: Dictionary, checksum: int,
		statuses: Dictionary, sim_ms: float) -> String:
	var ran := session.clock.tick_count
	var tps := float(_ticks) / (sim_ms / 1000.0) if sim_ms > 0.0 else 0.0
	var tick_micros := session.clock.tick_time_average_micros()
	# The budget is stated per second of game time: at 1x the clock asks for 20
	# ticks a second, so the honest number is 20 x one tick, not one tick.
	var tick_time_per_second := tick_micros * SimulationClock.TICK_RATE
	var memory_mb := float(OS.get_static_memory_usage()) / 1048576.0
	var lines: Array[String] = []
	lines.append("stress world — founder's synthetic valley")
	lines.append("  ticks            %d (requested %d)" % [ran, _ticks])
	lines.append("  sim time         %.1f ms  (%.0f ticks/s)" % [sim_ms, tps])
	lines.append(("  avg tick         %.1f us   = %.1f ms of tick time per second of game"
			+ " time at 1x   (budget 50 ms: %.0f%% used)")
			% [tick_micros, tick_time_per_second / 1000.0, tick_time_per_second / 50000.0 * 100.0])
	lines.append("  world seed       %d   checksum %d   (built twice, identical)" % [
		VEGETATION_SEED, checksum])
	lines.append("  rail cells       %d   (budget ≈ 2 000)" % counts["rail"])
	lines.append("  stations         %d   towns %d   industries %d   trains %d" % [
		counts["stations"], counts["towns"], counts["industries"], counts["trains"]])
	lines.append("  buildings        %d   (budget ≈ 5 000)   vegetation %d   (budget ≈ 10 000)" % [
		counts["buildings"], counts["scenery"]])
	lines.append("  route paths      %d   path finds %d (%d us total)" % [
		counts["routes"], session.rail.path_find_calls(), session.rail.path_find_micros_total()])
	lines.append("  delivered units  %.0f   cargo revenue %.0f" % [
		session.cargo.delivered_total(), session.cargo.revenue_total()])
	lines.append("  cash             %.2f   ledger rows %d" % [
		session.economy.cash, session.economy.ledger().size()])
	lines.append("  train status     %s" % _status_text(statuses))
	var pending_chunks := session.world.take_dirty_chunks().size()
	lines.append("  terrain rebuilds %d   chunks left dirty after the run %d (headless: nothing meshes)" % [
		session.world.geometry_rebuild_count(), pending_chunks])
	lines.append("  process memory   %.0f MB   (RAM budget 700 MB)" % memory_mb)
	return "\n".join(lines)


func _status_histogram(session: GameSession) -> Dictionary:
	var out := {"unnamed": 0}
	for train_id in session.trains.trains():
		var label := session.trains.state_label(train_id)
		if label == "" or label == "??":
			out["unnamed"] = int(out["unnamed"]) + 1
		else:
			out[label] = int(out.get(label, 0)) + 1
	return out


func _status_text(statuses: Dictionary) -> String:
	var parts: Array[String] = []
	for key in statuses.keys():
		if String(key) == "unnamed":
			continue
		parts.append("%s %d" % [key, int(statuses[key])])
	parts.sort()
	return ", ".join(parts) if not parts.is_empty() else "none"


## What the world actually holds, counted from the domain rather than remembered
## from the construction loop — a stress report that trusts its own setup cannot
## show a setup that quietly placed half of it.
func _count_world(session: GameSession) -> Dictionary:
	var buildings := 0
	var vegetation := 0
	for index in session.world.occupancy_kind.size():
		match int(session.world.occupancy_kind[index]):
			WorldGrid.Occupancy.BUILDING:
				buildings += 1
			WorldGrid.Occupancy.SCENERY:
				vegetation += 1
	return {
		"rail": session.rail.rail_tiles().size(),
		"stations": session.stations.count(),
		"towns": session.towns.count(),
		"industries": session.industries.count(),
		"trains": session.trains.count(),
		"routes": session.routes.count(),
		"buildings": buildings,
		"scenery": vegetation,
	}


## A 63-bit rolling hash over everything that identifies a placement: the grid's
## own arrays and every entity id in creation order.  Two runs with the same seed
## must agree on all of it, and nothing about timing may enter here.
func _checksum(session: GameSession) -> int:
	var h := 1469598103934665603
	h = _mix(h, session.world.width)
	h = _mix(h, session.world.height)
	for index in session.world.occupancy_kind.size():
		h = _mix(h, int(session.world.occupancy_kind[index]))
		h = _mix(h, int(session.world.rail_present[index]))
		if (index & 4095) == 0:
			h = _mix(h, int(session.world.occupancy_id[index]))
	for station_id in session.stations.stations():
		h = _mix(h, station_id)
		h = _mix(h, session.stations.tile_of(station_id).x * 1024
				+ session.stations.tile_of(station_id).y)
	for town_id in session.towns.towns():
		h = _mix(h, town_id)
	for industry_id in session.industries.industries():
		h = _mix(h, industry_id)
	for train_id in session.trains.trains():
		h = _mix(h, train_id)
		h = _mix(h, session.trains.route_of(train_id))
	return h & 0x7FFFFFFFFFFFFFFF


func _mix(hash_value: int, value: int) -> int:
	return (hash_value * 1099511628211) ^ value


func _read_ticks(args: PackedStringArray) -> int:
	for arg in args:
		if String(arg).begins_with("--ticks="):
			return maxi(1, int(String(arg).trim_prefix("--ticks=")))
	return _ticks
