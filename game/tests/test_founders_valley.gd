class_name TestFoundersValley
extends TestBase

## The shipped sandbox, held to what it was authored to be: the right entities on
## the right ground, corridors a railway can actually be built along, a float that
## covers the first line, and a month whose numbers come out exactly.

const MAP_ID := "founders_valley"

var session: GameSession


func setup() -> void:
	session = TestSession.create()


func teardown() -> void:
	TestSession.dispose(session)
	session = null


# --- 5.1 the authored document ---------------------------------------------

func test_the_map_document_carries_exactly_what_was_authored() -> void:
	var map := MapDocument.load_map(MAP_ID)
	check_eq(map.errors.size(), 0, "the shipped map loads without a complaint")
	check_eq(map.id, MAP_ID, "and identifies itself")
	check_eq(map.width, 256, "Founder's Valley is 256 tiles wide")
	check_eq(map.height, 256, "and 256 tiles deep")
	check_eq(map.towns.size(), 2, "two towns were authored")
	check_eq(map.industries.size(), 4, "four industries were authored")
	check_eq(map.towns[0]["name"], "Marlow", "Marlow, at the west end")
	check_eq(map.towns[1]["name"], "Kestrel Brook", "and Kestrel Brook, to the east")
	check_eq(map.industries[0]["definition"], "coal_mine", "two coal mines")
	check_eq(map.industries[1]["definition"], "coal_mine", "on the data, not in code")
	check_eq(map.industries[2]["definition"], "power_plant", "and two power plants")
	check_eq(map.industries[3]["definition"], "power_plant", "both named in the map")
	check_eq(map.entity_name(map.industries[0], "?"), "Blackedge Colliery", "each with its own name")
	check_eq(map.town_tile(map.towns[0]), Vector2i(70, 152), "Marlow sits on its authored tile")
	check_eq(map.industry_tile(map.industries[0]), Vector2i(38, 96), "as does the colliery")


func test_the_loaded_map_presents_the_same_counts_to_the_session() -> void:
	check_eq(session.towns.count(), 2, "the session sees both towns")
	check_eq(session.industries.count(), 4, "and all four industries")
	var producers := 0
	var consumers := 0
	for industry_id in session.industries.industries():
		if session.industries.is_producer(industry_id):
			producers += 1
		if session.industries.is_consumer(industry_id):
			consumers += 1
	check_eq(producers, 2, "exactly two of them dig")
	check_eq(consumers, 2, "and exactly two of them burn")
	check_eq(session.world.width, 256, "the grid the session runs on is the authored size")
	check_eq(session.world.total_tiles(), 65536, "every cell is allocated")


func test_the_valley_holds_water_forest_plains_and_high_ground() -> void:
	var map := MapDocument.load_map(MAP_ID)
	var counts := {}
	for index in map.terrain.size():
		var code := map.terrain[index]
		counts[str(code)] = int(counts.get(str(code), 0)) + 1
	var water := int(counts.get(str(int(WorldGrid.Terrain.WATER)), 0))
	var forest := int(counts.get(str(int(WorldGrid.Terrain.FOREST)), 0))
	var plain := int(counts.get(str(int(WorldGrid.Terrain.PLAIN)), 0))
	var rock := int(counts.get(str(int(WorldGrid.Terrain.ROCK)), 0))
	check_eq(water, 1094, "the river and its pools are 1 094 tiles of water")
	check_eq(forest, 13317, "forest covers 13 317 tiles")
	check_eq(plain, 10527, "open plain covers 10 527 tiles")
	check_gt(rock, 5000, "and the hills are built up out of rock")
	var lowest := 255
	var highest := 0
	for index in map.heights.size():
		lowest = mini(lowest, map.heights[index])
		highest = maxi(highest, map.heights[index])
	check_eq(lowest, 0, "the valley floor is at step zero")
	check_ge(float(highest), 12.0, "the ground climbs twelve steps above it")
	check_ge(float((highest - lowest) * WorldConstants.HEIGHT_STEP), 3.0,
		"three world units of relief is enough for a grade to matter")


