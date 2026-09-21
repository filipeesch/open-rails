extends TestBase

## The screens in front of the valley: the menu, the New Sandbox screen, and the
## handoff from either to a running game.
##
## These screens hold no simulation, so they are checked as themselves: built,
## pressed and listened to without a window.  What is worth proving here is the
## promises each one makes — that Continue cannot offer a file that is not there,
## that a name left blank still ends up on the top bar, that the year on the
## screen is the year the clock keeps.

func setup() -> void:
	DirAccess.make_dir_recursive_absolute(SaveService.SAVE_FOLDER)
	_clear_saves()
	SandboxIntent.clear()


func teardown() -> void:
	_clear_saves()
	SandboxIntent.clear()


# --- the menu -------------------------------------------------------------

func test_the_menu_offers_exactly_five_ways_into_the_valley() -> void:
	var menu := MainMenu.new()
	menu.configure(SaveService.new())
	var labels: Array[String] = []
	for button in menu.buttons():
		labels.append(button.text)
	check_eq(labels, ["Continue", "New Sandbox", "Load Game", "Settings", "Quit"],
		"the five ways in, in the order a player reads them")
	check_neq(menu.button_named("Continue"), null, "Continue is reachable by name")
	check_neq(menu.button_named("Quit"), null, "so is the way out")
	menu.free()


func test_continue_waits_until_there_is_something_to_continue() -> void:
	var menu := MainMenu.new()
	menu.configure(SaveService.new())
	var continue_button := menu.button_named("Continue")
	check_true(continue_button.disabled,
		"with an empty folder Continue is a grey button, not a missing one")
	menu.refresh()
	check_true(continue_button.disabled, "still nothing to resume")
	check_eq(_note_text(menu), "No saved game yet.",
		"and the reason is stated in plain words")

	_write_save("autosave_1851_02.json", "12 Jan 1851", "Piedmont Line", 41250.0, 1000)
	menu.refresh()
	check_false(continue_button.disabled, "a save on disk turns the button on")
	check_has(_note_text(menu), "12 Jan 1851", "the note names the day it will resume")
	check_has(_note_text(menu), "Piedmont Line", "and the company it will resume as")

	var opened: Array[String] = []
	menu.load_requested.connect(func(path: String) -> void: opened.append(path))
	continue_button.pressed.emit()
	check_eq(opened.size(), 1, "pressing Continue asks for exactly one thing")
	check_true(opened[0].ends_with("autosave_1851_02.json"),
		"and it asks for the newest save by name, not by guess")

	_clear_saves()
	menu.refresh()
	check_true(continue_button.disabled, "delete the last save and it is grey again")
	menu.free()


func test_the_load_list_is_the_folder_with_the_newest_on_top() -> void:
	_write_save("autosave_1851_02.json", "12 Jan 1851", "Piedmont Line", 41250.0, 1000)
	_write_save("autosave_1852_01.json", "09 Jan 1852", "Piedmont Line", 68900.0, 2000)
	_write_save("spring_terms.json", "20 May 1851", "Valley Copper Co", 12500.0, 1500)
	_write_raw("ruined.json", "{ this is not JSON")

	var menu := MainMenu.new()
	menu.configure(SaveService.new())
	var rows: Array[Node] = menu.find_children("Row_*", "Button", true, false)
	check_eq(rows.size(), 0, "the list stays folded until it is asked for")

	menu.button_named("Load Game").pressed.emit()
	rows = menu.find_children("Row_*", "Button", true, false)
	check_eq(rows.size(), 4, "every file in the folder, damaged ones included")
	check_has(_button_text(rows[0]), "09 Jan 1852", "newest first")
	check_has(_button_text(rows[0]), "autosave", "saying which kind of save it is")
	check_has(_button_text(rows[0]), "$69k", "and what the company was worth")
	var broken := 0
	for row in rows:
		if _button_text(row).contains("unreadable"):
			broken += 1
	check_eq(broken, 1, "the damaged file is listed as damaged, not hidden")

	var opened: Array[String] = []
	menu.load_requested.connect(func(path: String) -> void: opened.append(path))
	(rows[1] as Button).pressed.emit()
	check_eq(opened.size(), 1, "a row loads one thing")
	check_true(opened[0].ends_with("spring_terms.json"),
		"the row that says spring_terms loads spring_terms")
	menu.free()


# --- the new sandbox ------------------------------------------------------

func test_a_blank_name_still_founds_a_named_company() -> void:
	var screen := NewSandbox.new()
	screen.configure(_registry())
	check_has(",".join(screen.map_ids()), "founders_valley",
		"the valley that ships is the valley on offer")
	check_true(screen.choose_map("founders_valley"), "and it can be chosen")
	check_false(screen.choose_map("nowhere_valley"),
		"a map that is not installed cannot be picked into existence")

	screen.set_company_name("")
	var request := screen.start_sandbox()
	check_eq(String(request["company_name"]), "Founder's Valley Railway",
		"leaving the field alone borrows the valley's own name")
	check_neq(String(request["company_name"]), "", "never a company called nothing")
	screen.set_company_name("   ")
	check_eq(String(screen.start_sandbox()["company_name"]), "Founder's Valley Railway",
		"typing only spaces is the same answer as typing nothing")
	screen.set_company_name("  Piedmont & Valley Railroad  ")
	check_eq(String(screen.start_sandbox()["company_name"]), "Piedmont & Valley Railroad",
		"a typed name is used as typed, minus the corners")
	check_eq(String(request["map"]), "founders_valley", "the request names the map")
	screen.free()


