class_name TestUiControls
extends TestBase

## Every control the player can press, pressed.
##
## The rest of the suite asks a panel to *report* the domain correctly.  This file
## asks the other question — whether the thing a player clicks actually does the
## thing its own label promises — and it asks it of controls nobody was checking:
## the reorder and clear buttons inside the route editor, the palette's save and
## load commands, the options screen's steppers, the map screen's Back.  Two
## invariants run through it.  A control that leads nowhere is a dead button, so
## every button the shell builds is walked and required to be connected to
## something.  And a control that holds a state nobody chose is a button that
## lies, so a momentary verb must not come back lit.
##
## Key hints are graded here too, and deliberately not through `KeyHints`: a hint
## checked against the class that writes it can only agree with itself, so the
## expected letter is taken out of the InputMap the handlers ask about.

var view: TestView
var input: InputController
var line: Dictionary


func setup() -> void:
	_erase_settings_file()
	view = TestView.stage()
	input = InputController.new()
	input.attach(view.session, view.rig, view.selection)
	line = TestSession.coal_line(view.session)
	check_true(bool(line["ok"]), "a valley with a working coal line to click at: " + String(line["reason"]))


func teardown() -> void:
	input.free()
	view.dispose()
	view = null
	input = null
	line = {}
	# Several cases here drive the real options screen, whose switches reach into
	# the engine (a bus volume, the content scale) and whose Done button writes the
	# settings file.  Left behind, that file would be the starting world of the
	# next test file, which is exactly the kind of lie this suite exists to catch.
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		tree.root.content_scale_factor = 1.0
	var master := AudioServer.get_bus_index(SettingsService.BUS_MASTER)
	if master >= 0:
		AudioServer.set_bus_volume_db(master, 0.0)
	_erase_settings_file()
	# The hand-off across the scene swap is a static, and a stale one would name a
	# save or a company to the next file's session.
	SandboxIntent.clear()


# --- dead controls ---------------------------------------------------------

func test_no_button_in_the_shell_ships_with_nothing_behind_it() -> void:
	## Walk the interface the shipped shell builds and refuse to ship a button that
	## is connected to nothing: a label with no verb under it is discovered by the
	## player, always, and always at the worst moment.
	var screens: Array[Control] = []
	var toolbar := BottomToolbar.new()
	toolbar.attach(view.session, input)
	screens.append(toolbar)
	var hud := Hud.new()
	hud.attach(view.session)
	screens.append(hud)
	var tools := ToolPanel.new()
	tools.attach(view.session, input)
	screens.append(tools)
	var books := CompanyPanel.new()
	books.attach(view.session, input)
	screens.append(books)
	var inspector := ContextInspector.new()
	inspector.attach(view.session, view.selection, view.rig)
	view.selection.select_station(int(line["mine_station"]))
	screens.append(inspector)
	var drawer := TripPanel.new()
	drawer.attach(view.session, input, view.selection, view.rig)
	drawer.open_route_for(int(line["train"]))
	drawer.refresh_now()
	screens.append(drawer)
	var palette := CommandPalette.new()
	palette.attach(view.session, input, view.rig, view.selection)
	screens.append(palette)
	var options := SettingsPanel.new()
	options.attach(SettingsService.new())
	screens.append(options)

	var seen := 0
	for screen in screens:
		var label := _screen_name(screen)
		var buttons := _buttons_of(screen)
		var switches := screen.find_children("*", "CheckButton", true, false)
		# A `toggle_mode` Button is wired to `toggled` — that is the signal that
		# carries the state a switch exists to hold — and a plain one to `pressed`.
		# Either is a live wire; demanding one particular name here would fail the
		# controls that are wired correctly and say nothing about the dead ones.
		var pressables := buttons.size() + switches.size()
		if screen is CommandPalette:
			check_eq(pressables, 0, "%s is a search box and a list, not a row of buttons" % label)
		else:
			check_gt(pressables, 0, "%s offers the player something to press" % label)
		for button in buttons:
			seen += 1
			# A dropdown answers on `item_selected`, which is the only signal that
			# carries the choice it exists to make; a plain button on `pressed` and
			# a switch on `toggled`.  Any one of them is a live wire.
			var wired := button.pressed.get_connections().size() \
					+ button.toggled.get_connections().size()
			if button is OptionButton:
				wired += (button as OptionButton).item_selected.get_connections().size()
			check_gt(wired, 0, "the button saying \"%s\" on %s is wired to something" \
					% [button.text, label])
		for switch in switches:
			seen += 1
			var toggle := switch as CheckButton
			check_gt(toggle.toggled.get_connections().size() \
					+ toggle.pressed.get_connections().size(), 0,
					"the switch saying \"%s\" on %s is wired to something" % [toggle.text, label])
	check_gt(seen, 25, "the shell offers a real surface of controls, not a token few")

	for screen in screens:
		screen.free()


