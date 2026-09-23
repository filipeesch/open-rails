extends TestBase

## Cargo: where monthly production goes, what a sink will take, and what a
## delivery is worth.
##
## The allocator and the pricing rule are the two places the simulation can
## quietly invent or destroy value, so both are pinned here against the shipped
## map rather than against hand-made dictionaries.

var session: GameSession
var mine_id: int = 0
var plant_id: int = 0
var mine_station: int = 0
var plant_station: int = 0


func setup() -> void:
	session = TestSession.create()
	watch_months(session.clock)
	var line := TestSession.coal_line(session)
	check_true(bool(line["ok"]), "the coal line is buildable: " + String(line["reason"]))
	mine_id = int(line["mine"])
	plant_id = int(line["plant"])
	mine_station = int(line["mine_station"])
	plant_station = int(line["plant_station"])


func teardown() -> void:
	TestSession.dispose(session)
	session = null


## A station that serves `tile` and whose centre sits within a distance band of
## it.  Catchments are only four tiles wide, so "near" and "far" have to be
## asked for explicitly instead of being whatever the fixture found first.
func _station_covering(tile: Vector2i, min_distance: float, max_distance: float, label: String) -> int:
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var anchor := Vector2i(tile.x + dx, tile.y + dy)
			var centre := Vector2i(anchor.x + 1, anchor.y + 1)
			var distance := WorldCoords.distance_tiles(centre, tile)
			if distance < min_distance or distance > max_distance:
				continue
			var preview := session.builder.preview_station("small_station", anchor)
			if not bool(preview["ok"]) or not TestSession.preview_covers(preview, tile):
				continue
			var built := session.builder.build_station("small_station", anchor, label)
			if bool(built["ok"]):
				return int(built["id"])
	return 0


# --- allocation -------------------------------------------------------------

func test_a_working_mine_fills_the_station_that_serves_it() -> void:
	check_true(run_months(session.clock, 2), "two months of calendar pass")
	var coal := session.stations.inventory_of(mine_station, "coal")
	check_gt(coal, 0.0, "coal reached the colliery station")
	check_le(coal, session.stations.storage_limit(mine_station, "coal"), "and stopped at the storage ceiling")
	var rate := session.industries.production_rate(mine_id, "coal")
	check_le(coal, rate * 2.0 + 0.001, "no more than two months of output, either")


func test_allocation_cannot_invent_cargo() -> void:
	var rate := session.industries.production_rate(mine_id, "coal")
	check_gt(rate, 0.0, "the colliery produces coal")
	for month in 3:
		check_true(run_months(session.clock, 1), "the calendar rolls over")
		var produced := rate * float(month + 1)
		var afloat: float = session.stations.inventory_of(mine_station, "coal") \
				+ session.industries.inventory_of(mine_id, "coal") \
				+ float(session.cargo.delivered_by_cargo().get("coal", 0.0))
		for train_id in session.trains.trains():
			for batch in session.trains.batches(train_id):
				if String(batch["cargo"]) == "coal":
					afloat += float(batch["quantity"])
		check_le(afloat, produced + 0.001,
				"month %d: what exists (%.1f) never exceeds what was mined (%.1f)" % [month + 1, afloat, produced])


func test_cargo_with_no_rail_to_leave_on_is_stored_not_destroyed() -> void:
	var other_mine := 0
	for industry_id in session.industries.industries():
		if session.industries.definition_of(industry_id) == "coal_mine" and industry_id != mine_id:
			other_mine = industry_id
	check_neq(other_mine, 0, "the valley has a second, unrailwayd colliery")
	var rate := session.industries.production_rate(other_mine, "coal")
	check_true(run_months(session.clock, 2), "two months pass with no line to it")
	var heaped := session.industries.inventory_of(other_mine, "coal")
	check_near(heaped, minf(rate * 2.0, session.industries.capacity_of(other_mine, "coal")),
			"its coal sits where it was dug", 0.001)
	check_gt(heaped, 0.0, "and it is still there to be collected")


