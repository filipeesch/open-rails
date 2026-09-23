class_name TerrainRenderer
extends Node3D

## Turns WorldGrid's typed arrays into chunked vertex-coloured meshes.
##
## One MeshInstance3D per 32×32 chunk — 64 for the whole map, never one per
## tile.  A chunk is rebuilt only when `WorldGrid` reports it dirty, so a rail
## edit costs four chunk rebuilds and nothing else.

signal chunk_rebuilt(chunk: Vector2i, triangles: int)

const MAX_CHUNKS_PER_FRAME := 4
## How far past its own tiles a chunk generates geometry.  A chunk mesh reaches
## one tile into every neighbour, so a crack between two chunks is impossible:
## whichever side is drawn, the shared edge has been built.
const SKIRT := 1
const PALETTE := {
	WorldGrid.Terrain.PLAIN: Color(0.55, 0.62, 0.38),
	WorldGrid.Terrain.GRASS: Color(0.42, 0.58, 0.30),
	WorldGrid.Terrain.FOREST: Color(0.24, 0.40, 0.22),
	WorldGrid.Terrain.DIRT: Color(0.56, 0.44, 0.30),
	WorldGrid.Terrain.ROCK: Color(0.55, 0.55, 0.52),
	WorldGrid.Terrain.WATER: Color(0.28, 0.46, 0.58),
	WorldGrid.Terrain.HILL: Color(0.46, 0.49, 0.33),
}
## Scenery occupancy ids to asset ids.  Scenery is decoration, so an unknown id
## draws a tree rather than nothing: an unmapped id is then obvious in-world.
const SCENERY_ASSETS := {1: "tree", 2: "rock", 3: "bush"}
const DEFAULT_SCENERY_ASSET := "tree"
const HEIGHT_VARIANT := 0.02
const NOISE_AMOUNT := 0.055
## How far a body swings, and how often.  A tide the size of a fingernail, at the
## pace of breath: enough to see the water is not painted on, cheap enough that it
## costs one float per body per frame.
const WATER_BOB_AMPLITUDE := 0.045
const WATER_BOB_RATE := 0.85
## How far from the view a body may be and still be moved.  Beyond it the surface
## is not drawn larger than a pixel, and animating it would be work for no one.
const WATER_NEAR_TILES := 120.0
const NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const QUAD_CORNERS: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]

var world: WorldGrid
var material: StandardMaterial3D
var water_material: StandardMaterial3D
var water_bodies_root: Node3D
var catalog: ModelCatalog
## Where the player is looking, as a world position.  Set by the game root from the
## camera rig; left unset, every body is animated, because a renderer with no view
## has no business deciding what the player cannot see.
var view_source: Callable = Callable()

var _chunks := {}
var _scenery := {}
var _water_quads := 0
var _water_bodies: Array[Dictionary] = []
## Which body each cell belongs to, or -1 for dry ground.  The renderer needs the
## answer per tile — a test, a tooltip and the shoreline effect all ask "which
## surface is this?" — and it must not have to walk a river to say so.
var _water_body_of_cell := PackedInt32Array()
var _water_rebuilds := 0
var _water_animated := 0
var _water_time := 0.0
var _pending: Array[Vector2i] = []
var _rebuilt_total := 0
var _rebuilt_this_second := 0
var _triangle_total := 0
var _visible_chunks := 0
var _timer := 0.0


func _init() -> void:
	material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.94
	material.metallic = 0.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	water_material = StandardMaterial3D.new()
	water_material.vertex_color_use_as_albedo = true
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	water_material.roughness = 0.25
	water_material.metallic = 0.1
	catalog = ModelCatalog.new()


func attach(grid: WorldGrid) -> void:
	world = grid
	water_bodies_root = Node3D.new()
	water_bodies_root.name = "WaterBodies"
	add_child(water_bodies_root)
	_build_all()


