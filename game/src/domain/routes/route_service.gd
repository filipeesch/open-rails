class_name RouteService
extends RefCounted

## Routes are a list of stops plus per-stop load/unload orders.
##
## The expensive part — turning stops into a tile path over the rail graph —
## happens on edit and on `track_changed`, never per tick.  A train consumes the
## cached path.

signal route_changed(route_id: int)
signal route_removed(route_id: int)
signal route_path_invalid(route_id: int, reason: String)

const LOAD_NONE := "none"

var _routes := {}
var _order: Array[int] = []
var _rail: RailService
var _stations: StationService
var _ids: IdFactory
var _next_leg := {}


func configure(rail: RailService, stations: StationService, ids: IdFactory) -> void:
	_rail = rail
	_stations = stations
	_ids = ids
	rail.track_changed.connect(_on_track_changed)
	rail.track_removed.connect(_on_track_changed)


func routes() -> Array[int]:
	return _order


func count() -> int:
	return _order.size()


func route(route_id: int) -> Dictionary:
	return _routes.get(route_id, {})


func route_for_train(train_id: int) -> int:
	for route_id in _order:
		if int(_routes[route_id]["train_id"]) == train_id:
			return route_id
	return 0


## Create or replace the route flown by `train_id`.  `stops` is a list of
## {station_id, load: Array[String], unload: Array[String]}.
func set_route(train_id: int, stops: Array[Dictionary]) -> Dictionary:
	if stops.size() < 2:
		return _invalid("A route needs at least two stops")
	var station_ids: Array[int] = []
	for stop in stops:
		var station_id := int(stop["station_id"])
		if not _stations.has_station(station_id):
			return _invalid("Unknown station")
		if station_ids.has(station_id):
			return _invalid("A station may appear only once on a route")
		station_ids.append(station_id)
	var normalised: Array[Dictionary] = []
	for index in stops.size():
		var stop := stops[index]
		normalised.append({
			"station_id": station_ids[index],
			"load": Array(stop.get("load", [])),
			"unload": Array(stop.get("unload", [])),
		})
	var route_id := _existing_route_for_train(train_id)
	var is_new := route_id == 0
	if is_new:
		route_id = _ids.next_id()
		_order.append(route_id)
	# Keep the instance the train is scheduled on right now: an edit that turns
	# out to be unhoppable has to leave a working timetable exactly as it was.
	var previous: Dictionary = _routes.get(route_id, {})
	_routes[route_id] = {
		"id": route_id,
		"train_id": train_id,
		"stops": normalised,
		"path": PackedVector2Array(),
		"stop_ticks": PackedFloat64Array(),
		"valid": false,
		"reason": "",
		"length_tiles": 0.0,
	}
	var recomputed := recompute_path(route_id)
	if not recomputed["ok"]:
		if is_new:
			_routes.erase(route_id)
			_order.erase(route_id)
		else:
			_routes[route_id] = previous
			route_changed.emit(route_id)
		return recomputed
	route_changed.emit(route_id)
	return {"ok": true, "reason": "", "id": route_id}


func remove_route(route_id: int) -> bool:
	if not _routes.has(route_id):
		return false
	_routes.erase(route_id)
	_order.erase(route_id)
	route_removed.emit(route_id)
	return true


