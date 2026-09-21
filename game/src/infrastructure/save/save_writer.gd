class_name SaveWriter
extends RefCounted

## Atomic, versioned JSON persistence for the world grid and any document.
##
## A save is written to a temp file, parsed back, and only then renamed over the
## target.  A crash mid-write therefore leaves the previous save intact rather
## than a half-written file — the reason there is no `.bak` dance here.

const TEMP_SUFFIX := ".tmp"


static func write_json(path: String, data: Dictionary) -> Dictionary:
	var directory := path.get_base_dir()
	if directory != "":
		DirAccess.make_dir_recursive_absolute(directory)
	var text := JSON.stringify(data, "\t")
	var parse_check: Variant = JSON.parse_string(text)
	if parse_check == null:
		return {"ok": false, "reason": "Snapshot did not round-trip through JSON", "path": path}
	var temp := path + TEMP_SUFFIX
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "Cannot open %s for writing" % temp, "path": path}
	file.store_string(text)
	file.flush()
	file.close()
	var verify := FileAccess.get_file_as_string(temp)
	if JSON.parse_string(verify) == null:
		DirAccess.remove_absolute(temp)
		return {"ok": false, "reason": "Written save failed verification", "path": path}
	var absolute := ProjectSettings.globalize_path(path)
	var existing := absolute + ".prev"
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, existing)
	DirAccess.remove_absolute(path)
	var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), absolute)
	if error != OK:
		DirAccess.remove_absolute(temp)
		return {"ok": false, "reason": "Rename failed (%d)" % error, "path": path}
	return {"ok": true, "reason": "", "path": path, "bytes": text.length()}


static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "No save at %s" % path, "path": path}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		return {"ok": false, "reason": "Save is not valid JSON", "path": path}
	if not (parsed is Dictionary):
		return {"ok": false, "reason": "Save root is not an object", "path": path}
	return {"ok": true, "reason": "", "data": parsed, "path": path}


static func world_to_dict(world: WorldGrid) -> Dictionary:
	return {
		"width": world.width,
		"height": world.height,
		"terrain": _encode(world.terrain),
		"heights": _encode(world.height_steps),
		"occupancy": _encode(world.occupancy_kind),
		"occupancy_ids": _encode_int64(world.occupancy_id),
		"rail": _encode(world.rail),
		"rail_cells": _encode(world.rail_present),
	}


static func world_from_dict(world: WorldGrid, data: Dictionary) -> void:
	var width := int(data.get("width", world.width))
	var height := int(data.get("height", world.height))
	world.resize(width, height)
	_decode_into(data.get("terrain", []), world.terrain)
	_decode_into(data.get("heights", []), world.height_steps)
	_decode_into(data.get("occupancy", []), world.occupancy_kind)
	_decode_into_int64(data.get("occupancy_ids", []), world.occupancy_id)
	_decode_into(data.get("rail", []), world.rail)
	_decode_into(data.get("rail_cells", []), world.rail_present)
	world.take_dirty_tiles()
	world.take_dirty_chunks()


## Byte arrays go out as base64: 65 536 values as JSON numbers would be a
## megabyte of text and a second of parsing for no benefit.
static func _encode(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes)


static func _decode_into(value: Variant, target: PackedByteArray) -> void:
	if value is String:
		var decoded := Marshalls.base64_to_raw(String(value))
		var limit := mini(decoded.size(), target.size())
		for index in limit:
			target[index] = decoded[index]
		return
	if value is Array:
		var array: Array = value
		var limit := mini(array.size(), target.size())
		for index in limit:
			target[index] = int(array[index])


static func _encode_int64(values: PackedInt64Array) -> String:
	## 64-bit ids are entity references, and a truncated one silently re-points a
	## tile at a different owner.  var_to_bin keeps the full width and the array
	## type, so a save cannot quietly shrink an id.
	return Marshalls.raw_to_base64(var_to_bytes(values))


static func _decode_into_int64(value: Variant, target: PackedInt64Array) -> void:
	if not (value is String):
		return
	var decoded: Variant = bytes_to_var(Marshalls.base64_to_raw(String(value)))
	if typeof(decoded) != TYPE_PACKED_INT64_ARRAY:
		return
	var array: PackedInt64Array = decoded
	var limit := mini(array.size(), target.size())
	for index in limit:
		target[index] = array[index]
