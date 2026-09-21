class_name SaveService
extends RefCounted

## Named save slots, quicksave, autosave and versioned loading for one session.
##
## Every file this writes is the same envelope — `save_version`, `game_version`,
## a human-readable header for slot lists, and the domain snapshot — published
## through SaveWriter's temp → validate → rename contract.  A load validates
## (version, structure, cross-references) *before* the session is touched, so a
## corrupt or future-version file is refused with a reason and leaves both the
## file and the running game exactly as they were.
##
## Infrastructure: it composes the services' own to_dict/from_dict through the
## session's snapshot()/restore(); it knows nothing about nodes or screens.

const SAVE_FOLDER := "user://saves"
const SAVE_VERSION := 1
const GAME_VERSION := "0.1.0"
const AUTOSAVE_PREFIX := "autosave_"
const QUICKSAVE_SLOT := "quicksave"

## Autosaves are pruned to this many, oldest first — a recorded project
## decision (design: add-game-shell-and-persistence), not a knob to twiddle.
const AUTOSAVE_RETENTION := 5

var _session: Object = null
var _migrations := {}


## The session owns one of these and attaches itself; the UI reaches saves
## through `session.saves`.
func attach(session: Object) -> void:
	_session = session


# --- slots ------------------------------------------------------------------

static func is_valid_slot(slot_name: String) -> bool:
	if slot_name.is_empty() or slot_name == "." or slot_name == "..":
		return false
	for index in slot_name.length():
		var code := slot_name.unicode_at(index)
		var letter := (code >= 65 and code <= 90) or (code >= 97 and code <= 122) \
				or (code >= 48 and code <= 57) or code == 95 or code == 45
		if not letter:
			return false
	return true


func slot_path(slot_name: String) -> String:
	if not is_valid_slot(slot_name):
		return ""
	DirAccess.make_dir_recursive_absolute(SAVE_FOLDER)
	return SAVE_FOLDER.path_join("%s.json" % slot_name)


func exists(slot_name: String) -> bool:
	var path := slot_path(slot_name)
	return path != "" and FileAccess.file_exists(path)


# --- writing ----------------------------------------------------------------

## Manual save into a named slot.  Returns {ok, reason, path, bytes}.
func save(slot_name: String) -> Dictionary:
	return save_to_path(slot_path(slot_name), "manual")


func save_to_path(path: String, kind: String = "manual") -> Dictionary:
	if path == "":
		return {"ok": false, "reason": "Invalid save slot name", "path": path}
	return SaveWriter.write_json(path, document(kind))


func quicksave() -> Dictionary:
	return save_to_path(slot_path(QUICKSAVE_SLOT), "quicksave")


## One autosave, named by the in-game date, then retention pruning.  Reads only:
## nothing here advances a tick, records money, or otherwise mutates state.
func autosave() -> Dictionary:
	var date: GameDate = _session.date()
	var slot := "%s%04d_%02d" % [AUTOSAVE_PREFIX, int(date.year), int(date.month)]
	var result := save_to_path(slot_path(slot), "autosave")
	prune_autosaves()
	return result


## Keeps the newest AUTOSAVE_RETENTION autosave files; the names carry the
## padded in-game date, so lexicographic order is chronological order.
func prune_autosaves() -> void:
	var names := _autosave_names()
	while names.size() > AUTOSAVE_RETENTION:
		var oldest := String(names.pop_front())
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_FOLDER.path_join(oldest)))


func latest_autosave() -> String:
	var names := _autosave_names()
	if names.is_empty():
		return ""
	return SAVE_FOLDER.path_join(String(names[names.size() - 1]))


# --- reading ----------------------------------------------------------------

## Load a named slot.  Returns {ok, reason, path}.  A false return means the
## running session is untouched and the file on disk is unchanged.
func load(slot_name: String) -> Dictionary:
	return load_path(slot_path(slot_name))


func load_path(path: String) -> Dictionary:
	if path == "":
		return {"ok": false, "reason": "Invalid save slot name", "path": path}
	var read := SaveWriter.read_json(path)
	if not bool(read.get("ok", false)):
		return read
	return load_document(Dictionary(read.get("data", {})), path)


func quickload() -> Dictionary:
	var path := slot_path(QUICKSAVE_SLOT)
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "No quicksave to load", "path": path}
	return load_path(path)


