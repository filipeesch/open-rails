extends Node3D

## Root of a running game.  Owns the presentation layer and hands it the
## composition root; it holds no simulation state of its own.
##
## The order in `_ready` is the order the layers need: the valley first, then the
## things that project it, then the things that read the projection.  Audio comes
## last because it listens to everything above it.

@onready var _session: Node = $GameSession

var terrain_renderer: TerrainRenderer
var rail_renderer: RailRenderer
var entity_renderer: EntityRenderer
var camera_rig: IsoCameraRig
var selection: SelectionService
var effects: EffectLayer
var debug_overlay: DebugOverlay
var hud: Hud
var input: InputController
var tool_panel: ToolPanel
var company_panel: CompanyPanel
var context_inspector: ContextInspector
var world_panel: WorldPanel
## The train drawer, authored in `Game.tscn`; held because the inspector's buttons
## arrive there and nothing else in the tree can see both ends of that path.
var train_drawer: TripPanel
var notifications: NotificationCenter
var command_palette: CommandPalette
var map_labels: MapLabels
var hover_tooltip: HoverTooltip
var cursor_state: CursorState
var ghost_readout: GhostReadout
var station_ghost: StationGhost
var settings: SettingsService
var settings_panel: SettingsPanel
var audio: AudioService


func _ready() -> void:
	settings = SettingsService.new()
	_start_sandbox()
	_build_presentation()
	_build_interface()


## The session outlives nothing else here, and it is the one thing that has to be
## released rather than just freed — see `GameSession.shutdown`.  A scene being torn
## down is exactly the case with no new world coming.
func _exit_tree() -> void:
	if _session != null and _session.has_method("shutdown"):
		_session.call("shutdown")


## Open the valley the player asked for, if the menu said which one.  With no
## intent — a direct launch of this scene — the shipped map and the content's own
## company name are used, so the game has never needed the menu to exist.
func _start_sandbox() -> void:
	var intent := SandboxIntent.consume()
	var resume := String(intent.get("save_path", ""))
	if resume == "" and bool(intent.get("pending", false)) \
			and _session.has_method("choose_company_name"):
		_session.choose_company_name(String(intent.get("company_name", "")))
	# The world is booted before it is restored, saved game or not.  A session that
	# never booted has no services to restore into — every one of them is built by
	# the boot — and `restore` over that answers with a wall of Nil rather than a
	# valley.  A resumed game names its own company and its own map, so the choice
	# the New Sandbox screen made is deliberately not applied to it.
	_session.start(String(intent.get("map", "founders_valley")))
	if resume != "":
		_resume_valley(resume)


## Open a saved valley in place of a new one, and say in words when it will not
## open.  A save that cannot be read must never quietly turn into a fresh 1850:
## the button the player pressed said the valley was on disk, and a valley that
## opens empty looks like the game ate their railway.
func _resume_valley(path: String) -> bool:
	var verdict: Dictionary = _session.load_from(path)
	if bool(verdict.get("ok", false)):
		return true
	_session.notify("Could not open the saved valley — %s — so a new one was started." \
			% String(verdict.get("reason", "the file could not be read")), "bad")
	return false


## The inspector's "Focus", whichever kind of thing is selected: the same verb `F`
## performs, since the panel is drawn for the selection.  One behaviour, two hands
## on it, and no chance of the two drifting apart.
func _on_inspector_focus(_kind: String, _entity_id: int) -> void:
	input.focus_selection()


func _on_inspector_route(train_id: int) -> void:
	if train_drawer != null:
		train_drawer.open_route_for(train_id)


func _on_inspector_buy_train(station_id: int) -> void:
	if train_drawer != null:
		train_drawer.open_yard_for(station_id)


func _build_presentation() -> void:
	var world: WorldGrid = _session.world
	camera_rig = IsoCameraRig.new()
	camera_rig.name = "Camera"
	$World3D/CameraRig.add_child(camera_rig)
	camera_rig.configure(world)
	# The valley opens on the town the player is being asked to serve.  The centre
	# of the grid is the open country between the two settlements, so a first
	# frame of nothing at all reads to a player as a broken map.
	var home: int = _session.towns.principal_town()
	if home != 0:
		var home_tile: Vector2i = _session.towns.tile_of(home)
		camera_rig.focus_tile(Vector2(home_tile) + Vector2(0.5, 0.5), true)

	terrain_renderer = TerrainRenderer.new()
	$World3D/Terrain.add_child(terrain_renderer)
	terrain_renderer.attach(world)
	# The water asks where the player is looking so it can leave a lake alone when
	# it is offscreen.  A lambda rather than a stored reference keeps the renderer
	# reading a live value: the camera moves, the renderer never has to be told.
	terrain_renderer.view_source = func() -> Vector3: return camera_rig.target

	rail_renderer = RailRenderer.new()
	$World3D/Rail.add_child(rail_renderer)
	rail_renderer.attach(world, _session.rail)

	entity_renderer = EntityRenderer.new()
	$World3D/Buildings.add_child(entity_renderer)
	entity_renderer.attach(_session, camera_rig)

	effects = EffectLayer.new()
	$World3D/Effects.add_child(effects)
	# Smoke comes off the chimney the artist drew, and the renderer is the one
	# that knows where the built manifest says it is.
	effects.attach(_session, camera_rig, entity_renderer)

	selection = SelectionService.new()
	selection.name = "Selection"
	add_child(selection)
	selection.attach(_session, camera_rig)


