class_name TestTownsAndIndustries
extends TestBase

## Towns and industries are the cargo's origin and destination.  These cases hold
## them to the numbers their own data files declare, and to being reachable as ids
## through the occupancy grid rather than through any scene node.

var session: GameSession


func setup() -> void:
	session = TestSession.create()
	watch_months(session.clock)


func teardown() -> void:
	TestSession.dispose(session)
	session = null


# --- 2.1 towns -------------------------------------------------------------

func test_a_month_yields_each_town_its_declared_cargo() -> void:
	var marlow := TestSession.town_containing(session, "marlow")
	var kestrel := TestSession.town_containing(session, "kestrel")
	check_gt(float(marlow), 0.0, "Marlow is on the map")
	check_gt(float(kestrel), 0.0, "Kestrel Brook is on the map")
	check_eq(session.towns.population_of(marlow), 2400, "Marlow's population came from the map")
	check_near(session.towns.generation_of(marlow, "passengers"), 30.0,
		"Marlow yields 30 passengers a month")
	check_near(session.towns.generation_of(marlow, "mail"), 9.0, "Marlow yields 9 mail a month")
	check_near(session.towns.generation_of(kestrel, "passengers"), 18.0,
		"Kestrel Brook yields 18 passengers a month")
	check_near(session.towns.generation_of(kestrel, "mail"), 6.0,
		"Kestrel Brook yields 6 mail a month")
	check_eq(session.towns.generation_of(marlow, "coal"), 0.0, "a town does not mint coal")

	var station := TestSession.serve(session, session.towns.tile_of(marlow), "Marlow Station")
	check_gt(float(station), 0.0, "a station can be built that serves Marlow")
	if station == 0:
		return
	run_months(session.clock, 1)
	check_near(session.stations.inventory_of(station, "passengers"), 30.0,
		"one simulated month put Marlow's declared 30 passengers in the station", 0.001)
	check_near(session.stations.inventory_of(station, "mail"), 9.0,
		"and its declared 9 letters", 0.001)


# --- 2.2 producers ---------------------------------------------------------

func test_a_mine_grows_its_declared_rate_and_then_saturates() -> void:
	var mine := TestSession.industry_by_definition(session, "coal_mine")
	check_gt(float(mine), 0.0, "the valley has a coal mine")
	check_true(session.industries.is_producer(mine), "and it is a producer")
	check_near(session.industries.inventory_of(mine, "coal"), 0.0, "its yard starts empty", 0.001)
	var full_events: Array = [0]
	session.industries.industry_storage_full.connect(
		func(_id: int, _cargo: String) -> void: full_events[0] += 1)

	run_months(session.clock, 1)
	check_near(session.industries.inventory_of(mine, "coal"), 20.0,
		"a 20-a-month mine grew by 20 in a month", 0.001)
	check_near(float(session.industries.industry(mine).get("produced_this_month", 0.0)), 20.0,
		"and booked 20 of it to the month", 0.001)
	run_months(session.clock, 3)
	check_near(session.industries.inventory_of(mine, "coal"), 80.0,
		"four months of coal, none of it carried away, is 80 tons", 0.001)
	check_false(session.industries.is_full(mine, "coal"), "80 of 90 is not full yet")

	run_months(session.clock, 1)
	check_near(session.industries.inventory_of(mine, "coal"), 90.0,
		"the fifth month stops at the 90-ton yard, it does not overflow", 0.001)
	check_near(float(session.industries.industry(mine).get("produced_this_month", 0.0)), 10.0,
		"only the 10 tons of available room were produced", 0.001)
	check_true(session.industries.is_full(mine, "coal"), "now the yard reports itself full")
	check_gt(float(full_events[0]), 0.0, "the full condition was announced, not swallowed")

	run_months(session.clock, 2)
	check_near(session.industries.inventory_of(mine, "coal"), 90.0,
		"a saturated mine produces nothing more", 0.001)
	check_near(float(session.industries.industry(mine).get("produced_this_month", 0.0)), 0.0,
		"and books nothing", 0.001)


# --- 2.3 consumers ---------------------------------------------------------

func test_a_consumer_books_what_it_was_delivered_and_forgets_it_next_month() -> void:
	var plant := TestSession.industry_by_definition(session, "power_plant")
	check_gt(float(plant), 0.0, "the valley has a power plant")
	check_true(session.industries.is_consumer(plant), "and it is a consumer")
	check_true(session.industries.accepts(plant, "coal"), "coal is its declared input")
	var station := TestSession.serve(session, session.industries.tile_of(plant), "Works Station")
	check_gt(float(station), 0.0, "a station can be built that serves the works")
	if station == 0:
		return
	var outcome := session.cargo.deliver(station, "coal", 30.0, 100.0, station, 0.0)
	check_true(bool(outcome["ok"]), "a 30-ton coal delivery is accepted")
	check_near(float(outcome["delivered"]), 30.0, "all of it", 0.001)
	check_near(session.industries.received_this_month(plant, "coal"), 30.0,
		"the plant's monthly total records exactly the 30 units it was sent", 0.001)
	check_near(session.cargo.sink_demand(station, "coal"), 30.0,
		"its appetite for the rest of the month shrinks to the 30 tons still wanted", 0.001)
	run_months(session.clock, 1)
	check_near(session.industries.received_this_month(plant, "coal"), 0.0,
		"the total belongs to the month it describes", 0.001)


