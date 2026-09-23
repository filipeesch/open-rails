class_name WorldCoords
extends RefCounted

## Tile ⇄ world conversions.  The single place the coordinate convention lives.
##
## A tile's centre sits at `(tile + 0.5) * TILE_SIZE`; elevation is
## `height_steps * HEIGHT_STEP`.  Anything that needs a ground position goes
## through here so the convention can never drift.


static func tile_to_world(tile: Vector2i, height_steps: int = 0) -> Vector3:
	return Vector3(
		(tile.x + 0.5) * WorldConstants.TILE_SIZE,
		height_steps * WorldConstants.HEIGHT_STEP,
		(tile.y + 0.5) * WorldConstants.TILE_SIZE
	)


static func world_to_tile(position: Vector3) -> Vector2i:
	return Vector2i(
		floori(position.x / WorldConstants.TILE_SIZE),
		floori(position.z / WorldConstants.TILE_SIZE)
	)


static func world_to_tile_floor(position: Vector2) -> Vector2i:
	return Vector2i(
		floori(position.x / WorldConstants.TILE_SIZE),
		floori(position.y / WorldConstants.TILE_SIZE)
	)


static func tile_to_world_xz(tile: Vector2i) -> Vector2:
	return Vector2(
		(tile.x + 0.5) * WorldConstants.TILE_SIZE,
		(tile.y + 0.5) * WorldConstants.TILE_SIZE
	)


static func height_to_world(height_steps: int) -> float:
	return height_steps * WorldConstants.HEIGHT_STEP


static func world_to_height(world_y: float) -> int:
	return roundi(world_y / WorldConstants.HEIGHT_STEP)


static func tile_center_of_span(min_tile: Vector2i, size: Vector2i) -> Vector2i:
	return min_tile + (size / 2)


static func tiles_in_span(min_tile: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for dy in range(size.y):
		for dx in range(size.x):
			tiles.append(min_tile + Vector2i(dx, dy))
	return tiles


static func tiles_in_radius(centre: Vector2i, radius: float) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var r := int(ceilf(radius))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if Vector2(dx, dy).length() <= radius:
				tiles.append(centre + Vector2i(dx, dy))
	return tiles


static func distance_tiles(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a.x - b.x, a.y - b.y).length()


static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return int(maxi(absi(a.x - b.x), absi(a.y - b.y)))


## The yaw that aims a model's own +X along a tile-space direction.
##
## Rolling stock and stations are authored with their length along +X — the art
## library says so out loud: `forward +X, axle Y` — while the world lays a tile's
## second axis down world Z, and Godot's Y rotation sends local +X to
## `(cos θ, -sin θ)`.  So the angle a model needs is not the angle of the
## direction as it reads on the tile grid, and the difference is not subtle: get it
## wrong and a train is drawn broadside to its own rails.  Everything that has to
## lie along a track asks here, so a vehicle and the platform beside it cannot
## disagree about which way the line runs.
static func yaw_for_direction(direction: Vector2) -> float:
	if direction == Vector2.ZERO:
		return 0.0
	return atan2(-direction.y, direction.x)


## `yaw_for_direction` in degrees, for a node driven by `rotation_degrees`.
static func yaw_degrees_for_direction(direction: Vector2) -> float:
	return rad_to_deg(yaw_for_direction(direction))
