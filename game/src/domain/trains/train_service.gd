class_name TrainService
extends RefCounted

## Deterministic train movement and cargo handling on the integer tick.
##
## Trains carry aggregated batches, never one object per passenger.  A batch
## remembers where it was loaded and how far it has ridden, which is what makes
## distance- and age-weighted revenue possible without a path query per unit.

signal train_created(train_id: int)
signal train_removed(train_id: int)
signal train_arrived(train_id: int, station_id: int)
signal train_departed(train_id: int, station_id: int)
signal train_route_changed(train_id: int, route_id: int)
signal consist_changed(train_id: int)
signal train_revenue(train_id: int, station_id: int, cargo_id: String, revenue: float)

enum State { IDLE, LOADING, MOVING, LOST }

## km/h → tiles per 20 Hz tick.  Chosen so a 4-4-0 at full speed crosses a
## typical 40-tile route in well under a simulated day.
const KMH_TO_TILE_PER_TICK := 0.0105
const LOAD_PER_TICK := 1.6

## What comes back when a train is sold.  Half, because the works buys the steel
## second-hand — and stated as a figure so a confirm prompt can promise it.
const REFUND_RATE := 0.5

var _trains := {}
var _order: Array[int] = []
var _world: WorldGrid
var _rail: RailService
var _stations: StationService
var _routes: RouteService
var _cargo: CargoService
var _economy: EconomyService
var _registry: DataRegistry
var _clock: SimulationClock
var _ids: IdFactory
var _next_train_number := 1


func configure(world: WorldGrid, rail: RailService, stations: StationService, routes: RouteService,
		cargo: CargoService, economy: EconomyService, registry: DataRegistry,
		clock: SimulationClock, ids: IdFactory) -> void:
	_world = world
	_rail = rail
	_stations = stations
	_routes = routes
	_cargo = cargo
	_economy = economy
	_registry = registry
	_clock = clock
	_ids = ids


# --- purchase -------------------------------------------------------------

## A train is bought at a station: locomotive + an ordered list of wagons.
func purchase(station_id: int, locomotive_id: String, wagon_ids: Array[String]) -> Dictionary:
	var loco := _registry.stock(locomotive_id)
	if loco == null or loco.kind != "locomotive":
		return {"ok": false, "reason": "Unknown locomotive", "id": 0}
	if not _stations.has_station(station_id):
		return {"ok": false, "reason": "A train must start at a station", "id": 0}
	var stock_ids: Array[String] = [locomotive_id]
	for wagon_id in wagon_ids:
		var wagon := _registry.stock(wagon_id)
		if wagon == null or wagon.kind != "wagon":
			return {"ok": false, "reason": "Unknown wagon '%s'" % wagon_id, "id": 0}
		stock_ids.append(wagon_id)
	var price := consist_price(stock_ids)
	var transaction := _economy.spend(price, EconomyService.CATEGORY_TRAIN,
			"Train: %s ×1, %s" % [loco.display_name, _wagon_summary(wagon_ids)])
	if transaction == null:
		return {"ok": false, "reason": "Not enough cash for this train", "id": 0}
	var train_id := _ids.next_id()
	_trains[train_id] = _new_train(train_id, station_id, stock_ids, transaction.id)
	_order.append(train_id)
	_next_train_number += 1
	train_created.emit(train_id)
	return {
		"ok": true, "reason": "", "id": train_id, "price": price,
		"transaction": transaction.id,
	}


## What selling pays back.  Stated before the sale so a confirm prompt can be
## honest about the number it is about to pay.
func refund_for(train_id: int) -> float:
	return Money.round(consist_price(stock_of(train_id)) * REFUND_RATE)


func sell(train_id: int) -> bool:
	var instance := train(train_id)
	if instance.is_empty():
		return false
	_economy.earn(refund_for(train_id), EconomyService.CATEGORY_REFUND,
			"Sold %s" % instance["name"])
	_trains.erase(train_id)
	_order.erase(train_id)
	train_removed.emit(train_id)
	return true


func add_wagon(train_id: int, wagon_id: String, at_index: int = -1) -> Dictionary:
	var instance := train(train_id)
	if instance.is_empty():
		return {"ok": false, "reason": "Unknown train", "id": 0}
	var wagon := _registry.stock(wagon_id)
	if wagon == null or wagon.kind != "wagon":
		return {"ok": false, "reason": "Unknown wagon '%s'" % wagon_id, "id": 0}
	var transaction := _economy.spend(wagon.price, EconomyService.CATEGORY_WAGON,
			"Wagon: %s for %s" % [wagon.display_name, instance["name"]])
	if transaction == null:
		return {"ok": false, "reason": "Not enough cash for that wagon", "id": 0}
	var stock: Array[String] = _string_list(instance["stock"])
	var index := at_index if at_index >= 0 else stock.size()
	stock.insert(clampi(index, 1, stock.size()), wagon_id)
	instance["stock"] = stock
	instance["wagon_transactions"].append(transaction.id)
	consist_changed.emit(train_id)
	_refresh_rating(train_id)
	return {"ok": true, "reason": "", "id": train_id, "price": wagon.price}


