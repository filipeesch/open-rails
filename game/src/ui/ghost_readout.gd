class_name GhostReadout
extends PanelContainer

## The ghost's numbers have to land where the player is already looking — at
## the cursor — because the decision they are making is "here or not here".  A
## reason that only appears in a side drawer asks the player to carry the
## question across the screen and back, and a failure stated in general terms
## ("cannot build here") gives them nothing to act on: this readout quotes the
## domain's own sentence, verbatim, the one the commit path gave.


var session: GameSession
var input: InputController
var count_label: Label
var cost_label: Label
var status_label: Label
var reach_label: Label

var _screen := Vector2.ZERO
const OFFSET := Vector2(20, 14)


func attach(game_session: GameSession, controller: InputController) -> void:
	session = game_session
	input = controller
	theme = GameTheme.build()
	add_theme_stylebox_override("panel", GameTheme.panel(GameTheme.BACKGROUND))
	custom_minimum_size = Vector2(190, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 30
	visible = false

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	add_child(column)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	column.add_child(line)
	count_label = GameTheme.body("", GameTheme.TEXT_DIM)
	line.add_child(count_label)
	cost_label = GameTheme.body("")
	cost_label.add_theme_font_size_override("font_size", GameTheme.FONT_STRONG)
	line.add_child(cost_label)

	reach_label = GameTheme.body("", GameTheme.TEXT_DIM)
	reach_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reach_label.custom_minimum_size = Vector2(190, 0)
	column.add_child(reach_label)

	status_label = GameTheme.body("", GameTheme.TEXT_DIM)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(190, 0)
	column.add_child(status_label)

	controller.ghost_changed.connect(_on_ghost)
	controller.cursor_moved.connect(_on_cursor)
	controller.tool_changed.connect(_on_tool)
	controller.station_ghost_previewed.connect(_on_station_preview)


func configure(game_session: GameSession, controller: InputController) -> void:
	attach(game_session, controller)


## The readout floats beside the pointer, not under it: the ghost itself is
## drawn on the tile the cursor points at, and a panel laid over it would hide
## the very thing being judged.  Inside a window it is kept on screen; headless
## there is no screen to keep it on, and the position is still whatever the
## caller asked for.
func place_at(screen: Vector2) -> void:
	_screen = screen
	var origin := screen + OFFSET
	var viewport := get_viewport()
	if viewport != null:
		var extent := viewport.get_visible_rect().size
		if extent.x > 0.0 and extent.y > 0.0:
			var size := get_combined_minimum_size()
			origin.x = minf(origin.x, extent.x - size.x)
			origin.y = minf(origin.y, extent.y - size.y)
	global_position = origin


func _on_cursor(screen: Vector2) -> void:
	place_at(screen)


func _on_tool(_tool: String) -> void:
	# A tool switch invalidates the last ghost: what was legal for laying rail
	# says nothing yet about a station.  Silence beats a stale verdict — the
	# readout returns with the next real preview, seconds later on any mouse
	# motion.
	reach_label.text = ""
	if _tool == InputController.TOOL_NONE:
		visible = false


func _on_ghost(tiles: Array[Vector2i], state: String, reason: String, cost: float) -> void:
	if state == "none" or tiles.is_empty():
		visible = false
		return
	visible = true
	count_label.text = "%d tile%s" % [tiles.size(), "" if tiles.size() == 1 else "s"]
	if cost < 0.0:
		# A removal pays: the negative price is shown as the refund it is, so
		# the number beside the cursor matches the number the ledger will get.
		cost_label.text = "%s refund" % GameTheme.signed_money(-cost)
		cost_label.add_theme_color_override("font_color", GameTheme.GOOD)
	else:
		cost_label.text = GameTheme.money(cost)
		cost_label.add_theme_color_override("font_color",
			GameTheme.WARNING if state == "expensive" else GameTheme.TEXT)
	if state != "expensive" or input.tool != InputController.TOOL_STATION:
		reach_label.text = ""
	match state:
		"invalid":
			status_label.text = reason if reason != "" else "Cannot build here"
			status_label.add_theme_color_override("font_color", GameTheme.DANGER)
		"expensive":
			# The domain's own sentence first: "not enough cash for a station" is a
			# different problem from a line running dear, and the player should read
			# the one they actually have.
			status_label.text = reason if reason != "" else "Legal — this line runs long and dear."
			status_label.add_theme_color_override("font_color", GameTheme.WARNING)
		_:
			status_label.text = "Legal here."
			status_label.add_theme_color_override("font_color", GameTheme.GOOD)


## The station tool's extra line: what the yard would reach and what that reach
## is worth a month.  The numbers are the preview's own, summed by the domain from
## the sources' declared output, so the figure beside the cursor is the figure the
## first month's invoice is made of.
func _on_station_preview(preview: Dictionary) -> void:
	if input.tool != InputController.TOOL_STATION:
		return
	reach_label.text = _reach_sentence(preview)


func _reach_sentence(preview: Dictionary) -> String:
	var places := {}
	for entry in Array(preview.get("sources", [])):
		places[Vector2i(entry["tile"])] = true
	if places.is_empty():
		return "Reaches nothing — no cargo to carry from here."
	var parts: Array[String] = []
	var monthly := Dictionary(preview.get("monthly", {}))
	for cargo_id in monthly.keys():
		var def := session.data.cargo_def(String(cargo_id))
		var label := def.display_name if def != null else String(cargo_id)
		parts.append("%s %d" % [label, int(round(float(monthly[cargo_id])))])
	return "Reaches %d place%s — %s a month." % [places.size(),
		"" if places.size() == 1 else "s", " · ".join(parts)]