func test_the_nearer_station_receives_the_larger_share() -> void:
	## Two platforms on one source share its output, weighted by 1/distance.
	## A town is the honest place to test it: unlike the colliery it has no
	## railway of its own yet, so nothing else is competing for the split.
	var marlow := TestSession.town_containing(session, "marlow")
	var town_tile := session.towns.tile_of(marlow)
	session.builder.build_track_run(TestSession.spur_tiles(Vector2i(town_tile.x, town_tile.y - 3)))
	session.builder.build_track_run(TestSession.spur_tiles(Vector2i(town_tile.x, town_tile.y + 3)))
	var near := _station_covering(town_tile, 3.0, 3.3, "Market Place")
	check_neq(near, 0, "a station can stand at the edge of the town's ground")
	var far := _station_covering(town_tile, 3.5, 4.0, "Road End")
	check_neq(far, 0, "and another at the edge of the same catchment")
	check_neq(session.stations.tile_of(near), session.stations.tile_of(far), "on different ground")

	check_true(run_months(session.clock, 2), "two months of passenger traffic pass")
	var near_pax := session.stations.inventory_of(near, "passengers")
	var far_pax := session.stations.inventory_of(far, "passengers")
	check_gt(near_pax, 0.0, "the near platform took passengers")
	check_gt(far_pax, 0.0, "so did the far one — a catchment is shared, not won")
	check_gt(near_pax, far_pax,
			"but the nearer platform takes the larger share (%.1f against %.1f)" % [near_pax, far_pax])


func test_a_full_station_hands_the_overshoot_back_to_the_mine() -> void:
	## A pit with a platform but no train: the station fills, the pit keeps digging,
	## and the coal that has nowhere to go must wait at the pit rather than vanish.
	var other_mine := 0
	for industry_id in session.industries.industries():
		if session.industries.definition_of(industry_id) == "coal_mine" and industry_id != mine_id:
			other_mine = industry_id
	var pit_station := TestSession.serve(session, session.industries.tile_of(other_mine), "Deephilgans Wharf")
	check_neq(pit_station, 0, "a platform can be built at the second pit")
	var limit := session.stations.storage_limit(pit_station, "coal")
	var rate := session.industries.production_rate(other_mine, "coal")
	var months_needed := int(ceilf(limit / maxf(rate, 1.0))) + 2
	check_true(run_months(session.clock, months_needed), "enough months pass to overflow the platform")
	check_near(session.stations.inventory_of(pit_station, "coal"), limit,
			"the platform sits exactly at its ceiling", 0.001)
	check_gt(session.industries.inventory_of(other_mine, "coal"), 0.0,
			"and the coal it could not take is heaped at the pit, not deleted")


func test_town_cargo_arrives_in_whole_units_and_sums_up() -> void:
	var marlow := TestSession.town_containing(session, "marlow")
	var town_station := TestSession.serve(session, session.towns.tile_of(marlow), "Marlow East")
	check_neq(town_station, 0, "a station can be built to serve the town")
	check_true(run_months(session.clock, 3), "three months pass")
	for cargo_id in ["passengers", "mail"]:
		var held := session.stations.inventory_of(town_station, cargo_id)
		check_ge(held, 1.0, "%s accumulates into whole units" % cargo_id)
		check_eq(held, floorf(held), "%s is counted in whole units, never fractions" % cargo_id)


# --- sinks ------------------------------------------------------------------

func test_a_station_refuses_cargo_its_hinterland_has_no_use_for() -> void:
	var before := session.cargo.delivery_count()
	var refused := session.cargo.deliver(plant_station, "passengers", 20.0, 100.0, mine_station, 1.0)
	check_false(bool(refused["ok"]), "a power plant will not take passengers")
	check_near(float(refused["delivered"]), 0.0, "and it takes none of them", 0.001)
	check_has(String(refused["reason"]).to_lower(), "no use for", "the reason says why")
	check_eq(session.cargo.delivery_count(), before, "no delivery was recorded")
	check_true(session.economy.is_consistent(), "and no money was booked for it")


