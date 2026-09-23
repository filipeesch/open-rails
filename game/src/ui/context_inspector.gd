class_name ContextInspector
extends PanelContainer

## The right-hand inspector: what is selected and the handful of actions that
## make sense for it.  Hidden entirely when nothing is selected — map space wins.

signal focus_requested(kind: String, entity_id: int)
signal route_requested(train_id: int)
signal buy_train_requested(station_id: int)

var session: GameSession
var selection: SelectionService
var camera_rig: IsoCameraRig
## What arms a tool, when the host has named one.  See `attach`.
var controller: InputController = null
var column: VBoxContainer
var _kind: String = SelectionService.KIND_NONE
var _entity_id := 0


## The fourth argument names the controller the tool verbs go through.  It is
## optional because the panel is useful without it — the readings are the same —
## but an action that has nothing to arm is not built at all rather than built dead.
func attach(game_session: GameSession, sel: SelectionService, rig: IsoCameraRig,
		controller: InputController = null) -> void:
	session = game_session
	selection = sel
	camera_rig = rig
	self.controller = controller
	theme = GameTheme.build()
	add_theme_stylebox_override("panel", GameTheme.panel(GameTheme.BACKGROUND))
	custom_minimum_size = Vector2(266, 0)
	# Right-aligned by its host band; as tall as its content and no more, so the
	# map keeps the rest of the column when something is selected.
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	visible = false
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	add_child(column)
	sel.selection_changed.connect(_on_selection)
	session.station_inventory_changed.connect(func(_id): _rebuild())
	session.train_arrived.connect(func(_id, _station): _rebuild())
	session.cargo_delivered.connect(func(_id, _cargo, _q, _r): _rebuild())
	# Other panels find the inspector by group instead of reaching into the
	# shell for a reference to it.
	add_to_group("ui_inspector")


func configure(game_session: GameSession, sel: SelectionService, rig: IsoCameraRig) -> void:
	attach(game_session, sel, rig)


## Whether the sheet is answering for something.  "Nothing selected" is one state,
## not two: an untouched inspector and a cleared one give the same answer, so no
## caller has to know which happened first.
func has_selection() -> bool:
	return _kind != SelectionService.KIND_NONE


func inspected() -> String:
	return _kind



func inspected_id() -> int:
	return _entity_id


func _on_selection(kind: String, entity_id: int, _tile: Vector2i) -> void:
	_kind = kind
	_entity_id = entity_id
	visible = kind != SelectionService.KIND_NONE
	if visible:
		_rebuild()
	else:
		# The sheet is put down, not left standing.  A hidden panel still holding
		# yesterday's station is a panel that will be rebuilt over, and every widget
		# in it is a widget the frame has to walk past for nothing.
		_release_children()


func _rebuild() -> void:
	_release_children()
	match _kind:
		SelectionService.KIND_STATION:
			_station_panel()
		SelectionService.KIND_INDUSTRY:
			_industry_panel()
		SelectionService.KIND_TOWN:
			_town_panel()
		SelectionService.KIND_TRAIN:
			_train_panel()
		SelectionService.KIND_RAIL:
			_rail_panel()
		_:
			_terrain_panel()


## Let go of the sheet's rows.  Inside a tree they are queued — a row can be the
## very button whose press caused this rebuild, and freeing it mid-emit is refused
## by the engine.  An orphan panel (a preview, a test) never gets a frame to drain
## the queue, so for it the release is immediate.
func _release_children() -> void:
	for child in column.get_children():
		if is_inside_tree():
			child.queue_free()
		else:
			column.remove_child(child)
			child.free()


func _header(title: String, sub: String = "") -> void:
	column.add_child(GameTheme.heading(title))
	if sub != "":
		column.add_child(GameTheme.body(sub, GameTheme.TEXT_DIM))
	column.add_child(HSeparator.new())


## Station tool in hand, view on the industry, ghost where the cursor will land.
## The tool does the rest — legality, price, the catchment readout — because this
## screen has no opinion of its own about where a station may stand.
func _arm_station_here() -> void:
	controller.arm_station()
	var tile := Vector2i(session.industries.tile_of(_entity_id))
	if tile != Vector2i(-1, -1):
		camera_rig.stop_following()
		camera_rig.focus_tile(Vector2(tile) + Vector2(0.5, 0.5))


