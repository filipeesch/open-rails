class_name BuilderService
extends RefCounted

## The only way the player changes the map.
##
## Every construction action costs money through EconomyService and lands an
## undo entry that reverses both the world change and the ledger entry.  The
## ghost preview and the committed action call the same planners, so a preview
## that looked legal always commits with the same result.

signal rail_built(tiles: Array[Vector2i], cost: float)
signal rail_removed(tiles: Array[Vector2i], refund: float)
signal station_built(station_id: int, cost: float)
signal build_failed(reason: String)

var _world: WorldGrid
var _rail: RailService
var _planner: RailPlanner
var _stations: StationService
var _economy: EconomyService
var _registry: DataRegistry
var _undo: UndoService
var _deps: Callable = Callable()


func configure(world: WorldGrid, rail: RailService, planner: RailPlanner, stations: StationService,
		economy: EconomyService, registry: DataRegistry, undo: UndoService) -> void:
	_world = world
	_rail = rail
	_planner = planner
	_stations = stations
	_economy = economy
	_registry = registry
	_undo = undo


func set_dependency_check(callback: Callable) -> void:
	_deps = callback


# --- previews -------------------------------------------------------------

## The rail ghost: planned path, cost and validity, exactly as commit sees it.
func preview_rail(from_tile: Vector2i, to_tile: Vector2i) -> Dictionary:
	var plan := _planner.mark_expensive(_planner.plan(from_tile, to_tile))
	if not bool(plan.get("ok", false)):
		return plan
	var cost := float(plan["cost"])
	plan["affordable"] = _economy.can_afford(cost)
	if not plan["affordable"]:
		plan["warning"] = "Not enough cash for this line"
	return plan


## A hand-drawn run of cells (drag mode) — validated, priced, not committed.
func preview_track_run(tiles: Array[Vector2i]) -> Dictionary:
	var reason := _rail.segment_reason(tiles)
	if reason != "":
		return {"ok": false, "reason": reason, "tiles": tiles, "cost": 0.0}
	return {"ok": true, "reason": "", "tiles": tiles, "cost": run_cost(tiles), "expensive": false}


func run_cost(tiles: Array[Vector2i]) -> float:
	var total := 0.0
	for index in range(1, tiles.size()):
		var direction := _rail.direction_between(tiles[index - 1], tiles[index])
		# A tile set that is not a contiguous run (a scattered removal, say)
		# has no hop to price between far-apart cells; charging one would
		# conjure money out of a refund.
		if direction < 0:
			continue
		total += _registry.track_setting("cost_per_diagonal", 1350.0) \
			if RailDirections.is_diagonal(direction) \
			else _registry.track_setting("cost_per_straight", 950.0)
		if _world.height_at(tiles[index]) != _world.height_at(tiles[index - 1]):
			total += _registry.track_setting("slope_surcharge", 700.0)
	if tiles.size() == 1:
		# A single cell has no hop to price, which would make it free — and one
		# cell is exactly what precision building lays, so free there means track
		# at no cost.  Every cell pays at least the straight rate; a run still
		# pays only for the hops it actually makes.
		total = _registry.track_setting("cost_per_straight", 950.0)
	return Money.round(total)


