class_name TestWorldFactory
extends RefCounted

## Builds small synthetic worlds so a test can state exactly the situation it
## is checking, instead of depending on the shipped map's geography.

const FLAT := 4


static func blank(width: int = 24, height: int = 24, height_step: int = FLAT) -> WorldGrid:
	var world := WorldGrid.new(width, height)
	for y in height:
		for x in width:
			world.set_silent(Vector2i(x, y), WorldGrid.Terrain.PLAIN, height_step, 0)
	world.take_dirty_tiles()
	world.take_dirty_chunks()
	world.reset_counters()
	return world


static func with_water_column(width: int = 24, height: int = 24, at_x: int = 12) -> WorldGrid:
	var world := blank(width, height)
	for y in height:
		world.terrain[world.index_of(Vector2i(at_x, y))] = WorldGrid.Terrain.WATER
		world.height_steps[world.index_of(Vector2i(at_x, y))] = 2
	return world


## A river that blocks a corridor but leaves an open end, so a route exists
## only by detouring — the shape that produces an "expensive" preview.
static func with_water_wall(width: int = 24, height: int = 24, at_x: int = 12, from_y: int = 0, to_y: int = -1) -> WorldGrid:
	var world := blank(width, height)
	var last_y := height - 1 if to_y < 0 else mini(to_y, height - 1)
	for y in range(from_y, last_y + 1):
		world.terrain[world.index_of(Vector2i(at_x, y))] = WorldGrid.Terrain.WATER
	return world


static func with_slope(width: int = 24, height: int = 24, step_from_x: int = 12) -> WorldGrid:
	var world := blank(width, height)
	for y in height:
		for x in width:
			var step := FLAT + (1 if x >= step_from_x else 0)
			world.height_steps[world.index_of(Vector2i(x, y))] = step
	return world


static func with_cliff(width: int = 24, height: int = 24, at_x: int = 12) -> WorldGrid:
	var world := blank(width, height)
	for y in height:
		for x in width:
			world.height_steps[world.index_of(Vector2i(x, y))] = FLAT + (4 if x >= at_x else 0)
	return world
