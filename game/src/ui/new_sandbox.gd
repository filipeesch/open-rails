class_name NewSandbox
extends Control

## The New Sandbox screen: one map, one name, one year.
##
## V1 ships a single hand-authored valley, so this screen is not a level select —
## it is the moment the player says who they are.  The map row is generated from
## what is installed rather than typed into code, so a second map appearing in
## `data/maps/` shows up here by itself; and the year is read from the timing
## data, so the screen cannot promise a year the clock will not keep.
##
## Leaving the name field empty is a valid answer.  The valley has a name worth
## borrowing, and a player who does not want to think yet gets a company that is
## still called something on the top bar.

signal start_requested(request: Dictionary)
signal cancelled()

var registry: DataRegistry

var _maps: Array[String] = []
var _selected_map := 0
var _name_field: LineEdit
var _year_label: Label
var _map_list: VBoxContainer
var _error: Label
var _rows := {}


func attach(service: DataRegistry) -> void:
	registry = service
	_maps = registry.installed_maps()
	_selected_map = 0 if _maps.is_empty() else _index_of("founders_valley")
	_build()
	_refresh()


func configure(service: DataRegistry) -> void:
	attach(service)


func _init() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(420.0, 0.0)


# --- what the player sees -------------------------------------------------

func map_ids() -> Array[String]:
	return _maps


func selected_map() -> String:
	if _maps.is_empty():
		return SandboxIntent.DEFAULT_MAP
	return _maps[_selected_map]


func choose_map(map_id: String) -> bool:
	var index := _index_of(map_id)
	if index < 0:
		return false
	_selected_map = index
	_refresh()
	return true


func set_company_name(text: String) -> void:
	if _name_field != null:
		_name_field.text = text


func company_name_field() -> LineEdit:
	return _name_field


## The name to found the company with: what was typed, or the valley's own name
## when the field was left alone.  Never blank — a company called "" is a bug
## wearing a feature.
func company_name_or_default() -> String:
	var typed := _name_field.text.strip_edges() if _name_field != null else ""
	if typed != "":
		return typed
	return generated_company_name()


func generated_company_name() -> String:
	var summary := _summary()
	var place := String(summary.get("display_name", ""))
	if place == "":
		place = selected_map().replace("_", " ")
	return "%s Railway" % place


func start_year() -> int:
	return registry.start_year() if registry != null else SandboxIntent.DEFAULT_START_YEAR


## Everything the player decided, in the shape the arriving session reads.
func request() -> Dictionary:
	return {
		"map": selected_map(),
		"company_name": company_name_or_default(),
		"start_year": start_year(),
	}


## Found the company.  Returns the request even without a window, so the decision
## can be checked; the scene swap only happens when there is a scene to swap.
func start_sandbox() -> Dictionary:
	if _maps.is_empty():
		_error.text = "No map is installed, so there is no valley to open."
		return {}
	var chosen := request()
	SandboxIntent.write(String(chosen["map"]), String(chosen["company_name"]))
	_error.text = ""
	start_requested.emit(chosen)
	if not is_inside_tree():
		return chosen
	var tree := get_tree()
	if tree != null and tree.root != null:
		var packed := load(GAME_SCENE) as PackedScene
		if packed != null:
			tree.root.add_child.call_deferred(packed.instantiate())
			queue_free()
	return chosen


func press_cancel() -> void:
	cancelled.emit()
	if is_inside_tree():
		hide()


const GAME_SCENE := "res://scenes/Game.tscn"


func _index_of(map_id: String) -> int:
	for index in _maps.size():
		if _maps[index] == map_id:
			return index
	return -1


func _summary() -> Dictionary:
	if registry == null:
		return {}
	return registry.map_summary(selected_map())


# --- building -------------------------------------------------------------

func _build() -> void:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", GameTheme.panel(GameTheme.PANEL))
	add_child(panel)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.custom_minimum_size = Vector2(400.0, 0.0)
	column.add_theme_constant_override("separation", GameTheme.GAP)
	panel.add_child(column)

	column.add_child(GameTheme.heading("A New Sandbox"))
	column.add_child(GameTheme.small("Found a railway and see what the valley does with it."))

	var map_heading := GameTheme.small("Valley", GameTheme.TEXT_DIM)
	column.add_child(map_heading)
	_map_list = VBoxContainer.new()
	_map_list.name = "Maps"
	_map_list.add_theme_constant_override("separation", 2)
	column.add_child(_map_list)

	var name_row := GameTheme.labelled("Company", "")
	column.add_child(name_row)
	_name_field = LineEdit.new()
	_name_field.name = "CompanyName"
	_name_field.placeholder_text = "Name your company"
	_name_field.tooltip_text = "Leave it empty and the valley names the company for you."
	_name_field.text_submitted.connect(func(_text: String) -> void:
		start_sandbox())
	column.add_child(_name_field)

	_year_label = GameTheme.small("")
	_year_label.name = "StartYear"
	column.add_child(_year_label)

	_error = GameTheme.small("", GameTheme.DANGER)
	_error.name = "Error"
	column.add_child(_error)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", GameTheme.GAP)
	column.add_child(footer)
	var start := GameTheme.button_for("Found the company", "Open the valley and start running.")
	start.name = "Start"
	start.pressed.connect(start_sandbox)
	footer.add_child(start)
	# A plain button: "Back" is a verb. The map rows below are `toggle_mode`
	# because they hold a choice; this one holds nothing, and a toggle left lit
	# after the click claims a selection that was never made.
	var back := GameTheme.button_for("Back", "Return to the main menu.")
	back.name = "Back"
	back.pressed.connect(press_cancel)
	footer.add_child(back)


func _build_map_rows() -> void:
	for child in _map_list.get_children():
		child.free()
	_rows.clear()
	for index in _maps.size():
		var map_id := _maps[index]
		var label := _row_label(map_id)
		var choice := GameTheme.toggle(label, "Run in %s." % label)
		choice.name = "Map_" + map_id
		choice.toggle_mode = true
		choice.button_pressed = index == _selected_map
		choice.pressed.connect(func() -> void:
			choose_map(map_id))
		_map_list.add_child(choice)
		_rows[map_id] = choice


## Choosing a map is a change of state, not a change of furniture.  The rows are
## built once and then only told which one is lit: rebuilding them from inside a
## row's own press would free the button that is still emitting, which the engine
## refuses — and a row that refuses to update is a row that looks unclickable.
func _refresh() -> void:
	if _map_list == null:
		return
	if _rows.is_empty() and not _maps.is_empty():
		_build_map_rows()
	else:
		for map_id in _rows:
			var choice := _rows[map_id] as Button
			choice.button_pressed = not _maps.is_empty() and _maps[_selected_map] == map_id
	_name_field.placeholder_text = generated_company_name()
	_year_label.text = "The valley opens in %d." % start_year()


func _row_label(map_id: String) -> String:
	var summary := registry.map_summary(map_id) if registry != null else {}
	return "%s — %d × %d" % [String(summary.get("display_name", map_id)),
		int(summary.get("width", 0)), int(summary.get("height", 0))]


## The row that picks a map, so a test can press it the way a player does.
func map_button(map_id: String) -> Button:
	return _rows.get(map_id, null) as Button
