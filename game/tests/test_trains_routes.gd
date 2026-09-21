extends TestBase

## Consists, routes and the movement loop.
##
## Everything here runs on the shipped map through the same calls the tool panel
## makes — no hand-made train dictionaries — so a green case means a player could
## actually do it.

var session: GameSession
var _line: Dictionary = {}
var _line_built := false
var _working_region: Array[Vector2i] = []


func setup() -> void:
	session = TestSession.create()


func teardown() -> void:
	TestSession.dispose(session)
	session = null
	_line = {}
	_line_built = false


func line() -> Dictionary:
	if not _line_built:
		_line = TestSession.coal_line(session)
		_line_built = true
		watch_departures(session.trains)
	check_true(bool(_line["ok"]), "the coal line is buildable: " + String(_line["reason"]))
	return _line


func coal_train() -> int:
	return int(line()["train"])


# --- consist ---------------------------------------------------------------

func test_the_consist_carries_what_its_wagons_are_rated_for() -> void:
	var train := coal_train()
	var caps: Dictionary = session.trains.capacity_by_cargo(train)
	check_near(float(caps.get("coal", 0.0)), 90.0, "two 45-unit hoppers rate this train for 90 tons of coal")
	check_false(caps.has("mail"), "a consist with no mail car has no business offering mail")

	var added := session.trains.add_wagon(train, "mail_car")
	check_true(bool(added["ok"]), "a mail car can be bought and coupled on")
	caps = session.trains.capacity_by_cargo(train)
	check_near(float(caps.get("mail", 0.0)), 35.0, "the consist can carry mail from the moment it exists")

	check_true(session.trains.remove_wagon(train, 3), "and it can be sold off again")
	caps = session.trains.capacity_by_cargo(train)
	check_false(caps.has("mail"), "capacity follows the steel on the rails, not the wish")


func test_weight_slows_the_locomotive_down() -> void:
	var train := coal_train()
	var light_kmh := session.trains.estimated_max_speed(train)
	var light_tiles := session.trains.top_speed_tiles_per_tick(train)
	check_gt(light_kmh, 0.0, "an engine hauls something")
	check_gt(light_tiles, 0.0, "and that becomes a speed the movement code can use")

	for extra in 4:
		check_true(bool(session.trains.add_wagon(train, "coal_hopper")["ok"]), "couple on another hopper")

	var heavy_kmh := session.trains.estimated_max_speed(train)
	check_lt(heavy_kmh, light_kmh, "six wagons are slower than two")
	check_le(session.trains.top_speed_tiles_per_tick(train), light_tiles, "in every unit the sim uses")
	check_gt(heavy_kmh, 0.0, "a heavy train is slow, not parked")


func test_a_train_costs_its_price_and_a_refund_is_half() -> void:
	var station_id := int(line()["mine_station"])
	var before := session.economy.cash
	var bought := session.trains.purchase(station_id, "steam_440", ["coal_hopper", "coal_hopper"])
	check_true(bool(bought["ok"]), "the consist is on the market: " + String(bought["reason"]))
	check_near(float(bought["price"]), 35600.0, "26 000 for the engine, 4 800 a hopper")
	check_near(before - session.economy.cash, float(bought["price"]), "the ledger took exactly the consist price")
	check_true(session.economy.is_consistent(), "money still reconciles after the purchase")

	var extra := int(bought["id"])
	var before_sell := session.economy.cash
	check_true(session.trains.sell(extra), "the train can be sold again")
	check_near(session.economy.cash - before_sell, 17800.0, "a refund is half the price, rounded")
	check_eq(session.trains.count(), 1, "only the scheduled train is left on the roster")
	check_true(session.economy.is_consistent(), "and the ledger still adds up")


func test_only_real_stock_at_a_real_station_opens_a_train() -> void:
	var station_id := int(line()["mine_station"])
	var before := session.economy.cash
	var before_count := session.trains.count()

	var bad_loco := session.trains.purchase(station_id, "steam_442", ["coal_hopper"])
	check_has(String(bad_loco["reason"]).to_lower(), "locomotive", "an engine that does not exist is refused by name")
	var bad_wagon := session.trains.purchase(station_id, "steam_440", ["coal_hopper_iii"])
	check_has(String(bad_wagon["reason"]).to_lower(), "wagon", "so is a wagon that does not exist")
	var no_station := session.trains.purchase(987654, "steam_440", ["coal_hopper"])
	check_has(String(no_station["reason"]).to_lower(), "station", "and a train cannot start in a field")

	check_eq(session.trains.count(), before_count, "no phantom train came from a refused purchase")
	check_near(session.economy.cash, before, "a refused purchase took no money")


