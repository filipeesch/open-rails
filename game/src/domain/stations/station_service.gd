class_name StationService
extends RefCounted

## The single V1 station class: footprint, rail access, catchment, storage.
##
## Placement legality has one authority — `placement_reason` — so the ghost
## preview and the commit path can never disagree about what is allowed.

signal station_created(station_id: int)
signal station_removed(station_id: int)
signal station_renamed(station_id: int, new_name: String)
signal station_inventory_changed(station_id: int)

const RAIL_ACCESS_RADIUS := 2

## Coverage queries run once per source per month, and the map is 65 536 tiles
## wide, so they must not walk the station list.  Stations are bucketed into
## COVERAGE_CELL-sized cells; because no V1 catchment reaches further than one
## cell, a lookup only ever reads the nine cells around a source.
const COVERAGE_CELL := 8

var _coverage := {}

var _stations := {}
var _order: Array[int] = []
var _world: WorldGrid
var _rail: RailService
var _defs: DataRegistry
var _ids: IdFactory
var _sources_provider: Callable = Callable()
var _town_name_lookup: Callable = Callable()


func configure(world: WorldGrid, rail: RailService, registry: DataRegistry, ids: IdFactory) -> void:
	_world = world
	_rail = rail
	_defs = registry
	_ids = ids


func station_def(definition_id: String = "small_station") -> DataRegistry.StationDef:
	return _defs.stations.get(definition_id)


func stations() -> Array[int]:
	return _order


func count() -> int:
	return _order.size()


func has_station(station_id: int) -> bool:
	return _stations.has(station_id)


func station(station_id: int) -> Dictionary:
	return _stations.get(station_id, {})


func name_of(station_id: int) -> String:
	return String(station(station_id).get("name", "Station"))


func tile_of(station_id: int) -> Vector2i:
	return station(station_id).get("tile", Vector2i.ZERO)


func def_of(station_id: int) -> DataRegistry.StationDef:
	return station_def(String(station(station_id).get("definition", "small_station")))


func catchment_of(station_id: int) -> float:
	var def := def_of(station_id)
	return def.catchment_tiles if def != null else WorldConstants.STATION_CATCHMENT


# --- placement ------------------------------------------------------------

## The ghost and the commit path share this.  Empty string means buildable.
func placement_reason(definition_id: String, anchor: Vector2i) -> String:
	var def := station_def(definition_id)
	if def == null:
		return "Unknown station class"
	var footprint := WorldCoords.tiles_in_span(anchor, def.footprint)
	for tile in footprint:
		if not _world.in_bounds(tile):
			return "Footprint leaves the map"
	# A station exists to serve a through line, so that question is answered
	# before complaining about where exactly the platform would sit: of two
	# complaints, the player needs the one they can act on.
	if find_rail_access(anchor, def).is_empty():
		if def.requires_straight_rail:
			return "Requires straight rail within %d tiles" % def.rail_search_radius
		return "Requires rail access within %d tiles" % def.rail_search_radius
	for tile in footprint:
		if _world.terrain_at(tile) == WorldGrid.Terrain.WATER:
			return "Footprint overlaps water"
		var occupancy := _world.occupancy_at(tile)
		if occupancy == WorldGrid.Occupancy.STATION:
			return "Overlaps another station"
		if occupancy == WorldGrid.Occupancy.INDUSTRY or occupancy == WorldGrid.Occupancy.TOWN:
			return "Footprint overlaps developed ground"
		if occupancy == WorldGrid.Occupancy.RAIL:
			# Burying the line under the platform would leave a station whose
			# own access rail cannot be built on, upgraded, or removed.
			return "Footprint covers track — leave the line clear"
	return ""


## Nearest qualifying rail cell, or {} when there is none.
func find_rail_access(anchor: Vector2i, def: DataRegistry.StationDef) -> Dictionary:
	var centre := anchor + (def.footprint / 2)
	var best := {}
	var best_distance := 1e9
	for offset_y in range(-def.rail_search_radius - 1, def.rail_search_radius + 2):
		for offset_x in range(-def.rail_search_radius - 1, def.rail_search_radius + 2):
			var tile := centre + Vector2i(offset_x, offset_y)
			if not _rail.network.has_rail(tile):
				continue
			if def.requires_straight_rail and not _rail.network.is_straight(tile):
				continue
			var distance := WorldCoords.distance_tiles(centre, tile)
			if distance < best_distance:
				best_distance = distance
				best = {"tile": tile, "distance": distance}
	return best


