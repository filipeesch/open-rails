class_name GameSession
extends Node

## The composition root of one running game.
##
## Every domain service is constructed and wired here, and nothing else holds a
## reference graph.  Presentation and UI reach the simulation through the
## accessors below and through the services' own signals — the simulation never
## calls outward.

signal session_started
signal session_loaded
signal autosave_performed(slot: String)
signal month_rolled(year: int, month: int)
signal notice(message: String, severity: String)

## Entity events re-fired at session level.  Panels listen here rather than
## reaching through `session.stations` and `session.trains`: the session is the
## one thing a screen may depend on, and the service graph behind it is free to
## be rearranged without a single UI file noticing.
signal station_created(station_id: int)
signal station_removed(station_id: int)
signal station_renamed(station_id: int, new_name: String)
signal station_inventory_changed(station_id: int)
signal train_created(train_id: int)
signal train_removed(train_id: int)
signal train_arrived(train_id: int, station_id: int)
signal train_departed(train_id: int, station_id: int)
signal train_route_changed(train_id: int, route_id: int)
signal consist_changed(train_id: int)
signal cargo_allocated(station_id: int, cargo_id: String, amount: float)
signal cargo_delivered(station_id: int, cargo_id: String, quantity: float, revenue: float)
signal cargo_refused(station_id: int, cargo_id: String, reason: String)
signal industry_added(industry_id: int)
signal town_added(town_id: int)

const SAVE_FOLDER := SaveService.SAVE_FOLDER
const SAVE_VERSION := SaveService.SAVE_VERSION

var data: DataRegistry = DataRegistry.new()
var ids: IdFactory = IdFactory.new()
var world: WorldGrid = WorldGrid.new()
var clock: SimulationClock = SimulationClock.new()
var rail: RailService = RailService.new()
var planner: RailPlanner = RailPlanner.new()
var towns: TownService = TownService.new()
var industries: IndustryService = IndustryService.new()
var stations: StationService = StationService.new()
var cargo: CargoService = CargoService.new()
var routes: RouteService = RouteService.new()
var trains: TrainService = TrainService.new()
var economy: EconomyService = EconomyService.new()
var undo: UndoService = UndoService.new()
var builder: BuilderService = BuilderService.new()
var map: MapDocument = MapDocument.new()
var saves: SaveService = SaveService.new()

var map_id: String = "founders_valley"
## The name the player typed on the New Sandbox screen.  Empty means they left
## the field alone, and the company takes the name the content suggests.
var chosen_company_name := ""
var started := false
var last_error: String = ""
## How many cells of the grid carry scenery: planted from the map's feature list
## at boot, recounted from the grid after a restore.  A boot statistic, like
## `map_id`: the diagnostics overlay reports it instead of re-walking 65,536
## cells per frame, and the test suite uses it to prove the authored features
## really did reach the world the simulation runs on.
var scenery_cells: int = 0


var _wired := false


func _init() -> void:
	name = "GameSession"
	saves.attach(self)


# --- lifecycle ------------------------------------------------------------

## Boot a fresh sandbox.  Returns false with `last_error` set when content is
## missing, so the shell can show a real message instead of an empty valley.
func start(map_name: String = "founders_valley") -> bool:
	map_id = map_name
	if not _ensure_data():
		last_error = "Data definitions failed to load:\n" + "\n".join(data.errors)
		push_error(last_error)
		return false
	_boot(data_map_width(), data_map_height())
	if not _load_map():
		return false
	# Cargo sources only exist once the map is in place.
	cargo.allocate_sources()
	_finish_boot()
	started = true
	session_started.emit()
	return true


## Boot over a blank grid with no map content.  Same services, same clock and
## monthly wiring as `start`, minus the shipped valley — what the synthetic
## stress world needs so the run measures load, not content.
func start_blank(p_width: int, p_height: int) -> bool:
	map_id = "synthetic"
	if not _ensure_data():
		last_error = "Data definitions failed to load:\n" + "\n".join(data.errors)
		push_error(last_error)
		return false
	_boot(p_width, p_height)
	cargo.allocate_sources()
	_finish_boot()
	started = true
	session_started.emit()
	return true