func preview_station(definition_id: String, anchor: Vector2i) -> Dictionary:
	var reason := _stations.placement_reason(definition_id, anchor)
	var def := _stations.station_def(definition_id)
	var cost := station_cost(definition_id)
	if reason != "":
		# The yard's shape is knowable wherever the pointer stands, and a red ghost
		# has to be drawn somewhere — so the footprint is offered even here.  What
		# is withheld is the promise: no catchment, no covered places, no monthly
		# yield, because ground that cannot hold a station serves nothing.
		return {
			"ok": false, "reason": reason, "cost": cost, "state": "invalid",
			"footprint": WorldCoords.tiles_in_span(anchor, def.footprint),
			"catchment": [] as Array[Vector2i], "catchment_radius": 0.0,
			"sources": [] as Array[Dictionary], "monthly": {},
		}
	var sources := _prospective_sources(definition_id, anchor)
	var affordable := _economy.can_afford(cost)
	var offer := {
		"reason": reason, "cost": cost,
		"ok": affordable,
		# Which kind of "no" this is.  Ground the domain would accept but the
		# treasury cannot cover is a different problem from standing in a river, and
		# the ghost colours them differently; the word is decided here so the
		# readout beside the cursor and the band on the terrain agree on it.
		"state": "ok" if affordable else "expensive",
		"footprint": WorldCoords.tiles_in_span(anchor, def.footprint),
		# The ring the player is really buying is the reach, not the 3x2 yard, so
		# the preview carries the tiles the station would drain from and what they
		# would yield — the figures the first month's invoice will be checked
		# against.  They come from the same services `build_station` uses, so a
		# ghost cannot promise a town it would not in fact cover.
		"catchment": _stations.catchment_tiles_for(definition_id, anchor),
		"catchment_radius": def.catchment_tiles,
		"sources": sources,
		"monthly": _monthly_expectation(sources),
	}
	if not offer["ok"]:
		offer["reason"] = "Not enough cash for a station"
	return offer


## What the station would gather in a month standing here, per cargo.  The
## `rate` numbers are the industry's and town's own monthly output, so the
## ghost's promise is the simulation's arithmetic rather than a second guess at
## it.  Only the `load` side is counted: a sink is something the station will
## deliver to, not something it earns from.
func _monthly_expectation(sources: Array[Dictionary]) -> Dictionary:
	var monthly := {}
	for entry in sources:
		if String(entry.get("role", "")) != "load":
			continue
		var cargo_id := String(entry.get("cargo", ""))
		if cargo_id == "":
			continue
		monthly[cargo_id] = float(monthly.get(cargo_id, 0.0)) + float(entry.get("rate", 0.0))
	return monthly


func station_cost(definition_id: String) -> float:
	return _registry.station_setting("small_station_cost", 20000.0)


# --- rail -----------------------------------------------------------------

## Build the planned line between two points.  Returns the same shape as the
## preview plus `tiles` and `transaction`.
func build_rail(from_tile: Vector2i, to_tile: Vector2i) -> Dictionary:
	var plan := preview_rail(from_tile, to_tile)
	if not bool(plan.get("ok", false)):
		build_failed.emit(String(plan["reason"]))
		return plan
	return _commit_rail_run(plan["tiles"], float(plan["cost"]))


## Build a hand-drawn run of cells.
func build_track_run(tiles: Array[Vector2i]) -> Dictionary:
	var preview := preview_track_run(tiles)
	if not bool(preview.get("ok", false)):
		build_failed.emit(String(preview["reason"]))
		return preview
	return _commit_rail_run(preview["tiles"], float(preview["cost"]))


func _commit_rail_run(tiles: Array[Vector2i], cost: float) -> Dictionary:
	if not _economy.can_afford(cost):
		var reason := "Not enough cash for this line"
		build_failed.emit(reason)
		return {"ok": false, "reason": reason, "tiles": [] as Array[Vector2i]}
	var result := _rail.build_segment(tiles)
	if not bool(result.get("ok", false)):
		build_failed.emit(String(result["reason"]))
		return result
	var added: Array[Vector2i] = result["added"]
	var transaction := _economy.spend(cost, EconomyService.CATEGORY_TRACK,
			"Track: %d tile%s" % [added.size(), "" if added.size() == 1 else "s"])
	if transaction == null:
		var short := "Not enough cash for this line"
		_rail.remove_cells(added)
		build_failed.emit(short)
		return {"ok": false, "reason": short, "tiles": [] as Array[Vector2i]}
	var label := "Build %d tiles of track" % added.size()
	_undo.record(label, func(): _undo_rail(added, transaction),
		Callable(self, "_rail_revert_safe").bind(added))
	rail_built.emit(result["tiles"], cost)
	return {
		"ok": true, "reason": "", "tiles": result["tiles"], "added": added,
		"cost": cost, "transaction": transaction.id,
	}


