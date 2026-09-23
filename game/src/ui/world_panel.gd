class_name WorldPanel
extends PanelContainer

## The valley seen whole: which settlements are asking to be served, which works
## are producing or burning cargo, and whether a station has reached either yet.
##
## The bottom toolbar has offered this door since the first cut of the shell, and
## until now pressing it lit a button and opened nothing — the worst kind of dead
## control, because the light makes the player think something happened.  The
## screen it opens is the one question a new player actually has and no other
## panel answers: not *what do I own* (the books) or *what is running* (the
## drawer), but *what is out there*.
##
## Every figure is the domain's own answer, read at paint time.  Population is
## `TownService.population_of`, a town's monthly generation is its `generation_map`,
## an industry's stock is `IndustryService.inventory_of`, and "No station serves
## this town yet" is the same reach test the inspector and the route editor act on —
## `StationService.covered_sources`.  Nothing here is estimated, and nothing is
## carried over from the last paint: a town that gains a station shows it on the
## next frame, which is the whole reason the panel listens to the station signals
## rather than to a timer.
##
## Built by code like every other screen here, so `attach` is the wiring a host —
## or a headless test — drives.

var session: GameSession
var controller: InputController
var camera_rig: IsoCameraRig

var column: VBoxContainer
var _map_label: Label
var _town_box: VBoxContainer
var _industry_box: VBoxContainer
var _town_missing: Label
var _industry_missing: Label

var _built := false
var _dirty := true


func _ready() -> void:
	_ensure_built()


## Build once, whoever arrives: `_ready` in the shipped scene, `attach` for an
## orphan host.  A panel that builds only in `_ready` cannot be read by anything
## that never enters a tree.
func _ensure_built() -> void:
	if _built:
		return
	_built = true
	theme = GameTheme.build()
	add_theme_stylebox_override("panel", GameTheme.panel(GameTheme.BACKGROUND))
	custom_minimum_size = Vector2(368, 0)
	# The band hosts one drawer at a time and this sheet is only as tall as its
	# rows, so it hugs the top of the band instead of stretching down it.
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_build()
	visible = false


func attach(game_session: GameSession, input: InputController, rig: IsoCameraRig) -> void:
	session = game_session
	controller = input
	camera_rig = rig
	_ensure_built()
	session.clock.month_changed.connect(_on_changed)
	session.station_created.connect(_on_changed)
	session.station_removed.connect(_on_changed)
	if controller != null:
		controller.panel_requested.connect(_on_panel_requested)
		controller.tool_changed.connect(_on_tool_changed)
	_dirty = true


## Twin of `attach` for hosts that follow the configure idiom.
func configure(game_session: GameSession, input: InputController,
		rig: IsoCameraRig) -> void:
	attach(game_session, input, rig)


func is_open() -> bool:
	return visible


func mark_dirty() -> void:
	_dirty = true


func _on_changed(_argument: Variant = null) -> void:
	_dirty = true


## Paint immediately instead of waiting for the refresh tick.  Tests and probes use
## it so a headless run need not wait on a wall-clock timer.
func refresh_now() -> void:
	_dirty = false
	_paint()


## The panel's own clock: signals set the dirty flag, this paints once at the UI
## cadence the layout reference asks for.  Hidden means idle.
func refresh() -> void:
	if not _dirty or session == null:
		return
	_dirty = false
	_paint()


func _on_tool_changed(tool: String) -> void:
	# One drawer per band: an armed build tool owns the left band.
	if tool != InputController.TOOL_NONE and tool != InputController.TOOL_STOP_PICK:
		visible = false


func _on_panel_requested(panel: String) -> void:
	visible = panel == InputController.PANEL_WORLD


func _close() -> void:
	visible = false
	if controller != null:
		controller.close_panel(InputController.PANEL_WORLD)


# --- painting -------------------------------------------------------------

func _paint() -> void:
	_map_label.text = "%s · %d × %d tiles" % [session.map_id.replace("_", " ").capitalize(),
			session.world.width, session.world.height]
	_paint_towns()
	_paint_industries()


func _paint_towns() -> void:
	for child in _town_box.get_children():
		GameTheme.release(child)
	var ids := session.towns.towns()
	_town_box.visible = not ids.is_empty()
	_town_missing.visible = ids.is_empty()
	for town_id in ids:
		_town_box.add_child(_entity_row(session.towns.name_of(town_id),
				"Population %d" % session.towns.population_of(town_id),
				_cargo_rates(session.towns.generation_map(town_id)),
				_town_served_line(town_id),
				session.towns.tile_of(town_id)))