func test_the_map_screen_s_back_button_is_a_verb_not_a_state() -> void:
	## "Back" is a door, not a switch.  A `toggle_mode` Button keeps itself pressed
	## after one click — the behaviour this project leans on for the tool palette —
	## so a momentary verb built as a toggle comes back lit and claims a choice that
	## was never made.
	var screen := NewSandbox.new()
	screen.configure(_registry())
	# A lambda captures a local by value, so the tally lives in a box the closure
	# can actually reach into — an `int` here would stay 0 however often it fired.
	var fired := []
	screen.cancelled.connect(func() -> void: fired.append(1))
	var back := screen.find_child("Back", true, false) as Button
	check_true(back != null, "the map screen has a Back button")
	back.pressed.emit()
	check_eq(fired.size(), 1, "pressing it asks to go back")
	check_false(back.button_pressed, "and it does not stay lit afterwards")
	back.pressed.emit()
	check_eq(fired.size(), 2, "and it is a verb that fires again, not a latch")
	var choice := screen.find_child("Map_founders_valley", true, false) as Button
	check_true(choice != null, "the shipped valley is offered as a choice")
	choice.pressed.emit()
	check_true(choice.button_pressed, "a map row is a state, so it may hold itself down")
	screen.free()


# --- key hints -------------------------------------------------------------

func test_the_dial_names_the_key_the_engine_answers_to() -> void:
	## The speed row is where a player learns that Space and 1/2/3 exist, and the
	## spec asks that the speeds be reachable from anywhere in the interface.  The
	## tooltip and the binding are therefore checked against the InputMap itself.
	var hud := Hud.new()
	hud.attach(view.session)
	check_eq(hud.speed_buttons.size(), view.session.clock.SPEED_LABELS.size(),
			"one button per dial position the clock offers")
	check_eq(Hud.SPEED_ACTIONS.size(), hud.speed_buttons.size(),
			"and one action named per button, so the lists cannot drift apart")
	for index in hud.speed_buttons.size():
		var action: String = String(Hud.SPEED_ACTIONS[index])
		check_true(InputMap.has_action(action), "position %d names an action the engine knows" % index)
		var key := _bound_key(action)
		check_neq(key, "", "%s is bound to a real key, not merely declared" % action)
		check_has(hud.speed_buttons[index].tooltip_text, "(%s)" % key,
				"and the button shows the player that key, not a remembered one")
	hud.free()


func test_the_palette_names_the_key_the_engine_answers_to() -> void:
	## Three palette commands spell out a shortcut.  They are built from the action
	## each one's own `run` closure performs, so the check is that the letter on the
	## screen is the binding in the engine — letter for letter.
	var palette := CommandPalette.new()
	palette.attach(view.session, input, view.rig, view.selection)
	for id in CommandPalette.COMMAND_KEYS.keys():
		var action: String = String(CommandPalette.COMMAND_KEYS[id])
		check_true(InputMap.has_action(action), "%s points at an action the engine knows" % id)
		var label := _palette_label(palette, String(id))
		check_neq(label, "", "and the palette still offers the command: " + String(id))
		var key := _bound_key(action)
		check_neq(key, "", "%s is bound to something" % action)
		check_has(label, "(%s)" % key, "so \"%s\" may advertise %s" % [label, key])
	palette.free()


# --- the palette's list of the world -----------------------------------------

func test_the_palette_lets_go_of_a_station_the_valley_gave_back() -> void:
	## A command naming a yard that no longer exists takes the camera to where that
	## yard used to be.  The list has to follow the world in both directions.
	var palette := CommandPalette.new()
	palette.attach(view.session, input, view.rig, view.selection)
	var station_id := int(line["mine_station"])
	var yard := view.session.stations.name_of(station_id)
	check_neq(_palette_label_containing(palette, yard), "",
			"the yard is offered while it stands")
	view.session.stations.remove_station(station_id)
	check_eq(_palette_label_containing(palette, yard), "",
			"and the command goes the moment the station does — nothing to focus")
	palette.free()