func build(definition_id: String, anchor: Vector2i, label: String = "") -> Dictionary:
	var reason := placement_reason(definition_id, anchor)
	if reason != "":
		return {"ok": false, "reason": reason, "id": 0}
	var def := station_def(definition_id)
	var station_id := _ids.next_id()
	var footprint := WorldCoords.tiles_in_span(anchor, def.footprint)
	for tile in footprint:
		_world.set_occupancy(tile, WorldGrid.Occupancy.STATION, station_id)
	var access := find_rail_access(anchor, def)
	var instance := {
		"id": station_id,
		"definition": definition_id,
		"name": label if label != "" else _default_name(anchor),
		"anchor": anchor,
		"tile": anchor + (def.footprint / 2),
		"footprint": def.footprint,
		"access_tile": access.get("tile", Vector2i.ZERO),
		"inventory": {},
		"fraction_received": {},
		"monthly_revenue": 0.0,
		"lifetime_revenue": 0.0,
		"monthly_delivered": 0,
	}
	_stations[station_id] = instance
	_order.append(station_id)
	station_created.emit(station_id)
	return {"ok": true, "reason": "", "id": station_id, "footprint": footprint, "access": access}


func remove_station(station_id: int) -> bool:
	var instance := station(station_id)
	if instance.is_empty():
		return false
	for tile in WorldCoords.tiles_in_span(instance["anchor"], instance["footprint"]):
		_world.clear_occupancy(tile)
	_stations.erase(station_id)
	_order.erase(station_id)
	station_removed.emit(station_id)
	return true


func rename(station_id: int, new_name: String) -> void:
	var instance := station(station_id)
	if instance.is_empty():
		return
	instance["name"] = new_name if new_name != "" else instance["name"]
	station_renamed.emit(station_id, instance["name"])


func rename_from_query(station_id: int, new_name: String) -> void:
	rename(station_id, new_name)


func set_monthly_revenue(station_id: int, amount: float) -> void:
	var instance := station(station_id)
	if instance.is_empty():
		return
	instance["monthly_revenue"] = amount


func add_revenue(station_id: int, amount: float) -> void:
	var instance := station(station_id)
	if instance.is_empty():
		return
	instance["monthly_revenue"] = float(instance["monthly_revenue"]) + amount
	instance["lifetime_revenue"] = float(instance["lifetime_revenue"]) + amount


func monthly_revenue_of(station_id: int) -> float:
	return float(station(station_id).get("monthly_revenue", 0.0))


func close_month() -> void:
	for station_id in _order:
		var instance: Dictionary = _stations[station_id]
		instance["monthly_revenue"] = 0.0
		instance["monthly_delivered"] = 0


# --- catchment ------------------------------------------------------------

## The places within reach that would take cargo from this station.
func covered_sinks(station_id: int) -> Array[Dictionary]:
	var instance := station(station_id)
	if instance.is_empty():
		return []
	var centre: Vector2i = instance["tile"]
	var radius := catchment_of(station_id)
	var sinks: Array[Dictionary] = []
	for entry in _all_sinks():
		var distance: float = WorldCoords.distance_tiles(centre, entry["tile"])
		if distance <= radius:
			var copy := Dictionary(entry).duplicate()
			copy["distance"] = distance
			sinks.append(copy)
	sinks.sort_custom(func(a, b): return float(a["distance"]) < float(b["distance"]))
	return sinks


func _all_sinks() -> Array[Dictionary]:
	return _sink_provider.call() if _sink_provider.is_valid() else []


func provide_sinks(callback: Callable) -> void:
	_sink_provider = callback


var _sink_provider: Callable = Callable()


func covered_sources(station_id: int) -> Array[Dictionary]:
	var instance := station(station_id)
	if instance.is_empty():
		return []
	var radius := catchment_of(station_id)
	var centre: Vector2i = instance["tile"]
	var sources: Array[Dictionary] = []
	for entry in _all_sources():
		var distance: float = WorldCoords.distance_tiles(centre, entry["tile"])
		if distance <= radius:
			sources.append({
				"kind": entry["kind"],
				"id": entry["id"],
				"name": entry["name"],
				"tile": entry["tile"],
				"distance": distance,
			})
	sources.sort_custom(func(a, b): return float(a["distance"]) < float(b["distance"]))
	return sources


