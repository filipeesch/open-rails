class_name EntityRenderer
extends Node3D

## Puts a visible body on every entity that genuinely needs one — stations,
## industries, town buildings and trains — and nothing else.
##
## Entities are pooled and reused.  A train's consist is re-instantiated only
## when the consist actually changes, not every tick, and labels are screen-space
## Controls projected from world positions rather than Label3D nodes scattered
## across the map.
##
## Every substantial asset arrives from the compiler carrying three sibling
## bodies — LOD0, LOD1, LOD2 — and a GLB imports all three of them visible, so
## drawing all of them is the bug, not the baseline.  Choosing a tier is
## therefore a visibility switch over siblings: no instantiation, no allocation,
## and it costs one pass over the entities only when the zoom crosses a
## threshold.  The tier itself is the camera rig's orthographic size (see
## `IsoCameraRig.lod_for_tiles`), the game's one distance proxy, and it is
## injected rather than sniffed so the zoom under test is the zoom the game reads.

## Per-entity position updates are skipped this many frames at the far tier.  At
## ninety-six tiles a consist travels a fraction of a pixel per frame, so four
## frames of staleness reads identically for a quarter of the arithmetic.
const FAR_UPDATE_INTERVAL := 4
## How far above an entity its label floats, in world units.
const LABEL_HEIGHT := 0.8
## How far outside the screen a train may sit and still be treated as seen, in
## pixels.  Padding the rectangle rather than testing it exactly means a consist
## scrolling in from the edge is already positioned when it appears, instead of
## jumping into place one frame later.
const OFFSCREEN_MARGIN_PIXELS := 96.0
## How far a station's track-side edge stands out from its model's middle, and
## half of the platform's length down the line, in tiles.  Both are the figure the
## one shipped station is modelled to: a 2.4-tile platform with the rails a tile
## past its edge.
const DEFAULT_PLATFORM_OFFSET := 1.0
const DEFAULT_PLATFORM_HALF_LENGTH := 1.2

## Coupler to coupler: the gap left standing between two vehicles, in tiles.  The
## vehicles are hung from their own coupler faces, which the manifest publishes, so
## the length of a train is arithmetic over its own stock rather than a figure a
## wagon happens to be drawn near.
const COUPLER_GAP := 0.06
## Half-length used for a vehicle whose manifest is missing — a placeholder standing
## in for art that was never built — by class, in tiles.
const DEFAULT_HALF_LENGTH_WAGON := 0.35
const DEFAULT_HALF_LENGTH_LOCO := 0.475

var session: GameSession
var catalog: ModelCatalog = ModelCatalog.new()
var label_layer: CanvasLayer
var label_root: Control
## The view whose zoom picks the tier.  A renderer with no rig is a renderer
## nobody is looking through, and it draws at the game's working zoom.
var camera_rig: IsoCameraRig

## Viewport to assume when this node is not inside a scene tree.  The live
## viewport always wins; an authored size lets a headless host project labels
## through the same path the player uses instead of a second, test-only one.
var viewport_size := Vector2.ZERO

var _stations := {}
var _industries := {}
var _towns := {}
var _trains := {}
var _labels := {}
var _label_pool: Array[Control] = []
var _lod := IsoCameraRig.LOD_MEDIUM
var _bodies: Array[Node3D] = []
var _frames := 0
var _entity_updates := 0
var _suspended := 0
var _wheel_driven := 0
## train id -> one entry per wheeled body: the player that poses it, the length of
## the clip that carries one revolution, the wheel's circumference, and the phase
## last written.
var _wheels := {}
var _travelled := {}
var _wheel_last_tile := {}
## train id -> the consist's layout, one entry per body in train order: how far the
## body's own reference point sits behind the engine's reference point, measured
## along the rails, and the body standing there.
var _consist_offsets := {}
var _consist_nodes := {}
## industry id -> the machinery that runs while the yard is on screen: the player
## standing inside the asset, the clip the definition's own animation state
## resolves to, and whether it is turning on this frame.
var _works := {}
var _works_running := 0


func attach(game_session: GameSession, rig: IsoCameraRig) -> void:
	session = game_session
	camera_rig = rig
	label_layer = CanvasLayer.new()
	label_layer.name = "WorldLabels"
	label_layer.layer = 5
	add_child(label_layer)
	label_root = Control.new()
	label_root.name = "Labels"
	label_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	label_layer.add_child(label_root)
	_lod = lod_level()
	# The company's colours are read from state at the moment the renderer attaches.
	# Painting wires two shared materials and every consist and station in view
	# follows, so a livery is not something a body has to be built to wear.
	catalog.paint_livery(session.company_livery())
	session.station_created.connect(_on_station_created)
	session.station_removed.connect(_on_station_removed)
	session.train_created.connect(_on_train_created)
	session.train_removed.connect(_on_train_removed)
	session.consist_changed.connect(func(train_id: int): _rebuild_consist(train_id))
	session.session_loaded.connect(_rebuild_everything)
	session.towns.town_added.connect(_on_town_added)
	session.industries.industry_added.connect(_on_industry_added)
	_rebuild_everything()


