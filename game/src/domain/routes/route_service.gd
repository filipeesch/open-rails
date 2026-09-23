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
## Who tells a route how far its train has to pull up past a stop's marker —
## see `_set_halts_on_the_deck`.  The trains own that figure.
var _halt_set_back_of: Callable = Callable()



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
##
## A point on the path is the **centre of the rail lane** through a cell, in the
## same tile-space units the world is drawn in -- `WorldCoords.tile_to_world_xz`,
## the one place the centre convention lives.  It used to be the cell's integer
## corner, and nothing downstream could tell: distances along the path are
## differences, so a uniform half-tile shift left every stop marker, every
## length and every fare exactly right, while the only thing that read the
## numbers as a *position* -- the drawing -- put every train half a tile off the
## rails it was running on.  Distances are unchanged by this; only where a
## position means is fixed.
## Let a route ask the trains how long the train flying it is, in half-consists.
## A domain without trains — a preview, a bare route test — never calls this, and
## every halt then stays on the marker the legs meet at.
func set_halt_set_back_provider(provider: Callable) -> void:
	_halt_set_back_of = provider


## Re-measure every route.  A halt is measured in trains — half the consist pulled up
## the line — and a route that was rebuilt before its train was restored has had to
## guess that figure as nothing.  A save is loaded in one order and the domain is
## restored in another, so the halts are taken again once everything is back.
func recompute_all() -> void:
	for route_id in _order:
		recompute_path(route_id)


func _halt_set_back_for(train_id: int) -> float:
	if _halt_set_back_of.is_null() or not _halt_set_back_of.is_valid():
		return 0.0
	return maxf(0.0, float(_halt_set_back_of.call(train_id)))


func recompute_path(route_id: int) -> Dictionary:
	var instance := route(route_id)
	if instance.is_empty():
		return _invalid("Unknown route")
	var stop_list: Array = instance["stops"]
	var path := PackedVector2Array()
	var stop_ticks := PackedFloat64Array()
	# Which vertex each stop's marker falls on, and the cell that stop stands
	# on.  The halt pass needs both; guessing them back out of distances is
	# how a marker ends up standing a cell from its yard.
	var stop_vertices: Array[int] = []
	var stop_tiles: Array[Vector2i] = []
	var total := 0.0
	# A leg runs between the cells the trains stand on at each yard -- the berths --
	# and not between the cells the yards couple to.  Those are different cells
	# wherever a yard's frontage is longer than the straight stretch beside it, and
	# building the leg to the coupling cell stopped every train a whole platform short
	# of the deck it had come to serve.
	var first_tile := _stations.berth_tile(int(stop_list[0]["station_id"]))
	if not _rail.network.has_rail(first_tile):
		return _fail(route_id, "First stop has no rail access")
	path.append(WorldCoords.tile_to_world_xz(first_tile))
	stop_ticks.append(0.0)
	stop_vertices.append(0)
	stop_tiles.append(first_tile)
	# Distances are measured along the path the same way a train measures its own
	# progress — straight steps of 1.0, diagonals of √2.  Counting tiles instead
	# would put every stop marker short of where the train actually arrives.
	var walk := func(points: PackedVector2Array, from_index: int, running: float) -> float:
		var cursor := running
		for step in range(maxi(1, from_index), points.size()):
			cursor += points[step].distance_to(points[step - 1])
		return cursor
	for index in range(1, stop_list.size()):
		var from_tile := _stations.berth_tile(int(stop_list[index - 1]["station_id"]))
		var to_tile := _stations.berth_tile(int(stop_list[index]["station_id"]))
		var leg: Array[Vector2i] = _rail.find_path(from_tile, to_tile)
		if leg.is_empty():
			return _fail(route_id, "%s is not reachable from %s" % [
				_stations.name_of(int(stop_list[index]["station_id"])),
				_stations.name_of(int(stop_list[index - 1]["station_id"]))])
		var leg_first := path.size()
		for step in range(1, leg.size()):
			path.append(WorldCoords.tile_to_world_xz(leg[step]))
		total = walk.call(path, leg_first, total)
		stop_ticks.append(total)
		stop_vertices.append(path.size() - 1)
		stop_tiles.append(to_tile)
	# Return leg closes the loop back to the first stop.
	var last_tile := _stations.berth_tile(int(stop_list[stop_list.size() - 1]["station_id"]))
	var back: Array[Vector2i] = _rail.find_path(last_tile, first_tile)
	var is_circular := not back.is_empty() and stop_list.size() > 1
	if is_circular:
		var back_first := path.size()
		for step in range(1, back.size()):
			path.append(WorldCoords.tile_to_world_xz(back[step]))
		total = walk.call(path, back_first, total)
		# The way home is a stop too: without a marker at the close of the loop
		# a train would never arrive back at its first station.
		stop_ticks.append(total)
		stop_vertices.append(path.size() - 1)
		stop_tiles.append(first_tile)
	# A halt is where a train stops, and a train is not a point: the halt is pulled
	# along the line by half a consist, and the markers re-walked over the line as
	# it now runs.
	path = _set_halts_on_the_deck(path, stop_vertices, stop_tiles,
			_halt_set_back_for(int(instance.get("train_id", 0))))
	stop_ticks = PackedFloat64Array()
	var walked := 0.0
	var mark := 0
	for index in path.size():
		if index > 0:
			walked += path[index].distance_to(path[index - 1])
		while mark < stop_vertices.size() and int(stop_vertices[mark]) == index:
			stop_ticks.append(walked)
			mark += 1
	total = walked

	instance["path"] = path
	instance["stop_ticks"] = stop_ticks
	instance["length_tiles"] = total
	instance["valid"] = true
	instance["reason"] = ""
	instance["circular"] = is_circular
	route_changed.emit(route_id)
	return {"ok": true, "reason": "", "id": route_id, "length_tiles": total}


