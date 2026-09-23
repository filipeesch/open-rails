class_name RailRenderer
extends Node3D

## Merges track geometry into per-chunk meshes straight from the rail bitmask.
##
## Half of each connection is emitted once per cell, so a line shared by two
## tiles is drawn once.  No node per rail tile, no physics body, no material of
## its own — the whole network is 64 meshes at most.

const MAX_CHUNKS_PER_FRAME := 4
const GAUGE := 0.30
const RAIL_WIDTH := 0.055
const BALLAST_WIDTH := 0.72
## Every height a piece is drawn at comes from `TrackPieces`, the one place the
## running surface is decided: a locomotive is placed from the same figures, and a
## consist drawn to a different rail head than the one drawn is a consist floating
## in the air or buried in the ballast.
const TIES_PER_HALF := 2

const COLOUR_BALLAST := Color(0.55, 0.53, 0.49)
const COLOUR_RAIL := Color(0.36, 0.37, 0.40)
const COLOUR_TIE := Color(0.40, 0.30, 0.21)
const COLOUR_GHOST_OK := Color(0.35, 0.85, 0.40, 0.55)
const COLOUR_GHOST_WARN := Color(0.95, 0.80, 0.25, 0.55)
const COLOUR_GHOST_BAD := Color(0.90, 0.25, 0.22, 0.55)

var world: WorldGrid
var rail: RailService
var material: StandardMaterial3D
var ghost_material: StandardMaterial3D

var _chunks := {}
var _piece_census := {}
var _pending: Array[Vector2i] = []
var _rebuilt_total := 0
var _triangle_total := 0
var _ghost: MeshInstance3D
var _ghost_tiles: Array[Vector2i] = []


func _init() -> void:
	material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.8
	# A preview has to be seen through.  Its green/yellow/red is baked into the
	# vertices like everything else here, so without a vertex-colour material of its
	# own the ghost would be laid down in the engine's default grey — a preview that
	# shows where a line would go but not whether it may.
	ghost_material = StandardMaterial3D.new()
	ghost_material.resource_name = "construction_ghost"
	ghost_material.vertex_color_use_as_albedo = true
	ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED


func attach(grid: WorldGrid, rail_service: RailService) -> void:
	world = grid
	rail = rail_service
	_ghost = MeshInstance3D.new()
	_ghost.name = "ConstructionGhost"
	_ghost.material_override = ghost_material
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)
	rail.track_changed.connect(_on_track_changed)
	rail.track_removed.connect(_on_track_changed)
	_rebuild_all()


func tick() -> void:
	if world == null:
		return
	var budget := MAX_CHUNKS_PER_FRAME
	while not _pending.is_empty() and budget > 0:
		_rebuild_chunk(_pending.pop_front())
		budget -= 1


func triangle_total() -> int:
	return _triangle_total


func rebuild_count() -> int:
	return _rebuilt_total


func live_chunk_nodes() -> int:
	return _chunks.size()


## The construction preview.  One colour for legal, one for "legal but
## expensive", one for blocked — the player never has to read text to know
## whether a line will commit.
func show_ghost(tiles: Array[Vector2i], state: String) -> void:
	_ghost_tiles = tiles
	var colour := COLOUR_GHOST_OK
	match state:
		"expensive":
			colour = COLOUR_GHOST_WARN
		"invalid":
			colour = COLOUR_GHOST_BAD
	_ghost.mesh = _build_mesh(tiles, colour, true)


func hide_ghost() -> void:
	_ghost_tiles = []
	if _ghost != null:
		_ghost.mesh = null


func ghost_tiles() -> Array[Vector2i]:
	return _ghost_tiles


## The preview's geometry, or null when nothing is being previewed here.
func ghost_geometry() -> Mesh:
	return null if _ghost == null else _ghost.mesh


## Draw the build tool's preview.  The controller owns the intent — which tool is
## in hand and what the next click would do — and this renderer only says what
## that would look like laid down.  A station is the exception: its ghost is a yard
## and a reach, not a run of sleepers, so the rail layer yields the ground to
## `StationGhost` rather than drawing the same cells twice.
func attach_build_controller(controller: InputController) -> void:
	build_controller = controller
	controller.ghost_changed.connect(_on_ghost_changed)
	controller.tool_changed.connect(_on_tool_changed)


var build_controller: InputController = null


func _on_ghost_changed(tiles: Array[Vector2i], state: String, _reason: String,
		_cost: float) -> void:
	if state == "none" or _station_holds_the_ghost():
		hide_ghost()
		return
	show_ghost(tiles, state)