## Every station whose catchment reaches this source, nearest first.
func stations_covering(entry: Dictionary) -> Array[int]:
	var covering: Array[int] = []
	for station_id in _candidates_near(entry["tile"]):
		var instance: Dictionary = _stations[station_id]
		var distance := WorldCoords.distance_tiles(instance["tile"], entry["tile"])
		if distance <= catchment_of(station_id):
			covering.append(station_id)
	covering.sort_custom(func(a, b):
		return WorldCoords.distance_tiles(_stations[a]["tile"], entry["tile"]) \
			< WorldCoords.distance_tiles(_stations[b]["tile"], entry["tile"]))
	return covering


## The tiles a station of this class, standing at this anchor, would cover.
## The ghost asks for it before anything exists, so it takes the definition and
## the anchor rather than an id.
func catchment_tiles_for(definition_id: String, anchor: Vector2i) -> Array[Vector2i]:
	var def := station_def(definition_id)
	if def == null:
		return []
	return _tiles_in_catchment(anchor + (def.footprint / 2), def.catchment_tiles)


func catchment_tiles(station_id: int) -> Array[Vector2i]:
	var instance := station(station_id)
	if instance.is_empty():
		return []
	return _tiles_in_catchment(instance["tile"], catchment_of(station_id))


func _tiles_in_catchment(centre: Vector2i, radius: float) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var reach := int(ceilf(radius))
	for offset_y in range(-reach, reach + 1):
		for offset_x in range(-reach, reach + 1):
			var tile := centre + Vector2i(offset_x, offset_y)
			if not _world.in_bounds(tile):
				continue
			if WorldCoords.distance_tiles(centre, tile) <= radius:
				tiles.append(tile)
	return tiles


# --- coverage index -------------------------------------------------------

## Stations that could possibly reach this tile, read out of the bucket grid.
## The grid is rebuilt lazily after any station appears or disappears; reading
## it is what the monthly allocation loop does hundreds of times a minute.
func _candidates_near(tile: Vector2i) -> Array[int]:
	if _coverage.size() != _order.size():
		_rebuild_coverage_index()
	var centre := _coverage_cell(tile)
	var candidates: Array[int] = []
	for offset_y in range(-1, 2):
		for offset_x in range(-1, 2):
			var bucket: Array = _coverage.get(_cell_key(centre + Vector2i(offset_x, offset_y)), [])
			for station_id in bucket:
				candidates.append(int(station_id))
	return candidates


func _rebuild_coverage_index() -> void:
	_coverage = {}
	for station_id in _order:
		var cell := _coverage_cell(_stations[station_id]["tile"])
		var key := _cell_key(cell)
		var bucket: Array = _coverage.get(key, [])
		bucket.append(station_id)
		_coverage[key] = bucket


func _coverage_cell(tile: Vector2i) -> Vector2i:
	return Vector2i(floori(float(tile.x) / float(COVERAGE_CELL)),
		floori(float(tile.y) / float(COVERAGE_CELL)))


func _cell_key(cell: Vector2i) -> String:
	return "%d:%d" % [cell.x, cell.y]


## Returned when a station has no usable rail.  It is deliberately off the map:
## (0, 0) is a tile a station could legitimately stand beside, and a sentinel
## that names a real place turns "no access" into "access in the corner".
const NO_RAIL_ACCESS := Vector2i(-1, -1)


func rail_access_tile(station_id: int) -> Vector2i:
	var instance := station(station_id)
	if instance.is_empty():
		return NO_RAIL_ACCESS
	if _rail.network.has_rail(instance.get("access_tile", NO_RAIL_ACCESS)):
		return instance["access_tile"]
	var access := find_rail_access(instance["anchor"], def_of(station_id))
	if not access.is_empty():
		instance["access_tile"] = access["tile"]
		return access["tile"]
	return NO_RAIL_ACCESS


func has_rail_access(station_id: int) -> bool:
	return rail_access_tile(station_id) != NO_RAIL_ACCESS


func station_at_rail(tile: Vector2i) -> int:
	for station_id in _order:
		if rail_access_tile(station_id) == tile:
			return station_id
	return 0


