class_name TrainYard
extends PanelContainer

## Where a consist is bought: home station, locomotive, wagon counts, and every
## figure the form promises — price, capacity, weight, estimated speed, monthly
## running cost.
##
## Those figures come from one call, `TrainService.preview_consist`, which rates
## a not-yet-bought consist with the same code that rates a live train: what the
## yard shows is what the purchase delivers.  The panel sums nothing itself.
## Payment happens inside `TrainService.purchase`, so the panel never touches
## cash.  Rolling stock comes from the data registry, so a new wagon appears here
## without a code change.

signal bought(train_id: int)
signal cancel_requested()

var session: GameSession
var camera_rig: IsoCameraRig

var _station_select: OptionButton
var _loco_select: OptionButton
var _wagon_box: VBoxContainer
var _counts := {}
var _price_label: Label
var _cash_label: Label
var _capacity_label: Label
var _spec_label: Label
var _empty_hint: Label
var _buy_button: Button
var _reason_label: Label
var _station_key := ""
var _dirty := true
var _built := false


func _ready() -> void:
	_ensure_built()


## Build once, whoever arrives: `_ready` in the shipped scene, `attach` for an
## orphan host.  The yard built only in `_ready` would be an empty box in any
## host that wires it directly, which is every host that tests it.
func _ensure_built() -> void:
	if _built:
		return
	_built = true
	add_theme_stylebox_override("panel", GameTheme.panel(GameTheme.BACKGROUND))
	_build()


func attach(game_session: GameSession, rig: IsoCameraRig) -> void:
	session = game_session
	camera_rig = rig
	_ensure_built()
	_fill_loco_select()
	_fill_wagons()
	session.station_created.connect(_on_changed)
	session.station_removed.connect(_on_changed)
	session.station_renamed.connect(func(_id: int, _name: String) -> void: mark_dirty())
	session.economy.money_changed.connect(_on_changed)
	_dirty = true


func mark_dirty() -> void:
	_dirty = true


## Point the form at this station — how a player arrives from the inspector's "Buy
## a train here" rather than from the yard's own dropdown.  Says whether the
## station was on the list at all, so the drawer can answer in words when it was
## not, rather than opening a form that quietly ignored the request.
func select_station(station_id: int) -> bool:
	_ensure_built()
	if _station_select.item_count == 0:
		refresh()
	for index in _station_select.item_count:
		if int(_station_select.get_item_metadata(index)) == station_id:
			_station_select.select(index)
			mark_dirty()
			return true
	return false


func _on_changed(_argument: Variant = null) -> void:
	_dirty = true


## Called by the drawer's throttled refresh, and by nothing else: a control
## change sets the dirty flag, this paints it once.
func refresh() -> void:
	if not _dirty or session == null:
		return
	_dirty = false
	_paint_stations()
	_paint_consist()


func _paint_stations() -> void:
	var ids := session.stations.stations()
	var signature := ""
	for station_id in ids:
		signature += "%d," % station_id
	if signature == _station_key:
		return
	_station_key = signature
	var selected := _station_id()
	_station_select.clear()
	for station_id in ids:
		_station_select.add_item(session.stations.name_of(station_id))
		_station_select.set_item_metadata(_station_select.item_count - 1, station_id)
	for index in _station_select.item_count:
		if int(_station_select.get_item_metadata(index)) == selected:
			_station_select.select(index)
			break
	_station_select.visible = not ids.is_empty()
	_empty_hint.visible = ids.is_empty()


## Every figure the form promises, from one read of the domain — price, what it
## carries, how heavy it is, how fast it will run and what it costs to keep.  Run
## on the dirty flag only, so adding a wagon costs one consist rating.
func _paint_consist() -> void:
	var preview: Dictionary = session.trains.preview_consist(_consist_ids())
	var price := float(preview.get("price", 0.0))
	var cash := session.economy.cash
	var affordable := session.economy.can_afford(price) and session.stations.count() > 0
	_capacity_label.text = _capacity_text(preview.get("capacity", {}) as Dictionary)
	_spec_label.text = "Weight %s · estimated speed %s · upkeep %s/mo" % [
		GameTheme.tons(float(preview.get("weight_tons", 0.0))),
		GameTheme.kmh(float(preview.get("max_speed_kmh", 0.0))),
		GameTheme.money(float(preview.get("running_cost_month", 0.0)))]
	_price_label.text = "Price %s" % GameTheme.money(price)
	_price_label.add_theme_color_override("font_color",
			GameTheme.TEXT if affordable else GameTheme.DANGER)
	_cash_label.text = "Cash on hand %s" % GameTheme.money(cash)
	_buy_button.disabled = not affordable or _station_id() == 0
	_reason_label.visible = false


func _capacity_text(capacity: Dictionary) -> String:
	if capacity.is_empty():
		return "No wagons yet — a locomotive alone carries nothing"
	var parts: Array[String] = []
	for cargo_id in capacity.keys():
		var id := String(cargo_id)
		var def := session.data.cargo_def(id)
		var unit := def.unit_label if def != null else "units"
		parts.append("%s %d %s" % [session.data.cargo_display(id),
			int(roundf(float(capacity[id]))), unit])
	return "Capacity " + " · ".join(parts)


func _consist_ids() -> Array[String]:
	var ids: Array[String] = []
	var loco := _loco_id()
	if loco != "":
		ids.append(loco)
	for wagon_id in _counts.keys():
		var count := int(_counts[wagon_id].value)
		for _index in count:
			ids.append(String(wagon_id))
	return ids


func _station_id() -> int:
	var index := _station_select.selected
	if index < 0:
		return 0
	return int(_station_select.get_item_metadata(index))


