class_name TrainRow
extends PanelContainer

## One consist inside the trains drawer.
##
## The row is built when the train is created and afterwards only its text and
## its meter are rewritten: a drawer holding a dozen trains must never rebuild
## widgets on the simulation's 20 Hz cadence.  Every number here is a
## `TrainService` read — the row computes nothing about money or physics.

signal activated(train_id: int)
signal action(request: String, train_id: int)
signal rename_requested(train_id: int, new_name: String)

var session: GameSession
var train_id := 0

var _name_label: Label
var _name_field: LineEdit
var _state_stamp: Label
var _meter: ProgressBar
var _percent: Label
var _where_label: Label
var _consist_label: Label
var _cargo_label: Label
var _profit_label: Label
var _ledger_label: Label
var _sell_note: Label
var _follow_button: Button
var _sell_button: Button
var _rename_open := false
var _sell_armed := false
var _built := false


func _ready() -> void:
	_ensure_built()


## Build once, whoever arrives: the scene tree through `_ready`, or an orphan
## host (a headless test, a preview) through `bind`.  A row that only builds in
## `_ready` is a row that cannot be answered for outside a live viewport.
func _ensure_built() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", GameTheme.row(false))
	_build()
	gui_input.connect(_on_gui_input)


## Build the widgets once; `refresh` is the only thing called afterwards.
func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", GameTheme.GAP)
	column.add_child(head)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", GameTheme.FONT_STRONG)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text = true
	head.add_child(_name_label)
	_name_field = LineEdit.new()
	_name_field.visible = false
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_field.placeholder_text = "Train name"
	_name_field.text_submitted.connect(_on_name_submitted)
	_name_field.focus_exited.connect(_cancel_rename)
	head.add_child(_name_field)
	_percent = Label.new()
	_percent.add_theme_font_size_override("font_size", GameTheme.FONT_SMALL)
	head.add_child(_percent)
	_state_stamp = Label.new()
	_state_stamp.add_theme_font_size_override("font_size", GameTheme.FONT_SMALL)
	head.add_child(_state_stamp)

	_meter = ProgressBar.new()
	_meter.show_percentage = false
	_meter.min_value = 0.0
	_meter.max_value = 1.0
	_meter.custom_minimum_size = Vector2(0, 7)
	_meter.add_theme_stylebox_override("background", GameTheme.meter_track())
	_meter.add_theme_stylebox_override("fill", GameTheme.meter_fill())
	column.add_child(_meter)

	_where_label = GameTheme.body("", GameTheme.TEXT)
	column.add_child(_where_label)
	_consist_label = GameTheme.small("")
	column.add_child(_consist_label)
	_cargo_label = GameTheme.small("")
	column.add_child(_cargo_label)
	_profit_label = GameTheme.small("")
	column.add_child(_profit_label)
	_ledger_label = GameTheme.small("")
	column.add_child(_ledger_label)
	# Only ever visible while the destructive button below it is armed: the line
	# states in plain figures what confirming is about to do.
	_sell_note = GameTheme.small("", GameTheme.DANGER)
	_sell_note.visible = false
	column.add_child(_sell_note)
	column.add_child(_actions())


func _actions() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_follow_button = GameTheme.toggle("Follow", "Keep the camera on this train")
	_follow_button.toggled.connect(_on_follow_toggled)
	row.add_child(_follow_button)
	row.add_child(_action_button("Focus", "Centre the camera here", "focus"))
	row.add_child(_action_button("Route", "Edit this train's route", "route"))
	row.add_child(_action_button("Rename", "Name this train", "rename"))
	_sell_button = _action_button("Sell", "Sell the consist back at salvage value", "sell")
	row.add_child(_sell_button)
	return row


func _action_button(text: String, tooltip: String, request: String) -> Button:
	var button := GameTheme.button_for(text, tooltip)
	button.pressed.connect(func() -> void: _on_request(request))
	return button


func bind(game_session: GameSession, id: int) -> void:
	session = game_session
	train_id = id
	_ensure_built()
	refresh()


func set_selected(active: bool) -> void:
	add_theme_stylebox_override("panel", GameTheme.row(active))


## Report whether the camera is following this train, without the row owning
## any camera state: the drawer asks, the row only reflects it.
func set_following(following: bool) -> void:
	_follow_button.set_pressed_no_signal(following)


## Rewrite values only.  Safe to call at any UI refresh cadence.
func refresh() -> void:
	# `_ready` builds the widgets, so a row cannot paint before it is in the tree.
	if session == null or _name_label == null or session.trains.train(train_id).is_empty():
		return
	var trains := session.trains
	if not _rename_open:
		_name_label.text = trains.name_of(train_id)
	var state := trains.state_of(train_id)
	var colour := _state_colour(state)
	_state_stamp.text = trains.state_label(train_id).to_upper()
	_state_stamp.add_theme_color_override("font_color", colour)
	_meter.add_theme_stylebox_override("fill", GameTheme.meter_fill(colour))
	var moving := state == TrainService.State.MOVING
	_meter.value = trains.progress_fraction(train_id) if moving else 0.0
	_percent.text = GameTheme.percent(trains.progress_fraction(train_id)) if moving else ""
	_where_label.text = _where_text(state)
	_consist_label.text = _consist_text()
	_cargo_label.text = _cargo_text()
	_paint_profit(trains)
	_ledger_label.text = _ledger_text()
	_paint_sell_offer(trains)


