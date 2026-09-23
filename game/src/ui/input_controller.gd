class_name InputController
extends Node

## The tool state machine and the input that drives it.
##
## The controller owns *intent* — which tool is armed, what the ghost is showing
## — while the legality of that intent stays in the domain.  The ghost therefore
## comes from the same preview call the commit path uses, so it can never lie.

signal tool_changed(tool: String)
signal ghost_changed(tiles: Array[Vector2i], state: String, reason: String, cost: float)
## The whole station preview, handed over as the domain returned it.  The world's
## ghost needs what a footprint cannot carry — the catchment ring, the places it
## would cover, what they would yield — and re-running the preview to get them
## would let the picture and the click drift apart.  Emitted beside
## `ghost_changed`, which the cursor-side listeners already speak.
signal station_ghost_previewed(preview: Dictionary)
## Where the pointer is, in screen pixels, on every motion.  The ghost readout
## is placed by this rather than polling `Input` — a headless run can move the
## cursor by feeding motion events, and then the readout sits where the test
## put it, not at wherever the last window thought the mouse was.
signal cursor_moved(screen: Vector2)
signal panel_requested(panel: String)
signal speed_changed(index: int)
signal station_picked(station_id: int)

const TOOL_NONE := "none"
const TOOL_RAIL := "rail"
const TOOL_STATION := "station"
## The removal half of the build palette: a click lifts one laid tile and half
## its build cost comes back.  What may not be lifted (station access rail) is
## the domain's answer, via `RailService.removal_block`, never the tool's.
const TOOL_REMOVE := "remove"
## Direct-manipulation mode for the route editor: the next click on a station
## is a stop, not a selection.  Legality of the stop stays in `RouteService`.
const TOOL_STOP_PICK := "stop_pick"
const PANEL_TRIPS := "trips"
const PANEL_TRIPS_ACTION := "panel_trips"
const PANEL_COMPANY := "company"
const PANEL_WORLD := "world"
## The camera's named zoom steps, and the two advertised shortcuts that were
## printed on the tool buttons long before anything answered to them.  Every one
## of these is bound in `game/project.godot` and asserted to exist by
## `test_input_bindings.gd`, because a hint the engine does not honour is worse
## than no hint at all: it teaches the player a thing that then fails.
const ZOOM_IN_ACTION := "cam_zoom_in"
const ZOOM_OUT_ACTION := "cam_zoom_out"
const BUILD_ACTION := "build_mode"
const COMPANY_ACTION := "company_panel"
## The options screen had one door in the running game — the command palette —
## which is a long way to reach a volume slider.  `O` opens it, and Escape closes
## it, so the screen behaves like every other screen in the ladder.
const SETTINGS_ACTION := "settings_panel"
## A keypress spends exactly one wheel notch of zoom.  Zooming is one scale run
## however it is asked for, so the keyboard and the wheel cannot disagree about
## how far a step goes.
const ZOOM_KEY_STEPS := 1.0
## A pinch arrives as a factor centred on 1.0 — a brisk event is around 1.05 — so
## the gain turns that into wheel-notch units.  It is a feel constant, and it lives
## beside the others rather than inside the event branch.
const PINCH_ZOOM_GAIN := 20.0

const ZOOM_DRAG_THRESHOLD := 4.0
## The default hand-speeds, which are also the settings' defaults.  A player
## who never opens the options screen gets exactly these numbers; one who does
## replaces them through `attach_settings` without a restart.
const DEFAULT_PAN_SPEED := 900.0
## Where a station's footprint sits relative to the cursor: the yard hangs one
## cell to the left of the pointer and runs down from it.  `station_anchor_for`
## is the only place this is applied, so the ghost and the click that commits it
## cannot disagree about which ground is being bought.
const STATION_ANCHOR_OFFSET := Vector2i(1, 0)
const DEFAULT_ROTATE_SPEED := 0.42
const DEFAULT_ZOOM_SPEED := 1.0

var session: GameSession
var camera_rig: IsoCameraRig
var selection: SelectionService