## Validate and restore one parsed save document.  Kept public so a menu flow
## holding an already-parsed document can reuse the same gate.
func load_document(document: Dictionary, path: String) -> Dictionary:
	var prepared := _prepare(document)
	if not bool(prepared.get("ok", false)):
		return {"ok": false, "reason": String(prepared.get("reason", "")), "path": path}
	var snapshot: Dictionary = prepared["snapshot"]
	var refused := _map_refusal_reason(snapshot)
	if refused != "":
		return {"ok": false, "reason": refused, "path": path}
	var problems := verify_refs(snapshot)
	if not problems.is_empty():
		return {
			"ok": false,
			"reason": "Save failed structural validation: " + "; ".join(problems),
			"path": path,
		}
	if _session.restore(snapshot):
		return {"ok": true, "reason": "", "path": path}
	return {"ok": false, "reason": String(_session.last_error), "path": path}


## A save naming a different map must find that map installed before the
## session is reset to load it; checking first is what keeps the refusal clean.
func _map_refusal_reason(snapshot: Dictionary) -> String:
	var saved_map := String(snapshot.get("map", ""))
	var current := String(_session.map_id)
	if saved_map == "" or saved_map == current:
		return ""
	var map_path := MapDocument.MAP_ROOT.path_join(saved_map + ".json")
	if not FileAccess.file_exists(map_path):
		return "Save needs map '%s', which is not installed" % saved_map
	return ""


# --- versions and migrations --------------------------------------------------

## Register a pure migration old_document -> new_document for saves written at
## `from_version`.  Migrations never touch live services.
func register_migration(from_version: int, handler: Callable) -> void:
	_migrations[from_version] = handler


func clear_migrations() -> void:
	_migrations.clear()


## Unwrap the envelope, refuse a newer schema, and walk the registered
## migration chain forward.  Returns {ok, snapshot} or {ok: false, reason}.
func _prepare(document: Dictionary) -> Dictionary:
	var version := int(document.get("save_version", -1))
	var snapshot: Variant = null
	if document.has("save_version") and document.get("data") is Dictionary:
		snapshot = document["data"]
	elif document.has("version"):
		# Pre-envelope files were a bare snapshot; treat them as v1 exactly as
		# they were written, or the migration registry must claim version 0.
		version = int(document.get("version", 0))
		snapshot = document
	else:
		return {"ok": false, "reason": "Not an Open Rails save document"}
	if version > SAVE_VERSION:
		return {
			"ok": false,
			"reason": "Save was written by a newer save schema (v%d); this build reads up to v%d" % [
				version, SAVE_VERSION],
		}
	while version < SAVE_VERSION:
		var handler: Callable = _migrations.get(version, Callable())
		if not handler.is_valid():
			return {
				"ok": false,
				"reason": "No migration registered from save_version %d to %d — refusing to guess" % [
					version, SAVE_VERSION],
			}
		var migrated: Variant = handler.call(document)
		if not (migrated is Dictionary) or not Dictionary(migrated).has("save_version"):
			return {"ok": false,
				"reason": "The v%d migration did not return a save document" % version}
		document = migrated
		var next_version := int(document.get("save_version", version))
		if next_version <= version:
			return {"ok": false,
				"reason": "The v%d migration did not advance the save_version" % version}
		version = next_version
		if document.get("data") is Dictionary:
			snapshot = document["data"]
	if not (snapshot is Dictionary):
		return {"ok": false, "reason": "Save carries no snapshot"}
	return {"ok": true, "snapshot": Dictionary(snapshot)}


# --- structural integrity -----------------------------------------------------

