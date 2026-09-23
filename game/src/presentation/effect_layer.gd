class_name EffectLayer
extends Node3D

## Pooled, offscreen-aware visual effects: locomotive smoke and station steam.
##
## One MultiMesh per effect type, a fixed pool of particles, and nothing
## simulated while the emitter is offscreen or further away than the effect's
## useful range.  Smoke is decoration: it never touches simulation state.
##
## The tier is the camera rig's orthographic size, the same proxy the entity
## bodies read, so pulling the view back steps the effects down through the
## documented tiers: one puff per emitting locomotive per frame close in, every
## other frame at the working zoom, and nothing at all in the overview — where
## the pool is only stepped on a fraction of the frames, which is how the smoke
## already in the air ages out instead of hanging there for the rest of the run.

const SMOKE_POOL := 220
const SMOKE_LIFE := 2.4
const SMOKE_RISE := 1.5
const SMOKE_DRIFT := 0.5
const SMOKE_MAX_DISTANCE := 70.0
const ARRIVAL_PUFFS := 6
## Locomotives emitting at once.  Beyond this the extra plumes are indistinguishable
## from the ones already drawn, and the pool would only be spending slots.
const MAX_EMITTERS := 8
## The medium tier halves the emission rate: a plume every other frame is the same
## column of smoke from a dozen tiles up, for half the spawns.
const MEDIUM_RATE_DIVISOR := 2
## At the far tier the pool is stepped once every this many frames — enough to
## finish off what is already airborne, far too little to be a per-frame cost.
const FAR_UPDATE_INTERVAL := 4
## Seconds a step advances a particle's life when the engine has no process delta
## to give: a pool that is never aged never frees its particles, so a host outside
## a frame — a headless run, an offscreen pass — still has to pay the display rate
## this layer was authored against.
const STEP_SECONDS := 1.0 / 60.0
## Where smoke starts when the drawn locomotive cannot say where its own chimney
## is — an asset with no built manifest.  Only a fallback: the manifest's
## `smoke_origin` is the answer, and it is a different height per model.
const SMOKE_FALLBACK_HEIGHT := 0.55
## The pool's drift is chosen, not rolled.  Smoke is presentation and never
## touches the simulation, but a run that cannot reproduce its own screen is a
## run nobody can compare frame to frame, and an unseeded `randf()` shares the
## engine's global generator with anything else that rolls.
const SMOKE_SEED := 0x05104E52

var session: GameSession
var camera_rig: IsoCameraRig
var entities: EntityRenderer
var smoke: MultiMeshInstance3D
var mesh: SphereMesh
var material: StandardMaterial3D

var _particles: Array[Dictionary] = []
var _free: Array[int] = []
var _emitted := 0
var _live := 0
var _frames := 0
var _steps := 0
var _rng := RandomNumberGenerator.new()


func attach(game_session: GameSession, rig: IsoCameraRig, renderer: EntityRenderer = null) -> void:
	session = game_session
	camera_rig = rig
	entities = renderer
	_rng.seed = SMOKE_SEED
	mesh = SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.32
	mesh.radial_segments = 6
	mesh.rings = 3
	material = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.85, 0.85, 0.88, 0.5)
	material.vertex_color_use_as_albedo = true
	smoke = MultiMeshInstance3D.new()
	smoke.name = "Smoke"
	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.use_colors = true
	multi_mesh.mesh = mesh
	multi_mesh.instance_count = SMOKE_POOL
	smoke.multimesh = multi_mesh
	smoke.material_override = material
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smoke)
	for index in SMOKE_POOL:
		_particles.append({"alive": false, "position": Vector3.ZERO, "age": 0.0, "scale": 1.0, "drift": Vector3.ZERO})
		_free.append(index)
	session.train_arrived.connect(_on_train_arrived)
	session.session_loaded.connect(_clear)


func tick() -> void:
	if session == null or smoke == null:
		return
	_frames += 1
	if lod_level() == IsoCameraRig.LOD_FAR and _frames % FAR_UPDATE_INTERVAL != 0:
		return
	_step()


# --- what the tier is actually doing ----------------------------------------

func lod_level() -> int:
	return camera_rig.lod_level() if camera_rig != null else IsoCameraRig.LOD_NEAR


## Smoke exists at the two close tiers and stops entirely at the far one, where a
## puff is a speck that costs the same pool slot as a visible one.
func particles_allowed() -> bool:
	return lod_level() != IsoCameraRig.LOD_FAR


## Whether the layer is currently suspended: nothing new is born and the pool is
## stepped on a fraction of the frames.  Nothing here reaches the simulation, so
## this is the state a run of the game can be dropped into without cost.
func animation_suspended() -> bool:
	return not particles_allowed()


func live_particles() -> int:
	return _live


func emitted_total() -> int:
	return _emitted


