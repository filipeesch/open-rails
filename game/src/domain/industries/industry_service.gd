class_name IndustryService
extends RefCounted

## Producers and consumers, driven entirely by their definition lists.
##
## There is no CoalMine class and no PowerPlant class.  A definition declares
## `produces` and `accepts` flows and this service steps them, which is what
## lets an iron + coal → steel mill exist later without touching transport.

signal industry_added(industry_id: int)
signal industry_produced(industry_id: int, cargo_id: String, quantity: float)
signal industry_storage_full(industry_id: int, cargo_id: String)
signal industry_received(industry_id: int, cargo_id: String, quantity: float)

var _industries := {}
var _order: Array[int] = []
var _defs: DataRegistry
var _ids: IdFactory


func configure(registry: DataRegistry, ids: IdFactory) -> void:
	_defs = registry
	_ids = ids


func add(definition_id: String, tile: Vector2i, label: String, stable_id: int) -> int:
	var def: DataRegistry.IndustryDef = _defs.industries.get(definition_id)
	if def == null:
		return 0
	var instance := {
		"id": stable_id,
		"definition": definition_id,
		"name": label if label != "" else def.display_name,
		"tile": tile,
		"footprint": def.footprint,
		"inventory": {},
		"fraction": {},
		"received_this_month": {},
		"produced_this_month": 0.0,
		"total_produced": 0.0,
		"total_shipped": 0.0,
	}
	for flow in def.produces:
		instance["inventory"][flow["cargo"]] = 0.0
		instance["fraction"][flow["cargo"]] = 0.0
	for flow in def.accepts:
		instance["received_this_month"][flow["cargo"]] = 0.0
	_industries[stable_id] = instance
	_order.append(stable_id)
	_ids.adopt_highest(stable_id)
	industry_added.emit(stable_id)
	return stable_id


func industries() -> Array[int]:
	return _order


func count() -> int:
	return _order.size()


func industry(industry_id: int) -> Dictionary:
	return _industries.get(industry_id, {})


func name_of(industry_id: int) -> String:
	return String(industry(industry_id).get("name", "Industry"))


func definition_of(industry_id: int) -> String:
	return String(industry(industry_id).get("definition", ""))


func tile_of(industry_id: int) -> Vector2i:
	return industry(industry_id).get("tile", Vector2i.ZERO)


func def_of(industry_id: int) -> DataRegistry.IndustryDef:
	return _defs.industries.get(definition_of(industry_id))


func inventory_of(industry_id: int, cargo_id: String) -> float:
	return float(industry(industry_id).get("inventory", {}).get(cargo_id, 0.0))


func capacity_of(industry_id: int, cargo_id: String) -> float:
	for flow in _flows(industry_id, "produces"):
		if flow["cargo"] == cargo_id:
			return float(flow["storage_capacity"])
	return 0.0


func production_rate(industry_id: int, cargo_id: String) -> float:
	for flow in _flows(industry_id, "produces"):
		if flow["cargo"] == cargo_id:
			return float(flow["rate_per_month"])
	return 0.0


func is_producer(industry_id: int) -> bool:
	return not _flows(industry_id, "produces").is_empty()


func is_consumer(industry_id: int) -> bool:
	return not _flows(industry_id, "accepts").is_empty()


func accepts(industry_id: int, cargo_id: String) -> bool:
	for flow in _flows(industry_id, "accepts"):
		if flow["cargo"] == cargo_id:
			return true
	return false


func received_this_month(industry_id: int, cargo_id: String) -> float:
	return float(industry(industry_id).get("received_this_month", {}).get(cargo_id, 0.0))


func consume(industry_id: int, cargo_id: String, quantity: float) -> float:
	var instance: Dictionary = _industries[industry_id]
	if instance.is_empty() or not accepts(industry_id, cargo_id):
		return 0.0
	var inventory: Dictionary = instance["inventory"]
	var received: Dictionary = instance["received_this_month"]
	inventory[cargo_id] = float(inventory.get(cargo_id, 0.0)) + quantity
	received[cargo_id] = float(received.get(cargo_id, 0.0)) + quantity
	instance["total_shipped"] = float(instance.get("total_shipped", 0.0)) + quantity
	industry_received.emit(industry_id, cargo_id, quantity)
	return quantity


## Takes up to `quantity` units out of a producer's storage.
func withdraw(industry_id: int, cargo_id: String, quantity: float) -> float:
	var instance: Dictionary = _industries[industry_id]
	if instance.is_empty():
		return 0.0
	var inventory: Dictionary = instance["inventory"]
	var available := float(inventory.get(cargo_id, 0.0))
	var taken := minf(available, quantity)
	if taken <= 0.0:
		return 0.0
	inventory[cargo_id] = available - taken
	return taken