func test_a_loaded_valley_replaces_every_name_the_palette_holds() -> void:
	## Loading is not an edit, it is a different world.  The commands must speak of
	## the valley now in play, or the palette spends the rest of the session
	## offering places that were never on this map.
	var palette := CommandPalette.new()
	palette.attach(view.session, input, view.rig, view.selection)
	var path := view.session.save_path("uitest_palette")
	check_true(bool(view.session.save_to(path).get("ok", false)), "the valley is on disk")
	var yard := view.session.stations.name_of(int(line["mine_station"]))
	view.session.stations.rename(int(line["mine_station"]), "Wren's Halt")
	check_neq(_palette_label_containing(palette, "Wren's Halt"), "",
			"a renamed yard is offered under its new name")
	check_true(bool(view.session.load_from(path).get("ok", false)), "and the save comes back")
	check_neq(_palette_label_containing(palette, yard), "",
			"the loaded world's own names are what the palette lists")
	check_eq(_palette_label_containing(palette, "Wren's Halt"), "",
			"and the name the load undid is gone with it")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	palette.free()


func test_the_palette_says_what_a_save_and_a_load_actually_did() -> void:
	## `save_to` and `load_from` answer with a verdict.  A command that reports
	## success whatever that verdict says is the most expensive kind of dead button:
	## the player believes the valley is on disk and finds out otherwise at the worst
	## possible moment.
	var notices: Array[String] = []
	view.session.notice.connect(func(message: String, _severity: String) -> void:
		notices.append(message))
	var palette := CommandPalette.new()
	palette.attach(view.session, input, view.rig, view.selection)

	palette._save_quicksave()
	check_gt(notices.size(), 0, "the save said something")
	check_has(notices[notices.size() - 1], "Saved", "and said it honestly: " + notices[notices.size() - 1])
	check_true(FileAccess.file_exists(view.session.save_path("quicksave")),
			"the file the command named really is there")

	# A file that is not a save: the load must refuse in words, not announce a load.
	var bogus := view.session.save_path("autosave_1899_01")
	check_true(write_json(bogus, {"not": "a save"}), "a bogus autosave is in place")
	notices.clear()
	palette._load_latest()
	var last := notices[notices.size() - 1]
	check_false(last.begins_with("Loaded"), "a load that failed is not reported as a load: " + last)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bogus))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(view.session.save_path("quicksave")))
	palette.free()


# --- the options screen ----------------------------------------------------

func test_the_option_steppers_press_once_and_let_go() -> void:
	## `−` and `+` change a value by one step.  They are verbs: a value that went up
	## is not "still going up", and a button still lit after the click says it is.
	var settings := SettingsService.new()
	var panel := SettingsPanel.new()
	panel.attach(settings)
	panel.open_panel()
	# The row is looked up by key, not by searching for the first `−` on screen:
	# the resolution stepper sits above this one and answers to the same name.
	var before := panel.value_text("ui_scale")
	var stepper := panel.control_for("ui_scale")
	check_true(stepper != null, "a stepped row was built for this setting")
	var less := stepper.get_node("Less") as Button
	var more := stepper.get_node("More") as Button
	check_true(less != null and more != null, "and it shows one button per direction")
	more.pressed.emit()
	check_neq(panel.value_text("ui_scale"), before, "one press raises the value one step")
	check_false(more.button_pressed, "and the button does not sit there claiming it is still pressed")
	var middle := panel.value_text("ui_scale")
	less.pressed.emit()
	check_eq(panel.value_text("ui_scale"), before, "the other direction is the inverse, step for step")
	check_false(less.button_pressed, "and it lets go of its own highlight too")
	panel.close_panel()
	settings.reset_all()
	panel.free()