func _boot(p_width: int, p_height: int) -> void:
	world.resize(p_width, p_height)
	clock.configure(data.ticks_per_day(), 1)
	# The calendar opens in the year the data names.  Nothing else in the game
	# decides what a year is, so this is where that promise is kept.
	clock.date = GameDate.new(data.start_year(), 1, 1)
	economy.configure(data.starting_cash(), clock.date, company_name_or_default())
	_wire_services()


func _finish_boot() -> void:
	clock.clear_subsystems()
	clock.add_subsystem("trains", Callable(trains, "advance_tick"))
	clock.month_changed.connect(_on_month_changed)
	rail.track_changed.connect(Callable(trains, "_on_track_changed"))
	rail.track_removed.connect(Callable(trains, "_on_track_changed"))


## Definitions are static project data: load them once per session and keep
## them.  `load_all()` is idempotent, but re-running it would also discard any
## definition registered at runtime via `DataRegistry.load_definition_file()`
## (scenario packs, tests), so a restore only bootstraps when nothing is loaded.
func _ensure_data() -> bool:
	if data.cargo.is_empty():
		return data.load_all()
	return data.errors.is_empty()


func restart(map_name: String = "") -> bool:
	_reset_state()
	return start(map_name if map_name != "" else map_id)


func advance(real_delta: float) -> void:
	if not started:
		return
	var ticks := clock.feed(real_delta)
	for _index in ticks:
		clock.step()


## Run a whole number of ticks without touching real time — what tests and the
## stress harness use, and the reason simulation results are reproducible.
func advance_ticks(count: int) -> void:
	for _index in count:
		clock.step()


# --- accessors ------------------------------------------------------------

func world_grid() -> WorldGrid:
	return world


func date() -> GameDate:
	return clock.date


func is_paused() -> bool:
	return clock.is_paused()


func set_paused(paused: bool) -> void:
	clock.set_speed_index(0 if paused else 1)


func cycle_speed() -> void:
	clock.set_speed_index((clock.speed_index + 1) % clock.SPEEDS.size())


## The name this sandbox should carry: the player's if they wrote one, the
## content default otherwise.  Asked at boot, so a chosen name survives the
## whole start-up path without any service having to know about the screen.
func company_name_or_default() -> String:
	return chosen_company_name if chosen_company_name != "" else data.default_company_name()


func choose_company_name(name: String) -> void:
	chosen_company_name = name.strip_edges()


func company_name() -> String:
	return economy.company_name


# --- notifications --------------------------------------------------------

## Domain events the player should hear about, announced in one place.  The
## notification centre listens; nothing here knows a UI exists.
func notify(message: String, severity: String = "info") -> void:
	notice.emit(message, severity)


func camera_yaw() -> float:
	return 45.0


# --- wiring ---------------------------------------------------------------

func _wire_services() -> void:
	if _wired:
		return
	_wired = true
	rail.attach(world)
	planner.attach(world, rail, data)
	stations.configure(world, rail, data, ids)
	towns.configure(ids)
	industries.configure(data, ids)
	routes.configure(rail, stations, ids)
	cargo.configure(stations, towns, industries, data, clock, economy)
	trains.configure(world, rail, stations, routes, cargo, economy, data, clock, ids)
	builder.configure(world, rail, planner, stations, economy, data, undo)
	builder.provide_sources_preview(Callable(self, "_prospective_sources_at"))
	builder.set_dependency_check(Callable(self, "_construction_still_safe"))
	stations.provide_sources(Callable(cargo, "collect_sources"))
	stations.provide_sinks(Callable(cargo, "collect_sinks"))
	stations.provide_town_name_lookup(Callable(self, "_nearest_town_name"))
	rail.set_station_lookups(Callable(stations, "owns_access_tile"), Callable(stations, "name_of"))
	routes.provide_introspection(
		Callable(self, "_accepted_cargos_for"),
		Callable(cargo, "available_summary"),
		Callable(data, "cargo_display"))
	_relay_entity_signals()


