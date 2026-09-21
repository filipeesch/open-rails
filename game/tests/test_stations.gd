class_name TestStations
extends TestBase

## A station is a claim on ground, on rail and on cargo.  One service decides
## all three, and the answers it gives the UI are the answers it acts on.

var session: GameSession
var mine_id: int
var plant_id: int
var mine_tile: Vector2i


func setup() -> void:
	session = TestSession.create()
	mine_id = TestSession.industry_by_definition(session, "coal_mine")
	plant_id = TestSession.industry_by_definition(session, "power_plant")
	mine_tile = session.industries.tile_of(mine_id)


func teardown() -> void:
	TestSession.dispose(session)
	session = null


# --- placement authority ---------------------------------------------------

func test_the_reason_the_ui_shows_is_the_reason_the_build_uses() -> void:
	var water := Vector2i(0, 0)
	for y in session.world.height:
		for x in session.world.width:
			if session.world.terrain_at(Vector2i(x, y)) == WorldGrid.Terrain.WATER:
				water = Vector2i(x, y)
				break
	var preview := session.builder.preview_station("small_station", water)
	var reason := session.stations.placement_reason("small_station", water)
	check_false(bool(preview["ok"]), "a station cannot stand in a river")
	check_eq(String(preview["reason"]), reason, "the ghost and the build give the same verdict")


func test_a_refused_station_lays_down_nothing() -> void:
	var before := session.stations.count()
	var occupied := session.industries.tile_of(mine_id)
	var refused := session.builder.build_station("small_station", occupied, "On top of the mine")
	check_false(bool(refused["ok"]), "the mine's own ground is taken")
	check_eq(session.stations.count(), before, "no station appeared")
	check_eq(session.world.occupancy_at(occupied), WorldGrid.Occupancy.INDUSTRY, "and its occupancy is untouched")


func test_straight_rail_is_the_only_access_a_station_accepts() -> void:
	## Two cells of rail make two dead ends: real track, but nowhere for a train
	## to run.  A station must not accept either as its access.
	var bare := Vector2i(mine_tile.x + 40, mine_tile.y + 40)
	session.rail.commit_segment([Vector2i(bare.x - 1, bare.y), Vector2i(bare.x, bare.y)])
	check_false(session.rail.network.is_straight(Vector2i(bare.x - 1, bare.y)), "both cells are stubs")
	var reason := session.stations.placement_reason("small_station", Vector2i(bare.x - 1, bare.y - 1))
	check_has(reason.to_lower(), "straight", "the refusal says the rail is not a through line")


func test_a_served_station_appears_with_rail_and_catchment() -> void:
	var station_id := TestSession.serve(session, mine_tile, "Mine Head")
	check_neq(station_id, 0, "a station can be built beside the mine")
	var station := session.stations.station(station_id)
	var centre := station["tile"] as Vector2i
	check_lt(WorldCoords.distance_tiles(centre, mine_tile), session.stations.catchment_of(station_id) + 0.001,
		"the station stands inside its own catchment of the mine")
	check_gt(session.stations.catchment_of(station_id), 0.0, "it has a catchment")
	check_neq(session.stations.rail_access_tile(station_id), Vector2i(-1, -1), "and a rail tile to load from")


func test_the_footprint_belongs_to_the_station() -> void:
	var station_id := TestSession.serve(session, mine_tile, "Mine Head")
	var anchor := session.stations.tile_of(station_id)
	var def := session.stations.def_of(station_id)
	check_eq(session.world.occupancy_at(anchor), WorldGrid.Occupancy.STATION, "the anchor is station ground")
	check_eq(session.world.occupancy_entity(anchor), station_id, "and it knows whose")
	check_ge(float(def.footprint.x), 2.0, "the footprint spans more than one tile")
	var second := session.builder.build_station("small_station", anchor + Vector2i(1, 0), "Too close")
	check_false(bool(second["ok"]), "a neighbour cannot be dropped on the same ground")


# --- catchment -------------------------------------------------------------