func test_the_sandbox_that_starts_is_the_one_the_screen_asked_for() -> void:
	var screen := NewSandbox.new()
	var registry := _registry()
	screen.configure(registry)
	screen.set_company_name("Piedmont & Valley Railroad")
	var request := screen.start_sandbox()
	var intent := SandboxIntent.peek()
	check_true(bool(intent["pending"]), "the decision outlives the screen that made it")
	check_eq(String(intent["company_name"]), "Piedmont & Valley Railroad",
		"carried intact across the swap")

	# What `game_root` does with that intent, in the same order it does it.
	var intent_read := SandboxIntent.consume()
	check_false(bool(SandboxIntent.peek()["pending"]),
		"and reading it clears it, so the next launch starts clean")
	var session := GameSession.new()
	session.choose_company_name(String(intent_read["company_name"]))
	check_true(session.start(String(intent_read["map"])), "the valley opens")
	check_eq(session.company_name(), "Piedmont & Valley Railroad",
		"under the name the player typed")
	check_eq(session.clock.date.year, registry.start_year(),
		"in the year the data says the valley opens")
	check_eq(session.map_id, "founders_valley", "on the map that was chosen")
	session.free()


func test_the_menu_hands_the_new_sandbox_screen_over_and_takes_it_back() -> void:
	var menu := MainMenu.new()
	menu.wire_the_shell()
	check_neq(menu.new_screen, null, "the menu owns a New Sandbox screen")
	check_false(menu.new_screen.visible, "which starts hidden")
	menu.button_named("New Sandbox").pressed.emit()
	check_true(menu.new_screen.visible, "and the button puts it in front")
	menu.new_screen.map_button("founders_valley").pressed.emit()
	menu.new_screen.company_name_field().text = "Valley Copper Co"
	check_eq(menu.new_screen.company_name_or_default(), "Valley Copper Co",
		"typed straight into the screen the menu is showing")

	# Back out of it, the way a player who changed their mind does.
	for back in menu.new_screen.find_children("Back", "Button", true, false):
		(back as Button).pressed.emit()
	check_false(menu.new_screen.visible, "Back puts the menu back on screen")

	menu.button_named("Settings").pressed.emit()
	check_true(menu.settings_panel.is_open(),
		"the settings button opens the settings screen, not a dialog")
	check_eq(menu.settings_panel.settings, menu.settings,
		"and it edits the same table the rest of the game reads")
	menu.free()


func test_the_scenes_the_game_boots_from_are_real_scenes() -> void:
	## A `.tscn` that only opens in an editor is a scene nobody ships.  All three
	## are loaded and instantiated the way the engine loads them at launch.
	var menu := (load("res://scenes/MainMenu.tscn") as PackedScene).instantiate()
	check_eq(menu.name, "MainMenu", "the menu is the scene the project boots from")
	check_true(menu is MainMenu, "and it carries the menu script")
	menu.free()

	var sandbox := (load("res://scenes/NewSandbox.tscn") as PackedScene).instantiate()
	check_true(sandbox is NewSandbox, "the New Sandbox screen is a scene of its own")
	sandbox.free()

	var game := (load("res://scenes/Game.tscn") as PackedScene).instantiate()
	check_neq(game.get_node_or_null("World3D/Terrain"), null,
		"the world band the specification names is in the scene")
	check_neq(game.get_node_or_null("World3D/Trains"), null, "including the train band")
	check_neq(game.get_node_or_null("UI/TopBar"), null, "and the interface band")
	check_neq(game.get_node_or_null("UI/Notifications"), null, "with a corner for notices")
	check_neq(game.get_node_or_null("GameSession"), null,
		"and one node holding every domain service")
	game.free()


# --- helpers --------------------------------------------------------------

func _registry() -> DataRegistry:
	var registry := DataRegistry.new()
	check_true(registry.load_all(), "the definitions the screen reads are the shipped ones")
	return registry


func _note_text(menu: MainMenu) -> String:
	for child in menu.find_children("ContinueNote", "Label", true, false):
		return (child as Label).text
	return ""


func _button_text(node: Node) -> String:
	return (node as Button).text


func _write_save(file_name: String, date: String, company: String, cash: float,
		stamp: int) -> void:
	var path := SaveService.SAVE_FOLDER.path_join(file_name)
	write_json(path, {
		"save_version": SaveService.SAVE_VERSION,
		"game_version": SaveService.GAME_VERSION,
		"map": "founders_valley",
		"header": {
			"kind": "autosave" if file_name.begins_with("autosave_") else "manual",
			"date": date,
			"company": company,
			"cash": cash,
			"year": int(date.split(" ")[2]),
			"month": 1,
			"day": 1,
			"saved_at_unix": stamp,
		},
	})


func _write_raw(file_name: String, text: String) -> void:
	var path := SaveService.SAVE_FOLDER.path_join(file_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _clear_saves() -> void:
	var directory := DirAccess.open(SaveService.SAVE_FOLDER)
	if directory == null:
		return
	for file in directory.get_files():
		if String(file).ends_with(".json"):
			directory.remove(String(file))