func _action(text: String, callback: Callable) -> void:
	var button := GameTheme.button_for(text)
	button.pressed.connect(callback)
	column.add_child(button)


func _station_panel() -> void:
	var instance := session.stations.station(_entity_id)
	if instance.is_empty():
		return
	_header(session.stations.name_of(_entity_id), "Station")
	var summary := session.cargo.available_summary(_entity_id)
	if summary.is_empty():
		column.add_child(GameTheme.body("No cargo waiting.", GameTheme.TEXT_DIM))
	else:
		for entry in summary:
			column.add_child(GameTheme.body("%s  %d waiting" % [entry["label"], int(entry["amount"])]))
	column.add_child(HSeparator.new())
	column.add_child(GameTheme.body("Picks up in catchment", GameTheme.TEXT_DIM))
	var sources := session.cargo.prospective_sources(_entity_id)
	if sources.is_empty():
		column.add_child(GameTheme.body("Nothing within %d tiles — move it closer." % int(session.stations.catchment_of(_entity_id)), GameTheme.WARNING))
	for entry in sources:
		column.add_child(GameTheme.body("\u2191 %s: %s %d/mo" % [entry["name"], entry["label"], int(entry["amount"])]))
	_paint_sinks()
	column.add_child(HSeparator.new())
	column.add_child(GameTheme.body("Revenue this month: %s" % GameTheme.money(session.stations.monthly_revenue_of(_entity_id))))
	_action("Buy a train here", func(): buy_train_requested.emit(_entity_id))
	_action("Focus", func(): focus_requested.emit("station", _entity_id))
	_action("Rename", func(): _prompt_rename())


## A sink is not a source.  A power plant in the catchment is a customer, and
## the inspector used to say nothing at all about it — which made a destination
## station look like it served nothing.  `covered_sinks` is the domain's own
## reach test, so this is the same answer the route service will act on.
func _paint_sinks() -> void:
	column.add_child(GameTheme.body("Delivers to", GameTheme.TEXT_DIM))
	var sinks := session.stations.covered_sinks(_entity_id)
	if sinks.is_empty():
		column.add_child(GameTheme.body("No buyer within %d tiles — cargo would sit here." % int(session.stations.catchment_of(_entity_id)), GameTheme.WARNING))
		return
	for entry in sinks:
		column.add_child(GameTheme.body("\u2193 %s: %s" % [String(entry["name"]), _sink_cargos(entry)], GameTheme.GOOD))


func _sink_cargos(entry: Dictionary) -> String:
	var names: PackedStringArray = []
	for cargo_id in Array(entry.get("cargos", [])):
		names.append(session.data.cargo_display(String(cargo_id)))
	return "takes " + ", ".join(names) if not names.is_empty() else "takes cargo"


func _industry_panel() -> void:
	var def := session.industries.def_of(_entity_id)
	var tile := session.industries.tile_of(_entity_id)
	_header(session.industries.name_of(_entity_id), def.display_name if def != null else "Industry")
	if def != null:
		for flow in def.produces:
			column.add_child(GameTheme.body("Produces %s %d/mo · %d/%d stored" % [
				session.data.cargo_display(String(flow["cargo"])), int(flow["rate_per_month"]),
				int(session.industries.inventory_of(_entity_id, String(flow["cargo"]))),
				int(flow["storage_capacity"])]))
		for flow in def.accepts:
			column.add_child(GameTheme.body("Consumes up to %d %s per month" % [
				int(flow["capacity_per_month"]), session.data.cargo_display(String(flow["cargo"]))]))
	column.add_child(GameTheme.body("Delivered so far: %d" % int(float(session.industries.industry(_entity_id).get("total_shipped", 0.0))), GameTheme.TEXT_DIM))
	_action("Focus", func(): focus_requested.emit("industry", _entity_id))
	# The verb a producer's panel exists to offer: this coal is waiting to be
	# collected, and the way to collect it is a station beside it.  It used to be a
	# button whose handler was `pass` — the door was painted on the wall.  With no
	# controller named by the host there is nothing to arm, so no door is offered.
	if controller != null:
		_action("Build a station here", _arm_station_here)