## Advance the renderer's own work.  `delta` is the frame time; left out, the node's
## process delta is used, and a test may hand in the clock it wants to see.
func tick(delta: float = -1.0) -> void:
	if world == null:
		return
	_animate_water(delta if delta >= 0.0 else get_process_delta_time())
	for chunk in world.take_dirty_chunks():
		_queue(chunk)
	# The grid reports the chunk that holds the tile; the skirt means the mesh of
	# a neighbouring chunk contains that tile's geometry too, so the renderer —
	# which owns the skirt width — works out the full set from the dirty tiles.
	for tile in world.take_dirty_tiles():
		for chunk in _affected_chunks(tile):
			_queue(chunk)
	if world.has_dirty_chunks():
		return
	var budget := MAX_CHUNKS_PER_FRAME
	while not _pending.is_empty() and budget > 0:
		var chunk: Vector2i = _pending.pop_front()
		_rebuild_chunk(chunk)
		budget -= 1
	_timer += get_process_delta_time()
	if _timer >= 1.0:
		_timer = 0.0
		_rebuilt_this_second = 0


## Queue a chunk for rebuild, once, and only if it is a real chunk of this map.
## `WorldGrid` reports neighbour chunks that fall off the edge of an 8×8 grid;
## building those would add nodes that hold no geometry.
func _queue(chunk: Vector2i) -> void:
	if world == null:
		return
	var grid := world.chunk_count()
	if chunk.x < 0 or chunk.y < 0 or chunk.x >= grid.x or chunk.y >= grid.y:
		return
	if not _pending.has(chunk):
		_pending.append(chunk)


## Which chunk meshes a single tile edit changes.  Because every chunk draws a
## one-tile skirt, a tile on a seam is geometry inside the neighbour as well: the
## four chunks meeting at a corner tile all contain it.  Never more than four.
func _affected_chunks(tile: Vector2i) -> Array[Vector2i]:
	var size := WorldConstants.CHUNK_SIZE
	var base := Vector2i(floori(tile.x / float(size)), floori(tile.y / float(size)))
	var columns: Array[int] = [0]
	if tile.x % size == 0:
		columns.append(-1)
	elif tile.x % size == size - 1:
		columns.append(1)
	var rows: Array[int] = [0]
	if tile.y % size == 0:
		rows.append(-1)
	elif tile.y % size == size - 1:
		rows.append(1)
	var affected: Array[Vector2i] = []
	for row in rows:
		for column in columns:
			affected.append(base + Vector2i(column, row))
	return affected


func rebuild_count() -> int:
	return _rebuilt_total


func rebuilds_this_second() -> int:
	return _rebuilt_this_second


func pending_rebuilds() -> int:
	return _pending.size()


func triangle_total() -> int:
	return _triangle_total


func live_chunk_nodes() -> int:
	return _chunks.size()


func visible_chunk_count() -> int:
	return _visible_chunks


## The chunk's node, or null.  Exposed because a test — and the F3 overlay —
## needs to inspect one chunk's mesh without knowing the node's generated name.
func chunk_node(chunk: Vector2i) -> MeshInstance3D:
	var node: MeshInstance3D = _chunks.get(_chunk_key(chunk))
	return node


## The world-space extent of a chunk's geometry, including its skirt.  An empty
## AABB means the chunk was never built.
func chunk_aabb(chunk: Vector2i) -> AABB:
	var node := chunk_node(chunk)
	if node == null or node.mesh == null:
		return AABB()
	return node.get_aabb()


## How much ground geometry sits in the skirt rather than the chunk itself.
func skirt_tiles() -> int:
	var size := WorldConstants.CHUNK_SIZE
	return (size + SKIRT + SKIRT) * (size + SKIRT + SKIRT) - size * size


func scenery_node_count() -> int:
	return _scenery.size()


## Instances, not nodes: this is what a forest costs, and the number of scene
## nodes it contributes never moves with it.
func scenery_instance_total() -> int:
	var total := 0
	for key in _scenery.keys():
		var node: MultiMeshInstance3D = _scenery[key]
		if node.multimesh != null:
			total += node.multimesh.instance_count
	return total


func water_quads() -> int:
	return _water_quads


## How many separate surfaces the water became — one per body, not one per tile
## and not one for the whole map.  Two lakes that share no edge are two bodies, so
## they can be moved, and skipped, separately.
func water_body_count() -> int:
	return _water_bodies.size()


func water_body_nodes() -> Array[MeshInstance3D]:
	var nodes: Array[MeshInstance3D] = []
	for body in _water_bodies:
		nodes.append(body["node"])
	return nodes


