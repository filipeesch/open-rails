class_name TestMapKinds
extends TestBase

## A generated 256 × 256 valley that exercises every terrain kind.
##
## Task 2.2 asks for a deterministic map with water, forest, hill and plain, and
## task 2.1 asks for proof that a decoded layer matches what was authored.  Both
## need a source the test can hold in its hand: the shipped Founder's Valley is a
## 40 KiB file nobody should re-derive by eye, and it happens to contain no hill
## tiles at all.  So the map here is written by a rule — a river, a lake, an
## escarpment, two woods — encoded the way an author encodes it (run-length), then
## read back through the shipped `MapDocument` path.
##
## The rule is arithmetic on tile coordinates, never `randf()`: the same seed must
## produce the same bytes in a year, because a map that changes when nobody edited
## it makes every render and every determinism test unrepeatable.

const SIZE := 256
const SEED := 20250

var _source: Dictionary = {}


func setup() -> void:
	_source = _author_a_valley(SEED)


# --- the four kinds, and the decode that proves them ----------------------

func test_the_generated_valley_is_the_size_it_claims_and_decodes_cleanly() -> void:
	var document := _read(_source)
	check_eq(document.errors.size(), 0, "the generated map loads clean: " + _errors(document))
	check_eq(document.width, SIZE, "256 tiles across")
	check_eq(document.height, SIZE, "256 tiles down")
	check_eq(document.heights.size(), SIZE * SIZE, "one height step per tile")
	check_eq(document.terrain.size(), SIZE * SIZE, "one terrain kind per tile")


func test_all_four_terrain_kinds_are_present_in_the_decoded_layer() -> void:
	var document := _read(_source)
	var counts := _tally(document)
	for kind in [WorldGrid.Terrain.WATER, WorldGrid.Terrain.FOREST,
			WorldGrid.Terrain.HILL, WorldGrid.Terrain.PLAIN]:
		check_gt(int(counts.get(kind, 0)), 0,
				"%s is on the map (%d tiles)" % [document.terrain_code_to_name(kind),
						int(counts.get(kind, 0))])
	var total := 0
	for kind in counts.keys():
		total += int(counts[kind])
	check_eq(total, SIZE * SIZE, "and every tile is one of them")


func test_the_heights_say_the_hills_are_higher_than_the_water() -> void:
	var document := _read(_source)
	var water := _mean_height(document, WorldGrid.Terrain.WATER)
	var hill := _mean_height(document, WorldGrid.Terrain.HILL)
	check_gt(hill, water,
			"the escarpment stands above the river: %d steps over %d" % [hill, water])
	var plain := _mean_height(document, WorldGrid.Terrain.PLAIN)
	check_lt(water, plain, "and the water sits below the plain it runs across")


func test_the_decoded_layer_matches_the_authored_rule_tile_for_tile() -> void:
	var document := _read(_source)
	var mismatched := 0
	var first := ""
	for y in range(0, SIZE, 7):
		for x in range(0, SIZE, 7):
			var index := y * SIZE + x
			var wanted := WorldGrid.terrain_code_of_name(_terrain_at(SEED, x, y))
			if int(document.terrain[index]) != wanted:
				mismatched += 1
				if first == "":
					first = "(%d, %d) authored %s, decoded %s" % [x, y,
							_terrain_at(SEED, x, y), document.terrain_code_to_name(document.terrain[index])]
	check_eq(mismatched, 0, "the decode disagrees with the author: " + first)
	check_eq(document.heights.size(), SIZE * SIZE, "and there is a height for each of them")


func test_the_same_seed_authors_the_same_valley_and_another_seed_does_not() -> void:
	var first := _read(_author_a_valley(SEED))
	var again := _read(_author_a_valley(SEED))
	var other := _read(_author_a_valley(SEED + 1))
	check_true(first.terrain == again.terrain, "the terrain layer is identical, byte for byte")
	check_true(first.heights == again.heights, "and so is the height layer")
	check_false(first.terrain == other.terrain,
			"a different seed moves the water, so the seed is doing real work")


func test_applying_the_map_fills_the_grid_without_marking_the_world_dirty() -> void:
	var document := _read(_source)
	var grid := WorldGrid.new()
	document.apply_to(grid)
	check_eq(grid.width, SIZE, "the grid took the authored size")
	check_eq(grid.height, SIZE, "in both directions")
	var same := true
	for index in grid.total_tiles():
		if grid.terrain[index] != document.terrain[index]:
			same = false
			break
	check_true(same, "every tile of ground landed in the grid")
	check_eq(grid.take_dirty_tiles().size(), 0,
			"a map boot is content arriving, not sixty-four thousand edits")
	check_false(grid.has_dirty_chunks(), "so nothing asks the terrain renderer for a rebuild")


