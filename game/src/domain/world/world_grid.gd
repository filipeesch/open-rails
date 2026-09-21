class_name WorldGrid
extends RefCounted

## Authoritative tile state, held as compact arrays.
##
## There is deliberately no object per tile: a 256 × 256 map is 65,536 cells
## stored in five packed arrays, and the number of scene nodes holding world
## state never varies with map size.  Rendering is a projection of this data.

enum Terrain { GRASS = 0, DIRT = 1, ROCK = 2, WATER = 3, FOREST = 4, HILL = 5, PLAIN = 6 }
enum Occupancy { NONE = 0, RAIL = 1, STATION = 2, TOWN = 3, INDUSTRY = 4, BUILDING = 5, SCENERY = 6 }

const OCCUPANCY_NAMES: PackedStringArray = [
	"none", "rail", "station", "town", "industry", "building", "scenery",
]

## The authored vocabulary for `Terrain`, in enum order.  A map file names
## terrain with these words, so the enum and its words live in one place.
const TERRAIN_NAMES: PackedStringArray = [
	"grass", "dirt", "rock", "water", "forest", "hill", "plain",
]


## The enum code for an authored terrain word, or -1 when the word is not one.
## Unknown words come back as -1 rather than as some default terrain, so a typo
## in a map file can be reported instead of quietly redrawn as something else.
static func terrain_code_of_name(name: String) -> int:
	for index in TERRAIN_NAMES.size():
		if TERRAIN_NAMES[index] == name:
			return index
	return -1

var width: int = 0
var height: int = 0

var terrain: PackedByteArray
var height_steps: PackedByteArray
var occupancy_kind: PackedByteArray
var occupancy_id: PackedInt64Array
var rail: PackedByteArray
## Which cells hold a piece of track at all.  A mask alone cannot say this: a
## dead-end stub — a station approach, or a line mid-construction — is real
## track carrying zero connections, so presence needs its own byte.
var rail_present: PackedByteArray

## Tiles touched since the last flush.  Presentation rebuilds exactly these.
var _dirty_tiles: Dictionary = {}
var _rebuild_count: int = 0
var _chunk_dirty: Dictionary = {}


func _init(p_width: int = WorldConstants.MAP_WIDTH, p_height: int = WorldConstants.MAP_HEIGHT) -> void:
	resize(p_width, p_height)


func resize(p_width: int, p_height: int) -> void:
	width = p_width
	height = p_height
	var cells := p_width * p_height
	terrain = PackedByteArray()
	terrain.resize(cells)
	height_steps = PackedByteArray()
	height_steps.resize(cells)
	occupancy_kind = PackedByteArray()
	occupancy_kind.resize(cells)
	occupancy_id = PackedInt64Array()
	occupancy_id.resize(cells)
	rail = PackedByteArray()
	rail.resize(cells)
	rail_present = PackedByteArray()
	rail_present.resize(cells)
	_dirty_tiles.clear()
	_chunk_dirty.clear()


func clear_state() -> void:
	## Wipe occupancy, rail and dirtiness, keeping the dimensions.  Used when a
	## session restarts in place instead of being thrown away.
	resize(width, height)
	_rebuild_count = 0


func in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < width and tile.y < height


func index_of(tile: Vector2i) -> int:
	return tile.y * width + tile.x


func tile_at(index: int) -> Vector2i:
	return Vector2i(index % width, int(index / width))


func terrain_at(tile: Vector2i) -> int:
	if not in_bounds(tile):
		return Terrain.ROCK
	return terrain[index_of(tile)]


func is_water(tile: Vector2i) -> bool:
	return terrain_at(tile) == Terrain.WATER


func height_at(tile: Vector2i) -> int:
	if not in_bounds(tile):
		return 0
	return height_steps[index_of(tile)]


func elevation_at(tile: Vector2i) -> float:
	return WorldCoords.height_to_world(height_at(tile))


func elevation_at_world(position: Vector3) -> float:
	return elevation_at(WorldCoords.world_to_tile(position))


func occupancy_at(tile: Vector2i) -> int:
	if not in_bounds(tile):
		return Occupancy.NONE
	return occupancy_kind[index_of(tile)]


func occupancy_entity(tile: Vector2i) -> int:
	if not in_bounds(tile):
		return 0
	return occupancy_id[index_of(tile)]


func occupancy_name(kind: int) -> String:
	if kind >= 0 and kind < OCCUPANCY_NAMES.size():
		return OCCUPANCY_NAMES[kind]
	return "unknown"


func rail_mask_at(tile: Vector2i) -> int:
	if not in_bounds(tile):
		return 0
	return rail[index_of(tile)]


func is_rail(tile: Vector2i) -> bool:
	if not in_bounds(tile):
		return false
	return rail_present[index_of(tile)] != 0


## Presence is deliberately separate from the mask: the graph asks "is there
## track here", the mask asks "where does it lead".
func has_rail_cell(tile: Vector2i) -> bool:
	return is_rail(tile)


func set_rail_cell(tile: Vector2i, present: bool) -> void:
	if not in_bounds(tile):
		return
	var index := index_of(tile)
	var value := 1 if present else 0
	if rail_present[index] == value:
		return
	rail_present[index] = value
	mark_dirty(tile)
	if not present:
		rail[index] = 0


# --- mutation -------------------------------------------------------------

func set_terrain(tile: Vector2i, kind: int) -> void:
	if not in_bounds(tile):
		return
	terrain[index_of(tile)] = kind
	mark_dirty(tile)


