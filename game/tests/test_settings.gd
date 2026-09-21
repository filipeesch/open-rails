extends TestBase

## The options screen and the switch table behind it.
##
## The spec's §114 list is short and specific, so the checks are too: the screen
## offers exactly those switches, a change lands on the thing it names in the same
## frame, and a restart finds the values where they were left.

var settings: SettingsService


func setup() -> void:
	_erase_file()
	settings = SettingsService.new()


func teardown() -> void:
	if settings != null:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SettingsService.BUS_MASTER), 0.0)
		settings.reset_all()
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		tree.root.content_scale_factor = 1.0
	_erase_file()


# --- the catalogue --------------------------------------------------------

func test_the_screen_offers_exactly_the_switches_the_player_is_promised() -> void:
	var expected: Array[String] = [
		"master_volume", "music_volume", "effects_volume",
		"resolution", "fullscreen", "ui_scale",
		"camera_pan_speed", "camera_rotation_speed", "zoom_speed",
		"edge_scrolling",
	]
	check_eq(SettingsService.field_keys(), expected,
		"the settings table is the specification's list, in order")
	for key in expected:
		var field := SettingsService.field_for(key)
		check_neq(String(field.get("label", "")), "", "%s is named in words" % key)
		check_neq(String(field.get("kind", "")), "", "%s says how it is edited" % key)
		check_true(field.has("default"), "%s has a value a new install gets" % key)


func test_every_switch_comes_with_a_widget_that_can_actually_edit_it() -> void:
	var screen := SettingsPanel.new()
	screen.configure(settings)
	var controls: Array[String] = []
	for key in SettingsService.field_keys():
		var control := screen.control_for(key)
		check_true(control != null, "%s has a control on the screen" % key)
		match settings.kind_of(key):
			SettingsService.KIND_VOLUME, SettingsService.KIND_RANGE:
				check_true(control is Range, "%s is edited by dragging" % key)
			SettingsService.KIND_TOGGLE:
				check_true(control is CheckButton, "%s is a switch" % key)
			SettingsService.KIND_OPTION:
				check_true(control is HBoxContainer, "%s steps through its choices" % key)
		controls.append(key)
	check_eq(controls.size(), 10, "every promised switch made it onto the screen")
	screen.free()


func test_an_option_the_player_did_not_ask_for_is_refused_not_stored() -> void:
	check_false(settings.set_value("grain_of_film_grain", 0.5),
		"a key nobody promised is not silently accepted")
	check_false(settings.has_key("grain_of_film_grain"),
		"and it does not appear in the table either")
	var before: Variant = settings.get_value("resolution")
	check_false(settings.set_value("resolution", "37x41"),
		"a resolution that is not offered cannot be bought")
	check_eq(settings.get_value("resolution"), before,
		"the screen still shows what it had")
	settings.set_value("camera_pan_speed", 1000000.0)
	var field := SettingsService.field_for("camera_pan_speed")
	check_near(settings.as_float("camera_pan_speed"), float(field["max"]), "a slider thrown past its end stops at the end", 0.0001)


# --- applying -------------------------------------------------------------

func test_a_volume_setting_lands_on_the_bus_it_is_named_after() -> void:
	settings.ensure_audio_buses()
	check_true(AudioServer.get_bus_index(SettingsService.BUS_MASTER) >= 0,
		"the master bus exists to be turned")
	check_true(AudioServer.get_bus_index(SettingsService.BUS_MUSIC) >= 0,
		"a music bus exists, so music can be turned down on its own")
	check_true(AudioServer.get_bus_index(SettingsService.BUS_EFFECTS) >= 0,
		"and so does the one the construction noise goes through")
	settings.set_value("master_volume", 0.5)
	settings.set_value("music_volume", 0.25)
	settings.set_value("effects_volume", 1.0)
	check_near(db_to_linear(AudioServer.get_bus_volume_db(
		AudioServer.get_bus_index(SettingsService.BUS_MASTER))), 0.5, "the master dial is the master bus", 0.01)
	check_near(db_to_linear(AudioServer.get_bus_volume_db(
		AudioServer.get_bus_index(SettingsService.BUS_MUSIC))), 0.25, "the music dial is the music bus", 0.01)
	check_near(db_to_linear(AudioServer.get_bus_volume_db(
		AudioServer.get_bus_index(SettingsService.BUS_EFFECTS))), 1.0, "the effects dial is the effects bus", 0.01)


func test_the_interface_scale_resizes_the_interface_without_a_restart() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	check_true(tree != null and tree.root != null, "there is a window to scale")
	var before := tree.root.content_scale_factor
	settings.set_value("ui_scale", 1.0)
	check_near(tree.root.content_scale_factor, 1.0, "a hundred percent is exactly a hundred percent", 0.0001)
	settings.set_value("ui_scale", 1.5)
	check_near(tree.root.content_scale_factor, 1.5, "fifty percent more interface, same frame, no restart", 0.0001)
	check_eq(settings.display_value("ui_scale"), "150%",
		"and the record reads back in the units the player thinks in")
	settings.nudge("ui_scale", -1)
	check_near(tree.root.content_scale_factor, 1.25, "one step down from there is the next step, not a jump", 0.0001)
	settings.set_value("ui_scale", before)