func test_the_player_keeps_their_consist_order() -> void:
	var station_id := int(line()["mine_station"])
	var bought := session.trains.purchase(station_id, "steam_440",
			["coal_hopper", "mail_car", "coal_hopper"])
	check_true(bool(bought["ok"]), "a mixed freight train can be bought")
	var train := int(bought["id"])

	var stock := session.trains.stock_of(train)
	check_eq(stock[0], "steam_440", "the engine rides at the head")
	check_eq(stock.size(), 4, "behind three wagons")
	check_eq(stock[2], "mail_car", "the mail car was coupled on in the middle")

	check_true(session.trains.move_wagon(train, 2, 3), "the mail car can be moved to the brake end")
	stock = session.trains.stock_of(train)
	check_eq(stock[3], "mail_car", "and it arrives in the slot the player pointed at")
	check_eq(stock[1], "coal_hopper", "the hoppers close up behind the engine")

	check_false(session.trains.move_wagon(train, 0, 3), "the engine cannot be shuffled to the rear")
	check_false(session.trains.remove_wagon(train, 0), "nor cut off and sold")


# --- routes ----------------------------------------------------------------

func test_a_route_needs_two_different_stations() -> void:
	var train := coal_train()
	var mine_station := int(line()["mine_station"])
	var plant_station := int(line()["plant_station"])
	var keep := session.trains.route_of(train)

	var empty := session.trains.set_route(train, [])
	check_has(String(empty["reason"]).to_lower(), "two stops", "an empty timetable is refused")

	var one_stop: Array[Dictionary] = [{"station_id": mine_station, "load": ["coal"], "unload": []}]
	var single := session.trains.set_route(train, one_stop)
	check_false(bool(single["ok"]), "a single stop is still not a route")

	var round_trip: Array[Dictionary] = [
		{"station_id": mine_station, "load": ["coal"], "unload": []},
		{"station_id": mine_station, "load": [], "unload": ["coal"]},
	]
	var twice := session.trains.set_route(train, round_trip)
	check_has(String(twice["reason"]).to_lower(), "once", "a station may not appear twice on the same route")

	var ghost: Array[Dictionary] = [
		{"station_id": mine_station, "load": ["coal"], "unload": []},
		{"station_id": 987654, "load": [], "unload": ["coal"]},
	]
	var unknown := session.trains.set_route(train, ghost)
	check_has(String(unknown["reason"]).to_lower(), "station", "and neither stop may be imaginary")

	check_eq(session.trains.route_of(train), keep, "every refusal left the working timetable in place")
	var good: Array[Dictionary] = [
		{"station_id": mine_station, "load": ["coal"], "unload": []},
		{"station_id": plant_station, "load": [], "unload": ["coal"]},
	]
	check_true(bool(session.trains.set_route(train, good)["ok"]), "the real route is accepted")


func test_a_route_needs_both_ends_on_the_same_line() -> void:
	var train := coal_train()
	var mine_station := int(line()["mine_station"])
	# The valley has a second colliery nowhere near the coal line — a real
	# destination on a real line the train has never been joined to.
	var other_mine := 0
	for industry_id in session.industries.industries():
		if session.industries.definition_of(industry_id) == "coal_mine" \
				and industry_id != int(line()["mine"]):
			other_mine = industry_id
	check_neq(other_mine, 0, "the valley has a second colliery")
	var isolated := TestSession.serve(session, session.industries.tile_of(other_mine), "Deephilgans Wharf")
	check_neq(isolated, 0, "a station can be built on its own branch")

	var stops: Array[Dictionary] = [
		{"station_id": mine_station, "load": ["coal"], "unload": []},
		{"station_id": isolated, "load": [], "unload": ["coal"]},
	]
	var refused := session.trains.set_route(train, stops)
	check_false(bool(refused["ok"]), "but no timetable runs across two unconnected lines")
	check_has(String(refused["reason"]).to_lower(), "reachable", "and the reason says the line is not connected")
	check_true(session.routes.is_valid(session.trains.route_of(train)),
			"a refused edit leaves the timetable the train is running on intact")
	check_eq(session.routes.stop_count(session.trains.route_of(train)), 2,
			"with its stops unchanged, not half-written")

	var route_id := session.trains.route_of(train)
	var reachable := session.routes.reachable_stations(route_id, 0)
	var report := "route %d reach %s, plant access %s, isolated access %s" % [
		route_id, reachable,
		session.stations.rail_access_tile(int(line()["plant_station"])),
		session.stations.rail_access_tile(isolated)]
	check_true(reachable.has(int(line()["plant_station"])),
			"the editor offers the stations a train can actually reach — " + report)
	check_false(reachable.has(isolated), "and not the one it cannot — " + report)


