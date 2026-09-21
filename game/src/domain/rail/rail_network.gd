class_name RailNetwork
extends RefCounted

## The logical rail graph.
##
## Connections live as one byte per cell inside the WorldGrid; the graph is
## derived from those bytes on demand and is never stored twice.  Every
## intersection is a connected junction in V1 — grade separation is not
## representable.

const MAX_SLOPE_STEPS := 1

var _world: WorldGrid


func attach(world: WorldGrid) -> void:
	_world = world


func world() -> WorldGrid:
	return _world


func mask(tile: Vector2i) -> int:
	return _world.rail_mask_at(tile)


func set_mask(tile: Vector2i, value: int) -> void:
	_world.set_rail_mask(tile, value)


func has_rail(tile: Vector2i) -> bool:
	## Presence, not connectivity: a dead-end stub is a cell of the network even
	## while nothing points out of it.
	return _world.has_rail_cell(tile)


func connection_count(tile: Vector2i) -> int:
	return RailDirections.count_connections(mask(tile))


func is_junction(tile: Vector2i) -> bool:
	return connection_count(tile) >= 3


func is_straight(tile: Vector2i) -> bool:
	var value := mask(tile)
	if value == 0:
		return false
	var dirs := RailDirections.directions_in(value)
	if dirs.size() != 2:
		return false
	return RailDirections.opposite(dirs[0]) == dirs[1]


func is_curve(tile: Vector2i) -> bool:
	var dirs := RailDirections.directions_in(mask(tile))
	return dirs.size() == 2 and RailDirections.opposite(dirs[0]) != dirs[1]


func connected_tiles(tile: Vector2i) -> Array[Vector2i]:
	return RailDirections.neighbors(tile, mask(tile))


## Establishes a connection both ways.  Returns false when the far side cannot
## accept it, leaving the network untouched.
func connect_direction(tile: Vector2i, direction: int) -> bool:
	var other := tile + RailDirections.offset(direction)
	if not _world.in_bounds(other):
		return false
	_world.set_rail_cell(tile, true)
	_world.set_rail_cell(other, true)
	_world.set_rail_mask(tile, mask(tile) | (1 << direction))
	_world.set_rail_mask(other, mask(other) | (1 << RailDirections.opposite(direction)))
	return true


func disconnect_direction(tile: Vector2i, direction: int) -> void:
	var other := tile + RailDirections.offset(direction)
	_world.set_rail_mask(tile, mask(tile) & ~(1 << direction))
	if _world.in_bounds(other):
		_world.set_rail_mask(other, mask(other) & ~(1 << RailDirections.opposite(direction)))


## Removes a cell and every connection pointing into it, so no dangling
## connection can survive on a neighbour.
func remove_cell(tile: Vector2i) -> void:
	if not _world.has_rail_cell(tile):
		return
	var value := mask(tile)
	_world.set_rail_cell(tile, false)
	for direction in RailDirections.directions_in(value):
		var other := tile + RailDirections.offset(direction)
		if _world.in_bounds(other):
			_world.set_rail_mask(other, mask(other) & ~(1 << RailDirections.opposite(direction)))


func slope_ok(from: Vector2i, to: Vector2i) -> bool:
	return absi(_world.height_at(from) - _world.height_at(to)) <= MAX_SLOPE_STEPS


func slope_delta(from: Vector2i, to: Vector2i) -> int:
	return _world.height_at(to) - _world.height_at(from)


## Elevation change along the mask, for slope piece selection.
func max_uphill_delta(tile: Vector2i) -> int:
	var best := 0
	for neighbour in connected_tiles(tile):
		best = maxi(best, _world.height_at(neighbour) - _world.height_at(tile))
	return best


func occupancy_kind(tile: Vector2i) -> int:
	return _world.occupancy_at(tile)


## Snapshots the network for undo: mask per touched tile.
func snapshot(tiles: Array[Vector2i]) -> Dictionary:
	var state := {}
	for tile in tiles:
		state[_world.index_of(tile)] = mask(tile)
	return state


func restore(state: Dictionary) -> Array[Vector2i]:
	var restored: Array[Vector2i] = []
	for index in state.keys():
		var tile := _world.tile_at(int(index))
		_world.set_rail_mask(tile, int(state[index]))
		restored.append(tile)
	return restored
