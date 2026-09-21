class_name TestSceneryWorld
extends TestBase

## Tasks 2.1 and 3.5, domain side: the scenery an author wrote in
## `data/maps/founders_valley.json` reaching the world the simulation runs on.
##
## Nothing here touches a renderer or a model file.  Scenery in the domain is a
## kind code in a packed array, so every claim below is checkable headless and
## stays true whatever the tree model ends up looking like: authored JSON in,
## deterministic world state out.  The instancing half of 3.5 is measured in
## `test_scenery_instances.gd`; the shipped models in `test_view_terrain.gd`.

const MAP_ID := "founders_valley"
const HASH_MASK := 0x7FFFFFFF
## Pinned output of the shipped feature list: same file, same seed, same
## placement.  If either number moves, something in the data path stopped being
## a pure function of the map file — the invariant the determinism rule is about.
## Re-authoring the map on purpose is expected to move them.
const PLANTED_CELLS := 4703
const SCENERY_CHECKSUM := 16383505
## The same map with the hand-placed groups taken out: the bare lattice, which is
## what a seed test replays.  It differs from `SCENERY_CHECKSUM` by exactly the
## orchard, the hedgerow, the copse, the undergrowth, the crag and the alders.
const SCATTER_CHECKSUM := 1292463687
const TREE_CELLS := 3339
## Slot name for the round-trip case below; the `zz-` prefix is the suite's
## convention for throwaway slots, and `teardown` removes this one by name.
const SLOT_SCENERY := "zz-scenery-round-trip"

var session: GameSession
var map: MapDocument
var _slot: String = ""


func setup() -> void:
	session = TestSession.create(MAP_ID)
	map = MapDocument.load_map(MAP_ID)


func teardown() -> void:
	TestSession.dispose(session)
	session = null
	map = null
	if _slot != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_slot))
		_slot = ""


# --- 2.1 the loader reads the feature list ---------------------------------

func test_the_map_document_reads_the_authored_feature_list() -> void:
	check_eq(map.errors.size(), 0, "the shipped map loads without a complaint")
	check_eq(map.features.seed_value, 90210, "the map names the seed its scenery is hashed from")
	check_eq(map.features.settlement_clear_radius, 6,
		"and how wide a belt of cleared ground the settlements keep")
	check_eq(map.features.rules.size(), 4, "four scatter rules were authored")
	var forest := map.features.rules[0]
	check_eq(forest.terrain_name, "forest", "the first is the woods")
	check_eq(forest.terrain_code, WorldGrid.Terrain.FOREST, "resolved to the grid's own terrain code")
	check_eq(forest.scenery_name, "tree", "which carries trees")
	check_eq(forest.scenery_code, SceneryKind.TREE, "as a kind code, not as a model or a node")
	check_near(forest.density, 0.25, "a quarter of the forest floor carries one", 0.0001)
	check_eq(forest.spacing, 2, "and no two of them inside the same two-by-two block")
	check_eq(map.features.placed.size(), 6, "plus six hand-placed groups")
	var labels := ""
	for entry in map.features.placed:
		labels += String(entry["label"]) + " "
	check_has(labels, "Marlow Orchard", "the orchard is named in the data")
	check_has(labels, "The Fangs", "and so is the boulder field")
	# The whole table, row by row.  The totals further down would notice a silent
	# retune too, but three thousand cells away from the cause; a changed word or
	# pitch has to name the rule it belongs to.
	var authored := [
		["forest", "tree", 0.25, 2],
		["rock", "rock", 0.10, 3],
		["grass", "bush", 0.02, 3],
		["dirt", "bush", 0.01, 4],
	]
	for row in authored:
		var wanted := String(row[0])
		var found: MapFeatures.Rule = null
		for rule in map.features.rules:
			if rule.terrain_name == wanted:
				found = rule
		check_true(found != null, "a rule is authored for '%s' ground" % wanted)
		if found == null:
			continue
		check_eq(found.scenery_name, String(row[1]),
				"what the file says grows on '%s' is what the grid is told" % wanted)
		check_near(found.density, float(row[2]), "at the authored density", 0.0001)
		check_eq(found.spacing, int(row[3]), "at the authored lattice pitch")
	check_eq(map.features.rules.size(), authored.size(),
			"and there are no rules in the file that this table does not know")