var tool: String = TOOL_NONE
var station_definition := "small_station"
var rail_start := Vector2i(-1, -1)
var rail_plan := {}
var station_preview := {}
## The cell the station ghost (and therefore the next click) is anchored to, or
## (-1, -1) when no station is being aimed at.  The world-space ghost needs it:
## the signal carries only the footprint cells, and a preview that has to guess
## where it was standing is a preview that can be wrong.
var ghost_anchor := Vector2i(-1, -1)
var active_panel := ""
var is_rotating := false
var is_panning := false
## Shift held down: a rail click then means "this one cell", not "start/extend a
## run".  Tracked from the events themselves, never polled, so a headless run can
## drive it and the ghost can never disagree with the next click.
var precision_held := false
## Screen pixels of camera travel per second at the current zoom, degrees of
## yaw per pixel of right-drag, and the wheel's appetite.  Read from settings.
var pan_speed := DEFAULT_PAN_SPEED
var rotation_speed := DEFAULT_ROTATE_SPEED
var zoom_speed := DEFAULT_ZOOM_SPEED
var edge_scrolling := true
## Where to measure the edge zone against.  Empty means "ask the viewport",
## which a controller running without one cannot do.
var viewport_size := Vector2.ZERO
var settings: SettingsService = null
## The options screen, when a host has named it.  See `attach_settings_screen`.
var settings_screen: Control = null

var _last_mouse := Vector2.ZERO
var _last_valid_point := Vector2.ZERO
var _edge_pan := Vector2.ZERO


func attach(game_session: GameSession, rig: IsoCameraRig, sel: SelectionService) -> void:
	session = game_session
	camera_rig = rig
	selection = sel
	session.rail.track_changed.connect(func(_tiles): _refresh_ghost())
	session.rail.track_removed.connect(func(_tiles): _refresh_ghost())


func configure(game_session: GameSession, rig: IsoCameraRig, sel: SelectionService) -> void:
	attach(game_session, rig, sel)


## Hand the controller the switches it answers to.  The camera obeys the settings
## the moment they move, so a slider is a preview rather than a form field.
func attach_settings(service: SettingsService) -> void:
	settings = service
	settings.setting_changed.connect(_on_setting_changed)
	apply_settings()


## Name the options screen this controller is to open and close, so `O` and Escape
## have a door that does not depend on the engine iterating.  Passing `null` takes
## the name back — the screen the game_root builds lives as long as it does.
func attach_settings_screen(screen: Control) -> void:
	settings_screen = screen


func apply_settings() -> void:
	if settings == null:
		return
	if settings.has_key("camera_pan_speed"):
		pan_speed = settings.as_float("camera_pan_speed")
	if settings.has_key("camera_rotation_speed"):
		rotation_speed = settings.as_float("camera_rotation_speed")
	if settings.has_key("zoom_speed"):
		zoom_speed = settings.as_float("zoom_speed")
	if settings.has_key("edge_scrolling"):
		edge_scrolling = settings.as_bool("edge_scrolling")


func _on_setting_changed(key: String, _value: Variant) -> void:
	apply_settings()
	if key == "edge_scrolling" and not edge_scrolling:
		_edge_pan = Vector2.ZERO


