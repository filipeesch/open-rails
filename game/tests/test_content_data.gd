class_name TestContentData
extends TestBase

## `game/data/` is the only place definitions live (invariant 7), so the loader
## has to do two jobs: refuse a definition that names something that does not
## exist, and accept brand-new content without a line of transport code
## changing.  Both are checked here against the real registry.

var session: GameSession


func setup() -> void:
	session = TestSession.create()


func teardown() -> void:
	TestSession.dispose(session)
	session = null


# --- 1.1 validation --------------------------------------------------------

func test_a_wagon_naming_an_unknown_cargo_names_its_file() -> void:
	var registry := DataRegistry.new()
	check_true(registry.load_all(), "the shipped data loads clean")
	var path := "user://bad_wagon.json"
	check_true(write_json(path, {
		"id": "ghost_van", "type": "wagon", "cargo": "unobtainium",
		"price": 1200.0, "capacity": 20,
	}), "the bad wagon definition was written")
	var result := registry.load_definition_file(path)
	check_false(bool(result["ok"]), "a wagon carrying a cargo that does not exist is refused")
	check_eq(String(result["kind"]), "wagon", "the loader identified the file as rolling stock")
	check_has(String(result["reason"]), "bad_wagon.json", "the reason names the offending file")
	check_has(String(result["reason"]), "unobtainium", "the reason names the cargo it could not resolve")
	check_false(registry.rolling_stock.has("ghost_van"), "the refused wagon left nothing behind")


func test_an_industry_naming_an_unknown_cargo_names_its_file() -> void:
	var registry := DataRegistry.new()
	check_true(registry.load_all(), "the shipped data loads clean")
	var path := "user://bad_industry.json"
	check_true(write_json(path, {
		"id": "ghost_works", "display_name": "Ghost Works",
		"produces": [{"cargo": "unobtainium", "rate_per_month": 5.0, "storage_capacity": 40}],
		"accepts": [],
	}), "the bad industry definition was written")
	var result := registry.load_definition_file(path)
	check_false(bool(result["ok"]), "an industry flowing a cargo that does not exist is refused")
	check_eq(String(result["kind"]), "industry", "the loader identified the file as an industry")
	check_has(String(result["reason"]), "bad_industry.json", "the reason names the offending file")
	check_has(String(result["reason"]), "unobtainium", "the reason names the cargo it could not resolve")
	check_false(registry.cargo.has("unobtainium"), "the phantom cargo is not in the registry")
	check_false(registry.industries.has("ghost_works"), "the refused industry left nothing behind")
	check_eq(registry.industries.size(), 2, "only the two shipped industry classes remain")


func test_a_definition_is_classified_by_its_own_shape() -> void:
	# Only rolling stock carries a `type`, so an industry or station file has to
	# be recognised from its fields or it would be loaded as a wagon.
	check_eq(DataRegistry.classify({"base_rate": 1.0}), "cargo", "base_rate means cargo")
	check_eq(DataRegistry.classify({"produces": [], "accepts": []}), "industry", "flow lists mean industry")
	check_eq(DataRegistry.classify({"catchment_tiles": 4.0}), "station", "a catchment means a station")
	check_eq(DataRegistry.classify({"type": "locomotive"}), "locomotive", "a type means rolling stock")
	check_eq(DataRegistry.classify({"id": "plain_van"}), "wagon", "rolling stock defaults to wagon")


# --- 1.2 cargo tuning ------------------------------------------------------

func test_coal_is_far_less_time_sensitive_than_passengers() -> void:
	var coal := session.data.cargo_def("coal")
	var pax := session.data.cargo_def("passengers")
	check_true(coal != null and pax != null, "both cargos are defined")
	if coal == null or pax == null:
		return
	check_near(coal.base_rate, 8.0, "coal pays 8 per unit per tile")
	check_near(pax.base_rate, 14.0, "passengers pay 14 per unit per tile")
	check_gt(pax.time_sensitivity, 0.1, "passengers are perishable")
	check_near(coal.time_sensitivity, 0.01, "coal barely notices the clock")
	check_lt(coal.time_sensitivity, pax.time_sensitivity / 5.0,
		"coal must be materially less time sensitive than passengers, not marginally")
	check_eq(coal.unit_label, "tons", "coal is counted in tons")
	check_eq(pax.unit_label, "pax", "passengers are counted in heads")
	check_ge(coal.quality_floor, 0.9, "coal keeps almost all its worth however long it sits")


