class_name CommandPalette
extends PanelContainer

## Ctrl+K: type a few letters, hit Enter.
##
## Every entry is a real action on a real service — the palette is a shortcut to
## the same calls a button makes, never a parallel implementation of them.

signal command_invoked(id: String)

const HINT := "Search actions, towns, stations and trains…"

## Which verb each command performs, in the engine's own vocabulary.  A command
## naming its key in words — "(Q)" — was a hint that could only drift, because the
## letter lived in a string while the binding lived in the InputMap; a binding moves
## and the sentence keeps promising the old key.  These commands therefore spell the
## key out of the InputMap through `KeyHints`, from the same action their `run`
## closure performs, so there is nothing left to drift from.
const COMMAND_KEYS := {
	"rotate_left": "cam_rotate_ccw",
	"rotate_right": "cam_rotate_cw",
	"undo": "undo",
	"settings": "settings_panel",
}

var session: GameSession
var input: InputController
var camera_rig: IsoCameraRig
var selection: SelectionService
var field: LineEdit
var list: ItemList
var _actions: Array[Dictionary] = []
var _filter := ""


func attach(game_session: GameSession, controller: InputController, rig: IsoCameraRig,
		sel: SelectionService) -> void:
	session = game_session
	input = controller
	camera_rig = rig
	selection = sel
	theme = GameTheme.build()
	add_theme_stylebox_override("panel", GameTheme.panel(GameTheme.BACKGROUND))
	custom_minimum_size = Vector2(420, 260)
	# Centred in the modal band, which is transparent to the mouse so the world
	# stays live behind the palette.
	set_anchors_preset(Control.PRESET_CENTER)
	visible = false
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var column := VBoxContainer.new()
	add_child(column)
	field = LineEdit.new()
	field.placeholder_text = HINT
	field.add_theme_font_size_override("font_size", GameTheme.FONT_STRONG)
	column.add_child(field)
	list = ItemList.new()
	list.custom_minimum_size = Vector2(420, 200)
	column.add_child(list)
	field.text_changed.connect(_on_filter)
	field.text_submitted.connect(func(_text): _activate())
	list.item_activated.connect(func(index): _activate(index))
	add_to_group("modal")
	# Ctrl+K arrives through `InputController`, which finds the palette by group
	# rather than holding a reference to the shell that built it.
	add_to_group("ui_command_palette")
	_rebuild_actions()
	# A command that names a thing the valley no longer holds is a lie with a key
	# attached: "Focus station: Marlow" would carry the camera to wherever that
	# yard's tiles used to be.  So the list is rebuilt on the ways the world stops
	# holding it, not only on the ways it gains something — and on a load, which
	# replaces every entity in the world at once.
	session.station_created.connect(func(_id): _rebuild_actions())
	session.station_removed.connect(func(_id): _rebuild_actions())
	session.station_renamed.connect(func(_id, _name): _rebuild_actions())
	session.train_created.connect(func(_id): _rebuild_actions())
	session.train_removed.connect(func(_id): _rebuild_actions())
	session.towns.town_added.connect(func(_id): _rebuild_actions())
	session.industries.industry_added.connect(func(_id): _rebuild_actions())
	session.session_loaded.connect(_rebuild_actions)


func configure(game_session: GameSession, controller: InputController, rig: IsoCameraRig,
		sel: SelectionService) -> void:
	attach(game_session, controller, rig, sel)


func open_palette() -> void:
	visible = true
	field.grab_focus()
	field.text = ""
	_on_filter("")


func close_palette() -> void:
	visible = false


func is_open() -> bool:
	return visible


func entries() -> PackedStringArray:
	var out := PackedStringArray()
	for action in _visible_actions():
		out.append(String(action["label"]))
	return out


func activate_entry(index: int) -> void:
	_activate(index)


func _on_filter(text: String) -> void:
	_filter = text.to_lower()
	list.clear()
	for action in _visible_actions():
		list.add_item(String(action["label"]))
	# The best match is selected as the filter lands, so Enter means what it means
	# in every command palette there is: take the top of the list.  Until now the
	# first Enter did nothing at all unless the player had thought to click a row,
	# which the palette's own description of itself promises they will not do.
	if list.item_count > 0:
		list.select(0)


func _visible_actions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for action in _actions:
		if _filter == "" or String(action["label"]).to_lower().contains(_filter):
			out.append(action)
	return out


func _activate(index: int = -1) -> void:
	var visible_actions := _visible_actions()
	var target := list.get_selected_items()[0] if index < 0 and not list.get_selected_items().is_empty() else index
	if target < 0 or target >= visible_actions.size():
		# Refused in words.  A key that is silent is indistinguishable from a key
		# that was never bound, and the player has no way to tell which happened.
		if session != null:
			session.notify("Nothing in the valley answers to \"%s\"." % field.text
					if _filter != "" else "Nothing to choose yet.", "info")
		return
	var action: Dictionary = visible_actions[target]
	close_palette()
	command_invoked.emit(String(action["id"]))
	action["run"].call()


