class_name TestViewTerrain
extends TestBase

## Tasks 3.1 – 3.6: chunked terrain rendering.
##
## These cases measure the scene graph — node counts, material identity, AABBs,
## rebuild counters — because that is what the performance rules are written in.
## A screenshot cannot tell a shared material from a per-tile one; a node count
## can, and it costs milliseconds.

var _view: TestView


func teardown() -> void:
	if _view != null:
		_view.dispose()
		_view = null


# --- 3.1 chunked geometry ---------------------------------------------------

func test_map_becomes_chunk_nodes_not_nodes_per_tile() -> void:
	_view = TestView.stage()
	var grid := _view.grid()
	var chunks := grid.chunk_count()
	check_eq(chunks.x * chunks.y, 64, "256 tiles at 32 a chunk is eight by eight chunks")
	check_eq(_view.renderer.live_chunk_nodes(), chunks.x * chunks.y,
		"the renderer holds exactly one node per chunk")
	check_eq(grid.total_tiles(), 65536, "the map it renders is 65,536 tiles")
	# The renderer's own subtree: 64 chunks, its water surface and one node for
	# itself.  If a node per tile ever came back this number becomes six figures.
	var terrain_nodes := float(TestView.count_nodes(_view.renderer))
	check_le(terrain_nodes, 200.0, "65,536 tiles are drawn by a couple of hundred nodes at most")
	check_lt(terrain_nodes, grid.total_tiles() / 100.0,
		"two orders of magnitude under one node per tile")
	check_ge(_view.renderer.triangle_total(), 100000.0, "and the ground is actually in there")


func test_terrain_draws_with_one_shared_vertex_colour_material() -> void:
	_view = TestView.stage()
	var renderer := _view.renderer
	var mismatches := 0
	for chunk in _chunk_positions(renderer):
		var node := renderer.chunk_node(chunk)
		if node == null or node.material_override != renderer.material:
			mismatches += 1
	check_eq(mismatches, 0, "every chunk mesh draws with the renderer's one material")
	check_true(renderer.material.vertex_color_use_as_albedo,
		"that material reads colour from vertices rather than from a texture")
	var materials := TestView.materials_in_use(_view.renderer, {})
	check_le(materials.size(), 3.0,
		"the whole landscape — terrain, water, scenery — draws with at most three materials")
	check_true(materials.has(renderer.material.get_instance_id()),
		"and the terrain material in use is the one the renderer owns")


# --- 3.2 one-tile skirt -----------------------------------------------------

func test_chunk_geometry_reaches_one_tile_past_its_own_tiles() -> void:
	_view = TestView.stage_grid(TestWorldFactory.blank(128, 128))
	var renderer := _view.renderer
	check_eq(renderer.skirt_tiles(), 132, "a 32 tile chunk carries 34 by 34 tiles of ground")
	var middle: AABB = renderer.chunk_aabb(Vector2i(1, 1))
	check_near(middle.position.x, 31.0, "an interior chunk starts a tile before its own tiles", 0.001)
	check_near(middle.end.x, 65.0, "and finishes a tile past its last one", 0.001)
	check_near(middle.position.z, 31.0, "the skirt runs on both ends of the first axis", 0.001)
	check_near(middle.end.z, 65.0, "and both ends of the second", 0.001)
	var east: AABB = renderer.chunk_aabb(Vector2i(2, 1))
	check_near(east.position.x, 63.0, "the neighbour reaches back into the same overlap", 0.001)
	check_ge(middle.end.x - east.position.x, 1.0,
		"so the seam is drawn twice, once by each chunk: a changed tile cannot leave a gap")
	var edge: AABB = renderer.chunk_aabb(Vector2i(0, 0))
	check_near(edge.position.x, 0.0, "the skirt stops at the map edge — nothing outside is built", 0.001)
	check_near(edge.end.x, 33.0, "but it still runs one tile past this chunk's own tiles", 0.001)
	var corner: AABB = renderer.chunk_aabb(Vector2i(3, 3))
	check_near(corner.position.x, 95.0, "the last chunk starts one tile early", 0.001)
	check_near(corner.end.x, 128.0, "and ends at the map edge, not past it", 0.001)


# --- 3.3 local edits rebuild a bounded set ---------------------------------

