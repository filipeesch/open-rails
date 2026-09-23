class_name TripPanel
extends PanelContainer

## The trains drawer: every consist the company owns, what it is doing right
## now, and the route it runs — the whole train loop without the console.
##
## Reads: `TrainService`, `RouteService`, `StationService` queries.  Writes:
## service calls only (`rename`, `sell`, `purchase`, `set_route`); the drawer
## never moves money, `EconomyService` does that inside those calls.
##
## Refresh is event-driven: domain signals set a dirty flag and a 0.1 s timer
## paints it.  Row widgets live exactly as long as their train — made on
## `train_created`, freed on `train_removed` — so nothing is rebuilt per tick.
##
## The panel takes the left band, which it shares with the tool panel: while a
## build tool is armed the tool panel owns the band and this one steps aside.

const PAGE_TRAINS := "trains"
const PAGE_ROUTE := "route"
const PAGE_YARD := "yard"

var session: GameSession
var controller: InputController
var selection: SelectionService
var camera_rig: IsoCameraRig

var _route_editor: RouteEditor
var _yard: TrainYard

var _rows := {}
var _page := PAGE_TRAINS
var _filter := ""

var _count_label: Label
var _filter_field: LineEdit
var _list_box: VBoxContainer
var _empty_box: VBoxContainer
var _tabs := {}
var _footer: Label
var _list_page: VBoxContainer
var _tick: Timer
var _dirty := true
var _wired := false
var _built := false


func _ready() -> void:
	_ensure_built()
	# `game_root.gd` builds the session's collaborators in its own `_ready`,
	# which runs after a child's, so the lookup waits one frame.  A host that
	# wires the panel itself through `attach` never takes this path — and an
	# orphan (a headless test) has no tree to wait on in the first place.
	if not _wired and is_inside_tree():
		_await_autowire()


func _await_autowire() -> void:
	await get_tree().process_frame
	if not _wired:
		_autowire()


## Build once, whoever arrives: `_ready` in the shipped scene, `attach` for an
## orphan host.  A drawer that builds only inside `_ready` is a drawer no
## headless test can open, and a panel nobody can open is a panel that lies
## about being implemented.
func _ensure_built() -> void:
	if _built:
		return
	_built = true
	theme = GameTheme.build()
	add_theme_stylebox_override("panel", GameTheme.panel(GameTheme.BACKGROUND))
	custom_minimum_size = Vector2(368, 0)
	_build()
	visible = false
	_show_page(PAGE_TRAINS)
	_tick = Timer.new()
	_tick.name = "RefreshTick"
	_tick.wait_time = 0.1
	_tick.autostart = true
	_tick.timeout.connect(_on_refresh_tick)
	add_child(_tick)


## Explicit wiring for a host that owns the panel; the scene does the same thing
## one frame later through `_autowire`.
func attach(game_session: GameSession, input: InputController, sel: SelectionService,
		rig: IsoCameraRig) -> void:
	if _wired or game_session == null:
		return
	_ensure_built()
	session = game_session
	controller = input
	selection = sel
	camera_rig = rig
	_wired = true
	# Entity signals come off the session façade.  Route bookkeeping, revenue and
	# cash are not re-exported there, so those are read at their source.
	session.train_created.connect(_on_train_created)
	session.train_removed.connect(_on_train_removed)
	session.consist_changed.connect(func(_id: int) -> void: _mark_dirty())
	session.train_arrived.connect(func(_id: int, _station: int) -> void: _mark_dirty())
	session.train_departed.connect(func(_id: int, _station: int) -> void: _mark_dirty())
	session.cargo_delivered.connect(
			func(_station: int, _cargo: String, _qty: float, _rev: float) -> void: _mark_dirty())
	session.station_created.connect(func(_id: int) -> void: _mark_dirty())
	session.station_removed.connect(func(_id: int) -> void: _mark_dirty())
	session.station_renamed.connect(func(_id: int, _name: String) -> void: _mark_dirty())
	session.station_inventory_changed.connect(func(_id: int) -> void: _mark_dirty())
	session.session_loaded.connect(_on_session_loaded)
	session.trains.train_route_changed.connect(func(_id: int, _route: int) -> void: _mark_dirty())
	session.trains.train_revenue.connect(
			func(_id: int, _station: int, _cargo: String, _amount: float) -> void: _mark_dirty())
	session.routes.route_changed.connect(func(_id: int) -> void: _mark_dirty())
	session.routes.route_removed.connect(func(_id: int) -> void: _mark_dirty())
	session.routes.route_path_invalid.connect(
			func(_id: int, _reason: String) -> void: _mark_dirty())
	session.economy.money_changed.connect(func(_cash: float) -> void: _mark_dirty())
	session.clock.month_changed.connect(func(_date: Variant) -> void: _mark_dirty())
	_route_editor.attach(session, controller, camera_rig)
	_yard.attach(session, camera_rig)
	if controller != null:
		controller.panel_requested.connect(_on_panel_requested)
		controller.tool_changed.connect(_on_tool_changed)
	if selection != null:
		selection.selection_changed.connect(_on_selection_changed)
	for train_id in session.trains.trains():
		_add_row(train_id)
	_mark_dirty()


