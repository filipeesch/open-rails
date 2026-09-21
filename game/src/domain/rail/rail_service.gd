class_name RailService
extends RefCounted

## Rail construction validity and graph queries.
##
## `can_connect` is the single authority on whether a connection may exist.
## The planner, the build tool and the track renderer all ask it, so a reason
## string is never reconstructed from a boolean after the fact.

signal track_changed(tiles: Array[Vector2i])
signal track_removed(tiles: Array[Vector2i])

var network: RailNetwork = RailNetwork.new()

var _world: WorldGrid
var _revision: int = 0
var _path_cache: Dictionary = {}
var _path_find_calls: int = 0
var _path_find_micros_total: int = 0


func attach(world: WorldGrid) -> void:
	_world = world
	network.attach(world)


func world() -> WorldGrid:
	return _world


func revision() -> int:
	return _revision


func path_find_calls() -> int:
	return _path_find_calls


func path_find_micros_total() -> int:
	return _path_find_micros_total


func reset_counters() -> void:
	_path_find_calls = 0
	_path_find_micros_total = 0


# --- validity -------------------------------------------------------------

## Returns "" when the connection is legal, otherwise a specific reason safe
## to show the player verbatim.
func can_connect(tile: Vector2i, direction: int) -> String:
	if not _world.in_bounds(tile):
		return "Outside the map"
	var other := tile + RailDirections.offset(direction)
	if not _world.in_bounds(other):
		return "Outside the map"
	var reason := _cell_reason(other)
	if reason != "":
		return reason
	if not network.slope_ok(tile, other):
		return "Grade too steep — one height step per tile is the limit"
	return ""


func cell_reason(tile: Vector2i) -> String:
	return _cell_reason(tile)


func _cell_reason(tile: Vector2i) -> String:
	if not _world.in_bounds(tile):
		return "Outside the map"
	var terrain := _world.terrain_at(tile)
	if terrain == WorldGrid.Terrain.WATER:
		return "Cannot build on water"
	var occupancy := _world.occupancy_at(tile)
	if occupancy == WorldGrid.Occupancy.STATION:
		return "A station already occupies this site"
	if occupancy == WorldGrid.Occupancy.INDUSTRY:
		return "An industry already occupies this site"
	if occupancy == WorldGrid.Occupancy.TOWN:
		return "This is town ground"
	return ""


func can_place_cell(tile: Vector2i) -> String:
	var reason := _cell_reason(tile)
	if reason != "":
		return reason
	if _world.occupancy_at(tile) == WorldGrid.Occupancy.RAIL:
		return ""
	return ""


# --- mutation -------------------------------------------------------------

## Builds a straight run of connected cells.  Returns the tiles that changed.
## Any illegal cell aborts the whole segment, leaving the network untouched.
func build_segment(tiles: Array[Vector2i]) -> Dictionary:
	if tiles.is_empty():
		return {"ok": false, "reason": "No route selected", "tiles": [] as Array[Vector2i]}
	var reason := segment_reason(tiles)
	if reason != "":
		return {"ok": false, "reason": reason, "tiles": [] as Array[Vector2i]}
	return commit_segment(tiles)


func segment_reason(tiles: Array[Vector2i]) -> String:
	if tiles.is_empty():
		return "No route selected"
	for index in tiles.size():
		var cell_reason := _cell_reason(tiles[index])
		if cell_reason != "":
			return cell_reason
		if index > 0:
			var previous := tiles[index - 1]
			var direction := direction_between(previous, tiles[index])
			if direction < 0:
				return "Route contains a jump between non-adjacent tiles"
			if not network.slope_ok(previous, tiles[index]):
				return "Grade too steep — one height step per tile is the limit"
	return ""


func direction_between(from: Vector2i, to: Vector2i) -> int:
	var delta := to - from
	for direction in RailDirections.COUNT:
		if RailDirections.offset(direction) == delta:
			return direction
	return -1


