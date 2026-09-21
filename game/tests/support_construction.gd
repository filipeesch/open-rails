class_name TestConstruction
extends RefCounted

## Shared helpers for the construction-tool and track-rendering suites.
##
## These tests drive the domain through the same plan/preview/commit/undo API
## the tools call, and inspect the geometry the RailRenderer puts on screen —
## but never instantiate UI nodes or take screenshots.  Everything here keeps
## the money invariant true: cash only ever moves through EconomyService.

## One half-track piece (ballast strip, two sleepers, two rail strips) is
## 5 strips × 2 triangles.  The renderer's piece vocabulary is emitted per
## connection endpoint, so piece counts are read back as triangles / 10.
const HALF_TRACK_TRIANGLES := 10

const BALLAST_LIFT := 0.02
const RAIL_LIFT := 0.07
const EPSILON := 0.0001


## A wired session over a hand-authorable blank grid: no map geography can
## move under a test that names the tile it places on.  128×128 gives a 4×4
## chunk grid, enough for the node-scaling claims.
static func blank_session(width: int = 128, height: int = 128) -> GameSession:
	var session := GameSession.new()
	if not session.start_blank(width, height):
		push_error("blank session refused: " + session.last_error)
	return session


static func dispose(session: GameSession) -> void:
	if session != null:
		session.free()


# --- tile shapes -----------------------------------------------------------

static func east_run(origin: Vector2i, count: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for step in count:
		tiles.append(origin + Vector2i(step, 0))
	return tiles


static func scattered_tiles(origin: Vector2i, count: int, stride: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for step in count:
		tiles.append(origin + Vector2i(step * stride, 0))
	return tiles


## Builds each tile as its own one-tile commit; the splice pass in
## commit_segment joins the run, which is a different code path from a single
## multi-tile commit.
static func commit_tile_by_tile(session: GameSession, tiles: Array[Vector2i]) -> void:
	for tile in tiles:
		var single: Array[Vector2i] = [tile]
		var result := session.builder.build_track_run(single)
		if not bool(result.get("ok", false)):
			push_error("tile-by-tile build refused at %s: %s" % [tile, result.get("reason", "")])


# --- session probes ----------------------------------------------------------

static func rail_count(session: GameSession) -> int:
	return session.rail.rail_tiles().size()


static func cash(session: GameSession) -> float:
	return session.economy.cash


static func ledger_size(session: GameSession) -> int:
	return session.economy.ledger().size()


## Live (unreversed) ledger rows in one category.
static func live_transactions_in(session: GameSession, category: String) -> Array[EconomyService.Transaction]:
	var out: Array[EconomyService.Transaction] = []
	for entry: EconomyService.Transaction in session.economy.ledger():
		if entry.category == category and entry.reversed_by == 0:
			out.append(entry)
	return out


static func set_height_column(session: GameSession, x: int, from_y: int, to_y: int, steps: int) -> void:
	for y in range(from_y, to_y + 1):
		session.world.set_height(Vector2i(x, y), steps)


static func paint_water_column(session: GameSession, x: int, from_y: int, to_y: int) -> void:
	for y in range(from_y, to_y + 1):
		session.world.set_terrain(Vector2i(x, y), WorldGrid.Terrain.WATER)


static func touched_chunk_count(session: GameSession) -> int:
	var seen := {}
	for tile in session.rail.rail_tiles():
		seen[session.world.chunk_of(tile)] = true
	return seen.size()


# --- renderer geometry probes ------------------------------------------------

## The chunk's MeshInstance3D, or null.  Reached through the renderer's own
## chunk table so the probe does not depend on child ordering.
static func chunk_node(renderer: RailRenderer, chunk: Vector2i) -> MeshInstance3D:
	var key := chunk.y * 1024 + chunk.x
	var node: MeshInstance3D = renderer._chunks.get(key)
	return node


static func chunk_mesh(renderer: RailRenderer, chunk: Vector2i) -> ArrayMesh:
	var node := chunk_node(renderer, chunk)
	if node == null:
		return null
	var mesh: ArrayMesh = node.mesh
	return mesh


static func chunk_triangles(renderer: RailRenderer, chunk: Vector2i) -> int:
	return mesh_triangles(chunk_mesh(renderer, chunk))


static func mesh_triangles(mesh: ArrayMesh) -> int:
	if mesh == null:
		return 0
	var arrays := mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	return int(indices.size() / 3)


static func mesh_vertices(mesh: ArrayMesh) -> PackedVector3Array:
	if mesh == null:
		return PackedVector3Array()
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return verts


static func mesh_colours(mesh: ArrayMesh) -> PackedColorArray:
	if mesh == null:
		return PackedColorArray()
	var arrays := mesh.surface_get_arrays(0)
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	return colours


static func has_vertex(vertices: PackedVector3Array, x: float, y: float, tolerance: float) -> bool:
	for vertex in vertices:
		if absf(vertex.x - x) <= tolerance and absf(vertex.y - y) <= tolerance:
			return true
	return false


static func lowest_y_near_x(vertices: PackedVector3Array, x: float, tolerance: float) -> float:
	var best := INF
	for vertex in vertices:
		if absf(vertex.x - x) <= tolerance:
			best = minf(best, vertex.y)
	return best


static func highest_y_near_x(vertices: PackedVector3Array, x: float, tolerance: float) -> float:
	var best := -INF
	for vertex in vertices:
		if absf(vertex.x - x) <= tolerance:
			best = maxf(best, vertex.y)
	return best


## Lowest terrain height among a tile and its eight neighbours.  A piece may
## bridge one height step, so this is the floor it must never sink beneath.
static func lowest_elevation_around(world: WorldGrid, tile: Vector2i) -> float:
	var best := INF
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var probe := tile + Vector2i(dx, dy)
			if not world.in_bounds(probe):
				continue
			best = minf(best, world.elevation_at(probe))
	return best


static func ghost_mesh(renderer: RailRenderer) -> ArrayMesh:
	if renderer._ghost == null:
		return null
	var mesh: ArrayMesh = renderer._ghost.mesh
	return mesh


## Vertex colours round-trip through ArrayMesh at 8-bit depth, so colour
## assertions compare with byte tolerance rather than exactly.
static func colours_close(a: Color, b: Color, tolerance: float = 0.005) -> bool:
	return absf(a.r - b.r) <= tolerance and absf(a.g - b.g) <= tolerance \
		and absf(a.b - b.b) <= tolerance and absf(a.a - b.a) <= tolerance


## Count of nodes under the renderer that are physics bodies.
static func physics_body_count(root: Node) -> int:
	var total := 0
	for child in root.get_children():
		if child is RigidBody3D or child is StaticBody3D or child is Area3D or child is CharacterBody3D:
			total += 1
		total += physics_body_count(child)
	return total