func test_the_options_screen_opens_on_its_key_and_answers_to_escape() -> void:
	## In the running game the options screen used to be reachable one way only:
	## Ctrl+K and then type.  A volume slider behind a search box is a long way to
	## reach, so `O` opens it — and because it sits in the modal layer rather than in
	## the drawer band, `active_panel` never names it, which left it out of the
	## Escape ladder entirely.  It is the top of that ladder now.
	check_true(InputMap.has_action("settings_panel"), "the engine knows the action")
	check_neq(_bound_key("settings_panel"), "", "and a real key is bound to it")
	var settings := SettingsService.new()
	var panel := SettingsPanel.new()
	panel.attach(settings)
	# The hand-off the running game makes: the root builds both the screen and the
	# controller and tells one where the other is.  A group lookup would need a
	# live tree, which this runner never gives it — and a control that can only be
	# found by an engine that happens to be iterating is a control that cannot be
	# tested, which is how this door went unwatched in the first place.
	input.attach_settings_screen(panel)
	check_false(panel.is_open(), "it starts closed")
	check_true(input.open_settings(), "the key's verb opens it")
	check_true(panel.is_open(), "and the screen is standing open")
	input.cancel()
	check_false(panel.is_open(), "Escape puts the covering screen down first")
	input.attach_settings_screen(null)
	settings.reset_all()
	panel.free()


# --- the route editor, button by button -------------------------------------

func test_the_stop_buttons_move_and_remove_the_stop_they_stand_beside() -> void:
	## The arrows and the ✕ on a stop row act on that row, in the domain, and the
	## order the player left them in is the order the train runs.  Three stops, not
	## two: with two, a reorder and a removal are the same pair of moves and the
	## removal ends the timetable outright — which hides exactly the mistake this
	## case is here to catch, a button acting on the row above its own.
	var drawer := TripPanel.new()
	drawer.attach(view.session, input, view.selection, view.rig)
	var train := int(line["train"])
	drawer.open_route_for(train)
	drawer.refresh_now()
	var editor := drawer._route_editor
	var route_id := view.session.routes.route_for_train(train)
	var notices: Array[String] = []
	view.session.notice.connect(func(message: String, _severity: String) -> void:
		notices.append(message))

	var path := view.session.routes.path_of(route_id)
	var beside := Vector2i(int(path[1].x), int(path[1].y))
	var third := TestSession.station_for_tile(view.session, beside, "Newlay Halt", false)
	check_neq(third, 0, "a third platform can stand on this line")
	if third == 0:
		drawer.free()
		return
	drawer.refresh_now()
	var add := _button_named(editor, "Newlay Halt")
	check_true(add != null, "and the editor offers it as a stop to add")
	if add == null:
		drawer.free()
		return
	add.pressed.emit()
	drawer.refresh_now()
	var before := view.session.routes.station_ids(route_id)
	check_eq(before.size(), 3, "pressing it ran a three-stop timetable")

	# Rows are pooled and repainted, so each press reads the row again: a Dictionary
	# held across a repaint would be a button aimed at a stale index.
	var first: Dictionary = editor._stop_rows[0]
	check_true((first["up"] as Button).disabled, "the first stop has nowhere earlier to go")
	check_true((editor._stop_rows[2]["down"] as Button).disabled, "and the last has nowhere later")
	check_eq(String(first["name"].text), view.session.stations.name_of(before[0]),
			"a row is labelled with the stop it stands on")
	(first["down"] as Button).pressed.emit()
	drawer.refresh_now()
	var after_down := view.session.routes.station_ids(route_id)
	check_eq(after_down[0], before[1], "↓ took that row's stop down with it")
	check_eq(after_down[1], before[0], "and the stop it passed is where that row stood")

	# The way back is pressed on the row the stop landed on — the row that now
	# carries it, not the one it started on.
	((editor._stop_rows[1]["up"]) as Button).pressed.emit()
	drawer.refresh_now()
	check_eq(view.session.routes.station_ids(route_id), before, "↑ on that row puts it back")

	var middle: Dictionary = editor._stop_rows[1]
	var middle_id := before[1]
	check_eq(String(middle["name"].text), view.session.stations.name_of(middle_id),
			"the middle row still names the stop its ✕ belongs to")
	(middle["remove"] as Button).pressed.emit()
	drawer.refresh_now()
	var left := view.session.routes.station_ids(route_id)
	check_eq(left.size(), 2, "one press took exactly one stop out of the timetable")
	check_false(left.has(middle_id), "and it is the stop that row was standing beside")
	check_neq(view.session.routes.route_for_train(train), 0,
			"two stops is still a timetable, so the route survives it")

	# Down below two stops there is nothing to run, and the claim of this screen is
	# that every edit lands the moment it happens — so the stale route has to go.
	((editor._stop_rows[1]["remove"]) as Button).pressed.emit()
	drawer.refresh_now()
	check_eq(view.session.routes.route_for_train(train), 0,
			"a one-stop draft takes the stale timetable down with it")
	check_has(notices[notices.size() - 1], "needs two stops",
			"and the screen says why in words: " + notices[notices.size() - 1])
	drawer.free()