func test_a_local_edit_rebuilds_only_the_chunks_that_contain_it() -> void:
	_view = TestView.stage_grid(TestWorldFactory.blank(64, 64))
	var renderer := _view.renderer
	var grid := _view.grid()
	check_eq(renderer.rebuild_count(), 4, "attaching built the four chunks once")
	var nodes_before := TestView.count_nodes(renderer)
	var before_triangles := float(renderer.chunk_node(Vector2i(0, 0)).get_meta("triangles"))

	var before := renderer.rebuild_count()
	grid.set_height(Vector2i(10, 10), 7)
	_view.drain_rebuilds()
	check_eq(renderer.rebuild_count() - before, 1, "a tile mid-chunk rebuilds one chunk")
	check_gt(float(renderer.chunk_node(Vector2i(0, 0)).get_meta("triangles")), before_triangles,
		"the new height is in the mesh, not just in the queue")

	before = renderer.rebuild_count()
	grid.set_height(Vector2i(32, 32), 9)
	_view.drain_rebuilds()
	var rebuilt := renderer.rebuild_count() - before
	check_le(rebuilt, 4, "the tile where four chunks meet touches at most four")
	check_eq(rebuilt, 4, "and it does reach the diagonal neighbour, whose skirt holds it too")
	check_eq(TestView.count_nodes(renderer), nodes_before, "no node is created or lost by an edit")
	check_eq(renderer.live_chunk_nodes(), 4, "still four chunk nodes")


# --- 3.4 water -------------------------------------------------------------

func test_water_is_one_surface_holding_no_physics() -> void:
	_view = TestView.stage()
	var grid := _view.grid()
	var water_tiles := 0
	for y in grid.height:
		for x in grid.width:
			if grid.is_water(Vector2i(x, y)):
				water_tiles += 1
	check_gt(float(water_tiles), 100.0, "the shipped map has a river and lakes to draw")
	check_eq(_view.renderer.water_quads(), water_tiles,
		"the water surface is one quad per water cell")
	var bodies := _nodes_named(_view.host, "WaterBody_0")
	check_eq(bodies.size(), 1, "every surface under one root, named by its body")
	for node in _view.renderer.water_body_nodes():
		check_eq(node.mesh.get_surface_count(), 1, "%s draws one surface" % node.name)
	check_eq(TestView.count_physics_objects(_view.host), 0,
		"nothing in the world layer registers with physics: selection is a ray march")


func test_the_river_and_the_lake_are_separate_surfaces() -> void:
	_view = TestView.stage()
	var renderer := _view.renderer
	var tiles := renderer.water_quads()
	check_gt(float(renderer.water_body_count()), 1.0,
		"the valley's water is not one sheet: the flood fill found %d bodies" % renderer.water_body_count())
	check_lt(float(renderer.water_body_count()), float(tiles) / 50.0,
		"a body per run of water, not a node per tile (%d nodes, %d cells)" % [
				renderer.water_body_count(), tiles])
	var total := 0
	for node in renderer.water_body_nodes():
		check_true(node.mesh != null, "every body carries a mesh")
		total += int(node.get_meta("quads", 0))
	check_eq(total, tiles, "and between them they hold every water cell once")


## A body is whatever the water says it is, not whatever a test guessed.  Two
## ponds are two surfaces; fill the channel and they are one.
func test_a_surface_is_a_body_of_water_not_a_fixed_grid_of_cells() -> void:
	var grid := TestWorldFactory.blank(48, 48)
	for y in range(8, 14):
		for x in range(6, 12):
			grid.set_terrain(Vector2i(x, y), WorldGrid.Terrain.WATER)
	for y in range(8, 14):
		for x in range(24, 30):
			grid.set_terrain(Vector2i(x, y), WorldGrid.Terrain.WATER)
	_view = TestView.stage_grid(grid)
	var renderer := _view.renderer
	check_eq(renderer.water_body_count(), 2, "two ponds, two surfaces")
	var west := renderer.water_body_at(Vector2i(8, 10))
	var east := renderer.water_body_at(Vector2i(26, 10))
	check_true(west != null and east != null, "each pond can be pointed at")
	check_neq(west, east, "and they are different surfaces")
	check_eq(renderer.water_body_at(Vector2i(40, 40)), null, "dry ground belongs to neither")

	for x in range(12, 24):
		grid.set_terrain(Vector2i(x, 10), WorldGrid.Terrain.WATER)
	renderer.force_full_rebuild()
	check_eq(renderer.water_body_count(), 1, "fill the channel and it is one lake")
	check_eq(renderer.water_body_at(Vector2i(8, 10)), renderer.water_body_at(Vector2i(26, 10)),
		"and both ends now name the same surface")