func _rebuild_actions() -> void:
	_actions = []
	_add("tool_rail", "Lay rail", func(): input.arm_tool(InputController.TOOL_RAIL))
	_add("tool_station", "Place station", func(): input.arm_tool(InputController.TOOL_STATION))
	_add("cancel", "Cancel current tool", func(): input.cancel())
	_add("pause", "Pause simulation", func(): session.clock.set_speed_index(0))
	_add("speed_1", "Run at 1×", func(): session.clock.set_speed_index(1))
	_add("speed_2", "Run at 2×", func(): session.clock.set_speed_index(2))
	_add("speed_4", "Run at 4×", func(): session.clock.set_speed_index(3))
	_add("reset_view", "Reset camera to isometric view", func(): camera_rig.reset_view())
	_add("rotate_left", "Rotate camera left" + KeyHints.hint_suffix(COMMAND_KEYS["rotate_left"]),
			func(): camera_rig.snap_rotate(-1.0))
	_add("rotate_right", "Rotate camera right" + KeyHints.hint_suffix(COMMAND_KEYS["rotate_right"]),
			func(): camera_rig.snap_rotate(1.0))
	_add("zoom_in", "Zoom in", func(): camera_rig.zoom_in())
	_add("zoom_out", "Zoom out", func(): camera_rig.zoom_out())
	_add("undo", "Undo last construction" + KeyHints.hint_suffix(COMMAND_KEYS["undo"]),
			func(): session.undo.undo())
	_add("save", "Save the game", func(): _save_quicksave())
	_add("load", "Load the last autosave", func(): _load_latest())
	_add("trains", "Open the train list", func(): input.open_panel(InputController.PANEL_TRIPS))
	_add("company", "Open company finances", func(): input.open_panel(InputController.PANEL_COMPANY))
	_add("settings", "Open settings" + KeyHints.hint_suffix(COMMAND_KEYS["settings"]),
			func(): _open_settings())
	for town_id in session.towns.towns():
		_add("focus_town_%d" % town_id, "Focus town: %s" % session.towns.name_of(town_id),
			func(): _focus(session.towns.tile_of(town_id)))
	for industry_id in session.industries.industries():
		_add("focus_industry_%d" % industry_id, "Focus industry: %s" % session.industries.name_of(industry_id),
			func(): _focus(session.industries.tile_of(industry_id)))
	for station_id in session.stations.stations():
		_add("focus_station_%d" % station_id, "Focus station: %s" % session.stations.name_of(station_id),
			func(): _focus(session.stations.tile_of(station_id)))
	for train_id in session.trains.trains():
		var captured := train_id
		_add("follow_%d" % train_id, "Follow train: %s" % session.trains.name_of(captured),
			func(): camera_rig.follow_train(captured, Callable(session.trains, "position_tiles")))


func _add(id: String, label: String, action: Callable) -> void:
	_actions.append({"id": id, "label": label, "run": action})


## The options screen has one door — `InputController.open_settings`, which the `O`
## key answers to as well — so the palette cannot open a screen the keyboard thinks
## is absent.  A shell with no settings screen gets an honest notice instead of a
## silently dead command.
func _open_settings() -> void:
	if input != null and input.open_settings():
		return
	session.notify("The settings screen is not available.", "bad")


func _focus(tile: Vector2) -> void:
	camera_rig.focus_tile(tile + Vector2(0.5, 0.5))
	selection.select_tile(Vector2i(tile))


## The same verdict rule as loading, on the way out: a save that could not be
## written says so, because a player who believes the valley is on disk and finds
## it is not has lost more than the one who was told.
func _save_quicksave() -> void:
	var path := session.save_path("quicksave")
	var result := session.save_to(path)
	if not bool(result.get("ok", false)):
		session.notify(String(result.get("reason", "Could not write the save.")), "bad")
		return
	session.notify("Saved to %s" % path.get_file(), "info")


## Ask the save service which autosave is the newest, rather than scanning the
## folder for a second time here: retention and the padded-date naming are the
## service's rules, and a duplicate scan is free to disagree with them.  And say
## what actually happened — `load_from` answers with a verdict, and a command that
## reports "Loaded" whatever that verdict says is a button that lies about working.
func _load_latest() -> void:
	var path := session.saves.latest_autosave()
	if path == "":
		session.notify("No autosave found", "warning")
		return
	var result := session.load_from(path)
	if not bool(result.get("ok", false)):
		session.notify(String(result.get("reason", "That save could not be read.")), "bad")
		return
	session.notify("Loaded %s" % path.get_file(), "info")