## Each service event is re-emitted once at session level.  A plain forward, no
## logic: the session is a megaphone for the simulation, never a second opinion.
func _relay_entity_signals() -> void:
	stations.station_created.connect(func(station_id: int) -> void: station_created.emit(station_id))
	stations.station_removed.connect(func(station_id: int) -> void: station_removed.emit(station_id))
	stations.station_renamed.connect(
			func(station_id: int, new_name: String) -> void: station_renamed.emit(station_id, new_name))
	stations.station_inventory_changed.connect(
			func(station_id: int) -> void: station_inventory_changed.emit(station_id))
	trains.train_created.connect(func(train_id: int) -> void: train_created.emit(train_id))
	trains.train_removed.connect(func(train_id: int) -> void: train_removed.emit(train_id))
	trains.train_arrived.connect(
			func(train_id: int, station_id: int) -> void: train_arrived.emit(train_id, station_id))
	trains.train_departed.connect(
			func(train_id: int, station_id: int) -> void: train_departed.emit(train_id, station_id))
	trains.train_route_changed.connect(
			func(train_id: int, route_id: int) -> void: train_route_changed.emit(train_id, route_id))
	trains.consist_changed.connect(func(train_id: int) -> void: consist_changed.emit(train_id))
	cargo.cargo_allocated.connect(
			func(station_id: int, cargo_id: String, amount: float) -> void:
				cargo_allocated.emit(station_id, cargo_id, amount))
	cargo.cargo_delivered.connect(
			func(station_id: int, cargo_id: String, quantity: float, revenue: float) -> void:
				cargo_delivered.emit(station_id, cargo_id, quantity, revenue))
	cargo.cargo_refused.connect(
			func(station_id: int, cargo_id: String, reason: String) -> void:
				cargo_refused.emit(station_id, cargo_id, reason))
	industries.industry_added.connect(func(industry_id: int) -> void: industry_added.emit(industry_id))
	towns.town_added.connect(func(town_id: int) -> void: town_added.emit(town_id))


func _reset_state() -> void:
	started = false
	scenery_cells = 0
	ids.reset()
	world.clear_state()
	clock.clear_subsystems()
	clock.configure(data.ticks_per_day(), 1)
	economy.configure(data.starting_cash(), clock.date, data.default_company_name())
	undo.clear()
	for service in [towns, industries, stations, cargo, routes, trains]:
		service.from_dict({})


# --- map ------------------------------------------------------------------

func _load_map() -> bool:
	map = MapDocument.load_map(map_id)
	if not map.errors.is_empty():
		last_error = "Map '%s' failed to load:\n%s" % [map_id, "\n".join(map.errors)]
		push_error(last_error)
		return false
	map.apply_to(world)
	# Scenery is authored content, so it arrives the way the ground does: written
	# straight into the grid, quietly, before a single player edit exists.  It
	# stays data — the presentation layer instances it per chunk later, and no
	# tree is ever a node in this tree.
	scenery_cells = int(map.place_features(world).get("cells", 0))
	for entry in map.towns:
		var town_id := towns.add_from_map(entry, map.town_tile(entry), ids.next_id())
		if town_id != 0:
			_place_town_footprint(town_id)
	for entry in map.industries:
		var tile := map.industry_tile(entry)
		var industry_id := industries.add(map.industry_definition(entry), tile,
			map.entity_name(entry), ids.next_id())
		if industry_id == 0:
			last_error = "Map '%s' names an industry '%s' that has no definition" % [
				map_id, map.industry_definition(entry)]
			push_error(last_error)
			return false
		_place_industry_footprint(industry_id, tile)
	# Everything above is content an author wrote, not an edit by anybody, and the
	# presentation is not attached yet — it will build every chunk once, from the
	# state as it now stands.  So the queue is emptied here: sixty cells of town
	# and works ground left in it would otherwise be re-meshed in the first frames
	# after a boot that had already meshed them.
	world.take_dirty_tiles()
	world.take_dirty_chunks()
	return true


