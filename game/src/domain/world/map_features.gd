class_name MapFeatures
extends RefCounted

## The scenery a map file asks for, and the deterministic rule that turns it
## into world-grid cells.
##
## Spec §11 requires trees, rocks and bushes spread over the valley, grouped by
## chunk, instanced rather than node-per-object.  All of that is presentation's
## job; this module's job is the *data path*: what the author wrote in the JSON
## becomes `Occupancy.SCENERY` cells naming a `SceneryKind`, and nothing else.
## No node is created here, and no renderer is named.
##
## ## The representation, and why it is this small
##
## Founder's Valley has 13,317 forest tiles.  Hand-typing a tree for each is not
## a map file, it is a database, and the RLE height/terrain layers show the
## authoring format already knows how to say a lot in few bytes.  So a feature
## list comes in two parts, and the JSON is the source for both:
##
## * `scatter` — one rule per ground type: `terrain` (the authored terrain
##   word), `scenery` (the scenery word), `density` (what fraction of that
##   ground carries scenery) and `spacing` (the lattice pitch, so no two
##   instances of a rule can share a `spacing × spacing` block).  This is what
##   makes a wood look like a wood: *where* the rule fires is the map's terrain
##   layer, *how often* is authored here.
## * `placed` — explicit cells for things that are not a ground cover: Marlow's
##   orchard, the boulder field below the west escarpment.  Hand-placed entries
##   are keyed by tile, and they win over scatter.
##
## A rule's `scenery` word, not its terrain, decides what appears: the same
## terrain could carry a thin stand of trees or a dense one, and changing the
## density is an edit to the data file, not to this module.
##
## ## Determinism
##
## No engine random number is drawn here, ever.  Every choice comes from
## `hash_cell()`, a 31-bit integer mix of `(seed, x, y, salt)`.  `seed` is
## authored in the map file (`features.seed`, default `DEFAULT_SEED`), so the
## same file boots the same valley byte for byte on every machine and in every
## session — the invariant the test suite checks by comparing two booted sessions.
##
## Rule order is part of the data: rules are applied in the order the file lists
## them and scatter never replaces scenery that is already there, so two rules
## claiming the same ground resolve the same way every time.  `placed` entries
## are applied last and do replace.


## The scatter seed used when a map file does not name one.  Recorded here as
## well as in the data file: changing it re-tunes every wood on the map.
const DEFAULT_SEED := 90210
## One spacing jitter draw per axis, per rule, so a rule's trees do not line up
## with the lattice or with each other.
const SALT_BLOCK_X := 1
const SALT_BLOCK_Y := 2
## The fill roll for a rule starts above the jitter salts.
const SALT_FILL := 100
## Integer arithmetic keeps every intermediate inside int64 by masking to 31
## bits after each mix step; the mask is what makes the hash reproducible.
const HASH_MASK := 0x7FFFFFFF
const CHANCE_SCALE := 10000

## One `scatter` entry, decoded.
class Rule:
	extends RefCounted
	var terrain_name: String = ""
	var terrain_code: int = -1
	var scenery_name: String = ""
	var scenery_code: int = 0
	var density: float = 0.0
	var spacing: int = 1


var seed_value: int = DEFAULT_SEED
var settlement_clear_radius: int = 0
var rules: Array[Rule] = []
var placed: Array[Dictionary] = []
var errors: PackedStringArray = PackedStringArray()


## Decode the `features` member of a map document.  `path` names the file in
## every complaint, because a map that will not load is unreadable without one.
## Everything in the file is validated: an unknown scenery or terrain word is an
## error, never a fallback, or a typo would silently redraw the valley.
static func from_dictionary(data: Dictionary, path: String) -> MapFeatures:
	var features := MapFeatures.new()
	if data.has("seed"):
		if typeof(data["seed"]) != TYPE_INT and typeof(data["seed"]) != TYPE_FLOAT:
			features.errors.append("%s: features.seed must be a number" % path)
		else:
			features.seed_value = int(data["seed"])
	if data.has("settlement_clear_radius"):
		var radius := int(data["settlement_clear_radius"])
		if radius < 0:
			features.errors.append("%s: settlement_clear_radius is negative" % path)
		else:
			features.settlement_clear_radius = radius
	for raw in Array(data.get("scatter", [])):
		_read_rule(raw, path, features)
	for raw in Array(data.get("placed", [])):
		_read_placed(raw, path, features)
	return features


