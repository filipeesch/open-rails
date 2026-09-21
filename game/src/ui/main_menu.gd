class_name MainMenu
extends Control

## The first screen, and the only way into a valley.
##
## Five ways in and no chrome: Continue, New Sandbox, Load Game, Settings, Quit.
## The screen owns no simulation and no save data — it reads a `SaveService` that
## was built for the purpose of answering "is there something to continue", and it
## announces decisions through signals.  Who obeys them (the shell, a test) is not
## this screen's business, which is what lets the whole ladder be checked without
## a window.
##
## Continue is the interesting one: it is *disabled*, not hidden, when there is
## nothing to continue.  A greyed button with a reason says "you have not saved
## yet"; a missing button says "this game cannot resume", and that is a lie.

signal sandbox_requested(request: Dictionary)
## The payload is a path, because that is what the save service hands back for
## "the newest autosave" and what its `load_path` accepts.  One rule for the
## Continue button and one for the list, so the shell has a single call to make.
signal load_requested(path: String)
signal settings_requested()
signal quit_requested()
signal new_screen_requested()

const GAME_SCENE := "res://scenes/Game.tscn"

var saves: SaveService
var settings: SettingsService
var new_screen: NewSandbox
var settings_panel: SettingsPanel

var _title: Label
var _column: VBoxContainer
var _continue_button: Button
var _continue_note: Label
var _new_button: Button
var _load_button: Button
var _settings_button: Button
var _quit_button: Button
var _save_list: VBoxContainer
var _heading_row: HBoxContainer


func attach(service: SaveService) -> void:
	saves = service
	_build()
	refresh()


func configure(service: SaveService) -> void:
	attach(service)


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


## The shipped menu wires itself: the save service it reads, the New Sandbox
## screen it opens, the settings screen it hands over to.  A test that hands these
## in with `attach` never runs this, so the ladder stays checkable one rung at a
## time — the same reason every panel here takes its dependencies.
func _ready() -> void:
	wire_the_shell()


func wire_the_shell() -> void:
	if saves == null:
		attach(SaveService.new())
	if settings == null:
		settings = SettingsService.new()
	if new_screen == null:
		var registry := DataRegistry.new()
		registry.load_all()
		new_screen = NewSandbox.new()
		new_screen.name = "NewSandbox"
		new_screen.visible = false
		add_child(new_screen)
		new_screen.configure(registry)
		new_screen.cancelled.connect(_show_menu_again)
	if settings_panel == null:
		settings_panel = SettingsPanel.new()
		settings_panel.name = "SettingsPanel"
		settings_panel.visible = false
		add_child(settings_panel)
		settings_panel.attach(settings)
	if not new_screen_requested.is_connected(_show_new_screen):
		new_screen_requested.connect(_show_new_screen)
	if not settings_requested.is_connected(_show_settings):
		settings_requested.connect(_show_settings)


func _show_new_screen() -> void:
	if new_screen != null:
		new_screen.visible = true


func _show_settings() -> void:
	if settings_panel != null:
		settings_panel.open_panel()


func _show_menu_again() -> void:
	if new_screen != null:
		new_screen.visible = false
	refresh()


# --- what the player sees -------------------------------------------------

func buttons() -> Array[Button]:
	return [_continue_button, _new_button, _load_button, _settings_button, _quit_button]


func button_named(label: String) -> Button:
	for button in buttons():
		if button != null and button.text == label:
			return button
	return null


func can_continue() -> bool:
	return saves != null and saves.latest_autosave() != ""


## Where Continue would take the player, or "" when it has nowhere to go.
func continue_path() -> String:
	return saves.latest_autosave() if saves != null else ""


## Re-read the disk.  Called on show and after any save, so Continue never offers
## a file that is not there.
func refresh() -> void:
	if _continue_button == null:
		return
	var path := continue_path()
	_continue_button.disabled = path == ""
	if path == "":
		_continue_note.text = "No saved game yet."
	else:
		_continue_note.text = "Newest save: %s" % _stamp_for_path(path)


## The line under Continue, read out of the save's own header — the player should
## see which valley and which company they are about to walk back into.
func _stamp_for_path(path: String) -> String:
	if saves == null:
		return path
	for row in saves.list_saves():
		if String(row.get("path", "")) != path:
			continue
		var date := String(row.get("date", ""))
		var company := String(row.get("company", ""))
		if date != "" and company != "":
			return "%s · %s" % [date, company]
		return String(row.get("slot", path))
	return path