func test_a_route_measures_itself_in_the_units_the_train_moves_in() -> void:
	var route_id := int(line()["route"])
	var length := session.routes.length_tiles(route_id)
	check_gt(length, 0.0, "the timetable knows how long it is")
	check_true(session.routes.is_circular(route_id), "both ends are connected, so it is a round trip")

	var path: PackedVector2Array = session.routes.path_of(route_id)
	var measured := 0.0
	for step in range(1, path.size()):
		measured += path[step].distance_to(path[step - 1])
	check_near(length, measured, "the length is the path walked, in tile distances", 0.001)

	var ticks: PackedFloat64Array = session.routes.stop_ticks_of(route_id)
	check_eq(ticks.size(), session.routes.stop_count(route_id) + 1,
		"every stop has a marker and the way home has one too")
	check_near(float(ticks[ticks.size() - 1]), length, "the last marker closes the loop", 0.001)
	var previous := -1.0
	for tick in ticks:
		check_gt(float(tick), previous, "markers run strictly forwards along the path")
		previous = float(tick)


# --- movement --------------------------------------------------------------

func test_a_train_without_a_route_sits_where_it_was_built() -> void:
	var station_id := int(line()["mine_station"])
	var bought := session.trains.purchase(station_id, "steam_440", ["coal_hopper"])
	var train := int(bought["id"])
	check_eq(session.trains.state_label(train), "Idle", "a fresh train is idle at the platform")
	check_eq(session.trains.home_station(train), station_id, "at the station it was bought at")
	check_eq(session.trains.route_of(train), 0, "with no timetable")
	check_eq(session.trains.destination_label(train), "No route", "and nowhere to go")

	var start := session.trains.position_tiles(train)
	session.clock.step_ticks(200)
	check_eq(session.trains.state_label(train), "Idle", "twenty seconds of sim and it has not moved")
	check_eq(session.trains.position_tiles(train), start, "its position is the platform")


func test_a_timetabled_train_leaves_the_platform_and_runs() -> void:
	var train := coal_train()
	check_eq(session.trains.state_label(train), "Idle", "it starts idle until the clock turns over")

	session.clock.step_ticks(1)
	check_eq(session.trains.state_label(train), "Loading", "the first tick puts it to work at stop 0")
	var mine_station := int(line()["mine_station"])
	check_eq(session.trains.current_station(train), mine_station, "at the mine platform")
	check_eq(session.trains.destination_label(train), session.stations.name_of(int(line()["plant_station"])),
		"with the works marked as its destination")

	var seen_states := {}
	var moved_from := session.trains.position_tiles(train)
	for tick in 900:
		session.clock.step_ticks(1)
		seen_states[session.trains.state_label(train)] = true
		if session.trains.state_label(train) == "Moving":
			break
	check_true(bool(seen_states.has("Moving")), "it departs within the first minute of sim")
	# A departure tick only opens the throttle; give it a moment of acceleration
	# before asking whether the wheels are actually turning.
	session.clock.step_ticks(30)
	var moved_to := session.trains.position_tiles(train)
	check_gt(moved_to.distance_to(moved_from), 0.0, "and it is down the line")
	check_gt(session.trains.speed_tiles_per_tick(train), 0.0, "carrying speed")
	check_le(session.trains.speed_tiles_per_tick(train), session.trains.top_speed_tiles_per_tick(train),
		"never faster than the consist allows")
	check_ge(moved_to.x, 0.0, "still on the map")
	check_ge(moved_to.y, 0.0, "still on the map")
	check_true(is_finite(session.trains.heading(train)), "and it points somewhere sensible")


func test_a_train_completes_laps_and_returns_to_where_it_started() -> void:
	var train := coal_train()
	session.clock.step_ticks(4000)

	check_neq(session.trains.route_of(train), 0, "still on its timetable")
	check_gt(session.trains.total_revenue(train), 0.0, "the lap earned something")
	var trips := int(session.trains.train(train).get("trip_count", 0))
	check_gt(float(trips), 0.0, "it came back round at least once")
	check_ge(session.trains.progress_fraction(train), 0.0, "progress stays on the path")
	check_le(session.trains.progress_fraction(train), 1.0, "and never past the end of it")

	var visited := {}
	for tick in 4000:
		session.clock.step_ticks(1)
		var station := session.trains.current_station(train)
		if station != 0:
			visited[station] = true
	check_true(visited.has(int(line()["mine_station"])), "it dwells at the colliery")
	check_true(visited.has(int(line()["plant_station"])), "and at the works")


