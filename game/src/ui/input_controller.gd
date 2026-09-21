class_name InputController
extends Node

## The tool state machine and the input that drives it.
##
## The controller owns *intent* — which tool is armed, what the ghost is showing
## — while the legality of that intent stays in the domain.  The ghost therefore
## comes from the same preview call the commit path uses, so it can never lie.

signal tool_changed(tool: String)
signal ghost_changed(tiles: Array[Vector2i], state: String, reason: String, cost: float)
signal panel_requested(panel: String)
signal speed_changed(index: int)
signal hotbar_requested(index: int)
signal station_picked(station_id: int)

const TOOL_NONE := "none"
const TOOL_RAIL := "rail"
const TOOL_STATION := "station"
const TOOL_TRAIL := "trail"
## Direct-manipulation mode for the route editor: the next click on a station
## is a stop, not a selection.  Legality of the stop stays in `RouteService`.
const TOOL_STOP_PICK := "stop_pick"
const PANEL_TRIPS := "trips"
const PANEL_TRIPS_ACTION := "panel_trips"
const PANEL_COMPANY := "company"
const PANEL_WORLD := "world"

const ZOOM_DRAG_THRESHOLD := 4.0
## The default hand-speeds, which are also the settings' defaults.  A player
## who never opens the options screen gets exactly these numbers; one who does
## replaces them through `attach_settings` without a restart.
const DEFAULT_PAN_SPEED := 900.0
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

var on_hotbar: Callable = Callable()

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
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


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
	elif event.keycode == KEY_ESCAPE:
		cancel()
	elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
		if on_hotbar.is_valid():
			on_hotbar.call(event.keycode - KEY_1)


## The palette lives under the modal layer, built by `game_root.gd`; reach it by
## name so this controller does not need a reference to the shell.
func _open_command_palette() -> void:
	for candidate in get_tree().get_nodes_in_group("ui_command_palette"):
		if candidate.has_method("open_palette"):
			candidate.open_palette()
			return
	session.notify("The command palette is not available.", "bad")


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			camera_rig.zoom_by(event.factor * zoom_speed, _cursor_anchor(), _viewport_rect())
			return
		MOUSE_BUTTON_WHEEL_DOWN:
			camera_rig.zoom_by(-event.factor * zoom_speed, _cursor_anchor(), _viewport_rect())
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
			station_preview = session.builder.preview_station(station_definition, Vector2i(0, 0))
			session.notify("Station tool: the ghost is green where a station may stand.", "info")
		TOOL_STOP_PICK:
			session.notify("Route stop: click a station in the world.  Esc to go back.", "info")
	tool_changed.emit(tool)


func arm_rail() -> void:
	arm_tool(TOOL_RAIL)


func arm_station() -> void:
	arm_tool(TOOL_STATION)


## Escape ladder: back out of the armed operation first, then close the open
## panel, and only then let go of what the player had selected — the hover and the
## selection together.  One press never drops a level it did not need to.
func cancel() -> void:
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
	selection.clear_hover()
	ghost_changed.emit([], "none", "", 0.0)
	tool_changed.emit(tool)


func is_armed() -> bool:
	return tool != TOOL_NONE


func open_panel(panel: String) -> void:
	active_panel = "" if active_panel == panel else panel
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
			var result := session.builder.build_station(station_definition, tile)
			if bool(result.get("ok", false)):
				session.notify("Built %s for %s" % [session.stations.name_of(int(result["id"])),
					GameTheme.money(float(result["cost"]))], "good")
			else:
				session.notify(String(result["reason"]), "bad")
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
			var tile := selection.pick_tile(screen)
			if tile == Vector2i(-1, -1):
				return
			var anchor := tile - Vector2i(1, 0)
			station_preview = session.builder.preview_station(station_definition, anchor)
			var def := session.stations.station_def(station_definition)
			var tiles := WorldCoords.tiles_in_span(anchor, def.footprint) if def != null else []
			var state := "ok" if bool(station_preview.get("ok", false)) else "invalid"
			ghost_changed.emit(tiles, state, String(station_preview.get("reason", "")),
				float(station_preview.get("cost", 0.0)))
		_:
			ghost_changed.emit([], "none", "", 0.0)


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