func _autowire() -> void:
	if _wired:
		return
	var game := get_parent()
	if game != null:
		game = game.get_parent()
	if game == null:
		push_warning("TripPanel: no game root to wire against")
		return
	attach(game.get_node_or_null("GameSession") as GameSession,
			game.get_node_or_null("Input") as InputController,
			game.get_node_or_null("Selection") as SelectionService,
			game.get_node_or_null("World3D/CameraRig/Camera") as IsoCameraRig)


func is_open() -> bool:
	return visible


## Open the route page for a train from anywhere — the inspector's "Open route"
## button and a double click in the world both land here.
func open_route_for(train_id: int) -> void:
	if session == null or train_id <= 0 or session.trains.train(train_id).is_empty():
		return
	visible = true
	_edit_route(train_id)


## Open the yard with this station already chosen — where the inspector's "Buy a
## train here" button arrives.  A screen does not reach into another screen's
## widgets; it asks, and the root carries the ask across.
func open_yard_for(station_id: int) -> void:
	if session == null or station_id <= 0:
		return
	visible = true
	_ensure_built()
	_show_page(PAGE_YARD)
	refresh_now()
	if not _yard.select_station(station_id):
		session.notify("%s cannot start a train yet — the line does not reach it." \
				% session.stations.name_of(station_id), "bad")


func _mark_dirty() -> void:
	_dirty = true


## Paint immediately instead of waiting for the refresh tick.  Tests and probes
## use it so a headless run need not wait on a wall-clock timer.
func refresh_now() -> void:
	_dirty = false
	_paint()


## The panel's single clock: signals set the dirty flag, this paints it at the
## 0.1 s UI refresh cadence the layout reference asks for.  Hidden means idle.
## The yard marks *itself* dirty when one of its controls changes, so a spinner
## click repaints its statistics even while the simulation has nothing to say —
## and `TrainYard.refresh` does nothing until something actually changed.
func _on_refresh_tick() -> void:
	if not visible:
		return
	if _dirty:
		_dirty = false
		_paint()
	_yard.refresh()


func _on_session_loaded() -> void:
	for row in _rows.values():
		if row.get_parent() == _list_box:
			_list_box.remove_child(row)
		row.queue_free()
	_rows.clear()
	# Following is the camera's state, not this panel's; a load can hand the same
	# id to a different consist, so the follow has to be put down for real.
	_stop_following()
	for train_id in session.trains.trains():
		_add_row(train_id)
	_mark_dirty()


# --- rows ------------------------------------------------------------------

func _on_train_created(train_id: int) -> void:
	_add_row(train_id)
	_mark_dirty()


func _on_train_removed(train_id: int) -> void:
	if _rows.has(train_id):
		var row: TrainRow = _rows[train_id]
		_rows.erase(train_id)
		# Detach now, free later: the removal can be the second press of the
		# row's own Sell button, and a row cannot be freed mid-emit — so this
		# one release stays queued even for an orphan.  Detaching immediately
		# is enough for the list to tell the truth either way.
		if row.get_parent() == _list_box:
			_list_box.remove_child(row)
		row.queue_free()
	if camera_rig != null and camera_rig.followed_train_id() == train_id:
		camera_rig.stop_following()
	_mark_dirty()


func _add_row(train_id: int) -> void:
	if _rows.has(train_id):
		return
	var row := TrainRow.new()
	row.name = "Train%d" % train_id
	row.activated.connect(_on_row_activated)
	row.action.connect(_on_row_action)
	row.rename_requested.connect(_on_row_renamed)
	# Into the tree first: the row builds its widgets in `_ready` and cannot
	# paint before that has happened.
	_list_box.add_child(row)
	_rows[train_id] = row
	row.bind(session, train_id)


