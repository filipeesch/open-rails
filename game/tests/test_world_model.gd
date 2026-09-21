class_name TestWorldModel
extends TestBase

## The world is compact data, not a node tree, and a local edit must stay local.

func test_grid_is_backed_by_typed_arrays_not_nodes() -> void:
	var world := TestWorldFactory.blank(64, 64)
	check_eq(world.total_tiles(), 64 * 64, "a 64×64 map holds 4096 cells")
	check_eq(typeof(world.terrain), TYPE_PACKED_BYTE_ARRAY, "terrain is a PackedByteArray")
	check_eq(typeof(world.height_steps), TYPE_PACKED_BYTE_ARRAY, "height is a PackedByteArray")
	check_eq(typeof(world.occupancy_id), TYPE_PACKED_INT64_ARRAY, "occupancy ids are int64")
	check_eq(typeof(world.rail), TYPE_PACKED_BYTE_ARRAY, "rail masks are a PackedByteArray")
	check_eq(world.terrain.size(), 4096, "one byte per cell, nothing per cell object")


func test_index_is_row_major_and_reversible() -> void:
	var world := TestWorldFactory.blank(32, 16)
	for probe in [Vector2i.ZERO, Vector2i(31, 15), Vector2i(7, 3), Vector2i(0, 15)]:
		var index := world.index_of(probe)
		check_eq(index, probe.y * 32 + probe.x, "index of %s is row-major" % probe)
		check_eq(world.tile_at(index), probe, "tile_at inverts index_of for %s" % probe)


func test_out_of_bounds_lookups_are_safe() -> void:
	var world := TestWorldFactory.blank(16, 16)
	check_false(world.in_bounds(Vector2i(-1, 4)), "negative x is outside")
	check_false(world.in_bounds(Vector2i(16, 4)), "width is exclusive")
	check_near(world.elevation_at(Vector2i(999, 999)), 0.0, "an off-map elevation reads zero rather than crashing")


func test_height_is_exposed_in_world_units_from_the_shared_step() -> void:
	var world := TestWorldFactory.blank(8, 8, 6)
	check_near(world.elevation_at(Vector2i(3, 3)), 6.0 * WorldConstants.HEIGHT_STEP,
		"elevation is height_steps × HEIGHT_STEP")


func test_a_256_map_divides_into_64_chunks() -> void:
	var world := WorldGrid.new(WorldConstants.MAP_WIDTH, WorldConstants.MAP_HEIGHT)
	var chunks := world.chunk_count()
	check_eq(chunks.x * chunks.y, 64, "256 tiles / 32 gives 8×8 = 64 chunks")
	check_eq(chunks.x, 8, "eight chunks across")


func test_editing_one_tile_dirties_at_most_four_chunks() -> void:
	var world := TestWorldFactory.blank(WorldConstants.MAP_WIDTH, WorldConstants.MAP_HEIGHT)
	world.take_dirty_chunks()
	world.set_height(Vector2i(31, 31), 5)
	var dirty := world.take_dirty_chunks()
	check_le(float(dirty.size()), 4.0, "a corner edit touches the four chunks meeting there")
	check_true(dirty.has(Vector2i(0, 0)), "the edited chunk is dirty")
	check_true(dirty.has(Vector2i(1, 0)), "the neighbour east is dirty because its edge vertices moved")


func test_interior_edit_dirties_only_its_own_chunk() -> void:
	var world := TestWorldFactory.blank(WorldConstants.MAP_WIDTH, WorldConstants.MAP_HEIGHT)
	world.take_dirty_chunks()
	world.set_height(Vector2i(69, 69), 7)
	var dirty := world.take_dirty_chunks()
	check_eq(dirty.size(), 1, "a tile a few cells clear of the seam dirties one chunk")


func test_water_is_the_only_unbuildable_terrain() -> void:
	var world := TestWorldFactory.blank(16, 16)
	world.terrain[world.index_of(Vector2i(4, 4))] = WorldGrid.Terrain.WATER
	world.terrain[world.index_of(Vector2i(6, 4))] = WorldGrid.Terrain.ROCK
	world.terrain[world.index_of(Vector2i(8, 4))] = WorldGrid.Terrain.FOREST
	check_true(not world.build_reason(Vector2i(4, 4)).is_empty(), "water blocks construction")
	check_eq(world.build_reason(Vector2i(6, 4)), "", "rock is buildable by rail")
	check_eq(world.build_reason(Vector2i(8, 4)), "", "forest is buildable")