func test_the_water_moves_and_the_movement_stays_small() -> void:
	_view = TestView.stage()
	var renderer := _view.renderer
	var bodies := renderer.water_body_nodes()
	check_gt(bodies.size(), 0, "there is water to watch")
	renderer.view_source = func() -> Vector3: return bodies[0].position
	var heights: Array[float] = []
	for step in 40:
		renderer.tick(0.05)
		heights.append(bodies[0].position.y)
	check_eq(renderer.water_animated_last_tick(), bodies.size(),
			"with the view on it, every body was moved")
	var spread := 0.0
	for first in heights.size():
		for second in range(first + 1, heights.size()):
			spread = maxf(spread, absf(heights[first] - heights[second]))
	check_gt(spread, renderer.WATER_BOB_AMPLITUDE * 0.8,
			"the surface visibly moves: %.3f of travel" % spread)
	check_le(spread, renderer.WATER_BOB_AMPLITUDE * 2.0 + 0.001,
			"and it stays where it was built: %.3f at most" % spread)


func test_water_the_player_cannot_see_is_left_completely_alone() -> void:
	_view = TestView.stage()
	var renderer := _view.renderer
	var bodies := renderer.water_body_nodes()
	var still: Array[float] = []
	for node in bodies:
		still.append(node.position.y)
	renderer.view_source = func() -> Vector3: return Vector3(9000.0, 0.0, 9000.0)
	for step in 30:
		renderer.tick(0.05)
	check_eq(renderer.water_animated_last_tick(), 0,
			"nothing was written for water that is 9000 tiles away")
	for index in bodies.size():
		check_near(bodies[index].position.y, still[index],
				"surface %d never moved" % index, 0.000001)
	check_eq(renderer.water_body_count(), bodies.size(), "the water is still there, just idle")


func test_animating_the_water_simulates_nothing() -> void:
	_view = TestView.stage()
	var renderer := _view.renderer
	var before_terrain := _view.grid().terrain.duplicate()
	var before_ticks := _view.session.clock.tick_count
	var before_rebuilds := renderer.rebuild_count()
	renderer.view_source = func() -> Vector3: return Vector3(128.0, 0.0, 128.0)
	for step in 120:
		renderer.tick(0.016)
	check_eq(_view.session.clock.tick_count, before_ticks,
			"three seconds of frames advanced no simulation time at all")
	check_true(_view.grid().terrain == before_terrain,
			"and the water never wrote back to the world it draws")
	check_eq(renderer.rebuild_count(), before_rebuilds,
			"moving a surface is a transform, not a geometry rebuild")


func test_hiding_the_water_surface_changes_nothing_the_simulation_does() -> void:
	var shown := TestView.stage()
	var hidden := TestView.stage()
	hidden.renderer.water_bodies_root.visible = false
	check_false(hidden.renderer.water_bodies_root.visible, "the water is hidden")
	check_true(shown.renderer.water_bodies_root.visible, "the other run shows it")
	var left_line := TestSession.coal_line(shown.session)
	var right_line := TestSession.coal_line(hidden.session)
	check_true(bool(left_line["ok"]), "the left run has a working coal line to simulate")
	check_true(bool(right_line["ok"]), "and so has the right run")
	shown.session.advance_ticks(240)
	hidden.session.advance_ticks(240)

	var left := shown.session
	var right := hidden.session
	check_eq(right.clock.tick_count, left.clock.tick_count, "both ran the same number of ticks")
	check_true(right.world.terrain == left.world.terrain,
		"terrain state is identical with the water surface hidden")
	check_true(right.world.height_steps == left.world.height_steps, "heights are identical")
	check_true(right.world.rail_present == left.world.rail_present, "the rail network is identical")
	check_true(right.world.occupancy_id == left.world.occupancy_id, "and so is who occupies what")
	check_near(right.economy.cash, left.economy.cash,
		"the books balance the same way: presentation cannot reach into simulation", 0.0001)
	shown.dispose()
	hidden.dispose()


# --- 3.5 scenery instancing ------------------------------------------------

func test_scenery_is_one_multimesh_per_chunk_whatever_the_forest_size() -> void:
	_view = TestView.stage_grid(TestWorldFactory.blank(128, 128))
	var grid := _view.grid()
	var renderer := _view.renderer
	# One tree in each of the sixteen chunks, so every chunk owns its node before
	# the big fill starts.  That is the claim being tested: nodes follow chunks.
	for chunk_y in 4:
		for chunk_x in 4:
			var tile := Vector2i(chunk_x * 32 + 5, chunk_y * 32 + 5)
			grid.set_occupancy(tile, WorldGrid.Occupancy.SCENERY, 1)
	_view.drain_rebuilds()
	check_eq(TestView.count_multimeshes(_view.host), 16, "one instanced node per chunk")
	check_eq(renderer.scenery_instance_total(), 16, "one tree each")

	for row in 78:
		for column in 128:
			grid.set_occupancy(Vector2i(column, row), WorldGrid.Occupancy.SCENERY, 1)
	for column in 16:
		grid.set_occupancy(Vector2i(column, 78), WorldGrid.Occupancy.SCENERY, 1)
	_view.drain_rebuilds(80)
	check_eq(TestView.count_multimeshes(_view.host), 16,
		"a thousand times more trees, the same number of nodes")
	check_eq(renderer.scenery_instance_total(), 10004,
		"ten thousand instances: the fill, plus the four trees it does not cover")
	check_eq(TestView.count_nodes(_view.host), 37,
		"host, rig, camera, renderer, water, sixteen chunks and sixteen scenery nodes")