func deposit(industry_id: int, cargo_id: String, quantity: float) -> float:
	var instance: Dictionary = _industries[industry_id]
	if instance.is_empty():
		return 0.0
	var capacity := capacity_of(industry_id, cargo_id)
	var inventory: Dictionary = instance["inventory"]
	var current := float(inventory.get(cargo_id, 0.0))
	var room := capacity - current if capacity > 0.0 else quantity
	var given := minf(room, quantity)
	if given <= 0.0:
		return 0.0
	inventory[cargo_id] = current + given
	return given


func is_full(industry_id: int, cargo_id: String) -> bool:
	var capacity := capacity_of(industry_id, cargo_id)
	if capacity <= 0.0:
		return false
	return inventory_of(industry_id, cargo_id) >= capacity - 0.001


## One month of production.  Fractions accumulate per source so a 20/month mine
## delivers exactly 20 over a month rather than losing its remainder.
func advance_month() -> void:
	for industry_id in _order:
		var instance: Dictionary = _industries[industry_id]
		var inventory: Dictionary = instance["inventory"]
		var fractions: Dictionary = instance["fraction"]
		# The new month opens by closing the last one's counters, so "produced
		# this month" survives the whole month it describes.
		instance["received_this_month"] = _zero_flows(industry_id, "accepts")
		instance["produced_this_month"] = 0.0
		for flow in _flows(industry_id, "produces"):
			var cargo_id := String(flow["cargo"])
			var capacity := float(flow["storage_capacity"])
			var owed := float(flow["rate_per_month"]) + float(fractions.get(cargo_id, 0.0))
			var whole := floorf(owed)
			fractions[cargo_id] = owed - whole
			var current := float(inventory.get(cargo_id, 0.0))
			var room := capacity - current if capacity > 0.0 else whole
			var added := minf(room, whole)
			inventory[cargo_id] = current + added
			instance["produced_this_month"] = float(instance["produced_this_month"]) + added
			instance["total_produced"] = float(instance["total_produced"]) + added
			if added > 0.0:
				industry_produced.emit(industry_id, cargo_id, added)
			if capacity > 0.0 and inventory[cargo_id] >= capacity - 0.001:
				industry_storage_full.emit(industry_id, cargo_id)


func transported_share(industry_id: int) -> float:
	var produced := float(industry(industry_id).get("total_produced", 0.0))
	if produced <= 0.0:
		return 1.0
	return clampf(float(industry(industry_id).get("total_shipped", 0.0)) / produced, 0.0, 1.0)


func reset_monthly_counters() -> void:
	for industry_id in _order:
		var instance: Dictionary = _industries[industry_id]
		instance["received_this_month"] = _zero_flows(industry_id, "accepts")


func _flows(industry_id: int, kind: String) -> Array[Dictionary]:
	var def := def_of(industry_id)
	if def == null:
		return []
	return def.produces if kind == "produces" else def.accepts


func _zero_flows(industry_id: int, kind: String) -> Dictionary:
	var out := {}
	for flow in _flows(industry_id, kind):
		out[flow["cargo"]] = 0.0
	return out


func to_dict() -> Dictionary:
	var entries: Array = []
	for industry_id in _order:
		var instance: Dictionary = _industries[industry_id]
		entries.append({
			"id": industry_id,
			"definition": instance["definition"],
			"name": instance["name"],
			"x": instance["tile"].x,
			"y": instance["tile"].y,
			"inventory": instance["inventory"].duplicate(),
			"fraction": instance["fraction"].duplicate(),
			"total_produced": instance["total_produced"],
			"total_shipped": instance["total_shipped"],
		})
	return {"industries": entries}


func from_dict(data: Dictionary) -> void:
	_industries.clear()
	_order.clear()
	for entry in data.get("industries", []):
		var industry_id := int(entry["id"])
		var def: DataRegistry.IndustryDef = _defs.industries.get(String(entry["definition"]))
		if def == null:
			continue
		_industries[industry_id] = {
			"id": industry_id,
			"definition": entry["definition"],
			"name": String(entry.get("name", def.display_name)),
			"tile": Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0))),
			"footprint": def.footprint,
			"inventory": Dictionary(entry.get("inventory", {})),
			"fraction": Dictionary(entry.get("fraction", {})),
			"received_this_month": _zero_flows(industry_id, "accepts"),
			"produced_this_month": 0.0,
			"total_produced": float(entry.get("total_produced", 0.0)),
			"total_shipped": float(entry.get("total_shipped", 0.0)),
		}
		_order.append(industry_id)
		if _ids != null:
			_ids.adopt_highest(industry_id)