## A town's streets are painted into the occupancy grid so a click on the town
## resolves to the town id, and so track and stations cannot be dropped on top of
## them.  Scenery inside the block gives way to the town.
func _place_town_footprint(town_id: int) -> void:
	for covered in towns.footprint_tiles(town_id):
		if world.in_bounds(covered):
			world.set_occupancy(covered, WorldGrid.Occupancy.TOWN, town_id)


func _place_industry_footprint(industry_id: int, tile: Vector2i) -> void:
	var def := industries.def_of(industry_id)
	if def == null:
		return
	for covered in WorldCoords.tiles_in_span(tile - def.footprint / 2, def.footprint):
		if world.in_bounds(covered) and world.occupancy_at(covered) == WorldGrid.Occupancy.NONE:
			world.set_occupancy(covered, WorldGrid.Occupancy.INDUSTRY, industry_id)


# --- monthly cycle --------------------------------------------------------

func _on_month_changed(date: GameDate) -> void:
	cargo.advance_month()
	_apply_monthly_costs()
	stations.close_month()
	trains.close_month()
	industries.reset_monthly_counters()
	_should_autosave(date.year, date.month)
	month_rolled.emit(date.year, date.month)


func _apply_monthly_costs() -> void:
	var track_cost := rail.rail_tiles().size() * data.track_setting("maintenance_per_tile_month", 6.0)
	if track_cost > 0.0:
		economy.spend_allowing_deficit(track_cost, EconomyService.CATEGORY_MAINTENANCE,
				"Track maintenance")
	var operating := 0.0
	for train_id in trains.trains():
		operating += trains.consist_running_cost(train_id)
	if operating > 0.0:
		economy.spend_allowing_deficit(operating, EconomyService.CATEGORY_OPERATING,
				"Train operating costs")


# --- persistence ----------------------------------------------------------

func snapshot() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"map": map_id,
		"world": SaveWriter.world_to_dict(world),
		"clock": clock.to_dict(),
		"date": clock.date.to_dict(),
		"ids": ids.peek(),
		"economy": economy.to_dict(),
		"towns": towns.to_dict(),
		"industries": industries.to_dict(),
		"stations": stations.to_dict(),
		"cargo": cargo.to_dict(),
		"routes": routes.to_dict(),
		"trains": trains.to_dict(),
		# Composition-root capture of per-service live state the services' own
		# dictionaries do not carry (monthly counters, in-flight motion).
		"counters": _capture_live_counters(),
	}