## Pull every turnaround halt along the line by half a consist, so that a train
## stops with its middle on the yard's marker rather than its coupler alone.
##
## A yard is a length of deck, and the traffic is in the middle of the train that
## stands beside it.  Held to the marker, the engine's nose is on the stop and every
## wagon hangs back along the approach, off the deck it came to serve: the train
## arrives at the yard's boundary instead of at the yard.
##
## Only a stop the train turns round at can be moved this way.  Where a line carries
## on past the yard, the halt has to stay on the vertex the two legs meet at, or a
## train would be stopped on a point it runs over rather than at — V1's single-track
## valley turns round at every yard, so in it this is every halt.  And the rails
## ahead of the engine bound the pull: at the end of a branch, a wharf or a mine,
## the line itself stops and the train stops with it, lying as far alongside as the
## ballast reaches rather than exactly where it would have liked to.
func _set_halts_on_the_deck(path: PackedVector2Array, stop_vertices: Array[int],
		stop_tiles: Array[Vector2i], set_back: float) -> PackedVector2Array:
	if set_back <= 0.0 or path.size() < 3 or stop_vertices.size() < 2:
		return path
	var arrivals: Array[Vector2] = []
	var pulls: Array[float] = []
	for order in stop_vertices.size():
		var arrival := _arrival_at(path, int(stop_vertices[order]))
		arrivals.append(arrival)
		var pull := 0.0
		if arrival != Vector2.INF and _turns_round_at(path, int(stop_vertices[order]), arrival):
			pull = _room_ahead(stop_tiles[order], arrival, set_back)
		pulls.append(pull)
	# The first stop is arrived at twice: at the end of the loop, and again as the
	# loop begins.  Where the loop closes on it by turning round, its halt is set at
	# the head of the path as well as the foot, so a train running out again leaves
	# the halt itself rather than jumping back to the marker.
	var last := stop_vertices.size() - 1
	var closes_first := arrivals[last] != Vector2.INF and float(pulls[last]) > 0.001 \
			and stop_tiles[0] == stop_tiles[last]
	var laid := PackedVector2Array()
	if closes_first:
		laid.append(path[int(stop_vertices[0])] + arrivals[last] * float(pulls[last]))
	var marks: Array[int] = []
	for _order in stop_vertices.size():
		marks.append(-1)
	for index in path.size():
		laid.append(path[index])
		var order := _order_at(stop_vertices, index)
		if order < 0:
			continue
		marks[order] = laid.size() - 1
		if float(pulls[order]) <= 0.001:
			continue
		laid.append(path[index] + arrivals[order] * float(pulls[order]))
		marks[order] = laid.size() - 1
	if closes_first:
		marks[0] = 0
	for mark in marks:
		if int(mark) < 0:
			return path
	stop_vertices.clear()
	for mark in marks:
		stop_vertices.append(int(mark))
	return laid


## The direction of travel as a train reaches a stop's vertex.  The first vertex
## has no arrival of its own — a route starts there, and anything coming back to it
## arrives along the last leg — so it reports none.
func _arrival_at(path: PackedVector2Array, vertex: int) -> Vector2:
	if vertex <= 0 or vertex >= path.size():
		return Vector2.INF
	var arrival: Vector2 = path[vertex] - path[vertex - 1]
	if arrival.length_squared() <= 0.000001:
		return Vector2.INF
	return arrival.normalized()


## Whether the train goes back the way it came at this vertex.  The route's last
## vertex looks forward to where the loop starts again.
func _turns_round_at(path: PackedVector2Array, vertex: int, arrival: Vector2) -> bool:
	var onward := Vector2.INF
	if vertex + 1 < path.size():
		onward = path[vertex + 1] - path[vertex]
	elif path.size() > 2:
		onward = path[1] - path[0]
	if onward == Vector2.INF or onward.length_squared() <= 0.000001:
		return false
	return onward.normalized().dot(arrival) < -0.9


## How far the line runs on past a stop's cell in a direction, in tiles.  A halt may
## be pulled this far and no further: past here there is no rail to stand on.
func _room_ahead(tile: Vector2i, arrival: Vector2, wanted: float) -> float:
	var step := _bearing_towards(arrival)
	if step < 0:
		return 0.0
	var offset := RailDirections.offset(step)
	var room := 0.0
	var current := tile
	while room < wanted:
		var next: Vector2i = current + offset
		if not _rail.network.connected_tiles(current).has(next):
			break
		room += RailDirections.cost(step)
		current = next
	return minf(wanted, room)


## The rail direction a step of the line lies closest to.  A halt is pulled along a
## straight, so the bearing is taken once and kept: a halt that bends round a corner
## would stand the train across the rails it is supposed to be riding.
func _bearing_towards(direction: Vector2) -> int:
	var best := -1
	var best_dot := 0.75
	for index in RailDirections.COUNT:
		var against := Vector2(RailDirections.offset(index)).normalized().dot(direction)
		if against > best_dot:
			best_dot = against
			best = index
	return best


## Which stop, if any, has its marker on this vertex.
func _order_at(stop_vertices: Array[int], vertex: int) -> int:
	for order in stop_vertices.size():
		if int(stop_vertices[order]) == vertex:
			return order
	return -1


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