func _on_tool_changed(tool: String) -> void:
	if tool == InputController.TOOL_STATION:
		hide_ghost()


func _station_holds_the_ghost() -> bool:
	return build_controller != null and build_controller.tool == InputController.TOOL_STATION


# --- meshes ---------------------------------------------------------------

func _on_track_changed(tiles: Array[Vector2i]) -> void:
	for tile in tiles:
		var chunk := world.chunk_of(tile)
		if not _pending.has(chunk):
			_pending.append(chunk)


func _rebuild_all() -> void:
	_triangle_total = 0
	var grid := world.chunk_count()
	for y in grid.y:
		for x in grid.x:
			_rebuild_chunk(Vector2i(x, y))


func _rebuild_chunk(chunk: Vector2i) -> void:
	var key := chunk.y * 1024 + chunk.x
	var tiles := _rail_tiles_in(chunk)
	var mesh := _build_mesh(tiles, Color.WHITE, false)
	var node: MeshInstance3D = _chunks.get(key)
	if node == null:
		if mesh == null:
			# A chunk with no rail keeps no node: the network's node count
			# scales with the chunks that carry rail, not with the map.
			return
		node = MeshInstance3D.new()
		node.name = "Rail_%d_%d" % [chunk.x, chunk.y]
		node.material_override = material
		add_child(node)
		_chunks[key] = node
	_census_chunk(key, tiles)
	var previous := int(node.get_meta("triangles", 0)) if node.has_meta("triangles") else 0
	node.mesh = mesh
	var triangles := 0
	if mesh != null:
		triangles = int(mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3)
	node.set_meta("triangles", triangles)
	_triangle_total += triangles - previous
	_rebuilt_total += 1


## Name every piece in the chunk.  The census is what makes the piece vocabulary
## more than a caption: the renderer reports the railway in the same words the
## table uses, and a piece that was never selected shows up as an absent name
## rather than as a guess.
func _census_chunk(key: int, tiles: Array[Vector2i]) -> void:
	var counts := {}
	for tile in tiles:
		var piece := TrackPieces.piece_at(world, tile)
		counts[piece] = int(counts.get(piece, 0)) + 1
	if counts.is_empty():
		_piece_census.erase(key)
		return
	_piece_census[key] = counts


## How much railway of each shape is drawn, across every chunk built so far.
func piece_counts() -> Dictionary:
	var total := {}
	for key in _piece_census.keys():
		for piece in _piece_census[key].keys():
			total[piece] = int(total.get(piece, 0)) + int(_piece_census[key][piece])
	return total


func piece_total() -> int:
	var total := 0
	for count in piece_counts().values():
		total += int(count)
	return total


## The piece a single cell is drawn as, or "" when it carries no rail.
func piece_of(tile: Vector2i) -> String:
	if world == null or not world.in_bounds(tile) or not world.has_rail_cell(tile):
		return ""
	return TrackPieces.piece_at(world, tile)


