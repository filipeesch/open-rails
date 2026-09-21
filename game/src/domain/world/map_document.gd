class_name MapDocument
extends RefCounted

## A sandbox map as authored data.
##
## Heights and terrain are run-length encoded so a 256 × 256 map stays a
## reviewable 40 KiB JSON file instead of a 65,536-line one.  Decoding fills a
## WorldGrid silently — the map is content, not an edit, so it must not mark
## sixty-four thousand tiles dirty.
##
## A document carries three kinds of authored thing, and the loader reads all
## three: the ground (`heights`, `terrain`), the entities (`towns`,
## `industries`) and the feature list (`features`, decoded into `MapFeatures`).
## Ground lands in the grid through `apply_to`; features through
## `place_features`, which is a separate call because the entities have to be
## placed between the two: a town's streets are painted over whatever grew there.

const MAP_ROOT := "res://data/maps"

var id: String = ""
var display_name: String = ""
var width: int = 0
var height: int = 0
var heights: PackedByteArray
var terrain: PackedByteArray
var towns: Array[Dictionary] = []
var industries: Array[Dictionary] = []
## What the author planted: rules and explicit cells, decoded from the map's
## `features` member.  A map without one carries no scenery at all — that is not
## an error, it is a bare valley.
var features: MapFeatures = MapFeatures.new()

var errors: PackedStringArray = PackedStringArray()


static func load_map(map_id: String) -> MapDocument:
	var document := MapDocument.new()
	document.read(map_id)
	return document