## Restore a snapshot in place.  Order matters: the grid comes back whole
## before any service reads it, and train paths are rebuilt last.
func restore(snapshot_data: Dictionary) -> bool:
	var version := int(snapshot_data.get("version", 0))
	if version < 1 or version > SAVE_VERSION:
		last_error = "Save version %d is not supported" % version
		return false
	if not _ensure_data():
		last_error = "Data definitions failed to load"
		return false
	var saved_map := String(snapshot_data.get("map", map_id))
	# Validate the map is installed *before* touching live state: a save naming
	# a missing map must refuse cleanly, not leave a half-wiped session behind.
	if saved_map != map_id and not _map_installed(saved_map):
		last_error = "Save needs map '%s', which is not installed" % saved_map
		return false
	if saved_map != map_id and not _load_named_map(saved_map):
		return false
	undo.clear()
	ids.reset()
	clock.clear_subsystems()
	clock.configure(data.ticks_per_day(), 1)
	SaveWriter.world_from_dict(world, Dictionary(snapshot_data.get("world", {})))
	# The saved grid carries the scenery with it, so the boot statistic has to
	# describe the grid that actually arrived, not the one this call re-planted.
	scenery_cells = MapFeatures.count_planted(world)
	if snapshot_data.has("ids"):
		# Restore the counter exactly: peek() is the *next* id, so adopting it
		# as if it were a used one would advance every future id by one.
		ids.reset(int(snapshot_data["ids"]))
	else:
		ids.adopt_highest(1000)
	economy.configure(data.starting_cash(), clock.date, data.default_company_name())
	economy.from_dict(Dictionary(snapshot_data.get("economy", {})))
	towns.from_dict(Dictionary(snapshot_data.get("towns", {})))
	industries.from_dict(Dictionary(snapshot_data.get("industries", {})))
	stations.from_dict(Dictionary(snapshot_data.get("stations", {})))
	routes.from_dict(Dictionary(snapshot_data.get("routes", {})))
	cargo.from_dict(Dictionary(snapshot_data.get("cargo", {})))
	trains.from_dict(Dictionary(snapshot_data.get("trains", {})))
	clock.from_dict(Dictionary(snapshot_data.get("clock", {})))
	clock.add_subsystem("trains", Callable(trains, "advance_tick"))
	trains.refresh_paths()
	_apply_live_counters(Dictionary(snapshot_data.get("counters", {})))
	started = true
	session_loaded.emit()
	return true


## Live per-service state the service dictionaries intentionally leave out.
## Keys are strings so JSON round-trips them without surprise.
func _capture_live_counters() -> Dictionary:
	var station_entries := {}
	for station_id in stations.stations():
		var place := stations.station(station_id)
		station_entries[str(station_id)] = {
			"monthly_revenue": float(place.get("monthly_revenue", 0.0)),
			"monthly_delivered": int(place.get("monthly_delivered", 0)),
		}
	var industry_entries := {}
	for industry_id in industries.industries():
		var yard := industries.industry(industry_id)
		industry_entries[str(industry_id)] = {
			"received_this_month": Dictionary(yard.get("received_this_month", {})).duplicate(),
			"produced_this_month": float(yard.get("produced_this_month", 0.0)),
		}
	var train_entries := {}
	for train_id in trains.trains():
		var engine := trains.train(train_id)
		train_entries[str(train_id)] = {
			"speed": float(engine.get("speed", 0.0)),
			"loading_left": float(engine.get("loading_left", 0.0)),
			"heading": float(engine.get("heading", 0.0)),
		}
	return {"stations": station_entries, "industries": industry_entries, "trains": train_entries}


func _apply_live_counters(counters: Dictionary) -> void:
	for key in Dictionary(counters.get("stations", {})).keys():
		var station_id := int(String(key))
		if not stations.has_station(station_id):
			continue
		var place: Dictionary = stations.station(station_id)
		var place_entry: Dictionary = Dictionary(counters["stations"])[key]
		place["monthly_revenue"] = float(place_entry.get("monthly_revenue", 0.0))
		place["monthly_delivered"] = int(place_entry.get("monthly_delivered", 0))
	for key in Dictionary(counters.get("industries", {})).keys():
		var industry_id := int(String(key))
		var yard: Dictionary = industries.industry(industry_id)
		if yard.is_empty():
			continue
		var yard_entry: Dictionary = Dictionary(counters["industries"])[key]
		yard["received_this_month"] = Dictionary(yard_entry.get("received_this_month", {}))
		yard["produced_this_month"] = float(yard_entry.get("produced_this_month", 0.0))
	for key in Dictionary(counters.get("trains", {})).keys():
		var train_id := int(String(key))
		var engine: Dictionary = trains.train(train_id)
		if engine.is_empty():
			continue
		var engine_entry: Dictionary = Dictionary(counters["trains"])[key]
		engine["speed"] = float(engine_entry.get("speed", 0.0))
		engine["loading_left"] = float(engine_entry.get("loading_left", 0.0))
		engine["heading"] = float(engine_entry.get("heading", 0.0))