func test_a_map_without_a_feature_list_is_a_bare_valley_not_an_error() -> void:
	# Backward compatibility.  Every other map, mod and synthetic grid in the
	# suite loads through this same code, and a map that has not planted anything
	# is a legal map.
	var bare := MapFeatures.from_dictionary({}, "test")
	check_eq(bare.errors.size(), 0, "no features member is not a complaint")
	check_eq(bare.rules.size(), 0, "and it means no scatter rules")
	check_eq(bare.placed.size(), 0, "and nothing hand-placed")
	bare = MapFeatures.from_dictionary({"scatter": [], "placed": []}, "test")
	check_true(bare.errors.is_empty(), "an explicitly empty list is equally legal")
	var blank := GameSession.new()
	check_true(blank.start_blank(32, 32), "a session booted with no map at all still starts")
	check_eq(blank.scenery_cells, 0, "and it holds no scenery")
	check_eq(MapFeatures.count_planted(blank.world), 0, "and the grid says the same")
	blank.free()


func test_scenery_is_data_in_arrays_not_nodes() -> void:
	## A feature entry must not become a node.  The domain evidence for that is
	## where the scenery ended up: the same packed arrays as every other tile
	## fact, inside a world that is itself a RefCounted, with nothing in a tree.
	check_true(session.world is RefCounted, "the world holding the scenery is data, not a node")
	check_true(map.features is RefCounted, "as is the decoded feature list")
	check_true(map.features.rules[0] is RefCounted, "and so is one scatter rule")
	check_eq(typeof(session.world.occupancy_kind), TYPE_PACKED_BYTE_ARRAY,
		"scenery occupies the occupancy array, one byte per cell")
	check_eq(session.world.occupancy_kind.size(), session.world.total_tiles(),
		"one entry per tile, whatever the scenery count: the arrays do not grow")


# --- 3.5 the boot path writes it into the world ----------------------------

func test_boot_puts_the_authored_scenery_into_the_world_grid() -> void:
	var grid := session.world
	var planted := _count_scenery(grid)
	check_gt(float(planted["total"]), 1000.0,
		"a fresh session on the shipped map holds thousands of scenery cells")
	check_eq(planted["total"], PLANTED_CELLS, "and exactly as many as the map was authored to carry")
	check_eq(session.scenery_cells, PLANTED_CELLS,
		"the session's own count is the grid's count, not a promise")
	check_eq(int(planted["kinds"].get("tree", 0)), TREE_CELLS, "three woods' worth of trees")
	check_gt(float(int(planted["kinds"].get("rock", 0))), 500.0, "a strew of rock on the high ground")
	check_gt(float(int(planted["kinds"].get("bush", 0))), 300.0, "and scrub on the open ground")
	check_eq(_kinds_the_domain_does_not_know(grid), 0,
		"every scenery cell names a kind the domain table knows")


func test_scenery_is_written_quietly_a_boot_dirties_nothing() -> void:
	## Scenery arrives as content, not as an edit.  Written through the editing
	## path it would queue four thousand tiles — most of the map's sixty-four
	## chunks — for a rebuild the frame after the rebuild that built them.
	var grid := session.world
	check_false(grid.has_dirty_chunks(), "a booted map reports no dirty chunks")
	check_eq(grid.take_dirty_chunks().size(), 0, "and there really are none to take")
	check_eq(grid.take_dirty_tiles().size(), 0, "nor any dirty tiles")
	check_eq(grid.geometry_rebuild_count(), 0, "so no chunk rebuild has been asked for")


