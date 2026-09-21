class_name RouteEditor
extends PanelContainer

## The route page of the trains drawer: stops in order, and per stop what to
## pick up and what to deliver.
##
## Every structural edit is committed through `TrainService.set_route` the
## moment it happens, so the length and validity shown here are always the
## domain's own answer — never a UI-side guess.  A refusal is reported (a
## notification plus the reason on the panel) and the last working timetable
## stays in place, which is exactly what `RouteService` guarantees.
##
## New stops may only come from `RouteService.reachable_stations`, either by
## clicking a station in the world (stop-pick mode) or from the drawer's list.

signal close_requested()

var session: GameSession
var controller: InputController
var camera_rig: IsoCameraRig
var train_id := 0

var _title: Label
var _status: Label
var _reason: Label
var _pick_hint: Label
var _stops_box: VBoxContainer
var _reachable_box: VBoxContainer
var _pick_button: Button
var _clear_button: Button
var _reachable_key := ""

var _pending: Array[Dictionary] = []
var _refusal := ""
var _stop_rows: Array[Dictionary] = []
var _picking := false
var _dirty := true
var _syncing := false


func _ready() -> void:
	add_theme_stylebox_override("panel", GameTheme.panel(GameTheme.BACKGROUND))
	_build()


func attach(game_session: GameSession, input: InputController, rig: IsoCameraRig) -> void:
	session = game_session
	controller = input
	camera_rig = rig
	# Entity signals come off the session façade; route bookkeeping is only
	# emitted by `RouteService`, so that one is subscribed at service level.
	session.station_created.connect(_on_entity_changed)
	session.station_removed.connect(_on_entity_changed)
	session.station_renamed.connect(func(_id: int, _name: String) -> void: mark_dirty())
	session.station_inventory_changed.connect(_on_entity_changed)
	session.train_route_changed.connect(func(_id: int, _route: int) -> void: mark_dirty())
	session.train_removed.connect(_on_train_removed)
	session.routes.route_changed.connect(_on_entity_changed)
	session.routes.route_removed.connect(_on_entity_changed)
	session.routes.route_path_invalid.connect(_on_route_invalid)
	if controller != null:
		controller.station_picked.connect(_on_station_picked)
		controller.tool_changed.connect(_on_tool_changed)
	_dirty = true


# --- page control ----------------------------------------------------------

func edit(id: int) -> void:
	train_id = id
	_pending = []
	_refusal = ""
	_reachable_key = ""
	_dirty = true


func stop_edit() -> void:
	train_id = 0
	_pending = []
	_refusal = ""
	_reachable_key = ""
	_stop_rows.clear()


func is_editing() -> bool:
	return train_id != 0


func mark_dirty() -> void:
	_dirty = true


func _on_entity_changed(_argument: Variant = null) -> void:
	_dirty = true


func _on_train_removed(id: int) -> void:
	if id == train_id:
		stop_edit()
		close_requested.emit()
	_dirty = true


func _on_route_invalid(route_id: int, _reason: String) -> void:
	if route_id == session.routes.route_for_train(train_id):
		_dirty = true


func _on_tool_changed(tool: String) -> void:
	_picking = tool == InputController.TOOL_STOP_PICK
	_dirty = true


func _on_station_picked(station_id: int) -> void:
	add_station(station_id)


## Entry point for both picking paths: the map click and the drawer's list.
func add_station(station_id: int) -> void:
	if session == null or train_id == 0 or station_id <= 0:
		return
	var stops := _draft_stops()
	for stop in stops:
		if int(stop["station_id"]) == station_id:
			_refuse("That station is already a stop on this route")
			return
	stops.append(_blank_stop(station_id))
	_commit(stops, true)


## Toggle a cargo on a stop.  The domain revalidates the whole route, so an
## order that makes the timetable unhoppable is refused rather than saved.
func _set_plan(stop_index: int, key: String, cargo_id: String, wanted: bool) -> void:
	var stops := _draft_stops()
	if stop_index < 0 or stop_index >= stops.size():
		return
	var plan := _string_array(stops[stop_index].get(key, []))
	if wanted and not plan.has(cargo_id):
		plan.append(cargo_id)
	elif not wanted:
		plan.erase(cargo_id)
	stops[stop_index][key] = plan
	_commit(stops, false)