func tick() -> void:
	if session == null:
		return
	_frames += 1
	_select_lod()
	_entity_updates = 0
	_suspended = 0
	_wheel_driven = 0
	var rect := viewport_rect()
	var camera := _live_camera()
	# Deciding who is offscreen needs a projection; without one, everything is
	# treated as seen.  Failing open is the only honest default — a renderer that
	# hides bodies it cannot measure would erase the player's trains.
	var framed_known := rect.size.x > 0.0 and rect.size.y > 0.0 \
			and (camera != null or camera_rig != null)
	# Zoomed out to the overview, a consist is a few pixels long and moves a
	# fraction of one per frame: refresh the bodies on a cadence instead of
	# every frame and the picture is the same for a quarter of the work.
	# The odometer runs for every train on every frame, however far the zoom is and
	# whether or not anyone is looking at it.  A crank angle is a fact about the
	# ground a consist crossed, and one that spent a minute off the edge of the
	# screen must come back with its wheels where the ballast left them, not at
	# zero.  It is a dictionary read per train, which is the cheapest thing in this
	# file; the work the cadence and the suspension below skip is the node work.
	for train_id in session.trains.trains():
		_record_travel(train_id, session.trains.position_tiles(train_id))
	if lod_level() != IsoCameraRig.LOD_FAR or _frames % FAR_UPDATE_INTERVAL == 0:
		for train_id in session.trains.trains():
			var node: Node3D = _trains.get(train_id)
			if node == null:
				continue
			if framed_known and not _is_framed(_train_point(train_id), rect, camera):
				_suspend_train(node)
				continue
			_resume_train(node)
			_tick_train(train_id)
			_entity_updates += 1
	# A work's machinery is animation too, and the same law covers it: the flywheel
	# turns while the yard is on the screen, and stands still when nobody is looking
	# at it or when the view is pulled back past the point a flywheel is visible.
	_tick_works(rect, camera, framed_known)
	_refresh_labels()


## Whether a train is inside the padded screen rectangle.  The same arithmetic the
## labels use, so a consist and its name agree about where the edge is.
func _is_framed(point: Vector3, rect: Rect2, camera: Camera3D) -> bool:
	var screen := camera.unproject_position(point) if camera != null else camera_rig.project_point(point, rect)
	var padded := rect.grow(OFFSCREEN_MARGIN_PIXELS)
	if camera != null:
		# An orthographic camera reports points behind it at plausible coordinates,
		# so the frustum test is the authority and the rectangle is only a margin.
		return camera.is_position_in_frustum(point) or padded.has_point(screen)
	return padded.has_point(screen)


## Where the consist is, straight out of the simulation.  Framing is asked of the
## state and never of the last drawn frame: a body that was skipped has not been
## positioned yet, and measuring that stale origin would keep it hidden forever —
## the suspension would feed on itself and a train scrolled out of view at spawn
## could never come back.
func _train_point(train_id: int) -> Vector3:
	var tiles := session.trains.position_tiles(train_id)
	var tile := Vector2i(floori(tiles.x), floori(tiles.y))
	return Vector3(tiles.x, session.world.elevation_at(tile) + 0.02, tiles.y)


func _suspend_train(node: Node3D) -> void:
	# The simulation owns the train and carries on regardless; what stops here is
	# the presentation's own work — no reposition, no rotation, no wheel phase.
	if node.visible:
		node.visible = false
	_suspended += 1


func _resume_train(node: Node3D) -> void:
	node.visible = true


## Trains whose bodies were left alone on the last frame, and whether one of them
## is a particular train.  Both are read by the debug overlay and by the test that
## proves a hidden train still earns its keep.
func suspended_train_count() -> int:
	return _suspended


func is_train_suspended(train_id: int) -> bool:
	var node: Node3D = _trains.get(train_id)
	return node != null and not node.visible


# --- what the tier is actually doing ----------------------------------------

func lod_level() -> int:
	return IsoCameraRig.lod_for_tiles(zoom_tiles())


## How far out the view is, in tiles visible down the screen.
func zoom_tiles() -> float:
	return camera_rig.orthographic_tiles() if camera_rig != null else WorldConstants.CAMERA_ZOOM_DEFAULT


## Mesh drawables the current tier leaves on screen, across every entity this
## renderer owns.  This is what a tier buys: LOD0 is a part list, LOD1 one merged
## body, LOD2 a silhouette, so the count falls as the view pulls back.
## Bodies positioned on the last frame — the count that hides offscreen work.
func visible_body_count() -> int:
	return int(drawn_geometry(self)["drawables"])


## Triangles behind those drawables, read out of the imported meshes rather than
## asserted from a tier number.
func drawn_triangle_total() -> int:
	return int(drawn_geometry(self)["triangles"])


## Labels are drawn at the two close tiers and gone at the far one: past the
## medium bound a name is a bigger mark on screen than the thing it names.
func labels_shown() -> bool:
	return lod_level() != IsoCameraRig.LOD_FAR


func label_count() -> int:
	return _labels.size()