func _build_interface() -> void:
	input = InputController.new()
	input.name = "Input"
	add_child(input)
	input.attach(_session, camera_rig, selection)
	input.attach_settings(settings)

	hud = Hud.new()
	_fills_band(hud)
	$UI/TopBar.add_child(hud)
	hud.attach(_session)

	var toolbar := BottomToolbar.new()
	_fills_band(toolbar)
	$UI/BottomToolbar.add_child(toolbar)
	toolbar.attach(_session, input)

	tool_panel = ToolPanel.new()
	$UI/ToolPanel.add_child(tool_panel)
	tool_panel.attach(_session, input)

	# The books live in the same left band as the tool drawer, and each of them
	# stands down when the other is called for: one drawer per band.
	company_panel = CompanyPanel.new()
	company_panel.name = "Company"
	$UI/ToolPanel.add_child(company_panel)
	company_panel.attach(_session, input)

	world_panel = WorldPanel.new()
	world_panel.name = "World"
	$UI/ToolPanel.add_child(world_panel)
	world_panel.attach(_session, input, camera_rig)

	context_inspector = ContextInspector.new()
	$UI/ContextInspector.add_child(context_inspector)
	context_inspector.attach(_session, selection, camera_rig, input)

	# Three of the inspector's buttons are verbs this screen does not own: one
	# belongs to the camera, two to the train drawer.  They were emitted into the
	# air — labels that clicked — so the root, the only place holding both sides,
	# carries them across.
	train_drawer = $UI/TrainDrawer as TripPanel
	context_inspector.focus_requested.connect(_on_inspector_focus)
	context_inspector.route_requested.connect(_on_inspector_route)
	context_inspector.buy_train_requested.connect(_on_inspector_buy_train)

	notifications = NotificationCenter.new()
	$UI/Notifications.add_child(notifications)
	notifications.attach(_session)

	map_labels = MapLabels.new()
	map_labels.name = "MapLabels"
	$UI/MapLabels.add_child(map_labels)
	map_labels.attach(_session, camera_rig)
	map_labels.attach_selection(selection)

	# The pointer is part of the build mode, not a decoration on top of it: the
	# cursor itself carries whether the next click will lay track or refuse it, and
	# the figures beside it are the same preview the click will act on.  Both read
	# the controller's state; neither is allowed an opinion of its own.
	cursor_state = CursorState.new()
	add_child(cursor_state)
	cursor_state.attach(input)

	# Laid track previews in the world, in the domain's own colour for it — the
	# same three words the readout beside the cursor uses.
	rail_renderer.attach_build_controller(input)

	# The station ghost belongs to the world, not to the panel: what is being
	# bought is a stretch of valley.  It draws the domain's preview and nothing of
	# its own, so the yard, the reach and the marks on the towns are the same
	# answer the click will be charged for.
	station_ghost = StationGhost.new()
	station_ghost.name = "StationGhost"
	$World3D/Buildings.add_child(station_ghost)
	station_ghost.attach(_session, input)

	ghost_readout = GhostReadout.new()
	ghost_readout.name = "GhostReadout"
	$UI.add_child(ghost_readout)
	ghost_readout.attach(_session, input)

	hover_tooltip = HoverTooltip.new()
	hover_tooltip.name = "HoverTooltip"
	$UI/Tooltips.add_child(hover_tooltip)
	hover_tooltip.attach(_session, selection)

	command_palette = CommandPalette.new()
	$UI/ModalLayer.add_child(command_palette)
	command_palette.attach(_session, input, camera_rig, selection)

	debug_overlay = DebugOverlay.new()
	$UI/ModalLayer.add_child(debug_overlay)
	debug_overlay.attach(_session, terrain_renderer, rail_renderer)

	settings_panel = SettingsPanel.new()
	settings_panel.name = "Settings"
	settings_panel.visible = false
	$UI/ModalLayer.add_child(settings_panel)
	settings_panel.attach(settings)
	# The one door to the options screen is named here, to the controller that
	# opens it: `O`, Escape and the command palette all go through `O`'s handler.
	input.attach_settings_screen(settings_panel)

	_build_audio(toolbar)


## Stretch a code-built widget across the whole of the band it is about to be
## added to.  A `Control` created in code arrives with top-left anchors and zero
## size, which a band of permanent chrome cannot use: the panel would collapse to
## its minimum size in the corner, and the bar would be as wide as its text rather
## than as wide as the valley.  The band itself is authored in `Game.tscn`.
func _fills_band(control: Control) -> void:
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


## The valley's six sounds.  Audio is built last and listens: it is the only
## layer here that is caused by the others rather than causing them.  The ear is
## pulled from the camera rig rather than pushed, so a rig that never moves costs
## nothing and a rig that moves is heard moving.
func _build_audio(toolbar: BottomToolbar) -> void:
	audio = AudioService.new()
	audio.name = "Audio"
	add_child(audio)
	audio.configure(settings)
	audio.attach_session(_session)
	audio.ear_provider = func() -> Vector3: return camera_rig.target
	audio.start_ambience()
	toolbar.tool_requested.connect(func(_tool: String) -> void: audio.ui_click())
	toolbar.panel_requested.connect(func(_panel: String) -> void: audio.ui_click())
	command_palette.command_invoked.connect(func(_id: String) -> void: audio.ui_click())
	settings_panel.saved.connect(func(_path: String) -> void: audio.ui_click())


func _process(delta: float) -> void:
	_session.advance(delta)
	if camera_rig != null:
		camera_rig.tick(delta)
	if terrain_renderer != null:
		terrain_renderer.tick()
	if rail_renderer != null:
		rail_renderer.tick()
	if entity_renderer != null:
		entity_renderer.tick()
	if effects != null:
		effects.tick()
	if map_labels != null:
		# Dirty-gated: a still camera over a still valley scans nothing.
		map_labels.refresh()
	if company_panel != null:
		company_panel.refresh()
	if audio != null:
		audio.assign_locomotive_voices()