func test_the_camera_moves_the_distance_the_player_asked_for() -> void:
	var view := TestView.stage()
	var controller := InputController.new()
	controller.configure(view.session, view.rig, view.selection)
	controller.viewport_size = TestView.VIEWPORT_SIZE
	controller.attach_settings(settings)
	check_near(controller.pan_speed, 900.0, "a fresh install drives the camera at the speed it always used", 0.0001)

	var slow := _pan_distance(controller, 24.0)
	settings.set_value("camera_pan_speed", 1800.0)
	check_near(controller.pan_speed, 1800.0, "the controller heard the setting", 0.0001)
	var fast := _pan_distance(controller, 24.0)
	check_near(fast / slow, 2.0, "double the pan speed is double the distance over the same gesture", 0.05)

	var wheel := _wheel_zoom(controller)
	settings.set_value("zoom_speed", 2.0)
	var doubled_wheel := _wheel_zoom(controller)
	check_gt(doubled_wheel, wheel * 1.8,
		"the zoom dial makes the wheel do more work per notch")

	settings.set_value("camera_rotation_speed", 1.2)
	check_near(controller.rotation_speed, 1.2, "a right-drag turns at the speed on the screen", 0.0001)

	settings.set_value("edge_scrolling", false)
	controller.viewport_size = TestView.VIEWPORT_SIZE
	var edge := InputEventMouseMotion.new()
	edge.position = Vector2(2.0, 2.0)
	controller._unhandled_input(edge)
	view.rig.target = view.rig.desired_target
	var before := view.rig.desired_target
	controller._process(0.2)
	check_near(view.rig.desired_target.distance_to(before), 0.0, "with edge scrolling off a cursor parked on the wall moves nothing", 0.0001)
	settings.set_value("edge_scrolling", true)
	controller._unhandled_input(edge)
	controller._process(0.2)
	check_gt(view.rig.desired_target.distance_to(before), 0.5,
		"and with it on, the same cursor glides")
	view.dispose()


# --- persistence ----------------------------------------------------------

func test_the_switches_are_where_they_were_left_after_a_restart() -> void:
	settings.set_value("ui_scale", 1.5)
	settings.set_value("camera_pan_speed", 1400.0)
	settings.set_value("edge_scrolling", false)
	settings.set_value("master_volume", 0.35)
	check_true(settings.dirty, "unsaved changes are honest about being unsaved")
	check_true(settings.save_settings(), "the file was written")
	check_false(settings.dirty, "and after writing there is nothing pending")

	var restarted := SettingsService.new()
	check_near(restarted.as_float("ui_scale"), 1.5, "the scale came back", 0.0001)
	check_near(restarted.as_float("camera_pan_speed"), 1400.0, "so did the hand speed", 0.0001)
	check_false(restarted.as_bool("edge_scrolling"), "so did a switch turned off")
	check_near(restarted.as_float("master_volume"), 0.35, "so did the volume", 0.0001)
	check_false(restarted.dirty, "a restart starts with nothing pending")
	var tree := Engine.get_main_loop() as SceneTree
	check_near(tree.root.content_scale_factor, 1.5, "and the interface is already the size the file says, before anyone opens the screen", 0.0001)


func test_closing_the_screen_is_what_writes_the_file() -> void:
	var screen := SettingsPanel.new()
	screen.configure(settings)
	settings.set_value("music_volume", 0.6)
	check_true(settings.dirty, "the change is live but not yet on disk")
	screen.open_panel()
	check_true(screen.is_open(), "the screen is open")
	screen.close_panel()
	check_false(screen.is_open(), "and closed")
	check_eq(screen.status_text(), "Saved.", "the screen says what it did")
	check_true(FileAccess.file_exists(SettingsService.SAVE_PATH), "the file is there")
	var restarted := SettingsService.new()
	check_near(restarted.as_float("music_volume"), 0.6, "the next session opens at that volume", 0.0001)
	screen.free()


func test_the_screen_follows_a_setting_changed_elsewhere() -> void:
	var screen := SettingsPanel.new()
	screen.configure(settings)
	settings.set_value("resolution", "2560x1440")
	check_eq(screen.value_text("resolution"), "2560 × 1440",
		"a change from anywhere shows up on the row")
	settings.nudge("edge_scrolling", 1)
	check_false(settings.as_bool("edge_scrolling"), "a switch flips off")
	var control := screen.control_for("edge_scrolling") as CheckButton
	check_false(control.button_pressed, "and its checkbox was told, not clicked")
	settings.set_value("ui_scale", 1.75)
	var slider := screen.control_for("camera_pan_speed") as Range
	settings.set_value("camera_pan_speed", 1150.0)
	var before := slider.value
	settings.set_value("camera_pan_speed", 1200.0)
	check_near(slider.value, 1200.0, "the slider was told the new number", 0.0001)
	check_eq(slider.value, before + 50.0,
		"it moved by exactly the step, so nothing echoed back into the store")
	check_eq(screen.value_text("camera_pan_speed"), "1200", "printed without a tail of zeros")
	screen.free()


# --- helpers --------------------------------------------------------------

func _pan_distance(controller: InputController, frames: float) -> float:
	var view_rig := controller.camera_rig
	view_rig.desired_target = view_rig.target
	var before := view_rig.target
	controller.pan_camera(Vector2.RIGHT, 0.05)
	controller.pan_camera(Vector2.RIGHT, 0.05)
	return before.distance_to(view_rig.target)


func _wheel_zoom(controller: InputController) -> float:
	var rig := controller.camera_rig
	rig.desired_ortho_size = rig.ortho_size
	var before := rig.desired_ortho_size
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.factor = 1.0
	controller._unhandled_input(wheel)
	var moved := absf(before - rig.desired_ortho_size)
	rig.desired_ortho_size = before
	rig.ortho_size = before
	return moved


func _erase_file() -> void:
	var directory := DirAccess.open("user://")
	if directory != null and directory.file_exists("settings.cfg"):
		directory.remove("settings.cfg")
