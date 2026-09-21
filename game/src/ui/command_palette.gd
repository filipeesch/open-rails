class_name CommandPalette
extends PanelContainer

## Ctrl+K: type a few letters, hit Enter.
##
## Every entry is a real action on a real service — the palette is a shortcut to
## the same calls a button makes, never a parallel implementation of them.

signal command_invoked(id: String)

const HINT := "Search actions, towns, stations and trains…"

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
	session.station_created.connect(func(_id): _rebuild_actions())
	session.train_created.connect(func(_id): _rebuild_actions())
	session.towns.town_added.connect(func(_id): _rebuild_actions())
	session.industries.industry_added.connect(func(_id): _rebuild_actions())


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
	_add("rotate_left", "Rotate camera left (Q)", func(): camera_rig.snap_rotate(-1.0))
	_add("rotate_right", "Rotate camera right (E)", func(): camera_rig.snap_rotate(1.0))
	_add("zoom_in", "Zoom in", func(): camera_rig.zoom_in())
	_add("zoom_out", "Zoom out", func(): camera_rig.zoom_out())
	_add("undo", "Undo last construction (Ctrl+Z)", func(): session.undo.undo())
	_add("save", "Save the game", func(): session.save_to(session.save_path("quicksave")))
	_add("load", "Load the last autosave", func(): _load_latest())
	_add("trains", "Open the train list", func(): input.open_panel(InputController.PANEL_TRIPS))
	_add("company", "Open company finances", func(): input.open_panel(InputController.PANEL_COMPANY))
	_add("settings", "Open settings", func(): _open_settings())
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


## Reach the settings screen the same way the controller reaches this palette: by
## group name.  A shell that has no settings screen gets an honest notice instead
## of a silently dead command.
func _open_settings() -> void:
	if not is_inside_tree():
		return
	for candidate in get_tree().get_nodes_in_group("ui_settings_panel"):
		if candidate.has_method("open_panel"):
			candidate.open_panel()
			return
	session.notify("The settings screen is not available.", "bad")


func _focus(tile: Vector2) -> void:
	camera_rig.focus_tile(tile + Vector2(0.5, 0.5))
	selection.select_tile(Vector2i(tile))


func _load_latest() -> void:
	var directory := DirAccess.open(GameSession.SAVE_FOLDER)
	if directory == null:
		return
	var newest := ""
	var newest_stamp := ""
	for name in directory.get_files():
		if not name.begins_with("autosave_") or not name.ends_with(".json"):
			continue
		if name > newest:
			newest = name
			newest_stamp = name
	if newest == "":
		session.notify("No autosave found", "warning")
		return
	session.load_from(GameSession.SAVE_FOLDER.path_join(newest))
	session.notify("Loaded %s" % newest, "info")