func test_clearing_a_route_takes_the_timetable_off_the_train() -> void:
	## "Clear route" says the train stops running a timetable.  It must not merely
	## empty the panel while the domain keeps the route it had.
	var drawer := TripPanel.new()
	drawer.attach(view.session, input, view.selection, view.rig)
	drawer.open_route_for(int(line["train"]))
	drawer.refresh_now()
	var editor := drawer._route_editor
	var route_id := view.session.routes.route_for_train(int(line["train"]))
	check_gt(route_id, 0, "the train has a route to lose")
	var notices: Array[String] = []
	view.session.notice.connect(func(message: String, _severity: String) -> void:
		notices.append(message))
	editor._clear_button.pressed.emit()
	drawer.refresh_now()
	check_eq(view.session.routes.route_for_train(int(line["train"])), 0,
			"the domain has no route for the train any more")
	check_has(notices[notices.size() - 1], "cleared", "and the panel says so out loud")
	drawer.free()


func test_a_station_already_on_the_route_is_refused_rather_than_doubled() -> void:
	## The reachable list is supposed to hide stops the route already has; if one
	## arrives anyway — from a stale row, from a map pick — the answer is a reason,
	## not a second stop and not silence.
	var drawer := TripPanel.new()
	drawer.attach(view.session, input, view.selection, view.rig)
	drawer.open_route_for(int(line["train"]))
	drawer.refresh_now()
	var editor := drawer._route_editor
	var route_id := view.session.routes.route_for_train(int(line["train"]))
	var notices: Array[String] = []
	view.session.notice.connect(func(message: String, _severity: String) -> void:
		notices.append(message))
	editor.add_station(int(line["mine_station"]))
	check_eq(view.session.routes.station_ids(route_id).size(), 2,
			"the duplicate never reached the timetable")
	check_gt(notices.size(), 0, "and the refusal was said, not swallowed")
	drawer.free()


func test_the_look_at_station_button_moves_the_camera_and_nothing_else() -> void:
	## A ⌖ beside a station centres the camera on it.  It buys nothing, plans
	## nothing and spends nothing: the check is that it does the one thing.
	var drawer := TripPanel.new()
	drawer.attach(view.session, input, view.selection, view.rig)
	drawer.open_route_for(int(line["train"]))
	drawer.refresh_now()
	var editor := drawer._route_editor
	var cash_before := view.session.economy.cash
	var route_id := view.session.routes.route_for_train(int(line["train"]))
	var stops_before := view.session.routes.stop_count(route_id)
	var station_id := int(line["mine_station"])
	view.rig.target = Vector3.ZERO
	view.rig.follow_train(int(line["train"]), Callable())
	editor._focus_station(station_id)
	var wanted := Vector2(view.session.stations.tile_of(station_id)) + Vector2(0.5, 0.5)
	check_lt(absf(view.rig.desired_target.x - wanted.x) + absf(view.rig.desired_target.z - wanted.y),
			0.001, "the button commands the view toward the station it stands beside")
	check_false(view.rig.is_following(),
			"and it lets go of any train being followed, rather than fighting the player's choice")
	# The rig eases; a press is a command, not a teleport — that is the promise the
	# camera makes everywhere else, so this control is graded on where it arrives.
	view.settle()
	check_lt(absf(view.rig.target.x - wanted.x) + absf(view.rig.target.z - wanted.y), 0.02,
			"eased to a stop, the view is centred on that station")
	check_eq(view.session.economy.cash, cash_before, "and nothing was spent to look")
	check_eq(view.session.routes.stop_count(view.session.routes.route_for_train(int(line["train"]))),
			stops_before, "and no stop was added or removed by looking")
	drawer.free()


func test_the_pick_button_becomes_the_pick_it_arms() -> void:
	## "Add stop on map" arms a tool.  While that tool is in hand the button must
	## say what it now is, because the second click has to cancel rather than arm a
	## second time.
	var drawer := TripPanel.new()
	drawer.attach(view.session, input, view.selection, view.rig)
	drawer.open_route_for(int(line["train"]))
	drawer.refresh_now()
	var editor := drawer._route_editor
	var button := editor._pick_button
	var was := button.text
	button.pressed.emit()
	drawer.refresh_now()
	check_neq(button.text, was, "arming pick mode changed what the button says")
	check_has(button.text, "ick", "it names the pick it is offering: " + button.text)
	check_true(editor._picking, "and the editor knows the tool is in hand")
	var stops_before := view.session.routes.stop_count(view.session.routes.route_for_train(int(line["train"])))
	button.pressed.emit()
	drawer.refresh_now()
	check_false(editor._picking, "a second press puts the pick down instead of arming it again")
	check_eq(view.session.routes.stop_count(view.session.routes.route_for_train(int(line["train"]))),
			stops_before, "and no stop arrived while all this was happening")
	drawer.free()


