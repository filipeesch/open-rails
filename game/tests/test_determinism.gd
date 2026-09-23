extends TestBase

## Invariant 5: fixed 20 Hz integer ticks, no wall-clock and no unseeded
## randomness in the simulation — identical starting state plus identical ticks
## must give an identical result.  A save game, a replay and a multiplayer
## prototype all rest on this, so it is checked against the shipped map.

var session: GameSession


func setup() -> void:
	session = TestSession.create()


func teardown() -> void:
	TestSession.dispose(session)
	session = null


## A compact, human-diffable digest of everything the simulation has decided.
func fingerprint(s: GameSession) -> String:
	var parts: PackedStringArray = []
	parts.append("tick=%d" % s.clock.tick_count)
	parts.append("date=%s" % s.clock.date.display())
	parts.append("cash=%.2f" % s.economy.cash)
	parts.append("ledger=%d:%.2f" % [s.economy.unreversed_ledger().size(), _ledger_sum(s)])
	parts.append("rail=%s/%d" % [_rail_digest(s), s.rail.rail_tiles().size()])
	parts.append("stations=%d" % s.stations.count())
	for station_id in s.stations.stations():
		parts.append("st%d=%s" % [station_id, JSON.stringify(s.cargo.available_summary(station_id))])
	parts.append("trains=%d" % s.trains.count())
	for train_id in s.trains.trains():
		var loads: Array[String] = []
		for cargo_id in s.trains.capacity_by_cargo(train_id):
			loads.append("%s %.2f/%.0f" % [cargo_id, s.trains.loaded_for(train_id, cargo_id),
					s.trains.capacity_for(train_id, cargo_id)])
		loads.sort()
		parts.append("tr%d=%s|%.4f|%s|%s" % [
			train_id, s.trains.state_label(train_id), s.trains.progress_fraction(train_id),
			",".join(loads), JSON.stringify(s.trains.batches(train_id))])
	parts.append("cargo=%.3f/%.2f/%d" % [
		s.cargo.delivered_total(), s.cargo.revenue_total(), s.cargo.delivery_count()])
	for industry_id in s.industries.industries():
		parts.append("in%d=%s" % [industry_id, JSON.stringify(s.industries.industry(industry_id).get("inventory", {}))])
	return "\n".join(parts)


## Order-independent digest of the track graph: what a train can actually drive
## on, not the cache epoch the service happens to be on.
func _rail_digest(s: GameSession) -> String:
	var cells: Array[String] = []
	for tile in s.rail.rail_tiles():
		cells.append("%d:%d=%d" % [tile.x, tile.y, s.rail.network.mask(tile)])
	cells.sort()
	return str(JSON.stringify(cells).hash())


func _ledger_sum(s: GameSession) -> float:
	var total := 0.0
	for transaction in s.economy.unreversed_ledger():
		total += transaction.amount
	return total


func _describe_difference(left: String, right: String) -> String:
	var limit := mini(left.length(), right.length())
	for index in limit:
		if left[index] != right[index]:
			var from := maxi(0, index - 60)
			return "first difference at %d: |  A: %s|  B: %s" % [
				index, left.substr(from, 140).replace("\n", " | "),
				right.substr(from, 140).replace("\n", " | ")]
	if left.length() != right.length():
		return "one run is longer: %d against %d |  tail A: %s|  tail B: %s" % [
			left.length(), right.length(),
			left.substr(limit, 140).replace("\n", " | "),
			right.substr(limit, 140).replace("\n", " | ")]
	return ""


# --- determinism ------------------------------------------------------------

func test_the_same_build_and_the_same_ticks_end_in_the_same_state() -> void:
	var other := TestSession.create()
	var line := TestSession.coal_line(session)
	var other_line := TestSession.coal_line(other)
	check_true(bool(line["ok"]) and bool(other_line["ok"]), "both companies built the same line")

	session.clock.step_ticks(1370)
	other.clock.step_ticks(1370)

	var mine := fingerprint(session)
	var theirs := fingerprint(other)
	check_eq(mine, theirs, "the same ticks on the same build give the same world\n" + _describe_difference(mine, theirs))

	TestSession.dispose(other)