func remove_track(tiles: Array[Vector2i]) -> Dictionary:
	var blocked := _rail.removal_block(tiles)
	if blocked != "":
		build_failed.emit(blocked)
		return {"ok": false, "reason": blocked, "tiles": [] as Array[Vector2i]}
	var present: Array[Vector2i] = []
	for tile in tiles:
		if _rail.network.has_rail(tile):
			present.append(tile)
	if present.is_empty():
		return {"ok": false, "reason": "No track to remove", "tiles": [] as Array[Vector2i]}
	var refund := Money.round(refund_for(present))
	var result := _rail.remove_cells(present)
	if not bool(result.get("ok", false)):
		build_failed.emit(String(result["reason"]))
		return result
	var spend := _economy.earn(refund, EconomyService.CATEGORY_REFUND,
			"Removed %d tiles of track" % present.size())
	_undo.record("Remove %d tiles of track" % present.size(),
		func(): _undo_removal(present, spend))
	rail_removed.emit(present, refund)
	return {"ok": true, "reason": "", "tiles": present, "refund": refund, "transaction": spend.id}


func refund_for(tiles: Array[Vector2i]) -> float:
	return run_cost(tiles) * 0.5


# --- stations -------------------------------------------------------------

func build_station(definition_id: String, anchor: Vector2i, label: String = "") -> Dictionary:
	var preview := preview_station(definition_id, anchor)
	if not bool(preview.get("ok", false)):
		build_failed.emit(String(preview["reason"]))
		return preview
	var cost := float(preview["cost"])
	var result := _stations.build(definition_id, anchor, label)
	if not bool(result.get("ok", false)):
		build_failed.emit(String(result["reason"]))
		return result
	var transaction := _economy.spend(cost, EconomyService.CATEGORY_STATION,
			"Station: %s" % _stations.name_of(int(result["id"])))
	if transaction == null:
		_stations.remove_station(int(result["id"]))
		var short := "Not enough cash for a station"
		build_failed.emit(short)
		return {"ok": false, "reason": short, "id": 0}
	var station_id := int(result["id"])
	_undo.record("Build %s" % _stations.name_of(station_id),
		func(): _undo_station(station_id, transaction),
		Callable(self, "_station_revert_safe").bind(station_id))
	station_built.emit(station_id, cost)
	return {
		"ok": true, "reason": "", "id": station_id, "cost": cost,
		"footprint": result["footprint"], "transaction": transaction.id,
	}


# --- undo internals -------------------------------------------------------

func _undo_rail(added: Array[Vector2i], transaction: EconomyService.Transaction) -> void:
	# Only the cells this command laid are lifted.  `remove_cell` already
	# clears every neighbour bit pointing into a lifted cell, so pulling in
	# the neighbours here would delete rail a *previous* command paid for.
	_rail.remove_cells(added)
	_economy.refund(transaction.id)


func _undo_removal(tiles: Array[Vector2i], transaction: EconomyService.Transaction) -> void:
	_rail.commit_segment(tiles)
	_economy.refund(transaction.id)


func _undo_station(station_id: int, transaction: EconomyService.Transaction) -> void:
	_stations.remove_station(station_id)
	_economy.refund(transaction.id)


func _station_revert_safe(station_id: int) -> bool:
	if not _stations.has_station(station_id):
		return false
	return _deps.is_valid() and bool(_deps.call("station", station_id))


func _rail_revert_safe(added: Array[Vector2i]) -> bool:
	for tile in added:
		if not _rail.network.has_rail(tile):
			return false
		var owner := _rail.station_dependency(tile)
		if owner != 0:
			return false
	return true


func _prospective_sources(definition_id: String, anchor: Vector2i) -> Array[Dictionary]:
	if not _sources_preview.is_valid():
		return []
	return _sources_preview.call(definition_id, anchor)


var _sources_preview: Callable = Callable()


func provide_sources_preview(callback: Callable) -> void:
	_sources_preview = callback