func pooled_label_count() -> int:
	return _label_pool.size()


## Labels the projection pass left on screen — the ones whose entity is inside the
## view and whose tier still allows a name.
func visible_label_count() -> int:
	var shown := 0
	for entry in _labels.values():
		var control: Label = entry["control"]
		if control.visible:
			shown += 1
	return shown


## Whether this entity's name is on screen right now — the tier's decision and the
## view's, applied to one entity rather than counted over all of them.
func label_is_shown(target: Node3D) -> bool:
	if not _labels.has(target):
		return false
	var control: Label = _labels[target]["control"]
	return control.visible


## How many train bodies this renderer repositioned on its last frame.  The
## per-entity update cadence is a tier behaviour, and this is the only way to see
## it from outside: the positions themselves look the same either way.
func entity_updates_last_frame() -> int:
	return _entity_updates


func station_node(station_id: int) -> Node3D:
	return _stations.get(station_id)


func train_node(train_id: int) -> Node3D:
	return _trains.get(train_id)


## Drawables and triangles a subtree would actually cost to draw: a `MeshInstance3D`
## counts only when it and every ancestor under `root` is visible.  Static and
## public because a caller outside this renderer — a diagnostic, a test — has to
## count the same way the tier does, from the same rule.
static func drawn_geometry(root: Node) -> Dictionary:
	var tally := {"drawables": 0, "triangles": 0}
	_walk_geometry(root, true, tally)
	return tally


static func _walk_geometry(node: Node, seen: bool, tally: Dictionary) -> void:
	var visible := seen
	var body := node as Node3D
	if body != null:
		visible = seen and body.visible
	var instance := node as MeshInstance3D
	if visible and instance != null and instance.mesh != null:
		tally["drawables"] = int(tally["drawables"]) + 1
		tally["triangles"] = int(tally["triangles"]) + _mesh_triangles(instance.mesh)
	for child in node.get_children():
		_walk_geometry(child, visible, tally)


static func _mesh_triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		if indices != null:
			total += int(float(indices.size()) / 3.0)
			continue
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		if vertices != null:
			total += int(float(vertices.size()) / 3.0)
	return total


# --- tier selection --------------------------------------------------------

func _select_lod() -> void:
	var chosen := lod_level()
	if chosen == _lod:
		return
	_lod = chosen
	# An entity removed since the last rebuild leaves a dead entry in the registry,
	# and this is the pass that notices: it prunes as it goes rather than carrying
	# the corpse forward through every later zoom change.
	var live: Array[Node3D] = []
	for root in _bodies:
		if not is_instance_valid(root):
			continue
		live.append(root)
		_apply_lod(root)
	_bodies = live


func _register_body(root: Node3D) -> void:
	_bodies.append(root)
	_apply_lod(root)


## Show this asset instance's body for the current tier and nothing else.
##
## An unbuilt asset has one placeholder body and no LOD siblings, so it is left
## alone: there is nothing to choose between, and hiding the only body there is
## would make a missing asset invisible, which is the one thing a placeholder is
## not allowed to be.
func _apply_lod(root: Node3D) -> void:
	var shipped := -1
	for child in root.get_children():
		shipped = maxi(shipped, _lod_level_of(child.name))
	if shipped < 0:
		return
	# An asset that ships fewer levels than the tier asks for (props ship one or
	# two) draws its cheapest body rather than nothing at all.
	var choice := mini(_lod, shipped)
	for child in root.get_children():
		var level := _lod_level_of(child.name)
		if level >= 0:
			child.visible = level == choice


static func _lod_level_of(node_name: String) -> int:
	if not node_name.begins_with("LOD"):
		return -1
	var suffix := node_name.trim_prefix("LOD")
	return suffix.to_int() if suffix.is_valid_int() else -1


# --- entities -------------------------------------------------------------

func _rebuild_everything() -> void:
	# Each dictionary is emptied AFTER its loop, never inside it: `keys()` hands
	# back a copy, so clearing midway leaves the loop running through names that no
	# longer resolve, and the access error stops the rebuild with half the valley
	# still standing.  That only shows on a rebuild of a *populated* world — a load
	# with two towns in it — which is why it survived a suite that never attached a
	# renderer to a save being restored.
	for key in _stations.keys():
		_remove(_stations[key])
	_stations.clear()
	for key in _industries.keys():
		_remove(_industries[key])
	_industries.clear()
	# Every player the works were wired to went with the nodes `_remove` freed.
	_works.clear()
	_works_running = 0
	for key in _towns.keys():
		_remove(_towns[key])
	_towns.clear()
	for key in _trains.keys():
		_remove(_trains[key])
	_trains.clear()
	_bodies.clear()
	for town_id in session.towns.towns():
		_on_town_added(town_id)
	for industry_id in session.industries.industries():
		_on_industry_added(industry_id)
	for station_id in session.stations.stations():
		_on_station_created(station_id)
	for train_id in session.trains.trains():
		_on_train_created(train_id)