## The surface a water tile belongs to, or null when the tile is dry ground.
func water_body_at(tile: Vector2i) -> MeshInstance3D:
	if world == null or not world.in_bounds(tile):
		return null
	if world.terrain_at(tile) != WorldGrid.Terrain.WATER:
		return null
	var wanted := tile.y * world.width + tile.x
	if wanted < 0 or wanted >= _water_body_of_cell.size():
		return null
	var index := int(_water_body_of_cell[wanted])
	if index < 0 or index >= _water_bodies.size():
		return null
	return _water_bodies[index]["node"]


func water_rebuilds() -> int:
	return _water_rebuilds


## Bodies moved on the last frame.  This is the whole per-frame cost of the water,
## in units a reader can check: zero means nothing was written for it.
func water_animated_last_tick() -> int:
	return _water_animated


## Where the water thinks the player is.  Public because the test and the debug
## overlay both need to ask what the renderer believed, rather than guess.
func water_view_focus() -> Vector3:
	return _view_focus()


## Move every body the player can still resolve as a surface.
##
## The animation is a transform, not a simulation: no state accumulates, nothing
## per tile is touched, and a body outside the view is skipped by a distance
## comparison rather than by building anything.  Water is presentation, so the
## clock it reads is the frame clock — the simulation never sees it.
func _animate_water(delta: float) -> void:
	_water_time += delta
	_water_animated = 0
	var focus := _view_focus()
	for body in _water_bodies:
		var reach := maxf(WATER_NEAR_TILES, float(body["radius"]))
		if focus != Vector3.INF and focus.distance_to(body["centre"]) > reach:
			continue
		var node: MeshInstance3D = body["node"]
		var base := Vector3(body["centre"])
		base.y += WATER_BOB_AMPLITUDE * sin(_water_time * WATER_BOB_RATE + float(body["phase"]))
		node.position = base
		_water_animated += 1


func _view_focus() -> Vector3:
	if not view_source.is_valid():
		return Vector3.INF
	var value: Variant = view_source.call()
	return value if typeof(value) == TYPE_VECTOR3 else Vector3.INF





## Ground elevation under a world position.  Placement ghosts, drop shadows and
## pointer rays all ask this, and none of them may need a mesh to answer: the
## sample reads the height array, so it is the same cost offscreen as on.
func sample_height(world_position: Vector3) -> float:
	if world == null:
		return 0.0
	return world.elevation_at(WorldCoords.world_to_tile(world_position))


func force_full_rebuild() -> void:
	_rebuild_all()


## Water, as one surface per body: a flood fill groups the cells, and each group
## becomes a single translucent mesh sitting two steps below the banks so the
## shoreline reads as an edge.  Per body rather than one sheet for the whole map,
## because the body is the unit the player sees and the unit a frame can skip: the
## river can breathe while the lake is offscreen and costs nothing.
func _rebuild_water() -> void:
	_water_rebuilds += 1
	for body in _water_bodies:
		var old: MeshInstance3D = body["node"]
		old.free()
	_water_bodies.clear()
	var seen := PackedByteArray()
	seen.resize(world.width * world.height)
	_water_body_of_cell.resize(world.width * world.height)
	_water_body_of_cell.fill(-1)
	for y in world.height:
		for x in world.width:
			var start := y * world.width + x
			if seen[start] == 1 or world.terrain[start] != WorldGrid.Terrain.WATER:
				continue
			var cells := _flood_water(start, seen)
			for cell in cells:
				_water_body_of_cell[cell] = _water_bodies.size()
			_water_bodies.append(_make_water_body(cells, _water_bodies.size()))
	_water_quads = 0
	for body in _water_bodies:
		_water_quads += int(body["quads"])


## The connected run of water cells containing `start`, marked as seen in place.
## Four-neighbour on purpose: water that only touches at a corner is two bodies
## that happen to meet, and drawing them apart is the honest read of the map.
func _flood_water(start: int, seen: PackedByteArray) -> Array[int]:
	var cells: Array[int] = [start]
	var stack: Array[int] = [start]
	seen[start] = 1
	var width := world.width
	while not stack.is_empty():
		var index: int = stack.pop_back()
		var x := index % width
		var y := int(index / float(width))
		for step in NEIGHBOURS:
			var nx: int = x + step.x
			var ny: int = y + step.y
			if nx < 0 or ny < 0 or nx >= world.width or ny >= world.height:
				continue
			var next := ny * width + nx
			if seen[next] == 1 or world.terrain[next] != WorldGrid.Terrain.WATER:
				continue
			seen[next] = 1
			cells.append(next)
			stack.append(next)
	return cells


