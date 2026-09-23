class_name TestView
extends RefCounted

## Staging for the presentation-layer suites: camera rig, terrain renderer,
## entities, effects and selection, wired exactly as `src/game_root.gd` wires
## them — same classes, same calls, same order.
##
## Nothing here is put into a scene tree, because the test runner is a SceneTree
## script whose root is not in the tree while cases run: no node under it has a
## viewport.  That is a fact about the harness, not about the game, so the rig
## states its own projection and the layers that need pixels or a zoom are handed
## what they would otherwise read live — an authored viewport size and the rig
## itself.  Every one of them still takes the live viewport the moment one exists,
## so the shipped path is the one under test — there is no test-only projection to
## drift from the real one.

const VIEWPORT_SIZE := Vector2(1280.0, 720.0)
const FRAME := 1.0 / 60.0
## Enough frames for the slowest of the three smoothing channels to arrive.
const SETTLE_FRAMES := 120

var host: Node
var session: GameSession
var rig: IsoCameraRig
var renderer: TerrainRenderer
var entities: EntityRenderer
var effects: EffectLayer
var selection: SelectionService


## The full presentation stack over a running session.
static func stage(map_name: String = "founders_valley") -> TestView:
	var view := TestView.new()
	view.host = Node.new()
	view.session = TestSession.create(map_name)
	view.renderer = TerrainRenderer.new()
	view.host.add_child(view.renderer)
	view.renderer.attach(view.session.world)
	view.rig = IsoCameraRig.new()
	view.host.add_child(view.rig)
	view.rig.configure(view.session.world)
	view.entities = EntityRenderer.new()
	view.host.add_child(view.entities)
	view.entities.attach(view.session, view.rig)
	view.entities.viewport_size = VIEWPORT_SIZE
	view.effects = EffectLayer.new()
	view.host.add_child(view.effects)
	view.effects.attach(view.session, view.rig)
	view.selection = SelectionService.new()
	view.host.add_child(view.selection)
	view.selection.attach(view.session, view.rig)
	view.selection.viewport_size = VIEWPORT_SIZE
	return view


## A session over an empty grid: same services, no map content, so a case that
## only needs terrain, a pointer or a drawn entity does not pay for the shipped
## valley.  A blank grid is also the only ground a placement case can be sure of:
## on the hand-authored map, where a yard would go is somebody else's decision.
static func stage_blank(width: int = 64, height: int = 64) -> TestView:
	var view := TestView.new()
	view.host = Node.new()
	view.session = GameSession.new()
	view.session.start_blank(width, height)
	view.renderer = TerrainRenderer.new()
	view.host.add_child(view.renderer)
	view.renderer.attach(view.session.world)
	view.rig = IsoCameraRig.new()
	view.host.add_child(view.rig)
	view.rig.configure(view.session.world)
	view.entities = EntityRenderer.new()
	view.host.add_child(view.entities)
	view.entities.attach(view.session, view.rig)
	view.entities.viewport_size = VIEWPORT_SIZE
	view.effects = EffectLayer.new()
	view.host.add_child(view.effects)
	view.effects.attach(view.session, view.rig)
	view.selection = SelectionService.new()
	view.host.add_child(view.selection)
	view.selection.attach(view.session, view.rig)
	view.selection.viewport_size = VIEWPORT_SIZE
	return view


## Terrain and a rig over a hand-built grid: no session at all, because the
## chunk tests are not testing a simulation.
static func stage_grid(grid: WorldGrid) -> TestView:
	var view := TestView.new()
	view.host = Node.new()
	view.renderer = TerrainRenderer.new()
	view.host.add_child(view.renderer)
	view.renderer.attach(grid)
	view.rig = IsoCameraRig.new()
	view.host.add_child(view.rig)
	view.rig.configure(grid)
	return view


func dispose() -> void:
	# Freeing the host frees every presentation node with it, which is the point:
	# a renderer that leaked a node per rebuild would show up as a leak here.
	if host != null:
		host.free()
		host = null
	if session != null:
		TestSession.dispose(session)
	session = null
	renderer = null
	rig = null
	entities = null
	effects = null
	selection = null


# --- framing ---------------------------------------------------------------

func grid() -> WorldGrid:
	return renderer.world