## Frames on which the pool was actually stepped.  This is the update-frequency
## tier made visible: at the far tier it grows a quarter as fast as `_frames`.
func step_count() -> int:
	return _steps


func pool_size() -> int:
	return SMOKE_POOL


func puff_at(world_point: Vector3, count: int = 6) -> void:
	_spawn(world_point, count)


# --- the pool -------------------------------------------------------------

func _step() -> void:
	_steps += 1
	var delta := get_process_delta_time()
	if delta <= 0.0:
		delta = STEP_SECONDS
	if particles_allowed() and _emission_rate_allows():
		_emit_from_chimneys()
	var live := 0
	for index in SMOKE_POOL:
		var particle: Dictionary = _particles[index]
		if not bool(particle["alive"]):
			smoke.multimesh.set_instance_transform(index, Transform3D(Basis(), Vector3(0, -1000, 0)))
			continue
		particle["age"] = float(particle["age"]) + delta
		if float(particle["age"]) >= SMOKE_LIFE:
			particle["alive"] = false
			_free.append(index)
			smoke.multimesh.set_instance_transform(index, Transform3D(Basis(), Vector3(0, -1000, 0)))
			continue
		live += 1
		var life := float(particle["age"]) / SMOKE_LIFE
		var position: Vector3 = particle["position"] + Vector3(particle["drift"].x, SMOKE_RISE * life, particle["drift"].z)
		var scale := lerpf(0.5, 2.2, life)
		smoke.multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ONE * scale), position))
		smoke.multimesh.set_instance_color(index, Color(0.86, 0.86, 0.9, 0.55 * (1.0 - life)))
	_live = live


## One puff per moving locomotive inside the view's useful range, capped at
## `MAX_EMITTERS` chimneys per step.
func _emit_from_chimneys() -> void:
	var anchor := _view_anchor()
	var emitting_index := 0
	for train_id in session.trains.trains():
		if session.trains.state_of(train_id) != session.trains.State.MOVING:
			continue
		if session.trains.speed_tiles_per_tick(train_id) <= 0.02:
			continue
		var origin := train_smoke_origin(train_id)
		if anchor.distance_to(origin) > SMOKE_MAX_DISTANCE:
			continue
		if emitting_index >= MAX_EMITTERS:
			break
		_spawn(origin, 1)
		emitting_index += 1


## How often a locomotive's chimney is allowed to fire.  An event puff — a train
## arriving — is not a rate and is not throttled by this; only the per-frame
## emission is.
func _emission_rate_allows() -> bool:
	if lod_level() == IsoCameraRig.LOD_MEDIUM:
		return _frames % MEDIUM_RATE_DIVISOR == 0
	return true


func _on_train_arrived(_train_id: int, station_id: int) -> void:
	var tile := session.stations.tile_of(station_id)
	_spawn(Vector3(float(tile.x) + 0.5, session.world.elevation_at(tile) + 0.7, float(tile.y) + 0.5), ARRIVAL_PUFFS)


func _spawn(origin: Vector3, count: int) -> void:
	if not particles_allowed():
		return
	for _index in count:
		if _free.is_empty():
			return
		var index: int = _free.pop_back()
		var particle: Dictionary = _particles[index]
		particle["alive"] = true
		particle["age"] = 0.0
		particle["position"] = origin
		particle["drift"] = Vector3(_rng.randf() * 2.0 - 1.0, 0.0, _rng.randf() * 2.0 - 1.0) * SMOKE_DRIFT
		_emitted += 1


## Where a locomotive is emitting from.
##
## The built manifest says where each model's chimney is, and that is the answer
## whenever the entity renderer can hand it over.  The ground-plus-fallback figure
## below is only for a placeholder standing in for unbuilt art: taken as the rule,
## it put every plume in the same place regardless of the engine making it, half a
## tile below the cab roof it was supposed to be coming out of.
func train_smoke_origin(train_id: int) -> Vector3:
	if entities != null:
		var chimney := entities.smoke_origin_of(train_id)
		if chimney != Vector3.INF:
			return chimney
	var tiles := session.trains.position_tiles(train_id)
	return Vector3(tiles.x,
			session.world.elevation_at(Vector2i(floori(tiles.x), floori(tiles.y))) + SMOKE_FALLBACK_HEIGHT,
			tiles.y)


## The point the view is centred on.  Under an orthographic camera the eye sits a
## fixed, arbitrary distance back — measured to it, every emitter on the map is
## equally far away and the range test silently culls everything.  What matters is
## distance from the middle of what is on screen: an emitter outside the useful
## range of the view is pluming where nobody can see it.
func _view_anchor() -> Vector3:
	return camera_rig.target if camera_rig != null else Vector3.ZERO


func _clear() -> void:
	for index in SMOKE_POOL:
		_particles[index]["alive"] = false
		if not _free.has(index):
			_free.append(index)
