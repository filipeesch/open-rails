class_name TestTrackRendering
extends TestBase

## The track renderer, verified as data-to-geometry, never as pixels.
##
## The renderer's contract: a cell's connection mask fully determines which
## pieces appear, pieces are batched per chunk (never one node per tile), only
## dirty chunks rebuild, pieces ride the terrain instead of sinking into it,
## and the same connection set looks the same however it was built.  Physics
## bodies and per-piece materials are forbidden by the performance rules and
## asserted absent here.

const CHUNK := Vector2i(0, 0)

var session: GameSession
var renderer: RailRenderer


func setup() -> void:
	session = TestConstruction.blank_session(128, 128)
	renderer = RailRenderer.new()
	renderer.attach(session.world, session.rail)


func teardown() -> void:
	if renderer != null:
		renderer.free()
		renderer = null
	TestConstruction.dispose(session)
	session = null


func rebuild_pending() -> void:
	# One tick per expected dirty-chunk wave; the budget is 4 chunks per tick.
	renderer.tick()
	renderer.tick()
	renderer.tick()


# --- 4.1 connection mask selects the pieces ------------------------------------

func test_connection_masks_select_their_pieces() -> void:
	# The renderer has no piece-id table: its piece vocabulary is one half-track
	# per connection endpoint (ballast + sleepers + rails = 10 triangles).  The
	# connection mask is the only selector, so each representative mask below
	# must yield exactly its endpoint count.
	var base_triangles := TestConstruction.chunk_triangles(renderer, CHUNK)
	# Straight: two opposite bits (E|W).
	var straight := TestConstruction.east_run(Vector2i(4, 4), 2)
	session.builder.build_track_run(straight)
	rebuild_pending()
	check_eq(TestConstruction.chunk_triangles(renderer, CHUNK), base_triangles + 20,
		"an E|W straight selects one piece from each end")
	check_true(session.rail.network.mask(Vector2i(4, 4)) \
		== RailDirections.bit(RailDirections.E) | RailDirections.bit(RailDirections.W) \
		or session.rail.network.mask(Vector2i(4, 4)) == RailDirections.bit(RailDirections.E),
		"the west end keeps its east bit")
	base_triangles = TestConstruction.chunk_triangles(renderer, CHUNK)
	# Diagonal: NE|SW.
	session.builder.build_track_run([Vector2i(4, 7), Vector2i(5, 6)])
	rebuild_pending()
	check_eq(TestConstruction.chunk_triangles(renderer, CHUNK), base_triangles + 20,
		"a diagonal hop selects one piece from each end")
	check_eq(session.rail.network.mask(Vector2i(4, 7)), RailDirections.bit(RailDirections.NE),
		"the south end of the diagonal carries only its NE bit")
	base_triangles = TestConstruction.chunk_triangles(renderer, CHUNK)
	# 45-degree curve: E then NE, middle cell holds W|NE.
	session.builder.build_track_run([Vector2i(4, 9), Vector2i(5, 9), Vector2i(6, 8)])
	rebuild_pending()
	check_eq(TestConstruction.chunk_triangles(renderer, CHUNK), base_triangles + 40,
		"a 45-degree curve bends two connections, two pieces each")
	check_true(session.rail.network.is_curve(Vector2i(5, 9)), "the middle cell reads as a curve")
	base_triangles = TestConstruction.chunk_triangles(renderer, CHUNK)
	# 90-degree curve: N then E, corner cell holds S|E.
	session.builder.build_track_run([Vector2i(8, 11), Vector2i(8, 10), Vector2i(9, 10)])
	rebuild_pending()
	check_eq(TestConstruction.chunk_triangles(renderer, CHUNK), base_triangles + 40,
		"a 90-degree corner bends two connections too")
	check_true(session.rail.network.is_curve(Vector2i(8, 10)), "the corner reads as a curve")
	base_triangles = TestConstruction.chunk_triangles(renderer, CHUNK)
	# Junction: a T with three live connections at the hub.
	session.builder.build_track_run(TestConstruction.east_run(Vector2i(9, 4), 3))
	session.builder.build_track_run([Vector2i(10, 4), Vector2i(10, 3)])
	rebuild_pending()
	check_eq(TestConstruction.chunk_triangles(renderer, CHUNK), base_triangles + 60,
		"a three-way junction offers three connections, six endpoint pieces")
	check_true(session.rail.network.is_junction(Vector2i(10, 4)), "the hub reports a junction")
	base_triangles = TestConstruction.chunk_triangles(renderer, CHUNK)
	# Slope piece: a one-step climb.
	session.world.set_height(Vector2i(20, 14), 4)
	session.world.set_height(Vector2i(21, 14), 5)
	session.builder.build_track_run([Vector2i(20, 14), Vector2i(21, 14)])
	rebuild_pending()
	check_eq(TestConstruction.chunk_triangles(renderer, CHUNK), base_triangles + 20,
		"a climbed connection still selects exactly one piece per end")