func test_scenery_reaches_every_chunk_of_the_valley() -> void:
	## Instancing grouped by chunk is only worth claiming if the chunks really
	## are populated: one dense corner would let a renderer get away with a node.
	var grid := session.world
	var spread := _chunk_spread(grid)
	var chunks := grid.chunk_count()
	check_eq(float(chunks.x * chunks.y), 64.0, "the shipped map is eight chunks by eight")
	check_eq(spread["chunks"], chunks.x * chunks.y, "and every one of those chunks holds scenery")
	check_gt(float(spread["densest"]), 150.0, "the densest chunk is a wood, not a stray tree")
	check_ge(float(spread["sparsest"]), 1.0, "the sparsest still has something standing in it")
	check_le(float(spread["kinds"]), float(3 * chunks.x * chunks.y),
		"at most one instanced node per chunk per scenery kind")


func test_no_scenery_stands_in_water_or_on_settled_ground() -> void:
	var grid := session.world
	var wet := 0
	for index in grid.total_tiles():
		if grid.occupancy_kind[index] != WorldGrid.Occupancy.SCENERY:
			continue
		if grid.is_water(grid.tile_at(index)):
			wet += 1
	check_eq(wet, 0, "nothing is planted in the river or the mere")
	# The cleared belt is something the *rules* keep.  A hand-placed group may
	# stand inside it — an orchard is the author putting trees beside their own
	# town — so the claim to test is that nothing else does.
	var authored := {}
	for entry in map.features.placed:
		for tile_value in Array(entry["tiles"]):
			var planted: Vector2i = tile_value
			authored["%d:%d" % [planted.x, planted.y]] = true
	var radius := map.features.settlement_clear_radius
	var belt := 0
	var unexplained := 0
	for anchor in map.settlement_anchors():
		for offset_y in range(-radius, radius + 1):
			for offset_x in range(-radius, radius + 1):
				var tile := anchor + Vector2i(offset_x, offset_y)
				if grid.occupancy_at(tile) != WorldGrid.Occupancy.SCENERY:
					continue
				belt += 1
				if not authored.has("%d:%d" % [tile.x, tile.y]):
					unexplained += 1
	check_eq(unexplained, 0,
			"nothing scattered grows within %d tiles of a town or works: the ground beside a " \
			% radius + "platform stays buildable, and the map file is what decided that")
	check_gt(float(belt), 0.0, "and everything that does stand there was placed by hand")
	var scattered := _scatter_only_grid()
	var strays := 0
	for anchor in map.settlement_anchors():
		for offset_y in range(-radius, radius + 1):
			for offset_x in range(-radius, radius + 1):
				if scattered.occupancy_at(anchor + Vector2i(offset_x, offset_y)) \
						== WorldGrid.Occupancy.SCENERY:
					strays += 1
	check_eq(strays, 0, "replay the rules without the hand-placed groups and the belt is empty")
	var marlow := TestSession.town_containing(session, "marlow")
	var square := session.towns.tile_of(marlow)
	check_eq(grid.occupancy_at(square), WorldGrid.Occupancy.TOWN,
		"the town's own ground survived the forest, not the other way round")


func test_the_hand_placed_landmarks_stand_where_they_were_written() -> void:
	var grid := session.world
	var orchard: Array = map.features.placed[0]["tiles"]
	check_eq(orchard.size(), 9, "the orchard is nine cells of trees")
	var wrong := 0
	for tile_value in orchard:
		var tile: Vector2i = tile_value
		if grid.occupancy_at(tile) != WorldGrid.Occupancy.SCENERY \
				or grid.occupancy_entity(tile) != SceneryKind.TREE:
			wrong += 1
	check_eq(wrong, 0, "all nine stand, as trees, after the real boot path")
	var fangs: Array = map.features.placed[4]["tiles"]
	var boulders := 0
	for tile_value in fangs:
		var stone: Vector2i = tile_value
		if grid.occupancy_at(stone) == WorldGrid.Occupancy.SCENERY \
				and grid.occupancy_entity(stone) == SceneryKind.ROCK:
			boulders += 1
	check_eq(boulders, fangs.size(), "and the boulder field is rock, where it was written")
	var report := map.place_features(_ground_grid())
	check_true(Dictionary(report["skipped"]).is_empty(),
		"and no hand-placed cell fell into the water on the way in")


