extends Node3D

## Root of a running game.  Owns the presentation layer and hands it the
## composition root; it holds no simulation state of its own.

@onready var _session: Node = $GameSession

var terrain_renderer: TerrainRenderer
var rail_renderer: RailRenderer
var entity_renderer: EntityRenderer
var camera_rig: IsoCameraRig
var selection: SelectionService
var effects: EffectLayer
var debug_overlay: DebugOverlay
var hud: Hud
var tool_panel: ToolPanel
var context_inspector: ContextInspector
var notifications: NotificationCenter
var command_palette: CommandPalette
var settings: SettingsService
var settings_panel: SettingsPanel


func _ready() -> void:
	settings = SettingsService.new()
	_start_sandbox()
	_build_presentation()
	_build_interface()


## Open the valley the player asked for, if the menu said which one.  With no
## intent — a direct launch of this scene — the shipped map and the content's own
## company name are used, so the game has never needed the menu to exist.
func _start_sandbox() -> void:
	var intent := SandboxIntent.consume()
	if bool(intent.get("pending", false)) and _session.has_method("choose_company_name"):
		_session.choose_company_name(String(intent.get("company_name", "")))
	_session.start(String(intent.get("map", "founders_valley")))


func _build_presentation() -> void:
	var world: WorldGrid = _session.world
	camera_rig = IsoCameraRig.new()
	camera_rig.name = "Camera"
	$World3D/CameraRig.add_child(camera_rig)
	camera_rig.configure(world)

	terrain_renderer = TerrainRenderer.new()
	$World3D/Terrain.add_child(terrain_renderer)
	terrain_renderer.attach(world)

	rail_renderer = RailRenderer.new()
	$World3D/Rail.add_child(rail_renderer)
	rail_renderer.attach(world, _session.rail)

	entity_renderer = EntityRenderer.new()
	$World3D/Buildings.add_child(entity_renderer)
	entity_renderer.attach(_session)

	effects = EffectLayer.new()
	$World3D/Effects.add_child(effects)
	effects.attach(_session, camera_rig)

	selection = SelectionService.new()
	selection.name = "Selection"
	add_child(selection)
	selection.attach(_session, camera_rig)


func _build_interface() -> void:
	var input := InputController.new()
	input.name = "Input"
	add_child(input)
	input.attach(_session, camera_rig, selection)
	input.attach_settings(settings)

	hud = Hud.new()
	$UI/TopBar.add_child(hud)
	hud.attach(_session)

	var toolbar := BottomToolbar.new()
	$UI/BottomToolbar.add_child(toolbar)
	toolbar.attach(_session, input)

	tool_panel = ToolPanel.new()
	$UI/ToolPanel.add_child(tool_panel)
	tool_panel.attach(_session, input)

	context_inspector = ContextInspector.new()
	$UI/ContextInspector.add_child(context_inspector)
	context_inspector.attach(_session, selection, camera_rig)

	notifications = NotificationCenter.new()
	$UI/Notifications.add_child(notifications)
	notifications.attach(_session)

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
	settings_panel.add_to_group("ui_settings_panel")
	settings_panel.attach(settings)


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