func test_a_platform_run_takes_every_ton_the_platform_offers() -> void:
	var train := coal_train()
	var mine_station := int(line()["mine_station"])
	var capacity := session.trains.capacity_for(train, "coal")
	var mine_departures := 0
	var best_loaded := 0.0
	for tick in 4000:
		session.clock.step_ticks(1)
		while not departures.is_empty():
			var station_id := int(departures.pop_front())
			if station_id != mine_station:
				continue
			mine_departures += 1
			var loaded := session.trains.loaded_for(train, "coal")
			var left_behind := session.stations.inventory_of(mine_station, "coal")
			best_loaded = maxf(best_loaded, loaded)
			check_le(loaded, capacity, "a consist never leaves with more than its wagons hold")
			check_eq(left_behind, 0.0,
					"and it never leaves coal sitting on a platform it has room for (loaded %.1f)" % loaded)
	check_gt(float(best_loaded), 0.0, "coal got aboard somewhere along the run")
	check_gt(float(mine_departures), 0.0, "the train actually ran out of the colliery")
	check_gt(float(best_loaded), 45.0 * 0.4, "and hauled a meaningful load, not a token handful")


func test_dwell_is_bounded_so_a_train_is_not_parked_forever() -> void:
	var train := coal_train()
	var longest_dwell := 0
	var running := 0
	for tick in 3000:
		session.clock.step_ticks(1)
		if session.trains.state_label(train) == "Loading":
			running += 1
			longest_dwell = maxi(longest_dwell, running)
		else:
			running = 0
	check_gt(longest_dwell, 0, "trains do stop to load")
	var ceiling := float(session.data.timing.get("train", {}).get("max_dwell_ticks", 120.0))
	check_le(float(longest_dwell), ceiling + 1.0, "but a dwell is bounded by the timing data")


func test_a_broken_line_strands_the_train_until_the_line_is_repaired() -> void:
	var train := coal_train()
	var route_id := int(line()["route"])
	session.clock.step_ticks(400)

	var rails: Array[Vector2i] = []
	for tile in session.rail.rail_tiles():
		rails.append(tile)
	check_gt(float(rails.size()), 2.0, "there is a line to cut")
	var half := rails.size() >> 1
	var middle: Array[Vector2i] = [rails[half], rails[half + 1]]
	var cut := session.builder.remove_track(middle)
	check_true(bool(cut["ok"]), "the middle of the line can be lifted: " + String(cut["reason"]))

	session.clock.step_ticks(400)
	check_false(session.routes.is_valid(route_id), "the timetable knows the line is gone")
	check_eq(session.trains.state_label(train), "No path", "and the train says so rather than driving off")

	var rebuilt := session.builder.build_track_run(middle)
	check_true(bool(rebuilt["ok"]), "the same ground can be relaid: " + String(rebuilt["reason"]))
	session.clock.step_ticks(600)
	check_true(session.routes.is_valid(route_id),
			"the timetable recovers on its own — " + session.routes.invalid_reason(route_id))
	check_neq(session.trains.state_label(train), "No path", "and the train goes back to work")


func test_two_trains_on_one_line_keep_their_own_books() -> void:
	var first := coal_train()
	var plant_station := int(line()["plant_station"])
	var bought := session.trains.purchase(plant_station, "steam_440", ["coal_hopper"])
	check_true(bool(bought["ok"]), "a second train can be bought at the far station")
	var second := int(bought["id"])
	var stops: Array[Dictionary] = [
		{"station_id": plant_station, "load": [], "unload": ["coal"]},
		{"station_id": int(line()["mine_station"]), "load": ["coal"], "unload": []},
	]
	check_true(bool(session.trains.set_route(second, stops)["ok"]), "on the same two stations")

	session.clock.step_ticks(3000)

	check_neq(session.trains.route_of(first), session.trains.route_of(second),
		"each train keeps its own timetable")
	check_neq(session.trains.position_tiles(first), session.trains.position_tiles(second),
		"and they are not welded together — no collision, no coupling, per V1 scope")
	check_true(session.economy.is_consistent(), "two trains, one ledger, still consistent")


func test_an_unrouted_train_answers_every_question_the_ui_asks() -> void:
	## A freshly bought engine has no route — the single most common state in a
	## new game, and the state that used to abort every typed read of a route.
	var mine_station := int(line()["mine_station"])
	var bought := session.trains.purchase(mine_station, "steam_440", ["coal_hopper"])
	check_true(bool(bought["ok"]), "a second engine can be bought and left unassigned")
	var idle := int(bought["id"])
	check_eq(session.trains.route_of(idle), 0, "and it has no route to follow")

	var no_route: Array[Dictionary] = session.routes.stops(0)
	check_true(no_route.is_empty(), "route 0 answers with no stops rather than a script error")
	var no_stations: Array[int] = session.routes.station_ids(0)
	check_true(no_stations.is_empty(), "and no station ids")
	var load_list: Array[Dictionary] = session.routes.load_options(0, 0)
	var unload_list: Array[Dictionary] = session.routes.unload_options(0, 0)
	check_true(load_list.is_empty() and unload_list.is_empty(),
		"a draft route offers no load or unload options")

	var carried: Array[Dictionary] = session.trains.batches(idle)
	check_true(carried.is_empty(), "an empty consist carries nothing")
	check_eq(session.trains.next_station(idle), 0, "an unassigned engine has no next station")
	check_near(session.trains.loaded_for(idle, "coal"), 0.0, "and has loaded no coal", 0.001)
	check_near(session.trains.progress_fraction(idle), 0.0, "and has made no progress", 0.001)
	var capacity := session.trains.capacity_by_cargo(idle)
	check_near(float(capacity.get("coal", 0.0)), 45.0, "its hopper is still rated for 45 tons")
	check_eq(session.trains.state_label(idle), "Idle", "and it reads as Idle, not broken")
	var home := session.trains.home_station(idle)
	check_eq(home, mine_station, "it waits at the station it was bought at")
	check_true(session.economy.is_consistent(), "and the ledger still balances")