## One water body: one node, one mesh, one draw call.
##
## The mesh is built in space local to the body's own centre and the node is put
## at that centre, which is what makes the animation cheap: the whole surface
## moves with one transform, so a lake costs a float write per frame whether it is
## twelve tiles or twelve hundred.  No simulation runs here — nothing is stored
## per frame, nothing accumulates, and no physics body exists to be stepped.
func _make_water_body(cells: Array[int], index: int) -> Dictionary:
	var centre := Vector3.ZERO
	for cell in cells:
		centre += Vector3(float(cell % world.width) + 0.5, 0.0,
				float(int(cell / float(world.width))) + 0.5)
	centre /= float(cells.size())
	centre.y = WorldConstants.HEIGHT_STEP * 2.0
	var radius := 0.0
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var colours := PackedColorArray()
	for cell in cells:
		var tile := Vector2i(cell % world.width, int(cell / float(world.width)))
		var start := vertices.size()
		for corner in QUAD_CORNERS:
			var offset := Vector3(corner.x, 0.0, corner.y)
			var local := Vector3(float(tile.x) + offset.x, 0.0, float(tile.y) + offset.y) - centre
			vertices.append(local)
			radius = maxf(radius, Vector2(local.x, local.z).length())
		var tint := Color(0.31, 0.50, 0.62, 0.82).lightened(_noise(tile) * 0.04)
		for _corner in 4:
			colours.append(tint)
		indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.name = "WaterBody_%d" % index
	node.material_override = water_material
	node.position = centre
	node.mesh = mesh
	# Carried on the node because the overlay and the tests both want to know what
	# a surface is made of, and neither should have to count index buffers.
	node.set_meta("quads", cells.size())
	water_bodies_root.add_child(node)
	# The phase comes from the body's position, not from `randf()`: a valley must
	# look the same every time it is opened, and two lakes should not breathe in
	# lockstep because a shared clock would read as one surface, not two.
	return {"node": node, "centre": centre, "radius": radius, "quads": cells.size(),
			"phase": (centre.x * 0.7 + centre.z * 1.3)}



# --- scenery --------------------------------------------------------------

## Which model one scenery occupancy id draws.
func scenery_asset_id(scenery_code: int) -> String:
	return String(SCENERY_ASSETS.get(scenery_code, DEFAULT_SCENERY_ASSET))


## Scenery is instanced, never a node per tree: one `MultiMeshInstance3D` per
## chunk per scenery type carries every instance in that chunk, so a wood costs
## one node whether it holds ten trees or ten thousand.  The node is reused
## across rebuilds; only the instance buffer changes.
func _rebuild_scenery(chunk: Vector2i) -> void:
	var size := WorldConstants.CHUNK_SIZE
	var origin := chunk * size
	var by_asset := {}
	for local_y in size:
		for local_x in size:
			var tile := origin + Vector2i(local_x, local_y)
			if not world.in_bounds(tile):
				continue
			if world.occupancy_at(tile) != WorldGrid.Occupancy.SCENERY:
				continue
			var asset_id := scenery_asset_id(world.occupancy_entity(tile))
			var bucket: Array = by_asset.get(asset_id, [])
			bucket.append(tile)
			by_asset[asset_id] = bucket
	var prefix := "%d:%d:" % [chunk.x, chunk.y]
	var assets: Array = by_asset.keys()
	for key in _scenery.keys():
		var entry := String(key)
		if not entry.begins_with(prefix):
			continue
		var asset_id := entry.trim_prefix(prefix)
		if assets.has(asset_id):
			continue
		# This type has nothing left in the chunk: empty the instances, keep the
		# node, so the scene tree never grows or shrinks with content.
		var emptied: MultiMeshInstance3D = _scenery[key]
		emptied.multimesh.instance_count = 0
	for asset_id in assets:
		_fill_scenery(chunk, String(asset_id), Array(by_asset[asset_id]))


func _fill_scenery(chunk: Vector2i, asset_id: String, tiles: Array) -> void:
	var node := _scenery_node(chunk, asset_id)
	node.multimesh.instance_count = tiles.size()
	for index in tiles.size():
		node.multimesh.set_instance_transform(index, _scenery_transform(tiles[index]))