# --- the doors that were painted on the wall ------------------------------

func test_the_world_entry_opens_the_valley_screen_it_promised() -> void:
	## The toolbar has offered World since the first cut of the shell, and pressing
	## it lit the button and opened nothing.  The spec names that entry, so the fix
	## was the screen — and this is the case that fails the moment either half of
	## the pair comes apart.
	var world := WorldPanel.new()
	world.attach(view.session, input, view.rig)
	var toolbar := BottomToolbar.new()
	toolbar.attach(view.session, input)
	var entry := _button_named(toolbar, "World")
	check_true(entry != null, "the toolbar still offers the entry the specification names")

	input.open_panel(InputController.PANEL_WORLD)
	check_true(world.is_open(), "pressing World opens the valley screen")
	check_true(entry.button_pressed, "and the entry says so")
	world.refresh_now()
	var text := _labels_of(world)
	for town_id in view.session.towns.towns():
		check_has(text, view.session.towns.name_of(town_id),
				"every settlement is named on the screen that claims to list them")
	for industry_id in view.session.industries.industries():
		check_has(text, view.session.industries.name_of(industry_id),
				"and so is every work")
	check_has(text, "per month", "the figures are per month, which is the unit the game runs on")

	var close := world.find_child("Close", true, false) as Button
	check_true(close != null, "the screen carries its own way out")
	close.pressed.emit()
	check_false(world.is_open(), "the ✕ puts it down")
	check_eq(input.active_panel, "",
			"and the shared panel state stops claiming it is open, so the toolbar lets go of it")
	toolbar.free()
	world.free()


func test_the_valley_screen_s_camera_button_centers_the_place_it_stands_beside() -> void:
	## Each row offers one verb — ⌖ — and it had better be that row's place: a
	## button that moves the camera to the wrong town teaches the player to
	## distrust every camera button in the game.
	var world := WorldPanel.new()
	world.attach(view.session, input, view.rig)
	world.refresh_now()
	var town_id := view.session.towns.principal_town()
	check_neq(town_id, 0, "the valley has a principal town to look at")
	view.rig.target = Vector3.ZERO
	world._focus_tile(view.session.towns.tile_of(town_id))
	var wanted := Vector2(view.session.towns.tile_of(town_id)) + Vector2(0.5, 0.5)
	check_lt(absf(view.rig.desired_target.x - wanted.x) + absf(view.rig.desired_target.z - wanted.y),
			0.001, "the command is for the tile that row was drawn for")
	view.settle()
	check_lt(absf(view.rig.target.x - wanted.x) + absf(view.rig.target.z - wanted.y), 0.02,
			"and after the easing the view is standing on it")
	world.free()


func test_the_build_readout_builds_when_it_says_build() -> void:
	## The readout relabelled itself "Click to build" while its handler was
	## permanently `input.cancel()` — so the player who read the label and clicked
	## put the tool down instead of laying the line.  The tool is run here the way it
	## is run in play: a click stakes the line, the pointer moves, and then the
	## button that calls itself a build is pressed.
	var panel := ToolPanel.new()
	panel.attach(view.session, input)
	var stake := _open_run_origin()
	check_neq(stake, Vector2i(-1, -1), "there is open country to lay a line across")
	if stake == Vector2i(-1, -1):
		panel.free()
		return
	var end := Vector2i(stake.x + 3, stake.y)
	input.arm_tool(InputController.TOOL_RAIL)
	view.selection.hovered_tile = stake
	input.build_at(stake)
	view.selection.hovered_tile = end
	input._refresh_ghost()
	check_eq(panel.state(), "ok", "the ghost is standing on a line that can be laid")
	check_has(panel.action_button.text, "Lay",
			"and the button is named for the tool in hand: " + panel.action_button.text)
	var cash_before := view.session.economy.cash
	panel.action_button.pressed.emit()
	check_true(view.session.rail.network.has_rail(end),
			"the press the button called a build laid the track it was showing")
	check_lt(view.session.economy.cash, cash_before, "at a price, out through the ledger")
	check_eq(input.tool, InputController.TOOL_RAIL, "and a build is not an exit — the tool stayed in hand")
	panel.free()