func test_committed_line_draws_both_halves_of_every_connection() -> void:
	# Three tiles in a line hold two connections; each connection has two
	# endpoint halves — the one from each tile meeting at the shared edge.
	# Losing either half leaves the line visibly dashed between tile centres.
	var run := TestConstruction.east_run(Vector2i(6, 20), 3)
	session.builder.build_track_run(run)
	rebuild_pending()
	var mesh := TestConstruction.chunk_mesh(renderer, CHUNK)
	var triangles := TestConstruction.mesh_triangles(mesh)
	check_eq(triangles, 40, "two connections render four half-track pieces")
	var verts := TestConstruction.mesh_vertices(mesh)
	check_true(TestConstruction.has_vertex(verts, 6.5, 0.02, 0.001) \
		and TestConstruction.has_vertex(verts, 8.5, 0.02, 0.001),
		"both far ends of the line carry their own ballast start, not just one")


# --- 4.2 chunk batching ---------------------------------------------------------

func test_five_hundred_tile_railway_scales_with_chunks_not_tiles() -> void:
	# Four ladder yards of 130 cells each, spread across four chunks.
	var yards: Array[Vector2i] = [Vector2i(2, 2), Vector2i(36, 2), Vector2i(2, 68), Vector2i(36, 68)]
	for yard in yards:
		for row in 5:
			session.builder.build_track_run(TestConstruction.east_run(yard + Vector2i(0, row), 26))
	rebuild_pending()
	var cells := TestConstruction.rail_count(session)
	check_ge(float(cells), 500.0, "the fixture really is a ~500-tile railway")
	var touched := TestConstruction.touched_chunk_count(session)
	check_eq(float(touched), 4.0, "the four yards touch four chunks")
	var nodes := renderer.live_chunk_nodes()
	check_le(float(nodes), float(2 * touched), "nodes stay at or below two per touched chunk")
	check_lt(float(nodes), float(cells) / 10.0, "node count is nowhere near one per tile")
	check_eq(float(nodes), float(touched), "one batched mesh per chunk carrying rail, no empty chunk nodes")
	var batched := 0
	for child in renderer.get_children():
		if child is MeshInstance3D:
			batched += 1
	check_le(float(batched), float(touched + 1), "only chunk meshes plus the construction ghost exist")
	check_eq(TestConstruction.physics_body_count(renderer), 0,
		"no physics body anywhere under the rail renderer")


func test_pieces_share_one_material_not_one_per_piece() -> void:
	session.builder.build_track_run(TestConstruction.east_run(Vector2i(6, 20), 5))
	session.builder.build_track_run(TestConstruction.east_run(Vector2i(6, 24), 5))
	rebuild_pending()
	var seen := 0
	for child in renderer.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			seen += 1
			check_true((child as MeshInstance3D).material_override == renderer.material,
				"chunk mesh %s rides the shared material" % child.name)
	check_gt(float(seen), 0.0, "at least one chunk mesh was inspected")


# --- 4.3 dirty-chunk rebuilds ----------------------------------------------------

func test_interior_edit_rebuilds_exactly_one_chunk() -> void:
	var before := renderer.rebuild_count()
	session.builder.build_track_run(TestConstruction.east_run(Vector2i(10, 10), 3))
	renderer.tick()
	var delta := renderer.rebuild_count() - before
	check_eq(delta, 1, "a chunk-interior edit rebuilds its one chunk and nothing else")
	var total_chunks := session.world.chunk_count()
	check_lt(float(delta), float(total_chunks.x * total_chunks.y), "no full-world rebuild for a local edit")