func _on_station_created(station_id: int) -> void:
	var instance := session.stations.station(station_id)
	if instance.is_empty():
		return
	var asset_id := "small_station"
	if session.stations.def_of(station_id) != null:
		asset_id = String(session.stations.def_of(station_id).asset)
	var node := catalog.instantiate(asset_id)
	var reach := platform_reach(asset_id)
	var spot := station_transform(instance, session.stations.rail_access(station_id),
			float(reach[0]), float(reach[1]))
	var at: Vector2 = spot["position"]
	node.position = Vector3(at.x, session.world.elevation_at(WorldCoords.world_to_tile_floor(at)), at.y)
	node.rotation.y = float(spot["yaw"])
	add_child(node)
	_stations[station_id] = node
	_register_body(node)
	# No name here on purpose: a yard's name is a place name, and place names are
	# the map-label layer's job (§72), where the zoom bands and the selected
	# exception live.  What this class labels is the thing it has to follow
	# frame to frame — a train.


## Where a station's model goes: its middle in tile space and its yaw in radians.
##
## A yard is authored as a platform along a line: its long axis is the run, and
## `platform_offset` is how far the track-side edge stands out from the model's
## middle along local +Z, with `platform_half_length` half of the platform
## measured down the line.  So the middle is not the middle of the footprint but
## the point that puts that edge on the lane: the yard is set back off the rail by
## exactly that offset, and slid along the line towards the cell it couples to as
## far as its own ground allows.
##
## Turning it to the run is what makes it read as a station at all.  The model is
## not a billboard: a yard held square to the camera instead of to the track is a
## platform no train can stop at, which is the fault this replaces.  Because a
## platform serves the line from whichever side the rails are on, the run is
## reversed rather than the model mirrored when the rails lie the other way.
static func station_transform(instance: Dictionary, access: Dictionary,
		platform_offset: float = DEFAULT_PLATFORM_OFFSET,
		platform_half_length: float = DEFAULT_PLATFORM_HALF_LENGTH) -> Dictionary:
	var anchor: Vector2i = instance["anchor"]
	var footprint: Vector2i = instance["footprint"]
	var centre := Vector2(anchor) + Vector2(footprint) * 0.5
	var lane := Vector2(access.get("tile", Vector2i.ZERO)) + Vector2(0.5, 0.5)
	var direction: Vector2 = access.get("direction", Vector2.RIGHT)
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	var normal := Vector2(-direction.y, direction.x)
	if (lane - centre).dot(normal) < 0.0:
		direction = -direction
		normal = -normal
	# Slide towards the cell the yard couples to, but only as far as the yard's
	# own ground allows: a platform that hangs over the boundary is standing on
	# ground the player never bought.
	var reach := (absf(direction.x) * float(footprint.x) + absf(direction.y) * float(footprint.y)) * 0.5
	var centre_along := centre.dot(direction)
	var along := clampf(lane.dot(direction), centre_along - reach + platform_half_length,
			centre_along + reach - platform_half_length)
	var origin := direction * along + normal * (lane.dot(normal) - platform_offset)
	return {
		"position": origin,
		"yaw": WorldCoords.yaw_for_direction(direction),
		"direction": direction,
	}


## How far a station class's track-side edge stands out from its model's middle,
## and half of its length down the line — `[offset, half_length]`, in tiles — read
## off the built manifest so the art and the placement cannot drift apart.  The
## coupling attachment says both: it is where a car meets the platform, so its
## distance down the line is the platform's half-length and its distance behind
## the model is where the rails run.  The attachment is authored in Blender space,
## where +y is the model's back, hence the sign flip onto Godot's +Z.  A class
## with no built manifest — a placeholder standing in for unbuilt art — keeps the
## figures the shipped station is modelled to.
func platform_reach(asset_id: String) -> Array:
	var attachments: Dictionary = catalog.manifest(asset_id).get("attachments", {})
	var coupler: Array = attachments.get("coupler_front", [])
	if coupler.size() < 2:
		return [DEFAULT_PLATFORM_OFFSET, DEFAULT_PLATFORM_HALF_LENGTH]
	return [-float(coupler[1]), absf(float(coupler[0]))]


func _on_station_removed(station_id: int) -> void:
	var node: Node3D = _stations.get(station_id)
	if node != null:
		_drop_label(node)
		_remove(node)
	_stations.erase(station_id)


## Town buildings are visual only — the simulation entity is the town itself —
## so they are a small deterministic scatter, not a per-building record.
func _on_town_added(town_id: int) -> void:
	var tile := session.towns.tile_of(town_id)
	var population := session.towns.population_of(town_id)
	var homes := clampi(int(population / 260.0), 4, 22)
	var root := Node3D.new()
	root.name = "Town_%d" % town_id
	for index in homes:
		var node := catalog.instantiate("house")
		var angle := float(index) / float(homes) * TAU
		var radius := 2.0 + float(index % 4) * 1.6
		var offset := Vector2(cos(angle), sin(angle)) * radius
		var at := Vector2i(clampi(tile.x + roundi(offset.x), 0, session.world.width - 1),
			clampi(tile.y + roundi(offset.y), 0, session.world.height - 1))
		var occupancy := session.world.occupancy_at(at)
		# Town ground is the town's own block and houses belong on it; anything
		# else already claims the tile, so the scatter steps around it.
		if occupancy != WorldGrid.Occupancy.NONE and occupancy != WorldGrid.Occupancy.TOWN:
			continue
		node.position = Vector3(float(at.x) + 0.5, session.world.elevation_at(at), float(at.y) + 0.5)
		node.rotation.y = float((index * 37) % 8) * PI / 4.0
		root.add_child(node)
		_register_body(node)
	add_child(root)
	_towns[town_id] = root


