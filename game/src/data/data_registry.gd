class_name DataRegistry
extends RefCounted

## Loads JSON definitions from `res://data/` once at session start.
##
## Definitions are immutable after load.  A definition that references an
## unknown id — a wagon carrying a cargo that does not exist — fails loudly
## with the offending file name rather than quietly producing a broken game.

const DATA_ROOT := "res://data"

var cargo: Dictionary = {}          # id -> CargoDef
var rolling_stock: Dictionary = {}  # id -> StockDef
var locomotives: Dictionary = {}
var wagons: Dictionary = {}
var industries: Dictionary = {}
var stations: Dictionary = {}
var economy: Dictionary = {}
var timing: Dictionary = {}
## Company liveries, in the order they were authored: each is
## `{id, name, primary: Color, secondary: Color}`.
var liveries: Array[Dictionary] = []
var default_livery_id := ""

var errors: PackedStringArray = PackedStringArray()


class CargoDef extends RefCounted:
	var id: String = ""
	var display_name: String = ""
	var unit_label: String = "units"
	var base_rate: float = 1.0
	var time_sensitivity: float = 0.0
	var quality_floor: float = 0.25
	var colour: Color = Color.WHITE
	var wagon_required: bool = true
	var tonnes_per_unit: float = 1.0
	var source_file: String = ""


class StockDef extends RefCounted:
	var id: String = ""
	var display_name: String = ""
	var kind: String = "wagon"
	var asset: String = ""
	var price: float = 0.0
	var running_cost_month: float = 0.0
	var weight_tons: float = 1.0
	var cargo: String = ""
	var capacity: int = 0
	var max_speed_kmh: float = 0.0
	var power: float = 0.0
	## Coupler to coupler along the vehicle, in tiles.  The domain has to know how
	## long a train is in order to halt it beside a platform rather than a platform
	## short of it; the built model's coupler attachments carry the same figures, and
	## a test holds the two to each other.  0.75 is the stock of a wagon.
	var wheel_radius: float = 0.0
	var length_tiles: float = 0.75
	var source_file: String = ""


class IndustryDef extends RefCounted:
	var id: String = ""
	var display_name: String = ""
	var asset: String = ""
	var footprint: Vector2i = Vector2i(1, 1)
	var produces: Array[Dictionary] = []
	var accepts: Array[Dictionary] = []
	var animation_state: String = "working"
	var source_file: String = ""


class StationDef extends RefCounted:
	var id: String = ""
	var display_name: String = ""
	var asset: String = ""
	var cost: float = 0.0
	var footprint: Vector2i = Vector2i(3, 2)
	var catchment_tiles: float = 4.0
	var storage_per_cargo: int = 120
	var requires_straight_rail: bool = true
	## Rings outside the footprint searched for a rail cell to couple to.  One
	## ring means a yard couples to ground beside it, which is what a station is;
	## a larger radius lets the model drift away from its own platform.
	var rail_search_radius: int = 1
	var source_file: String = ""


## Reload everything from disk.  Idempotent: a second call scans from a clean
## slate, so it cannot flag the definitions it loaded the first time as
## duplicates, and stale `errors` never leak into the result.  It also drops
## anything registered at runtime via [method load_definition_file].
func load_all() -> bool:
	_clear()
	economy = _read_json(DATA_ROOT.path_join("economy/balance.json"))
	timing = _read_json(DATA_ROOT.path_join("economy/timing.json"))
	_load_dir(DATA_ROOT.path_join("cargo"), _load_cargo)
	_load_dir(DATA_ROOT.path_join("rolling_stock"), _load_stock)
	_load_dir(DATA_ROOT.path_join("industries"), _load_industry)
	_load_dir(DATA_ROOT.path_join("stations"), _load_station)
	_load_liveries()
	_validate()
	return errors.is_empty()


func cargo_ids() -> Array[String]:
	return _sorted_keys(cargo)


func cargo_def(id: String) -> CargoDef:
	return cargo.get(id)


func cargo_display(id: String) -> String:
	var def := cargo_def(id)
	return def.display_name if def != null else id.capitalize()


func cargo_colour(id: String) -> Color:
	var def := cargo_def(id)
	return def.colour if def != null else Color(0.7, 0.7, 0.7)


func stock(id: String) -> StockDef:
	return rolling_stock.get(id)


func wagon_ids() -> Array[String]:
	return _sorted_keys(wagons)


func locomotive_ids() -> Array[String]:
	return _sorted_keys(locomotives)