func test_the_purchase_form_promises_what_the_train_delivers() -> void:
	## The yard's numbers must be the domain's numbers, not a second calculation
	## that can drift from it (task 3.2: live capacity, weight, estimated speed).
	var mine_station := int(line()["mine_station"])
	var consist: Array[String] = ["steam_440", "coal_hopper", "coal_hopper"]
	var preview := session.trains.preview_consist(consist)
	check_near(float(preview["price"]), 35600.0, "a 4-4-0 with two hoppers costs 35 600")
	var capacity: Dictionary = preview["capacity"]
	check_near(float(capacity.get("coal", 0.0)), 90.0, "and it offers 90 tons of coal")
	check_gt(float(preview["weight_tons"]), 0.0, "the form can state a weight before buying")
	check_gt(float(preview["max_speed_kmh"]), 0.0, "and an estimated speed")
	check_gt(float(preview["running_cost_month"]), 0.0, "and the monthly upkeep")

	var bought := session.trains.purchase(mine_station, "steam_440", ["coal_hopper", "coal_hopper"])
	check_true(bool(bought["ok"]), "the quoted consist is buyable")
	var train := int(bought["id"])
	check_near(session.trains.consist_weight(train), float(preview["weight_tons"]),
		"the weight promised is the weight delivered", 0.001)
	check_near(session.trains.estimated_max_speed(train), float(preview["max_speed_kmh"]),
		"the speed promised is the speed it runs at when empty", 0.001)
	check_near(session.trains.consist_running_cost(train), float(preview["running_cost_month"]),
		"the upkeep promised is the upkeep charged")
	var actual := session.trains.capacity_by_cargo(train)
	check_near(float(actual.get("coal", 0.0)), float(capacity.get("coal", 0.0)),
		"and the capacity promised is the capacity it has")


func test_a_train_books_its_earnings_to_the_month_and_the_lifetime() -> void:
	var train := coal_train()
	var ticks := 0
	while session.trains.total_revenue(train) <= 0.0 and ticks < 6000:
		session.clock.step_ticks(10)
		ticks += 10
	var lifetime := session.trains.total_revenue(train)
	check_gt(lifetime, 0.0, "the coal line earns its first money")
	if lifetime <= 0.0:
		return
	check_near(session.trains.monthly_revenue_of(train), lifetime,
		"in its first month every ton of revenue belongs to that month", 0.01)
	check_lt(session.trains.monthly_profit(train), lifetime,
		"and profit is that takings less the consist's upkeep")
	watch_months(session.clock)
	check_true(run_months(session.clock, 1), "the calendar rolls over")
	check_lt(session.trains.monthly_revenue_of(train), session.trains.total_revenue(train),
		"the new month starts afresh while the lifetime total stands")
	check_gt(session.trains.total_revenue(train), 0.0, "and nothing was wiped from the ledger")


func test_selling_states_the_refund_before_it_asks() -> void:
	var mine_station := int(line()["mine_station"])
	var bought := session.trains.purchase(mine_station, "steam_440", ["coal_hopper"])
	check_true(bool(bought["ok"]), "a plain hopper outfit is bought")
	var train := int(bought["id"])
	var promised := session.trains.refund_for(train)
	check_near(promised, 15400.0, "half of 30 800 comes back")
	var cash_before := session.economy.cash
	check_true(session.trains.sell(train), "the sale completes")
	check_near(session.economy.cash - cash_before, promised,
		"and the banked figure is exactly the one that was stated", 0.001)
	check_true(session.economy.is_consistent(), "a refund leaves the ledger consistent")