func _load_named_map(name: String) -> bool:
	map_id = name
	_reset_state()
	return _load_map()


## Save/load entry points.  Both delegate to the SaveService so every writer —
## menu, palette, autosave — produces the same versioned envelope with a
## metadata header, and every reader validates before touching the session.
func save_to(path: String) -> Dictionary:
	return saves.save_to_path(path, "manual")


func load_from(path: String) -> Dictionary:
	var result := saves.load_path(path)
	if not bool(result.get("ok", false)):
		last_error = String(result.get("reason", "Could not read save"))
	return result


func save_path(slot: String) -> String:
	DirAccess.make_dir_recursive_absolute(SAVE_FOLDER)
	return SAVE_FOLDER.path_join("%s.json" % slot)


func _map_installed(name: String) -> bool:
	return FileAccess.file_exists(MapDocument.MAP_ROOT.path_join(name + ".json"))


func _should_autosave(year: int, month: int) -> void:
	var every := data.autosave_every_months()
	if every <= 0 or (month - 1) % every != 0:
		return
	var result := saves.autosave()
	if bool(result.get("ok", false)):
		autosave_performed.emit(String(result.get("path", "")))


# --- helpers used by wiring -------------------------------------------------

func _prospective_sources_at(definition_id: String, anchor: Vector2i) -> Array[Dictionary]:
	var def := stations.station_def(definition_id)
	if def == null:
		return []
	var centre := anchor + (def.footprint / 2)
	var radius := def.catchment_tiles
	var out: Array[Dictionary] = []
	for entry in cargo.collect_sources():
		if WorldCoords.distance_tiles(centre, entry["tile"]) <= radius:
			var loadable := Dictionary(entry).duplicate()
			loadable["role"] = "load"
			out.append(loadable)
	for entry in cargo.collect_sinks():
		if WorldCoords.distance_tiles(centre, entry["tile"]) <= radius:
			var placeable := Dictionary(entry).duplicate()
			placeable["role"] = "unload"
			out.append(placeable)
	return out


func _accepted_cargos_for(station_id: int) -> Array[String]:
	var out: Array[String] = []
	for entry in stations.covered_sources(station_id):
		if String(entry["kind"]) != CargoService.SOURCE_TOWN:
			continue
		for cargo_id in ["passengers", "mail"]:
			if not out.has(cargo_id):
				out.append(cargo_id)
	for entry in stations.covered_sinks(station_id):
		if String(entry["kind"]) == CargoService.SOURCE_TOWN:
			for cargo_id in ["passengers", "mail"]:
				if not out.has(cargo_id):
					out.append(cargo_id)
			continue
		for flow in industries.def_of(int(entry["id"])).accepts:
			var cargo_id := String(flow["cargo"])
			if not out.has(cargo_id):
				out.append(cargo_id)
	return out


func _nearest_town_name(tile: Vector2i) -> String:
	var best := ""
	var best_distance := 3.5
	for town_id in towns.towns():
		var distance := WorldCoords.distance_tiles(tile, towns.tile_of(town_id))
		if distance < best_distance:
			best_distance = distance
			best = towns.name_of(town_id)
	return best


## Undo is refused once a demolished thing has been built upon.
func _construction_still_safe(kind: String, entity_id: int) -> bool:
	if kind != "station":
		return true
	if not stations.has_station(entity_id):
		return false
	for train_id in trains.trains():
		if trains.home_station(train_id) == entity_id:
			return false
		var route_id := trains.route_of(train_id)
		if route_id != 0 and entity_id in routes.station_ids(route_id):
			return false
	return true


func data_map_width() -> int:
	return WorldConstants.MAP_WIDTH


func data_map_height() -> int:
	return WorldConstants.MAP_HEIGHT