func commit_segment(tiles: Array[Vector2i]) -> Dictionary:
	var touched: Array[Vector2i] = []
	var added: Array[Vector2i] = []
	for index in tiles.size():
		var tile := tiles[index]
		if not touched.has(tile):
			touched.append(tile)
		var held := _world.occupancy_at(tile)
		if held == WorldGrid.Occupancy.NONE or held == WorldGrid.Occupancy.SCENERY:
			# Scenery is what stands where the line goes.  A tree has no owner, no
			# economics and no player intent behind it, so laying rail cuts it down
			# rather than leaving it drawn through the ballast.  Anything that owns
			# the ground — town, industry, station — refused this placement upstream.
			_world.set_occupancy(tile, WorldGrid.Occupancy.RAIL, 0)
		if not network.has_rail(tile):
			added.append(tile)
		# A lone cell is a dead-end stub, not nothing: presence is laid down
		# whether or not this segment also creates a connection here.
		_world.set_rail_cell(tile, true)
		if index > 0:
			network.connect_direction(tiles[index - 1], direction_between(tiles[index - 1], tile))
			if not touched.has(tiles[index - 1]):
				touched.append(tiles[index - 1])
	# Track splices into the line it touches.  Only the cells of this run are
	# walked in order, so a piece relayed into a gap would otherwise sit there as
	# two dead ends facing the stubs it was meant to join, and every route across
	# it would stay broken until the player rebuilt the whole line.  Diagonal
	# contact is deliberately excluded: two lines that only graze at a corner are
	# not a junction, and a corner link would let a train skip the cell it should
	# turn through.  Diagonal joins come from a run that steps diagonally.
	for tile in tiles:
		for direction in RailDirections.COUNT:
			if RailDirections.is_diagonal(direction):
				continue
			if network.mask(tile) & RailDirections.bit(direction) != 0:
				continue
			var other := tile + RailDirections.offset(direction)
			if not network.has_rail(other):
				continue
			if not network.slope_ok(tile, other):
				continue
			network.connect_direction(tile, direction)
			if not touched.has(other):
				touched.append(other)
	_bump()
	track_changed.emit(touched)
	return {"ok": true, "reason": "", "tiles": touched, "added": added}


func remove_cells(tiles: Array[Vector2i]) -> Dictionary:
	var blocked := removal_block(tiles)
	if blocked != "":
		return {"ok": false, "reason": blocked, "tiles": [] as Array[Vector2i]}
	var touched: Array[Vector2i] = []
	for tile in tiles:
		for neighbour in network.connected_tiles(tile):
			if not touched.has(neighbour):
				touched.append(neighbour)
		network.remove_cell(tile)
		if _world.occupancy_at(tile) == WorldGrid.Occupancy.RAIL:
			_world.clear_occupancy(tile)
		if not touched.has(tile):
			touched.append(tile)
	_bump()
	track_removed.emit(touched)
	return {"ok": true, "reason": "", "tiles": touched}


## Rail that a station depends on for access must not vanish underneath it.
func removal_block(tiles: Array[Vector2i]) -> String:
	for tile in tiles:
		if not network.has_rail(tile):
			continue
		var owner := station_dependency(tile)
		if owner != 0:
			return "Station '%s' uses this track for rail access" % _station_name(owner)
	return ""


var _station_lookup: Callable = Callable()
var _station_name_lookup: Callable = Callable()


## The station service answers "does a station depend on this cell?" so rail
## rules stay here while the dependency itself stays with stations.
func set_station_lookups(tile_owner: Callable, name_lookup: Callable) -> void:
	_station_lookup = tile_owner
	_station_name_lookup = name_lookup


func station_dependency(tile: Vector2i) -> int:
	if _station_lookup.is_valid():
		return _station_lookup.call(tile)
	return 0


func _station_name(station_id: int) -> String:
	if _station_name_lookup.is_valid():
		return _station_name_lookup.call(station_id)
	return "#%d" % station_id


func _bump() -> void:
	_revision += 1
	_path_cache.clear()


# --- graph queries --------------------------------------------------------

func is_reachable(from_tile: Vector2i, to_tile: Vector2i) -> bool:
	return not find_path(from_tile, to_tile).is_empty()


func find_path(from_tile: Vector2i, to_tile: Vector2i) -> Array[Vector2i]:
	var key := _world.index_of(from_tile) * 1000000 + _world.index_of(to_tile)
	if _path_cache.has(key):
		return _path_cache[key]
	var started := Time.get_ticks_usec()
	_path_find_calls += 1
	var path := _astar_rail(from_tile, to_tile)
	_path_find_micros_total += int(Time.get_ticks_usec() - started)
	_path_cache[key] = path
	return path