## What the consist is making in the running calendar month, upkeep included —
## the subtraction is `TrainService.monthly_profit`'s, never this row's.
func _paint_profit(trains: TrainService) -> void:
	var profit := trains.monthly_profit(train_id)
	_profit_label.text = "Profit this month %s" % GameTheme.signed_money(profit)
	_profit_label.add_theme_color_override("font_color",
			GameTheme.GOOD if profit > 0.0 else (GameTheme.DANGER if profit < 0.0
					else GameTheme.TEXT_DIM))


func _where_text(state: int) -> String:
	var trains := session.trains
	if state == TrainService.State.LOST:
		return "No path — repair the line or re-route"
	var current := trains.current_station(train_id)
	# Only a train that actually flies a route is asked for its next stop: the
	# domain reads its stop list from a typed array, and the domain hands out an
	# untyped empty for a train with no route (reported as a domain gap), so the
	# question is one it cannot currently answer.
	var next := trains.next_station(train_id) if trains.route_of(train_id) != 0 else 0
	if state == TrainService.State.LOADING and current != 0:
		return "Loading at %s for %s" % [
			session.stations.name_of(current), trains.destination_label(train_id)]
	if next != 0:
		return "To %s for %s" % [session.stations.name_of(next),
			trains.destination_label(train_id)]
	var home := trains.home_station(train_id)
	if home != 0:
		return "Idle at %s · no route" % session.stations.name_of(home)
	return "Idle · no route"


func _consist_text() -> String:
	var parts: Array[String] = []
	var last := ""
	var runs := 0
	for stock_id in session.trains.stock_of(train_id):
		var def := session.data.stock(stock_id)
		var label := def.display_name if def != null else stock_id
		if label == last:
			runs += 1
			continue
		if last != "":
			parts.append(_run_text(last, runs))
		last = label
		runs = 1
	if last != "":
		parts.append(_run_text(last, runs))
	return "Consist: " + " · ".join(parts) if not parts.is_empty() else "No rolling stock"


func _run_text(label: String, count: int) -> String:
	return "%s ×%d" % [label, count] if count > 1 else label


## Carried cargo against consist capacity, in each cargo's own units.
func _cargo_text() -> String:
	var capacities: Dictionary = session.trains.capacity_by_cargo(train_id)
	if capacities.is_empty():
		return "No freight wagons — nothing to carry"
	var parts: Array[String] = []
	for cargo_id in capacities.keys():
		var id := String(cargo_id)
		var capacity := float(capacities[cargo_id])
		var loaded := session.trains.loaded_for(train_id, id)
		var def := session.data.cargo_def(id)
		var unit := def.unit_label if def != null else "units"
		parts.append("%s %d/%d %s" % [session.data.cargo_display(id),
			int(roundf(loaded)), int(roundf(capacity)), unit])
	return "Carrying " + " · ".join(parts)


func _ledger_text() -> String:
	var speed := session.trains.speed_kmh(train_id)
	return "%s · earned %s all-time · upkeep %s/mo" % [GameTheme.kmh(speed),
		GameTheme.money(session.trains.total_revenue(train_id)),
		GameTheme.money(session.trains.consist_running_cost(train_id))]


## The salvage figure, wherever selling is offered: in the tooltip always, and in
## a line of its own for as long as the confirm step is armed.  `refund_for` is
## the exact number `sell` will credit, so the promise cannot drift from the act.
func _paint_sell_offer(trains: TrainService) -> void:
	var pays := "pays back %s" % GameTheme.money(trains.refund_for(train_id))
	_sell_button.tooltip_text = "Sell the consist back at salvage value · " + pays
	_sell_note.text = "Sell · %s · press the button again to confirm" % pays
	_sell_note.visible = _sell_armed


func _state_colour(state: int) -> Color:
	match state:
		TrainService.State.MOVING:
			return GameTheme.GOOD
		TrainService.State.LOADING:
			return GameTheme.WARNING
		TrainService.State.LOST:
			return GameTheme.DANGER
	return GameTheme.TEXT_DIM


func begin_rename() -> void:
	_rename_open = true
	_name_field.visible = true
	_name_label.visible = false
	_name_field.text = session.trains.name_of(train_id)
	_name_field.grab_focus()
	_name_field.select_all()


func _cancel_rename() -> void:
	if not _rename_open:
		return
	_rename_open = false
	_name_field.visible = false
	_name_label.visible = true


func _on_name_submitted(new_name: String) -> void:
	_cancel_rename()
	var trimmed := new_name.strip_edges()
	if trimmed != "":
		rename_requested.emit(train_id, trimmed)


## Destructive actions arm in place rather than opening a modal.
func _on_request(request: String) -> void:
	if request != "sell":
		action.emit(request, train_id)
		return
	if _sell_armed:
		_sell_armed = false
		_sell_button.text = "Sell"
		_paint_sell_offer(session.trains)
		action.emit("sell", train_id)
		return
	_sell_armed = true
	_sell_button.text = "Confirm sell"
	# Stated the moment the row arms, not on the next refresh tick: the player
	# decides on this figure.
	_paint_sell_offer(session.trains)


func _on_follow_toggled(pressed: bool) -> void:
	action.emit("follow" if pressed else "unfollow", train_id)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		activated.emit(train_id)