func remove_wagon(train_id: int, index: int) -> bool:
	var instance := train(train_id)
	if instance.is_empty():
		return false
	var stock: Array[String] = _string_list(instance["stock"])
	if index < 1 or index >= stock.size():
		return false
	var wagon := _registry.stock(stock[index])
	stock.remove_at(index)
	instance["stock"] = stock
	var transactions: Array = instance["wagon_transactions"]
	if transactions.size() >= index:
		transactions.remove_at(index - 1)
	if wagon != null:
		_economy.earn(Money.round(wagon.price * 0.5), EconomyService.CATEGORY_REFUND,
				"Sold %s from %s" % [wagon.display_name, instance["name"]])
	consist_changed.emit(train_id)
	_refresh_rating(train_id)
	return true


func move_wagon(train_id: int, from_index: int, to_index: int) -> bool:
	## `to_index` is the slot the wagon should occupy in the consist that comes
	## back, and index 0 — the engine — is not a slot a wagon can take.
	var instance := train(train_id)
	if instance.is_empty():
		return false
	var stock: Array[String] = _string_list(instance["stock"])
	if from_index < 1 or from_index >= stock.size():
		return false
	var to := clampi(to_index, 1, stock.size() - 1)
	if to == from_index:
		return false
	var wagon_id := stock[from_index]
	stock.remove_at(from_index)
	stock.insert(to, wagon_id)
	instance["stock"] = stock
	consist_changed.emit(train_id)
	return true


func rename(train_id: int, new_name: String) -> void:
	var instance := train(train_id)
	if instance.is_empty() or new_name.strip_edges() == "":
		return
	instance["name"] = new_name


# --- consist statistics ---------------------------------------------------

func stock_of(train_id: int) -> Array[String]:
	return _string_list(train(train_id).get("stock", []))