## Does a station depend on this rail cell for access?  Rail removal asks.
func owns_access_tile(tile: Vector2i) -> int:
	if tile == NO_RAIL_ACCESS:
		return 0
	for station_id in _order:
		if rail_access_tile(station_id) == tile:
			return station_id
	return 0


func _all_sources() -> Array[Dictionary]:
	return _sources_provider.call() if _sources_provider.is_valid() else []


func provide_sources(callback: Callable) -> void:
	_sources_provider = callback


# --- inventory ------------------------------------------------------------

func inventory_of(station_id: int, cargo_id: String) -> float:
	return float(station(station_id).get("inventory", {}).get(cargo_id, 0.0))


func total_waiting(station_id: int) -> int:
	var total := 0
	for value in station(station_id).get("inventory", {}).values():
		total += int(value)
	return total


func inventory_by_cargo(station_id: int) -> Dictionary:
	return Dictionary(station(station_id).get("inventory", {}))


func storage_limit(station_id: int, cargo_id: String) -> float:
	var def := def_of(station_id)
	return float(def.storage_per_cargo) if def != null else 120.0


func add_cargo(station_id: int, cargo_id: String, quantity: float) -> float:
	var instance := station(station_id)
	if instance.is_empty() or quantity <= 0.0:
		return 0.0
	var inventory: Dictionary = instance["inventory"]
	var limit := storage_limit(station_id, cargo_id)
	var current := float(inventory.get(cargo_id, 0.0))
	var room := maxf(0.0, limit - current)
	var given := minf(room, quantity)
	if given <= 0.0:
		return 0.0
	inventory[cargo_id] = current + given
	station_inventory_changed.emit(station_id)
	return given


func take_cargo(station_id: int, cargo_id: String, quantity: float) -> float:
	var instance := station(station_id)
	if instance.is_empty():
		return 0.0
	var inventory: Dictionary = instance["inventory"]
	var available := float(inventory.get(cargo_id, 0.0))
	var taken := minf(available, quantity)
	if taken <= 0.0:
		return 0.0
	inventory[cargo_id] = available - taken
	station_inventory_changed.emit(station_id)
	return taken


func _default_name(anchor: Vector2i) -> String:
	var town_service := _town_name_lookup
	if town_service.is_valid():
		var nearest: String = town_service.call(anchor)
		if nearest != "":
			return "%s Station" % nearest
	return "Station %d" % (_order.size() + 1)


func provide_town_name_lookup(callback: Callable) -> void:
	_town_name_lookup = callback


func to_dict() -> Dictionary:
	var entries: Array = []
	for station_id in _order:
		var instance: Dictionary = _stations[station_id]
		entries.append({
			"id": station_id,
			"definition": instance["definition"],
			"name": instance["name"],
			"ax": instance["anchor"].x,
			"ay": instance["anchor"].y,
			"access_x": instance["access_tile"].x,
			"access_y": instance["access_tile"].y,
			"inventory": instance["inventory"].duplicate(),
			"lifetime_revenue": instance["lifetime_revenue"],
		})
	return {"stations": entries}


func from_dict(data: Dictionary) -> void:
	_stations.clear()
	_order.clear()
	for entry in data.get("stations", []):
		var station_id := int(entry["id"])
		var def := station_def(String(entry.get("definition", "small_station")))
		if def == null:
			continue
		var anchor := Vector2i(int(entry.get("ax", 0)), int(entry.get("ay", 0)))
		for tile in WorldCoords.tiles_in_span(anchor, def.footprint):
			_world.set_occupancy(tile, WorldGrid.Occupancy.STATION, station_id)
		_stations[station_id] = {
			"id": station_id,
			"definition": entry["definition"],
			"name": String(entry.get("name", "Station")),
			"anchor": anchor,
			"tile": anchor + (def.footprint / 2),
			"footprint": def.footprint,
			"access_tile": Vector2i(int(entry.get("access_x", 0)), int(entry.get("access_y", 0))),
			"inventory": Dictionary(entry.get("inventory", {})),
			"fraction_received": {},
			"monthly_revenue": 0.0,
			"lifetime_revenue": float(entry.get("lifetime_revenue", 0.0)),
			"monthly_delivered": 0,
		}
		_order.append(station_id)
		if _ids != null:
			_ids.adopt_highest(station_id)