func _scenery_node(chunk: Vector2i, asset_id: String) -> MultiMeshInstance3D:
	var key := "%d:%d:%s" % [chunk.x, chunk.y, asset_id]
	var node: MultiMeshInstance3D = _scenery.get(key)
	if node != null:
		return node
	node = MultiMeshInstance3D.new()
	node.name = "Scenery_%d_%d_%s" % [chunk.x, chunk.y, asset_id]
	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.use_colors = true
	multi_mesh.mesh = catalog.mesh_for(asset_id)
	node.multimesh = multi_mesh
	# The one vertex-colour material every model in the game shares.
	node.material_override = catalog.shared_material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	_scenery[key] = node
	return node


## Deterministic placement: same map, same trees.  Rotation and scale vary per
## tile so a repeated instance does not read as a copied row.
func _scenery_transform(tile: Vector2i) -> Transform3D:
	var spin := _noise(tile) * PI
	var stretch := lerpf(0.85, 1.30, (_noise(tile + Vector2i(31, 17)) + 1.0) * 0.5)
	var basis := Basis.from_scale(Vector3.ONE * stretch).rotated(Vector3.UP, spin)
	return Transform3D(basis, Vector3(float(tile.x) + 0.5, world.elevation_at(tile), float(tile.y) + 0.5))


func _clear_scenery() -> void:
	for key in _scenery.keys():
		var node: MultiMeshInstance3D = _scenery[key]
		node.queue_free()
	_scenery.clear()


# --- geometry -------------------------------------------------------------

func _build_all() -> void:
	_triangle_total = 0
	_clear_scenery()
	var grid := world.chunk_count()
	for y in grid.y:
		for x in grid.x:
			_rebuild_chunk(Vector2i(x, y))
	_rebuild_water()


func _rebuild_chunk(chunk: Vector2i) -> void:
	if not _is_live_chunk(chunk):
		return
	var origin := chunk * WorldConstants.CHUNK_SIZE
	var node: MeshInstance3D = _chunks.get(_chunk_key(chunk))
	if node == null:
		node = MeshInstance3D.new()
		node.name = "Chunk_%d_%d" % [chunk.x, chunk.y]
		node.material_override = material
		add_child(node)
		_chunks[_chunk_key(chunk)] = node
	var arrays := _build_surface(origin)
	if arrays.is_empty():
		node.mesh = null
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var previous_triangles: int = int(node.get_meta("triangles", 0)) if node.has_meta("triangles") else 0
	node.mesh = mesh
	var triangles := int(arrays[Mesh.ARRAY_INDEX].size() / 3) if arrays[Mesh.ARRAY_INDEX] != null else 0
	node.set_meta("triangles", triangles)
	_triangle_total += triangles - previous_triangles
	_rebuilt_total += 1
	_rebuilt_this_second += 1
	_rebuild_scenery(chunk)
	chunk_rebuilt.emit(chunk, triangles)


## Is this a chunk of the map as it is now?  Neighbour notifications from
## `WorldGrid` can name chunks outside an 8×8 grid, and building one of those
## would add a node holding nothing.
func _is_live_chunk(chunk: Vector2i) -> bool:
	if world == null:
		return false
	var grid := world.chunk_count()
	return chunk.x >= 0 and chunk.y >= 0 and chunk.x < grid.x and chunk.y < grid.y


