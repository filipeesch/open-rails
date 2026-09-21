class_name TestSceneryInstances
extends TestBase

## Task 3.5, presentation side of the same data path: the scenery cells the map
## file planted must come out as instances, and the nodes must follow chunks.
##
## `test_view_terrain.gd` proves the instancing rule with a hand-filled grid,
## because that is the cleanest way to state "a thousand times more trees, the
## same number of nodes".  What it cannot prove is that the *shipped map's*
## feature list arrives — that four thousand seven hundred authored cells become
## four thousand seven hundred instances in a hundred and odd nodes rather than
## vanishing on their way to the renderer.  That is the claim here, and it is
## measured on `founders_valley` booted the way the game boots it.

const MAP_ID := "founders_valley"

var _view: TestView


func teardown() -> void:
	if _view != null:
		_view.dispose()
		_view = null


func test_every_authored_scenery_cell_becomes_an_instance_and_nodes_follow_chunks() -> void:
	_view = TestView.stage(MAP_ID)
	var grid := _view.grid()
	var renderer := _view.renderer
	var cells := 0
	var per_chunk := {}
	var pairs := {}
	for index in grid.total_tiles():
		if grid.occupancy_kind[index] != WorldGrid.Occupancy.SCENERY:
			continue
		cells += 1
		var tile := grid.tile_at(index)
		var chunk := grid.chunk_of(tile)
		var key := "%d:%d" % [chunk.x, chunk.y]
		per_chunk[key] = int(per_chunk.get(key, 0)) + 1
		pairs["%s:%s" % [key, renderer.scenery_asset_id(grid.occupancy_id[index])]] = true
	check_gt(float(cells), 1000.0, "the booted map holds thousands of authored scenery cells")
	check_eq(float(renderer.scenery_instance_total()), float(cells),
		"and the renderer instances every one of them — none is lost between data and draw")
	check_eq(renderer.scenery_node_count(), pairs.size(),
		"one instanced node per chunk per scenery kind, no more")
	check_le(float(renderer.scenery_node_count()), float(3 * grid.chunk_count().x * grid.chunk_count().y),
		"so the node count is bounded by chunks times kinds, never by trees")
	check_gt(float(cells) / float(renderer.scenery_node_count()), 20.0,
		"each instanced node carries scores of scenery, which is the point of instancing")
	# The existing budget in `test_view_terrain.gd`: 65,536 tiles drawn by "a
	# couple of hundred nodes at most".  Real scenery spends part of that budget,
	# and a density retune that pushes past it must be a decision, not a surprise.
	var terrain_nodes := float(TestView.count_nodes(renderer))
	check_le(terrain_nodes, 200.0,
			"the shipped valley — 64 chunks, water, and %d instanced scenery nodes — " \
			% renderer.scenery_node_count() + "still fits the renderer's 200 node budget")
	check_eq(TestView.count_multimeshes(renderer), renderer.scenery_node_count(),
		"and every one of those nodes is an instanced MultiMesh, not a mesh per tree")


func test_the_shipped_frame_loop_finds_nothing_left_to_mesh_after_a_boot() -> void:
	## `game_root._process` feeds the renderer by calling `tick()` once a frame,
	## and `tick()` takes its work from the grid's dirty-chunk queue.  That is the
	## path asserted here — not a test pulling chunks out of the queue by hand.  A
	## booted map that left scenery queued would show up as chunk rebuilds in the
	## first frames, meshing ground the boot had already meshed.
	_view = TestView.stage(MAP_ID)
	var renderer := _view.renderer
	var meshes := renderer.scenery_instance_total()
	check_gt(float(meshes), 1000.0, "attaching built the authored scenery in one pass")
	check_eq(renderer.pending_rebuilds(), 0, "and it queued nothing for later")
	var before := renderer.rebuild_count()
	for frame in 12:
		renderer.tick()
	check_eq(renderer.rebuild_count() - before, 0,
		"twelve frames of the shipped loop mesh nothing again: a boot is not an edit")
	check_eq(renderer.scenery_instance_total(), meshes, "and every instance is still there")