func test_filing_the_same_stops_in_the_other_order_turns_the_train_round() -> void:
	## Editing a route is not a cosmetic edit: the path has to be recomputed and
	## the train handed over to the new one, or the consist keeps running a line
	## the player believes they have changed.
	var l := line()
	var train := int(l["train"])
	var route_id := int(l["route"])
	var mine_station := int(l["mine_station"])
	var plant_station := int(l["plant_station"])
	var stops := session.routes.stops(route_id)
	check_eq(stops.size(), 2, "the line was built with two stops")
	var path_before := session.routes.path_of(route_id)
	check_gt(float(path_before.size()), 1.0, "and it has a path to run")

	var reversed: Array[Dictionary] = []
	for index in range(stops.size() - 1, -1, -1):
		reversed.append(Dictionary(stops[index].duplicate()))
	var refiled := session.trains.set_route(train, reversed)
	check_true(bool(refiled["ok"]), "the same stops filed the other way: " + String(refiled["reason"]))
	var edited := int(refiled["id"])
	check_neq(edited, 0, "the edited route exists")
	check_true(session.routes.is_valid(edited), "and it is valid on the day it was filed")
	var path_after := session.routes.path_of(edited)
	check_near(float(path_after.size()), float(path_before.size()),
		"the recomputed path runs over the same length of rail")
	# A route is a closed loop, so the path always begins at the stop filed first:
	# the anchor moving to the other end of the valley is what proves the running
	# was rewritten, rather than the old path being handed back unchanged.
	var pit_access := Vector2(session.stations.rail_access_tile(mine_station))
	var works_access := Vector2(session.stations.rail_access_tile(plant_station))
	check_near(Vector2(path_before[0]).distance_to(pit_access), 0.0,
		"the old path began at the pit, the stop filed first", 0.001)
	check_near(Vector2(path_after[0]).distance_to(works_access), 0.0,
		"the new path begins at the works: the path was recomputed, not reused", 0.001)
	var same_ground := 0
	for point in path_after:
		for other in path_before:
			if Vector2(point).distance_to(Vector2(other)) < 0.001:
				same_ground += 1
				break
	check_eq(same_ground, path_after.size(),
		"and it runs over exactly the same rail, in the other order")
	var ends := session.routes.station_ids(edited)
	check_eq(ends[0], plant_station, "the works is the first stop now")
	check_eq(ends[1], mine_station, "and the pit the last")
	check_eq(session.trains.route_of(train), edited, "the train was moved onto the route it now has")

func test_a_heavier_stop_holds_the_train_longer() -> void:
	## Dwell is priced by the units handled, not by a stopwatch: 40 tons on a
	## platform must keep the consist standing longer than 10, and by what the
	## timing data says — bounded so a blocked platform cannot park a train.
	var light := _longest_dwell_with(10.0)
	var heavy := _longest_dwell_with(40.0)
	check_gt(float(light), 0.0, "a loaded platform does make a train stop")
	check_gt(float(heavy), float(light), "and four times the coal holds it longer (%d against %d ticks)" % [heavy, light])
	var timing: Dictionary = session.data.timing.get("train", {})
	var per_unit := float(timing.get("dwell_ticks_per_unit", 1.2))
	var floor_ticks := float(timing.get("min_dwell_ticks", 6.0))
	var ceiling := float(timing.get("max_dwell_ticks", 120.0))
	check_ge(float(light), floor_ticks + 10.0 * per_unit - 6.0,
		"ten tons is held for the ticks the data prices it at")
	check_le(float(heavy), ceiling, "and no stop outruns the ceiling in the data file")


func _longest_dwell_with(amount: float) -> int:
	var fresh := TestSession.create()
	var l := TestSession.coal_line(fresh)
	check_true(bool(l["ok"]), "a line to measure on: " + String(l["reason"]))
	var train := int(l["train"])
	var piled := fresh.stations.add_cargo(int(l["mine_station"]), "coal", amount)
	check_gt(piled, 0.0, "and there is coal on the platform to load")
	var longest := 0
	var running := 0
	for tick in 420:
		fresh.clock.step_ticks(1)
		if fresh.trains.state_label(train) == "Loading":
			running += 1
			longest = maxi(longest, running)
		else:
			running = 0
	TestSession.dispose(fresh)
	return longest