func _rail_tiles_in(chunk: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var origin := chunk * WorldConstants.CHUNK_SIZE
	for offset_y in WorldConstants.CHUNK_SIZE:
		for offset_x in WorldConstants.CHUNK_SIZE:
			var tile := origin + Vector2i(offset_x, offset_y)
			if not world.in_bounds(tile):
				continue
			if world.rail_mask_at(tile) != 0:
				out.append(tile)
	return out


func _build_mesh(tiles: Array[Vector2i], tint: Color, is_ghost: bool) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	for tile in tiles:
		var mask := world.rail_mask_at(tile)
		if is_ghost and mask == 0:
			# A preview cell with no track yet still needs a footprint marker.
			_append_pad(vertices, normals, colours, indices, tile, tint)
		# The piece table decides what a mask is made of.  Enumerating the bits by
		# hand here would be a second, quieter definition of every piece.
		for direction in TrackPieces.halves_for(mask):
			# A connection is drawn as the pair of halves that meet at the
			# shared edge — each endpoint cell emits *its* half.  Skipping the
			# higher-indexed end left every line dashed at the tile edges.
			_append_half_track(vertices, normals, colours, indices, tile, direction, tint, is_ghost)
	if vertices.is_empty():
		return null
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## One half of a connection: ballast, two sleepers and two rails running from
## the cell centre to the shared edge.
func _append_half_track(vertices: PackedVector3Array, normals: PackedVector3Array,
		colours: PackedColorArray, indices: PackedInt32Array, tile: Vector2i,
		direction: int, tint: Color, is_ghost: bool) -> void:
	var centre := TrackPieces.lane(tile)
	var offset := Vector2(RailDirections.offset(direction))
	var edge := centre + offset * 0.5
	var perpendicular := Vector2(-offset.y, offset.x).normalized()
	var neighbour := tile + RailDirections.offset(direction)
	# Ballast and rails are read off the shared rule rather than worked out here, so
	# the line the renderer draws and the line a locomotive stands on are the same
	# measurement — and the sleeper sits under the rail head instead of through it.
	var here_ballast := TrackPieces.ballast_top(world, tile, neighbour, 0.0)
	var there_ballast := TrackPieces.ballast_top(world, tile, neighbour, 0.5)
	var here_head := TrackPieces.rail_head(world, tile, neighbour, 0.0)
	var there_head := TrackPieces.rail_head(world, tile, neighbour, 0.5)
	var ballast := _tint(COLOUR_BALLAST, tint, is_ghost)
	var rail_colour_here := _tint(COLOUR_RAIL, tint, is_ghost)
	_append_strip(vertices, normals, colours, indices, centre, here_ballast, edge, there_ballast,
		BALLAST_WIDTH, ballast)
	if is_ghost:
		return
	var tie_colour := _tint(COLOUR_TIE, tint, is_ghost)
	var tie_lift := TrackPieces.LIFT_TIE - TrackPieces.LIFT_BALLAST
	for tie in TIES_PER_HALF:
		var t := (float(tie) + 0.5) / float(TIES_PER_HALF)
		var along := centre.lerp(edge, t)
		var height := lerpf(here_ballast, there_ballast, t) + tie_lift
		_append_strip(vertices, normals, colours, indices,
			along - perpendicular * 0.17, height,
			along + perpendicular * 0.17, height, 0.10, tie_colour)
	for side: float in [-1.0, 1.0]:
		var offset_vector := perpendicular * (GAUGE * 0.5 * side)
		_append_strip(vertices, normals, colours, indices,
			centre + offset_vector, here_head,
			edge + offset_vector, there_head, RAIL_WIDTH, rail_colour_here)


func _append_strip(vertices: PackedVector3Array, normals: PackedVector3Array,
		colours: PackedColorArray, indices: PackedInt32Array,
		from: Vector2, from_height: float, to: Vector2, to_height: float,
		width: float, colour: Color) -> void:
	var direction := to - from
	if direction.length_squared() < 0.000001:
		return
	var perpendicular := direction.orthogonal().normalized() * (width * 0.5)
	var start := vertices.size()
	vertices.append(Vector3(from.x - perpendicular.x, from_height, from.y - perpendicular.y))
	vertices.append(Vector3(from.x + perpendicular.x, from_height, from.y + perpendicular.y))
	vertices.append(Vector3(to.x + perpendicular.x, to_height, to.y + perpendicular.y))
	vertices.append(Vector3(to.x - perpendicular.x, to_height, to.y - perpendicular.y))
	var normal := _strip_normal(from_height, to_height, direction)
	for _corner in 4:
		normals.append(normal)
	for _corner in 4:
		colours.append(colour)
	indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))


func _append_pad(vertices: PackedVector3Array, normals: PackedVector3Array,
		colours: PackedColorArray, indices: PackedInt32Array, tile: Vector2i, colour: Color) -> void:
	var height := world.elevation_at(tile) + 0.05
	var start := vertices.size()
	vertices.append(Vector3(float(tile.x), height, float(tile.y)))
	vertices.append(Vector3(float(tile.x + 1), height, float(tile.y)))
	vertices.append(Vector3(float(tile.x + 1), height, float(tile.y + 1)))
	vertices.append(Vector3(float(tile.x), height, float(tile.y + 1)))
	for _corner in 4:
		normals.append(Vector3.UP)
		colours.append(colour)
	indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))


func _strip_normal(from_height: float, to_height: float, direction: Vector2) -> Vector3:
	var slope := to_height - from_height
	var flat := Vector3(direction.x, 0.0, direction.y).normalized()
	# A flat strip faces the sky; only a sloped strip tilts.  The old flat-case
	# cross product produced a sideways normal, shading level track dark.
	return Vector3.UP if absf(slope) < 0.001 else Vector3(-flat.x * slope, 1.0, -flat.y * slope).normalized()


func _tint(base: Color, tint: Color, is_ghost: bool) -> Color:
	if not is_ghost:
		return base
	return Color(tint.r, tint.g, tint.b, tint.a)