func _move_stop(index: int, offset: int) -> void:
	var stops := _draft_stops()
	var target := index + offset
	if target < 0 or target >= stops.size():
		return
	var moved: Dictionary = stops[index]
	stops.remove_at(index)
	stops.insert(target, moved)
	_commit(stops, true)


func _remove_stop(index: int) -> void:
	var stops := _draft_stops()
	if index < 0 or index >= stops.size():
		return
	stops.remove_at(index)
	_commit(stops, true)


func _clear_route() -> void:
	if session == null or train_id == 0:
		return
	session.trains.clear_route(train_id)
	_pending = []
	_refusal = ""
	_dirty = true
	session.notify("Route cleared", "info")


# --- commit ----------------------------------------------------------------

func _commit(stops: Array[Dictionary], announce: bool) -> void:
	if stops.size() < 2:
		# Below two stops there is no route to create yet, so the picks are held
		# here and said out loud instead of asking the domain to refuse every
		# click on the way to a legal timetable.
		_pending = stops
		_refusal = ""
		_dirty = true
		return
	var result := session.trains.set_route(train_id, stops)
	if bool(result.get("ok", false)):
		_pending = []
		_refusal = ""
		if announce:
			session.notify("Route set — %s" % _caption(stops), "good")
	else:
		_refusal = String(result.get("reason", ""))
		if _refusal == "":
			_refusal = "That route was refused"
		session.notify(_refusal, "bad")
	_dirty = true


func _refuse(reason: String) -> void:
	_refusal = reason
	session.notify(reason, "bad")
	_dirty = true


## A route read back from a save is a plain Array; every consumer here wants
## `Array[String]`, so the conversion happens once, at this boundary.
func _string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return out
	for item in value:
		out.append(String(item))
	return out


func _blank_stop(station_id: int) -> Dictionary:
	var load: Array[String] = []
	var unload: Array[String] = []
	return {"station_id": station_id, "load": load, "unload": unload}


## The stops being worked on: the committed route where one exists, otherwise
## the picks waiting for a second stop.  Always a deep copy — a widget must
## never be handed the route's own dictionaries.
func _draft_stops() -> Array[Dictionary]:
	var route_id := _route_id()
	if route_id == 0:
		return _copy(_pending)
	return _copy(Array(session.routes.stops(route_id)))


func _copy(source: Array) -> Array[Dictionary]:
	var copies: Array[Dictionary] = []
	for stop in source:
		copies.append({
			"station_id": int(stop["station_id"]),
			"load": Array(stop.get("load", [])),
			"unload": Array(stop.get("unload", [])),
		})
	return copies


func _route_id() -> int:
	if session == null or train_id == 0:
		return 0
	return session.routes.route_for_train(train_id)


func _caption(stops: Array[Dictionary]) -> String:
	var names: Array[String] = []
	for stop in stops:
		names.append(session.stations.name_of(int(stop["station_id"])))
	return " → ".join(names)


# --- painting --------------------------------------------------------------

## Called by the drawer's throttled refresh; does nothing unless a signal said
## something changed.
func refresh() -> void:
	if not _dirty or session == null:
		return
	_dirty = false
	if train_id == 0 or session.trains.train(train_id).is_empty():
		return
	_title.text = "Route · %s" % session.trains.name_of(train_id)
	_status.text = _status_text()
	_status.add_theme_color_override("font_color", _status_colour())
	_reason.text = _refusal
	_reason.visible = _refusal != ""
	_pick_hint.visible = _picking
	_pick_button.text = "Stop pick: click a station" if _picking else "Add stop on map"
	_clear_button.disabled = _route_id() == 0
	_paint_stops()
	_paint_reachable()


func _status_text() -> String:
	var route_id := _route_id()
	if route_id == 0:
		if not _pending.is_empty():
			return "One stop picked — pick a second to open the route."
		return "No route yet — pick two stations to open one."
	if session.routes.is_valid(route_id):
		return "%d stops · %.1f tiles round trip" % [
			session.routes.stop_count(route_id), session.routes.length_tiles(route_id)]
	return "Invalid route: %s" % session.routes.invalid_reason(route_id)


func _status_colour() -> Color:
	var route_id := _route_id()
	if route_id == 0:
		return GameTheme.TEXT_DIM
	return GameTheme.GOOD if session.routes.is_valid(route_id) else GameTheme.DANGER