func test_boundary_edit_rebuilds_only_the_touching_chunks() -> void:
	var before := renderer.rebuild_count()
	# A run that straddles the x = 31/32 chunk line.
	session.builder.build_track_run(TestConstruction.east_run(Vector2i(30, 8), 4))
	renderer.tick()
	var delta := renderer.rebuild_count() - before
	check_ge(float(delta), 2.0, "both touched chunks come back")
	check_le(float(delta), 4.0, "the skirt rule keeps a boundary edit to four chunks")
	var total_chunks := session.world.chunk_count()
	check_lt(float(delta), float(total_chunks.x * total_chunks.y), "still never the whole world")


# --- 4.4 elevation -----------------------------------------------------------------

func test_slope_piece_bridges_both_tile_heights() -> void:
	session.world.set_height(Vector2i(8, 8), 4)
	session.world.set_height(Vector2i(9, 8), 5)
	session.builder.build_track_run([Vector2i(8, 8), Vector2i(9, 8)])
	rebuild_pending()
	var verts := TestConstruction.mesh_vertices(TestConstruction.chunk_mesh(renderer, CHUNK))
	check_false(verts.is_empty(), "the climb produced geometry")
	var low_elev := session.world.elevation_at(Vector2i(8, 8))
	var high_elev := session.world.elevation_at(Vector2i(9, 8))
	# At the low tile's centre the piece starts at the low tile's height.
	check_near(TestConstruction.lowest_y_near_x(verts, 8.5, 0.001), low_elev + TestConstruction.BALLAST_LIFT,
		"the piece starts at the low tile's elevation", 0.0001)
	# At the high tile's centre it has reached the high tile's height.
	check_near(TestConstruction.lowest_y_near_x(verts, 9.5, 0.001), high_elev + TestConstruction.BALLAST_LIFT,
		"the piece ends at the high tile's elevation", 0.0001)
	# The shared edge carries the bridged midpoint of the two heights, reached
	# identically by both halves — one continuous slope, not a V-knot.
	var bridge := (low_elev + high_elev) * 0.5 + TestConstruction.BALLAST_LIFT
	check_near(TestConstruction.lowest_y_near_x(verts, 9.0, 0.001), bridge,
		"both halves meet at the bridged midpoint height on the shared edge", 0.0001)
	check_near(TestConstruction.highest_y_near_x(verts, 9.0, 0.001),
		bridge + TestConstruction.RAIL_LIFT,
		"the rails cross the shared edge at that same bridged height", 0.0001)
	check_gt(TestConstruction.lowest_y_near_x(verts, 9.0, 0.001),
		TestConstruction.lowest_y_near_x(verts, 8.5, 0.001),
		"a slope piece is not flat: it rises across the connection")


func test_no_piece_sinks_into_the_heightfield() -> void:
	# Plain → step → step → plateau: every hop is a legal one height step.
	TestConstruction.set_height_column(session, 10, 0, 20, 1)
	TestConstruction.set_height_column(session, 11, 0, 20, 2)
	TestConstruction.set_height_column(session, 12, 0, 20, 2)
	TestConstruction.set_height_column(session, 13, 0, 20, 2)
	session.builder.build_rail(Vector2i(8, 10), Vector2i(13, 10))
	rebuild_pending()
	var verts := TestConstruction.mesh_vertices(TestConstruction.chunk_mesh(renderer, CHUNK))
	check_gt(float(verts.size()), 0.0, "the climb over two steps rendered geometry")
	# A piece bridging two terraces may sit between their heights, but nothing
	# may sit below the lower terrace plus its ballast lift — that is a piece
	# intersecting the terrain.
	var sinks := 0
	for vertex in verts:
		var tile := Vector2i(int(floorf(vertex.x)), int(floorf(vertex.z)))
		var ground := TestConstruction.lowest_elevation_around(session.world, tile)
		if vertex.y < ground + TestConstruction.BALLAST_LIFT - TestConstruction.EPSILON:
			sinks += 1
	check_eq(sinks, 0, "no vertex intersects the terrain it rides over")