func test_scenery_placed_after_boot_reaches_the_renderer_through_that_same_loop() -> void:
	## The other half: the queue is genuinely live, so the empty one above is a
	## fact about boot and not about a renderer that never reads the grid.  One
	## tile is planted through the ordinary mutation path, and the frame loop alone
	## is allowed to move it.
	_view = TestView.stage(MAP_ID)
	var grid := _view.grid()
	var renderer := _view.renderer
	var tile := Vector2i(-1, -1)
	for index in grid.total_tiles():
		var candidate := grid.tile_at(index)
		if grid.occupancy_at(candidate) == WorldGrid.Occupancy.NONE \
				and not grid.is_water(candidate):
			tile = candidate
			break
	check_neq(tile, Vector2i(-1, -1), "the valley has an empty cell to plant in")
	var started := renderer.scenery_instance_total()
	var chunk := grid.chunk_of(tile)
	var chunk_before := _instances_in_chunk(renderer, chunk)
	var nodes_before := renderer.scenery_node_count()
	# The ordinary edit path, the one a builder would use: it marks the tile and
	# its chunk dirty, and the renderer's own frame tick is what notices.
	grid.set_occupancy(tile, WorldGrid.Occupancy.SCENERY, SceneryKind.BUSH)
	_view.drain_rebuilds()
	check_eq(renderer.scenery_instance_total(), started + 1, "the frame loop instanced the new cell")
	check_eq(_instances_in_chunk(renderer, chunk), chunk_before + 1,
			"in chunk %s, where the cell lives" % chunk)
	check_le(float(renderer.scenery_node_count() - nodes_before), 1.0,
		"and it cost at most one node: a new kind in that chunk, or none")


func test_scenery_is_grouped_by_chunk_in_the_nodes_that_hold_it() -> void:
	## "Grouped spatially by chunk" is checkable exactly: for every chunk, the
	## instances held by the nodes named for that chunk must equal the cells that
	## chunk owns.  One cell counted twice, or one wood split across the wrong
	## nodes, breaks the equality somewhere.
	_view = TestView.stage(MAP_ID)
	var grid := _view.grid()
	var renderer := _view.renderer
	var cells := {}
	for index in grid.total_tiles():
		if grid.occupancy_kind[index] != WorldGrid.Occupancy.SCENERY:
			continue
		var chunk := grid.chunk_of(grid.tile_at(index))
		var key := "%d:%d" % [chunk.x, chunk.y]
		cells[key] = int(cells.get(key, 0)) + 1
	var grid_size := grid.chunk_count()
	var mismatched := 0
	var largest := 0
	var largest_chunk := Vector2i(-1, -1)
	for chunk_y in grid_size.y:
		for chunk_x in grid_size.x:
			var chunk := Vector2i(chunk_x, chunk_y)
			var owned := int(cells.get("%d:%d" % [chunk.x, chunk.y], 0))
			if _instances_in_chunk(renderer, chunk) != owned:
				mismatched += 1
			if owned > largest:
				largest = owned
				largest_chunk = chunk
	check_eq(mismatched, 0, "every chunk holds exactly its own cells, no more and no less")
	check_ge(float(largest), 50.0, "and at least one chunk is a real wood of its own")
	check_eq(_instances_in_chunk(renderer, largest_chunk), largest,
			"the densest of them, chunk %s, is instanced complete" % largest_chunk)
	var oversize := 0
	for child in renderer.get_children():
		var multi := child as MultiMeshInstance3D
		if multi == null or multi.multimesh == null:
			continue
		if multi.multimesh.instance_count > WorldConstants.CHUNK_SIZE * WorldConstants.CHUNK_SIZE:
			oversize += 1
	check_eq(oversize, 0,
		"no node holds more instances than one chunk has tiles, so none spans a chunk")


func test_every_kind_the_map_writes_is_a_model_the_renderer_knows() -> void:
	## The contract between the domain's scenery table and the presentation's.
	## The domain refuses to write a code it does not know; this refuses to let a
	## code exist that the renderer would silently draw as its fallback tree.
	_view = TestView.stage(MAP_ID)
	var grid := _view.grid()
	var seen := {}
	for index in grid.total_tiles():
		if grid.occupancy_kind[index] != WorldGrid.Occupancy.SCENERY:
			continue
		seen[grid.occupancy_id[index]] = int(seen.get(grid.occupancy_id[index], 0)) + 1
	check_ge(float(seen.size()), 3.0, "the shipped map writes at least tree, rock and bush")
	var unmapped := 0
	var codes: Array = []
	for key in seen.keys():
		codes.append(int(key))
	codes.sort()
	for code in codes:
		if not TerrainRenderer.SCENERY_ASSETS.has(code):
			unmapped += 1
	check_eq(unmapped, 0,
			"every scenery code the map writes is a key in the renderer's own asset table (%s)" \
			% str(codes))
	var distinct := {}
	for code in codes:
		distinct[_view.renderer.scenery_asset_id(code)] = true
	check_eq(distinct.size(), codes.size(), "and each code resolves to a different model")


# --- helpers ---------------------------------------------------------------

## Instances the renderer actually holds for one chunk, read off the instanced
## nodes by their names — `Scenery_<chunk_x>_<chunk_y>_<asset>`.
func _instances_in_chunk(renderer: TerrainRenderer, chunk: Vector2i) -> int:
	var prefix := "Scenery_%d_%d_" % [chunk.x, chunk.y]
	var total := 0
	for child in renderer.get_children():
		var multi := child as MultiMeshInstance3D
		if multi == null or not String(multi.name).begins_with(prefix):
			continue
		if multi.multimesh != null:
			total += multi.multimesh.instance_count
	return total