func _on_industry_added(industry_id: int) -> void:
	var def := session.industries.def_of(industry_id)
	if def == null:
		return
	var node := catalog.instantiate(def.asset)
	var tile := session.industries.tile_of(industry_id)
	var corner := tile - def.footprint / 2
	var centre := Vector2(corner) + Vector2(def.footprint) * 0.5 + Vector2(0.5, 0.5)
	node.position = Vector3(centre.x, session.world.elevation_at(Vector2i(roundi(centre.x - 0.5), roundi(centre.y - 0.5))), centre.y)
	add_child(node)
	_industries[industry_id] = node
	_register_body(node)
	_wire_work(industry_id, node, def)
	# A work's name is a place name too — see the note on stations.


## Wire a work's own machinery to the clip its asset published for the state its
## definition names.
##
## Both halves of this contract existed and neither kept it: the industry JSON names
## an `animation_state`, and the built manifest maps that state to a clip.  Nothing
## resolved one into the other, so the colliery's flywheel and the power plant's
## beam engine shipped authored and never played.  Whether the clip actually runs is
## decided every frame by `_tick_works`, under the law the wheels already obey —
## nothing animates what nobody can see.
func _wire_work(industry_id: int, node: Node3D, def: DataRegistry.IndustryDef) -> void:
	var clip := _state_clip(def.asset, def.animation_state)
	if clip == "":
		return
	var player := _find_animation_player(node)
	if player == null or not player.has_animation(clip):
		return
	# Machinery has no first revolution.  A clip that arrived unlooped is asked to
	# cycle here rather than redrawing the asset: the presentation is allowed to
	# decline to stop a flywheel dead in mid-turn.
	var animation := player.get_animation(clip)
	if animation != null and animation.loop_mode == Animation.LOOP_NONE:
		animation.loop_mode = Animation.LOOP_LINEAR
	_works[industry_id] = {"player": player, "clip": clip, "running": false}


## The clip an asset publishes for one animation state, or "" when it publishes
## nothing — an unbuilt asset with only a placeholder behind it publishes less.
func _state_clip(asset_id: String, state: String) -> String:
	var states: Dictionary = catalog.manifest(asset_id).get("animation_states", {})
	return String(states.get(state, ""))


## Who is turning this frame.  Detail first: in the overview a works is a speck and
## a flywheel is nothing.  Then the yard's own place on the screen.  Pausing rather
## than stopping keeps the machinery's position, so scrolling back finds the wheel
## mid-turn instead of started over.
func _tick_works(rect: Rect2, camera: Camera3D, framed_known: bool) -> void:
	var detail := lod_level() != IsoCameraRig.LOD_FAR
	var running := 0
	for industry_id in _works:
		var entry: Dictionary = _works[industry_id]
		var player: AnimationPlayer = entry["player"]
		if player == null or not is_instance_valid(player):
			continue
		var want := detail
		if want and framed_known:
			want = _is_framed(_industry_point(industry_id), rect, camera)
		if want and not bool(entry["running"]):
			player.play(String(entry["clip"]))
			entry["running"] = true
		elif not want and bool(entry["running"]):
			player.pause()
			entry["running"] = false
		if bool(entry["running"]):
			running += 1
	_works_running = running


## Where a work stands, asked of the domain for the same reason `_train_point` is:
## a framing test must never be answered by a body that was skipped.
func _industry_point(industry_id: int) -> Vector3:
	var tile := session.industries.tile_of(industry_id)
	return Vector3(float(tile.x) + 0.5, session.world.elevation_at(tile) + 0.02, float(tile.y) + 0.5)


## How many works are turning, and what one particular work is doing.  Read by the
## case that proves an authored animation is played near, and paused far.
func works_running() -> int:
	return _works_running


func industry_animation(industry_id: int) -> Dictionary:
	if not _works.has(industry_id):
		return {}
	var entry: Dictionary = _works[industry_id]
	return {"clip": String(entry["clip"]), "running": bool(entry["running"])}


func _on_train_created(train_id: int) -> void:
	var root := Node3D.new()
	root.name = "Train_%d" % train_id
	add_child(root)
	_trains[train_id] = root
	_rebuild_consist(train_id)
	_set_label(root, session.trains.name_of(train_id), "train")


func _on_train_removed(train_id: int) -> void:
	var node: Node3D = _trains.get(train_id)
	if node != null:
		_drop_label(node)
		_remove(node)
	_trains.erase(train_id)