func test_a_station_covers_the_source_it_was_built_for() -> void:
	var station_id := TestSession.serve(session, mine_tile, "Mine Head")
	var covered := session.stations.covered_sources(station_id)
	var covers_mine := false
	for entry in covered:
		if String(entry["kind"]) == CargoService.SOURCE_INDUSTRY and int(entry["id"]) == mine_id:
			covers_mine = true
	check_true(covers_mine, "the mine is inside this station's catchment")
	var sources := session.cargo.collect_sources()
	for source in sources:
		if String(source["kind"]) == CargoService.SOURCE_INDUSTRY and int(source["id"]) == mine_id:
			var covering := session.stations.stations_covering(source)
			check_true(covering.has(station_id), "the allocator sees the same coverage the station reports")


func test_two_stations_sharing_a_source_are_both_offered() -> void:
	var town_id := TestSession.town_containing(session, "Marlow")
	var town_tile := session.towns.tile_of(town_id)
	var first := TestSession.serve(session, town_tile, "Marlow East")
	var second := TestSession.station_for_tile(session, town_tile, "Marlow West")
	check_neq(first, 0, "the first station serves the town")
	check_neq(second, 0, "a second station can serve it too")
	var covering := session.stations.stations_covering({
		"kind": CargoService.SOURCE_TOWN, "id": town_id,
		"tile": town_tile, "cargo": "passengers", "rate": 30.0,
	})
	check_true(covering.has(first) and covering.has(second), "the town's cargo is offered to both")


# --- inventory -------------------------------------------------------------

func test_storage_is_a_ceiling_not_a_suggestion() -> void:
	var station_id := TestSession.serve(session, mine_tile, "Mine Head")
	var limit := session.stations.storage_limit(station_id, "coal")
	var taken := session.stations.add_cargo(station_id, "coal", limit + 500.0)
	check_le(taken, limit, "the station refuses cargo beyond its storage")
	check_near(session.stations.inventory_of(station_id, "coal"), limit, "and holds exactly the ceiling", 0.001)


func test_a_station_cannot_give_what_it_does_not_have() -> void:
	var station_id := TestSession.serve(session, mine_tile, "Mine Head")
	session.stations.add_cargo(station_id, "coal", 30.0)
	var removed := session.stations.take_cargo(station_id, "coal", 100.0)
	check_le(removed, 30.0, "nothing is taken that was not there")
	check_ge(session.stations.inventory_of(station_id, "coal"), 0.0, "inventory never goes negative")


func test_removal_frees_the_ground_it_claimed() -> void:
	var station_id := TestSession.serve(session, mine_tile, "Mine Head")
	var anchor := session.stations.tile_of(station_id)
	check_true(session.stations.remove_station(station_id), "the station is removed")
	check_eq(session.stations.count(), 0, "and the register forgets it")
	check_neq(session.world.occupancy_at(anchor), WorldGrid.Occupancy.STATION, "the ground is public again")


func test_track_a_station_depends_on_cannot_be_pull_up() -> void:
	var station_id := TestSession.serve(session, mine_tile, "Mine Head")
	var access := session.stations.rail_access_tile(station_id)
	var blocked := session.builder.remove_track([access])
	check_false(bool(blocked["ok"]), "the access rail is protected while the station stands")
	check_has(String(blocked["reason"]).to_lower(), "station", "and the reason names the station")
	check_true(session.world.is_rail(access), "the rail is still there")


func test_a_station_may_stand_with_nothing_in_its_catchment() -> void:
	## Deliberate: a line may be built ahead of the traffic it will carry.  What
	## must not happen is a station pretending to serve something it cannot see.
	var far := Vector2i(mine_tile.x + 60, mine_tile.y + 40)
	session.rail.commit_segment([
		Vector2i(far.x - 2, far.y), Vector2i(far.x - 1, far.y),
		Vector2i(far.x, far.y), Vector2i(far.x + 1, far.y)])
	var anchor := Vector2i(far.x - 1, far.y - 2)
	var built := session.builder.build_station("small_station", anchor, "Empty Siding")
	if bool(built["ok"]):
		check_eq(session.stations.covered_sources(int(built["id"])).size(), 0,
			"an empty catchment reports as empty, not as a service")
	else:
		check_false(session.world.terrain_at(anchor) == WorldGrid.Terrain.WATER,
			"the probe site was dry ground: " + String(built["reason"]))