func read(map_id: String) -> void:
	var path := MAP_ROOT.path_join(map_id + ".json")
	if not FileAccess.file_exists(path):
		errors.append("map not found: " + path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		errors.append("map is not a JSON object: " + path)
		return
	var data: Dictionary = parsed
	id = String(data.get("id", map_id))
	display_name = String(data.get("display_name", id))
	width = int(data.get("width", 0))
	height = int(data.get("height", 0))
	if width <= 0 or height <= 0:
		errors.append(path + ": missing or non-positive width/height")
		return
	var expected := width * height
	heights = _decode(data.get("heights", {}), expected, path, "heights")
	var terrain_values := _decode_strings(data.get("terrain", {}), expected, path, "terrain")
	terrain = PackedByteArray()
	terrain.resize(expected)
	for index in expected:
		terrain[index] = _terrain_code(String(terrain_values[index]))
	for town in data.get("towns", []):
		if not _has_tile(town, path, "town"):
			continue
		towns.append(town)
	for industry in data.get("industries", []):
		if not _has_tile(industry, path, "industry"):
			continue
		if String(industry.get("definition", "")) == "":
			errors.append("%s: industry '%s' names no definition" % [path, String(industry.get("id", "?"))])
			continue
		industries.append(industry)
	_read_features(data, path)


## Decode the feature list, if the map has one.  Absent means "no scenery",
## which is a legitimate bare map: a map made for a test, or a mod that has not
## planted anything yet.  Present-but-malformed is the opposite — the loader
## reports it, because half a forest is a silent, unfalsifiable surprise.
func _read_features(data: Dictionary, path: String) -> void:
	var raw: Variant = data.get("features", null)
	if raw == null:
		features = MapFeatures.new()
		return
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: features must be an object" % path)
		return
	features = MapFeatures.from_dictionary(raw, path)
	for problem in features.errors:
		errors.append(problem)


## An entity without a tile would silently land on the map corner, which is
## worse than a map that refuses to load.
func _has_tile(entry: Dictionary, path: String, label: String) -> bool:
	var value: Variant = entry.get("tile", null)
	if typeof(value) == TYPE_ARRAY and value.size() >= 2:
		return true
	errors.append("%s: %s '%s' has no tile [x, y]" % [path, label, String(entry.get("id", "?"))])
	return false


func apply_to(world: WorldGrid) -> void:
	world.resize(width, height)
	for index in world.total_tiles():
		world.terrain[index] = terrain[index]
		world.height_steps[index] = heights[index]
	world.take_dirty_tiles()
	world.take_dirty_chunks()


## Plant the authored feature list into a grid that already has this map's
## ground.  Returns the boot report — cells written and how they split by
## scenery kind — so a caller can log or display what grew without walking the
## grid again.
##
## This is deliberately not part of `apply_to`: town and industry ground is
## placed between the two calls, and the feature rules need to know where those
## settlements are to keep their surroundings clear.
func place_features(world: WorldGrid) -> Dictionary:
	return features.place_onto(world, settlement_anchors())


## Every town and industry tile, as authored.  `MapFeatures` treats these as
## settled ground; the footprints themselves are a later concern of the session.
func settlement_anchors() -> Array[Vector2i]:
	var anchors: Array[Vector2i] = []
	for entry in towns:
		anchors.append(town_tile(entry))
	for entry in industries:
		anchors.append(industry_tile(entry))
	return anchors


func terrain_code_to_name(code: int) -> String:
	match code:
		WorldGrid.Terrain.WATER:
			return "water"
		WorldGrid.Terrain.FOREST:
			return "forest"
		WorldGrid.Terrain.ROCK:
			return "rock"
		WorldGrid.Terrain.DIRT:
			return "dirt"
		WorldGrid.Terrain.GRASS:
			return "grass"
		_:
			return "plain"


func town_at(index: int) -> Dictionary:
	return towns[index] if index >= 0 and index < towns.size() else {}


func town_tile(entry: Dictionary) -> Vector2i:
	return _tile(entry.get("tile", [0, 0]))


func industry_tile(entry: Dictionary) -> Vector2i:
	return _tile(entry.get("tile", [0, 0]))


func industry_definition(entry: Dictionary) -> String:
	return String(entry.get("definition", ""))


func entity_name(entry: Dictionary, fallback: String = "") -> String:
	var label := String(entry.get("name", ""))
	return label if label != "" else fallback


func _tile(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_ARRAY and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO


## The terrain layer names ground with words and `WorldGrid` owns that
## vocabulary, so there is one table to drift from, not two.  An unknown word
## here stays plain ground: the layer is one long list of runs and a single
## unusual word is not worth refusing a valley over.  The feature list takes the
## opposite line — there a typo changes what the author planted, so it errors.
func _terrain_code(name: String) -> int:
	var code := WorldGrid.terrain_code_of_name(name)
	return code if code >= 0 else WorldGrid.Terrain.PLAIN


func _decode(layer: Variant, expected: int, path: String, label: String) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(expected)
	if typeof(layer) != TYPE_DICTIONARY or String(layer.get("encoding", "")) != "rle":
		errors.append("%s: %s must be an rle layer" % [path, label])
		return out
	var cursor := 0
	for run in layer.get("run_length", []):
		if typeof(run) != TYPE_ARRAY or run.size() < 2:
			errors.append("%s: %s has a malformed run" % [path, label])
			continue
		var value := int(run[0])
		var count := int(run[1])
		if cursor + count > expected:
			errors.append("%s: %s overruns the declared size" % [path, label])
			break
		for offset in count:
			out[cursor + offset] = clampi(value, 0, 255)
		cursor += count
	if cursor != expected:
		errors.append("%s: %s decoded %d of %d cells" % [path, label, cursor, expected])
	return out


func _decode_strings(layer: Variant, expected: int, path: String, label: String) -> PackedStringArray:
	var out := PackedStringArray()
	out.resize(expected)
	if typeof(layer) != TYPE_DICTIONARY or String(layer.get("encoding", "")) != "rle":
		errors.append("%s: %s must be an rle layer" % [path, label])
		return out
	var cursor := 0
	for run in layer.get("run_length", []):
		if typeof(run) != TYPE_ARRAY or run.size() < 2:
			errors.append("%s: %s has a malformed run" % [path, label])
			continue
		var value := String(run[0])
		var count := int(run[1])
		if cursor + count > expected:
			errors.append("%s: %s overruns the declared size" % [path, label])
			break
		for offset in count:
			out[cursor + offset] = value
		cursor += count
	return out