func test_the_build_readout_offers_cancel_only_when_it_means_cancel() -> void:
	## The other half of the same claim: "Cancel" is a promise that pressing it ends
	## the tool, so it may appear only where the ghost has been refused — and there
	## it must really put the tool down.
	var panel := ToolPanel.new()
	panel.attach(view.session, input)
	var off_line := _open_run_origin()
	check_neq(off_line, Vector2i(-1, -1), "there is open country to stand the remove tool over")
	if off_line == Vector2i(-1, -1):
		panel.free()
		return
	input.arm_tool(InputController.TOOL_REMOVE)
	input._update_ghost_at_mouse(view.screen_of_tile(off_line))
	check_eq(panel.state(), "invalid", "there is no track out there to remove")
	check_eq(panel.action_button.text, "Cancel", "so the only true word is the one it says")
	check_has(panel.action_button.tooltip_text, KeyHints.hint_suffix("tool_cancel"),
			"and it names the key that does the same thing, read out of the engine")
	panel.action_button.pressed.emit()
	check_eq(input.tool, InputController.TOOL_NONE, "pressing it put the tool down")
	panel.free()


func test_the_follow_row_lights_when_the_camera_starts_following_elsewhere() -> void:
	## The row's Follow switch was driven by the drawer's own memory of who it had
	## told the camera to chase.  Following on `F`, or from the palette, moved the
	## view while the row sat dark — the panel disagreeing with the valley beside it.
	var drawer := TripPanel.new()
	drawer.attach(view.session, input, view.selection, view.rig)
	drawer.refresh_now()
	var train := int(line["train"])
	check_true(drawer._rows.has(train), "the consist has a row to light up")
	var row = drawer._rows[train]
	check_false(row._follow_button.button_pressed, "nobody is being followed yet")
	view.selection.select_train(train)
	input.focus_selection()
	check_true(view.rig.is_following(), "`F` took up the chase")
	drawer.refresh_now()
	check_true(row._follow_button.button_pressed,
			"and the row the camera disagrees with no longer exists")
	view.rig.stop_following()
	drawer.refresh_now()
	check_false(row._follow_button.button_pressed, "letting go goes dark the same way")
	drawer.free()


func test_the_menu_carries_the_save_its_own_button_named() -> void:
	## "Continue — Newest save: 12 Jan 1851 · Piedmont Line" used to start a fresh
	## 1850 valley: the button emitted a signal nobody listened to, and the scene
	## that arrived read only the map and the company name out of the hand-off.  The
	## save path rides with them now, and this follows it all the way into a world.
	_clear_autosaves()
	var autosave: Dictionary = view.session.saves.autosave()
	check_true(bool(autosave.get("ok", false)), "there is a save to go back to")
	var path := String(autosave["path"])
	var menu := MainMenu.new()
	menu.configure(view.session.saves)
	var continue_button := menu.button_named("Continue")
	check_false(continue_button.disabled, "and the menu knows it is there")

	continue_button.pressed.emit()
	var pending := SandboxIntent.peek()
	check_true(bool(pending["pending"]), "the hand-off is standing")
	check_eq(String(pending["save_path"]), path,
			"and it names the very file the button was pressed over")

	# The arriving half: a session that consumes what the menu wrote must find the
	# valley that was written, not a new one.
	var request := SandboxIntent.consume()
	var fresh := GameSession.new()
	check_false(bool(fresh.load_from(String(request["save_path"])).get("ok", false)),
			"a load into a session that never booted is refused rather than answered in Nil")
	check_has(fresh.last_error, "start", "and the refusal says what had not happened")
	check_true(fresh.start(String(request["map"])), "so the boot comes first, as the root orders it")
	var verdict: Dictionary = fresh.load_from(String(request["save_path"]))
	check_true(bool(verdict.get("ok", false)),
			"a valley opened from that intent is a loaded valley: " + String(verdict.get("reason", "")))
	check_eq(fresh.map_id, view.session.map_id, "on the map the save named")
	check_eq(fresh.towns.count(), view.session.towns.count(), "holding the towns the save held")
	fresh.shutdown()
	fresh.free()
	menu.free()