## Cross-references a save must satisfy before it may touch a session:
## routes → stations, trains → stations, stations → rail cells.  Reports every
## problem; the caller refuses the load rather than repairing silently.
func verify_refs(snapshot: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var station_ids := {}
	for entry in Array(Dictionary(snapshot.get("stations", {})).get("stations", [])):
		var station_id := int(entry["id"])
		if station_ids.has(station_id):
			problems.append("duplicate station id %d" % station_id)
		station_ids[station_id] = true
	var train_ids := {}
	for entry in Array(Dictionary(snapshot.get("trains", {})).get("trains", [])):
		train_ids[int(entry["id"])] = true
	var rail := _scratch_rail(Dictionary(snapshot.get("world", {})))
	for entry in Array(Dictionary(snapshot.get("stations", {})).get("stations", [])):
		var access := Vector2i(int(entry.get("access_x", 0)), int(entry.get("access_y", 0)))
		if not _has_rail(rail, access):
			problems.append("station %d has no rail at its access tile (%d, %d)" % [
				int(entry["id"]), access.x, access.y])
	for entry in Array(Dictionary(snapshot.get("routes", {})).get("routes", [])):
		for stop in Array(entry.get("stops", [])):
			var stop_station := int(stop["station_id"])
			if not station_ids.has(stop_station):
				problems.append("route %d references station %d that does not exist" % [
					int(entry["id"]), stop_station])
	for entry in Array(Dictionary(snapshot.get("trains", {})).get("trains", [])):
		var home := int(entry.get("station", 0))
		if home != 0 and not station_ids.has(home):
			problems.append("train %d is home-based at station %d that does not exist" % [
				int(entry["id"]), home])
	return problems


## Decodes just the rail presence of a saved world, into a scratch grid.
func _scratch_rail(world_dict: Dictionary) -> WorldGrid:
	var scratch := WorldGrid.new(1, 1)
	SaveWriter.world_from_dict(scratch, world_dict)
	return scratch


func _has_rail(grid: WorldGrid, tile: Vector2i) -> bool:
	return grid.in_bounds(tile) and grid.is_rail(tile)


# --- listing and deletion -----------------------------------------------------

## Every save in the folder, newest first, with the header facts a slot list
## shows: map name, date/year, cash, company, timestamp, schema version.
func list_saves() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var directory := DirAccess.open(SAVE_FOLDER)
	if directory == null:
		return rows
	var names: Array = []
	for file in directory.get_files():
		if String(file).ends_with(".json"):
			names.append(String(file))
	names.sort()
	for file in names:
		var path := SAVE_FOLDER.path_join(String(file))
		var slot := String(file).trim_suffix(".json")
		var read := SaveWriter.read_json(path)
		if not bool(read.get("ok", false)):
			# A damaged file is still a file the player can see, so it gets a row —
			# with the fields the sort below reads.  Leaving them out made listing a
			# folder containing one corrupt save abort with a script error.
			rows.append({"slot": slot, "path": path, "corrupt": true,
				"reason": String(read.get("reason", "unreadable")),
				"saved_at_unix": 0, "autosave": slot.begins_with(AUTOSAVE_PREFIX),
				"date": "", "company": "", "cash": 0.0})
			continue
		var document := Dictionary(read.get("data", {}))
		var header := Dictionary(document.get("header", {}))
		var stamp := int(header.get("saved_at_unix", 0))
		var row := {
			"slot": slot,
			"path": path,
			"corrupt": false,
			"save_version": int(document.get("save_version", document.get("version", 0))),
			"game_version": String(document.get("game_version", "")),
			"kind": String(header.get("kind", "legacy")),
			"autosave": slot.begins_with(AUTOSAVE_PREFIX),
			"map": String(header.get("map", document.get("map", ""))),
			"company": String(header.get("company", "")),
			"cash": float(header.get("cash", 0.0)),
			"year": int(header.get("year", 0)),
			"month": int(header.get("month", 0)),
			"day": int(header.get("day", 0)),
			"date": String(header.get("date", "")),
			"saved_at": String(header.get("saved_at", "")),
			"saved_at_unix": stamp,
		}
		rows.append(row)
	rows.sort_custom(func(a, b):
		if int(a["saved_at_unix"]) != int(b["saved_at_unix"]):
			return int(a["saved_at_unix"]) > int(b["saved_at_unix"])
		return String(a["slot"]) > String(b["slot"]))
	return rows


## Delete a save.  The file is really gone; a false return explains why not.
func delete(slot_name: String) -> Dictionary:
	var path := slot_path(slot_name)
	if path == "":
		return {"ok": false, "reason": "Invalid save slot name", "path": path}
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "No save at %s" % path, "path": path}
	var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if error != OK:
		return {"ok": false, "reason": "Could not remove %s (%d)" % [path, error], "path": path}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".prev"))
	return {"ok": true, "reason": "", "path": path}


# --- documents ----------------------------------------------------------------

func document(kind: String) -> Dictionary:
	var with_kind := header()
	with_kind["kind"] = kind
	return {
		"save_version": SAVE_VERSION,
		"game_version": GAME_VERSION,
		"header": with_kind,
		"data": _session.snapshot(),
	}


## The human-readable facts a slot list needs, straight from the session.
## Wall-clock appears *only* here — save metadata, never simulation input.
func header() -> Dictionary:
	var date: GameDate = _session.date()
	var stamp: Dictionary = Time.get_datetime_dict_from_system(true)
	return {
		"map": String(_session.map_id),
		"company": String(_session.company_name()),
		"cash": float(_session.economy.cash),
		"year": int(date.year),
		"month": int(date.month),
		"day": int(date.day),
		"date": String(date.display_full()),
		"saved_at": "%04d-%02d-%02d %02d:%02d UTC" % [
			int(stamp.year), int(stamp.month), int(stamp.day),
			int(stamp.hour), int(stamp.minute)],
		"saved_at_unix": int(Time.get_unix_time_from_system()),
	}


func _autosave_names() -> Array:
	var names: Array = []
	var directory := DirAccess.open(SAVE_FOLDER)
	if directory == null:
		return names
	for file in directory.get_files():
		if String(file).begins_with(AUTOSAVE_PREFIX) and String(file).ends_with(".json"):
			names.append(String(file))
	names.sort()
	return names
