class_name EntityRenderer
extends Node3D

## Puts a visible body on every entity that genuinely needs one — stations,
## industries, town buildings and trains — and nothing else.
##
## Entities are pooled and reused.  A train's consist is re-instantiated only
## when the consist actually changes, not every tick, and labels are screen-space
## Controls projected from world positions rather than Label3D nodes scattered
## across the map.

const LABEL_FADE_SIZE := 46.0

var session: GameSession
var catalog: ModelCatalog = ModelCatalog.new()
var label_layer: CanvasLayer
var label_root: Control

var _stations := {}
var _industries := {}
var _towns := {}
var _trains := {}
var _labels := {}
var _label_pool: Array[Control] = []
var _lod := 0


func attach(game_session: GameSession) -> void:
	session = game_session
	label_layer = CanvasLayer.new()
	label_layer.name = "WorldLabels"
	label_layer.layer = 5
	add_child(label_layer)
	label_root = Control.new()
	label_root.name = "Labels"
	label_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	label_layer.add_child(label_root)
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
	_lod = _camera_lod()
	for train_id in session.trains.trains():
		_tick_train(train_id)
	_refresh_labels()


func label_count() -> int:
	return _labels.size()


func pooled_label_count() -> int:
	return _label_pool.size()


func station_node(station_id: int) -> Node3D:
	return _stations.get(station_id)


func train_node(train_id: int) -> Node3D:
	return _trains.get(train_id)


# --- entities -------------------------------------------------------------

func _rebuild_everything() -> void:
	for key in _stations.keys():
		_remove(_stations[key])
	_stations.clear()
	for key in _industries.keys():
		_remove(_industries[key])
	_industries.clear()
	for key in _towns.keys():
		_remove(_towns[key])
	_towns.clear()
	for key in _trains.keys():
		_remove(_trains[key])
	_trains.clear()
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
	var def := session.stations.def_of(station_id)
	var node := catalog.instantiate(def.asset if def != null else "small_station")
	var anchor: Vector2i = instance["anchor"]
	var footprint: Vector2i = instance["footprint"]
	var centre := Vector2(anchor) + Vector2(footprint) * 0.5 + Vector2(0.5, 0.5)
	node.position = Vector3(centre.x, session.world.elevation_at(Vector2i(roundi(centre.x - 0.5), roundi(centre.y - 0.5))), centre.y)
	node.rotation_degrees = Vector3(0, session.camera_yaw(), 0) if session.has_method("camera_yaw") else Vector3.ZERO
	add_child(node)
	_stations[station_id] = node
	_set_label(node, session.stations.name_of(station_id), "station")


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
		var node := catalog.instantiate("town_house")
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
	_set_label(node, session.industries.name_of(industry_id), "industry")


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
func _rebuild_consist(train_id: int) -> void:
	var root: Node3D = _trains.get(train_id)
	if root == null:
		return
	for child in root.get_children():
		if child is MeshInstance3D or child.name.begins_with("Stock_"):
			_remove(child)
	var stock_ids := session.trains.stock_of(train_id)
	var travelled := 0.0
	var positions: Array[float] = []
	for stock_id in stock_ids:
		var def := session.data.stock(stock_id)
		var length := 0.7 if def == null or def.kind == "wagon" else 0.95
		positions.append(travelled + length * 0.5)
		travelled += length + 0.06
	var index := 0
	for stock_id in stock_ids:
		var def := session.data.stock(stock_id)
		var node := catalog.instantiate(def.asset if def != null else stock_id)
		node.name = "Stock_%d" % index
		node.position = Vector3(0, 0.02, -positions[index])
		root.add_child(node)
		index += 1
	root.set_meta("length", travelled)


func _tick_train(train_id: int) -> void:
	var node: Node3D = _trains.get(train_id)
	if node == null:
		return
	var tiles := session.trains.position_tiles(train_id)
	var tile := Vector2i(floori(tiles.x), floori(tiles.y))
	node.position = Vector3(tiles.x, session.world.elevation_at(tile) + 0.02, tiles.y)
	node.rotation.y = deg_to_rad(session.trains.heading(train_id))


func _remove(node: Node) -> void:
	if node == null:
		return
	node.queue_free()


# --- labels ---------------------------------------------------------------

func _set_label(target: Node3D, text: String, kind: String) -> void:
	if not _labels.has(target):
		var control := _claim_label()
		control.text = text
		control.visible = true
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
	var viewport := get_viewport()
	if viewport == null:
		return
	var camera := viewport.get_camera_3d()
	if camera == null:
		return
	var rect := Rect2(Vector2.ZERO, viewport.get_visible_rect().size)
	var show := session.trains != null and _lod < 2
	for target in _labels.keys():
		if not is_instance_valid(target):
			continue
		var entry: Dictionary = _labels[target]
		var control: Label = entry["control"]
		var screen := camera.unproject_position(target.global_position + Vector3.UP * 0.8)
		# Frustum test, not a screen-rect test: an orthographic camera reports
		# points behind it at plausible screen coordinates.
		var offscreen: bool = not camera.is_position_in_frustum(target.global_position)
		control.visible = show and not offscreen
		if control.visible:
			control.position = screen + rect.position - control.size * 0.5


func _claim_label() -> Label:
	if not _label_pool.is_empty():
		var reused: Label = _label_pool.pop_back()
		reused.visible = true
		return reused
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.06, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label_root.add_child(label)
	return label


func _release_label(control: Control) -> void:
	control.visible = false
	_label_pool.append(control)


func _camera_lod() -> int:
	var viewport := get_viewport()
	if viewport == null:
		return 0
	var camera := viewport.get_camera_3d()
	if camera == null:
		return 0
	if camera.size <= 14.0:
		return 0
	if camera.size <= 44.0:
		return 1
	return 2
