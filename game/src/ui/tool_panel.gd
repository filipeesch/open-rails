class_name ToolPanel
extends PanelContainer

## The left-hand tool drawer.  It exists only while a tool is armed, and it says
## the one thing the ghost cannot: why an action is blocked and what it costs.

var session: GameSession
var input: InputController
var title_label: Label
var detail_label: Label
var cost_label: Label
var hint_label: Label
var action_button: Button
var _tiles: Array[Vector2i] = []
var _state := "none"
var _reason := ""
var _cost := 0.0


func attach(game_session: GameSession, controller: InputController) -> void:
	session = game_session
	input = controller
	theme = GameTheme.build()
	add_theme_stylebox_override("panel", GameTheme.panel(GameTheme.BACKGROUND))
	custom_minimum_size = Vector2(248, 0)
	# The band hosts one drawer at a time and this panel is only as tall as its
	# text, so it hugs the top of the band instead of stretching down it.
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	visible = false

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	title_label = GameTheme.heading("Tool")
	column.add_child(title_label)

	detail_label = GameTheme.body("", GameTheme.TEXT_DIM)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.custom_minimum_size = Vector2(230, 0)
	column.add_child(detail_label)

	cost_label = GameTheme.body("")
	cost_label.add_theme_font_size_override("font_size", GameTheme.FONT_STRONG)
	column.add_child(cost_label)

	hint_label = GameTheme.body("")
	hint_label.add_theme_color_override("font_color", GameTheme.TEXT_DIM)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint_label)

	action_button = GameTheme.button_for("Cancel", "Esc")
	action_button.pressed.connect(func(): input.cancel())
	column.add_child(action_button)

	controller.tool_changed.connect(_on_tool)
	controller.ghost_changed.connect(_on_ghost)
	session.economy.insufficient_funds.connect(_on_insufficient)


func configure(game_session: GameSession, controller: InputController) -> void:
	attach(game_session, controller)


func _on_tool(tool: String) -> void:
	_state = "none"
	_tiles = []
	visible = tool != InputController.TOOL_NONE
	# Stop-picking belongs to the trains drawer, which explains it where the
	# player is already looking; two panels in this band would fight.
	if tool == InputController.TOOL_STOP_PICK:
		visible = false
		return
	if not visible:
		return
	match tool:
		InputController.TOOL_RAIL:
			title_label.text = "Lay rail"
			# What the planner actually charges (`rail_planner._finalise`): the tile
			# rate — a curve runs on the dearer diagonal rate — plus the slope and
			# ground surcharges.  Nothing else is charged, so the panel names nothing
			# else: the price shown is the price paid, to the cent.
			detail_label.text = "Click a start tile, then an end tile.  The planned line is shown on the terrain; the price covers the tile rate, gradients and ground surcharges."
			hint_label.text = "Straight is cheapest.  One height step per tile is the limit.  Shift-click lays a single tile."
		InputController.TOOL_STATION:
			title_label.text = "Place station"
			detail_label.text = "A station needs straight rail within reach and undeveloped ground.  Green means legal."
			hint_label.text = "Sources inside the catchment are listed below."
	_update()


func _on_ghost(tiles: Array[Vector2i], state: String, reason: String, cost: float) -> void:
	_tiles = tiles
	_state = state
	_reason = reason
	_cost = cost
	_update()


func _on_insufficient(cost: float, _cash: float, label: String) -> void:
	_state = "invalid"
	_reason = "Not enough cash for %s (%s needed)" % [label, GameTheme.money(cost)]
	_update()


func state() -> String:
	return _state


func cost() -> float:
	return _cost


func _update() -> void:
	if not visible:
		return
	match _state:
		"none":
			cost_label.text = ""
			cost_label.add_theme_color_override("font_color", GameTheme.TEXT)
			detail_label.modulate = Color.WHITE
		"ok":
			cost_label.text = "%s  ·  %d tiles" % [GameTheme.money(_cost), _tiles.size()] \
				if _cost > 0.0 else "Ready"
			cost_label.add_theme_color_override("font_color", GameTheme.GOOD)
			action_button.text = "Click to build"
		"expensive":
			cost_label.text = "%s  ·  long route" % GameTheme.money(_cost)
			cost_label.add_theme_color_override("font_color", GameTheme.WARNING)
			action_button.text = "Click to build anyway"
		"invalid":
			cost_label.text = _reason if _reason != "" else "Cannot build here"
			cost_label.add_theme_color_override("font_color", GameTheme.DANGER)
			action_button.text = "Cancel"
	if _state != "invalid" and _reason != "":
		hint_label.text = _reason
	if input != null and input.tool == InputController.TOOL_STATION and _state != "invalid":
		hint_label.text = _catchment_text()


## The ghost preview carries the domain's own verdict for every place in reach,
## tagged `role`: "load" for a producer whose cargo this station would pick up,
## "unload" for a sink that would take it.  Showing only the producers called a
## pure destination a served place, so both sides are listed under their own
## heading and buyers can be told apart from pickups.
func _catchment_text() -> String:
	if input == null:
		return ""
	var entries: Array = Array(input.station_preview.get("sources", []))
	if entries.is_empty():
		return "Move the ghost over the map to see what it would serve."
	var pickups: PackedStringArray = []
	var buyers: PackedStringArray = []
	for entry in entries:
		if String(entry.get("role", "load")) == "unload":
			buyers.append("%s (%s)" % [String(entry["name"]), _cargos_text(entry)])
		else:
			pickups.append("%s — %s %d/mo" % [String(entry["name"]),
				session.data.cargo_display(String(entry["cargo"])),
				int(float(entry.get("rate", 0.0)))])
	var lines := PackedStringArray()
	lines.append("Picks up: " + (", ".join(pickups) if not pickups.is_empty() else "nothing"))
	lines.append("Delivers to: " + (", ".join(buyers) if not buyers.is_empty() else "nobody"))
	return "\n".join(lines)


func _cargos_text(entry: Dictionary) -> String:
	var names: PackedStringArray = []
	var cargos: Array = Array(entry.get("cargos", []))
	for cargo_id in cargos:
		names.append(session.data.cargo_display(String(cargo_id)))
	return ", ".join(names) if not names.is_empty() else "cargo"