func test_a_loaded_train_gives_up_speed_for_the_climb_it_meets() -> void:
	## Grade is what stands between a timetable and reality.  A stretch of line is
	## first run flat, then run as a ramp, by the same loaded consist over the same
	## tiles: the only thing that changes is the slope under the wheels, so the only
	## thing the assertion can be blaming is the slope.
	var l := line()
	var train := int(l["train"])
	var route_id := int(l["route"])
	session.stations.add_cargo(int(l["mine_station"]), "coal", 40.0)
	var waited := 0
	while waited < 900 and (session.trains.state_label(train) != "Moving"
			or session.trains.loaded_for(train, "coal") < 5.0):
		session.clock.step_ticks(1)
		waited += 1
	check_eq(session.trains.state_label(train), "Moving", "the loaded consist is out on the line")
	check_ge(session.trains.loaded_for(train, "coal"), 5.0, "and it is carrying coal as it runs")

	var per_step := float(session.data.timing.get("train", {}).get("grade_speed_factor_per_step", 0.72))
	var region := _line_ahead_of(train, session.routes.path_of(route_id))
	check_gt(float(region.size()), 12.0, "there is a stretch of line ahead to work with")
	var original := _heights_of(region)

	_shape_region(region, 0)
	var flat := _cross_loaded(train, region)
	check_gt(float(flat["slowest"]), 0.0, "over flat ground it never even looks at the brakes")
	check_near(float(flat["lowest_factor"]), 1.0, "and the data applies no grade factor to level ground", 0.001)

	_shape_region(region, 3)
	var climbing := _cross_loaded(train, region)
	check_gt(float(climbing["slowest"]), 0.0, "a one-in-three rise slows a train, it does not stop one")
	check_lt(float(climbing["slowest"]), float(flat["slowest"]),
			"the same consist over the same tiles gives up speed for the climb (%.3f against %.3f)" % [
				float(climbing["slowest"]), float(flat["slowest"])])
	check_near(float(climbing["lowest_factor"]), per_step,
			"and it gives way by exactly the factor the timing data prices", 0.001)
	check_true(session.routes.is_valid(route_id), "a graded line is still a runnable line")

	_shape_region_inverted(region, 3)
	var descending := _cross_loaded(train, region)
	check_gt(float(descending["highest_factor"]), 1.0, "the same slope run the other way gives the speed back")
	check_le(float(descending["highest_factor"]), 1.0 / per_step,
			"and the descent bonus is bounded by the same data, not by a guess")

	_restore_heights(original)
	var level_again := _cross_loaded(train, region)
	check_ge(float(level_again["slowest"]), float(climbing["slowest"]),
			"take the slope away and the train stops paying for it")


func test_no_consist_ever_runs_faster_than_the_speed_it_is_rated_at() -> void:
	## The yard quotes a speed built from the whole consist, cargo included.  If the
	## tick loop kept the ceiling the train was bought with, every loaded departure
	## would run past the number the player was quoted.
	var train := coal_train()
	session.stations.add_cargo(int(line()["mine_station"]), "coal", 60.0)
	var worst := _worst_overshoot(train, 1800)
	check_gt(float(worst["samples"]), 300.0, "the consist was actually running while it was watched")
	check_le(float(worst["breach"]), 0.0001,
			"never once over its rated speed times the grade it is on (%.4f over)" % float(worst["breach"]))


func test_two_trains_running_at_each_other_pass_and_neither_notices() -> void:
	## V1 has no signals and no block reservation, which only works if the movement
	## code truly cannot be blocked by another consist: two trains filed in opposite
	## directions have to interchange on a single track and keep working.
	var l := line()
	var first := int(l["train"])
	var mine_station := int(l["mine_station"])
	var plant_station := int(l["plant_station"])
	var bought := session.trains.purchase(plant_station, "steam_440", ["coal_hopper"])
	check_true(bool(bought["ok"]), "a second engine is bought at the far platform: " + String(bought["reason"]))
	var second := int(bought["id"])
	var stops: Array[Dictionary] = [
		{"station_id": plant_station, "load": [], "unload": ["coal"]},
		{"station_id": mine_station, "load": ["coal"], "unload": []},
	]
	var planned := session.trains.set_route(second, stops)
	check_true(bool(planned["ok"]), "and filed to run the same single line in reverse: " + String(planned["reason"]))

	var origin := Vector2(session.stations.rail_access_tile(mine_station))
	var far := Vector2(session.stations.rail_access_tile(plant_station))
	var direction := far - origin
	var previous := _along(session.trains.position_tiles(first), origin, direction) \
			- _along(session.trains.position_tiles(second), origin, direction)
	var sign := 1 if previous > 0.0 else -1
	var interchanges := 0
	var strands := 0
	for tick in 2400:
		session.clock.step_ticks(1)
		var now := _along(session.trains.position_tiles(first), origin, direction) \
				- _along(session.trains.position_tiles(second), origin, direction)
		if now != 0.0:
			var now_sign := 1 if now > 0.0 else -1
			if now_sign != sign:
				interchanges += 1
				sign = now_sign
		if session.trains.state_label(first) == "No path" or session.trains.state_label(second) == "No path":
			strands += 1

	check_gt(float(interchanges), 1.0, "the two consists interchange on the single line")
	check_eq(strands, 0, "and neither one is ever left stranded by the other")
	check_eq(session.trains.state_label(first), "Moving", "one is still running at the end")
	check_neq(session.trains.state_label(second), "No path", "so is the other")
	check_true(session.routes.is_valid(session.trains.route_of(first)), "both timetables are still valid")
	check_true(session.routes.is_valid(session.trains.route_of(second)), "including the reversed one")
	check_gt(session.trains.total_revenue(first) + session.trains.total_revenue(second), 0.0,
			"and the valley paid them both for the coal they moved")