## Re-instantiate the consist only when the consist changed.
##
## The consist is *not* one rigid body with its cars bolted to a single axis.  One
## path serves the whole train, but every vehicle is placed at its own point on it
## each frame (see `_tick_train`), so what this function decides is where each
## vehicle's reference point sits relative to the engine and how high off its own
## rails it stands.  Both are read off the built manifests: the coupler faces are
## published precisely so that vehicles can be joined without anyone guessing a
## body length, and a wagon redrawn longer lengthens the train with it.
func _rebuild_consist(train_id: int) -> void:
	var root: Node3D = _trains.get(train_id)
	if root == null:
		return
	for child in root.get_children():
		if child is MeshInstance3D or child.name.begins_with("Stock_"):
			_remove(child)
	var stock_ids := session.trains.stock_of(train_id)
	var offsets: Array[float] = []
	var behind := 0.0
	var rear_reach := 0.0
	# Every body of the previous consist is gone, its AnimationPlayer with it, so
	# the wheel list is rebuilt from the bodies wired below.
	var wheels: Array[Dictionary] = []
	var bodies: Array[Node3D] = []
	for index in stock_ids.size():
		var stock_id: String = stock_ids[index]
		var def := session.data.stock(stock_id)
		var reach := _coupler_reach(stock_id, def)
		if index == 0:
			# The point the simulation moves is the engine's front coupler, so the
			# engine's own origin sits one front reach behind it — and a train held
			# at a stop marker has its nose on the marker, as a real train has.
			behind = float(reach[0])
		else:
			behind += rear_reach + COUPLER_GAP + float(reach[0])
		offsets.append(behind)
		rear_reach = float(reach[1])
		var node := catalog.instantiate(def.asset if def != null else stock_id)
		node.name = "Stock_%d" % index
		root.add_child(node)
		_register_body(node)
		bodies.append(node)
		var wheel := _wire_wheels(node, stock_id)
		if not wheel.is_empty():
			wheels.append(wheel)
	root.set_meta("length", behind + rear_reach)
	_consist_offsets[train_id] = offsets
	_consist_nodes[train_id] = bodies
	_wheels[train_id] = wheels
	_tick_train(train_id)
	_apply_wheel_phase(train_id)


## Where a locomotive's chimney actually is, in world space.
##
## The built manifest publishes it as a `smoke_origin` effect attachment, in the
## axes the asset is authored in (`x` forward, `y` across, `z` up), which become
## Godot's `(x, z, -y)`.  Handing it out from here means the plume rises off the
## chimney the artist drew, and a model whose chimney moves in the file moves in
## the game; an asset with no manifest — a placeholder standing in for unbuilt
## art — answers `Vector3.INF` and the caller keeps its own fallback.
func smoke_origin_of(train_id: int) -> Vector3:
	var bodies: Array = _consist_nodes.get(train_id, [])
	if bodies.is_empty():
		return Vector3.INF
	var body: Node3D = bodies[0]
	if body == null or not is_instance_valid(body):
		return Vector3.INF
	var stock_ids := session.trains.stock_of(train_id)
	if stock_ids.is_empty():
		return Vector3.INF
	var offset := attachment_offset(String(stock_ids[0]), "smoke_origin")
	if offset == Vector3.INF:
		return offset
	var root: Node3D = _trains.get(train_id)
	if root == null or not is_instance_valid(root):
		return Vector3.INF
	# Composed by hand instead of read off `global_transform`.  `_tick_train` roots a
	# consist at the train's own world position and hangs each vehicle off that root,
	# so the root's transform *is* a world transform and this product is the chimney
	# — with or without a scene tree.  `global_transform` asks a question the tree
	# has to answer: outside one, a node's global transform is only its local one,
	# the lead position drops out, and every plume lands at the world origin.
	return root.transform * (body.transform * offset)


## One published attachment as a Godot-space offset, or `Vector3.INF` when the
## manifest does not carry it.  Public because the effect layer has to ask where
## a chimney is, and guessing a height from the ground up is what made the smoke
## sit half a tile below the engine that was making it.
func attachment_offset(stock_id: String, key: String) -> Vector3:
	var attachments: Dictionary = catalog.manifest(stock_id).get("attachments", {})
	var values: Array = attachments.get(key, [])
	if values.size() < 3:
		return Vector3.INF
	return Vector3(float(values[0]), float(values[2]), -float(values[1]))


## How the consist is strung out: one distance per vehicle, behind the engine's own
## reference point and measured along the rails, in train order.  A read accessor for
## the same reason `train_node` is one — the layout is the renderer's business, and a
## test that had to guess it would only be measuring its own guess.
func consist_offsets(train_id: int) -> Array:
	return _consist_offsets.get(train_id, [])


## How far each end of a vehicle stands out from its own origin, as `[front, rear]`
## in tiles.  The coupler faces published by the built manifest *are* those ends —
## an asset with no manifest, a placeholder for art that was never built, keeps the
## half-length the shipped body of its class is modelled to.
func _coupler_reach(stock_id: String, def: DataRegistry.StockDef) -> Array:
	var attachments: Dictionary = catalog.manifest(stock_id).get("attachments", {})
	var front: Array = attachments.get("coupler_front", [])
	var rear: Array = attachments.get("coupler_rear", [])
	if front.is_empty() or rear.is_empty():
		var half := DEFAULT_HALF_LENGTH_LOCO if def != null and def.kind == "locomotive" \
				else DEFAULT_HALF_LENGTH_WAGON
		return [half, half]
	return [absf(float(front[0])), absf(float(rear[0]))]