# --- 5.2 viable corridors --------------------------------------------------

func test_the_valley_offers_at_least_two_mine_to_plant_corridors() -> void:
	var corridors := [
		["Blackedge Colliery", "Valley Gate Works"],
		["Deephilgans Pit", "Kestrel Riverside Works"],
	]
	var viable := 0
	for pair in corridors:
		var mine := _industry_tile_named(pair[0])
		var plant := _industry_tile_named(pair[1])
		check_true(session.world.in_bounds(mine) and session.world.in_bounds(plant),
			"%s and %s are both on the map" % [pair[0], pair[1]])
		# A V1 line cannot sit on the industry itself, so it is planned between the
		# buildable ground beside each site, exactly as a player would lay it.
		var start := _approach_tile(mine)
		var goal := _approach_tile(plant)
		check_true(start != Vector2i(-1, -1), "there is free ground beside " + String(pair[0]))
		check_true(goal != Vector2i(-1, -1), "there is free ground beside " + String(pair[1]))
		if start == Vector2i(-1, -1) or goal == Vector2i(-1, -1):
			continue
		var plan := session.planner.plan(start, goal)
		check_true(bool(plan["ok"]), "a railway can be planned from %s to %s: %s" % [
			pair[0], pair[1], plan["reason"]])
		if not bool(plan["ok"]):
			continue
		var tiles: Array[Vector2i] = plan["tiles"]
		check_gt(float(tiles.size()), 20.0,
			"and the corridor is a real crossing, not a shortcut across the map")
		check_gt(float(plan["cost"]), 0.0, "which costs money to lay")
		viable += 1
	check_ge(float(viable), 2.0, "at least two mine-to-plant corridors are viable")


func test_a_planned_valley_corridor_respects_water_and_grade() -> void:
	var pairs := [
		["Blackedge Colliery", "Valley Gate Works"],
		["Deephilgans Pit", "Kestrel Riverside Works"],
	]
	var checked := 0
	for pair in pairs:
		var start := _approach_tile(_industry_tile_named(pair[0]))
		var goal := _approach_tile(_industry_tile_named(pair[1]))
		var plan := session.planner.plan(start, goal)
		check_true(bool(plan["ok"]), "the crossing is plannable: " + String(plan["reason"]))
		if not bool(plan["ok"]):
			continue
		var tiles: Array[Vector2i] = plan["tiles"]
		var water_hits := 0
		var cliffs := 0
		var jumps := 0
		for index in tiles.size():
			var tile: Vector2i = tiles[index]
			if session.world.is_water(tile):
				water_hits += 1
			if session.world.occupancy_at(tile) != WorldGrid.Occupancy.NONE:
				water_hits += 1
			if index > 0:
				var previous: Vector2i = tiles[index - 1]
				if maxi(absi(tile.x - previous.x), absi(tile.y - previous.y)) != 1:
					jumps += 1
				var step := absi(session.world.height_at(tile) \
					- session.world.height_at(previous))
				if step > 1:
					cliffs += 1
		check_eq(water_hits, 0,
			"no V1 bridge exists and no line is laid on claimed ground: " + String(pair[0]))
		check_eq(cliffs, 0,
			"no cell climbs more than one height step to the next: " + String(pair[0]))
		check_eq(jumps, 0, "and the plan is one unbroken chain of neighbours: " + String(pair[0]))
		check_eq(tiles[0], start, "the plan starts on the ground beside the pit")
		check_eq(tiles[tiles.size() - 1], goal, "and ends beside the works")
		checked += 1
	check_ge(float(checked), 2.0, "both corridors were held to these rules")


# --- 5.3 affordability -----------------------------------------------------