func test_a_sink_at_its_monthly_limit_takes_what_fits_and_refuses_the_rest() -> void:
	var room := session.cargo.sink_demand(plant_station, "coal")
	check_gt(room, 0.0, "the works has appetite this month")
	var first := session.cargo.deliver(plant_station, "coal", room + 30.0, 100.0, mine_station, 0.0)
	check_true(bool(first["ok"]), "the delivery is accepted")
	check_near(float(first["delivered"]), room, "but only as far as the works has room", 0.001)
	var second := session.cargo.deliver(plant_station, "coal", 30.0, 100.0, mine_station, 0.0)
	check_false(bool(second["ok"]), "the remainder is refused, not force-fed")
	check_near(float(second["delivered"]), 0.0, "the train keeps every ton of it", 0.001)
	check_has(String(second["reason"]).to_lower(), "cannot take more", "and the reason says the works is full for the month")


func test_delivered_coal_is_consumed_by_the_plant_that_took_it() -> void:
	var room := session.cargo.sink_demand(plant_station, "coal")
	session.cargo.deliver(plant_station, "coal", room, 100.0, mine_station, 0.0)
	var taken := session.industries.received_this_month(plant_id, "coal")
	check_gt(taken, 0.0, "the works books what it received this month")
	check_le(session.cargo.sink_demand(plant_station, "coal"), room - taken + 0.001,
			"and its remaining appetite shrinks by exactly that")


# --- pricing ----------------------------------------------------------------

func test_a_delivery_is_paid_for_by_distance_carried_and_quality() -> void:
	var def := session.data.cargo_def("coal")
	var quantity := 20.0
	var distance := 120.0
	var outcome := session.cargo.deliver(plant_station, "coal", quantity, distance, mine_station, 0.0)
	check_true(bool(outcome["ok"]), "the coal was taken")
	var expected := quantity * def.base_rate * distance * session.cargo.quality("coal", 0.0)
	check_near(float(outcome["revenue"]), expected, "revenue is quantity × rate × distance × quality", 0.01)
	check_near(float(outcome["delivered"]), quantity, "and the delivered tonnage is its own number", 0.001)
	check_neq(float(outcome["revenue"]), quantity, "the two are not the same figure")


func test_a_further_haul_pays_better_than_a_short_one() -> void:
	var short_run := session.cargo.deliver(plant_station, "coal", 10.0, 40.0, mine_station, 0.0)
	var long_run := session.cargo.deliver(plant_station, "coal", 10.0, 160.0, mine_station, 0.0)
	check_true(bool(short_run["ok"]) and bool(long_run["ok"]), "both loads were accepted")
	check_gt(float(long_run["revenue"]), float(short_run["revenue"]),
			"the longer haul earns more for the same ten tons")


func test_perishable_cargo_arrives_worth_less_the_longer_it_takes() -> void:
	var fresh := session.cargo.quality("passengers", 0.0)
	var stale := session.cargo.quality("passengers", 20.0)
	check_near(fresh, 1.0, "cargo fresh off the platform is worth full rate", 0.001)
	check_lt(stale, fresh, "passengers waiting twenty days are not")
	var def := session.data.cargo_def("passengers")
	check_ge(stale, def.quality_floor, "but quality never falls below the floor in the data")
	var coal_floor := session.data.cargo_def("coal")
	var coal_age := session.cargo.quality("coal", 40.0)
	check_near(coal_age, coal_floor.quality_floor, "coal settles at its own high floor, not lower", 0.001)
	check_gt(coal_age, stale, "and it keeps its value far better than passengers do")