# --- the actions ----------------------------------------------------------

func press_continue() -> void:
	if not can_continue():
		return
	load_requested.emit(continue_path())
	_handoff()


func press_new_sandbox() -> void:
	new_screen_requested.emit()


func press_load_game() -> void:
	_save_list.visible = not _save_list.visible
	if _save_list.visible:
		_rebuild_save_list()


func press_settings() -> void:
	settings_requested.emit()


func press_quit() -> void:
	quit_requested.emit()
	if is_inside_tree():
		get_tree().quit()


## The scene swap.  Guarded on a live tree so the same button works from a test
## that never installed the menu into a window.
func _handoff() -> void:
	# An orphan — a test holding the screen, a preview — has no scene to swap, and
	# asking it for one makes the engine log a complaint nobody can act on.
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var packed := load(GAME_SCENE) as PackedScene
	if packed == null:
		return
	tree.root.add_child.call_deferred(packed.instantiate())
	queue_free()


# --- building -------------------------------------------------------------

func _build() -> void:
	var frame := CenterContainer.new()
	frame.name = "Frame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(frame)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", GameTheme.panel(GameTheme.PANEL))
	frame.add_child(panel)

	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.custom_minimum_size = Vector2(340.0, 0.0)
	_column.add_theme_constant_override("separation", GameTheme.GAP)
	panel.add_child(_column)

	_title = GameTheme.heading("Open Rails")
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column.add_child(_title)

	var subtitle := GameTheme.small("Founder's Valley · 1850")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column.add_child(subtitle)
	_column.add_child(_spacer(8.0))

	_continue_button = _menu_button("Continue", "Return to the newest save.")
	_continue_button.name = "Continue"
	_continue_button.pressed.connect(press_continue)
	_column.add_child(_continue_button)

	_continue_note = GameTheme.small("")
	_continue_note.name = "ContinueNote"
	_continue_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column.add_child(_continue_note)

	_new_button = _menu_button("New Sandbox", "Open the valley as a new company.")
	_new_button.name = "NewSandbox"
	_new_button.pressed.connect(press_new_sandbox)
	_column.add_child(_new_button)

	_load_button = _menu_button("Load Game", "Choose one of the saved games.")
	_load_button.name = "LoadGame"
	_load_button.pressed.connect(press_load_game)
	_column.add_child(_load_button)

	_save_list = VBoxContainer.new()
	_save_list.name = "SaveList"
	_save_list.visible = false
	_save_list.add_theme_constant_override("separation", 2)
	_column.add_child(_save_list)

	_settings_button = _menu_button("Settings", "Sound, screen, camera and interface.")
	_settings_button.name = "Settings"
	_settings_button.pressed.connect(press_settings)
	_column.add_child(_settings_button)

	_quit_button = _menu_button("Quit", "Leave the valley until next time.")
	_quit_button.name = "Quit"
	_quit_button.pressed.connect(press_quit)
	_column.add_child(_quit_button)


func _menu_button(label: String, tooltip: String) -> Button:
	var button := GameTheme.button_for(label, tooltip)
	button.custom_minimum_size = Vector2(0.0, 34.0)
	return button


func _rebuild_save_list() -> void:
	for child in _save_list.get_children():
		_save_list.remove_child(child)
		child.free()
	if saves == null:
		return
	var rows := saves.list_saves()
	if rows.is_empty():
		_save_list.add_child(GameTheme.small("Nothing saved yet."))
		return
	for row in rows:
		var slot := String(row.get("slot", ""))
		var path := String(row.get("path", ""))
		var line := GameTheme.button_for(_row_label(row), "Load %s." % slot)
		line.name = "Row_" + slot
		line.pressed.connect(func() -> void:
			load_requested.emit(path)
			_handoff())
		_save_list.add_child(line)


func _row_label(row: Dictionary) -> String:
	if bool(row.get("corrupt", false)):
		return "%s — unreadable (%s)" % [String(row.get("slot", "")),
			String(row.get("reason", "damaged"))]
	var kind := "autosave" if bool(row.get("autosave", false)) else "save"
	return "%s · %s · %s" % [String(row.get("date", "?")), kind,
		GameTheme.money_compact(float(row.get("cash", 0.0)))]


func _spacer(height: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, height)
	return gap