static func _read_rule(raw: Variant, path: String, features: MapFeatures) -> void:
	if typeof(raw) != TYPE_DICTIONARY:
		features.errors.append("%s: a features.scatter entry is not an object" % path)
		return
	var entry: Dictionary = raw
	var rule := Rule.new()
	rule.terrain_name = String(entry.get("terrain", ""))
	rule.terrain_code = WorldGrid.terrain_code_of_name(rule.terrain_name)
	if rule.terrain_code < 0:
		features.errors.append("%s: scatter names terrain '%s', which is not a terrain" % [
			path, rule.terrain_name])
		return
	if not SceneryKind.is_scatterable(rule.terrain_name):
		features.errors.append("%s: scatter cannot plant on '%s'" % [path, rule.terrain_name])
		return
	rule.scenery_name = String(entry.get("scenery", ""))
	rule.scenery_code = SceneryKind.code_of(rule.scenery_name)
	if rule.scenery_code == 0:
		features.errors.append("%s: scatter names scenery '%s', which does not exist" % [
			path, rule.scenery_name])
		return
	rule.density = float(entry.get("density", 0.0))
	if rule.density <= 0.0 or rule.density > 1.0:
		features.errors.append("%s: scatter on '%s' has density %s, which is not in (0, 1]" % [
			path, rule.terrain_name, str(rule.density)])
		return
	rule.spacing = int(entry.get("spacing", 1))
	if rule.spacing < 1:
		features.errors.append("%s: scatter on '%s' has spacing %d" % [
			path, rule.terrain_name, rule.spacing])
		return
	# `density` promises a fraction of the covered ground.  A lattice can only
	# offer one cell per `spacing × spacing` block, so a density above 1/spacing²
	# is a promise this representation cannot keep — and the honest answer to an
	# author who asks for it is to say so, not to quietly place less.
	if rule.density * float(rule.spacing * rule.spacing) > 1.0:
		features.errors.append(
				"%s: scatter on '%s' asks for density %.3f at spacing %d, but that spacing " \
				% [path, rule.terrain_name, rule.density, rule.spacing]
				+ "holds at most 1/%d of the ground: tighten the spacing or lower the density" \
				% (rule.spacing * rule.spacing))
		return
	features.rules.append(rule)


static func _read_placed(raw: Variant, path: String, features: MapFeatures) -> void:
	if typeof(raw) != TYPE_DICTIONARY:
		features.errors.append("%s: a features.placed entry is not an object" % path)
		return
	var entry: Dictionary = raw
	var scenery_name := String(entry.get("scenery", ""))
	# A group may carry a `name` — "Marlow Orchard" — which is the author talking
	# to whoever reads the file next.  It is what a complaint quotes back, so a
	# failure points at the orchard rather than at 'tree' number four.
	var who := String(entry.get("name", ""))
	if who == "":
		who = scenery_name
	var code := SceneryKind.code_of(scenery_name)
	if code == 0:
		features.errors.append("%s: the placed feature '%s' names scenery '%s', which does not exist" \
				% [path, who, scenery_name])
		return
	var tiles: Array[Vector2i] = []
	var raw_tiles: Variant = entry.get("tiles", [])
	if typeof(raw_tiles) != TYPE_ARRAY or raw_tiles.is_empty():
		features.errors.append("%s: the placed feature '%s' names no tiles" % [path, who])
		return
	for tile_value in raw_tiles:
		if typeof(tile_value) != TYPE_ARRAY or tile_value.size() < 2:
			features.errors.append(
					"%s: the placed feature '%s' has a tile that is not [x, y]" % [path, who])
			continue
		tiles.append(Vector2i(int(tile_value[0]), int(tile_value[1])))
	features.placed.append({"label": who, "kind": scenery_name, "code": code, "tiles": tiles})


## Write every authored feature into `world`, quietly.
##
## `settlement_anchors` are the town and industry tiles: their ground is settled
## country, cleared before the map was drawn, so nothing is planted within
## `settlement_clear_radius` of one.  The footprints themselves are painted over
## scenery by `GameSession` a moment later; the radius is what keeps the ground
## *beside* a town buildable instead of a wood.
##
## The report describes what the grid holds afterwards — `cells`, and `by_kind`
## split by scenery word — because that is the only honest thing to report: an
## authored tree standing on a cell where the lattice had already dropped a bush
## is one scenery cell, not two writes.  `skipped` names each hand-placed group
## that could not stand (water or off the map), by the label the author gave it,
## so an orchard that quietly fell into the river is a number in a report rather
## than eleven missing trees.
func place_onto(world: WorldGrid, settlement_anchors: Array[Vector2i]) -> Dictionary:
	var skipped := {}
	_place_scatter(world, settlement_anchors)
	_place_authored(world, skipped)
	return {
		"cells": count_planted(world),
		"by_kind": planted_by_kind(world),
		"rules": rules.size(),
		"skipped": skipped,
	}