## Clicking a row selects the train, which is what opens the inspector.
func _on_row_activated(train_id: int) -> void:
	if selection != null:
		selection.select_train(train_id)
	_mark_dirty()


func _on_row_renamed(train_id: int, new_name: String) -> void:
	session.trains.rename(train_id, new_name)
	session.notify("Train renamed to %s" % new_name, "info")
	_mark_dirty()


func _on_row_action(request: String, train_id: int) -> void:
	match request:
		"focus":
			_focus_train(train_id)
		"follow":
			_follow_train(train_id)
		"unfollow":
			_stop_following()
		"route":
			_edit_route(train_id)
		"rename":
			if _rows.has(train_id):
				(_rows[train_id] as TrainRow).begin_rename()
		"sell":
			_sell_train(train_id)
	_mark_dirty()


func _focus_train(train_id: int) -> void:
	if camera_rig == null:
		return
	camera_rig.stop_following()
	camera_rig.focus_tile(Vector2(session.trains.position_tiles(train_id)) + Vector2(0.5, 0.5))
	if selection != null:
		selection.select_train(train_id)


func _follow_train(train_id: int) -> void:
	if camera_rig == null:
		return
	camera_rig.follow_train(train_id, Callable(session.trains, "position_tiles"))


func _stop_following() -> void:
	if camera_rig != null:
		camera_rig.stop_following()


func _sell_train(train_id: int) -> void:
	var train_name := session.trains.name_of(train_id)
	# Read before the sale: once the consist is gone the figure reads 0, and the
	# row armed the player on exactly this number.
	var refund := session.trains.refund_for(train_id)
	if not session.trains.sell(train_id):
		session.notify("%s could not be sold" % train_name, "bad")
		return
	session.notify("Sold %s · pays back %s" % [train_name, GameTheme.money(refund)], "good")
	if _route_editor.train_id == train_id:
		_route_editor.stop_edit()
		_show_page(PAGE_TRAINS)


func _edit_route(train_id: int) -> void:
	_route_editor.edit(train_id)
	_show_page(PAGE_ROUTE)
	if selection != null:
		selection.select_train(train_id)


func _on_train_bought(train_id: int) -> void:
	_edit_route(train_id)
	if selection != null:
		selection.select_train(train_id)


# --- panel and page plumbing ----------------------------------------------

func _on_panel_requested(panel: String) -> void:
	if panel == InputController.PANEL_TRIPS:
		visible = true
		_mark_dirty()
		return
	if not visible:
		return
	if panel == "":
		_close()
		return
	# Some other panel was asked for.  The left band hosts one drawer at a time,
	# so this one steps aside — but the controller's choice is the other panel,
	# and stepping aside must not overwrite it.
	visible = false


func _close() -> void:
	visible = false
	if controller != null:
		controller.close_panel(InputController.PANEL_TRIPS)
	_stop_following()


func _on_tool_changed(tool: String) -> void:
	# One drawer per band: a build tool takes the left band.  Stop-picking is
	# this drawer's own mode, so it leaves the panel alone.
	if tool != InputController.TOOL_NONE and tool != InputController.TOOL_STOP_PICK \
			and visible:
		visible = false


func _on_selection_changed(kind: String, entity_id: int, _tile: Vector2i) -> void:
	if kind == SelectionService.KIND_TRAIN and entity_id != 0 and _page == PAGE_TRAINS:
		_highlight(entity_id)
	_mark_dirty()


func _show_page(page: String) -> void:
	_page = page
	_list_page.visible = page == PAGE_TRAINS
	_route_editor.visible = page == PAGE_ROUTE
	_yard.visible = page == PAGE_YARD
	_filter_field.visible = page == PAGE_TRAINS
	for key in _tabs.keys():
		(_tabs[key] as Button).set_pressed_no_signal(key == page)
	_dirty = true


