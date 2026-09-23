class_name TownService
extends RefCounted

## Towns as economic entities.
##
## A town is a data-shaped record: id, name, population, position and two
## generation rates.  It does not grow in V1 — population is fixed at load —
## and its buildings are decoration, not simulation.

signal town_added(town_id: int)

var _towns := {}
var _order: Array[int] = []
var _ids: IdFactory


func configure(ids: IdFactory) -> void:
	_ids = ids


func add_from_map(entry: Dictionary, tile: Vector2i, stable_id: int) -> int:
	var town := {
		"id": stable_id,
		"name": String(entry.get("name", "Town")),
		"population": int(entry.get("population", 500)),
		"tile": tile,
		"passengers_per_month": float(entry.get("passengers_per_month", 0.0)),
		"mail_per_month": float(entry.get("mail_per_month", 0.0)),
	}
	_towns[stable_id] = town
	_order.append(stable_id)
	_ids.adopt_highest(stable_id)
	town_added.emit(stable_id)
	return stable_id


func towns() -> Array[int]:
	return _order


func count() -> int:
	return _order.size()


func town(town_id: int) -> Dictionary:
	return _towns.get(town_id, {})


func name_of(town_id: int) -> String:
	return String(town(town_id).get("name", "Unknown"))


func tile_of(town_id: int) -> Vector2i:
	return town(town_id).get("tile", Vector2i.ZERO)


func population_of(town_id: int) -> int:
	return int(town(town_id).get("population", 0))


## The settlement the valley opens on.
##
## Whoever boots the game should be looking at ground with a name on it, and the
## domain already knows which town that is: the one with the most people, which
## is also the one whose cargo pays the bills.  Stating it here keeps the opening
## view a fact about the map rather than a guess about where the player wants to
## be.  Ties fall to the lower id, which is the map's own order.
func principal_town() -> int:
	var best := 0
	var best_population := -1
	for town_id in _order:
		var population := population_of(town_id)
		if population > best_population:
			best_population = population
			best = town_id
	return best


## The block of ground a town's square and its frontages claim.
##
## A town is a place rather than a placed building, so it claims its ground from
## the map: that makes a click on the square resolve to the town id (invariant 3 —
## an id, never a node path) and keeps track from being run through Main Street.
## The claim is deliberately one block, whatever the population: a station needs
## its own 3 x 2 of ground clear of town cells *and* straight rail within two
## tiles, so a bigger claim would leave a town with nowhere to build its platform.
## Population drives the cargo and the scatter of houses, not the property line.
const FOOTPRINT := Vector2i(3, 3)


func footprint_of(_town_id: int) -> Vector2i:
	return FOOTPRINT


## Every cell the town claims, centred on its tile.
func footprint_tiles(town_id: int) -> Array[Vector2i]:
	return WorldCoords.tiles_in_span(tile_of(town_id) - FOOTPRINT / 2, FOOTPRINT)


func generation_of(town_id: int, cargo_id: String) -> float:
	match cargo_id:
		"passengers":
			return float(town(town_id).get("passengers_per_month", 0.0))
		"mail":
			return float(town(town_id).get("mail_per_month", 0.0))
	return 0.0


## Per-cargo monthly output, in the shape the cargo allocator consumes.
func generation_map(town_id: int) -> Dictionary:
	var out := {}
	var passengers := generation_of(town_id, "passengers")
	var mail := generation_of(town_id, "mail")
	if passengers > 0.0:
		out["passengers"] = passengers
	if mail > 0.0:
		out["mail"] = mail
	return out


func nearest_to(tile: Vector2i) -> int:
	var best := 0
	var best_distance := 1e9
	for town_id in _order:
		var distance := WorldCoords.distance_tiles(tile_of(town_id), tile)
		if distance < best_distance:
			best_distance = distance
			best = town_id
	return best


func to_dict() -> Dictionary:
	var entries: Array = []
	for town_id in _order:
		var entry: Dictionary = _towns[town_id]
		entries.append({
			"id": town_id,
			"name": entry["name"],
			"population": entry["population"],
			"x": entry["tile"].x,
			"y": entry["tile"].y,
			"passengers_per_month": entry["passengers_per_month"],
			"mail_per_month": entry["mail_per_month"],
		})
	return {"towns": entries}


func from_dict(data: Dictionary) -> void:
	_towns.clear()
	_order.clear()
	for entry in data.get("towns", []):
		var town_id := int(entry["id"])
		_towns[town_id] = {
			"id": town_id,
			"name": String(entry.get("name", "Town")),
			"population": int(entry.get("population", 500)),
			"tile": Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0))),
			"passengers_per_month": float(entry.get("passengers_per_month", 0.0)),
			"mail_per_month": float(entry.get("mail_per_month", 0.0)),
		}
		_order.append(town_id)
		if _ids != null:
			_ids.adopt_highest(town_id)