func set_height(tile: Vector2i, steps: int) -> void:
	if not in_bounds(tile):
		return
	height_steps[index_of(tile)] = steps
	mark_dirty(tile)


func set_occupancy(tile: Vector2i, kind: int, entity_id: int) -> void:
	if not in_bounds(tile):
		return
	var index := index_of(tile)
	occupancy_kind[index] = kind
	occupancy_id[index] = entity_id
	mark_dirty(tile)


## Occupancy written without the dirty bookkeeping.
##
## This is the write path for state that *arrives with the map* — scenery the
## author planted — as opposed to state a player changed.  A player edit has to
## reach the chunk rebuild queue; sixty thousand cells of authored content must
## not, or booting a valley would queue the whole map for a rebuild it has
## already done.  `MapDocument` and `MapFeatures` are the callers that matter:
## authored content is never an edit.
func set_occupancy_silent(tile: Vector2i, kind: int, entity_id: int) -> void:
	if not in_bounds(tile):
		return
	var index := index_of(tile)
	occupancy_kind[index] = kind
	occupancy_id[index] = entity_id


func clear_occupancy(tile: Vector2i) -> void:
	set_occupancy(tile, Occupancy.NONE, 0)


func set_rail_mask(tile: Vector2i, mask: int) -> void:
	if not in_bounds(tile):
		return
	rail[index_of(tile)] = mask
	# A live connection implies a piece of track.  Losing every connection
	# does not imply the opposite - a dead-end stub is still track - so
	# presence is cleared only through set_rail_cell().
	if mask != 0:
		rail_present[index_of(tile)] = 1
	mark_dirty(tile)


func set_silent(tile: Vector2i, p_terrain: int, p_height: int, p_scenery: int) -> void:
	var index := index_of(tile)
	terrain[index] = p_terrain
	height_steps[index] = p_height
	if p_scenery != 0:
		occupancy_kind[index] = Occupancy.SCENERY
		occupancy_id[index] = p_scenery


# --- construction validity ------------------------------------------------

## Single authority for "may a structure go here".  Returns a reason string
## that is safe to show to the player verbatim.
func build_reason(tile: Vector2i) -> String:
	if not in_bounds(tile):
		return "Outside the map"
	if terrain_at(tile) == Terrain.WATER:
		return "Cannot build on water"
	var kind := occupancy_at(tile)
	if kind == Occupancy.SCENERY:
		return "Clear the scenery first"
	if kind == Occupancy.RAIL:
		return "Track already occupies this tile"
	if kind == Occupancy.STATION:
		return "A station already occupies this site"
	if kind == Occupancy.INDUSTRY:
		return "An industry already occupies this site"
	if kind == Occupancy.TOWN:
		return "This is town ground"
	return ""


func can_build(tile: Vector2i) -> bool:
	return build_reason(tile) == ""


# --- change bookkeeping ---------------------------------------------------

func mark_dirty(tile: Vector2i) -> void:
	_dirty_tiles[index_of(tile)] = true
	_mark_chunk_dirty(tile)


func _mark_chunk_dirty(tile: Vector2i) -> void:
	var chunk := chunk_of(tile)
	_chunk_dirty[chunk] = true
	# A mesh edge depends on the neighbouring tile just outside the chunk, so a tile
	# on a boundary makes up to four chunks dirty.  A tile at a chunk *corner* is
	# geometry inside the diagonal neighbour's skirt as much as inside the two edge
	# neighbours', so the diagonal has to be named too — leaving it out leaves a
	# one-tile seam in the mesh after a corner edit.
	var size := WorldConstants.CHUNK_SIZE
	var offset := tile - chunk * size
	var step_x := 0
	if offset.x == 0:
		step_x = -1
	elif offset.x == size - 1:
		step_x = 1
	var step_y := 0
	if offset.y == 0:
		step_y = -1
	elif offset.y == size - 1:
		step_y = 1
	var deltas: Array[Vector2i] = []
	if step_x != 0:
		deltas.append(Vector2i(step_x, 0))
	if step_y != 0:
		deltas.append(Vector2i(0, step_y))
	if step_x != 0 and step_y != 0:
		deltas.append(Vector2i(step_x, step_y))
	for delta in deltas:
		_dirty_chunks_add(chunk, delta)


func _dirty_chunks_add(chunk: Vector2i, delta: Vector2i) -> void:
	_chunk_dirty[chunk + delta] = true


func chunk_of(tile: Vector2i) -> Vector2i:
	var size := WorldConstants.CHUNK_SIZE
	return Vector2i(int(floorf(tile.x / float(size))), int(floorf(tile.y / float(size))))


func chunk_count() -> Vector2i:
	var size := WorldConstants.CHUNK_SIZE
	return Vector2i(int(ceilf(width / float(size))), int(ceilf(height / float(size))))


func take_dirty_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for index in _dirty_tiles.keys():
		tiles.append(tile_at(index))
	_dirty_tiles.clear()
	return tiles


func take_dirty_chunks() -> Array[Vector2i]:
	var chunks: Array[Vector2i] = []
	for chunk in _chunk_dirty.keys():
		chunks.append(chunk)
	_chunk_dirty.clear()
	return chunks


func has_dirty_chunks() -> bool:
	return not _chunk_dirty.is_empty()


func note_geometry_rebuild() -> void:
	_rebuild_count += 1


func geometry_rebuild_count() -> int:
	return _rebuild_count


func reset_counters() -> void:
	_rebuild_count = 0


func total_tiles() -> int:
	return width * height