# --- persistence -----------------------------------------------------------

func test_scenery_survives_a_save_and_a_restore() -> void:
	## Scenery is grid state, so it travels with the grid.  A restored session must
	## come back with whatever stood where the player saved it, rather than being
	## replanted from the map file by the boot path.
	_slot = session.saves.slot_path(SLOT_SCENERY)
	var saved := session.saves.save(SLOT_SCENERY)
	check_true(bool(saved.get("ok", false)),
			"the planted valley saves: " + String(saved.get("reason", "")))
	var loaded := TestSession.create(MAP_ID)
	var result := loaded.saves.load(SLOT_SCENERY)
	check_true(bool(result.get("ok", false)),
			"a second session loads the slot: " + String(result.get("reason", "")))
	check_eq(loaded.scenery_cells, PLANTED_CELLS, "and reports the count it saved")
	check_true(loaded.world.occupancy_kind == session.world.occupancy_kind,
			"byte for byte the same cells hold scenery after the round trip")
	check_true(loaded.world.occupancy_id == session.world.occupancy_id,
			"and every one of them names the kind it had when the game was saved")
	TestSession.dispose(loaded)


# --- determinism -----------------------------------------------------------

func test_two_booted_sessions_plant_the_identical_valley() -> void:
	var left := TestSession.create(MAP_ID)
	var right := TestSession.create(MAP_ID)
	check_true(left != null and right != null, "two sessions booted independently")
	check_true(left.world.occupancy_kind == right.world.occupancy_kind,
		"byte for byte, the same cells hold scenery in both")
	check_true(left.world.occupancy_id == right.world.occupancy_id,
		"and every one of them names the same kind")
	check_eq(_checksum(left.world), _checksum(right.world), "their aggregates agree")
	check_eq(_checksum(left.world), SCENERY_CHECKSUM,
		"and the aggregate is the one this map file is known to produce")
	TestSession.dispose(right)
	TestSession.dispose(left)


func test_the_seed_decides_where_a_tree_stands() -> void:
	## The hash is the only source of scatter placement, so pin some of its
	## answers: neither a careless edit nor a different machine may move them.
	check_eq(MapFeatures.hash_cell(90210, 41, 17, 100), 2133346487, "a pinned mix")
	check_eq(MapFeatures.hash_cell(90210, 41, 17, 101), 1003780830, "one per rule")
	check_eq(MapFeatures.hash_cell(90211, 41, 17, 100), 859220744, "and one per seed")
	var first := _planted_with_seed(90210)
	var same := _planted_with_seed(90210)
	var other := _planted_with_seed(90211)
	check_eq(_checksum(first), _checksum(same), "the same seed boots the same valley twice")
	check_eq(_checksum(first), SCATTER_CHECKSUM, "and the lattice alone is a pinned answer")
	check_neq(_checksum(other), _checksum(first), "a different seed boots a different one")
	check_gt(float(MapFeatures.count_planted(other)), 1000.0,
		"still a full valley, not an accident of one number")