func test_scenery_shares_the_one_material_and_draws_a_real_model() -> void:
	_view = TestView.stage_grid(TestWorldFactory.blank(64, 64))
	var grid := _view.grid()
	var renderer := _view.renderer
	for index in 6:
		grid.set_occupancy(Vector2i(index, 4), WorldGrid.Occupancy.SCENERY, index % 3 + 1)
	_view.drain_rebuilds()
	var shared := renderer.catalog.shared_material()
	var mismatches := 0
	var empty_meshes := 0
	for node in _multimeshes(_view.host):
		var multi: MultiMeshInstance3D = node
		if multi.material_override != shared:
			mismatches += 1
		if multi.multimesh == null or multi.multimesh.mesh == null:
			empty_meshes += 1
	check_eq(mismatches, 0, "instanced scenery draws with the one shared material")
	check_eq(empty_meshes, 0, "every scenery type resolves to a drawable mesh")
	check_neq(_view.renderer.scenery_asset_id(1), _view.renderer.scenery_asset_id(2),
		"scenery ids name different models")
	check_true(renderer.catalog.has_asset("tree"), "the tree model is a built asset")
	var tree_mesh := renderer.catalog.mesh_for("tree")
	check_true(tree_mesh.get_surface_count() > 0, "and it brings real geometry to instance")


# --- 3.6 elevation sampling ------------------------------------------------

func test_elevation_sampling_tracks_the_authored_heights() -> void:
	_view = TestView.stage_grid(TestWorldFactory.with_slope(64, 64, 16))
	var grid := _view.grid()
	var mismatches := 0
	var lowest := 1000.0
	var highest := -1000.0
	for y in range(0, 64, 5):
		for x in range(0, 64, 3):
			var tile := Vector2i(x, y)
			var authored := grid.elevation_at(tile)
			lowest = minf(lowest, authored)
			highest = maxf(highest, authored)
			# Sampled from high above, the way a pointer ray arrives.
			var sampled := _view.renderer.sample_height(Vector3(float(x) + 0.5, 90.0, float(y) + 0.5))
			if absf(sampled - authored) > 0.0001:
				mismatches += 1
	check_gt(highest - lowest, 0.1, "the fixture has real relief, so a constant could not pass")
	check_eq(mismatches, 0, "every sample returns its tile's authored height")
	check_near(_view.renderer.sample_height(Vector3(-4.0, 0.0, -4.0)), 0.0,
		"outside the map it answers the grid's own off-map value instead of crashing", 0.0001)

	# A renderer re-attached to another grid samples the new heights at once.
	_view.dispose()
	_view = TestView.stage_grid(TestWorldFactory.with_cliff(64, 64, 20))
	var cliff := _view.grid()
	check_near(_view.renderer.sample_height(Vector3(30.5, 0.0, 30.5)),
		cliff.elevation_at(Vector2i(30, 30)), "it follows the grid it is attached to", 0.0001)
	check_near(_view.renderer.sample_height(Vector3(10.5, 0.0, 30.5)),
		cliff.elevation_at(Vector2i(10, 30)), "on either side of the cliff edge", 0.0001)
	check_gt(cliff.elevation_at(Vector2i(30, 30)) - cliff.elevation_at(Vector2i(10, 30)), 0.5,
		"and the two sides really are a metre apart")


# --- helpers ---------------------------------------------------------------

func _chunk_positions(renderer: TerrainRenderer) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var count := renderer.world.chunk_count()
	for y in count.y:
		for x in count.x:
			found.append(Vector2i(x, y))
	return found


func _nodes_named(root: Node, node_name: String) -> Array[Node]:
	var found: Array[Node] = []
	if root.name == node_name:
		found.append(root)
	for child in root.get_children():
		found.append_array(_nodes_named(child, node_name))
	return found


func _multimeshes(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	if root is MultiMeshInstance3D:
		found.append(root)
	for child in root.get_children():
		found.append_array(_multimeshes(child))
	return found