func reachable_from(from_tile: Vector2i, limit: int = 100000) -> Dictionary:
	var reached := {}
	if not network.has_rail(from_tile):
		return reached
	var queue: Array[Vector2i] = [from_tile]
	reached[_world.index_of(from_tile)] = 0
	var head := 0
	while head < queue.size() and reached.size() < limit:
		var tile := queue[head]
		head += 1
		var cost: int = reached[_world.index_of(tile)]
		for neighbour in network.connected_tiles(tile):
			if not network.has_rail(neighbour):
				continue
			var index := _world.index_of(neighbour)
			if reached.has(index):
				continue
			reached[index] = cost + 1
			queue.append(neighbour)
	return reached


## The same flood keyed by tile.  Callers that hold a tile — a station's rail
## access, a route stop — ask about it here rather than reaching into how the
## grid happens to number its cells; keyed by index they would silently match
## nothing.
func reachable_tiles(from_tile: Vector2i, limit: int = 100000) -> Dictionary:
	var reached := {}
	if not network.has_rail(from_tile):
		return reached
	var queue: Array[Vector2i] = [from_tile]
	reached[from_tile] = 0
	var head := 0
	while head < queue.size() and reached.size() < limit:
		var tile := queue[head]
		head += 1
		var cost: int = reached[tile]
		for neighbour in network.connected_tiles(tile):
			if not network.has_rail(neighbour) or reached.has(neighbour):
				continue
			reached[neighbour] = cost + 1
			queue.append(neighbour)
	return reached


func rail_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for y in _world.height:
		for x in _world.width:
			var tile := Vector2i(x, y)
			if _world.has_rail_cell(tile):
				tiles.append(tile)
	return tiles


## Every live connection point, for renderers and diagnostics.
func junction_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for tile in rail_tiles():
		if network.is_junction(tile):
			tiles.append(tile)
	return tiles


func _astar_rail(from_tile: Vector2i, to_tile: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not network.has_rail(from_tile) or not network.has_rail(to_tile):
		return empty
	if from_tile == to_tile:
		return [from_tile]
	var open_heap: Array[Dictionary] = [{"tile": from_tile, "f": 0.0}]
	var came_from := {}
	var g_cost := {_world.index_of(from_tile): 0.0}
	var closed := {}
	var guard := 0
	while not open_heap.is_empty():
		guard += 1
		if guard > 400000:
			return empty
		var best_index := 0
		var best_f := float(open_heap[0]["f"])
		for index in open_heap.size():
			if float(open_heap[index]["f"]) < best_f:
				best_f = float(open_heap[index]["f"])
				best_index = index
		var current: Dictionary = open_heap[best_index]
		open_heap.remove_at(best_index)
		var tile: Vector2i = current["tile"]
		var index := _world.index_of(tile)
		if closed.has(index):
			continue
		closed[index] = true
		if tile == to_tile:
			return _reconstruct(came_from, tile)
		for neighbour in network.connected_tiles(tile):
			if not network.has_rail(neighbour):
				continue
			var neighbour_index := _world.index_of(neighbour)
			if closed.has(neighbour_index):
				continue
			var direction := direction_between(tile, neighbour)
			var step_cost: float = RailDirections.cost(maxi(direction, 0))
			if network.slope_delta(tile, neighbour) > 0:
				step_cost *= 1.4
			var tentative: float = float(g_cost[index]) + step_cost
			if g_cost.has(neighbour_index) and tentative >= float(g_cost[neighbour_index]):
				continue
			g_cost[neighbour_index] = tentative
			came_from[neighbour_index] = tile
			open_heap.append({"tile": neighbour, "f": tentative + _heuristic(neighbour, to_tile)})
	return empty


func _reconstruct(came_from: Dictionary, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [goal]
	var current := goal
	while true:
		var key := _world.index_of(current)
		if not came_from.has(key):
			break
		current = came_from[key]
		path.push_front(current)
	return path


func _heuristic(from: Vector2i, to: Vector2i) -> float:
	var delta := Vector2(to.x - from.x, to.y - from.y)
	return maxf(absf(delta.x), absf(delta.y)) + 0.41421356 * minf(absf(delta.x), absf(delta.y))