## `Dictionary.keys()` hands back an untyped Array; assigning it to a typed
## Array[String] is a runtime error, so the copy is done explicitly.
func _sorted_keys(source: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for key in source:
		ids.append(String(key))
	ids.sort()
	return ids


func starting_cash() -> float:
	return float(economy.get("starting_cash", 500000.0))


func default_company_name() -> String:
	return String(economy.get("default_company_name", "Founder's Railway"))


# --- company liveries ------------------------------------------------------

## Liveries are one table rather than one file per livery: a livery is two palette
## colours and a name, and a directory of eight two-line files would be a filing
## system pretending to be content.
func _load_liveries() -> void:
	var path := DATA_ROOT.path_join("company/liveries.json")
	var data := _read_json(path)
	if data.is_empty():
		errors.append("missing livery table: " + path)
		return
	var entries: Variant = data.get("liveries", [])
	if typeof(entries) != TYPE_ARRAY or entries.is_empty():
		errors.append(path + ": no liveries listed")
		return
	var seen := {}
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append(path + ": every livery must be an object")
			continue
		var id := String(entry.get("id", ""))
		if id == "":
			errors.append(path + ": a livery has no id")
			continue
		if seen.has(id):
			errors.append(path + ": duplicate livery id " + id)
			continue
		seen[id] = true
		liveries.append({
			"id": id,
			"name": String(entry.get("name", id.capitalize())),
			"primary": _palette_colour(entry.get("primary", ""), id, "primary", path),
			"secondary": _palette_colour(entry.get("secondary", ""), id, "secondary", path),
		})
	default_livery_id = String(data.get("default_livery", ""))
	if default_livery_id != "" and not seen.has(default_livery_id):
		errors.append(path + ": default_livery names an unknown id " + default_livery_id)


## A livery colour is `#rrggbb` from `art/config/material_palette.json`.  A typo
## there would paint a company grey, so it is an error rather than a fallback.
func _palette_colour(value: Variant, livery_id: String, role: String, path: String) -> Color:
	var text := String(value) if typeof(value) == TYPE_STRING else ""
	if not text.begins_with("#") or text.length() != 7:
		errors.append("%s: livery %s has an unusable %s colour (want #rrggbb)" % [path, livery_id, role])
		return Color(0.7, 0.7, 0.7)
	return Color.from_string(text.to_lower(), Color(0.7, 0.7, 0.7))


func livery_ids() -> Array[String]:
	var ids: Array[String] = []
	for livery in liveries:
		ids.append(String(livery["id"]))
	return ids


func livery_by_id(id: String) -> Dictionary:
	for livery in liveries:
		if String(livery["id"]) == id:
			return livery.duplicate()
	return {}


func default_livery() -> Dictionary:
	var found := livery_by_id(default_livery_id)
	if not found.is_empty():
		return found
	return liveries[0].duplicate() if not liveries.is_empty() else {}


## The livery a company paints itself with: the name alone decides, so a name typed
## twice earns the same colours and no screen has to ask for paint.  The fold is
## arithmetic written here rather than the engine's `hash()`, because a livery that
## moved between engine builds would repaint a saved company in another road's
## colours.  An empty name folds to zero, which is the palette's own default.
func livery_for(company_name: String) -> Dictionary:
	if liveries.is_empty():
		return {}
	return liveries[livery_fold(company_name.strip_edges().to_lower()) % liveries.size()].duplicate()


static func livery_fold(text: String) -> int:
	var acc := 0
	for unit in text.to_utf8_buffer():
		acc = acc * 31 + int(unit)
		if acc > FOLD_LIMIT:
			# Bounded arithmetic: the fold is meant to be the same number in every
			# build, so it stays far inside 64 bits instead of relying on wraparound.
			acc %= FOLD_LIMIT
	return acc


const FOLD_LIMIT := 1 << 40


func track_setting(key: String, fallback: float) -> float:
	var track: Dictionary = economy.get("track", {})
	return float(track.get(key, fallback))


func planner_setting(key: String, fallback: float) -> float:
	var planner: Dictionary = economy.get("planner", {})
	return float(planner.get(key, fallback))


func station_setting(key: String, fallback: float) -> float:
	var station: Dictionary = economy.get("station", {})
	return float(station.get(key, fallback))


func train_setting(key: String, fallback: float) -> float:
	var train: Dictionary = timing.get("train", {})
	return float(train.get(key, fallback))


## The pace of the calendar.  The fallback is the shipped value, not a smaller
## one: `ticks_per_day` is what keeps a month longer than a loaded leg, so a
## silent 12 here would have a pit pin its platform ceiling before a train
## could clear it — a whole valley looking broken with every number correct.
func ticks_per_day() -> int:
	return int(timing.get("ticks_per_day", 60))


## The year the valley opens.  Read rather than remembered, so the calendar the
## simulation runs on and the year the New Sandbox screen promises cannot drift.
func start_year() -> int:
	return int(timing.get("start_year", 1850))


## Every map that is actually installed.  V1 ships one, and the New Sandbox
## screen lists this rather than trusting a row written into code — a second map
## has to appear on that screen by being copied in and nothing else.
func installed_maps() -> Array[String]:
	var ids: Array[String] = []
	var directory := DirAccess.open(DATA_ROOT.path_join("maps"))
	if directory == null:
		return ids
	var names: Array = []
	for file in directory.get_files():
		var name := String(file)
		if name.ends_with(".json"):
			names.append(name.trim_suffix(".json"))
	names.sort()
	for name in names:
		ids.append(String(name))
	return ids


## What an install file says about itself, without decoding a single tile.  A
## menu row needs a name and a size; reading 65 536 heights to label it would be
## silly, and `MapDocument.read` is what the boot path is for.
func map_summary(map_id: String) -> Dictionary:
	var parsed := _read_json(DATA_ROOT.path_join("maps").path_join(map_id + ".json"))
	if parsed.is_empty():
		return {"id": map_id, "display_name": map_id, "width": 0, "height": 0}
	return {
		"id": String(parsed.get("id", map_id)),
		"display_name": String(parsed.get("display_name", map_id)),
		"width": int(parsed.get("width", 0)),
		"height": int(parsed.get("height", 0)),
	}


func autosave_every_months() -> int:
	return int(timing.get("autosave_every_months", 3))


## Drop everything loaded so far, so a re-scan starts from a clean slate.
## Without this, a second `load_all()` flags the first pass's own definitions
## as duplicate ids and reports failures that are not real.
func _clear() -> void:
	cargo.clear()
	rolling_stock.clear()
	locomotives.clear()
	wagons.clear()
	industries.clear()
	stations.clear()
	economy.clear()
	timing.clear()
	liveries.clear()
	default_livery_id = ""
	errors.clear()


func _load_dir(path: String, handler: Callable) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		errors.append("missing data directory: " + path)
		return
	var files: Array[String] = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json"):
			files.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	files.sort()
	for file in files:
		handler.call(path.path_join(file))


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("missing data file: " + path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		errors.append("not a JSON object: " + path)
		return {}
	return parsed


## Load one more definition after startup — a scenario pack, a mod, a test.
## New content is meant to be a data file and nothing else (invariant 7), which
## is only true if the loader that runs at startup can be reached afterwards.
func load_definition_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "No such file: " + path, "id": "", "kind": ""}
	var data := _read_json(path)
	if data.is_empty():
		return {"ok": false, "reason": "Not readable JSON: " + path, "id": "", "kind": ""}
	var kind := classify(data)
	var before := errors.size()
	if kind == "cargo":
		_load_cargo(path)
	elif kind == "locomotive" or kind == "wagon":
		_load_stock(path)
	elif kind == "industry":
		_load_industry(path)
	elif kind == "station":
		_load_station(path)
	else:
		return {"ok": false, "reason": "Unrecognised definition in " + path, "id": "", "kind": ""}
	if errors.size() > before:
		return {"ok": false, "reason": String(errors[errors.size() - 1]), "id": "", "kind": kind}
	var id := String(data.get("id", path.get_file().get_basename()))
	var landed := false
	match kind:
		"cargo":
			landed = cargo.has(id)
		"locomotive", "wagon":
			landed = rolling_stock.has(id)
		"industry":
			landed = industries.has(id)
		"station":
			landed = stations.has(id)
	return {"ok": landed, "reason": "", "id": id, "kind": kind}


## Which table a definition document belongs to, decided from its own shape —
## only rolling stock carries a `type`, so guessing from that alone would load
## an industry as a wagon.
static func classify(data: Dictionary) -> String:
	if data.has("base_rate"):
		return "cargo"
	if data.has("produces") or data.has("accepts"):
		return "industry"
	if data.has("catchment_tiles") or data.has("storage_per_cargo"):
		return "station"
	return String(data.get("type", "wagon"))


func _load_cargo(path: String) -> void:
	var data := _read_json(path)
	if data.is_empty():
		return
	var def := CargoDef.new()
	def.id = String(data.get("id", path.get_file().get_basename()))
	def.display_name = String(data.get("display_name", def.id.capitalize()))
	def.unit_label = String(data.get("unit_label", "units"))
	def.base_rate = float(data.get("base_rate", 1.0))
	def.time_sensitivity = float(data.get("time_sensitivity", 0.0))
	def.quality_floor = float(data.get("quality_floor", 0.25))
	def.colour = _colour(data.get("colour", "#b0b0b0"))
	def.wagon_required = bool(data.get("wagon_required", true))
	def.tonnes_per_unit = float(data.get("tonnes_per_unit", 1.0))
	def.source_file = path
	if cargo.has(def.id):
		errors.append("%s: duplicate cargo id '%s'" % [path, def.id])
		return
	cargo[def.id] = def


func _load_stock(path: String) -> void:
	var data := _read_json(path)
	if data.is_empty():
		return
	var def := StockDef.new()
	def.id = String(data.get("id", path.get_file().get_basename()))
	def.display_name = String(data.get("display_name", def.id.capitalize()))
	def.kind = String(data.get("type", "wagon"))
	def.asset = String(data.get("asset", def.id))
	def.price = float(data.get("price", 0.0))
	def.running_cost_month = float(data.get("running_cost_month", 0.0))
	def.weight_tons = float(data.get("weight_tons", 1.0))
	def.cargo = String(data.get("cargo", ""))
	def.capacity = int(data.get("capacity", 0))
	def.max_speed_kmh = float(data.get("max_speed_kmh", 0.0))
	def.power = float(data.get("power", 1.0))
	def.wheel_radius = float(data.get("wheel_radius", 0.1))
	def.length_tiles = float(data.get("length_tiles", 0.75))
	def.source_file = path
	if def.kind == "wagon" and def.cargo != "" and not cargo.has(def.cargo):
		# A definition that names a cargo which does not exist is broken, not
		# merely degraded: registering it would hand the player a wagon that can
		# never be loaded.  Report and drop it.
		errors.append("%s: wagon '%s' carries unknown cargo '%s'" % [path, def.id, def.cargo])
		return
	if def.kind == "locomotive":
		locomotives[def.id] = def
	else:
		wagons[def.id] = def
	rolling_stock[def.id] = def


func _load_industry(path: String) -> void:
	var data := _read_json(path)
	if data.is_empty():
		return
	var def := IndustryDef.new()
	def.id = String(data.get("id", path.get_file().get_basename()))
	def.display_name = String(data.get("display_name", def.id.capitalize()))
	def.asset = String(data.get("asset", def.id))
	def.footprint = _footprint(data.get("footprint", [1, 1]))
	def.animation_state = String(data.get("animation_state", "working"))
	def.source_file = path
	var rejected := errors.size()
	for entry in data.get("produces", []):
		var record := _flow(entry, path, def.id)
		if record.is_empty():
			continue
		def.produces.append(record)
	for entry in data.get("accepts", []):
		var record := _flow(entry, path, def.id)
		if record.is_empty():
			continue
		def.accepts.append(record)
	if errors.size() > rejected:
		# Same rule as rolling stock: one unresolvable flow and the whole
		# definition is dropped, so no industry simulates half its contract.
		return
	industries[def.id] = def


func _flow(entry: Variant, path: String, owner: String) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		errors.append("%s: industry '%s' has a non-object flow entry" % [path, owner])
		return {}
	var cargo_id := String(entry.get("cargo", ""))
	if cargo_id == "" or not cargo.has(cargo_id):
		errors.append("%s: industry '%s' references unknown cargo '%s'" % [path, owner, cargo_id])
		return {}
	return {
		"cargo": cargo_id,
		"rate_per_month": float(entry.get("rate_per_month", entry.get("capacity_per_month", 0.0))),
		"storage_capacity": float(entry.get("storage_capacity", entry.get("capacity_per_month", 0.0))),
		"capacity_per_month": float(entry.get("capacity_per_month", 0.0)),
	}


func _load_station(path: String) -> void:
	var data := _read_json(path)
	if data.is_empty():
		return
	var def := StationDef.new()
	def.id = String(data.get("id", path.get_file().get_basename()))
	def.display_name = String(data.get("display_name", def.id.capitalize()))
	def.asset = String(data.get("asset", def.id))
	def.cost = float(data.get("cost", 0.0))
	def.footprint = _footprint(data.get("footprint", [3, 2]))
	def.catchment_tiles = float(data.get("catchment_tiles", WorldConstants.STATION_CATCHMENT))
	def.storage_per_cargo = int(data.get("storage_per_cargo", 120))
	def.requires_straight_rail = bool(data.get("requires_straight_rail", true))
	def.rail_search_radius = maxi(1, int(data.get("rail_search_radius", def.rail_search_radius)))
	def.source_file = path
	stations[def.id] = def


func _validate() -> void:
	if cargo.is_empty():
		errors.append("no cargo definitions found under " + DATA_ROOT.path_join("cargo"))
	if locomotives.is_empty():
		errors.append("no locomotive definitions found under " + DATA_ROOT.path_join("rolling_stock"))
	if wagons.is_empty():
		errors.append("no wagon definitions found under " + DATA_ROOT.path_join("rolling_stock"))
	if stations.is_empty():
		errors.append("no station definitions found under " + DATA_ROOT.path_join("stations"))


func _footprint(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_ARRAY and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i(1, 1)


func _colour(value: Variant) -> Color:
	if typeof(value) == TYPE_STRING:
		return Color.from_string(value, Color(0.7, 0.7, 0.7))
	return Color(0.7, 0.7, 0.7)