func test_station_names_are_unique_enough_to_tell_apart() -> void:
	var first := TestSession.serve(session, mine_tile, "")
	var second := TestSession.serve(session, session.industries.tile_of(plant_id), "")
	check_neq(first, 0, "first unnamed station built")
	check_neq(second, 0, "second unnamed station built")
	check_neq(session.stations.name_of(first), session.stations.name_of(second), "auto-naming gives them different names")


func test_a_station_beside_no_rail_says_so_instead_of_pointing_at_the_origin() -> void:
	## A hand-authored or half-loaded map can put a station beside ground that
	## carries no rail.  "No access" must not be reported as a real tile.
	var station_id := TestSession.serve(session, mine_tile, "Mine Head")
	var access := session.stations.rail_access_tile(station_id)
	session.world.set_rail_cell(access, false)
	session.world.clear_occupancy(access)
	for tile in TestSession.spur_tiles(Vector2i(mine_tile.x, mine_tile.y - 3)):
		session.world.set_rail_cell(tile, false)
		session.world.clear_occupancy(tile)
	check_false(session.stations.has_rail_access(station_id), "with its rail gone it has no access")
	check_eq(session.stations.rail_access_tile(station_id), Vector2i(-1, -1),
			"and that is reported as no tile at all, not as (0, 0)")
	check_eq(session.stations.station_at_rail(Vector2i(0, 0)), 0,
			"it does not claim the origin of the map as its platform")


# --- every refusal the player can meet ---------------------------------------

func test_every_reason_a_station_can_be_refused_is_reachable() -> void:
	## One claim per refusal.  A reason no test can reach is a reason the game
	## cannot actually mean, and a ghost that shows it would be lying.
	check_has(session.stations.placement_reason("maglev_depot", mine_tile), "Unknown station",
		"an unknown class says so")
	check_has(session.stations.placement_reason("small_station", Vector2i(-4, -4)), "leaves the map",
		"off the western edge")
	check_has(session.stations.placement_reason("small_station", Vector2i(255, 255)), "leaves the map",
		"and off the eastern one")
	check_has(session.stations.placement_reason("small_station", Vector2i(4, 4)), "rail",
		"open country with no line beside it names the missing rail")

	var site := _prepared_site()
	check_eq(session.stations.placement_reason("small_station", site), "",
		"the probe site is legal before anything is wrong with it")
	check_has(session.stations.placement_reason("small_station", site + Vector2i(0, -2)), "track",
		"a platform may not bury the line it serves")

	var flooded := site + Vector2i(1, 1)
	var dry := session.world.terrain_at(flooded)
	session.world.set_terrain(flooded, WorldGrid.Terrain.WATER)
	check_has(session.stations.placement_reason("small_station", site), "water",
		"a flooded corner of the footprint says water")
	session.world.set_terrain(flooded, dry)
	check_eq(session.stations.placement_reason("small_station", site), "",
		"drain it and the same site is legal again")

	var built := session.builder.build_station("small_station", site, "Probe Siding")
	check_true(bool(built["ok"]), "the legal site commits: " + String(built["reason"]))
	check_has(session.stations.placement_reason("small_station", site), "another station",
		"the ground it took is refused to a second platform")


## Station building is the one purchase whose price the player reads before
## paying, so the ghost's number and the ledger's number must be one number.
func test_a_station_costs_what_the_ghost_priced_and_nothing_when_refused() -> void:
	var site := _prepared_site()
	var ghost := session.builder.preview_station("small_station", site)
	check_true(bool(ghost["ok"]), "the ghost is legal: " + String(ghost["reason"]))
	var price := float(ghost["cost"])
	check_near(price, 20000.0, "a small station is priced at 20 000")

	var before := session.economy.cash
	var rows := session.economy.ledger().size()
	var refused := session.builder.build_station("small_station", site + Vector2i(0, -2), "On the line")
	check_false(bool(refused["ok"]), "the illegal site is refused")
	check_near(session.economy.cash, before, "and not one cent moved")
	check_eq(session.economy.ledger().size(), rows, "with no ledger entry either")

	var committed := session.builder.build_station("small_station", site, "Priced Siding")
	check_true(bool(committed["ok"]), "the legal site commits")
	check_near(session.economy.cash, before - price, "and the charge is exactly the previewed price")
	var entries: Array[EconomyService.Transaction] = session.economy.ledger()
	check_eq(entries.size(), rows + 1, "booked as a single ledger entry")
	var last := entries[entries.size() - 1]
	check_eq(last.category, EconomyService.CATEGORY_STATION, "against the station category")
	check_near(absf(last.amount), price, "for the previewed amount")
	check_has(last.description, "Priced Siding", "and the ledger says which platform it bought")