func test_the_cargo_ledger_and_the_money_ledger_tell_the_same_story() -> void:
	TestSession.run_until(session, func() -> bool: return session.cargo.delivery_count() > 0,
			TestSession.DELIVERY_TICKS)
	check_gt(session.cargo.delivery_count(), 0, "the train made deliveries")
	var booked := 0.0
	for transaction in session.economy.unreversed_ledger():
		if transaction.category == EconomyService.CATEGORY_REVENUE:
			booked += transaction.amount
	check_gt(booked, 0.0, "the ledger shows revenue")
	check_near(booked, session.cargo.revenue_total(),
			"every pound the cargo service earned is in the ledger", 0.01)
	check_true(session.economy.is_consistent(), "and the ledger still balances")


func test_a_new_cargo_type_needs_a_data_file_and_nothing_else() -> void:
	## Invariant 7: content is data.  A cargo that did not exist when the game was
	## compiled has to travel through the same wagons, stations and allocators the
	## shipped three cargos use, with no transport code written for it.
	var cargo_path := "user://test_timber_cargo.json"
	var wagon_path := "user://test_timber_wagon.json"
	write_json(cargo_path, {
		"id": "test_timber", "display_name": "Test Timber", "unit_label": "loads",
		"base_rate": 9.0, "time_sensitivity": 0.0, "quality_floor": 0.9,
		"colour": "#8a5a2b", "wagon_required": true, "tonnes_per_unit": 1.2,
	})
	write_json(wagon_path, {
		"id": "test_timber_flat", "display_name": "Test Timber Flat", "type": "wagon",
		"asset": "test_timber_flat", "price": 3000.0, "running_cost_month": 90.0,
		"cargo": "test_timber", "capacity": 25, "weight_tons": 9.0,
	})
	var loaded_cargo := session.data.load_definition_file(cargo_path)
	check_true(bool(loaded_cargo["ok"]), "the cargo definition loads: " + String(loaded_cargo["reason"]))
	var loaded_wagon := session.data.load_definition_file(wagon_path)
	check_true(bool(loaded_wagon["ok"]), "and its wagon: " + String(loaded_wagon["reason"]))

	var bought := session.trains.purchase(mine_station, "steam_440", ["test_timber_flat"])
	check_true(bool(bought["ok"]), "a consist can be bought for it: " + String(bought["reason"]))
	var freight := int(bought["id"])
	var caps: Dictionary = session.trains.capacity_by_cargo(freight)
	check_near(float(caps.get("test_timber", 0.0)), 25.0, "the wagons rate it by the data file", 0.001)

	var stored := session.stations.add_cargo(mine_station, "test_timber", 12.0)
	check_near(stored, 12.0, "a station will hold it like any other cargo", 0.001)
	var refused := session.cargo.deliver(plant_station, "test_timber", 12.0, 80.0, mine_station, 0.0)
	check_false(bool(refused["ok"]),
			"and no sink takes it until an industry is written to want it — nothing invented a market")
	check_has(String(refused["reason"]).to_lower(), "no use for", "with the plain refusal to show the player")
	session.trains.sell(freight)

# --- conservation and aggregation --------------------------------------------

