class_name RailPlanner
extends RefCounted

## Plans a railway between two tiles across unbuilt ground.
##
## Nodes are terrain tiles, not rail cells — construction has to plan over
## ground that carries no track yet.  Edge cost folds in terrain, slope and a
## turn penalty, so the plan prefers short distance, few turns, gentle slopes
## and existing rail (the reuse bonus) exactly as the specification asks.
##
## Results are cached against (start, goal, network revision): hovering the
## same tile twice costs nothing, which is what keeps a drag at frame rate.

var _world: WorldGrid
var _rail: RailService
var _registry: DataRegistry
var _cache: Dictionary = {}
var _turn_penalty: float = 0.55
var _slope_penalty: float = 1.9
var _reuse_bonus: float = 0.85
var _node_limit: int = 26000
var _search_calls: int = 0


func attach(world: WorldGrid, rail: RailService, registry: DataRegistry) -> void:
	_world = world
	_rail = rail
	_registry = registry
	_turn_penalty = registry.planner_setting("turn_penalty", 0.55)
	_slope_penalty = registry.planner_setting("slope_penalty", 1.9)
	_reuse_bonus = registry.planner_setting("reuse_bonus", 0.85)
	_node_limit = int(registry.planner_setting("search_node_limit", 26000.0))


func search_calls() -> int:
	return _search_calls


func plan(from_tile: Vector2i, to_tile: Vector2i) -> Dictionary:
	var key := "%d:%d:%d" % [_world.index_of(from_tile), _world.index_of(to_tile), _rail.revision()]
	if _cache.has(key):
		return _cache[key]
	_search_calls += 1
	var result := _plan_uncached(from_tile, to_tile)
	_cache.clear()
	_cache[key] = result
	return result


func _plan_uncached(from_tile: Vector2i, to_tile: Vector2i) -> Dictionary:
	var failure := _endpoint_reason(from_tile, to_tile)
	if failure != "":
		return _invalid(failure, from_tile, to_tile)
	if from_tile == to_tile:
		return _invalid("Start and end are the same tile", from_tile, to_tile)

	var start_g := _cell_cost(from_tile, -1)
	var open_heap: Array[Dictionary] = [{"tile": from_tile, "dir": -1, "g": start_g, "f": start_g}]
	var best := {_world.index_of(from_tile): start_g}
	var came_from := {}
	var closed := {}
	var expanded := 0
	while not open_heap.is_empty():
		expanded += 1
		if expanded > _node_limit:
			return _invalid("No route within reach — the valley is in the way", from_tile, to_tile)
		var best_index := 0
		var best_f := float(open_heap[0]["f"])
		for index in open_heap.size():
			if float(open_heap[index]["f"]) < best_f:
				best_f = float(open_heap[index]["f"])
				best_index = index
		var node: Dictionary = open_heap[best_index]
		open_heap.remove_at(best_index)
		var tile: Vector2i = node["tile"]
		var index := _world.index_of(tile)
		if closed.has(index):
			continue
		closed[index] = true
		if tile == to_tile:
			return _finalise(_reconstruct(came_from, tile))
		for direction in RailDirections.COUNT:
			var neighbour := tile + RailDirections.offset(direction)
			if not _world.in_bounds(neighbour):
				continue
			var neighbour_index := _world.index_of(neighbour)
			if closed.has(neighbour_index):
				continue
			var edge := _edge_cost(tile, neighbour, int(node["dir"]), direction)
			if edge < 0.0:
				continue
			var tentative: float = float(node["g"]) + edge
			if best.has(neighbour_index) and tentative >= float(best[neighbour_index]):
				continue
			best[neighbour_index] = tentative
			came_from["%d:%d" % [neighbour_index, direction]] = [index, int(node["dir"])]
			open_heap.append({
				"tile": neighbour, "dir": direction, "g": tentative,
				"f": tentative + _heuristic(neighbour, to_tile),
			})
	return _invalid("No route found", from_tile, to_tile)


func _endpoint_reason(from_tile: Vector2i, to_tile: Vector2i) -> String:
	var start_reason := _placement_reason(from_tile)
	if start_reason != "":
		return start_reason
	return _placement_reason(to_tile)


func _placement_reason(tile: Vector2i) -> String:
	if not _world.in_bounds(tile):
		return "Outside the map"
	if _world.terrain_at(tile) == WorldGrid.Terrain.WATER:
		return "Cannot build on water"
	var occupancy := _world.occupancy_at(tile)
	if occupancy == WorldGrid.Occupancy.STATION:
		return "A station already occupies this site"
	if occupancy == WorldGrid.Occupancy.INDUSTRY:
		return "An industry already occupies this site"
	if occupancy == WorldGrid.Occupancy.TOWN:
		return "This is town ground"
	return ""


