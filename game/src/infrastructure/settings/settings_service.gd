class_name SettingsService
extends RefCounted

## Every switch the player may touch, in one place, persisted across restarts.
##
## The list is the specification's §114 list — nothing more.  A setting here is a
## record: a label for the screen, a kind that decides how it is edited, and a
## default that is also the value a fresh install gets.  Nothing outside this
## file is allowed to invent a key: the settings screen builds itself from
## `FIELDS`, so the screen and the storage can never drift apart.
##
## Setting a value *applies* it.  Volumes land on their audio bus, the UI scale
## lands on the window's content-scale factor, the camera switches are read by
## whoever drives the camera.  A change is therefore visible in the frame that
## follows it — no restart, no "apply" button, no apply dialog.

signal setting_changed(key: String, value: Variant)
signal settings_saved(path: String)

const SAVE_PATH := "user://settings.cfg"
const SECTION := "settings"

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_EFFECTS := "Effects"

const RESOLUTIONS := ["1280x720", "1366x768", "1600x900", "1920x1080", "2560x1440"]
const UI_SCALES := [1.0, 1.25, 1.5, 1.75, 2.0]

const KIND_VOLUME := "volume"
const KIND_OPTION := "option"
const KIND_TOGGLE := "toggle"
const KIND_RANGE := "range"

## `bus` marks a key that lands on an audio bus, `applies` marks a key whose
## change must reach the window or the scene tree the moment it is set.
const FIELDS: Array[Dictionary] = [
	{
		"key": "master_volume", "label": "Master volume", "kind": KIND_VOLUME,
		"default": 1.0, "min": 0.0, "max": 1.0, "step": 0.05, "bus": BUS_MASTER,
	},
	{
		"key": "music_volume", "label": "Music volume", "kind": KIND_VOLUME,
		"default": 0.8, "min": 0.0, "max": 1.0, "step": 0.05, "bus": BUS_MUSIC,
	},
	{
		"key": "effects_volume", "label": "Effects volume", "kind": KIND_VOLUME,
		"default": 0.9, "min": 0.0, "max": 1.0, "step": 0.05, "bus": BUS_EFFECTS,
	},
	{
		"key": "resolution", "label": "Resolution", "kind": KIND_OPTION,
		"default": "1920x1080", "options": RESOLUTIONS, "applies": true,
	},
	{
		"key": "fullscreen", "label": "Fullscreen", "kind": KIND_TOGGLE,
		"default": false, "applies": true,
	},
	{
		"key": "ui_scale", "label": "Interface scale", "kind": KIND_OPTION,
		"default": 1.0, "options": UI_SCALES, "applies": true,
	},
	{
		"key": "camera_pan_speed", "label": "Camera pan speed", "kind": KIND_RANGE,
		"default": 900.0, "min": 200.0, "max": 2400.0, "step": 50.0,
	},
	{
		"key": "camera_rotation_speed", "label": "Camera rotation speed",
		"kind": KIND_RANGE, "default": 0.42, "min": 0.1, "max": 1.2, "step": 0.05,
	},
	{
		"key": "zoom_speed", "label": "Zoom speed", "kind": KIND_RANGE,
		"default": 1.0, "min": 0.2, "max": 3.0, "step": 0.1,
	},
	{
		"key": "edge_scrolling", "label": "Edge scrolling", "kind": KIND_TOGGLE,
		"default": true,
	},
]

var _values := {}
## True once something has been changed since the file was last written.
var dirty := false


func _init() -> void:
	load_settings()


# --- the catalogue --------------------------------------------------------

static func field_keys() -> Array[String]:
	var keys: Array[String] = []
	for field in FIELDS:
		keys.append(String(field["key"]))
	return keys


## The record behind a key, or an empty dictionary for a key that does not exist.
static func field_for(key: String) -> Dictionary:
	for field in FIELDS:
		if String(field["key"]) == key:
			return field
	return {}


static func default_value(key: String) -> Variant:
	var field := field_for(key)
	return field.get("default", null) if not field.is_empty() else null


func label_for(key: String) -> String:
	return String(field_for(key).get("label", key))


func kind_of(key: String) -> String:
	return String(field_for(key).get("kind", ""))


func options_for(key: String) -> Array:
	return field_for(key).get("options", []) as Array


## How the screen shows the current value: a percent for volumes and scale, an
## unmistakable On/Off for a switch, the raw number otherwise.
func display_value(key: String) -> String:
	var field := field_for(key)
	if field.is_empty():
		return ""
	match String(field["kind"]):
		KIND_VOLUME:
			return "%d%%" % int(roundf(float(_values[key]) * 100.0))
		KIND_TOGGLE:
			return "On" if bool(_values[key]) else "Off"
		KIND_OPTION:
			if String(key) == "ui_scale":
				return "%d%%" % int(roundf(float(_values[key]) * 100.0))
			return String(_values[key]).replace("x", " × ")
	return _number_text(float(_values[key]))


static func _number_text(value: float) -> String:
	if absf(value - roundf(value)) < 0.0001:
		return str(int(roundf(value)))
	return "%.2f" % value


# --- reading and writing --------------------------------------------------

func has_key(key: String) -> bool:
	return _values.has(key)


func get_value(key: String) -> Variant:
	return _values.get(key, null)


func as_float(key: String) -> float:
	return float(_values.get(key, 0.0))


func as_int(key: String) -> int:
	return int(_values.get(key, 0))


func as_bool(key: String) -> bool:
	return bool(_values.get(key, false))