func test_the_allocator_never_creates_or_destroys_a_ton() -> void:
	## Many overlapping platforms on the valley's sources, three months of digging:
	## what the pits added has to still be somewhere — heaped at the pit, lying on
	## a platform, aboard a train or burnt at the works.  Not a ton more, and not a
	## ton less than what was put in.
	var marlow := TestSession.town_containing(session, "marlow")
	var town_tile := session.towns.tile_of(marlow)
	var line := session.builder.build_track_run(
		TestSession.spur_tiles(Vector2i(town_tile.x, town_tile.y - 3)))
	check_true(bool(line["ok"]), "a line reaches Marlow: " + String(line["reason"]))
	var first := _station_covering(town_tile, 3.0, 3.3, "Market Place")
	var second := _station_covering(town_tile, 3.5, 4.0, "Road End")
	check_neq(first, 0, "one platform serves the town")
	check_neq(second, 0, "and a second overlaps the same catchment")

	var dug_before := _coal_in_valley()
	var mined_before := _dug_since_start()
	var dug_after := 0.0
	var mined_after := 0.0
	for month in 3:
		check_true(run_months(session.clock, 1), "month %d of the three passes" % (month + 1))
	dug_after = _coal_in_valley()
	mined_after = _dug_since_start()
	var produced := mined_after - mined_before

	check_gt(produced, 0.0, "both pits dug coal across the three months")
	check_near(dug_before + produced, dug_after,
		"every ton dug is still in the valley — %.1f in against %.1f out" % [
			dug_before + produced, dug_after], 0.001)

	## Town cargo is generated on the calendar, so the tonnage a platform should
	## hold is exact only at a fixed distance from the first month.  Read it here,
	## at exactly three months of running, before the wait below lets the clock run
	## on to whatever tick a loaded leg across the valley finishes at.
	var passengers := 0.0
	var mail := 0.0
	for station_id in session.stations.stations():
		passengers += session.stations.inventory_of(station_id, "passengers")
		mail += session.stations.inventory_of(station_id, "mail")
	var town_pax: float = session.towns.generation_map(marlow).get("passengers", 0.0)
	var town_mail: float = session.towns.generation_map(marlow).get("mail", 0.0)

	## Where the ton ended up, in the aggregate: a works that was paid for a
	## delivery owns the coal it took.  V1 burns nothing, so a delivery is a
	## transfer into the works' yard and no coal simply leaves the world.
	##
	## This wait is only so the claim about where a ton ended up is about a ton that
	## actually moved; at the pace the models imply a loaded leg across the valley
	## is longer than a month of the calendar.
	TestSession.run_until(session,
			func() -> bool: return float(session.cargo.delivered_by_cargo().get("coal", 0.0)) > 0.0,
			TestSession.DELIVERY_TICKS)
	var taken := float(session.cargo.delivered_by_cargo().get("coal", 0.0))
	var at_works := 0.0
	for industry_id in session.industries.industries():
		if session.industries.is_consumer(industry_id):
			at_works += session.industries.inventory_of(industry_id, "coal")
	check_gt(taken, 0.0, "and part of it was delivered to a works by rail")
	check_ge(at_works, taken - 0.001,
		"the works holds every ton it took (%.1f in its yard against %.1f delivered)" % [
			at_works, taken])

	check_near(passengers, town_pax * 3.0,
		"Marlow's three months of passengers all lie on its two platforms, shared but not lost",
		0.001)
	check_near(mail, town_mail * 3.0, "and so does its mail", 0.001)