func test_a_restored_snapshot_continues_exactly_where_it_left_off() -> void:
	var line := TestSession.coal_line(session)
	check_true(bool(line["ok"]), "a line is running: " + String(line["reason"]))
	session.clock.step_ticks(800)

	var saved := session.snapshot()
	session.clock.step_ticks(600)
	var continued := fingerprint(session)

	var reloaded := TestSession.create()
	check_true(bool(reloaded.restore(saved)), "the snapshot restores cleanly")
	reloaded.clock.step_ticks(600)
	var replayed := fingerprint(reloaded)
	check_eq(continued, replayed,
			"six hundred ticks from a restored state match six hundred ticks run straight on\n" \
					+ _describe_difference(continued, replayed))

	TestSession.dispose(reloaded)


func test_the_clock_moves_in_fixed_ticks_and_a_paused_clock_moves_nothing() -> void:
	var line := TestSession.coal_line(session)
	check_true(bool(line["ok"]), "a line is running: " + String(line["reason"]))
	session.clock.step_ticks(200)
	var frozen := fingerprint(session)

	session.set_paused(true)
	for frame in 120:
		session.advance(0.05)
	check_true(session.is_paused(), "the game is paused")
	check_eq(fingerprint(session), frozen, "two seconds of wall clock changed nothing while paused")

	session.set_paused(false)
	session.clock.set_speed_index(1)
	var ticks_before := session.clock.tick_count
	session.advance(1.0)
	check_neq(fingerprint(session), frozen, "the same second unpaused moved the simulation on")
	var stepped := session.clock.tick_count - ticks_before
	check_gt(stepped, 0, "a real second of wall clock buys real ticks")
	check_le(float(stepped), 8.0, "but never more than the fixed cap per frame, whatever the delta was")
	var expected_at_one := int(SimulationClock.TICK_RATE * session.clock.speed())
	check_eq(float(expected_at_one), 20.0, "1× means twenty ticks a second")


func test_the_planner_answers_the_same_whether_cold_or_cached() -> void:
	var line := TestSession.coal_line(session)
	check_true(bool(line["ok"]), "a line is running: " + String(line["reason"]))
	var from_tile := session.stations.rail_access_tile(int(line["mine_station"]))
	var to_tile := session.stations.rail_access_tile(int(line["plant_station"]))

	var cold := session.rail.find_path(from_tile, to_tile)
	var warm := session.rail.find_path(from_tile, to_tile)
	check_eq(JSON.stringify(warm), JSON.stringify(cold), "the cached answer is the same path")
	var calls_before := session.planner.search_calls()
	session.planner.plan(from_tile, to_tile)
	session.planner.plan(from_tile, to_tile)
	check_eq(session.planner.search_calls(), calls_before + 1,
			"the second plan is served from cache, so the cache cannot drift within a revision")

	var planned := session.planner.plan(from_tile, to_tile)
	check_true(bool(planned["ok"]), "the plan is offered")
	var planned_tiles: Array[Vector2i] = planned["tiles"]
	check_eq(JSON.stringify(planned_tiles), JSON.stringify(cold),
			"and it walks the same route the graph search finds")


func test_the_simulation_contains_no_unseeded_randomness() -> void:
	## Determinism is a property of the code, not only of one run: any `randf()`
	## or unseeded generator in the domain would break saves and replays.
	var offenders: PackedStringArray = []
	for path in _gd_files("res://src/domain"):
		var text := _read_text(path)
		for needle in ["randf(", "randi(", "randf_range(", "randi_range(", "randomize()", "RandomNumberGenerator"]:
			if text.contains(needle):
				offenders.append("%s uses %s" % [path, needle])
	check_eq(offenders.size(), 0, "no domain file rolls dice:\n" + "\n".join(offenders))
	check_gt(float(_gd_files("res://src/domain").size()), 20.0, "and the scan really looked at the domain")


func test_presentation_code_is_not_reachable_from_the_domain() -> void:
	## Invariant 2 again, this time by looking at what the domain references.
	var offenders: PackedStringArray = []
	for path in _gd_files("res://src/domain"):
		var text := _read_text(path)
		for needle in ["res://src/ui/", "res://src/presentation/", "CanvasItem", "Node3D", "Label", "Control"]:
			if text.contains(needle):
				offenders.append("%s mentions %s" % [path, needle])
	check_eq(offenders.size(), 0, "the domain never names a widget:\n" + "\n".join(offenders))