func _town_panel() -> void:
	_header(session.towns.name_of(_entity_id), "Population %d" % session.towns.population_of(_entity_id))
	var generation := session.towns.generation_map(_entity_id)
	for cargo_id in generation.keys():
		column.add_child(GameTheme.body("%s: %d per month" % [session.data.cargo_display(String(cargo_id)), int(generation[cargo_id])]))
	column.add_child(HSeparator.new())
	var covered := false
	for station_id in session.stations.stations():
		for entry in session.stations.covered_sources(station_id):
			if int(entry["id"]) == _entity_id:
				covered = true
	column.add_child(GameTheme.body("Served by a station" if covered else "No station serves this town yet",
		GameTheme.GOOD if covered else GameTheme.WARNING))
	_action("Focus", func(): focus_requested.emit("town", _entity_id))


func _train_panel() -> void:
	_header(session.trains.name_of(_entity_id), session.trains.state_label(_entity_id))
	var stock := session.trains.stock_of(_entity_id)
	var parts: PackedStringArray = []
	for stock_id in stock:
		var def := session.data.stock(stock_id)
		parts.append(def.display_name if def != null else stock_id)
	column.add_child(GameTheme.body(" · ".join(parts)))
	column.add_child(GameTheme.body("Top speed ≈ %.0f km/h" % session.trains.estimated_max_speed(_entity_id)))
	column.add_child(GameTheme.body("Capacity: %s" % _capacity_text(_entity_id)))
	var on_board := session.trains.carried_units(_entity_id)
	column.add_child(GameTheme.body("On board: %d units" % int(on_board)))
	var route_id := session.trains.route_of(_entity_id)
	column.add_child(GameTheme.body("Route: %s" % (session.routes.describe(route_id) if route_id != 0 else "none"),
		GameTheme.TEXT_DIM if route_id == 0 else GameTheme.TEXT))
	if route_id != 0 and not session.routes.is_valid(route_id):
		column.add_child(GameTheme.body("Route broken: %s" % session.routes.invalid_reason(route_id),
			GameTheme.DANGER))
	column.add_child(GameTheme.body("Earned: %s" % GameTheme.money(session.trains.total_revenue(_entity_id))))
	_action("Open route", func(): route_requested.emit(_entity_id))
	_action("Follow (F)", func(): camera_rig.follow_train(_entity_id, Callable(session.trains, "position_tiles")))
	_action("Stop following", func(): camera_rig.stop_following())


func _rail_panel() -> void:
	_header("Track", "Tile %s" % selection.selected_tile)
	var mask := session.world.rail_mask_at(selection.selected_tile)
	column.add_child(GameTheme.body("Connections: %d" % session.rail.network.connection_count(selection.selected_tile)))
	column.add_child(GameTheme.body("Junction" if session.rail.network.is_junction(selection.selected_tile) else "Through line"))
	column.add_child(HSeparator.new())
	_action("Remove this track", func():
		var result := session.builder.remove_track([selection.selected_tile])
		if not bool(result.get("ok", false)):
			session.notify(String(result["reason"]), "bad"))


func _terrain_panel() -> void:
	var tile := selection.selected_tile
	_header(session.world.terrain_name(tile), "Tile %s" % tile)
	column.add_child(GameTheme.body("Height %d (%.2f)" % [session.world.height_at(tile), session.world.elevation_at(tile)]))
	column.add_child(GameTheme.body("Buildable" if session.world.can_build(tile) else "Blocked: %s" % session.world.build_reason(tile),
		GameTheme.GOOD if session.world.can_build(tile) else GameTheme.DANGER))


func _capacity_text(train_id: int) -> String:
	var parts: PackedStringArray = []
	for cargo_id in session.trains.capacity_by_cargo(train_id).keys():
		parts.append("%d %s" % [int(session.trains.capacity_for(train_id, String(cargo_id))),
			session.data.cargo_display(String(cargo_id))])
	return ", ".join(parts) if not parts.is_empty() else "none"


func _prompt_rename() -> void:
	var edit := LineEdit.new()
	edit.text = session.stations.name_of(_entity_id)
	edit.text_submitted.connect(func(value):
		session.stations.rename(_entity_id, value)
		_rebuild())
	column.add_child(edit)