# --- 1.3 station and industry definitions ----------------------------------

func test_station_definition_parses_its_declared_shape() -> void:
	var def: DataRegistry.StationDef = session.data.stations.get("small_station")
	check_true(def != null, "the small station is defined")
	if def == null:
		return
	check_near(def.cost, 20000.0, "a small station costs 20 000")
	check_eq(def.footprint, Vector2i(3, 2), "the footprint is 3 x 2 tiles")
	check_near(def.catchment_tiles, 4.0, "the catchment is four tiles")
	check_eq(def.storage_per_cargo, 120, "storage is 120 units per cargo")
	check_true(def.requires_straight_rail, "a station needs straight rail to be reachable")
	check_eq(def.rail_search_radius, 1,
			"it couples to the line beside its yard, not to one it merely overlooks")


func test_industry_definitions_parse_their_declared_flows() -> void:
	var mine: DataRegistry.IndustryDef = session.data.industries.get("coal_mine")
	var plant: DataRegistry.IndustryDef = session.data.industries.get("power_plant")
	check_true(mine != null and plant != null, "both industry classes are defined")
	if mine == null or plant == null:
		return
	check_eq(mine.produces.size(), 1, "a mine has one output")
	check_eq(String(mine.produces[0]["cargo"]), "coal", "that output is coal")
	check_near(float(mine.produces[0]["rate_per_month"]), 20.0, "a mine delivers 20 a month")
	check_near(float(mine.produces[0]["storage_capacity"]), 90.0, "a mine stores 90 tons")
	check_eq(mine.accepts.size(), 0, "a mine takes nothing in")
	check_eq(plant.produces.size(), 0, "a plant ships nothing out")
	check_eq(plant.accepts.size(), 1, "a plant has one input")
	check_eq(String(plant.accepts[0]["cargo"]), "coal", "that input is coal")
	check_near(float(plant.accepts[0]["capacity_per_month"]), 60.0, "a plant burns 60 a month")
	check_eq(mine.footprint, Vector2i(3, 3), "the mine holds its declared footprint")
	check_eq(plant.footprint, Vector2i(4, 3), "the plant holds its declared footprint")


# --- 2.4 multi-input, multi-output industry --------------------------------

func test_an_iron_and_coal_to_steel_works_needs_a_data_file_and_nothing_else() -> void:
	for path in _write_synthetic_cargos():
		var loaded := session.data.load_definition_file(path)
		check_true(bool(loaded["ok"]), "synthetic cargo " + path + " registers from data alone")
	var works := session.data.load_definition_file(_write_iron_works())
	check_true(bool(works["ok"]), "the iron works registers from data alone")
	check_eq(String(works["kind"]), "industry", "the loader classified it as an industry")
	if not bool(works["ok"]):
		return
	var foundry := session.industries.add("iron_works", Vector2i(214, 44), "Valley Foundry",
		session.ids.next_id())
	check_gt(float(foundry), 0.0, "the synthetic industry joined the live session")
	if foundry == 0:
		return
	check_true(session.industries.is_producer(foundry), "it produces, because its data list says so")
	check_true(session.industries.is_consumer(foundry), "and it consumes, because its data list says so")
	check_true(session.industries.accepts(foundry, "iron_ore"), "input one came from the file")
	check_true(session.industries.accepts(foundry, "coal"), "input two came from the file")
	check_near(session.industries.capacity_of(foundry, "steel"), 60.0, "its output shed holds 60")
	session.industries.consume(foundry, "iron_ore", 14.0)
	session.industries.consume(foundry, "coal", 6.0)
	check_near(session.industries.received_this_month(foundry, "iron_ore"), 14.0,
		"the first input is recorded against the month")
	check_near(session.industries.received_this_month(foundry, "coal"), 6.0,
		"the second input is recorded against the same month")
	watch_months(session.clock)
	check_true(run_months(session.clock, 1), "one calendar month rolled over")
	check_near(session.industries.inventory_of(foundry, "steel"), 12.0,
		"it manufactured its declared 12 tons of steel, with no code written for steel", 0.001)
	check_near(session.cargo.quality("steel", 400.0), 0.9,
		"the new cargo decays to the floor its own file declared", 0.02)


