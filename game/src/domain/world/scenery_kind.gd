class_name SceneryKind
extends RefCounted

## What a scenery cell in the world grid actually names.
##
## A scenery cell is `Occupancy.SCENERY` plus a small integer in `occupancy_id`.
## That integer is not an entity id — scenery has no identity, no owner and
## nothing to look up — it is a *kind*, and the kind table lives here because
## the map file names scenery by these words and the grid stores it as bytes.
##
## The codes are a contract with the presentation layer:
## `TerrainRenderer.SCENERY_ASSETS` maps each of them to a model, and
## `test_scenery_world.gd` fails if a code exists here that the renderer cannot
## draw.  Nothing in this file knows a renderer exists; the dependency runs the
## other way.
##
## Scenery is data, never a node: `WorldGrid` holds one kind byte's worth of
## information per cell and the renderer instances them per chunk.

const TREE := 1
const ROCK := 2
const BUSH := 3

const NAMES: PackedStringArray = ["tree", "rock", "bush"]

## Terrains that carry no scenery at all, whatever a scatter rule asks for.
## Nothing stands in open water, so a rule naming water is an authoring mistake
## and the map loader says so rather than planting a river.
const UNSCATTERABLE: PackedStringArray = ["water"]


## The code for a scenery word, or 0 when the word names nothing known.
## Zero means "no scenery", so a typo can never quietly become a tree.
static func code_of(name: String) -> int:
	for index in NAMES.size():
		if NAMES[index] == name:
			return index + 1
	return 0


static func name_of(code: int) -> String:
	if code >= 1 and code <= NAMES.size():
		return NAMES[code - 1]
	return "unknown"


static func is_known(code: int) -> bool:
	return code >= 1 and code <= NAMES.size()


static func is_scatterable(terrain_name: String) -> bool:
	return not UNSCATTERABLE.has(terrain_name)


## Every valid code, for validation and for tests that enumerate the table.
static func codes() -> Array[int]:
	var out: Array[int] = []
	for index in NAMES.size():
		out.append(index + 1)
	return out