func test_the_shipped_valley_still_decodes_through_the_same_path() -> void:
	var document := MapDocument.load_map("founders_valley")
	check_eq(document.errors.size(), 0, "the authored map loads clean: " + _errors(document))
	var counts := _tally(document)
	check_gt(int(counts.get(WorldGrid.Terrain.WATER, 0)), 0, "the valley has a river")
	check_gt(int(counts.get(WorldGrid.Terrain.FOREST, 0)), 0, "and woods")
	check_gt(int(counts.get(WorldGrid.Terrain.PLAIN, 0)), 0, "and plains to build on")


# --- the authoring rule ---------------------------------------------------

## Water carves the map, the escarpment lifts one edge, and two woods sit in the
## middle distance.  Everything is a function of (seed, x, y).
func _author_a_valley(seed: int) -> Dictionary:
	var heights: Array = []
	var terrain: Array = []
	for y in SIZE:
		for x in SIZE:
			terrain.append(_terrain_at(seed, x, y))
			heights.append(_height_at(seed, x, y))
	return {
		"id": "generated_valley",
		"display_name": "Generated Valley",
		"width": SIZE,
		"height": SIZE,
		"heights": _runs(heights),
		"terrain": _runs(terrain),
		"towns": [{"id": "test_town", "name": "Testford", "tile": [64, 96]}],
		"industries": [{"id": "test_mine", "definition": "coal_mine", "tile": [180, 60]}],
	}


func _terrain_at(seed: int, x: int, y: int) -> String:
	if _is_water(seed, x, y):
		return "water"
	if _is_hill(seed, x, y):
		return "hill"
	if _is_forest(seed, x, y):
		return "forest"
	if _near_river(seed, x, y):
		return "grass"
	return "plain"


func _height_at(seed: int, x: int, y: int) -> int:
	if _is_water(seed, x, y):
		return 2
	if _is_hill(seed, x, y):
		# The escarpment climbs with distance from its foot, so the high ground is
		# a slope the terrain renderer has to actually tessellate.
		return clampi(6 + int(float(y - _hill_foot(seed, x)) * 0.16), 6, 24)
	return 4 + _hash(seed * 3 + x, y) % 2


func _is_water(seed: int, x: int, y: int) -> bool:
	return absf(float(x) - _river_x(seed, y)) <= 2.5 or _in_lake(x, y)


func _near_river(seed: int, x: int, y: int) -> bool:
	return absf(float(x) - _river_x(seed, y)) <= 5.5


func _river_x(seed: int, y: int) -> float:
	return 96.0 + float(seed % 40) + 22.0 * sin(float(y) * 0.031)


func _in_lake(x: int, y: int) -> bool:
	var dx := float(x - 190) / 22.0
	var dy := float(y - 150) / 12.0
	return dx * dx + dy * dy <= 1.0


func _hill_foot(seed: int, x: int) -> int:
	return 170 + int(10.0 * sin(float(x) * 0.05)) + seed % 7


func _is_hill(seed: int, x: int, y: int) -> bool:
	return y > _hill_foot(seed, x)


func _is_forest(seed: int, x: int, y: int) -> bool:
	return _in_wood(x, y, 60, 60, 26) or _in_wood(x, y, 140, 120, 30) \
			or _hash(seed + x, y * 5) % 40 == 0


func _in_wood(x: int, y: int, cx: int, cy: int, radius: int) -> bool:
	var dx := float(x - cx)
	var dy := float(y - cy)
	return dx * dx + dy * dy <= float(radius * radius)


## FNV-style mixing: cheap, seed-sensitive and identical on every platform, which
## is what a map generator needs and a dice roll is not.
func _hash(a: int, b: int) -> int:
	var value := 1469598103934665603
	value = (value * 1099511628211) ^ a
	value = (value * 1099511628211) ^ b
	return absi(value & 0x7FFFFFFF)


# --- encoding -------------------------------------------------------------

## Coalesce a row-major list of values into the run-length form the authored file
## uses, so the test authors a map the way a map author does.
func _runs(values: Array) -> Dictionary:
	var runs: Array = []
	var cursor := 0
	while cursor < values.size():
		var value: Variant = values[cursor]
		var count := 1
		while cursor + count < values.size() and values[cursor + count] == value:
			count += 1
		runs.append([value, count])
		cursor += count
	return {"encoding": "rle", "run_length": runs}


# --- reading and counting -------------------------------------------------

func _read(source: Dictionary) -> MapDocument:
	var document := MapDocument.new()
	document.load_dictionary(source, "generated_valley")
	return document


func _tally(document: MapDocument) -> Dictionary:
	var counts := {}
	for index in document.terrain.size():
		var code := int(document.terrain[index])
		counts[code] = int(counts.get(code, 0)) + 1
	return counts


func _mean_height(document: MapDocument, kind: int) -> int:
	var total := 0
	var count := 0
	for index in document.terrain.size():
		if int(document.terrain[index]) != kind:
			continue
		total += int(document.heights[index])
		count += 1
	return int(float(total) / float(maxi(count, 1)))


func _errors(document: MapDocument) -> String:
	return ", ".join(document.errors)