func test_the_catchment_reaches_four_tiles_and_no_further() -> void:
	var station_id := TestSession.serve(session, mine_tile, "Mine Head")
	var centre := session.stations.tile_of(station_id)
	check_near(session.stations.catchment_of(station_id), 4.0, "the V1 catchment is four tiles")
	var source := {"kind": "industry", "id": mine_id, "tile": centre, "cargo": "coal", "rate": 20.0}

	source["tile"] = centre + Vector2i(0, -3)
	check_true(session.stations.stations_covering(source).has(station_id),
		"three tiles out is still inside the catchment")
	source["tile"] = centre + Vector2i(0, -4)
	check_true(session.stations.stations_covering(source).has(station_id),
		"four tiles out is the edge, and the edge counts")
	source["tile"] = centre + Vector2i(0, -5)
	check_false(session.stations.stations_covering(source).has(station_id),
		"five tiles out is out of reach")
	source["tile"] = centre + Vector2i(3, -3)
	check_false(session.stations.stations_covering(source).has(station_id),
		"a diagonal at 4.24 tiles is not covered either")

	## The service answers coverage out of a bucket grid, not by walking every
	## station it has ever seen.  The grid must answer exactly what measuring
	## each station by hand answers — including across a bucket boundary.
	var bucketed := 0
	var measured := 0
	for offset_y in range(-8, 9):
		for offset_x in range(-8, 9):
			source["tile"] = centre + Vector2i(offset_x, offset_y)
			if session.stations.stations_covering(source).has(station_id):
				bucketed += 1
			if WorldCoords.distance_tiles(centre, centre + Vector2i(offset_x, offset_y)) <= 4.0:
				measured += 1
	check_eq(bucketed, measured, "the bucket index agrees with measuring every station")
	check_gt(float(measured), 40.0, "and that is a real catchment, not an empty overlap")


func test_the_ghost_draws_the_catchment_the_station_would_have() -> void:
	## Coverage is promised before the player commits and delivered after.  If the
	## two are computed differently, a ghost that showed a mine can stand somewhere
	## that turns round and does not see it.
	var site := _prepared_site()
	var ghost_tiles := session.stations.catchment_tiles_for("small_station", site)
	check_gt(float(ghost_tiles.size()), 40.0, "a four-tile catchment highlights a real area")
	check_false(ghost_tiles.has(mine_tile), "standing nowhere near it, it does not claim the mine")
	check_eq(session.stations.catchment_tiles_for("maglev_depot", site).size(), 0,
		"an unknown class highlights nothing rather than guessing")

	var served := TestSession.serve(session, mine_tile, "Mine Head")
	var served_anchor: Vector2i = session.stations.station(served)["anchor"]
	var built_tiles := session.stations.catchment_tiles(served)
	built_tiles.sort()
	var ghost_at_served := session.stations.catchment_tiles_for("small_station", served_anchor)
	ghost_at_served.sort()
	check_eq(ghost_at_served, built_tiles,
		"a ghost at that anchor and the platform built there cover the same ground")
	check_true(built_tiles.has(mine_tile), "and the station beside the mine really does see it")
	check_eq(session.stations.catchment_tiles(9999).size(), 0,
		"a station that does not exist covers nothing")


func test_a_loaded_train_leaves_the_station_balanced_to_the_ton() -> void:
	var station_id := TestSession.serve(session, mine_tile, "Mine Head")
	session.stations.add_cargo(station_id, "coal", 40.0)
	session.stations.add_cargo(station_id, "passengers", 12.0)
	check_near(session.stations.inventory_of(station_id, "coal"), 40.0, "40 tons on the ground")
	check_eq(session.stations.total_waiting(station_id), 52, "with 52 units waiting in total")

	var taken := session.stations.take_cargo(station_id, "coal", 25.0)
	check_near(taken, 25.0, "the train is given the 25 tons it asked for")
	check_near(session.stations.inventory_of(station_id, "coal"), 15.0,
		"and exactly 15 tons remain, with no rounding tail left behind")
	check_eq(session.stations.total_waiting(station_id), 27, "the platform total follows it down")
	check_near(session.stations.inventory_of(station_id, "passengers"), 12.0,
		"the other cargo on the same platform is untouched")

	check_near(session.stations.take_cargo(station_id, "coal", 900.0), 15.0,
		"asking for more than is there takes what is, not what was asked")
	check_near(session.stations.take_cargo(station_id, "coal", 5.0), 0.0,
		"and from empty ground nothing can be lifted")


