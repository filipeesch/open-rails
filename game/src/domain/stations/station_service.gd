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

## How far off the yard centre a candidate rail cell may sit before it is
## passed over for one that is more central, in the access scoring below.
## Everything a station actually reaches is `def.rail_search_radius` rings,
## so the reach is authored with the class rather than hard-coded here.
const CENTRING_WEIGHT := 10.0

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
			return "Requires a straight rail run beside the yard"
		return "Requires rail beside the yard"
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


## The rail cell the yard couples to, or {} when it stands off a line.  The
## result carries the run's `direction` as well, because "which cell" is only
## half of it: the yard has to be turned to face down the line, and nothing else
## in the save records that.
##
## Two rules, both of which the old square scan broke.
##
## The ground a yard couples to is the ground beside its platform, so the search
## walks rings outward from the footprint -- ring 1 touches it -- up to
## `rail_search_radius` rings out.  The old version took the nearest rail in a
## square of side `2 * radius + 3` and never filtered by that radius at all, so a
## yard asking for "within 2" happily coupled to track two and a half tiles off,
## and the drawing built on top of it came out adrift from the line.
##
## And where two cells qualify, the one the yard sits *beside* wins over one it
## sits back from: a station is drawn as one yard with a platform edge at the
## rails, so a body kept inside its footprint while the rails run two tiles away
## is a station standing in a field with the line somewhere past it.
##
## A depot, which asks for `requires_straight_rail`, only hears about a cell the
## trains can run through -- the junctions, curves and dead ends it would
## otherwise couple to are exactly the ones where a train cannot pass.
func find_rail_access(anchor: Vector2i, def: DataRegistry.StationDef) -> Dictionary:
	var centre := centre_of(anchor, def.footprint)
	var best := {}
	var best_score := 1e9
	var reach := maxi(1, def.rail_search_radius)
	for ring in range(1, reach + 1):
		for tile in _ring_outside(anchor, def.footprint, ring):
			if not _rail.network.has_rail(tile):
				continue
			if def.requires_straight_rail and not _rail.network.is_straight(tile):
				continue
			var direction := run_direction(tile)
			if direction == Vector2.ZERO and not def.requires_straight_rail:
				direction = _any_axis(tile)
			if direction == Vector2.ZERO:
				continue
			var lane := WorldCoords.tile_to_world_xz(tile)
			var offset := absf((lane - centre).dot(Vector2(-direction.y, direction.x)))
			var score := offset * CENTRING_WEIGHT + float(ring)
			if score < best_score:
				best_score = score
				best = {"tile": tile, "distance": float(ring), "direction": direction}
	return best


## The axis trains run along at `tile`, as a unit tile-space direction: an axis
## with track on both sides.  A cell reached from one side only -- a dead end, the
## stub of a spur -- has no run direction, because nothing runs *through* it.
## Rails run eight ways, so a diagonal line yields a diagonal direction.
func run_direction(tile: Vector2i) -> Vector2:
	var value := _rail.network.mask(tile)
	for direction in [RailDirections.N, RailDirections.NE, RailDirections.E, RailDirections.SE]:
		if RailDirections.has(value, direction) \
				and RailDirections.has(value, RailDirections.opposite(direction)):
			return _direction_of_offset(RailDirections.offset(direction))
	return Vector2.ZERO


## Where a yard's trains reach the line: the cell it coupled to and the axis they
## run along it.  This is what the drawing places a station by, so it is a pure
## read of what the yard was built against -- unlike `rail_access_tile`, which
## re-derives when the line has since moved and so is the simulation's question.
## If the line a station faced has been pulled up, the yard keeps facing the axis
## it was built to rather than snapping to a nonsense angle.
func rail_access(station_id: int) -> Dictionary:
	var instance := station(station_id)
	if instance.is_empty():
		return {"tile": NO_RAIL_ACCESS, "direction": Vector2.RIGHT}
	var tile: Vector2i = instance.get("access_tile", NO_RAIL_ACCESS)
	var direction := run_direction(tile)
	if direction == Vector2.ZERO:
		direction = _any_axis(tile)
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	return {"tile": tile, "direction": direction}


