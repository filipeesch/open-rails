class_name EffectLayer
extends Node3D

## Pooled, offscreen-aware visual effects: locomotive smoke and station steam.
##
## One MultiMesh per effect type, a fixed pool of particles, and nothing
## simulated while the emitter is offscreen or further away than the effect's
## useful range.  Smoke is decoration: it never touches simulation state.

const SMOKE_POOL := 220
const SMOKE_LIFE := 2.4
const SMOKE_RISE := 1.5
const SMOKE_DRIFT := 0.5
const SMOKE_MAX_DISTANCE := 70.0
const ARRIVAL_PUFFS := 6

var session: GameSession
var camera_rig: IsoCameraRig
var smoke: MultiMeshInstance3D
var mesh: SphereMesh
var material: StandardMaterial3D

var _particles: Array[Dictionary] = []
var _free: Array[int] = []
var _emitted := 0
var _live := 0


func attach(game_session: GameSession, rig: IsoCameraRig) -> void:
	session = game_session
	camera_rig = rig
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
	var delta := get_process_delta_time()
	var camera_position := _camera_position()
	var emitting_index := 0
	for train_id in session.trains.trains():
		if session.trains.state_of(train_id) != session.trains.State.MOVING:
			continue
		if session.trains.speed_tiles_per_tick(train_id) <= 0.02:
			continue
		var origin := _train_world(train_id)
		if camera_position.distance_to(origin) > SMOKE_MAX_DISTANCE:
			continue
		if emitting_index >= 8:
			continue
		_spawn(origin, 1)
		emitting_index += 1
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


func live_particles() -> int:
	return _live


func emitted_total() -> int:
	return _emitted


func pool_size() -> int:
	return SMOKE_POOL


func puff_at(world_point: Vector3, count: int = 6) -> void:
	_spawn(world_point, count)


func _on_train_arrived(_train_id: int, station_id: int) -> void:
	var tile := session.stations.tile_of(station_id)
	_spawn(Vector3(float(tile.x) + 0.5, session.world.elevation_at(tile) + 0.7, float(tile.y) + 0.5), ARRIVAL_PUFFS)


func _spawn(origin: Vector3, count: int) -> void:
	for _index in count:
		if _free.is_empty():
			return
		var index: int = _free.pop_back()
		var particle: Dictionary = _particles[index]
		particle["alive"] = true
		particle["age"] = 0.0
		particle["position"] = origin
		particle["drift"] = Vector3(randf() * 2.0 - 1.0, 0.0, randf() * 2.0 - 1.0) * SMOKE_DRIFT
		_emitted += 1


func _train_world(train_id: int) -> Vector3:
	var tiles := session.trains.position_tiles(train_id)
	return Vector3(tiles.x, session.world.elevation_at(Vector2i(floori(tiles.x), floori(tiles.y))) + 0.55, tiles.y)


func _camera_position() -> Vector3:
	var viewport := get_viewport()
	if viewport == null:
		return Vector3.ZERO
	var camera := viewport.get_camera_3d()
	return camera.global_position if camera != null else Vector3.ZERO


func _clear() -> void:
	for index in SMOKE_POOL:
		_particles[index]["alive"] = false
		if not _free.has(index):
			_free.append(index)