## The stops as they were committed.  Built as a typed array by hand:
## `Array(untyped)` stays untyped at runtime, so every caller binding the result
## to `Array[Dictionary]` — which is all of them — would abort the moment a train
## has no route yet, the most common state in a brand-new game.
## The stops as they were committed.  Built as a typed array by hand:
## `Array(untyped)` stays untyped at runtime, so every caller binding the result
## to `Array[Dictionary]` — which is all of them — would abort the moment a train
## has no route yet, the most common state in a brand-new game.
func stops(route_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in route(route_id).get("stops", []):
		out.append(entry)
	return out


func stop_count(route_id: int) -> int:
	return stops(route_id).size()


func station_ids(route_id: int) -> Array[int]:
	var out: Array[int] = []
	for stop in stops(route_id):
		out.append(int(stop["station_id"]))
	return out


func is_valid(route_id: int) -> bool:
	return bool(route(route_id).get("valid", false))


func invalid_reason(route_id: int) -> String:
	return String(route(route_id).get("reason", ""))


func length_tiles(route_id: int) -> float:
	return float(route(route_id).get("length_tiles", 0.0))


## Only reachable stations are valid picking targets in the route editor.
func reachable_stations(from_route: int, ignore_station_id: int = 0) -> Array[int]:
	var current := station_ids(from_route)
	if current.is_empty():
		return _stations.stations()
	var origin := _stations.rail_access_tile(current[0])
	var reachable := _rail.reachable_tiles(origin)
	var out: Array[int] = []
	for station_id in _stations.stations():
		if station_id == ignore_station_id:
			continue
		if reachable.has(_stations.rail_access_tile(station_id)):
			out.append(station_id)
	return out


func load_options(route_id: int, stop_index: int) -> Array[Dictionary]:
	var stop_list := stops(route_id)
	if stop_index < 0 or stop_index >= stop_list.size():
		return []
	var station_id := int(stop_list[stop_index]["station_id"])
	var out: Array[Dictionary] = []
	for entry in _cargo_service_available(station_id):
		out.append({
			"cargo": String(entry["cargo"]),
			"label": String(entry["label"]),
			"available": float(entry["amount"]),
		})
	return out


## Which cargos this stop may unload: those a destination-side sink wants.
func unload_options(route_id: int, stop_index: int) -> Array[Dictionary]:
	var stop_list := stops(route_id)
	if stop_index < 0 or stop_index >= stop_list.size():
		return []
	var station_id := int(stop_list[stop_index]["station_id"])
	var out: Array[Dictionary] = []
	var seen := {}
	for cargo_id in _accepted_cargos(station_id):
		if seen.has(cargo_id):
			continue
		seen[cargo_id] = true
		out.append({"cargo": cargo_id, "label": _cargo_label(cargo_id)})
	return out


# --- path -----------------------------------------------------------------

## Rebuild the tile path.  Called on edit and whenever the track changes.
func recompute_path(route_id: int) -> Dictionary:
	var instance := route(route_id)
	if instance.is_empty():
		return _invalid("Unknown route")
	var stop_list: Array = instance["stops"]
	var path := PackedVector2Array()
	var stop_ticks := PackedFloat64Array()
	var total := 0.0
	var first_tile := _stations.rail_access_tile(int(stop_list[0]["station_id"]))
	if not _rail.network.has_rail(first_tile):
		return _fail(route_id, "First stop has no rail access")
	path.append(Vector2(first_tile))
	stop_ticks.append(0.0)
	# Distances are measured along the path the same way a train measures its own
	# progress — straight steps of 1.0, diagonals of √2.  Counting tiles instead
	# would put every stop marker short of where the train actually arrives.
	var walk := func(points: PackedVector2Array, from_index: int, running: float) -> float:
		var cursor := running
		for step in range(maxi(1, from_index), points.size()):
			cursor += points[step].distance_to(points[step - 1])
		return cursor
	for index in range(1, stop_list.size()):
		var from_tile := _stations.rail_access_tile(int(stop_list[index - 1]["station_id"]))
		var to_tile := _stations.rail_access_tile(int(stop_list[index]["station_id"]))
		var leg: Array[Vector2i] = _rail.find_path(from_tile, to_tile)
		if leg.is_empty():
			return _fail(route_id, "%s is not reachable from %s" % [
				_stations.name_of(int(stop_list[index]["station_id"])),
				_stations.name_of(int(stop_list[index - 1]["station_id"]))])
		var leg_first := path.size()
		for step in range(1, leg.size()):
			path.append(Vector2(leg[step]))
		total = walk.call(path, leg_first, total)
		stop_ticks.append(total)
	# Return leg closes the loop back to the first stop.
	var last_tile := _stations.rail_access_tile(int(stop_list[stop_list.size() - 1]["station_id"]))
	var back: Array[Vector2i] = _rail.find_path(last_tile, first_tile)
	var is_circular := not back.is_empty() and stop_list.size() > 1
	if is_circular:
		var back_first := path.size()
		for step in range(1, back.size()):
			path.append(Vector2(back[step]))
		total = walk.call(path, back_first, total)
		# The way home is a stop too: without a marker at the close of the loop
		# a train would never arrive back at its first station.
		stop_ticks.append(total)
	instance["path"] = path
	instance["stop_ticks"] = stop_ticks
	instance["length_tiles"] = total
	instance["valid"] = true
	instance["reason"] = ""
	instance["circular"] = is_circular
	route_changed.emit(route_id)
	return {"ok": true, "reason": "", "id": route_id, "length_tiles": total}


func path_of(route_id: int) -> PackedVector2Array:
	return route(route_id).get("path", PackedVector2Array())


func stop_ticks_of(route_id: int) -> PackedFloat64Array:
	return route(route_id).get("stop_ticks", PackedFloat64Array())


func is_circular(route_id: int) -> bool:
	return bool(route(route_id).get("circular", false))


## The stop index a distance along the path falls on, and whether that distance
## is a stop boundary.
func stop_at_distance(route_id: int, travelled: float) -> int:
	var ticks := stop_ticks_of(route_id)
	for index in ticks.size():
		if is_equal_approx(travelled, float(ticks[index])):
			return index
	return -1


func describe(route_id: int) -> String:
	if not is_valid(route_id):
		return "Route invalid: %s" % invalid_reason(route_id)
	var parts: PackedStringArray = []
	for stop in stops(route_id):
		var loads: Array[String] = []
		for cargo_id in Array(stop["load"]):
			loads.append(_cargo_label(String(cargo_id)))
		var text := _stations.name_of(int(stop["station_id"]))
		if not loads.is_empty():
			text += " (load %s)" % ", ".join(loads)
		parts.append(text)
	return " → ".join(PackedStringArray(parts))


# --- internals ------------------------------------------------------------

func _existing_route_for_train(train_id: int) -> int:
	return route_for_train(train_id)


func _on_track_changed(_a: Variant = null, _b: Variant = null) -> void:
	for route_id in _order:
		var result := recompute_path(route_id)
		if not result["ok"]:
			route_path_invalid.emit(route_id, String(result["reason"]))


func _fail(route_id: int, reason: String) -> Dictionary:
	var instance := route(route_id)
	if not instance.is_empty():
		instance["valid"] = false
		instance["reason"] = reason
		instance["path"] = PackedVector2Array()
		instance["stop_ticks"] = PackedFloat64Array()
		instance["circular"] = false
	route_path_invalid.emit(route_id, reason)
	return {"ok": false, "reason": reason, "id": route_id}


func _invalid(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "id": 0}


func _accepted_cargos(station_id: int) -> Array[String]:
	return _accepted_provider.call(station_id) if _accepted_provider.is_valid() else []


func _cargo_service_available(station_id: int) -> Array[Dictionary]:
	return _available_provider.call(station_id) if _available_provider.is_valid() else []


func _cargo_label(cargo_id: String) -> String:
	return _label_provider.call(cargo_id) if _label_provider.is_valid() else cargo_id


## Wired by GameSession so RouteService need not know CargoService's shape.
var _accepted_provider: Callable = Callable()
var _available_provider: Callable = Callable()
var _label_provider: Callable = Callable()


func provide_introspection(accepted: Callable, available: Callable, label: Callable) -> void:
	_accepted_provider = accepted
	_available_provider = available
	_label_provider = label


func to_dict() -> Dictionary:
	var entries: Array = []
	for route_id in _order:
		var instance: Dictionary = _routes[route_id]
		var stop_entries: Array = []
		for stop in instance["stops"]:
			stop_entries.append({
				"station_id": int(stop["station_id"]),
				"load": Array(stop["load"]).duplicate(),
				"unload": Array(stop["unload"]).duplicate(),
			})
		entries.append({
			"id": route_id,
			"train_id": instance["train_id"],
			"stops": stop_entries,
		})
	return {"routes": entries}


func from_dict(data: Dictionary) -> void:
	_routes.clear()
	_order.clear()
	for entry in data.get("routes", []):
		var route_id := int(entry["id"])
		var stop_list: Array[Dictionary] = []
		for stop in entry.get("stops", []):
			stop_list.append({
				"station_id": int(stop["station_id"]),
				"load": Array(stop.get("load", [])),
				"unload": Array(stop.get("unload", [])),
			})
		_routes[route_id] = {
			"id": route_id,
			"train_id": int(entry["train_id"]),
			"stops": stop_list,
			"path": PackedVector2Array(),
			"stop_ticks": PackedFloat64Array(),
			"valid": false,
			"reason": "",
			"length_tiles": 0.0,
			"circular": false,
		}
		_order.append(route_id)
		if _ids != null:
			_ids.adopt_highest(route_id)
	for route_id in _order:
		recompute_path(route_id)
