class_name CargoService
extends RefCounted

## Turns sources into cargo that stations can offer, and turns deliveries into
## ledger revenue.
##
## Two invariants live here:
##   * a source's cargo is *allocated*, never duplicated — the sum distributed
##     to covering stations can never exceed what the source produced, however
##     many stations cover it;
##   * revenue is computed per batch and always leaves through EconomyService.

signal cargo_generated(source_kind: String, source_id: int, cargo_id: String, amount: float)
signal cargo_allocated(station_id: int, cargo_id: String, amount: float)
signal cargo_delivered(station_id: int, cargo_id: String, quantity: float, revenue: float)
signal cargo_refused(station_id: int, cargo_id: String, reason: String)

const SOURCE_TOWN := "town"
const SOURCE_INDUSTRY := "industry"

## Inverse-distance weighting: a station right next to a mine gets clearly more
## of its output than one at the far edge of the catchment, but neither is
## starved to zero.
const DISTANCE_WEIGHT_POWER := 1.6

var _stations: StationService
var _towns: TownService
var _industries: IndustryService
var _defs: DataRegistry
var _clock: SimulationClock
var _economy: EconomyService
var _fractions := {}
var _delivered_total := 0.0
var _revenue_total := 0.0
var _delivered_by_cargo := {}


func configure(stations: StationService, towns: TownService, industries: IndustryService,
		registry: DataRegistry, clock: SimulationClock, economy: EconomyService) -> void:
	_stations = stations
	_towns = towns
	_industries = industries
	_defs = registry
	_clock = clock
	_economy = economy


## Called on `month_changed`: produce, then allocate.
func advance_month() -> void:
	_industries.advance_month()
	allocate_sources()


## Every source hands its cargo to the stations that cover it, split by
## distance.  Called again whenever a station is built or removed.
func allocate_sources() -> void:
	for entry in collect_sources():
		_distribute(entry)


## All cargo sources, town and industry, in one shape.
func collect_sources() -> Array[Dictionary]:
	var sources: Array[Dictionary] = []
	for town_id in _towns.towns():
		var generation := _towns.generation_map(town_id)
		for cargo_id in generation.keys():
			sources.append({
				"kind": SOURCE_TOWN,
				"id": town_id,
				"name": _towns.name_of(town_id),
				"tile": _towns.tile_of(town_id),
				"cargo": cargo_id,
				"rate": float(generation[cargo_id]),
			})
	for industry_id in _industries.industries():
		if not _industries.is_producer(industry_id):
			continue
		for flow in _industry_flows(industry_id, "produces"):
			var cargo_id := String(flow["cargo"])
			sources.append({
				"kind": SOURCE_INDUSTRY,
				"id": industry_id,
				"name": _industries.name_of(industry_id),
				"tile": _industries.tile_of(industry_id),
				"cargo": cargo_id,
				"rate": float(flow["rate_per_month"]),
			})
	return sources


## All cargo sinks, industry and town, in the same shape as `collect_sources`.
## A power plant produces nothing, so it is invisible to the source list — and
## a station that cannot see a sink has nothing to deliver.
func collect_sinks() -> Array[Dictionary]:
	var sinks: Array[Dictionary] = []
	for town_id in _towns.towns():
		sinks.append({
			"kind": SOURCE_TOWN,
			"id": town_id,
			"name": _towns.name_of(town_id),
			"tile": _towns.tile_of(town_id),
			"cargo": "passengers",
			"cargos": ["passengers", "mail"] as Array[String],
			"rate": 0.0,
		})
	for industry_id in _industries.industries():
		if not _industries.is_consumer(industry_id):
			continue
		var accepted: Array[String] = []
		for flow in _industry_flows(industry_id, "accepts"):
			accepted.append(String(flow["cargo"]))
		if accepted.is_empty():
			continue
		sinks.append({
			"kind": SOURCE_INDUSTRY,
			"id": industry_id,
			"name": _industries.name_of(industry_id),
			"tile": _industries.tile_of(industry_id),
			"cargo": accepted[0],
			"cargos": accepted,
			"rate": 0.0,
		})
	return sinks