func _paint_stops() -> void:
	var stops := _draft_stops()
	while _stop_rows.size() > stops.size():
		var extra: Dictionary = _stop_rows.pop_back()
		extra["panel"].queue_free()
	while _stop_rows.size() < stops.size():
		var row := _make_stop_row()
		_stop_rows.append(row)
		_stops_box.add_child(row["panel"])
	var route_id := _route_id()
	for index in stops.size():
		_paint_stop(index, stops[index], route_id)


func _paint_stop(index: int, stop: Dictionary, route_id: int) -> void:
	var row: Dictionary = _stop_rows[index]
	var panel: PanelContainer = row["panel"]
	panel.set_meta(&"stop_index", index)
	row["index"].text = "%d" % (index + 1)
	row["name"].text = session.stations.name_of(int(stop["station_id"]))
	panel.self_modulate = Color(1, 1, 1, 1.0) if route_id != 0 else Color(1, 1, 1, 0.8)
	(row["up"] as Button).disabled = index == 0
	(row["down"] as Button).disabled = index == _stop_rows.size() - 1
	_paint_chips(row, "load", route_id, index, stop)
	_paint_chips(row, "unload", route_id, index, stop)


## Chips are rebuilt only when the *set* of offered cargos changes; a delivery
## or a fresh pile only rewrites the amount on the chip already there.
func _paint_chips(row: Dictionary, key: String, route_id: int, index: int, stop: Dictionary) -> void:
	var box: HBoxContainer = row[key + "_box"]
	var chips: Dictionary = row[key + "_chips"]
	var options: Array[Dictionary] = []
	if route_id != 0:
		options = session.routes.load_options(route_id, index) if key == "load" \
				else session.routes.unload_options(route_id, index)
	var plan: Array = Array(stop.get(key, []))
	var signature := ""
	for option in options:
		signature += String(option["cargo"]) + "|"
	if signature != String(row[key + "_key"]):
		for child in box.get_children():
			child.queue_free()
		chips = {}
		for option in options:
			var cargo_id := String(option["cargo"])
			var chip := _make_chip(cargo_id, key, index)
			box.add_child(chip)
			chips[cargo_id] = chip
		row[key + "_chips"] = chips
		row[key + "_key"] = signature
	for option in options:
		var cargo_id := String(option["cargo"])
		var chip: CheckBox = chips.get(cargo_id, null)
		if chip == null:
			continue
		chip.set_meta(&"stop_index", index)
		var label := session.data.cargo_display(cargo_id)
		if key == "load":
			label += " · %d waiting" % int(roundf(float(option.get("available", 0.0))))
		_syncing = true
		chip.set_pressed_no_signal(plan.has(cargo_id))
		_syncing = false
		chip.text = label
	row[key + "_empty"].visible = options.is_empty()


func _make_chip(cargo_id: String, key: String, index: int) -> CheckBox:
	var chip := CheckBox.new()
	chip.add_theme_font_size_override("font_size", GameTheme.FONT_SMALL)
	chip.tooltip_text = "Cargos waiting here to load" if key == "load" \
			else "Cargos a buyer here can take"
	chip.set_meta(&"stop_index", index)
	chip.toggled.connect(func(pressed: bool) -> void:
		if _syncing:
			return
		_set_plan(int(chip.get_meta(&"stop_index", -1)), key, cargo_id, pressed))
	return chip


func _make_stop_row() -> Dictionary:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", GameTheme.row(false))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	column.add_child(head)
	var index_label := Label.new()
	index_label.add_theme_font_size_override("font_size", GameTheme.FONT_SMALL)
	index_label.add_theme_color_override("font_color", GameTheme.ACCENT)
	head.add_child(index_label)
	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", GameTheme.FONT_BODY)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	head.add_child(name_label)
	var row := {"panel": panel, "index": index_label, "name": name_label}
	row["up"] = _stop_button("↑", "Move this stop earlier",
			func() -> void: _move_stop(int(panel.get_meta(&"stop_index", 0)), -1))
	row["down"] = _stop_button("↓", "Move this stop later",
			func() -> void: _move_stop(int(panel.get_meta(&"stop_index", 0)), 1))
	row["remove"] = _stop_button("✕", "Remove this stop",
			func() -> void: _remove_stop(int(panel.get_meta(&"stop_index", 0))))
	head.add_child(row["up"])
	head.add_child(row["down"])
	head.add_child(row["remove"])
	_plan_section(column, row, "load", "Picks up", "Nothing waiting here yet")
	_plan_section(column, row, "unload", "Delivers to", "No buyer here for this")
	return row