func _paint_industries() -> void:
	for child in _industry_box.get_children():
		GameTheme.release(child)
	var ids := session.industries.industries()
	_industry_box.visible = not ids.is_empty()
	_industry_missing.visible = ids.is_empty()
	for industry_id in ids:
		var lines: PackedStringArray = []
		var def := session.industries.def_of(industry_id)
		if def != null:
			for flow in def.produces:
				var stock := session.industries.inventory_of(industry_id, String(flow["cargo"]))
				lines.append("Turns out up to %d %s per month · %d on site" % [
						int(flow["rate_per_month"]),
						session.data.cargo_display(String(flow["cargo"])), int(stock)])
			for flow in def.accepts:
				var taken := session.industries.inventory_of(industry_id, String(flow["cargo"]))
				lines.append("Takes up to %d %s per month · %d waiting" % [
						int(flow["capacity_per_month"]),
						session.data.cargo_display(String(flow["cargo"])), int(taken)])
		_industry_box.add_child(_entity_row(session.industries.name_of(industry_id),
				_producer_words(industry_id), lines, "", session.industries.tile_of(industry_id)))


## "Makes coal" / "Burns coal" / "Trades" — what this works is to the valley, in
## one line, straight from the definition's own two lists rather than a guess at
## the definition id.
func _producer_words(industry_id: int) -> String:
	var words: PackedStringArray = []
	if session.industries.is_producer(industry_id):
		words.append("Produces")
	if session.industries.is_consumer(industry_id):
		words.append("Consumes")
	return " · ".join(words) if not words.is_empty() else "Takes no cargo"


func _cargo_rates(rates: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for cargo_id in rates.keys():
		lines.append("%s: %d per month" % [session.data.cargo_display(String(cargo_id)),
				int(float(rates[cargo_id]))])
	return lines


## The same reach test the inspector draws and the route service acts on, so this
## line can never disagree with the click it is advising.
func _town_served_line(town_id: int) -> String:
	for station_id in session.stations.stations():
		for entry in session.stations.covered_sources(station_id):
			if int(entry["id"]) == town_id:
				return "Served by %s" % session.stations.name_of(station_id)
	return "No station serves this town yet"


## One place, named, with the figures under it and the camera verb beside it.  The
## ⌖ button is the only control on a row: a town cannot be edited, so a row that
## offered anything else would be offering a door that is not there.
func _entity_row(title: String, subtitle: String, lines: PackedStringArray,
		status: String, tile: Vector2i) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", GameTheme.row(false))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	panel.add_child(head)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(text)
	text.add_child(GameTheme.body(title))
	if subtitle != "":
		text.add_child(GameTheme.small(subtitle, GameTheme.TEXT_DIM))
	for line in lines:
		text.add_child(GameTheme.small(line, GameTheme.TEXT_DIM))
	if status != "":
		var served := status.begins_with("No station")
		text.add_child(GameTheme.small(status, GameTheme.WARNING if served else GameTheme.GOOD))
	var show := GameTheme.button_for("⌖", "Centre the camera on it")
	show.pressed.connect(_focus_tile.bind(tile))
	head.add_child(show)
	return panel


func _focus_tile(tile: Vector2i) -> void:
	if camera_rig == null or tile == Vector2i(-1, -1):
		return
	camera_rig.stop_following()
	camera_rig.focus_tile(Vector2(tile) + Vector2(0.5, 0.5))


# --- building -------------------------------------------------------------

func _build() -> void:
	column = VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", GameTheme.GAP)
	add_child(column)

	var head := HBoxContainer.new()
	column.add_child(head)
	var title := GameTheme.heading("The valley")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := GameTheme.button_for("✕", "Put the map down " \
			+ KeyHints.hint_suffix("tool_cancel"))
	close.name = "Close"
	close.pressed.connect(_close)
	head.add_child(close)

	_map_label = GameTheme.small("", GameTheme.TEXT_DIM)
	column.add_child(_map_label)

	column.add_child(GameTheme.body("Towns", GameTheme.TEXT_DIM))
	_town_box = VBoxContainer.new()
	_town_box.add_theme_constant_override("separation", 4)
	column.add_child(_town_box)
	_town_missing = GameTheme.small("No settlements on this map.", GameTheme.TEXT_DIM)
	_town_missing.visible = false
	column.add_child(_town_missing)

	column.add_child(HSeparator.new())
	column.add_child(GameTheme.body("Works", GameTheme.TEXT_DIM))
	_industry_box = VBoxContainer.new()
	_industry_box.add_theme_constant_override("separation", 4)
	column.add_child(_industry_box)
	_industry_missing = GameTheme.small("No works on this map.", GameTheme.TEXT_DIM)
	_industry_missing.visible = false
	column.add_child(_industry_missing)