func _loco_id() -> String:
	var index := _loco_select.selected
	if index < 0:
		return ""
	return String(_loco_select.get_item_metadata(index))


func _buy() -> void:
	var station_id := _station_id()
	if station_id == 0:
		return
	var result := session.trains.purchase(station_id, _loco_id(), _wagon_ids())
	if not bool(result.get("ok", false)):
		var reason := String(result.get("reason", "That purchase was refused"))
		_reason_label.text = reason
		_reason_label.visible = true
		session.notify(reason, "bad")
		_dirty = true
		return
	_reason_label.visible = false
	session.notify("Purchased %s for %s" % [session.trains.name_of(int(result["id"])),
		GameTheme.money(float(result.get("price", 0.0)))], "good")
	bought.emit(int(result["id"]))


func _wagon_ids() -> Array[String]:
	var ids: Array[String] = []
	for wagon_id in _counts.keys():
		var count := int(_counts[wagon_id].value)
		for _index in count:
			ids.append(String(wagon_id))
	return ids


func _focus_station() -> void:
	var station_id := _station_id()
	if camera_rig == null or station_id == 0:
		return
	camera_rig.stop_following()
	camera_rig.focus_tile(Vector2(session.stations.tile_of(station_id)) + Vector2(0.5, 0.5))


# --- static layout ---------------------------------------------------------

func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", GameTheme.GAP)
	add_child(column)

	var head := HBoxContainer.new()
	column.add_child(head)
	var title := GameTheme.heading("Buy a train")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := GameTheme.button_for("✕", "Back to the train list")
	close.pressed.connect(func() -> void: cancel_requested.emit())
	head.add_child(close)

	_empty_hint = GameTheme.paragraph(
		"No station yet — build one on the rail and a train can start there.",
		GameTheme.WARNING, 300.0)
	column.add_child(_empty_hint)

	# The order form scrolls; the price and the button do not, so a short window
	# never hides the thing the player is trying to press.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 6)
	scroll.add_child(form)

	form.add_child(GameTheme.paragraph(
		"A train starts at a station whose rail the line reaches, and its price leaves company cash.",
		GameTheme.TEXT_DIM, 300.0))
	_station_select = OptionButton.new()
	_station_select.item_selected.connect(func(_index: int) -> void: mark_dirty())
	form.add_child(_station_select)

	var station_row := HBoxContainer.new()
	form.add_child(station_row)
	var show := GameTheme.button_for("⌖ Look at station", "Centre the camera on it")
	show.pressed.connect(_focus_station)
	station_row.add_child(show)

	form.add_child(GameTheme.small("Locomotive", GameTheme.TEXT_DIM))
	_loco_select = OptionButton.new()
	# A different engine changes weight, speed and price, so the choice repaints
	# the statistics rather than waiting for the simulation to say something.
	_loco_select.item_selected.connect(func(_index: int) -> void: mark_dirty())
	form.add_child(_loco_select)

	form.add_child(GameTheme.small("Wagons", GameTheme.TEXT_DIM))
	_wagon_box = VBoxContainer.new()
	_wagon_box.add_theme_constant_override("separation", 4)
	form.add_child(_wagon_box)

	_capacity_label = GameTheme.paragraph("", GameTheme.TEXT_DIM, 300.0)
	column.add_child(_capacity_label)
	# A wrapping paragraph, not a clipping body label: this line carries weight,
	# speed and upkeep together and must never lose one of them to an ellipsis.
	_spec_label = GameTheme.paragraph("", GameTheme.TEXT, 300.0)
	column.add_child(_spec_label)
	_price_label = GameTheme.body("", GameTheme.TEXT)
	column.add_child(_price_label)
	_cash_label = GameTheme.small("")
	column.add_child(_cash_label)
	_reason_label = GameTheme.paragraph("", GameTheme.DANGER, 300.0)
	_reason_label.visible = false
	column.add_child(_reason_label)

	_buy_button = GameTheme.button_for("Buy train", "Pay for the consist and place it")
	_buy_button.pressed.connect(_buy)
	column.add_child(_buy_button)


func _fill_loco_select() -> void:
	for loco_id in session.data.locomotive_ids():
		var def := session.data.stock(loco_id)
		var label := def.display_name if def != null else loco_id
		if def != null:
			label += " · %s" % GameTheme.money(def.price)
		_loco_select.add_item(label)
		_loco_select.set_item_metadata(_loco_select.item_count - 1, loco_id)
	_loco_select.select(0)


func _fill_wagons() -> void:
	for wagon_id in session.data.wagon_ids():
		var def := session.data.stock(wagon_id)
		if def == null:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", GameTheme.GAP)
		var label := GameTheme.body("%s · %s" % [def.display_name, GameTheme.money(def.price)])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		label.tooltip_text = "%s %d %s · %s/mo upkeep" % [def.cargo.capitalize(),
			int(def.capacity), _unit_for(def.cargo), GameTheme.money(def.running_cost_month)]
		row.add_child(label)
		var spinner := SpinBox.new()
		spinner.min_value = 0.0
		spinner.max_value = 8.0
		spinner.step = 1.0
		spinner.custom_minimum_size = Vector2(64, 0)
		spinner.value = 1.0 if _counts.is_empty() else 0.0
		# Every figure on this form depends on the wagon count, so the spinner
		# dirties the whole form rather than one number.
		spinner.value_changed.connect(func(_value: float) -> void: mark_dirty())
		row.add_child(spinner)
		_counts[wagon_id] = spinner
		_wagon_box.add_child(row)


func _unit_for(cargo_id: String) -> String:
	var def := session.data.cargo_def(cargo_id)
	return def.unit_label if def != null else "units"