func _gd_files(root: String) -> Array[String]:
	var found: Array[String] = []
	var queue: Array[String] = [root]
	while not queue.is_empty():
		var path: String = queue.pop_front()
		var dir := DirAccess.open(path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			var child: String = path.path_join(name)
			if dir.current_is_dir():
				if name != ".godot":
					queue.append(child)
			elif name.ends_with(".gd") and not name.ends_with(".gd.uid"):
				found.append(child)
			name = dir.get_next()
		dir.list_dir_end()
	found.sort()
	return found


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func test_the_calendar_crosses_the_year_once_a_month() -> void:
	var clock := session.clock
	check_eq(clock.date.year, 1850, "the valley opens in 1850")
	check_eq(clock.date.month, 1, "in January")
	check_eq(clock.date.day, 1, "on the first of it")
	watch_months(clock)
	for expected_month in range(2, 13):
		check_true(run_months(clock, 1), "month %d of 1850 rolls over" % expected_month)
		check_eq(clock.date.month, expected_month, "the calendar is in the month it earned")
		check_eq(clock.date.year, 1850, "and still in 1850 until December runs out")
		check_eq(clock.date.day, 1, "a month always opens on the first")
		check_eq(months_observed, expected_month - 1, "exactly one month event per month")
	check_true(run_months(clock, 1), "December 1850 finally runs out")
	check_eq(clock.date.year, 1851, "December 1850 hands over to 1851")
	check_eq(clock.date.month, 1, "and the month counter starts again at January")
	check_eq(clock.date.day, 1, "on the first of it")
	check_eq(months_observed, 12, "the New Year fired one month event, like every other month")


func test_the_timing_data_sets_the_pace_and_nothing_else() -> void:
	var clock := session.clock
	var shipped := clock.ticks_per_day
	var configured := int(session.data.timing.get("ticks_per_day", 0.0))
	check_eq(shipped, configured, "the clock runs at the pace the data file gives it")
	check_eq(shipped, 60,
		"and the shipped pace puts a month at ninety seconds of play at 1x, which is a "
		+ "little over one loaded leg across the shipped valley")
	watch_months(clock)
	check_true(run_months(clock, 1), "a month passes at the shipped pace")
	var month_ticks := clock.tick_count
	check_eq(month_ticks % shipped, 0, "a month ends exactly on a day boundary, never mid-day")
	var days_in_month := month_ticks / shipped
	check_ge(float(days_in_month), 28.0, "and a month is a whole month of days, at least 28")
	check_le(float(days_in_month), 31.0, "no more than 31")

	clock.configure(shipped / 2, clock.speed_index)
	check_eq(clock.ticks_per_day, shipped / 2, "halving the ratio leaves half the ticks in a day")
	var days_before := clock.days_elapsed()
	var ticks_before := clock.tick_count
	watch_months(clock)
	clock.step_ticks(month_ticks)
	check_eq(clock.tick_count - ticks_before, month_ticks,
			"the same number of ticks is still exactly that many ticks — none skipped, none invented")
	check_eq(clock.days_elapsed() - days_before, days_in_month * 2,
			"the very same ticks now buy twice the calendar, which is all the ratio ever claimed")
	check_eq(months_observed, 2, "which is what two months looks like from the calendar side")


func test_the_speed_dial_is_a_rate_and_not_a_different_game() -> void:
	## Paused, 1×, 2× and 4× must be the same simulation sampled at four rates: the
	## same stretch of wall clock buys a multiple of the ticks and nothing else
	## changes.  A 4× that quietly ran its own rules would silently fork every save.
	var line := TestSession.coal_line(session)
	check_true(bool(line["ok"]), "a line is running: " + String(line["reason"]))
	var speeds: Array = session.data.timing.get("speeds", [0.0, 1.0, 2.0, 4.0])
	check_eq(speeds.size(), 4, "the dial has four positions, and they come from the data file")

	var gained: Array[int] = []
	for index in speeds.size():
		session.clock.set_speed_index(index)
		check_near(session.clock.speed(), float(speeds[index]),
				"dial position %d means %s×" % [index, speeds[index]], 0.001)
		var before: int = session.clock.tick_count
		for frame in 120:
			session.advance(1.0 / 60.0)
		gained.append(session.clock.tick_count - before)

	check_eq(float(gained[0]), 0.0, "paused buys no ticks from two seconds of wall clock")
	check_near(float(gained[1]), float(SimulationClock.TICK_RATE) * 2.0,
			"1× is twenty ticks a second, so two seconds is forty", 1.0)
	check_near(float(gained[2]), float(gained[1]) * 2.0, "2× buys exactly double that", 1.0)
	check_near(float(gained[3]), float(gained[1]) * 4.0, "4× buys exactly four times", 1.0)
	check_true(session.routes.is_valid(session.trains.route_of(int(line["train"]))),
			"and the timetable survived running at four times the pace")
	check_true(session.economy.is_consistent(), "the ledger still reconciles after the fast run")