## Heading, chip row, and a designed empty state — stored on the stop row.
func _plan_section(column: VBoxContainer, row: Dictionary, key: String,
		title: String, empty_text: String) -> void:
	column.add_child(GameTheme.small(title, GameTheme.TEXT_DIM))
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	column.add_child(box)
	var placeholder := GameTheme.small(empty_text, GameTheme.TEXT_DIM)
	column.add_child(placeholder)
	row[key + "_box"] = box
	row[key + "_empty"] = placeholder
	row[key + "_chips"] = {}
	row[key + "_key"] = ""


func _stop_button(text: String, tooltip: String, handler: Callable) -> Button:
	var button := GameTheme.button_for(text, tooltip)
	button.custom_minimum_size = Vector2(26, 0)
	button.pressed.connect(handler)
	return button


func _paint_reachable() -> void:
	var used := {}
	for stop in _draft_stops():
		used[int(stop["station_id"])] = true
	var candidates: Array[int] = []
	for station_id in session.routes.reachable_stations(_route_id()):
		if not used.has(station_id):
			candidates.append(station_id)
	var signature := ""
	for station_id in candidates:
		signature += "%d," % station_id
	if signature == _reachable_key:
		return
	_reachable_key = signature
	for child in _reachable_box.get_children():
		child.queue_free()
	if candidates.is_empty():
		_reachable_box.add_child(GameTheme.paragraph(
			"No other station is on this line — lay rail and build one first.",
			GameTheme.TEXT_DIM, 320.0))
		return
	for station_id in candidates:
		_reachable_box.add_child(_station_row(station_id))


func _station_row(station_id: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var add := GameTheme.button_for("＋  %s" % session.stations.name_of(station_id),
			"Add this station as a stop")
	add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add.alignment = HORIZONTAL_ALIGNMENT_LEFT
	add.pressed.connect(func() -> void: add_station(station_id))
	row.add_child(add)
	var show := GameTheme.button_for("⌖", "Look at this station")
	show.custom_minimum_size = Vector2(30, 0)
	show.pressed.connect(func() -> void: _focus_station(station_id))
	row.add_child(show)
	return row


func _focus_station(station_id: int) -> void:
	if camera_rig == null:
		return
	var tile := Vector2(session.stations.tile_of(station_id)) + Vector2(0.5, 0.5)
	camera_rig.stop_following()
	camera_rig.focus_tile(tile)


func _on_pick_pressed() -> void:
	if controller == null:
		return
	if _picking:
		controller.cancel()
		return
	controller.arm_tool(InputController.TOOL_STOP_PICK)


# --- static layout ---------------------------------------------------------

func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", GameTheme.GAP)
	add_child(column)

	var head := HBoxContainer.new()
	column.add_child(head)
	_title = GameTheme.heading("Route")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	head.add_child(_title)
	var close := GameTheme.button_for("✕", "Close the route editor")
	close.pressed.connect(func() -> void: close_requested.emit())
	head.add_child(close)

	_status = GameTheme.paragraph("", GameTheme.TEXT_DIM, 320.0)
	column.add_child(_status)
	_reason = GameTheme.paragraph("", GameTheme.DANGER, 320.0)
	_reason.visible = false
	column.add_child(_reason)

	var actions := HBoxContainer.new()
	column.add_child(actions)
	_pick_button = GameTheme.button_for("Add stop on map",
			"Click a reachable station in the world (Esc cancels)")
	_pick_button.pressed.connect(_on_pick_pressed)
	actions.add_child(_pick_button)
	_clear_button = GameTheme.button_for("Clear route", "Remove this train's route")
	_clear_button.pressed.connect(_clear_route)
	actions.add_child(_clear_button)

	_pick_hint = GameTheme.paragraph("Pick mode: click a station in the world, or press Esc.",
		GameTheme.WARNING, 320.0)
	_pick_hint.visible = false
	column.add_child(_pick_hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)
	_stops_box = VBoxContainer.new()
	_stops_box.add_theme_constant_override("separation", 6)
	body.add_child(_stops_box)
	body.add_child(GameTheme.small("Stops reachable from this line:", GameTheme.TEXT_DIM))
	_reachable_box = VBoxContainer.new()
	_reachable_box.add_theme_constant_override("separation", 4)
	body.add_child(_reachable_box)