## A consist read back from a save is a plain Array; every consumer expects
## Array[String], so the conversion happens once here at the boundary.
func _string_list(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item in value:
		result.append(String(item))
	return result

func consist_price(stock_ids: Array[String]) -> float:
	var total := 0.0
	for stock_id in stock_ids:
		var def := _registry.stock(stock_id)
		if def != null:
			total += def.price
	return Money.round(total)


## What the purchase form must show before anything is bought.  Every figure is
## produced by the same code that rates a train once it exists, so a yard that
## promises 45 tons and 71 km/h delivers 45 tons and 71 km/h.
func preview_consist(stock_ids: Array[String]) -> Dictionary:
	return {
		"price": consist_price(stock_ids),
		"weight_tons": consist_weight_ids(stock_ids),
		"max_speed_kmh": estimated_max_speed_ids(stock_ids),
		"running_cost_month": consist_running_cost_ids(stock_ids),
		"capacity": capacity_by_cargo_ids(stock_ids),
	}


func consist_weight_ids(stock_ids: Array[String]) -> float:
	var total := 0.0
	for stock_id in stock_ids:
		var def := _registry.stock(stock_id)
		if def != null:
			total += def.weight_tons
	return total


func consist_weight(train_id: int) -> float:
	return consist_weight_ids(stock_of(train_id)) + carried_weight(train_id)


func consist_running_cost_ids(stock_ids: Array[String]) -> float:
	var total := 0.0
	for stock_id in stock_ids:
		var def := _registry.stock(stock_id)
		if def != null:
			total += def.running_cost_month
	return Money.round(total)


func consist_running_cost(train_id: int) -> float:
	return consist_running_cost_ids(stock_of(train_id))


func capacity_by_cargo_ids(stock_ids: Array[String]) -> Dictionary:
	var out := {}
	for stock_id in stock_ids:
		var def := _registry.stock(stock_id)
		if def == null or def.kind != "wagon" or def.cargo == "":
			continue
		out[def.cargo] = float(out.get(def.cargo, 0.0)) + float(def.capacity)
	return out


func capacity_by_cargo(train_id: int) -> Dictionary:
	return capacity_by_cargo_ids(stock_of(train_id))


func capacity_for(train_id: int, cargo_id: String) -> float:
	return float(capacity_by_cargo(train_id).get(cargo_id, 0.0))


func loaded_for(train_id: int, cargo_id: String) -> float:
	var total := 0.0
	for batch in batches(train_id):
		if String(batch["cargo"]) == cargo_id:
			total += float(batch["quantity"])
	return total


func free_space(train_id: int, cargo_id: String) -> float:
	return maxf(0.0, capacity_for(train_id, cargo_id) - loaded_for(train_id, cargo_id))


func carried_units(train_id: int) -> float:
	var total := 0.0
	for batch in batches(train_id):
		total += float(batch["quantity"])
	return total


func carried_weight(train_id: int) -> float:
	var total := 0.0
	for batch in batches(train_id):
		var def := _registry.cargo_def(String(batch["cargo"]))
		if def != null:
			total += float(batch["quantity"]) * def.tonnes_per_unit
	return total


## Estimated maximum speed: the locomotive's own speed, reduced by what it is
## dragging — the number the consist editor shows live.
func estimated_max_speed(train_id: int) -> float:
	var stock_ids := stock_of(train_id)
	if stock_ids.is_empty():
		return 0.0
	var loco := _registry.stock(stock_ids[0])
	if loco == null:
		return 0.0
	return _speed_for(loco, maxf(0.0, consist_weight(train_id) - loco.weight_tons))


## The same rating for a consist that does not exist yet, empty wagons and all:
## what the purchase form promises before the money moves.
func estimated_max_speed_ids(stock_ids: Array[String]) -> float:
	if stock_ids.is_empty():
		return 0.0
	var loco := _registry.stock(stock_ids[0])
	if loco == null:
		return 0.0
	return _speed_for(loco, maxf(0.0, consist_weight_ids(stock_ids) - loco.weight_tons))


func _speed_for(loco: DataRegistry.StockDef, hauled: float) -> float:
	var power := maxf(0.05, loco.power)
	var drag := 1.0 + hauled / ( loco_weight_factor(loco) * power )
	return loco.max_speed_kmh / drag


## How much a locomotive can haul before it starts losing speed.
func loco_weight_factor(loco: DataRegistry.StockDef) -> float:
	return loco.weight_tons * 11.0


func top_speed_tiles_per_tick(train_id: int) -> float:
	return estimated_max_speed(train_id) * KMH_TO_TILE_PER_TICK


# --- routing --------------------------------------------------------------

func set_route(train_id: int, stops: Array[Dictionary]) -> Dictionary:
	var instance := train(train_id)
	if instance.is_empty():
		return {"ok": false, "reason": "Unknown train", "id": 0}
	var result := _routes.set_route(train_id, stops)
	if not bool(result.get("ok", false)):
		return result
	var route_id := int(result["id"])
	instance["route_id"] = route_id
	instance["path"] = _routes.path_of(route_id)
	instance["stop_ticks"] = _routes.stop_ticks_of(route_id)
	instance["progress"] = _clamp_progress(instance)
	_reset_motion(instance)
	train_route_changed.emit(train_id, route_id)
	return result


func clear_route(train_id: int) -> void:
	var instance := train(train_id)
	if instance.is_empty():
		return
	if int(instance["route_id"]) != 0:
		_routes.remove_route(int(instance["route_id"]))
	instance["route_id"] = 0
	instance["path"] = PackedVector2Array()
	instance["stop_ticks"] = PackedFloat64Array()
	instance["state"] = State.IDLE
	_reset_motion(instance)


func route_of(train_id: int) -> int:
	return int(train(train_id).get("route_id", 0))


func state_of(train_id: int) -> int:
	return int(train(train_id).get("state", State.IDLE))


func state_label(train_id: int) -> String:
	match int(train(train_id).get("state", State.IDLE)):
		State.IDLE:
			return "Idle"
		State.LOADING:
			return "Loading"
		State.MOVING:
			return "Moving"
		State.LOST:
			return "No path"
	return "Idle"


## Recompute the cached path.  Called on `track_changed`, never per tick.
## Signal slot: any track edit invalidates every running path.
func _on_track_changed(_tiles: Variant = null) -> void:
	refresh_paths()


func refresh_paths() -> void:
	for train_id in _order:
		var instance: Dictionary = _trains[train_id]
		var route_id := int(instance["route_id"])
		if route_id == 0:
			continue
		if not _routes.is_valid(route_id):
			_routes.recompute_path(route_id)
		if not _routes.is_valid(route_id):
			instance["state"] = State.LOST
			continue
		var previous_length := float(instance["path_length"])
		instance["path"] = _routes.path_of(route_id)
		instance["stop_ticks"] = _routes.stop_ticks_of(route_id)
		if previous_length > 0.0 and float(instance["path"].size()) > 1.0:
			instance["progress"] = _clamp_progress(instance)
		if int(instance["state"]) == State.LOST:
			instance["state"] = State.MOVING


## Where the train is, in tile coordinates and world height, for rendering.
func position_tiles(train_id: int) -> Vector2:
	var instance := train(train_id)
	if instance.is_empty():
		return Vector2.ZERO
	var path: PackedVector2Array = instance["path"]
	if path.size() < 2:
		var station_tile := _stations.rail_access_tile(int(instance["station"]))
		return Vector2(station_tile)
	return _point_at(path, float(instance["progress"]))


func heading(train_id: int) -> float:
	var instance := train(train_id)
	if instance.is_empty():
		return 0.0
	var path: PackedVector2Array = instance["path"]
	if path.size() < 2:
		return 0.0
	var ahead := _point_at(path, float(instance["progress"]) + 0.5)
	var behind := _point_at(path, float(instance["progress"]) - 0.5)
	var delta := ahead - behind
	if delta.length_squared() < 0.0001:
		return float(instance.get("heading", 0.0))
	return rad_to_deg(atan2(-delta.x, delta.y))


func speed_tiles_per_tick(train_id: int) -> float:
	return float(train(train_id).get("speed", 0.0))


## The speed the player reads, in the unit the purchase form quoted it in.  The
## conversion lives here so the panel and the movement model can never disagree
## about what the same consist is doing.
func speed_kmh(train_id: int) -> float:
	if KMH_TO_TILE_PER_TICK <= 0.0:
		return 0.0
	return speed_tiles_per_tick(train_id) / KMH_TO_TILE_PER_TICK


func current_station(train_id: int) -> int:
	var instance := train(train_id)
	if int(instance.get("state", State.IDLE)) == State.LOADING:
		return int(instance.get("at_station", 0))
	return 0


func next_station(train_id: int) -> int:
	var instance := train(train_id)
	var stop_list := _routes.stops(int(instance.get("route_id", 0)))
	if stop_list.is_empty():
		return 0
	var index := (int(instance.get("stop_index", 0)) + 1) % stop_list.size()
	return int(stop_list[index]["station_id"])


func progress_fraction(train_id: int) -> float:
	var instance := train(train_id)
	var total := float(instance.get("path_length", 0.0))
	if total <= 0.0:
		return 0.0
	return clampf(float(instance["progress"]) / total, 0.0, 1.0)


func destination_label(train_id: int) -> String:
	var instance := train(train_id)
	if int(instance.get("route_id", 0)) == 0:
		return "No route"
	var stop_list := _routes.stops(int(instance["route_id"]))
	if stop_list.is_empty():
		return "No route"
	var index := (int(instance.get("stop_index", 0)) + 1) % stop_list.size()
	return _stations.name_of(int(stop_list[index]["station_id"]))


func trains() -> Array[int]:
	return _order


func count() -> int:
	return _order.size()


func train(train_id: int = 0) -> Dictionary:
	if train_id == 0:
		return {}
	return _trains.get(train_id, {})


func name_of(train_id: int) -> String:
	return String(train(train_id).get("name", "Train"))


## The cargo riding right now.  Assembled as a typed array: `Array(untyped)`
## stays untyped, and callers bind the result to `Array[Dictionary]`.
func batches(train_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for batch in train(train_id).get("cargo", []):
		out.append(batch)
	return out


func home_station(train_id: int) -> int:
	return int(train(train_id).get("station", 0))


func total_revenue(train_id: int) -> float:
	return float(train(train_id).get("revenue", 0.0))


## What this train earned during the running calendar month.  The drawer's
## monthly profit is this less `consist_running_cost`, so both halves of the
## figure come from the same places the ledger does.
func monthly_revenue_of(train_id: int) -> float:
	return Money.round(float(train(train_id).get("monthly_revenue", 0.0)))


func monthly_profit(train_id: int) -> float:
	return Money.round(monthly_revenue_of(train_id) - consist_running_cost(train_id))


## Called by the session on the month boundary, beside the stations' own closing.
func close_month() -> void:
	for train_id in _order:
		_trains[train_id]["monthly_revenue"] = 0.0


# --- simulation -----------------------------------------------------------

## One simulation tick for every train.  Movement is a scalar advance along a
## cached path: no physics, no pathfinding, no allocation per tick.
func advance_tick() -> void:
	for train_id in _order:
		_advance_train(train_id)


func _advance_train(train_id: int) -> void:
	var instance: Dictionary = _trains[train_id]
	match int(instance["state"]):
		State.IDLE:
			var route_id := int(instance["route_id"])
			if route_id != 0 and _routes.is_valid(route_id):
				var stops := _routes.stops(route_id)
				if stops.is_empty():
					instance["state"] = State.LOST
				else:
					# The trip begins at stop 0: progress, servicing index and
					# the platform all agree before any cargo moves.
					instance["stop_index"] = 0
					instance["progress"] = 0.0
					_begin_loading(train_id, int(stops[0]["station_id"]))
		State.LOST:
			if _routes.is_valid(int(instance["route_id"])):
				refresh_paths()
		State.LOADING:
			_tick_loading(train_id)
		State.MOVING:
			_tick_moving(train_id)


func _tick_loading(train_id: int) -> void:
	var instance: Dictionary = _trains[train_id]
	var station_id := int(instance["at_station"])
	if instance["loading_left"] > 0.0:
		instance["loading_left"] = float(instance["loading_left"]) - LOAD_PER_TICK
		_transfer_cargo(train_id, station_id, LOAD_PER_TICK)
		instance["dwell"] = float(instance["dwell"]) - 1.0
		if float(instance["dwell"]) <= 0.0:
			instance["loading_left"] = 0.0
	else:
		_transfer_cargo(train_id, station_id, 0.0)
		instance["dwell"] = float(instance["dwell"]) - 1.0
	if float(instance["dwell"]) > 0.0:
		return
	_finish_loading(train_id, station_id)


func _transfer_cargo(train_id: int, station_id: int, rate: float) -> void:
	if rate <= 0.0:
		return
	var instance: Dictionary = _trains[train_id]
	var stop_list := _routes.stops(int(instance["route_id"]))
	var index := int(instance["stop_index"])
	if index >= stop_list.size():
		return
	var stop: Dictionary = stop_list[index]
	var loads: Array = stop.get("load", [])
	var unloads: Array = stop.get("unload", [])
	# Unload first: it frees space for what this station wants to send.
	for cargo_id in unloads:
		_unload(train_id, station_id, String(cargo_id))
	for cargo_id in loads:
		_load(train_id, station_id, String(cargo_id), rate)


func _finish_loading(train_id: int, station_id: int) -> void:
	var instance: Dictionary = _trains[train_id]
	instance["state"] = State.MOVING
	instance["speed"] = 0.0
	# Re-read the ceiling on every departure: the consist that leaves a platform is
	# heavier than the one that arrived, and a loaded train that kept the empty
	# consist's ceiling would run past the speed it is rated at on the purchase
	# form — which would make the estimate a decoration rather than a limit.
	_refresh_rating(train_id)
	train_departed.emit(train_id, station_id)


func _tick_moving(train_id: int) -> void:
	var instance: Dictionary = _trains[train_id]
	var path: PackedVector2Array = instance["path"]
	var total := float(instance["path_length"])
	if path.size() < 2 or total <= 0.0:
		refresh_paths()
		if not _routes.is_valid(int(instance["route_id"])):
			instance["state"] = State.LOST
			return
		path = instance["path"]
		total = float(instance["path_length"])
	var step := _accelerate(train_id)
	if step <= 0.0:
		return
	var from := float(instance["progress"])
	var to := from + step
	_record_travel(train_id, step)
	var stop_ticks: PackedFloat64Array = instance["stop_ticks"]
	for index in stop_ticks.size():
		var marker := float(stop_ticks[index])
		if marker > from + 0.000001 and marker <= to + 0.000001:
			var stop_list := _routes.stops(int(instance["route_id"]))
			if stop_list.is_empty():
				instance["state"] = State.LOST
				return
			# The last marker closes the loop back to stop 0, so markers wrap
			# around the stop list rather than running past its end.
			var stop_at := index % stop_list.size()
			instance["progress"] = fmod(marker, total)
			instance["speed"] = 0.0
			instance["stop_index"] = stop_at
			_arrive(train_id, int(stop_list[stop_at]["station_id"]))
			return
	if to >= total - 0.000001:
		to = fmod(to, total)
		if to <= 0.000001:
			to = 0.0
	instance["progress"] = to


func _accelerate(train_id: int) -> float:
	var instance: Dictionary = _trains[train_id]
	var top := float(instance["max_speed"]) * _grade_factor(train_id)
	var acceleration := _registry.train_setting("acceleration_per_tick", 0.06)
	var braking := _registry.train_setting("braking_per_tick", 0.12)
	var limit := top
	var stop_ticks: PackedFloat64Array = instance["stop_ticks"]
	var progress := float(instance["progress"])
	var remaining_to_stop := float(instance["path_length"]) - progress
	for marker in stop_ticks:
		if float(marker) > progress + 0.000001:
			remaining_to_stop = float(marker) - progress
			break
	var braking_distance := (float(instance["speed"]) * float(instance["speed"])) / (2.0 * braking)
	if remaining_to_stop <= braking_distance:
		limit = maxf(0.02, float(instance["speed"]) - braking)
	instance["speed"] = clampf(float(instance["speed"]) + signf(top - float(instance["speed"])) * acceleration,
		0.0, maxf(0.0, minf(top, limit if limit < float(instance["speed"]) else top)))
	return float(instance["speed"])


## Steeper grades slow a train; a descent lets it run faster, up to the cap.
func _tile_at(path: PackedVector2Array, distance: float) -> Vector2i:
	var point := _point_at(path, distance)
	return Vector2i(roundi(point.x), roundi(point.y))


## The ceiling the consist is under right now, as a multiple of its rated speed:
## below 1 climbing, above 1 descending.  Read-only for the diagnostics overlay and
## the tests — nobody outside the tick loop may write it.
func grade_speed_factor(train_id: int) -> float:
	if not _trains.has(train_id):
		return 1.0
	return _grade_factor(train_id)


func _grade_factor(train_id: int) -> float:
	var instance: Dictionary = _trains[train_id]
	var path: PackedVector2Array = instance["path"]
	if path.size() < 2:
		return 1.0
	var here := _tile_at(path, float(instance["progress"]))
	var ahead := _tile_at(path, minf(float(instance["path_length"]), float(instance["progress"]) + 1.0))
	if not _world.in_bounds(here) or not _world.in_bounds(ahead):
		return 1.0
	var delta := _world.height_at(ahead) - _world.height_at(here)
	if delta == 0:
		return 1.0
	var per_step := _registry.train_setting("grade_speed_factor_per_step", 0.72)
	if delta > 0:
		return clampf(pow(per_step, float(delta)), 0.25, 1.0)
	return clampf(1.0 / pow(per_step, float(-delta)), 1.0, 1.35)


func _arrive(train_id: int, station_id: int) -> void:
	var instance: Dictionary = _trains[train_id]
	instance["at_station"] = station_id
	if int(instance["stop_index"]) == 0:
		# Coming back to the first stop is what a completed turn means to the
		# player, so the counter follows that definition.
		instance["trip_count"] = int(instance["trip_count"]) + 1
	_begin_loading(train_id, station_id)
	train_arrived.emit(train_id, station_id)


func _begin_loading(train_id: int, station_id: int) -> void:
	var instance: Dictionary = _trains[train_id]
	if station_id == 0:
		instance["state"] = State.LOST
		return
	# Dwell is sized by the work standing on this platform — what can be lifted
	# on and what can be dropped off — not by what is already aboard.  A train
	# that arrives empty would otherwise leave after a token pause, half empty,
	# while the station is full.
	var to_load := _work_to_load(train_id, station_id)
	var to_drop := _work_to_unload(train_id, station_id)
	var min_dwell := _registry.train_setting("min_dwell_ticks", 6.0)
	var per_unit := _registry.train_setting("dwell_ticks_per_unit", 1.2)
	var max_dwell := _registry.train_setting("max_dwell_ticks", 120.0)
	var work := to_load + to_drop
	var dwell := clampf(min_dwell + per_unit * work, min_dwell, max_dwell)
	instance["state"] = State.LOADING
	instance["dwell"] = dwell
	instance["loading_left"] = work + min_dwell
	instance["at_station"] = station_id


## Units this station could hand the train, limited by what the train can carry.
func _work_to_load(train_id: int, station_id: int) -> float:
	var total := 0.0
	for cargo_id in _planned_cargos(train_id, station_id, "load"):
		total += minf(_stations.inventory_of(station_id, cargo_id), free_space(train_id, cargo_id))
	return total


## Units aboard that this station can absorb.
func _work_to_unload(train_id: int, station_id: int) -> float:
	var total := 0.0
	for cargo_id in _planned_cargos(train_id, station_id, "unload"):
		total += minf(loaded_for(train_id, cargo_id), _cargo.sink_demand(station_id, cargo_id))
	return total


## The cargos a stop is scheduled to handle — from the stop's own plan.
func _planned_cargos(train_id: int, station_id: int, field: String) -> Array[String]:
	var result: Array[String] = []
	var instance := train(train_id)
	var stop_list := _routes.stops(int(instance.get("route_id", 0)))
	for stop in stop_list:
		if int(stop["station_id"]) != station_id:
			continue
		for cargo_id in Array(stop.get(field, [])):
			var id := String(cargo_id)
			if not result.has(id):
				result.append(id)
	return result



# --- cargo handling -------------------------------------------------------

func _load(train_id: int, station_id: int, cargo_id: String, rate: float) -> void:
	var room := free_space(train_id, cargo_id)
	if room <= 0.0:
		return
	var wanted := minf(room, maxf(1.0, rate))
	var taken := _stations.take_cargo(station_id, cargo_id, wanted)
	if taken <= 0.0:
		return
	_add_batch(train_id, cargo_id, taken, station_id)


func _unload(train_id: int, station_id: int, cargo_id: String) -> void:
	var instance: Dictionary = _trains[train_id]
	var batches: Array = instance["cargo"]
	var index := 0
	while index < batches.size():
		var batch: Dictionary = batches[index]
		if String(batch["cargo"]) != cargo_id:
			index += 1
			continue
		var origin_id := int(batch["origin"])
		if origin_id == station_id:
			index += 1
			continue
		var distance := float(batch["travelled"])
		if distance <= 0.0:
			distance = 1.0
		var age_days := _clock.days_elapsed() - float(batch["created_day"]) \
			+ float(_clock.tick_count - int(batch["created_tick"])) / float(maxi(1, _clock.ticks_per_day))
		var quantity := float(batch["quantity"])
		# Unload only what the sink can actually take.  Delivering more would
		# either be refused outright — which is fine, the batch stays aboard —
		# or accepted in part, and a partially delivered batch would lose the
		# remainder that the player can still see on the consist.
		var wanted := minf(quantity, maxf(0.0, _cargo.sink_demand(station_id, cargo_id)))
		if wanted <= 0.0:
			return
		var outcome := _cargo.deliver(station_id, cargo_id, wanted, distance, origin_id, maxf(0.0, age_days))
		var delivered := float(outcome.get("delivered", 0.0))
		if delivered <= 0.0:
			return
		var earned := float(outcome.get("revenue", 0.0))
		instance["revenue"] = float(instance["revenue"]) + earned
		instance["monthly_revenue"] = float(instance["monthly_revenue"]) + earned
		train_revenue.emit(train_id, station_id, cargo_id, earned)
		batch["quantity"] = quantity - delivered
		if float(batch["quantity"]) <= 0.001:
			batches.remove_at(index)
			instance["cargo"] = batches
			return
		# The train still carries part of this batch; the next stop gets the
		# chance to try again rather than this one burning the rest.
		instance["cargo"] = batches
		return
	instance["cargo"] = batches


func _add_batch(train_id: int, cargo_id: String, quantity: float, origin_station_id: int) -> void:
	var instance: Dictionary = _trains[train_id]
	var batches: Array = instance["cargo"]
	for batch in batches:
		if String(batch["cargo"]) == cargo_id and int(batch["origin"]) == origin_station_id:
			batch["quantity"] = float(batch["quantity"]) + quantity
			return
	batches.append({
		"cargo": cargo_id,
		"quantity": quantity,
		"origin": origin_station_id,
		"created_tick": _clock.tick_count,
		"created_day": _clock.days_elapsed(),
		"travelled": 0.0,
	})
	instance["cargo"] = batches


## Every onboard unit has travelled this far, so revenue can pay for the haul
## it actually made rather than the straight-line guess.
func _record_travel(train_id: int, step: float) -> void:
	for batch in _trains[train_id]["cargo"]:
		batch["travelled"] = float(batch["travelled"]) + step


# --- helpers --------------------------------------------------------------

func _new_train(train_id: int, station_id: int, stock_ids: Array[String], transaction_id: int) -> Dictionary:
	var path := PackedVector2Array()
	return {
		"id": train_id,
		"name": "Train %d" % _next_train_number,
		"station": station_id,
		"at_station": station_id,
		"stock": stock_ids,
		"route_id": 0,
		"state": State.IDLE,
		"path": path,
		"stop_ticks": PackedFloat64Array(),
		"progress": 0.0,
		"speed": 0.0,
		"max_speed": 0.0,
		"heading": 0.0,
		"stop_index": 0,
		"dwell": 0.0,
		"loading_left": 0.0,
		"cargo": [] as Array[Dictionary],
		"revenue": 0.0,
		"monthly_revenue": 0.0,
		"trip_count": 0,
		"purchase_transaction": transaction_id,
		"wagon_transactions": [] as Array,
		"path_length": 0.0,
	}


## Re-read the consist's speed ceiling: the estimate already accounts for the
## wagons and the cargo standing in them, so the ceiling has to move every time
## either of them does.
func _refresh_rating(train_id: int) -> void:
	var instance := train(train_id)
	if instance.is_empty():
		return
	instance["max_speed"] = top_speed_tiles_per_tick(train_id)


func _reset_motion(instance: Dictionary) -> void:
	var path: PackedVector2Array = instance["path"]
	var length := 0.0
	for index in range(1, path.size()):
		length += path[index].distance_to(path[index - 1])
	instance["path_length"] = length
	instance["speed"] = 0.0
	instance["max_speed"] = top_speed_tiles_per_tick(int(instance["id"]))


func _clamp_progress(instance: Dictionary) -> float:
	var length := 0.0
	var path: PackedVector2Array = instance["path"]
	for index in range(1, path.size()):
		length += path[index].distance_to(path[index - 1])
	instance["path_length"] = length
	if length <= 0.0:
		return 0.0
	return fmod(float(instance.get("progress", 0.0)), length)


func _point_at(path: PackedVector2Array, distance: float) -> Vector2:
	var total := 0.0
	for index in range(1, path.size()):
		total += path[index].distance_to(path[index - 1])
	var wanted := fmod(maxf(0.0, distance), maxf(total, 0.000001))
	if total <= 0.0:
		return path[0] if path.size() > 0 else Vector2.ZERO
	var walked := 0.0
	for index in range(1, path.size()):
		var segment := path[index].distance_to(path[index - 1])
		if walked + segment >= wanted:
			var t := 0.0 if segment <= 0.0 else (wanted - walked) / segment
			return path[index - 1].lerp(path[index], t)
		walked += segment
	return path[path.size() - 1]


func _wagon_summary(wagon_ids: Array[String]) -> String:
	var counts := {}
	for wagon_id in wagon_ids:
		var def := _registry.stock(wagon_id)
		var label := def.display_name if def != null else wagon_id
		counts[label] = int(counts.get(label, 0)) + 1
	var parts: PackedStringArray = []
	for label in counts.keys():
		parts.append("%s ×%d" % [label, counts[label]])
	return ", ".join(parts) if not parts.is_empty() else "no wagons"


func to_dict() -> Dictionary:
	var entries: Array = []
	for train_id in _order:
		var instance: Dictionary = _trains[train_id]
		var cargo_entries: Array = []
		for batch in instance["cargo"]:
			cargo_entries.append(batch.duplicate())
		var stock_copy: Array = []
		for stock_id in _string_list(instance["stock"]):
			stock_copy.append(stock_id)
		entries.append({
			"id": train_id,
			"name": instance["name"],
			"station": instance["station"],
			"at_station": instance["at_station"],
			"stock": stock_copy,
			"state": instance["state"],
			"progress": instance["progress"],
			"stop_index": instance["stop_index"],
			"dwell": instance["dwell"],
			"revenue": instance["revenue"],
			"monthly_revenue": instance["monthly_revenue"],
			"trip_count": instance["trip_count"],
			"cargo": cargo_entries,
		})
	return {"trains": entries, "next_number": _next_train_number}


func from_dict(data: Dictionary) -> void:
	_trains.clear()
	_order.clear()
	for entry in data.get("trains", []):
		var train_id := int(entry["id"])
		var instance := _new_train(train_id, int(entry["station"]),
			_string_list(entry.get("stock", [])), 0)
		instance["name"] = String(entry.get("name", "Train"))
		instance["at_station"] = int(entry.get("at_station", entry.get("station", 0)))
		instance["state"] = int(entry.get("state", State.IDLE))
		instance["progress"] = float(entry.get("progress", 0.0))
		instance["stop_index"] = int(entry.get("stop_index", 0))
		instance["dwell"] = float(entry.get("dwell", 0.0))
		instance["revenue"] = float(entry.get("revenue", 0.0))
		instance["monthly_revenue"] = float(entry.get("monthly_revenue", 0.0))
		instance["trip_count"] = int(entry.get("trip_count", 0))
		var batches: Array[Dictionary] = []
		for batch in entry.get("cargo", []):
			batches.append(Dictionary(batch))
		instance["cargo"] = batches
		_trains[train_id] = instance
		_order.append(train_id)
		if _ids != null:
			_ids.adopt_highest(train_id)
	_next_train_number = int(data.get("next_number", _order.size() + 1))
	for train_id in _order:
		var instance: Dictionary = _trains[train_id]
		var route_id := _routes.route_for_train(train_id)
		instance["route_id"] = route_id
		if route_id != 0:
			instance["path"] = _routes.path_of(route_id)
			instance["stop_ticks"] = _routes.stop_ticks_of(route_id)
		_reset_motion(instance)
