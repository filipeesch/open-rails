class_name SettingsPanel
extends PanelContainer

## The options screen: the specification's list, built from the settings table.
##
## The screen holds no state of its own.  Every row is a projection of one
## `SettingsService` record — label, kind, current value — so the screen cannot
## offer a switch that does not exist, and cannot omit one that does.  Because
## the service *applies* what it stores, a row is a live control: dragging the
## interface-scale row resizes the interface in the same frame, and there is no
## "Apply" button to press and no restart to promise.
##
## Nothing here is modal.  Closing the screen writes the file; leaving without
## closing still leaves the applied values in force for the session.

signal closed()
signal saved(path: String)

const WIDTH := 460.0

var settings: SettingsService

var _rows := {}
var _list: VBoxContainer
var _status: Label
var _is_open := false


func attach(service: SettingsService) -> void:
	settings = service
	settings.setting_changed.connect(_on_setting_changed)
	_build()
	_refresh_all()


func configure(service: SettingsService) -> void:
	attach(service)


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, 0.0)
	add_theme_stylebox_override("panel", GameTheme.panel(GameTheme.BACKGROUND))


# --- the screen -----------------------------------------------------------

func open_panel() -> void:
	_is_open = true
	visible = true
	_refresh_all()


func close_panel() -> void:
	_is_open = false
	visible = false
	save_now()


func is_open() -> bool:
	return _is_open


func row_keys() -> Array[String]:
	var keys: Array[String] = []
	for field in SettingsService.FIELDS:
		keys.append(String(field["key"]))
	return keys


## The widget a player edits this setting with: a slider, a stepped selector or a
## checkbox.  Exposed so the screen itself can be driven and checked.
func control_for(key: String) -> Control:
	var row: Dictionary = _rows.get(key, {})
	return row.get("control", null) as Control


func value_text(key: String) -> String:
	var row: Dictionary = _rows.get(key, {})
	var label := row.get("value", null) as Label
	return label.text if label != null else ""


func status_text() -> String:
	return _status.text


func save_now() -> bool:
	if settings == null:
		return false
	var wrote := settings.save_settings()
	_status.text = "Saved." if wrote else "Could not write the settings file."
	if wrote:
		saved.emit(SettingsService.SAVE_PATH)
	return wrote


# --- building -------------------------------------------------------------

func _build() -> void:
	var box := VBoxContainer.new()
	box.name = "Rows"
	box.add_theme_constant_override("separation", GameTheme.GAP)
	add_child(box)

	var title := GameTheme.heading("Settings")
	title.name = "Title"
	box.add_child(title)
	box.add_child(_rule())

	_list = VBoxContainer.new()
	_list.name = "Settings"
	_list.add_theme_constant_override("separation", GameTheme.GAP)
	box.add_child(_list)

	for field in SettingsService.FIELDS:
		_list.add_child(_row_for_field(field))

	box.add_child(_rule())
	_status = GameTheme.small("Changes take effect at once.")
	_status.name = "Status"
	box.add_child(_status)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", GameTheme.GAP)
	box.add_child(footer)

	var reset := GameTheme.button_for("Reset to defaults",
		"Put every switch back to the value a new install gets.")
	reset.name = "Reset"
	reset.pressed.connect(func() -> void:
		settings.reset_all()
		save_now())
	footer.add_child(reset)

	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	var done := GameTheme.button_for("Done", "Close this screen and keep these settings.")
	done.name = "Done"
	done.pressed.connect(close_panel)
	footer.add_child(done)


func _row_for_field(field: Dictionary) -> Control:
	var key := String(field["key"])
	var line := HBoxContainer.new()
	line.name = "Row_" + key
	line.add_theme_constant_override("separation", GameTheme.GAP)

	var name_label := GameTheme.body(String(field["label"]))
	name_label.name = "Name"
	name_label.custom_minimum_size = Vector2(170.0, 0.0)
	line.add_child(name_label)

	var control := Control.new()
	match String(field["kind"]):
		SettingsService.KIND_VOLUME, SettingsService.KIND_RANGE:
			control = _slider_for_field(field, key)
		SettingsService.KIND_OPTION:
			control = _stepper_for_field(field, key)
		SettingsService.KIND_TOGGLE:
			control = _toggle_for_field(field, key)
	control.name = "Control"
	line.add_child(control)

	var value := GameTheme.small("")
	value.name = "Value"
	value.custom_minimum_size = Vector2(74.0, 0.0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(value)

	_rows[key] = {"control": control, "value": value, "name": name_label}
	return line


func _slider_for_field(field: Dictionary, key: String) -> Control:
	var slider := HSlider.new()
	slider.min_value = float(field["min"])
	slider.max_value = float(field["max"])
	slider.step = float(field.get("step", 0.01))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.editable = true
	slider.tooltip_text = String(field["label"])
	slider.value_changed.connect(func(value: float) -> void:
		settings.set_value(key, value))
	return slider


func _stepper_for_field(field: Dictionary, key: String) -> Control:
	# A stepped selector rather than a dropdown: the whole point of the screen is
	# that a change is visible immediately, and a dropdown hides the alternatives.
	var stepper := HBoxContainer.new()
	stepper.add_theme_constant_override("separation", 4.0)
	stepper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var less := GameTheme.toggle("−", "One step down")
	less.name = "Less"
	less.pressed.connect(func() -> void:
		settings.nudge(key, -1))
	var more := GameTheme.toggle("+", "One step up")
	more.name = "More"
	more.pressed.connect(func() -> void:
		settings.nudge(key, 1))
	var readout := Control.new()
	readout.name = "Track"
	readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stepper.add_child(less)
	stepper.add_child(readout)
	stepper.add_child(more)
	return stepper


func _toggle_for_field(field: Dictionary, key: String) -> Control:
	var check := CheckButton.new()
	check.name = "Switch"
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check.tooltip_text = String(field["label"])
	check.toggled.connect(func(on: bool) -> void:
		settings.set_value(key, on))
	return check


func _rule() -> Control:
	var line := Panel.new()
	line.custom_minimum_size = Vector2(0.0, 1.0)
	line.add_theme_stylebox_override("panel", GameTheme.row(false))
	return line


# --- keeping the rows honest ----------------------------------------------

func _on_setting_changed(key: String, _value: Variant) -> void:
	_refresh_row(key)


func _refresh_all() -> void:
	for key in _rows.keys():
		_refresh_row(key)


func _refresh_row(key: String) -> void:
	if not _rows.has(key) or settings == null:
		return
	var row: Dictionary = _rows[key]
	var control := row.get("control", null) as Control
	if control is HSlider:
		var slider := control as HSlider
		var wanted := settings.as_float(key)
		if absf(slider.value - wanted) > 0.0001:
			# Written back without an echo: the service already has this value, so
			# the slider is being *told*, not edited.
			slider.set_value_no_signal(wanted)
	elif control is CheckButton:
		var check := control as CheckButton
		check.set_pressed_no_signal(settings.as_bool(key))
	var value := row.get("value", null) as Label
	if value != null:
		value.text = settings.display_value(key)