# --- 2.5 source index and occupancy ---------------------------------------

func test_sources_are_resolved_by_id_from_the_grid_with_no_scene_nodes() -> void:
	var marlow := TestSession.town_containing(session, "marlow")
	var kestrel := TestSession.town_containing(session, "kestrel")
	var mine := TestSession.industry_by_definition(session, "coal_mine")
	var plant := TestSession.industry_by_definition(session, "power_plant")

	var marlow_tile := session.towns.tile_of(marlow)
	check_eq(session.world.occupancy_at(marlow_tile), int(WorldGrid.Occupancy.TOWN),
		"a town claims its own ground in the occupancy grid")
	check_eq(session.world.occupancy_entity(marlow_tile), marlow,
		"the tile names the town by id, never by a node path")
	check_eq(session.world.occupancy_at(session.industries.tile_of(mine)),
		int(WorldGrid.Occupancy.INDUSTRY), "an industry claims its site")
	check_eq(session.world.occupancy_entity(session.industries.tile_of(mine)), mine,
		"and is identified by id there too")
	check_eq(session.towns.footprint_of(marlow), Vector2i(3, 3),
		"a town claims one block of ground")
	check_eq(session.towns.footprint_of(kestrel), Vector2i(3, 3),
		"however big it is — a bigger claim would leave no room for a platform")
	check_eq(session.towns.footprint_tiles(marlow).size(), 9, "the block is 9 cells")
	check_eq(session.world.occupancy_at(marlow_tile + Vector2i(1, 1)), int(WorldGrid.Occupancy.TOWN),
		"the corner of the block is town ground as well")
	check_eq(session.world.occupancy_at(marlow_tile + Vector2i(2, 2)), int(WorldGrid.Occupancy.NONE),
		"and one step beyond it is open country again")

	# Selection is camera ray → tile → occupancy id.  Everything past the tile is
	# a data lookup, so no scene node may be involved.
	check_true(session.towns is RefCounted, "the town index is data, not a scene node")
	check_true(session.industries is RefCounted, "the industry index is data, not a scene node")
	check_eq(session.towns.nearest_to(marlow_tile), marlow,
		"a proximity query resolves the town from the grid alone")

	var town_ids := {}
	var industry_ids := {}
	for entry in session.cargo.collect_sources():
		if String(entry["kind"]) == CargoService.SOURCE_TOWN:
			town_ids[int(entry["id"])] = true
		else:
			industry_ids[int(entry["id"])] = true
	check_true(town_ids.has(marlow), "the source index lists Marlow")
	check_true(town_ids.has(kestrel), "and Kestrel Brook")
	check_true(industry_ids.has(mine), "and the colliery")
	check_false(industry_ids.has(plant), "a plant consumes, so it is not a source")

	var station := TestSession.serve(session, marlow_tile, "Marlow Station")
	check_gt(float(station), 0.0, "a station can be built beside the town")
	if station == 0:
		return
	var covered_ids := {}
	for entry in session.stations.covered_sources(station):
		covered_ids[int(entry["id"])] = true
	check_true(covered_ids.has(marlow), "the coverage query resolves the town by id")
	check_ge(float(covered_ids.size()), 1.0, "and the station counts what it serves")
	var offered := {}
	for entry in session.cargo.prospective_sources(station):
		offered[String(entry["cargo"])] = float(entry["amount"])
	check_near(float(offered.get("passengers", 0.0)), 30.0,
		"and the station is told the town's whole monthly output")


func test_town_ground_refuses_track_and_stations_and_says_so() -> void:
	var marlow := TestSession.town_containing(session, "marlow")
	var square := session.towns.tile_of(marlow)
	var spur := TestSession.lay_spur(session, square)
	check_false(bool(spur["ok"]), "track may not be laid through the town square")
	check_has(String(spur["reason"]).to_lower(), "town", "and the reason points at the town")
	var rail := session.builder.build_rail(square, square + Vector2i(0, 6))
	check_true(bool(rail["ok"]) or String(rail["reason"]).to_lower().contains("town"),
		"a planned line either refuses town ground or goes around it, never through it")
	for tile in session.towns.footprint_tiles(marlow):
		check_eq(session.world.rail_mask_at(tile), 0, "no track landed on town ground")
		check_eq(session.world.occupancy_at(tile), int(WorldGrid.Occupancy.TOWN),
			"%s is still claimed by the town" % tile)
	# Give the site its rail access first, so the complaint that surfaces is the
	# ground rather than the missing line.
	TestSession.lay_spur(session, Vector2i(square.x, square.y - 3))
	var preview := session.builder.preview_station("small_station", square - Vector2i(1, 2))
	check_false(bool(preview["ok"]), "a platform may not be dropped across the town square")
	check_has(String(preview["reason"]).to_lower(), "developed ground",
		"and the reason says the ground is already taken")