func rect() -> Rect2:
	return Rect2(Vector2.ZERO, VIEWPORT_SIZE)


func centre_pixel() -> Vector2:
	return VIEWPORT_SIZE * 0.5


## Where the centre of this tile lands on screen, in viewport pixels.  Used to
## build a click from a known answer, so a pick can be checked against the tile
## that produced it instead of against a guessed one.
func screen_of_tile(tile: Vector2i) -> Vector2:
	return rig.project_point(surface_point(tile), rect())


## The middle of a tile's top surface, at its authored elevation.
func surface_point(tile: Vector2i) -> Vector3:
	return Vector3(float(tile.x) + 0.5, grid().elevation_at(tile), float(tile.y) + 0.5)


func look_at_tile(tile: Vector2i) -> void:
	rig.focus_tile(Vector2(float(tile.x) + 0.5, float(tile.y) + 0.5), true)
	rig.tick(FRAME)


## Run the rig until its smoothing has arrived, then report the frame it took.
func settle(frames: int = SETTLE_FRAMES) -> int:
	for frame in frames:
		rig.tick(FRAME)
	return frames


## Pull the view to a commanded zoom and let the easing arrive, so the tier a case
## measures is the one the rig itself settles on rather than a tier asserted by
## writing a number into a renderer.
func zoom_to(tiles: float, frames: int = SETTLE_FRAMES) -> float:
	rig.set_zoom(tiles)
	settle(frames)
	return rig.orthographic_tiles()


## One frame of the whole loop, in the order `game_root._process` runs it: the
## ticks the clock advances, then the layers the root drives.  A case that cares
## about what presentation costs or changes has to run it, not just one of them.
func run_frame(ticks: int = 1) -> void:
	session.advance_ticks(ticks)
	rig.tick(FRAME)
	renderer.tick()
	if entities != null:
		entities.tick()
	if effects != null:
		effects.tick()


## Drive the renderer until its rebuild queue drains.  The queue is filled from
## the grid inside `tick()`, so this always runs at least one cycle; a frame
## budget means a wide change needs several.
func drain_rebuilds(cycles: int = 40) -> int:
	var used := 0
	while used < cycles:
		renderer.tick()
		used += 1
		if renderer.pending_rebuilds() == 0:
			break
	return used


# --- scene-graph evidence --------------------------------------------------

static func count_nodes(root: Node) -> int:
	var total := 1
	for child in root.get_children():
		total += count_nodes(child)
	return total


static func count_mesh_drawables(root: Node) -> int:
	var total := 0
	if root is MeshInstance3D or root is MultiMeshInstance3D:
		total += 1
	for child in root.get_children():
		total += count_mesh_drawables(child)
	return total


static func count_multimeshes(root: Node) -> int:
	var total := 0
	if root is MultiMeshInstance3D:
		total += 1
	for child in root.get_children():
		total += count_multimeshes(child)
	return total


## Anything that would register a shape with the physics server.  The rendering
## layer is required to own none of these: selection is a ray march, not a query.
static func count_physics_objects(root: Node) -> int:
	var total := 0
	if root is PhysicsBody3D or root is Area3D or root is CollisionShape3D \
			or root is CollisionObject3D or root is SoftBody3D:
		total += 1
	for child in root.get_children():
		total += count_physics_objects(child)
	return total


## Every distinct material reachable from a drawable under `root`, keyed by
## instance id.  One shared material is a hard performance rule, and this is the
## only way to tell a shared resource from a per-object copy.
static func materials_in_use(root: Node, into: Dictionary) -> Dictionary:
	if root is MeshInstance3D:
		var instance: MeshInstance3D = root
		_note_surface_materials(instance.mesh, instance.material_override, into)
	elif root is MultiMeshInstance3D:
		var multi: MultiMeshInstance3D = root
		var source: Mesh = null
		if multi.multimesh != null:
			source = multi.multimesh.mesh
		_note_surface_materials(source, multi.material_override, into)
	for child in root.get_children():
		materials_in_use(child, into)
	return into


static func _note_surface_materials(mesh: Mesh, over: Material, into: Dictionary) -> void:
	if over != null:
		into[over.get_instance_id()] = over
		return
	if mesh == null:
		return
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface)
		if material != null:
			into[material.get_instance_id()] = material
