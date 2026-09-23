class_name BottomToolbar
extends PanelContainer

## The permanent bottom toolbar.  Five entries, all keyboard-reachable, all
## doing one thing each.

signal tool_requested(tool: String)
signal panel_requested(panel: String)

## Each entry names the action its shortcut would come from, not the letter.  The
## tooltip is then assembled from the InputMap at build time, so a button can only
## ever advertise a key that actually does what the button does — and falls silent,
## rather than lying, when the verb has no key.
const ENTRIES := [
	{"label": "Build", "kind": "tool", "target": "rail", "hint": "Lay track", "action": "build_mode"},
	{"label": "Stations", "kind": "tool", "target": "station", "hint": "Place a station", "action": ""},
	{"label": "Trains", "kind": "panel", "target": "trips", "hint": "Trains and routes", "action": "panel_trips"},
	{"label": "Company", "kind": "panel", "target": "company", "hint": "Finances", "action": "company_panel"},
	{"label": "World", "kind": "panel", "target": "world", "hint": "Map and towns", "action": ""},
]

var session: GameSession
var input: InputController
var _buttons := {}
var _kinds := {}


func attach(game_session: GameSession, controller: InputController) -> void:
	session = game_session
	input = controller
	theme = GameTheme.build()
	add_theme_stylebox_override("panel", GameTheme.panel(GameTheme.BACKGROUND))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(row)
	for entry in ENTRIES:
		var button := Button.new()
		button.text = String(entry["label"])
		button.tooltip_text = String(entry["hint"]) \
				+ KeyHints.hint_suffix(String(entry["action"]))
		button.custom_minimum_size = Vector2(96, 30)
		button.focus_mode = Control.FOCUS_ALL
		# The armed tool and the open panel are marked by holding their entry
		# down.  Without `toggle_mode` the engine silently drops an assigned
		# `button_pressed`, and the mark never appears — the simulation stays
		# honest while the button lies about it.
		button.toggle_mode = true
		var kind := String(entry["kind"])
		var target := String(entry["target"])
		button.pressed.connect(_on_entry.bind(kind, target))
		row.add_child(button)
		_buttons[String(entry["label"])] = button
		_kinds[String(entry["label"])] = kind
	if controller != null:
		controller.tool_changed.connect(_on_tool_changed)
		controller.panel_requested.connect(_on_panel_changed)


func configure(game_session: GameSession, controller: InputController) -> void:
	attach(game_session, controller)


func _on_entry(kind: String, target: String) -> void:
	if kind == "tool":
		tool_requested.emit(target)
		if input != null:
			input.arm_tool(target)
	else:
		panel_requested.emit(target)
		if input != null:
			input.open_panel(target)


func _on_tool_changed(tool: String) -> void:
	for label in _buttons.keys():
		var button: Button = _buttons[label]
		# Only the entry the signal speaks about is pressed or released: the
		# open panel keeps its mark while a tool is armed, and vice versa.
		if String(_kinds[label]) != "tool":
			continue
		var armed: bool = (label == "Build" and tool == "rail") or (label == "Stations" and tool == "station") \
			or (label == "Build" and tool == "remove")
		button.button_pressed = armed
		button.add_theme_color_override("font_color", GameTheme.ACCENT if armed else GameTheme.TEXT)


func _on_panel_changed(panel: String) -> void:
	for label in _buttons.keys():
		var button: Button = _buttons[label]
		if String(_kinds[label]) != "panel":
			continue
		var open: bool = label == "Trains" and panel == "trips" or label == "Company" and panel == "company" or label == "World" and panel == "world"
		button.button_pressed = open
		button.add_theme_color_override("font_color", GameTheme.ACCENT if open else GameTheme.TEXT)