func test_the_feature_list_decides_what_appears_not_the_terrain_alone() -> void:
	# The claim that keeps 2.1 honest.  Same ground, same seed, same lattice: the
	# only difference is a word in the feature list.
	var trees := _planted_with_rule({"terrain": "forest", "scenery": "tree",
			"density": 0.25, "spacing": 2})
	var bushes := _planted_with_rule({"terrain": "forest", "scenery": "bush",
			"density": 0.25, "spacing": 2})
	var thin := _planted_with_rule({"terrain": "forest", "scenery": "tree",
			"density": 0.05, "spacing": 2})
	var rock := _planted_with_rule({"terrain": "rock", "scenery": "rock",
			"density": 0.10, "spacing": 3})
	check_eq(MapFeatures.count_planted(trees), MapFeatures.count_planted(bushes),
		"one word changes what grows there, not which cells were chosen")
	var shared := 0
	var as_bush := 0
	for index in trees.total_tiles():
		if trees.occupancy_kind[index] != WorldGrid.Occupancy.SCENERY:
			continue
		if bushes.occupancy_kind[index] == WorldGrid.Occupancy.SCENERY:
			shared += 1
		if bushes.occupancy_id[index] == SceneryKind.BUSH:
			as_bush += 1
	check_eq(shared, MapFeatures.count_planted(trees),
		"every cell the tree rule chose is the cell the bush rule chose")
	check_eq(as_bush, MapFeatures.count_planted(bushes),
		"and each of them names the scenery the file asked for, not what forest means")
	check_lt(float(MapFeatures.count_planted(thin)), float(MapFeatures.count_planted(trees)) * 0.5,
		"a fifth of the density is a thin wood, not the same wood by another name")
	check_gt(float(MapFeatures.count_planted(rock)), 100.0,
		"a rule naming rock plants the high ground instead of the woods")
	check_eq(_scenery_on_terrain(rock, WorldGrid.Terrain.FOREST), 0,
		"and none of it drifted onto the forest floor")


func test_a_feature_list_that_lies_is_refused() -> void:
	var unknown_kind := MapFeatures.from_dictionary(
			{"scatter": [{"terrain": "forest", "scenery": "willow", "density": 0.2, "spacing": 2}]},
			"lie.json")
	check_eq(unknown_kind.errors.size(), 1, "an invented scenery word is one complaint")
	check_has(String(unknown_kind.errors[0]), "willow", "and it names the word that is not real")
	check_eq(unknown_kind.rules.size(), 0, "nothing half-decoded is left behind")
	var unknown_ground := MapFeatures.from_dictionary(
			{"scatter": [{"terrain": "tundra", "scenery": "tree", "density": 0.2, "spacing": 2}]},
			"lie.json")
	check_has(String(unknown_ground.errors[0]), "tundra", "an invented terrain is refused too")
	var in_the_river := MapFeatures.from_dictionary(
			{"scatter": [{"terrain": "water", "scenery": "tree", "density": 0.2, "spacing": 2}]},
			"lie.json")
	check_has(String(in_the_river.errors[0]), "water", "and so is a rule that would plant a river")
	var unreachable := MapFeatures.from_dictionary(
			{"scatter": [{"terrain": "forest", "scenery": "tree", "density": 0.9, "spacing": 3}]},
			"lie.json")
	check_has(String(unreachable.errors[0]), "spacing", "a density the spacing cannot hold is refused")
	var bad_spacing := MapFeatures.from_dictionary(
			{"scatter": [{"terrain": "forest", "scenery": "tree", "density": 0.2, "spacing": 0}]},
			"lie.json")
	check_eq(bad_spacing.rules.size(), 0, "and a lattice with no pitch never divides")
	var no_tiles := MapFeatures.from_dictionary(
			{"placed": [{"name": "Nowhere Orchard", "scenery": "tree", "tiles": []}]}, "lie.json")
	check_has(String(no_tiles.errors[0]), "Nowhere Orchard", "a placed group with no cells is named out")
	var off_map := MapFeatures.from_dictionary(
			{"placed": [{"name": "Atlantis", "scenery": "tree", "tiles": [[999, 999]]}]}, "lie.json")
	check_eq(off_map.errors.size(), 0, "a cell past the edge is not a syntax error in the file")
	var world := _ground_grid()
	var anchors: Array[Vector2i] = []
	off_map.place_onto(world, anchors)
	check_eq(MapFeatures.count_planted(world), 0, "but nothing is planted off the map either")


# --- helpers ---------------------------------------------------------------