## Stand the whole train on its own rails: the root at the engine, and each vehicle
## at its own point, on its own tangent, at its own height.
##
## One path serves the train, and the train follows it as a whole — but a vehicle
## turns the way it is standing, so a consist swings through a curve one vehicle at
## a time, engine already on the new bearing while the brake van is still on the
## old one.  Bolting the bodies to one root and rotating the root cannot do that: a
## train four tiles long pivoting about its own centre puts the tail several tiles
## off the rails it is supposed to be riding, which is the fault this replaces.
func _tick_train(train_id: int) -> void:
	var root: Node3D = _trains.get(train_id)
	if root == null:
		return
	var bodies: Array = _consist_nodes.get(train_id, [])
	var offsets: Array = _consist_offsets.get(train_id, [])
	if bodies.is_empty() or bodies.size() != offsets.size():
		return
	var frames := session.trains.consist_frames(train_id, offsets)
	if frames.size() != bodies.size():
		return
	var lead: Dictionary = frames[0]
	var lead_at: Vector2 = session.trains.position_tiles(train_id)
	var lead_ground := TrackPieces.surface(session.world, lead["from_tile"], lead["to_tile"],
			float(lead["t"]))
	# The root carries the train, and the train's position is whatever the simulation
	# says it is — the engine's front coupler — so a label, a click and a screen test
	# asking where a train stands all get the same answer the domain gives.  The root
	# carries no rotation: direction belongs to the vehicle standing on the rail.
	root.position = Vector3(lead_at.x, lead_ground, lead_at.y)
	root.rotation = Vector3.ZERO
	for index in bodies.size():
		var body: Node3D = bodies[index]
		if body == null or not is_instance_valid(body):
			continue
		_place_vehicle(body, frames[index], lead_at, lead_ground)
	_apply_wheel_phase(train_id)


## One vehicle, standing on the rails where its own point on the line is.
##
## Height is the tile surface, because the models are compiled with their wheels on
## the rail head at `TrackPieces.RIDE_HEIGHT` above their own origin: a vehicle set
## down on the surface it runs over has its wheels on the rail, by construction and
## not by tuning.  Pitch is that surface's own gradient, so a locomotive climbing a
## grade leans into it instead of hovering over it with its nose in the air.
func _place_vehicle(body: Node3D, frame: Dictionary,
		lead_at: Vector2, lead_ground: float) -> void:
	var at: Vector2 = frame["at"]
	var from_tile: Vector2i = frame["from_tile"]
	var to_tile: Vector2i = frame["to_tile"]
	var t := float(frame["t"])
	var ground := TrackPieces.surface(session.world, from_tile, to_tile, t)
	var direction: Vector2 = frame["direction"]
	var yaw := WorldCoords.yaw_for_direction(direction)
	var rise := session.world.elevation_at(to_tile) - session.world.elevation_at(from_tile)
	var step := maxf(float(frame.get("step", 1.0)), 0.0001)
	body.transform = Transform3D(
		Basis(Vector3.UP, yaw) * Basis(Vector3(0.0, 0.0, 1.0), atan2(rise, step)),
		Vector3(at.x - lead_at.x, ground - lead_ground, at.y - lead_at.y))



# --- wheel phase ----------------------------------------------------------

## A wheel turns because the train moved, not because time passed.
##
## Phase is travelled distance divided by the wheel's circumference, wrapped to a
## turn, and each asset's `moving` clip is exactly one revolution — so the phase is
## the clip position, nothing else.  Three consequences the tests pin down: a train
## standing in a yard cannot animate its wheels, a train covering twice the distance
## between two frames turns them twice as far, and a consist whose bodies were
## rebuilt mid-run keeps its crank angle because the distance lives on the train,
## not on the nodes.
func _record_travel(train_id: int, tiles: Vector2) -> void:
	var last: Vector2 = _wheel_last_tile.get(train_id, tiles)
	_travelled[train_id] = float(_travelled.get(train_id, 0.0)) + last.distance_to(tiles)
	_wheel_last_tile[train_id] = tiles


## How one vehicle's wheels are to be posed, or an empty Dictionary when the
## asset carries no mechanical clip to pose.  Handed back rather than filed away,
## so the consist that owns it stays the single place its bodies are listed.
func _wire_wheels(stock_node: Node3D, stock_id: String) -> Dictionary:
	var player := _find_animation_player(stock_node)
	if player == null:
		return {}
	var clip := _moving_clip(stock_id)
	if clip == "" or not player.has_animation(clip):
		return {}
	var seconds := player.get_animation(clip).length
	if seconds <= 0.0:
		return {}
	var circumference := _wheel_circumference(stock_id)
	if circumference <= 0.0:
		return {}
	# The clock is switched off on purpose.  A free-running player animates a
	# stationary train and misses a fast one, and neither is a wheel.
	player.play(clip)
	player.pause()
	return {"player": player, "clip": clip, "seconds": seconds,
			"circumference": circumference, "phase": 0.0}