# --- 4.5 same masks, same pieces, whichever path built them ------------------------

func test_identical_connection_sets_select_identical_pieces_by_every_path() -> void:
	# Path 1: one multi-tile segment commit.
	var a_tiles := TestConstruction.east_run(Vector2i(6, 20), 4)
	session.builder.build_track_run(a_tiles)
	# Path 2: the same shape as four single-tile commits that splice together.
	var b_tiles := TestConstruction.east_run(Vector2i(6, 24), 4)
	TestConstruction.commit_tile_by_tile(session, b_tiles)
	rebuild_pending()
	for step in 4:
		var mask_a := session.rail.network.mask(a_tiles[step])
		var mask_b := session.rail.network.mask(b_tiles[step])
		check_eq(mask_b, mask_a, "single-tile commits build the same connection mask at step %d" % step)
	# Path 3: snapshot-and-restore of the first region, transplanted wholesale.
	var state := session.rail.network.snapshot(a_tiles)
	var c_tiles: Array[Vector2i] = []
	for tile in a_tiles:
		c_tiles.append(tile + Vector2i(64, 0))
	var transplanted := {}
	for index in state.keys():
		var source := session.world.tile_at(int(index))
		transplanted[session.world.index_of(source + Vector2i(64, 0))] = state[index]
	session.rail.network.restore(transplanted)
	# Force the receiving chunk to rebuild through the normal dirty path.
	session.builder.build_track_run([Vector2i(70, 24)])
	rebuild_pending()
	for step in 4:
		var source_tile := a_tiles[step]
		var target := c_tiles[step]
		check_eq(session.rail.network.mask(target), session.rail.network.mask(source_tile),
			"restored-from-snapshot tiles carry the same mask at step %d" % step)
		check_true(session.rail.network.has_rail(target), "the restored tile exists at step %d" % step)
	var pieces_a := TestConstruction.chunk_triangles(renderer, session.world.chunk_of(a_tiles[0]))
	# Region B shares a chunk with region A; the stub that forced the rebuild
	# of chunk (2,0) is isolated, so chunk (2,0) shows the transplanted
	# fixture on its own.
	var pieces_c := TestConstruction.chunk_triangles(renderer, session.world.chunk_of(c_tiles[0]))
	check_eq(float(pieces_c), 60.0, "the restored-from-snapshot region selects 6 endpoint pieces")
	check_eq(float(pieces_a), 120.0,
		"segment-commit and tile-by-tile copies select the same 60 pieces each")


# --- 3.3 (renderer side) validity state to colour ------------------------------------

func test_ghost_colour_maps_validity_state_to_green_yellow_red() -> void:
	var tiles: Array[Vector2i] = [Vector2i(40, 40), Vector2i(41, 40)]
	renderer.show_ghost(tiles, "ok")
	var colours := TestConstruction.mesh_colours(TestConstruction.ghost_mesh(renderer))
	check_gt(float(colours.size()), 0.0, "the legal ghost produced coloured geometry")
	for colour in colours:
		check_true(TestConstruction.colours_close(colour, RailRenderer.COLOUR_GHOST_OK),
			"the ok state renders the green ghost, got %s" % str(colour))
		check_gt(colour.g, colour.r, "green really leans green")
	renderer.show_ghost(tiles, "expensive")
	colours = TestConstruction.mesh_colours(TestConstruction.ghost_mesh(renderer))
	for colour in colours:
		check_true(TestConstruction.colours_close(colour, RailRenderer.COLOUR_GHOST_WARN),
			"the expensive state renders the yellow ghost, got %s" % str(colour))
	renderer.show_ghost(tiles, "invalid")
	colours = TestConstruction.mesh_colours(TestConstruction.ghost_mesh(renderer))
	for colour in colours:
		check_true(TestConstruction.colours_close(colour, RailRenderer.COLOUR_GHOST_BAD),
			"the invalid state renders the red ghost, got %s" % str(colour))
		check_gt(colour.r, colour.g, "red really leans red")
	check_eq(renderer.ghost_tiles(), tiles, "the ghost keeps the exact tiles the preview handed it")
	renderer.hide_ghost()
	check_true(TestConstruction.ghost_mesh(renderer) == null, "hiding clears the ghost mesh")