# --- helpers ---------------------------------------------------------------

func _write_synthetic_cargos() -> Array[String]:
	var paths: Array[String] = ["user://iron_ore_cargo.json", "user://steel_cargo.json"]
	write_json(paths[0], {
		"id": "iron_ore", "display_name": "Iron Ore", "unit_label": "tons",
		"base_rate": 6.0, "time_sensitivity": 0.02, "quality_floor": 0.95,
		"colour": "#7d5a3c", "wagon_required": true, "tonnes_per_unit": 1.0,
	})
	write_json(paths[1], {
		"id": "steel", "display_name": "Steel", "unit_label": "bars",
		"base_rate": 22.0, "time_sensitivity": 0.05, "quality_floor": 0.9,
		"colour": "#8f9aa6", "wagon_required": true, "tonnes_per_unit": 1.0,
	})
	return paths


func _write_iron_works() -> String:
	var path := "user://iron_works.json"
	write_json(path, {
		"id": "iron_works", "display_name": "Iron Works", "asset": "iron_works",
		"footprint": [3, 2], "animation_state": "working",
		"produces": [{"cargo": "steel", "rate_per_month": 12.0, "storage_capacity": 60}],
		"accepts": [
			{"cargo": "iron_ore", "capacity_per_month": 20},
			{"cargo": "coal", "capacity_per_month": 10},
		],
	})
	return path


func test_the_stock_on_sale_is_described_in_full_before_it_is_sold() -> void:
	## The yard can only quote a consist if the JSON carries every number the quote
	## needs, so the shipped roster is read field by field: an engine with no power
	## or a hopper with no capacity would otherwise reach the shop silently.
	var registry := DataRegistry.new()
	check_true(registry.load_all(), "the shipped rolling stock loads clean")
	var engines := registry.locomotive_ids()
	check_true(engines.has("steam_440"), "the 4-4-0 is in the catalogue")
	var roster := registry.wagon_ids()
	for wanted in ["coal_hopper", "mail_car", "passenger_coach"]:
		check_true(roster.has(wanted), "and the catalogue carries the %s" % wanted)

	var engine := registry.locomotives.get("steam_440") as DataRegistry.StockDef
	check_true(engine != null, "the engine parsed into a definition")
	check_eq(engine.kind, "locomotive", "classified as an engine, not a wagon")
	check_gt(engine.price, 0.0, "with a price the shop can charge")
	check_ge(engine.running_cost_month, 0.0, "a monthly upkeep to bill")
	check_gt(engine.max_speed_kmh, 0.0, "a speed to run at")
	check_gt(engine.power, 0.0, "and the power that estimate is built from")
	check_gt(engine.weight_tons, 0.0, "and a weight for the consist to haul")
	check_gt(engine.wheel_radius, 0.0, "and a wheel for the animation to turn")
	check_true(engine.source_file != "", "each number came out of a file in game/data")

	for wagon_id in roster:
		var wagon := registry.wagons.get(wagon_id) as DataRegistry.StockDef
		check_eq(wagon.kind, "wagon", "%s is classified as a wagon" % wagon_id)
		check_gt(wagon.price, 0.0, "%s has a price" % wagon_id)
		check_gt(wagon.capacity, 0.0, "%s has a capacity to fill" % wagon_id)
		check_gt(wagon.weight_tons, 0.0, "%s has a weight" % wagon_id)
		check_true(registry.cargo.has(wagon.cargo), "%s carries a cargo that exists" % wagon_id)
		check_true(wagon.source_file != "", "%s was read from the data folder" % wagon_id)