## Units of `cargo_id` this station can pick up right now, as the UI shows it.
func available_at(station_id: int, cargo_id: String) -> float:
	return _stations.inventory_of(station_id, cargo_id)


func available_summary(station_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cargo_id in _stations.inventory_by_cargo(station_id).keys():
		var amount := available_at(station_id, cargo_id)
		if amount <= 0.0:
			continue
		out.append({
			"cargo": cargo_id,
			"label": _defs.cargo_display(cargo_id),
			"amount": amount,
		})
	out.sort_custom(func(a, b): return String(a["cargo"]) < String(b["cargo"]))
	return out


## Sources whose cargo this station could ever offer — used by the catchment
## overlay ("what will this station serve?" before it is built).
func prospective_sources(station_id: int) -> Array[Dictionary]:
	var covered := _stations.covered_sources(station_id)
	var out: Array[Dictionary] = []
	for entry in covered:
		if String(entry["kind"]) == SOURCE_TOWN:
			var generation := _towns.generation_map(int(entry["id"]))
			for cargo_id in generation.keys():
				out.append({
					"cargo": cargo_id,
					"label": _defs.cargo_display(cargo_id),
					"kind": entry["kind"],
					"name": entry["name"],
					"amount": float(generation[cargo_id]),
				})
		else:
			for flow in _industry_flows(int(entry["id"]), "produces"):
				out.append({
					"cargo": String(flow["cargo"]),
					"label": _defs.cargo_display(String(flow["cargo"])),
					"kind": entry["kind"],
					"name": entry["name"],
					"amount": float(flow["rate_per_month"]),
				})
	return out


# --- sinks ----------------------------------------------------------------

## Can this station accept `cargo_id`?  A station accepts a cargo when something
## in its catchment wants it: a town for passengers/mail, a consumer industry
## for its accepted commodities.
func accepts(station_id: int, cargo_id: String) -> bool:
	return acceptance_reason(station_id, cargo_id) == ""


func acceptance_reason(station_id: int, cargo_id: String) -> String:
	for entry in _sink_entries(station_id, cargo_id):
		if entry["kind"] == SOURCE_INDUSTRY:
			var remaining := _industry_room(int(entry["id"]), cargo_id)
			if remaining > 0.0:
				return ""
			return "%s cannot take more %s this month" % [entry["name"], _defs.cargo_display(cargo_id)]
		return ""
	return "%s has no use for %s nearby" % [_stations.name_of(station_id), _defs.cargo_display(cargo_id)]


func sink_demand(station_id: int, cargo_id: String) -> float:
	var total := 0.0
	for entry in _sink_entries(station_id, cargo_id):
		if entry["kind"] == SOURCE_INDUSTRY:
			total += _industry_room(int(entry["id"]), cargo_id)
		else:
			total += 1e9
	return minf(total, 1e9)


## Hand a batch to a station's sinks.  Returns what the sink actually took and
## what it paid — the two are different numbers whenever the sink was nearly
## full, and a caller that assumes they match will either lose cargo or book
## tonnage as income.
func deliver(station_id: int, cargo_id: String, quantity: float, distance_tiles: float,
		origin_station_id: int, age_days: float) -> Dictionary:
	if quantity <= 0.0:
		return {"ok": false, "delivered": 0.0, "revenue": 0.0, "reason": "Nothing to deliver"}
	var reason := acceptance_reason(station_id, cargo_id)
	if reason != "":
		cargo_refused.emit(station_id, cargo_id, reason)
		return {"ok": false, "delivered": 0.0, "revenue": 0.0, "reason": reason}
	var room := sink_demand(station_id, cargo_id)
	var accepted := minf(quantity, room)
	if accepted <= 0.0:
		cargo_refused.emit(station_id, cargo_id, "sink is full")
		return {"ok": false, "delivered": 0.0, "revenue": 0.0, "reason": "sink is full"}
	for entry in _sink_entries(station_id, cargo_id):
		if entry["kind"] == SOURCE_INDUSTRY:
			_industries.consume(int(entry["id"]), cargo_id, minf(accepted, _industry_room(int(entry["id"]), cargo_id)))
		else:
			break
	var revenue := _revenue_for(cargo_id, accepted, distance_tiles, age_days)
	var origin_name := _stations.name_of(origin_station_id) if _stations.has_station(origin_station_id) else "Unknown"
	_stations.add_revenue(station_id, revenue)
	_economy.earn(revenue, EconomyService.CATEGORY_REVENUE, "Delivery of %s %s to %s" % [
		_trunc(accepted), _defs.cargo_display(cargo_id), _stations.name_of(station_id)])
	_delivered_total += accepted
	_revenue_total += revenue
	_delivered_by_cargo[cargo_id] = float(_delivered_by_cargo.get(cargo_id, 0.0)) + accepted
	var instance: Dictionary = _stations.station(station_id)
	instance["monthly_delivered"] = int(instance.get("monthly_delivered", 0)) + int(accepted)
	cargo_delivered.emit(station_id, cargo_id, accepted, revenue)
	_deliver_log.append({
		"cargo": cargo_id,
		"quantity": accepted,
		"origin": origin_station_id,
		"origin_name": origin_name,
		"destination": station_id,
		"distance": distance_tiles,
		"age_days": age_days,
		"revenue": revenue,
	})
	return {"ok": true, "delivered": accepted, "revenue": revenue, "reason": ""}


func delivery_count() -> int:
	return _deliver_log.size()


func delivered_total() -> float:
	return _delivered_total


func revenue_total() -> float:
	return _revenue_total


func delivered_by_cargo() -> Dictionary:
	return _delivered_by_cargo


func deliveries() -> Array[Dictionary]:
	return _deliver_log


## revenue = quantity × base_rate × distance × quality, all coefficients in data.
func _revenue_for(cargo_id: String, quantity: float, distance_tiles: float, age_days: float) -> float:
	var def := _defs.cargo_def(cargo_id)
	if def == null:
		return 0.0
	return quantity * def.base_rate * maxf(0.0, distance_tiles) * quality(cargo_id, age_days)


## 1.0 when fresh; falls with age for time-sensitive cargo, never below floor.
func quality(cargo_id: String, age_days: float) -> float:
	var def := _defs.cargo_def(cargo_id)
	if def == null:
		return 1.0
	if def.time_sensitivity <= 0.0:
		return 1.0
	return clampf(1.0 - def.time_sensitivity * maxf(0.0, age_days), def.quality_floor, 1.0)


# --- internals ------------------------------------------------------------

var _deliver_log: Array[Dictionary] = []


## Split one source's monthly output across the stations covering it.
func _distribute(source: Dictionary) -> void:
	var station_ids := _stations.stations_covering(source)
	if station_ids.is_empty():
		return
	var cargo_id := String(source["cargo"])
	var key := "%s:%d:%s" % [source["kind"], int(source["id"]), cargo_id]
	var owed: float
	if String(source["kind"]) == SOURCE_INDUSTRY:
		# The industry's own storage is the buffer; allocate what it can spare.
		var spare := _industries.inventory_of(int(source["id"]), cargo_id)
		if spare <= 0.0:
			return
		owed = spare
		_industries.withdraw(int(source["id"]), cargo_id, owed)
	else:
		var rate := float(source["rate"])
		var carried := float(_fractions.get(key, 0.0))
		var accumulated := rate + carried
		owed = floorf(accumulated)
		_fractions[key] = accumulated - owed
		if owed <= 0.0:
			return
	var placed := _allocate_by_distance(station_ids, source, owed)
	var remainder := owed - placed
	if String(source["kind"]) == SOURCE_INDUSTRY and remainder > 0.0:
		# Nothing could take it — leave it in the industry, do not destroy it.
		_industries.deposit(int(source["id"]), cargo_id, remainder)
	elif String(source["kind"]) == SOURCE_TOWN and remainder > 0.0:
		push_warning("unplaced source cargo %s" % key)


## Weight each station by 1/distance, then give it its share of `amount`.
## Shares are floor()'d and the remainder handed to the nearest stations, so
## Σ placed ≤ amount always: allocation cannot invent cargo.
func _allocate_by_distance(station_ids: Array[int], source: Dictionary, amount: float) -> float:
	if station_ids.is_empty() or amount <= 0.0:
		return 0.0
	var weights: Array[Dictionary] = []
	var total_weight := 0.0
	for station_id in station_ids:
		var distance: float = WorldCoords.distance_tiles(source["tile"], _stations.tile_of(station_id))
		var weight := 1.0 / pow(maxf(distance, 0.5), DISTANCE_WEIGHT_POWER)
		total_weight += weight
		weights.append({"id": station_id, "weight": weight})
	if total_weight <= 0.0:
		return 0.0
	weights.sort_custom(func(a, b): return float(a["weight"]) > float(b["weight"]))
	var assigned := 0.0
	var handed: Array[Dictionary] = []
	for entry in weights:
		var share := floorf(amount * float(entry["weight"]) / total_weight)
		if share > 0.0:
			handed.append({"id": entry["id"], "share": share})
		assigned += share
	# Distribute the indivisible remainder nearest-first, one unit at a time.
	var remainder := int(roundf(amount - assigned))
	var pass_index := 0
	while remainder > 0 and pass_index < weights.size() * 64:
		var entry: Dictionary = weights[pass_index % weights.size()]
		var found := false
		for item in handed:
			if int(item["id"]) == int(entry["id"]):
				item["share"] = float(item["share"]) + 1.0
				found = true
				break
		if not found:
			handed.append({"id": entry["id"], "share": 1.0})
		remainder -= 1
		pass_index += 1
	var placed := 0.0
	for item in handed:
		var station_id := int(item["id"])
		var given := _stations.add_cargo(station_id, String(source["cargo"]), float(item["share"]))
		if given > 0.0:
			placed += given
			cargo_allocated.emit(station_id, String(source["cargo"]), given)
	return placed


func _sink_entries(station_id: int, cargo_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _stations.covered_sinks(station_id):
		if String(entry["kind"]) == SOURCE_INDUSTRY:
			if _industries.accepts(int(entry["id"]), cargo_id):
				out.append(entry)
		elif _town_wants(String(entry["kind"]), cargo_id):
			out.append(entry)
	return out


func _town_wants(kind: String, cargo_id: String) -> bool:
	return kind == SOURCE_TOWN and (cargo_id == "passengers" or cargo_id == "mail")


func _industry_room(industry_id: int, cargo_id: String) -> float:
	for flow in _industry_flows(industry_id, "accepts"):
		if String(flow["cargo"]) == cargo_id:
			var capacity := float(flow["capacity_per_month"])
			return maxf(0.0, capacity - _industries.received_this_month(industry_id, cargo_id))
	return 0.0


func _industry_flows(industry_id: int, kind: String) -> Array[Dictionary]:
	var def := _industries.def_of(industry_id)
	if def == null:
		return []
	return def.produces if kind == "produces" else def.accepts


func _trunc(amount: float) -> String:
	return "%d" % int(roundf(amount))


func to_dict() -> Dictionary:
	var deliveries: Array = []
	for entry in _deliver_log.slice(maxi(0, _deliver_log.size() - 400)):
		deliveries.append(entry.duplicate())
	return {
		"fractions": _fractions.duplicate(),
		"delivered_total": _delivered_total,
		"revenue_total": _revenue_total,
		"delivered_by_cargo": _delivered_by_cargo.duplicate(),
		"deliveries": deliveries,
	}


func from_dict(data: Dictionary) -> void:
	_fractions = Dictionary(data.get("fractions", {}))
	_delivered_total = float(data.get("delivered_total", 0.0))
	_revenue_total = float(data.get("revenue_total", 0.0))
	_delivered_by_cargo = Dictionary(data.get("delivered_by_cargo", {}))
	_deliver_log.clear()
	for entry in data.get("deliveries", []):
		_deliver_log.append(Dictionary(entry))