## A chunk's mesh: one top quad per tile plus a skirt of one tile all the way
## round, and a wall wherever a neighbour is lower.  Normals and colours are
## generated here so the shared material stays the only material in the scene.
func _build_surface(origin: Vector2i) -> Array:
	var size := WorldConstants.CHUNK_SIZE
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	var step := WorldConstants.HEIGHT_STEP
	for local_y in range(-SKIRT, size + SKIRT):
		for local_x in range(-SKIRT, size + SKIRT):
			var tile := origin + Vector2i(local_x, local_y)
			if not world.in_bounds(tile):
				continue
			var terrain := world.terrain_at(tile)
			var height := world.height_at(tile) * step
			var base: Color = PALETTE.get(terrain, Color.MAGENTA)
			var shade := _noise(tile) * NOISE_AMOUNT
			var colour := Color(
				clampf(base.r + shade, 0.0, 1.0),
				clampf(base.g + shade * 0.7, 0.0, 1.0),
				clampf(base.b + shade * 0.5, 0.0, 1.0))
			var x := float(tile.x)
			var y := float(tile.y)
			var start := vertices.size()
			vertices.append(Vector3(x, height, y))
			vertices.append(Vector3(x + 1.0, height, y))
			vertices.append(Vector3(x + 1.0, height, y + 1.0))
			vertices.append(Vector3(x, height, y + 1.0))
			var top_normal := _top_normal(world, tile)
			for _corner in 4:
				normals.append(top_normal)
			colours.append(colour)
			colours.append(colour)
			colours.append(colour)
			colours.append(colour)
			indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))
			var left := world.height_at(tile + Vector2i(-1, 0)) * step
			var right := world.height_at(tile + Vector2i(1, 0)) * step
			var up := world.height_at(tile + Vector2i(0, -1)) * step
			var down := world.height_at(tile + Vector2i(0, 1)) * step
			if left < height - 0.001:
				_append_wall(vertices, normals, colours, indices, colour, tile, Vector3(0, 0, 0), Vector3(0, 0, 1), height, left, Vector3(-1, 0, 0))
			if right > height + 0.001:
				_append_wall(vertices, normals, colours, indices, colour, tile, Vector3(1, 0, 0), Vector3(1, 0, 1), height, right, Vector3(1, 0, 0))
			if up < height - 0.001:
				_append_wall(vertices, normals, colours, indices, colour, tile, Vector3(0, 0, 0), Vector3(1, 0, 0), height, up, Vector3(0, 0, -1))
			if down > height + 0.001:
				_append_wall(vertices, normals, colours, indices, colour, tile, Vector3(0, 0, 1), Vector3(1, 0, 1), height, down, Vector3(0, 0, 1))
	if vertices.is_empty():
		return []
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


func _append_wall(vertices: PackedVector3Array, normals: PackedVector3Array,
		colours: PackedColorArray, indices: PackedInt32Array, colour: Color,
		tile: Vector2i, from: Vector3, to: Vector3, top: float, bottom: float, normal: Vector3) -> void:
	var start := vertices.size()
	var dark := colour.darkened(0.28)
	vertices.append(Vector3(float(tile.x) + from.x, top, float(tile.y) + from.z))
	vertices.append(Vector3(float(tile.x) + to.x, top, float(tile.y) + to.z))
	vertices.append(Vector3(float(tile.x) + to.x, bottom, float(tile.y) + to.z))
	vertices.append(Vector3(float(tile.x) + from.x, bottom, float(tile.y) + from.z))
	for _corner in 4:
		normals.append(normal)
	for _corner in 4:
		colours.append(dark)
	indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))


func _top_normal(grid: WorldGrid, tile: Vector2i) -> Vector3:
	var step := WorldConstants.HEIGHT_STEP
	var dx := (grid.height_at(tile + Vector2i(1, 0)) - grid.height_at(tile + Vector2i(-1, 0))) * step
	var dz := (grid.height_at(tile + Vector2i(0, 1)) - grid.height_at(tile + Vector2i(0, -1))) * step
	var normal := Vector3(-dx, 2.0, -dz)
	return normal.normalized() if normal.length_squared() > 0.0 else Vector3.UP


## Deterministic per-tile value noise: the same map always looks the same, and
## two neighbouring tiles never share a shade, which is what keeps a
## texture-less landscape from reading as flat.
func _noise(tile: Vector2i) -> float:
	var mixed := (tile.x * 73856093) ^ (tile.y * 19349663)
	mixed = mixed ^ (mixed >> 13)
	return float(mixed & 1023) / 1023.0 * 2.0 - 1.0


func _chunk_key(chunk: Vector2i) -> int:
	return chunk.y * 1024 + chunk.x


func _rebuild_all() -> void:
	_triangle_total = 0
	for key in _chunks.keys():
		var node: MeshInstance3D = _chunks[key]
		node.mesh = null
		node.set_meta("triangles", 0)
	var grid := world.chunk_count()
	for y in grid.y:
		for x in grid.x:
			_rebuild_chunk(Vector2i(x, y))
	_rebuild_water()