func test_a_second_lift_from_the_same_place_joins_the_first_batch() -> void:
	## A consist that cannot unload everything keeps what is left, and the next
	## lift at the same pit has to join that cargo to the batch it is already
	## carrying — keeping the day the first of it was lifted, because that is the
	## day a late delivery is priced from.
	var train := 0
	for train_id in session.trains.trains():
		if session.trains.route_of(train_id) != 0:
			train = train_id
	check_neq(train, 0, "a train is working the line")
	var capacity := session.trains.capacity_for(train, "coal")
	check_near(capacity, 90.0, "two coal hoppers rate 90 tons")
	check_true(run_months(session.clock, 2), "the pit builds a head of coal")
	session.stations.add_cargo(mine_station, "coal", 120.0)

	var batch_tick := -1
	var least_aboard := 0.0
	var burned := 0
	var merged := -1.0
	var guard := 0
	while guard < 20000 and merged < 0.0:
		session.clock.step_ticks(1)
		guard += 1
		var coal_aboard: Array[Dictionary] = []
		for batch in session.trains.batches(train):
			if String(batch["cargo"]) == "coal":
				coal_aboard.append(batch)
		if coal_aboard.size() > 1:
			continue
		# Half of a month's appetite is handed to the works while the train is on
		# the road to it, so the consist is only part-emptied on arrival and comes
		# home still carrying coal.
		if burned == 0 and coal_aboard.size() == 1 \
				and session.trains.current_station(train) == 0 \
				and session.trains.next_station(train) == plant_station \
				and float(coal_aboard[0]["quantity"]) > 60.0:
			session.cargo.deliver(plant_station, "coal", 30.0, 12.0, mine_station, 0.0)
			burned += 1
			batch_tick = int(coal_aboard[0]["created_tick"])
			least_aboard = float(coal_aboard[0]["quantity"])
			continue
		if burned == 0 or coal_aboard.size() == 0:
			continue
		if int(coal_aboard[0]["created_tick"]) != batch_tick:
			continue
		var aboard := float(coal_aboard[0]["quantity"])
		least_aboard = minf(least_aboard, aboard)
		if aboard > least_aboard + 0.001:
			merged = aboard
	check_gt(float(burned), 0.0, "the works was fed early, so the consist came home half-full")
	check_gt(merged, 0.0,
		"the lift after the refused delivery joined the cargo still aboard instead of " \
		+ "standing beside it as a second batch")
	check_le(merged, capacity, "and the merged batch still fits the consist")

	var duplicates := 0
	for train_id in session.trains.trains():
		var seen := {}
		for batch in session.trains.batches(train_id):
			var key := "%s:%d" % [String(batch["cargo"]), int(batch["origin"])]
			if seen.has(key):
				duplicates += 1
			seen[key] = true
	check_eq(duplicates, 0, "no train ever carries two batches of one cargo from one station")


## What the pits have dug since the world began, read from their own lifetime
## totals — the one number that cannot be misread by looking at it on the wrong
## side of a month boundary.
func _dug_since_start() -> float:
	var total := 0.0
	for industry_id in session.industries.industries():
		total += float(session.industries.industry(industry_id).get("total_produced", 0.0))
	return total


## Every ton of coal in the world, wherever it happens to be standing: heaped at
## a pit, waiting on a platform, aboard a train, or lying in the works that took
## delivery of it.
func _coal_in_valley() -> float:
	var total := 0.0
	for industry_id in session.industries.industries():
		total += session.industries.inventory_of(industry_id, "coal")
	for station_id in session.stations.stations():
		total += session.stations.inventory_of(station_id, "coal")
	for train_id in session.trains.trains():
		for batch in session.trains.batches(train_id):
			if String(batch["cargo"]) == "coal":
				total += float(batch["quantity"])
	return total


func test_the_fare_follows_the_configured_rate() -> void:
	## Revenue is a formula over data, so the data has to be the thing that moves
	## it: double the configured rate and the same haul pays double, with nothing
	## recompiled and no constant touched.
	var def := session.data.cargo_def("coal")
	check_true(def != null, "coal is defined in the data folder")
	var rate := def.base_rate
	var distance := 80.0
	var room := session.cargo.sink_demand(plant_station, "coal")
	var first := session.cargo.deliver(plant_station, "coal", minf(10.0, room), distance, mine_station, 0.0)
	check_true(bool(first["ok"]), "the works takes the first delivery: " + String(first["reason"]))
	var earned := float(first["revenue"])
	check_gt(earned, 0.0, "and it pays for it")

	def.base_rate = rate * 2.0
	var second := session.cargo.deliver(plant_station, "coal", minf(10.0, session.cargo.sink_demand(plant_station, "coal")),
			distance, mine_station, 0.0)
	check_true(bool(second["ok"]), "the same haul, the same distance, the same day")
	check_near(float(second["revenue"]), earned * 2.0,
			"double the configured rate, double the fare", 0.02)
	def.base_rate = rate

	var halved := session.cargo.deliver(plant_station, "coal", minf(10.0, session.cargo.sink_demand(plant_station, "coal")),
			distance, mine_station, 0.0)
	check_near(float(halved["revenue"]), earned, "put the data back and the fare is what it was", 0.02)
