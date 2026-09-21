extends SceneTree

## Synthetic stress world for `python tools/rr.py stress --ticks N`.
##
## Boots a blank WorldGrid through the real composition root (`start_blank`),
## generates a rail grid of hundreds of route-km, twelve stations, twelve
## passenger/mail trains and a dozen cargo-generating towns — then advances the
## requested tick budget and reports.  Nothing about the shipped valley is
## loaded; this measures the simulation, not the content.
##
## Exit code is the CLI's: 0 only when the full tick budget ran and money
## reconciled.  `quit()` is explicit — a bare SceneTree script otherwise hangs.
## Wall-clock (`Time.get_ticks_*`) appears in this file for reporting only;
## simulation advance is whole integer ticks, as everywhere else.

const MAP_SIZE := 160
const LINES := 20          ## rail lines per axis, every 8 tiles → ~5.7k cells
const LINE_SPAN := 152     ## tiles 4..156 inclusive per line
const STATION_ROWS: Array[int] = [2, 7, 12, 17]
const STATION_COLS: Array[int] = [0, 1, 2]

var _ticks := 2000
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_ticks = _read_ticks(OS.get_cmdline_user_args())
	var started_us := Time.get_ticks_usec()
	var session := GameSession.new()
	if not session.start_blank(MAP_SIZE, MAP_SIZE):
		print("stress: FAIL — blank boot failed: " + session.last_error)
		quit(1)
		return
	# Stress is a pure compute run: no autosave file writes mid-measurement.
	session.data.timing["autosave_every_months"] = 0

	_build_rail_grid(session)
	_build_stations(session)
	_build_towns(session)
	_build_trains(session)
	if not _failures.is_empty():
		for reason in _failures:
			print("stress: FAIL — " + reason)
		session.free()
		quit(1)
		return

	var sim_start_us := Time.get_ticks_usec()
	session.advance_ticks(_ticks)
	var sim_ms := float(Time.get_ticks_usec() - sim_start_us) / 1000.0
	var total_ms := float(Time.get_ticks_usec() - started_us) / 1000.0

	var ran := session.clock.tick_count
	var tps := float(_ticks) / (sim_ms / 1000.0) if sim_ms > 0.0 else 0.0
	var rail_cells := session.rail.rail_tiles().size()
	var reconciled := session.economy.is_consistent()

	print("stress world — founder's synthetic valley")
	print("  ticks            %d (requested %d)" % [ran, _ticks])
	print("  sim time         %.1f ms  (%.0f ticks/s)" % [sim_ms, tps])
	print("  setup time       %.1f ms" % (total_ms - sim_ms))
	print("  rail cells       %d" % rail_cells)
	print("  stations         %d   towns %d   trains %d   routes %d" % [
		session.stations.count(), session.towns.count(),
		session.trains.count(), session.routes.count()])
	print("  delivered units  %.0f" % session.cargo.delivered_total())
	print("  cargo revenue    %.0f" % session.cargo.revenue_total())
	print("  cash             %.2f   ledger rows %d" % [
		session.economy.cash, session.economy.ledger().size()])
	print("  terrain rebuilds %d   dirty-chunk flushes n/a (headless)" % session.world.geometry_rebuild_count())
	print("  path finds       %d (%d us total)   avg tick %.1f us" % [
		session.rail.path_find_calls(), session.rail.path_find_micros_total(),
		session.clock.tick_time_average_micros()])

	var ok := ran == _ticks
	if not ok:
		print("stress: FAIL — tick budget incomplete: %d of %d" % [ran, _ticks])
	if not reconciled:
		ok = false
		print("stress: FAIL — money does not reconcile (opening + Σ ledger != cash)")
	print("stress: %s" % ("OK" if ok else "FAIL"))
	session.free()
	quit(0 if ok else 1)


func _read_ticks(args: PackedStringArray) -> int:
	for arg in args:
		if String(arg).begins_with("--ticks="):
			return maxi(1, int(String(arg).trim_prefix("--ticks=")))
	return _ticks


# --- world construction -------------------------------------------------------

## A grid of collinear through-lines: 20 rows × 152 tiles + 20 columns, minus
## the crossings — about 5.7 km of single track at map scale, built once.
func _build_rail_grid(session: GameSession) -> void:
	for line in LINES:
		var at := 4 + line * 8
		var row: Array[Vector2i] = []
		for step in LINE_SPAN:
			row.append(Vector2i(4 + step, at))
		var horizontal := session.rail.build_segment(row)
		if not bool(horizontal["ok"]):
			_failures.append("rail row at %d refused: %s" % [at, horizontal["reason"]])
			return
		var column: Array[Vector2i] = []
		for step in LINE_SPAN:
			column.append(Vector2i(at, 4 + step))
		var vertical := session.rail.build_segment(column)
		if not bool(vertical["ok"]):
			_failures.append("rail column at %d refused: %s" % [at, vertical["reason"]])
			return


## Twelve stations sitting between the lines; each finds a straight approach
## exactly as the build tool's ghost would.
func _build_stations(session: GameSession) -> void:
	for row_index in STATION_ROWS.size():
		for column_index in STATION_COLS.size():
			var anchor := Vector2i(13 + STATION_COLS[column_index] * 48, 4 + STATION_ROWS[row_index] * 8 + 2)
			var reason := session.stations.placement_reason("small_station", anchor)
			if reason != "":
				_failures.append("station at %s refused: %s" % [anchor, reason])
				return
			var built := session.stations.build("small_station", anchor,
					"Yard %d-%d" % [row_index, column_index])
			if not bool(built["ok"]):
				_failures.append("station build refused: " + String(built["reason"]))
				return


## Towns are the cargo: every station yard gets one pax/mail generator in its
## catchment, so months actually move units and the ledger actually grows.
func _build_towns(session: GameSession) -> void:
	var entries: Array = []
	var index := 0
	for row_index in STATION_ROWS.size():
		for column_index in STATION_COLS.size():
			var centre := Vector2i(14 + STATION_COLS[column_index] * 48, 4 + STATION_ROWS[row_index] * 8 + 3)
			entries.append({
				"id": session.ids.next_id(),
				"name": "Stress Town %d" % index,
				"population": 1200,
				"x": centre.x,
				"y": centre.y + 2,
				# Rates sized so the row's trains can clear a month's cargo —
				# a storage-full valley measures refusal paths, not throughput.
				"passengers_per_month": 50.0,
				"mail_per_month": 30.0,
			})
			index += 1
	session.towns.from_dict({"towns": entries})
	session.cargo.allocate_sources()


## Three trains per row of yards, full load/unload plans, so every tick has
## movement, dwell scheduling and occasional delivery work to do.
func _build_trains(session: GameSession) -> void:
	for row_index in STATION_ROWS.size():
		# stations() is append-ordered: the twelve yards were built row-major.
		var row_stations: Array[int] = []
		for column_index in STATION_COLS.size():
			row_stations.append(session.stations.stations()[row_index * STATION_COLS.size() + column_index])
		for train_index in 3:
			var home := row_stations[train_index]
			var bought := session.trains.purchase(home, "steam_440",
					["passenger_coach", "passenger_coach", "mail_car"])
			if not bool(bought["ok"]):
				_failures.append("train purchase refused: " + String(bought["reason"]))
				return
			var stops: Array[Dictionary] = []
			for station_id in row_stations:
				stops.append({
					"station_id": station_id,
					"load": ["passengers", "mail"],
					"unload": ["passengers", "mail"],
				})
			var routed := session.trains.set_route(int(bought["id"]), stops)
			if not bool(routed["ok"]):
				_failures.append("route refused: " + String(routed["reason"]))
				return
