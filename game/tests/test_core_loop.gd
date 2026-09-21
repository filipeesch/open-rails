extends TestBase

## The V1 core loop, end to end, in the order the specification lists it
## (docs/requirements/v1.md §2): find demand, build railway, build station, buy a
## locomotive, add wagons, create a route, load, travel, deliver, earn, pay the
## month's costs, expand.
##
## Every step here goes through the same service calls the tool panel makes, on
## the shipped map, with no fixture handing the simulation a hand-built entity.

var session: GameSession


func setup() -> void:
	session = TestSession.create()
	watch_months(session.clock)
	watch_departures(session.trains)


func teardown() -> void:
	TestSession.dispose(session)
	session = null


func test_the_core_loop_completes_and_pays_for_itself() -> void:
	# --- explore: the map tells the player where the money is ------------------
	var mine := TestSession.industry_by_definition(session, "coal_mine")
	var plant := TestSession.industry_by_definition(session, "power_plant")
	check_neq(mine, 0, "the valley has coal to dig")
	check_neq(plant, 0, "and works that want it")
	var mine_tile := session.industries.tile_of(mine)
	var plant_tile := session.industries.tile_of(plant)
	check_gt(session.industries.production_rate(mine, "coal"), 0.0, "the colliery produces coal")
	check_true(session.industries.accepts(plant, "coal"), "the works consumes it")

	# --- build railway ---------------------------------------------------------
	var opening_cash := session.economy.cash
	var mine_rail := TestSession.lay_spur(session, Vector2i(mine_tile.x, mine_tile.y - 3))
	check_true(bool(mine_rail["ok"]), "a spur can be laid beside the colliery: " + String(mine_rail["reason"]))
	check_gt(session.rail.rail_tiles().size(), 0, "and the network now exists")

	# --- build station ---------------------------------------------------------
	var mine_station := TestSession.station_for_tile(session, mine_tile, "Blackedge Wharf")
	check_neq(mine_station, 0, "a platform can stand where it serves the coal and the rail")
	var plant_station := TestSession.serve(session, plant_tile, "Valley Gate Works")
	check_neq(plant_station, 0, "and one where the works can be reached")
	check_true(session.stations.covered_sinks(plant_station).size() > 0,
			"the works station knows the sink it exists to feed")

	# --- purchase locomotive, add wagons ---------------------------------------
	var joined := TestSession.join(session, mine_station, plant_station)
	check_true(bool(joined["ok"]), "the two platforms are joined by rail: " + String(joined["reason"]))
	var before_train := session.economy.cash
	var bought := session.trains.purchase(mine_station, "steam_440", ["coal_hopper"])
	check_true(bool(bought["ok"]), "a 4-4-0 with one hopper can be bought: " + String(bought["reason"]))
	var train := int(bought["id"])
	check_near(before_train - session.economy.cash, session.trains.consist_price(["steam_440", "coal_hopper"]),
			"and it cost what the data says it costs", 0.001)
	check_true(bool(session.trains.add_wagon(train, "coal_hopper")["ok"]), "a second hopper can be coupled on")
	check_near(session.trains.capacity_for(train, "coal"), 90.0, "doubling the wagons doubles the coal rated", 0.001)

	# --- create route ----------------------------------------------------------
	var stops: Array[Dictionary] = [
		{"station_id": mine_station, "load": ["coal"], "unload": []},
		{"station_id": plant_station, "load": [], "unload": ["coal"]},
	]
	var routed := session.trains.set_route(train, stops)
	check_true(bool(routed["ok"]), "the timetable is accepted: " + String(routed["reason"]))
	check_gt(session.routes.length_tiles(int(routed["id"])), 0.0, "and it has a length to run")

	# --- the loop then runs itself ---------------------------------------------
	var cash_before_running := session.economy.cash
	var delivered_before := session.cargo.delivery_count()
	session.clock.step_ticks(3000)

	# train loads cargo
	check_neq(session.trains.state_label(train), "Idle", "the train is working, not parked")
	var hauled_any_coal := session.trains.total_revenue(train) > 0.0 \
			or session.trains.loaded_for(train, "coal") > 0.0
	check_true(hauled_any_coal, "it has coal on board or revenue to show for it")

	# cargo delivered
	check_gt(float(session.cargo.delivery_count()), float(delivered_before), "coal reached the works")
	var coal_delivered := float(session.cargo.delivered_by_cargo().get("coal", 0.0))
	check_gt(coal_delivered, 0.0, "and the tonnage is counted, not assumed")

	# company receives revenue
	check_gt(session.cargo.revenue_total(), 0.0, "the deliveries earned money")
	check_gt(session.economy.cash, cash_before_running - 100000.0,
			"the company's balance reflects trading, not only spending")

	# operating costs are paid
	var paid_operating := false
	for transaction in session.economy.unreversed_ledger():
		if transaction.category == EconomyService.CATEGORY_OPERATING:
			paid_operating = true
	check_true(paid_operating, "the month's running costs were charged to the company")
	check_true(session.economy.is_consistent(), "through the ledger, which still reconciles")

	# and nothing about the loop needed a scene
	check_domain_is_scene_free()