func _count_scenery(grid: WorldGrid) -> Dictionary:
	var kinds := {}
	var total := 0
	for index in grid.total_tiles():
		if grid.occupancy_kind[index] != WorldGrid.Occupancy.SCENERY:
			continue
		total += 1
		var word := SceneryKind.name_of(grid.occupancy_id[index])
		kinds[word] = int(kinds.get(word, 0)) + 1
	return {"total": total, "kinds": kinds}


func _kinds_the_domain_does_not_know(grid: WorldGrid) -> int:
	var strangers := 0
	for index in grid.total_tiles():
		if grid.occupancy_kind[index] != WorldGrid.Occupancy.SCENERY:
			continue
		if not SceneryKind.is_known(grid.occupancy_id[index]):
			strangers += 1
	return strangers


func _chunk_spread(grid: WorldGrid) -> Dictionary:
	var per_chunk := {}
	var kinds := {}
	for index in grid.total_tiles():
		if grid.occupancy_kind[index] != WorldGrid.Occupancy.SCENERY:
			continue
		var chunk := grid.chunk_of(grid.tile_at(index))
		var key := "%d:%d" % [chunk.x, chunk.y]
		per_chunk[key] = int(per_chunk.get(key, 0)) + 1
		kinds["%s:%d" % [key, grid.occupancy_id[index]]] = true
	var sparsest := 1 << 30
	var densest := 0
	for key in per_chunk.keys():
		sparsest = mini(sparsest, int(per_chunk[key]))
		densest = maxi(densest, int(per_chunk[key]))
	return {"chunks": per_chunk.size(), "sparsest": sparsest, "densest": densest,
			"kinds": kinds.size()}


func _scenery_on_terrain(grid: WorldGrid, terrain: int) -> int:
	var found := 0
	for index in grid.total_tiles():
		if grid.occupancy_kind[index] != WorldGrid.Occupancy.SCENERY:
			continue
		if grid.terrain[index] == terrain:
			found += 1
	return found


## A whole-map aggregate of where the scenery is, in index order.  Two grids
## that agree on this agree on every planted cell, and it costs one pass.
func _checksum(grid: WorldGrid) -> int:
	var mixed := 0
	for index in grid.total_tiles():
		if grid.occupancy_kind[index] != WorldGrid.Occupancy.SCENERY:
			continue
		mixed = (mixed * 131 + index * 7 + grid.occupancy_id[index]) & HASH_MASK
	return mixed


## The shipped map's ground on a fresh grid, with no scenery on it yet.
func _ground_grid() -> WorldGrid:
	var world := WorldGrid.new()
	map.apply_to(world)
	return world


func _planted_with_seed(seed_value: int) -> WorldGrid:
	var world := _ground_grid()
	var features := MapFeatures.from_dictionary(_shipped_rules_as_data(), "seed-test")
	features.seed_value = seed_value
	features.place_onto(world, map.settlement_anchors())
	return world


## The shipped rules with the hand-placed groups taken away, so a seed test
## measures the lattice and nothing else.
func _scatter_only_grid() -> WorldGrid:
	return _planted_with_seed(map.features.seed_value)


func _planted_with_rule(rule: Dictionary) -> WorldGrid:
	var world := _ground_grid()
	var features := MapFeatures.from_dictionary(
			{"seed": 90210, "settlement_clear_radius": 6, "scatter": [rule]}, "rule-test")
	check_true(features.errors.is_empty(), "the test rule is well formed: %s" % features.errors)
	features.place_onto(world, map.settlement_anchors())
	return world


## The shipped scatter rules as plain data, so a seed test changes nothing else.
func _shipped_rules_as_data() -> Dictionary:
	var rules: Array = []
	for rule in map.features.rules:
		rules.append({
			"terrain": rule.terrain_name,
			"scenery": rule.scenery_name,
			"density": rule.density,
			"spacing": rule.spacing,
		})
	return {
		"seed": map.features.seed_value,
		"settlement_clear_radius": map.features.settlement_clear_radius,
		"scatter": rules,
	}