## Returns -1 when the edge is impossible.
func _edge_cost(from_tile: Vector2i, to_tile: Vector2i, previous_direction: int, direction: int) -> float:
	var delta := _world.height_at(to_tile) - _world.height_at(from_tile)
	if absi(delta) > RailNetwork.MAX_SLOPE_STEPS:
		return -1.0
	var reason := _placement_reason(to_tile)
	if reason != "":
		return -1.0
	if _world.occupancy_at(to_tile) == WorldGrid.Occupancy.RAIL and not _rail.network.has_rail(to_tile):
		return -1.0
	var cost := _cell_cost(to_tile, direction)
	if _rail.network.has_rail(to_tile):
		cost *= (1.0 - _reuse_bonus)
	if delta > 0:
		cost += _slope_penalty
	cost += RailDirections.turn_penalty(previous_direction, direction, _turn_penalty)
	return cost


func _cell_cost(tile: Vector2i, direction: int) -> float:
	var cost := 1.0 if (direction < 0 or not RailDirections.is_diagonal(direction)) else 1.4142135623730951
	match _world.terrain_at(tile):
		WorldGrid.Terrain.ROCK:
			cost *= 1.7
		WorldGrid.Terrain.FOREST:
			cost *= 1.15
		WorldGrid.Terrain.DIRT:
			cost *= 1.1
	return cost


func _heuristic(from: Vector2i, to: Vector2i) -> float:
	var delta := Vector2(to.x - from.x, to.y - from.y)
	return maxf(absf(delta.x), absf(delta.y)) + 0.41421356 * minf(absf(delta.x), absf(delta.y))


func _reconstruct(came_from: Dictionary, goal: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = [goal]
	var tile := goal
	var guard := 0
	while guard < 20000:
		guard += 1
		var found := false
		for direction in RailDirections.COUNT:
			var key := "%d:%d" % [_world.index_of(tile), direction]
			if came_from.has(key):
				var parent: Array = came_from[key]
				tile = _world.tile_at(int(parent[0]))
				tiles.push_front(tile)
				found = true
				break
		if not found:
			break
	return tiles


func _finalise(tiles: Array[Vector2i]) -> Dictionary:
	var cost := 0.0
	var straight_count := 0
	for index in tiles.size():
		if index > 0:
			var direction := _rail.direction_between(tiles[index - 1], tiles[index])
			cost += _tile_cost_for(tiles[index], direction)
			if RailDirections.is_diagonal(direction):
				straight_count += 1
		var delta := 0
		if index > 0:
			delta = _world.height_at(tiles[index]) - _world.height_at(tiles[index - 1])
		if delta != 0:
			cost += _registry.track_setting("slope_surcharge", 700.0)
	return {
		"ok": true,
		"reason": "",
		"tiles": tiles,
		"cost": Money.round(cost),
		"length": float(tiles.size()),
		"expensive": false,
	}


func _tile_cost_for(tile: Vector2i, direction: int) -> float:
	var base := _registry.track_setting("cost_per_diagonal", 1350.0) if RailDirections.is_diagonal(direction) else _registry.track_setting("cost_per_straight", 950.0)
	var surcharge := 0.0
	match _world.terrain_at(tile):
		WorldGrid.Terrain.ROCK:
			surcharge = base * 0.45
		WorldGrid.Terrain.FOREST:
			surcharge = base * 0.1
	return base + surcharge


## A route is "valid but expensive" when it costs more than the straight-line
## minimum by the configured multiplier — the yellow preview state.
func mark_expensive(result: Dictionary) -> Dictionary:
	if not bool(result.get("ok", false)):
		return result
	var tiles: Array[Vector2i] = result["tiles"]
	if tiles.size() < 2:
		return result
	var span := WorldCoords.distance_tiles(tiles[0], tiles[tiles.size() - 1])
	var cheapest := maxf(1.0, span) * _registry.track_setting("cost_per_straight", 950.0)
	var threshold := cheapest * _registry.track_setting("expensive_route_multiplier", 1.6)
	result["expensive"] = float(result["cost"]) > threshold
	result["cheapest_reference"] = Money.round(cheapest)
	return result


func _invalid(reason: String, from_tile: Vector2i, to_tile: Vector2i) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"tiles": [from_tile, to_tile] as Array[Vector2i],
		"cost": 0.0,
		"length": 0.0,
		"expensive": false,
	}