## Store a value, apply it, and announce it.  Returns false — and changes
## nothing — for a key the catalogue does not know, so a stale binding in an
## old panel cannot smuggle a setting into the save file.
## Returns false — and changes nothing — when the key is unknown or the value is
## not one the field can hold.  A range clamps, because a slider is allowed to
## overshoot; a choice list refuses, because "37x41" is not a resolution somebody
## overshot into.
func set_value(key: String, value: Variant) -> bool:
	var field := field_for(key)
	if field.is_empty():
		return false
	if String(field["kind"]) == KIND_OPTION and not _is_option(field, value):
		return false
	var coerced: Variant = _coerce(field, value)
	var previous: Variant = _values.get(key, null)
	_values[key] = coerced
	# Apply unconditionally: the store and the world must agree even when a
	# widget re-sends the value it already had.  Announce only a real change,
	# so a listener is never woken for nothing.
	_apply(key, field)
	if previous == null or not _same(previous, coerced):
		dirty = true
		setting_changed.emit(key, coerced)
	return true


## One edit-step along a key: one option to the next, one range step, a flip.
## This is what the +/- arrows and the slider do, so no widget has to know the
## kind of the thing it is nudging.
func nudge(key: String, direction: int = 1) -> Variant:
	var field := field_for(key)
	if field.is_empty():
		return null
	var current: Variant = _values[key]
	match String(field["kind"]):
		KIND_TOGGLE:
			set_value(key, not bool(current))
		KIND_OPTION:
			var options: Array = field["options"]
			var index := 0
			for i in options.size():
				if _same(options[i], current):
					index = i
			set_value(key, options[clampi(index + direction, 0, options.size() - 1)])
		_:
			var step := float(field.get("step", 0.05))
			set_value(key, float(current) + step * float(direction))
	return _values.get(key, null)


func reset_all() -> void:
	for field in FIELDS:
		set_value(String(field["key"]), field["default"])


# --- persistence ----------------------------------------------------------

func load_settings() -> void:
	_values.clear()
	for field in FIELDS:
		_values[String(field["key"])] = field["default"]
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		for field in FIELDS:
			var key := String(field["key"])
			if config.has_section_key(SECTION, key):
				_values[key] = _coerce(field, config.get_value(SECTION, key, field["default"]))
	dirty = false
	apply_all()


## Write the file the way every other file in this game is written: a temporary
## name, then the rename.  A crash mid-write leaves the last good file alone.
func save_settings() -> bool:
	var config := ConfigFile.new()
	for field in FIELDS:
		var key := String(field["key"])
		config.set_value(SECTION, key, _values.get(key, field["default"]))
	var temp := SAVE_PATH + ".tmp"
	if config.save(temp) != OK:
		return false
	var dir := DirAccess.open("user://")
	if dir == null:
		return false
	if dir.file_exists(SAVE_PATH):
		if dir.remove(SAVE_PATH) != OK:
			return false
	if dir.rename(temp, SAVE_PATH) != OK:
		return false
	dirty = false
	settings_saved.emit(SAVE_PATH)
	return true


func erase_settings() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists(SAVE_PATH):
		dir.remove(SAVE_PATH)


# --- applying -------------------------------------------------------------

## Push everything at the places it belongs.  Called on load and whenever the
## screen wants a clean sweep.
func apply_all() -> void:
	ensure_audio_buses()
	for field in FIELDS:
		_apply(String(field["key"]), field)


func _apply(key: String, field: Dictionary) -> void:
	match String(field["kind"]):
		KIND_VOLUME:
			_apply_volume(key, field)
		KIND_OPTION:
			if key == "ui_scale":
				_apply_ui_scale()
			elif key == "resolution":
				_apply_window()
		KIND_TOGGLE:
			if key == "fullscreen":
				_apply_window()


func _apply_volume(key: String, field: Dictionary) -> void:
	var bus := String(field.get("bus", ""))
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0002, float(_values[key]))))


## The three buses the spec names.  The shipped project starts with Master
## alone, so the other two are created on demand rather than being committed as
## a binary bus layout — the same "code builds the thing" rule the UI follows.
func ensure_audio_buses() -> void:
	for bus in [BUS_MUSIC, BUS_EFFECTS]:
		if AudioServer.get_bus_index(bus) >= 0:
			continue
		AudioServer.add_bus(AudioServer.get_bus_count())
		var index := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, BUS_MASTER)


func _apply_ui_scale() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	tree.root.content_scale_factor = maxf(0.1, float(_values["ui_scale"]))


func _apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		# Nothing to resize in a run with no window; the value is still stored and
		# a real run applies it on launch.
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var window := tree.root
	if bool(_values["fullscreen"]):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	var parts := String(_values["resolution"]).split("x")
	if parts.size() != 2:
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	window.size = Vector2i(int(parts[0]), int(parts[1]))


# --- validation -----------------------------------------------------------

func _is_option(field: Dictionary, value: Variant) -> bool:
	for option in (field["options"] as Array):
		if _same(option, value) or str(option) == str(value):
			return true
	return false


func _coerce(field: Dictionary, value: Variant) -> Variant:
	match String(field["kind"]):
		KIND_VOLUME, KIND_RANGE:
			return clampf(float(value), float(field["min"]), float(field["max"]))
		KIND_OPTION:
			var options: Array = field["options"]
			for option in options:
				if _same(option, value) or str(option) == str(value):
					return option
			return field["default"]
		KIND_TOGGLE:
			return bool(value)
	return value


func _same(left: Variant, right: Variant) -> bool:
	if typeof(left) == TYPE_FLOAT or typeof(right) == TYPE_FLOAT:
		return absf(float(left) - float(right)) < 0.0001
	return left == right