## How many cells of `world` carry scenery.  A whole-map pass: it belongs to
## boot and to diagnostics, never to a tick.
static func count_planted(world: WorldGrid) -> int:
	var cells := 0
	for index in world.total_tiles():
		if world.occupancy_kind[index] == WorldGrid.Occupancy.SCENERY:
			cells += 1
	return cells


## The same pass, split by scenery word.
static func planted_by_kind(world: WorldGrid) -> Dictionary:
	var by_kind := {}
	for index in world.total_tiles():
		if world.occupancy_kind[index] != WorldGrid.Occupancy.SCENERY:
			continue
		var word := SceneryKind.name_of(world.occupancy_id[index])
		by_kind[word] = int(by_kind.get(word, 0)) + 1
	return by_kind


func _place_scatter(world: WorldGrid, anchors: Array[Vector2i]) -> void:
	for rule_index in rules.size():
		var rule := rules[rule_index]
		var chance := minf(1.0, rule.density * float(rule.spacing * rule.spacing))
		var threshold := int(round(chance * float(CHANCE_SCALE)))
		var span := Vector2i(
				int(ceilf(world.width / float(rule.spacing))),
				int(ceilf(world.height / float(rule.spacing))))
		for block_y in span.y:
			for block_x in span.x:
				var tile := _block_cell(world, rule, block_x, block_y)
				if tile == Vector2i(-1, -1):
					continue
				if _inside_settlement(tile, anchors):
					continue
				if hash_cell(seed_value, tile.x, tile.y, SALT_FILL + rule_index) % CHANCE_SCALE \
						>= threshold:
					continue
				_write_scattered(world, tile, rule.scenery_code)


## The one cell of this rule's lattice block that scenery may stand on, or
## (-1, -1) when the ground there is not the ground the rule is about.
func _block_cell(world: WorldGrid, rule: Rule, block_x: int, block_y: int) -> Vector2i:
	var offset := Vector2i(
			hash_cell(seed_value, block_x, block_y, SALT_BLOCK_X) % rule.spacing,
			hash_cell(seed_value, block_x, block_y, SALT_BLOCK_Y) % rule.spacing)
	var tile := Vector2i(block_x * rule.spacing + offset.x, block_y * rule.spacing + offset.y)
	if not world.in_bounds(tile):
		return Vector2i(-1, -1)
	if world.terrain[world.index_of(tile)] != rule.terrain_code:
		return Vector2i(-1, -1)
	return tile


func _place_authored(world: WorldGrid, skipped: Dictionary) -> void:
	for entry in placed:
		var code := int(entry["code"])
		var label := String(entry["label"])
		for tile in Array(entry["tiles"]):
			if not world.in_bounds(tile) or world.is_water(tile):
				skipped[label] = int(skipped.get(label, 0)) + 1
				continue
			# Hand-placed beats scattered: an authored orchard is the author's
			# word against whatever the lattice happened to choose.
			world.set_occupancy_silent(tile, WorldGrid.Occupancy.SCENERY, code)


## Scatter fills a cell, it never re-plants one.  With this rule, the order of
## `scatter` in the file is the whole story of who wins shared ground — and both
## runs of a session read the same file in the same order.
func _write_scattered(world: WorldGrid, tile: Vector2i, code: int) -> void:
	var index := world.index_of(tile)
	if world.occupancy_kind[index] == WorldGrid.Occupancy.SCENERY:
		return
	world.set_occupancy_silent(tile, WorldGrid.Occupancy.SCENERY, code)


func _inside_settlement(tile: Vector2i, anchors: Array[Vector2i]) -> bool:
	if settlement_clear_radius <= 0:
		return false
	for anchor in anchors:
		if maxi(absi(tile.x - anchor.x), absi(tile.y - anchor.y)) <= settlement_clear_radius:
			return true
	return false


## A 31-bit mix of four integers.  Every multiply is masked before the next
## one, so no intermediate reaches the width of an int64 and the result does not
## depend on the platform — which is the whole reason this exists at all, in
## place of an engine random number that no session could replay.
static func hash_cell(seed: int, x: int, y: int, salt: int) -> int:
	var mixed := (seed ^ (x * 374761393)) & HASH_MASK
	mixed = (mixed ^ (y * 668265263)) & HASH_MASK
	mixed = (mixed ^ ((salt * 2654435761) & HASH_MASK)) & HASH_MASK
	mixed = (mixed ^ (mixed >> 13)) & HASH_MASK
	mixed = (mixed * 1274126177) & HASH_MASK
	mixed = (mixed ^ (mixed >> 16)) & HASH_MASK
	return mixed