func _paint() -> void:
	var ids := session.trains.trains()
	_count_label.text = "%d train%s" % [ids.size(), "" if ids.size() == 1 else "s"]
	_empty_box.visible = ids.is_empty()
	var selected_train := selection != null and selection.selected_kind == SelectionService.KIND_TRAIN
	for train_id in _rows.keys():
		var row: TrainRow = _rows[train_id]
		var matches := _matches(train_id)
		row.visible = matches
		if matches:
			row.refresh()
		row.set_selected(selected_train and selection.selected_id == train_id)
		# The camera's own answer, so a follow begun on `F` or in the palette lights
		# this row too — the row must not disagree with the view it sits beside.
		row.set_following(camera_rig != null and camera_rig.followed_train_id() == train_id)
	_route_editor.refresh()
	_yard.refresh()
	_footer.text = _footer_text()


func _footer_text() -> String:
	if _page == PAGE_ROUTE:
		return "Add stops on the map · Esc backs out of pick mode"
	return "T opens this drawer · Esc closes it · F follows the selected train"


func _matches(train_id: int) -> bool:
	if _filter == "":
		return true
	var haystack := "%s %s %s %s" % [session.trains.name_of(train_id),
		session.trains.state_label(train_id), session.trains.destination_label(train_id),
		_cargo_words(train_id)]
	return haystack.to_lower().contains(_filter.to_lower())


func _cargo_words(train_id: int) -> String:
	var words := ""
	for cargo_id in (session.trains.capacity_by_cargo(train_id) as Dictionary).keys():
		words += " " + session.data.cargo_display(String(cargo_id))
	for batch in session.trains.batches(train_id):
		words += " " + session.data.cargo_display(String(batch["cargo"]))
	return words


func _highlight(train_id: int) -> void:
	if _rows.has(train_id):
		(_rows[train_id] as TrainRow).refresh()


# --- static layout --------------------------------------------------------

func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", GameTheme.GAP)
	add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", GameTheme.GAP)
	column.add_child(head)
	var title := GameTheme.heading("Trains & routes")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_count_label = GameTheme.small("")
	head.add_child(_count_label)
	var close := GameTheme.button_for("✕", "Close (Esc)")
	close.pressed.connect(_close)
	head.add_child(close)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	column.add_child(tabs)
	_tabs[PAGE_TRAINS] = _tab_button("Trains", "Every consist you own", PAGE_TRAINS)
	tabs.add_child(_tabs[PAGE_TRAINS])
	_tabs[PAGE_YARD] = _tab_button("Buy train", "Buy a new consist", PAGE_YARD)
	tabs.add_child(_tabs[PAGE_YARD])
	_tabs[PAGE_ROUTE] = _tab_button("Route", "The route of the train being edited", PAGE_ROUTE)
	tabs.add_child(_tabs[PAGE_ROUTE])

	_filter_field = LineEdit.new()
	_filter_field.placeholder_text = "Filter by name, status, station or cargo"
	_filter_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_field.text_changed.connect(func(text: String) -> void:
		_filter = text.strip_edges()
		_mark_dirty())
	column.add_child(_filter_field)

	var pages := VBoxContainer.new()
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages.add_theme_constant_override("separation", GameTheme.GAP)
	column.add_child(pages)

	_list_page = VBoxContainer.new()
	_list_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages.add_child(_list_page)

	_empty_box = VBoxContainer.new()
	_empty_box.add_theme_constant_override("separation", 6)
	_list_page.add_child(_empty_box)
	_empty_box.add_child(GameTheme.body("No trains yet", GameTheme.TEXT))
	_empty_box.add_child(GameTheme.paragraph(
		"Buy a consist at a station, then give it two stops to run between.",
		GameTheme.TEXT_DIM, 300.0))
	var buy_first := GameTheme.button_for("Buy a train", "Open the train yard")
	buy_first.pressed.connect(func() -> void: _show_page(PAGE_YARD))
	_empty_box.add_child(buy_first)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_page.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_list_box)

	_route_editor = RouteEditor.new()
	_route_editor.name = "RouteEditor"
	pages.add_child(_route_editor)
	_route_editor.close_requested.connect(func() -> void: _show_page(PAGE_TRAINS))

	_yard = TrainYard.new()
	_yard.name = "TrainYard"
	pages.add_child(_yard)
	_yard.cancel_requested.connect(func() -> void: _show_page(PAGE_TRAINS))
	_yard.bought.connect(_on_train_bought)

	_footer = GameTheme.small("")
	column.add_child(_footer)


func _tab_button(text: String, tooltip: String, page: String) -> Button:
	var button := GameTheme.toggle(text, tooltip)
	button.pressed.connect(func() -> void: _show_page(page))
	return button