func test_renaming_a_station_leaves_the_train_running_its_route() -> void:
	var line := TestSession.coal_line(session)
	check_true(bool(line["ok"]), "a working line exists: " + String(line["reason"]))
	var plant_station := int(line["plant_station"])
	var route_id := int(line["route"])
	var train_id := int(line["train"])

	session.stations.rename(plant_station, "Kestrel Riverside Works")
	check_eq(session.stations.name_of(plant_station), "Kestrel Riverside Works",
		"the platform answers to its new name")
	check_eq(int(session.stations.station(plant_station).get("id", 0)), plant_station,
		"but it is the same entity, under the same id")
	check_true(_stop_ids(route_id).has(plant_station), "the route still stops there")
	check_true(session.routes.is_valid(route_id), "and the route is still valid")
	check_neq(session.trains.route_of(train_id), 0, "with the train still working it")

	watch_months(session.clock)
	check_true(run_months(session.clock, 2), "two months of the calendar pass")
	check_true(run_months(session.clock, 2), "and two more, with the trains still running")
	var moved: float = session.cargo.delivered_by_cargo().get("coal", 0.0)
	check_gt(moved, 0.0, "coal is still arriving at the works under its new name")
	check_true(session.economy.is_consistent(), "and the ledger still balances")


func test_undo_asks_the_session_before_tearing_a_station_down() -> void:
	## Undo is a promise the builder cannot always keep: a platform a train has
	## been routed through is no longer the thing that was just built.  So the
	## session is asked, once per train that carries a route — which is precisely
	## where a mistyped check used to raise a script error and expire every
	## station undo in the world in silence.
	var line := TestSession.coal_line(session)
	check_true(bool(line["ok"]), "a world with a routed train exists: " + String(line["reason"]))
	var site := _prepared_site()
	var before := session.economy.cash
	var built := session.builder.build_station("small_station", site, "Undo Siding")
	check_true(bool(built["ok"]), "a fresh platform goes up: " + String(built["reason"]))
	var station_id := int(built["id"])
	check_near(session.economy.cash, before - 20000.0, "and was paid for")

	check_true(session.undo.can_undo(), "the builder offers to take it back")
	check_eq(session.undo.next_label(), "Build Undo Siding",
		"naming the thing it would take back")
	check_eq(session.undo.undo(), "Build Undo Siding", "the undo runs, with no script error")
	check_false(session.stations.has_station(station_id), "and the platform is gone")
	check_near(session.economy.cash, before, "with the money handed back in full")
	check_true(session.economy.is_consistent(), "the ledger still tells the truth")


func _stop_ids(route_id: int) -> Array[int]:
	var ids: Array[int] = []
	for stop in session.routes.stops(route_id):
		ids.append(int(stop["station_id"]))
	return ids


## Ground far enough from every authored entity that nothing else can be the
## reason a probe is refused, with a through line beside it — the one setting in
## which a placement complaint is genuinely about the thing being tested.
func _prepared_site() -> Vector2i:
	for y in range(20, 232, 3):
		for x in range(20, 232, 3):
			var anchor := Vector2i(x, y)
			if not _quiet_ground(anchor):
				continue
			if not bool(TestSession.lay_spur(session, anchor)["ok"]):
				continue
			var site := anchor + Vector2i(0, 2)
			if session.stations.placement_reason("small_station", site) != "":
				continue
			return site
	return Vector2i(-1, -1)


func _quiet_ground(tile: Vector2i) -> bool:
	for industry_id in session.industries.industries():
		if WorldCoords.distance_tiles(tile, session.industries.tile_of(industry_id)) < 24.0:
			return false
	for town_id in session.towns.towns():
		if WorldCoords.distance_tiles(tile, session.towns.tile_of(town_id)) < 24.0:
			return false
	return true