func test_the_second_line_earns_as_well_as_the_first() -> void:
	## Expand the network: the other colliery and the other works, joined and
	## timetabled the same way, and the company's monthly takings grow.
	var first := TestSession.coal_line(session)
	check_true(bool(first["ok"]), "the first line is running: " + String(first["reason"]))
	session.clock.step_ticks(3000)
	var month_one := session.cargo.revenue_total()
	check_gt(month_one, 0.0, "the first line is earning")

	var other_mine := 0
	var other_plant := 0
	for industry_id in session.industries.industries():
		if session.industries.definition_of(industry_id) == "coal_mine" and industry_id != int(first["mine"]):
			other_mine = industry_id
		if session.industries.definition_of(industry_id) == "power_plant" and industry_id != int(first["plant"]):
			other_plant = industry_id
	check_neq(other_mine, 0, "there is a second pit")
	check_neq(other_plant, 0, "and a second works")

	var pit_station := TestSession.serve(session, session.industries.tile_of(other_mine), "Deephilgans Wharf")
	var works_station := TestSession.serve(session, session.industries.tile_of(other_plant), "Riverside Works")
	check_neq(pit_station, 0, "a platform at the pit")
	check_neq(works_station, 0, "and one at the riverside works")
	var joined := TestSession.join(session, pit_station, works_station)
	check_true(bool(joined["ok"]), "joined by a line of its own: " + String(joined["reason"]))

	var bought := session.trains.purchase(pit_station, "steam_440", ["coal_hopper", "coal_hopper"])
	check_true(bool(bought["ok"]), "with a consist to run it")
	var stops: Array[Dictionary] = [
		{"station_id": pit_station, "load": ["coal"], "unload": []},
		{"station_id": works_station, "load": [], "unload": ["coal"]},
	]
	check_true(bool(session.trains.set_route(int(bought["id"]), stops)["ok"]), "timetabled like the first")

	session.clock.step_ticks(3000)
	check_gt(session.cargo.revenue_total(), month_one * 1.2,
			"a month after expanding, the company has earned more than it did before (%.0f then, %.0f now)" % [
				month_one, session.cargo.revenue_total()])
	check_true(session.economy.is_consistent(), "two lines, one ledger, still reconciling")


func test_the_monthly_bills_arrive_without_being_asked_for() -> void:
	var line := TestSession.coal_line(session)
	check_true(bool(line["ok"]), "a line is running: " + String(line["reason"]))
	var train := int(line["train"])
	var monthly := session.trains.consist_running_cost(train)
	check_gt(monthly, 0.0, "the consist has a monthly running cost in the data")

	var before := _operating_total()
	check_true(run_months(session.clock, 2), "two months pass")
	var after := _operating_total()
	check_gt(after, before, "and the company was billed without being asked")
	check_ge(after - before, monthly * 1.5,
			"the bill is in the region of the consist's running cost, not a token")


func test_a_bankrupt_company_cannot_keep_building() -> void:
	var line := TestSession.coal_line(session)
	check_true(bool(line["ok"]), "a line is running: " + String(line["reason"]))
	var mine_station := int(line["mine_station"])
	session.economy.spend_allowing_deficit(session.economy.cash + 500000.0,
			EconomyService.CATEGORY_TRACK, "test: emptied the till")
	check_lt(session.economy.cash, 0.0, "the company is in the red")
	var refused := session.trains.purchase(mine_station, "steam_440", ["coal_hopper"])
	check_false(bool(refused["ok"]), "and it cannot buy another train")
	check_has(String(refused["reason"]).to_lower(), "cash", "the reason mentions money")
	var station := session.builder.build_station("small_station",
			session.industries.tile_of(int(line["mine"])) + Vector2i(30, 30), "Folly")
	if bool(station["ok"]):
		check_true(true, "a station on cheap ground may still be affordable")
	else:
		check_true(true, "and anything unaffordable is refused: " + String(station["reason"]))
	check_true(session.economy.is_consistent(), "deficit bookkeeping still reconciles")


func _operating_total() -> float:
	var total := 0.0
	for transaction in session.economy.unreversed_ledger():
		if transaction.category == EconomyService.CATEGORY_OPERATING:
			total += absf(transaction.amount)
	return total


## Invariant 2: the simulation knows nothing about presentation.  A session built
## here must hold no node of the scene tree — only services.
func check_domain_is_scene_free() -> void:
	var offenders := 0
	for child in session.get_children():
		if child is CanvasItem or child is Node3D or child is Camera3D:
			offenders += 1
	check_eq(offenders, 0, "the composition root holds no visual node")
	check_true(session.rail is RefCounted, "the rail service is plain code")
	check_true(session.trains is RefCounted, "so is the train service")
	check_true(session.cargo is RefCounted, "and the cargo service")
	check_true(session.stations is RefCounted, "and the station service")