func _apply_wheel_phase(train_id: int) -> void:
	var distance := float(_travelled.get(train_id, 0.0))
	for entry in _wheels.get(train_id, []):
		var player: AnimationPlayer = entry["player"]
		if player == null or not is_instance_valid(player):
			continue
		var phase := fmod(distance / float(entry["circumference"]), 1.0)
		entry["phase"] = phase
		# `seek` is the only way into a clip's timeline: `playback_position` is
		# read-only, and `update = true` poses the wheels on this frame instead of
		# waiting for a clock that has been deliberately stopped.
		player.seek(phase * float(entry["seconds"]), true)
		_wheel_driven += 1


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _moving_clip(stock_id: String) -> String:
	var manifest := catalog.manifest(stock_id)
	var states: Dictionary = manifest.get("animation_states", {})
	return String(states.get("moving", ""))


## The biggest wheel on the vehicle: the drivers, not the leading truck.  Their
## circumference is what converts ground distance into a crank angle, and the
## compiler published it rather than letting the renderer measure a mesh.
func _wheel_circumference(stock_id: String) -> float:
	var circumferences: Dictionary = catalog.manifest(stock_id).get("wheel_circumference_tiles", {})
	var best := 0.0
	for value in circumferences.values():
		best = maxf(best, float(value))
	return best


## How far the wheels of a train have turned, as a fraction of a revolution (the
## locomotive's, which is the one the eye follows), how far the train has been
## hauled in tile units, and how many bodies were posed on the last frame.
func wheel_phase(train_id: int) -> float:
	var entries: Array = _wheels.get(train_id, [])
	return float(entries[0]["phase"]) if not entries.is_empty() else 0.0


func wheel_distance(train_id: int) -> float:
	return float(_travelled.get(train_id, 0.0))


func wheels_driven_last_tick() -> int:
	return _wheel_driven


func _remove(node: Node) -> void:
	if node == null:
		return
	node.queue_free()


# --- labels ---------------------------------------------------------------

func _set_label(target: Node3D, text: String, kind: String) -> void:
	if not _labels.has(target):
		var control := _claim_label()
		control.text = text
		_labels[target] = {"control": control, "kind": kind}
	else:
		_labels[target]["control"].text = text


func _drop_label(target: Node3D) -> void:
	if not _labels.has(target):
		return
	var entry: Dictionary = _labels[target]
	_release_label(entry["control"])
	_labels.erase(target)


func _refresh_labels() -> void:
	var rect := viewport_rect()
	var camera := _live_camera()
	# Nothing can be placed without something to project through: either the live
	# camera or, outside a scene tree, the rig's own identical arithmetic.
	if rect.size.x <= 0.0 or rect.size.y <= 0.0 or (camera == null and camera_rig == null):
		return
	var show := labels_shown()
	for target in _labels.keys():
		if not is_instance_valid(target):
			continue
		var entry: Dictionary = _labels[target]
		var control: Label = entry["control"]
		var body := target as Node3D
		control.visible = false
		if not show:
			continue
		var point := _world_point(body) + Vector3.UP * LABEL_HEIGHT
		var screen := camera.unproject_position(point) if camera != null else camera_rig.project_point(point, rect)
		# Inside a tree the frustum is the authority, because an orthographic
		# camera reports points behind it at plausible screen coordinates; the
		# rig's projection has the same trap and answers it the same way, by
		# asking whether the pixel landed on the screen at all.
		var framed := camera.is_position_in_frustum(point) if camera != null else rect.has_point(screen)
		control.visible = framed
		if framed:
			control.position = screen + rect.position - control.size * 0.5


## The rectangle pixels are measured in: the live viewport, or the authored size.
func viewport_rect() -> Rect2:
	var viewport := get_viewport()
	if viewport != null:
		var live := viewport.get_visible_rect()
		if live.size.x > 0.0 and live.size.y > 0.0:
			return live
	return Rect2(Vector2.ZERO, viewport_size)


func _live_camera() -> Camera3D:
	var viewport := get_viewport()
	return viewport.get_camera_3d() if viewport != null else null


## The world point a label hangs from.  Everything this renderer draws is a direct
## child of it and the renderer itself is never moved, so outside a scene tree the
## local position is already the world position.
func _world_point(node: Node3D) -> Vector3:
	return node.global_position if node.is_inside_tree() else node.position


func _claim_label() -> Label:
	# A claimed label comes back hidden on purpose: only the projection pass gets
	# to decide that a name is on screen, so a recycled control cannot flash over
	# an entity that has since scrolled away.
	if not _label_pool.is_empty():
		var reused: Label = _label_pool.pop_back()
		return reused
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.06, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = false
	label_root.add_child(label)
	return label


func _release_label(control: Control) -> void:
	control.visible = false
	_label_pool.append(control)