## The root is the only place that sees both a screen's button and the thing that
## button belongs to — the camera, another drawer.  Four verbs died that way: they
## were emitted into the air, and every test that pressed one watched a signal fire
## and called it a pass.  A runner that never builds the real scene cannot press its
## way through, so this reads the wiring itself: the next orphan verb fails here.
func test_the_root_wires_every_verb_a_screen_cannot_reach_on_its_own() -> void:
	var root := _root_source()
	check_neq(root, "", "the composition root is readable source, as the guide describes it")
	for verb in ["focus_requested", "route_requested", "buy_train_requested"]:
		check_true(root.contains(verb + ".connect("),
				"the inspector's %s is connected by the root, not left in the air" % verb)
	check_true(root.contains("camera_rig, input)"),
			"the inspector is named the controller, so its station verb has something to arm")
	check_true(root.contains("WorldPanel.new()"),
			"the screen behind the toolbar's World entry is built by the root")
	check_true(root.contains("attach_settings_screen(settings_panel)"),
			"and the options screen is named to the controller that opens it")


# --- reading the world back -----------------------------------------------

# --- helpers ---------------------------------------------------------------

## Every word a control shows, gathered for "does the screen actually say this".
func _labels_of(root: Node) -> String:
	var out := ""
	for child in root.get_children():
		if child is Label:
			out += (child as Label).text + "\n"
		out += _labels_of(child)
	return out


## A stretch of open country three tiles long that the domain would let a line
## start on.  Searched rather than remembered, because a fixed coordinate is a
## fixture that silently moves when the map is redrawn.
func _open_run_origin() -> Vector2i:
	for y in range(24, 96):
		for x in range(24, 96):
			var candidate := Vector2i(x, y)
			# The very preview the ghost will run, so this cannot find a place the
			# panel then refuses.
			var preview := view.session.builder.preview_rail(candidate, Vector2i(candidate.x + 3, candidate.y))
			if bool(preview.get("ok", false)) and not bool(preview.get("expensive", false)):
				return candidate
	return Vector2i(-1, -1)


## An install with nothing on disk yet — the state Continue's note promises about.
func _clear_autosaves() -> void:
	var folder := DirAccess.open("user://saves")
	if folder == null:
		return
	for file in folder.get_files():
		if String(file).begins_with("autosave_"):
			folder.remove(String(file))


func _root_source() -> String:
	var file := FileAccess.open("res://src/game_root.gd", FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


## A control found by the words on it, the way a player finds it.  A substring,
## because the reachable list spells its adds as "＋ <station>".
func _button_named(root: Node, needle: String) -> Button:
	for button in _buttons_of(root):
		if String(button.text).contains(needle):
			return button
	return null


## Which script built this control, read off the control itself.  A failure here
## has to name the screen, and `get_class()` answers "Control" or "Panel" for all
## of them.
func _screen_name(screen: Node) -> String:
	var script := screen.get_script() as Script
	if script == null or String(script.resource_path) == "":
		return screen.get_class()
	return String(script.resource_path).get_file().get_basename()


func _erase_settings_file() -> void:
	var directory := DirAccess.open("user://")
	if directory != null and directory.file_exists("settings.cfg"):
		directory.remove("settings.cfg")


## Every Button under a control, whatever the control calls it: this is a sweep,
## not a lookup, because the point is to find the one nobody thought about.
func _buttons_of(root: Node) -> Array[Button]:
	var out: Array[Button] = []
	for child in root.get_children():
		if child is Button and not (child is CheckButton):
			out.append(child as Button)
		out.append_array(_buttons_of(child))
	return out


## The key a player would have to press, taken from the InputMap and spelled by the
## engine.  Deliberately not `KeyHints.key_for`, which is the thing under test.
func _bound_key(action: String) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return ""
	return KeyHints.label_for(events[0])


func _palette_label(palette: CommandPalette, id: String) -> String:
	for action in palette._actions:
		if String(action["id"]) == id:
			return String(action["label"])
	return ""


func _palette_label_containing(palette: CommandPalette, needle: String) -> String:
	for action in palette._actions:
		if String(action["label"]).contains(needle):
			return String(action["label"])
	return ""


func _registry() -> DataRegistry:
	var registry := DataRegistry.new()
	check_true(registry.load_all(), "the definitions the screen reads are the shipped ones")
	return registry