func test_the_configured_float_covers_a_working_line_with_room_to_spare() -> void:
	var opening := session.economy.cash
	check_near(opening, 750000.0, "a new company starts with 750 000")
	var line := TestSession.coal_line(session)
	check_true(bool(line["ok"]),
		"the scripted first line succeeds from that float: " + String(line["reason"]))
	if not bool(line["ok"]):
		return
	check_gt(session.economy.cash, 500000.0,
		"and the whole line — two platforms, the rail, an engine and two hoppers — " \
		+ "leaves more than half the float for expansion")
	check_lt(session.economy.cash, opening, "money was genuinely spent, not waved through")
	check_true(session.economy.is_consistent(), "every cent of it is accounted for in the ledger")
	var spent := opening - session.economy.cash
	check_lt(spent, opening * 0.4, "a first line costs under 40% of the starting capital")


# --- 6.1 a month over the valley -------------------------------------------

func test_one_month_over_the_valley_lands_the_exact_numbers() -> void:
	var line := TestSession.coal_line(session)
	check_true(bool(line["ok"]), "a working line exists: " + String(line["reason"]))
	if not bool(line["ok"]):
		return
	var mine := int(line["mine"])
	var mine_station := int(line["mine_station"])
	var plant_station := int(line["plant_station"])
	check_near(session.stations.inventory_of(mine_station, "coal"), 0.0,
		"the pit's platform starts with nothing waiting", 0.001)

	watch_months(session.clock)
	check_true(run_months(session.clock, 1), "one calendar month of the valley passes")

	check_near(float(session.industries.industry(mine).get("produced_this_month", 0.0)), 20.0,
		"the colliery produced its declared 20 tons", 0.001)
	check_near(session.stations.inventory_of(mine_station, "coal"), 20.0,
		"and all 20 tons reached the one platform that covers it", 0.001)
	check_near(session.stations.inventory_of(plant_station, "coal"), 0.0,
		"the works' own platform received nothing it had no use for", 0.001)
	check_near(session.stations.inventory_of(mine_station, "passengers"), 0.0,
		"neither platform is near a town, so no passengers appeared", 0.001)
	check_near(session.stations.inventory_of(mine_station, "mail"), 0.0,
		"nor any mail", 0.001)
	var waiting := 0
	for station_id in session.stations.stations():
		waiting += session.stations.total_waiting(station_id)
	check_eq(waiting, 20, "the whole valley is holding exactly 20 tons of coal")

	check_true(run_months(session.clock, 3), "three more months of trains running pass")
	var moved: float = session.cargo.delivered_by_cargo().get("coal", 0.0)
	check_gt(moved, 0.0, "and the trains moved coal to the works that wanted it")

	var booked := 0.0
	var entries := 0
	for transaction in session.economy.ledger():
		if transaction.category == "revenue":
			booked += transaction.amount
			entries += 1
	check_gt(booked, 0.0, "the revenue reached the ledger")
	# The ledger stores rounded amounts, the cargo ledger keeps the raw figures,
	# so they may differ by at most half a cent per revenue entry.
	check_near(session.cargo.revenue_total(), booked,
		"the cargo ledger and the money ledger agree on what the freight earned",
		0.005 * float(entries + 1))
	check_true(session.economy.is_consistent(), "with the ledger still balancing")


func _industry_tile_named(label: String) -> Vector2i:
	for industry_id in session.industries.industries():
		if session.industries.name_of(industry_id) == label:
			return session.industries.tile_of(industry_id)
	return Vector2i(-1, -1)


## The nearest tile a rail line could actually start or end on: in bounds, dry
## and unclaimed. Industry and town ground is claimed, so a line always stops
## beside it rather than on it.
func _approach_tile(tile: Vector2i) -> Vector2i:
	for radius in range(1, 7):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var candidate := tile + Vector2i(dx, dy)
				if not session.world.in_bounds(candidate):
					continue
				if session.world.is_water(candidate):
					continue
				if session.world.occupancy_at(candidate) != WorldGrid.Occupancy.NONE:
					continue
				return candidate
	return Vector2i(-1, -1)