func test_occupancy_records_which_entity_is_there() -> void:
	var world := TestWorldFactory.blank(16, 16)
	world.set_occupancy(Vector2i(5, 5), WorldGrid.Occupancy.STATION, 1234)
	check_eq(world.occupancy_at(Vector2i(5, 5)), WorldGrid.Occupancy.STATION, "kind is recorded")
	check_eq(world.occupancy_entity(Vector2i(5, 5)), 1234, "the stable id is recorded")
	world.clear_occupancy(Vector2i(5, 5))
	check_eq(world.occupancy_at(Vector2i(5, 5)), WorldGrid.Occupancy.NONE, "clearing empties the cell")
	check_eq(world.occupancy_entity(Vector2i(5, 5)), 0, "and drops the id")


func test_rebuild_counter_only_moves_on_an_explicit_geometry_rebuild() -> void:
	var world := TestWorldFactory.blank(64, 64)
	world.reset_counters()
	world.note_geometry_rebuild()
	check_eq(world.geometry_rebuild_count(), 1, "the counter is exposed for the profiler")


func test_a_tile_recovers_exactly_from_a_round_trip_through_world_space() -> void:
	## Every pick, ghost and camera solve is a `world_to_tile` of a position some
	## piece of presentation produced with `tile_to_world`.  The pair has to be an
	## exact inverse at every corner of the map and at every authored height, not an
	## approximate one that happens to work on flat ground.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20250930
	var probes: Array[Vector2i] = [
		Vector2i.ZERO, Vector2i(255, 255), Vector2i(0, 255), Vector2i(255, 0), Vector2i(128, 128),
	]
	for probe in 400:
		probes.append(Vector2i(rng.randi_range(0, 255), rng.randi_range(0, 255)))
	for tile in probes:
		var steps := rng.randi_range(0, 12)
		var position := WorldCoords.tile_to_world(tile, steps)
		check_eq(WorldCoords.world_to_tile(position), tile, "%s survives the round trip" % tile)
		check_near(position.y, float(steps) * WorldConstants.HEIGHT_STEP,
				"elevation travels with the position", 0.0001)
		check_eq(WorldCoords.world_to_height(position.y), steps, "and lands back on the same step")
		check_eq(WorldCoords.world_to_tile_floor(WorldCoords.tile_to_world_xz(tile)), tile,
				"the plan view inverts too")


func test_entity_ids_stay_unique_over_many_creations() -> void:
	## Ids are the only handle the save file, the ledger and the UI have on an
	## entity, so a repeated id is not a cosmetic bug — it points two things at one
	## record.  Checked at the volume a long game would actually reach.
	var session := TestSession.create()
	var drawn := {}
	var repeats := 0
	for draw in 4000:
		var id := session.ids.next_id()
		if id <= 0 or drawn.has(id):
			repeats += 1
		drawn[id] = true
	check_eq(repeats, 0, "4000 ids drawn, none repeated and none reserved for nothing")

	var planted := 0
	var collisions := 0
	for row in 20:
		for column in 20:
			var tile := Vector2i(4 + column, 4 + row)
			var id := session.ids.next_id()
			session.world.set_occupancy(tile, WorldGrid.Occupancy.STATION, id)
			planted += 1
	for row in 20:
		for column in 20:
			var tile := Vector2i(4 + column, 4 + row)
			if session.world.occupancy_entity(tile) == 0:
				collisions += 1
	check_eq(planted, 400, "four hundred lots were booked")
	check_eq(collisions, 0, "and each of them answers to its own id")
	session.world.clear_occupancy(Vector2i(10, 10))
	check_eq(session.world.occupancy_entity(Vector2i(10, 3)), 0, "ground outside the block was never booked")
	check_gt(session.world.occupancy_entity(Vector2i(10, 12)), 0, "clearing one lot leaves its neighbour")
	TestSession.dispose(session)