func _along(point: Vector2, origin: Vector2, direction: Vector2) -> float:
	if direction.length_squared() <= 0.0:
		return 0.0
	return (point - origin).dot(direction / direction.length())


func _line_ahead_of(train_id: int, path: PackedVector2Array) -> Array[Vector2i]:
	## A stretch of the train's own line, ending before the next platform: three
	## approach tiles that stay level, then the measured stretch.
	var at := _nearest_index(path, session.trains.position_tiles(train_id))
	var tiles: Array[Vector2i] = []
	for index in range(mini(at + 4, path.size() - 1), mini(at + 26, path.size())):
		var tile := Vector2i(roundi(path[index].x), roundi(path[index].y))
		if not tiles.has(tile):
			tiles.append(tile)
	return tiles


func _heights_of(tiles: Array[Vector2i]) -> Array[int]:
	var heights: Array[int] = []
	for tile in tiles:
		heights.append(session.world.height_at(tile))
	return heights


func _lowest_height(tiles: Array[Vector2i]) -> int:
	var lowest := session.world.height_at(tiles[0])
	for tile in tiles:
		lowest = mini(lowest, session.world.height_at(tile))
	return lowest


func _shape_region(tiles: Array[Vector2i], rise_every: int) -> void:
	## Level ground, or a rise of one step every `rise_every` tiles from the approach.
	var base := _lowest_height(tiles) - rise_every
	for index in tiles.size():
		var climb := 0 if rise_every == 0 else int(float(maxi(0, index - 3)) / float(rise_every))
		session.world.set_height(tiles[index], base + climb)


func _shape_region_inverted(tiles: Array[Vector2i], fall_every: int) -> void:
	## The same ramp, reversed, so the consist runs downhill over the identical rail.
	var base := _lowest_height(tiles) + maxi(0, int(float(tiles.size() - 3) / float(fall_every)))
	for index in tiles.size():
		var fall := 0 if fall_every == 0 else int(float(maxi(0, index - 3)) / float(fall_every))
		session.world.set_height(tiles[index], base - fall)


func _restore_heights(original: Array[int]) -> void:
	var tiles := _working_region
	for index in original.size():
		session.world.set_height(tiles[index], original[index])


func _cross_loaded(train_id: int, region: Array[Vector2i]) -> Dictionary:
	## Run the train until it has crossed the region and left it again, loaded only,
	## and report the slowest tick it managed on the region plus the steepest and the
	## most generous grade factors it met there.
	_working_region = region
	var slowest := 1000.0
	var lowest_factor := 1.0
	var highest_factor := 1.0
	var inside := false
	for tick in 4000:
		session.clock.step_ticks(1)
		if session.trains.state_label(train_id) != "Moving":
			continue
		var point := session.trains.position_tiles(train_id)
		var here := Vector2i(roundi(point.x), roundi(point.y))
		if not region.has(here):
			if inside:
				break
			continue
		if session.trains.loaded_for(train_id, "coal") < 5.0:
			continue
		inside = true
		slowest = minf(slowest, session.trains.speed_tiles_per_tick(train_id))
		var factor := session.trains.grade_speed_factor(train_id)
		lowest_factor = minf(lowest_factor, factor)
		highest_factor = maxf(highest_factor, factor)
	if not inside:
		return {"slowest": -1.0, "lowest_factor": 1.0, "highest_factor": 1.0}
	return {"slowest": slowest, "lowest_factor": lowest_factor, "highest_factor": highest_factor}


## The rated ceiling against the speed actually held, tick by tick.  The factor is
## read before the tick and the speed after it, because that is the pairing
## `_accelerate` itself uses: read the other way round, a train that crested a
## descent last tick looks like a violation when it is only obeying the brakes.
func _worst_overshoot(train_id: int, ticks: int) -> Dictionary:
	var breach := 0.0
	var samples := 0
	for tick in ticks:
		var ceiling := session.trains.top_speed_tiles_per_tick(train_id) \
				* session.trains.grade_speed_factor(train_id)
		session.clock.step_ticks(1)
		if session.trains.state_label(train_id) != "Moving":
			continue
		samples += 1
		breach = maxf(breach, session.trains.speed_tiles_per_tick(train_id) - ceiling)
	return {"breach": breach, "samples": float(samples)}


func _nearest_index(path: PackedVector2Array, point: Vector2) -> int:
	var best := 0
	var best_distance := 1e9
	for index in path.size():
		var distance := Vector2(path[index]).distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = index
	return best