## The middle of a yard, as a continuous position.  A tile spans `tile` ..
## `tile + 1`, so this lands on a grid line for an even footprint and on a tile
## centre for an odd one -- which is why it cannot be the rounded `tile`.
func centre_of(anchor: Vector2i, size: Vector2i) -> Vector2:
	return Vector2(anchor) + Vector2(size) * 0.5


func _any_axis(tile: Vector2i) -> Vector2:
	for direction in RailDirections.directions_in(_rail.network.mask(tile)):
		return _direction_of_offset(RailDirections.offset(direction))
	return Vector2.ZERO


## The cells exactly `ring` steps outside the yard's footprint, walked around its
## border.  Ring 1 is the ring of ground the platform stands against.
func _ring_outside(anchor: Vector2i, size: Vector2i, ring: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var min_x := anchor.x - ring
	var min_y := anchor.y - ring
	var max_x := anchor.x + size.x - 1 + ring
	var max_y := anchor.y + size.y - 1 + ring
	for x in range(min_x, max_x + 1):
		cells.append(Vector2i(x, min_y))
		cells.append(Vector2i(x, max_y))
	for y in range(min_y + 1, max_y):
		cells.append(Vector2i(min_x, y))
		cells.append(Vector2i(max_x, y))
	return cells


## A tile-space step as a direction.  A diagonal's offset is (1, 1) — a whole
## tile in each axis, not a unit vector — and everything downstream reads these
## as axes and measures distances along them, so they are normalised here.
## Turns a rail-direction offset into a unit vector.
##
## It NORMALISES, because the only thing it is for is a direction: feed it a cell
## coordinate and it answers with the bearing of that cell from the origin, which is a
## number that looks plausible and means nothing.  A cell's lane centre is
## `WorldCoords.tile_to_world_xz`, the one place that convention lives.
func _direction_of_offset(offset: Vector2i) -> Vector2:
	var vector := Vector2(float(offset.x), float(offset.y))
	if vector.length_squared() <= 0.0001:
		return vector
	return vector.normalized()


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


## The cell a train standing at this yard stands on -- which is not always the cell the
## yard couples to.
##
## A yard's platform is a length of deck down the line, and a train halts *along the
## deck*: the thing a yard exists to do is exchange cargo with a train standing beside
## it.  Coupling answers a different question -- which cell the ground beside the yard
## owns, and for a depot a cell the line runs through -- and where the line is straight
## for only part of a yard's frontage those two answers differ by a cell or two.  The
## valley's coal wharf is the case the tests keep: its coupling cell is the one straight
## cell at the east end of a three-cell frontage, so a train held there stood with its
## engine at the platform's last handrail and its wagons back along the approach, off
## the deck they had come to serve.
##
## So the halt is the cell abreast the middle of the yard's own ground, slid along the
## run no further than that ground reaches: the same middle the platform is built
## around, which is why a train stopped here stands at the station the player sees
## rather than at whichever cell happens to be nearest it.  Ground with no rail abreast
## the middle falls back to the coupling cell -- a yard standing on a curve stops where
## it can, not where it would like to.
func berth_tile(station_id: int) -> Vector2i:
	var instance := station(station_id)
	if instance.is_empty():
		return NO_RAIL_ACCESS
	var access := rail_access(station_id)
	var tile: Vector2i = access["tile"]
	if tile == NO_RAIL_ACCESS:
		return NO_RAIL_ACCESS
	var direction: Vector2 = access.get("direction", Vector2.RIGHT)
	if direction == Vector2.ZERO:
		return tile
	var footprint: Vector2i = instance.get("footprint", Vector2i(1, 1))
	var centre := centre_of(instance["anchor"], footprint)
	var lane := WorldCoords.tile_to_world_xz(tile)
	var slides := roundi((centre - lane).dot(direction))
	# Only as far along as the yard's own ground: a stop beyond the boundary is a train
	# standing on ground the player never bought.
	var reach := int(floorf((absf(direction.x) * float(footprint.x) \
			+ absf(direction.y) * float(footprint.y)) * 0.5))
	slides = clampi(slides, -reach, reach)
	if slides == 0:
		return tile
	var berth := tile + Vector2i(roundi(direction.x * float(slides)),
			roundi(direction.y * float(slides)))
	if not _rail.network.has_rail(berth):
		return tile
	return berth


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