func _process(delta: float) -> void:
	_handle_held_keys(delta)
	if _edge_pan != Vector2.ZERO:
		pan_camera(_edge_pan, delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_SHIFT and not event.echo:
		# Shift is what decides the shape of the next click, so the ghost is
		# re-previewed on the modifier alone — even with the cursor standing still.
		precision_held = event.pressed
		_update_ghost_at_mouse(_last_mouse)
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMagnifyGesture:
		_handle_pinch(event)
	elif event is InputEventPanGesture:
		_handle_trackpad_pan(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


## Pinch on a trackpad is the same zoom as a wheel notch, spent at the same scale
## and anchored on the same ground.  This branch exists because a MacBook sends no
## wheel buttons at all: a game that listens only for the wheel cannot be zoomed
## from the machine's own pointing device, which is the difference between a
## camera the player has and a camera they read about in the help.
func _handle_pinch(event: InputEventMagnifyGesture) -> void:
	# Spreading the fingers means *magnify*, and the rig counts zoom the other way
	# round: a positive number of steps widens the view.  Hence `1.0 - factor`.
	var steps := (1.0 - event.factor) * PINCH_ZOOM_GAIN * zoom_speed
	if absf(steps) < 0.001:
		return
	camera_rig.zoom_by(steps, _cursor_anchor(), _viewport_rect())


## Two-finger scroll pans the valley, by the rule a middle-drag already follows: the
## ground goes where the fingers go.  The gesture is direct manipulation, so it
## spends the same 1:1 distance rather than the panning *speed* — a slider that
## made fingers and ground disagree would be a slider that lied.
func _handle_trackpad_pan(event: InputEventPanGesture) -> void:
	if event.delta == Vector2.ZERO:
		return
	camera_rig.pan(Vector2(-event.delta.x, event.delta.y), 1.0)


func _handle_key(event: InputEventKey) -> void:
	if event.is_action_pressed("tool_cancel"):
		cancel()
	elif event.is_action_pressed("undo"):
		var label := session.undo.undo()
		session.notify("Undid: %s" % label if label != "" else "Nothing to undo", 
			"info" if label != "" else "bad")
	elif event.is_action_pressed("cam_rotate_ccw"):
		camera_rig.snap_rotate(-1.0)
	elif event.is_action_pressed("cam_rotate_cw"):
		camera_rig.snap_rotate(1.0)
	elif event.is_action_pressed("cam_reset"):
		camera_rig.reset_view()
	elif InputMap.has_action(ZOOM_IN_ACTION) and event.is_action_pressed(ZOOM_IN_ACTION):
		# Closer, which the rig spells as a negative number of steps.
		camera_rig.zoom_by(-ZOOM_KEY_STEPS, _cursor_anchor(), _viewport_rect())
	elif InputMap.has_action(ZOOM_OUT_ACTION) and event.is_action_pressed(ZOOM_OUT_ACTION):
		camera_rig.zoom_by(ZOOM_KEY_STEPS, _cursor_anchor(), _viewport_rect())
	elif event.is_action_pressed("focus_selected"):
		focus_selection()
	elif event.is_action_pressed("speed_pause"):
		session.clock.set_speed_index(0 if not session.clock.is_paused() else 1)
	elif event.is_action_pressed("speed_1x"):
		session.clock.set_speed_index(1)
	elif event.is_action_pressed("speed_2x"):
		session.clock.set_speed_index(2)
	elif event.is_action_pressed("speed_4x"):
		session.clock.set_speed_index(3)
	elif event.is_action_pressed("command_palette"):
		_open_command_palette()
	elif InputMap.has_action(PANEL_TRIPS_ACTION) \
			and event.is_action_pressed(PANEL_TRIPS_ACTION):
		open_panel(PANEL_TRIPS)
	elif InputMap.has_action(BUILD_ACTION) and event.is_action_pressed(BUILD_ACTION):
		# The same verb as the toolbar's `Build` entry, reached by the key that
		# entry has been advertising since it was written.
		arm_tool(TOOL_RAIL)
	elif InputMap.has_action(COMPANY_ACTION) and event.is_action_pressed(COMPANY_ACTION):
		open_panel(PANEL_COMPANY)
	elif InputMap.has_action(SETTINGS_ACTION) and event.is_action_pressed(SETTINGS_ACTION):
		# Advertised to the player by the palette entry that offers the same verb,
		# so the key is learnable from the interface rather than from a manual.
		if not open_settings():
			session.notify("The settings screen is not available.", "bad")
	elif event.keycode == KEY_ESCAPE:
		cancel()
	# No number key is handled here.  A nine-slot hotbar was once wired to
	# `on_hotbar`, which nothing ever assigned and nothing else read; and 1, 2 and
	# 3 were unreachable even then, the speed dial above claiming them first.  A
	# branch that cannot be reached is not a feature waiting for a host, it is a
	# place where a future reader looks for one.


## The palette lives under the modal layer, built by `game_root.gd`; reach it by
## name so this controller does not need a reference to the shell.
func _open_command_palette() -> void:
	for candidate in get_tree().get_nodes_in_group("ui_command_palette"):
		if candidate.has_method("open_palette"):
			candidate.open_palette()
			return
	session.notify("The command palette is not available.", "bad")


## The one door to the options screen, for the key, the palette and Escape alike.
## Reached by group name for the same reason the palette is: this controller does
## not hold a reference to the shell that built the screen, and a shell without one
## gets an honest refusal instead of a click that does nothing.
func open_settings() -> bool:
	var screen: Variant = _settings_screen()
	if screen == null:
		return false
	screen.call("open_panel")
	return true


## Close the options screen if it is standing open, reporting whether that is what
## happened — Escape's ladder needs to know whether it found a rung here or has to
## keep going down to the hover and the selection.
func close_settings() -> bool:
	var screen: Variant = _settings_screen()
	if screen == null or not bool(screen.call("is_open")):
		return false
	screen.call("close_panel")
	return true


## The options screen this controller was pointed at, so long as it is still there
## and can be opened and closed.  Named by the root that builds both, rather than
## found by searching a node group: a group is only searchable from inside a tree
## that is iterating, so a verb reachable only through one cannot be exercised
## outside one — and this door sat unwatched for exactly that reason.
func _settings_screen() -> Variant:
	if settings_screen == null or not is_instance_valid(settings_screen):
		return null
	if not settings_screen.has_method("open_panel") or not settings_screen.has_method("close_panel"):
		return null
	return settings_screen


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			# Scroll up brings the ground closer — the wheel's one convention, and
			# stated against the rig here because the rig counts the other way.
			camera_rig.zoom_by(-event.factor * zoom_speed, _cursor_anchor(), _viewport_rect())
			return
		MOUSE_BUTTON_WHEEL_DOWN:
			camera_rig.zoom_by(event.factor * zoom_speed, _cursor_anchor(), _viewport_rect())
			return
		MOUSE_BUTTON_MIDDLE:
			is_panning = event.pressed
			_last_mouse = event.position
			return
		MOUSE_BUTTON_RIGHT:
			is_rotating = event.pressed
			_last_mouse = event.position
			return
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_on_click(event.position, event.shift_pressed or precision_held)
			return


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	precision_held = event.shift_pressed
	if is_rotating:
		camera_rig.rotate_by(event.relative.x * rotation_speed)
		_last_mouse = event.position
		return
	if is_panning:
		camera_rig.pan(Vector2(-event.relative.x, event.relative.y), 1.0)
		_last_mouse = event.position
		return
	_last_mouse = event.position
	selection.point_at(event.position)
	_last_valid_point = event.position
	_update_ghost_at_mouse(event.position)
	cursor_moved.emit(event.position)
	_edge_pan = _edge_vector(event.position)


func _edge_vector(position: Vector2) -> Vector2:
	if not edge_scrolling:
		# The switch is honoured here rather than at the caller: a player who turned
		# edge scrolling off must not find the camera creeping when the cursor rests
		# against a wall — not even a pixel.
		return Vector2.ZERO
	var rect := _viewport_rect()
	if rect.size.x <= 0.0:
		return Vector2.ZERO
	var zone := 18.0
	var out := Vector2.ZERO
	if position.x < zone:
		out.x = -1.0
	elif position.x > rect.size.x - zone:
		out.x = 1.0
	if position.y < zone:
		out.y = -1.0
	elif position.y > rect.size.y - zone:
		out.y = 1.0
	return out


## The one place the pan speed is spent.  Held keys and edge scrolling both come
## through here, so the setting cannot apply to one and not the other.
func pan_camera(direction: Vector2, delta: float) -> void:
	camera_rig.pan(direction * pan_speed * delta, delta)


func _handle_held_keys(delta: float) -> void:
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_action_pressed("cam_pan_up"):
		pan.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_action_pressed("cam_pan_down"):
		pan.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_action_pressed("cam_pan_left"):
		pan.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_action_pressed("cam_pan_right"):
		pan.x += 1.0
	if pan != Vector2.ZERO:
		pan_camera(-pan, delta)


# --- tools ----------------------------------------------------------------

func arm_tool(next_tool: String) -> void:
	if tool == next_tool:
		cancel()
		return
	tool = next_tool
	rail_start = Vector2i(-1, -1)
	rail_plan = {}
	match tool:
		TOOL_RAIL:
			session.notify("Rail tool: click a start tile, then an end tile.  Shift-click lays one tile.  Esc to cancel.", "info")
		TOOL_STATION:
			_preview_station_at(_last_mouse)
			session.notify("Station tool: the ghost is green where a station may stand.", "info")
		TOOL_REMOVE:
			session.notify("Remove tool: click laid track to lift it and take half the cost back.  " \
				+ "Rail a station depends on stays put.  Esc to cancel.", "info")
		TOOL_STOP_PICK:
			session.notify("Route stop: click a station in the world.  Esc to go back.", "info")
	tool_changed.emit(tool)


func arm_rail() -> void:
	arm_tool(TOOL_RAIL)


func arm_station() -> void:
	arm_tool(TOOL_STATION)


## Escape ladder: dismiss whatever is covering the valley first — today the options
## screen, which sits in the modal layer over everything — then abandon a
## half-finished operation, then put the tool down, then close the open
## panel, and only then let go of what the player had selected, the hover and
## the selection together.  One press never drops a level it did not need to,
## so a player mid-line who hits Escape keeps the rail tool in hand (spec 2.1:
## cancelling the operation must not silently exit build mode).
func cancel() -> void:
	# Covering the valley outranks everything: while the options screen is up it is
	# the thing the player is looking at, and an Escape that walked past it to put a
	# tool down would answer a question nobody asked.
	if close_settings():
		return
	if _operation_pending():
		_cancel_operation()
		return
	if tool != TOOL_NONE:
		_clear_tool()
		return
	if active_panel != "":
		active_panel = ""
		panel_requested.emit("")
		return
	selection.clear_hover()
	selection.clear_selection()


func _clear_tool() -> void:
	tool = TOOL_NONE
	rail_start = Vector2i(-1, -1)
	rail_plan = {}
	station_preview = {}
	ghost_anchor = Vector2i(-1, -1)
	selection.clear_hover()
	_ghost_none()
	tool_changed.emit(tool)


## The signal's tiles argument is typed `Array[Vector2i]`, and Godot refuses an
## untyped literal against a typed parameter — the emit would silently skip
## every listener, leaving panels holding a ghost that no longer exists.  One
## helper, one type, everywhere the ghost goes away.
func _ghost_none() -> void:
	var cleared: Array[Vector2i] = []
	ghost_changed.emit(cleared, "none", "", 0.0)


## An operation is pending when the player has already spent a click inside the
## tool — today, the rail run that opened with a start-tile click.  Station and
## stop-pick commit on the single click, so nothing dangles between presses.
func _operation_pending() -> bool:
	return tool == TOOL_RAIL and rail_start != Vector2i(-1, -1)


## The first rung: give up the half-laid run, stay in the tool.  The player is
## still in build mode and can open a new line with the very next click.
func _cancel_operation() -> void:
	rail_start = Vector2i(-1, -1)
	rail_plan = {}
	_ghost_none()
	session.notify("Line cancelled — the rail tool is still armed.", "info")


func is_armed() -> bool:
	return tool != TOOL_NONE


func open_panel(panel: String) -> void:
	active_panel = "" if active_panel == panel else panel
	panel_requested.emit(active_panel)


## Put one named panel down.  A drawer's own ✕ needs this rather than another
## `open_panel(name)`: the toggle only hides the panel while the controller and the
## drawer still agree about what is standing open, and they stop agreeing the
## moment the panel was hidden by something else — an armed tool, the other drawer.
## Then the ✕ was opening the sheet it was labelled to close.
func close_panel(panel: String) -> void:
	if active_panel != panel:
		return
	active_panel = ""
	panel_requested.emit(active_panel)


func focus_selection() -> void:
	if selection.selected_kind == SelectionService.KIND_TRAIN:
		camera_rig.follow_train(selection.selected_id, Callable(session.trains, "position_tiles"))
	elif selection.has_selection():
		camera_rig.focus_tile(Vector2(selection.selected_tile) + Vector2(0.5, 0.5))


func build_at(tile: Vector2i) -> void:
	match tool:
		TOOL_RAIL:
			_commit_rail(tile)
		TOOL_STATION:
			# The same anchor the ghost is standing on, not the cell under the
			# cursor: what the player watched is what they buy.
			var result := session.builder.build_station(station_definition, station_anchor_for(tile))
			if bool(result.get("ok", false)):
				session.notify("Built %s for %s" % [session.stations.name_of(int(result["id"])),
					GameTheme.money(float(result["cost"]))], "good")
			else:
				session.notify(String(result["reason"]), "bad")
		TOOL_REMOVE:
			var run: Array[Vector2i] = [tile]
			var result := session.builder.remove_track(run)
			if bool(result.get("ok", false)):
				session.notify("Removed %d tile%s — refund %s" % [
					Array(result["tiles"]).size(), "" if Array(result["tiles"]).size() == 1 else "s",
					GameTheme.signed_money(float(result["refund"]))], "good")
			else:
				session.notify(String(result["reason"]), "bad")
			_update_ghost_at_mouse(_last_mouse)
		_:
			selection.select_tile(tile)


# --- internals ------------------------------------------------------------

## A plain click opens or confirms a run.  Shift holds a click down to exactly the
## one cell under the cursor.
func _on_click(screen: Vector2, precision := false) -> void:
	var tile := selection.pick_tile(screen)
	if tile == Vector2i(-1, -1):
		return
	if tool == TOOL_STOP_PICK:
		_pick_station()
		return
	if tool == TOOL_RAIL and precision:
		_commit_tile(tile)
		return
	if tool == TOOL_RAIL and rail_start == Vector2i(-1, -1):
		rail_start = tile
		_refresh_ghost()
		return
	build_at(tile)


## Stop-picking hands the station over and stays armed: a route is built one
## stop at a time, and Esc is what ends the mode.
func _pick_station() -> void:
	if selection.hovered_kind == SelectionService.KIND_STATION and selection.hovered_id != 0:
		station_picked.emit(selection.hovered_id)
		return
	selection.select_tile(selection.hovered_tile)
	session.notify("That is not a station — click a station building.", "bad")


func _commit_rail(tile: Vector2i) -> void:
	if rail_start == Vector2i(-1, -1):
		rail_start = tile
		return
	var result := session.builder.build_rail(rail_start, tile)
	if bool(result.get("ok", false)):
		session.notify("Laid %d tiles for %s" % [Array(result["added"]).size(),
			GameTheme.money(float(result["cost"]))], "good")
		rail_start = tile
	else:
		session.notify(String(result["reason"]), "bad")
		rail_plan = {}
	_refresh_ghost()


## Shift-precision: lay exactly this cell and no more.  The one-cell run goes
## through the same preview/commit pair a drag uses, so legality and price stay
## the domain's answer.  A drag already under way is left where it was: precision
## is a correction to the line, not a mode switch.
func _commit_tile(tile: Vector2i) -> void:
	var run: Array[Vector2i] = [tile]
	var result := session.builder.build_track_run(run)
	if bool(result.get("ok", false)):
		session.notify("Laid 1 tile for %s" % GameTheme.money(float(result["cost"])), "good")
	else:
		session.notify(String(result["reason"]), "bad")
	_update_ghost_at_mouse(_last_mouse)


## The precision ghost: the single cell a Shift-click would lay, priced by the
## very preview that commit will run.
func _refresh_precision_ghost(screen: Vector2) -> void:
	var tile := selection.pick_tile(screen)
	if tile == Vector2i(-1, -1):
		return
	var run: Array[Vector2i] = [tile]
	var preview := session.builder.preview_track_run(run)
	if not bool(preview.get("ok", false)):
		ghost_changed.emit(run, "invalid", String(preview.get("reason", "")), 0.0)
		return
	ghost_changed.emit(run, "ok", "", float(preview.get("cost", 0.0)))


func _update_ghost_at_mouse(screen: Vector2) -> void:
	match tool:
		TOOL_RAIL:
			if precision_held:
				_refresh_precision_ghost(screen)
			else:
				_refresh_ghost(screen)
		TOOL_STATION:
			_preview_station_at(screen)
		TOOL_REMOVE:
			var tile := selection.pick_tile(screen)
			if tile == Vector2i(-1, -1):
				return
			var run: Array[Vector2i] = [tile]
			var reason := "Nothing to remove here"
			if session.rail.network.has_rail(tile):
				reason = session.rail.removal_block(run)
			if reason != "":
				ghost_changed.emit(run, "invalid", reason, 0.0)
			else:
				# Removal pays rather than charges, so the price rides the shared
				# signal as a negative cost — one number the readout renders
				# either way without inventing a second channel.
				ghost_changed.emit(run, "ok", "", -session.builder.refund_for(run))
		_:
			_ghost_none()


## The cell a station's footprint is anchored to when the cursor stands here.
func station_anchor_for(tile: Vector2i) -> Vector2i:
	return tile - STATION_ANCHOR_OFFSET


## One preview, used both when the pointer moves and when the tool is armed.  The
## footprint travels with the signal so every listener draws the same yard, and
## the published `ghost_anchor` travels with it so the world-space ghost can ask
## the domain what that yard would reach.
func _preview_station_at(screen: Vector2) -> void:
	var tile := selection.pick_tile(screen)
	if tile == Vector2i(-1, -1):
		# Nothing under the pointer yet — the tool was armed before the mouse had
		# moved.  Quote a real spot rather than leaving the readout blank.
		_preview_station_at_anchor(Vector2i.ZERO)
		return
	_preview_station_at_anchor(station_anchor_for(tile))


func _preview_station_at_anchor(anchor: Vector2i) -> void:
	ghost_anchor = anchor
	station_preview = session.builder.preview_station(station_definition, anchor)
	var tiles: Array[Vector2i] = []
	var def := session.stations.station_def(station_definition)
	if def != null:
		tiles = WorldCoords.tiles_in_span(anchor, def.footprint)
	# The word comes from the preview: an unaffordable yard is `expensive`, the same
	# amber the rail tool uses, and only ground the domain refuses is `invalid`.
	var state := String(station_preview.get("state", "invalid"))
	ghost_changed.emit(tiles, state, String(station_preview.get("reason", "")),
		float(station_preview.get("cost", 0.0)))
	station_ghost_previewed.emit(station_preview)


func _refresh_ghost(screen: Vector2 = Vector2.ZERO) -> void:
	if tool != TOOL_RAIL:
		return
	if rail_start == Vector2i(-1, -1):
		return
	var end := selection.hovered_tile
	if end == Vector2i(-1, -1) or end == rail_start:
		return
	rail_plan = session.builder.preview_rail(rail_start, end)
	if not bool(rail_plan.get("ok", false)):
		ghost_changed.emit([rail_start], "invalid", String(rail_plan.get("reason", "")), 0.0)
		return
	var state := "expensive" if bool(rail_plan.get("expensive", false)) else "ok"
	ghost_changed.emit(Array(rail_plan["tiles"]), state, "", float(rail_plan["cost"]))


func _cursor_anchor() -> Vector2:
	var tile := selection.pick_tile(_last_mouse)
	if tile == Vector2i(-1, -1):
		return Vector2.INF
	return Vector2(tile) + Vector2(0.5, 0.5)


func _viewport_rect() -> Rect2:
	if viewport_size.x > 0.0 and viewport_size.y > 0.0:
		return Rect2(Vector2.ZERO, viewport_size)
	var viewport := get_viewport()
	if viewport == null:
		return Rect2()
	return Rect2(Vector2.ZERO, viewport.get_visible_rect().size)
