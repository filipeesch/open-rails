class_name StationGhost
extends Node3D

## The world-space ghost of a station that has not been paid for yet.
##
## A station is bought for its reach, not for its 3x2 yard, so the preview has to
## be seen on the map: the ground that would be occupied, the ring of ground it
## would drain, and a mark on each town, mine or plant that would actually feed
## it.  Every figure drawn here is read out of `BuilderService.preview_station` —
## the same dictionary `build_station` re-runs on the click — so the ghost cannot
## promise a town the finished station would not serve, and a ghost that says no
## has already said no to the domain.
##
## Three bands, one shared translucent material, no node per tile: the whole
## preview is three meshes, and they are rebuilt only when the preview's answer
## actually changes — a mouse crossing the same tile costs nothing.

const BAND_FOOTPRINT := "footprint"
const BAND_CATCHMENT := "catchment"
const BAND_COVERAGE := "coverage"
const BANDS := [BAND_FOOTPRINT, BAND_CATCHMENT, BAND_COVERAGE]

const LIFT_CATCHMENT := 0.02
const LIFT_FOOTPRINT := 0.05
const LIFT_COVERAGE := 0.09
const COVERAGE_INSET := 0.18
const LINK_WIDTH := 0.10

const COLOUR_OK := Color(0.35, 0.85, 0.40, 0.55)
const COLOUR_WARN := Color(0.95, 0.80, 0.25, 0.55)
const COLOUR_INVALID := Color(0.90, 0.25, 0.22, 0.60)
const COLOUR_CATCHMENT := Color(0.55, 0.70, 0.90, 0.16)
const COLOUR_LOAD := Color(0.95, 0.78, 0.30, 0.85)
const COLOUR_UNLOAD := Color(0.36, 0.62, 0.86, 0.85)

var session: GameSession
var controller: InputController

var _material: StandardMaterial3D
var _bands := {}
var _footprint: Array[Vector2i] = []
var _catchment: Array[Vector2i] = []
var _sources: Array[Dictionary] = []
var _monthly := {}
var _cost := 0.0
var _validity := "none"
var _reason := ""
var _answer := ""
var _rebuilds := 0


func attach(game_session: GameSession, build_controller: InputController) -> void:
	session = game_session
	controller = build_controller
	_material = _overlay_material()
	for band in BANDS:
		var node := MeshInstance3D.new()
		node.name = band.capitalize() + "Band"
		node.material_override = _material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_bands[band] = node
	controller.ghost_changed.connect(_on_ghost_changed)
	controller.tool_changed.connect(_on_tool_changed)
	controller.station_ghost_previewed.connect(_on_station_preview)
	hide()


# --- what the preview looks like, as asked ----------------------------------

func is_shown() -> bool:
	return visible


func footprint_cells() -> Array[Vector2i]:
	return _footprint


func catchment_cells() -> Array[Vector2i]:
	return _catchment


func covered_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for entry in _sources:
		var tile := Vector2i(entry["tile"])
		if not cells.has(tile):
			cells.append(tile)
	return cells


func covered_entries() -> Array[Dictionary]:
	return _sources


## Per cargo, what the covered sources would put up in a month.  The domain added
## these up; this node only hands them to the readout.
func monthly_expectation() -> Dictionary:
	return _monthly


func cost() -> float:
	return _cost


func validity() -> String:
	return _validity


func reason() -> String:
	return _reason


## How many times geometry was actually rebuilt.  A ghost that follows the
## pointer must not re-tessellate on every mouse event.
func rebuilds() -> int:
	return _rebuilds


## The mesh a band drew, for anything that has to check what was actually built
## rather than what was asked for.  The three bands share one translucent
## material, which `material_override` on each of them reports.
func band_mesh(band: String) -> Mesh:
	var node: MeshInstance3D = _bands.get(band)
	return null if node == null else node.mesh


# --- the pointer's answer ---------------------------------------------------

func _on_ghost_changed(_tiles: Array[Vector2i], state: String, _reason_arg: String,
		_cost_arg: float) -> void:
	if state == "none":
		_retire()


## The tool that is in hand decides who speaks.  Every other tool's ghost is a run
## of track cells, which the rail renderer draws; this node has a station to talk
## about or it has nothing to say — and it goes quiet the moment the tool changes,
## not at some later mouse event.
func _on_tool_changed(tool: String) -> void:
	if tool != InputController.TOOL_STATION:
		_retire()


func _on_station_preview(preview: Dictionary) -> void:
	_validity = _state_of(preview)
	_reason = String(preview.get("reason", ""))
	_cost = float(preview.get("cost", 0.0))
	var footprint := _cells_of(preview, "footprint")
	var catchment := _cells_of(preview, "catchment")
	var sources: Array[Dictionary] = []
	for entry in Array(preview.get("sources", [])):
		sources.append(Dictionary(entry))
	var monthly := Dictionary(preview.get("monthly", {}))
	var answer := _answer_for(footprint, catchment, sources, monthly)
	if answer == _answer:
		# The same answer from the domain: redraw nothing, keep showing it.
		show()
		return
	_answer = answer
	_footprint = footprint
	_catchment = catchment
	_sources = sources
	_monthly = monthly
	_rebuild_bands()
	_rebuilds += 1
	show()


## The domain's own word for the preview, defaulting to the colour that refuses:
## a preview this node cannot read must never look like an invitation.
func _state_of(preview: Dictionary) -> String:
	return String(preview.get("state", "invalid"))


## Everything the bands are drawn from, in one string.  If it matches the last
## answer, the meshes are still correct and rebuilding them would be busywork.
func _answer_for(footprint: Array[Vector2i], catchment: Array[Vector2i],
		sources: Array[Dictionary], monthly: Dictionary) -> String:
	var parts := [_validity, _reason]
	for tile in footprint:
		parts.append("f%d:%d" % [tile.x, tile.y])
	for tile in catchment:
		parts.append("c%d:%d" % [tile.x, tile.y])
	for entry in sources:
		var tile := Vector2i(entry["tile"])
		parts.append("s%s:%d:%d:%s" % [String(entry.get("cargo", "")), tile.x, tile.y,
			String(entry.get("role", ""))])
	for cargo_id in monthly.keys():
		parts.append("m%s:%f" % [String(cargo_id), float(monthly[cargo_id])])
	parts.append("%f" % _cost)
	return "|".join(parts)


func _retire() -> void:
	_answer = ""
	_validity = "none"
	_reason = ""
	_cost = 0.0
	_footprint = []
	_catchment = []
	_sources = []
	_monthly = {}
	for band in BANDS:
		(_bands[band] as MeshInstance3D).mesh = null
	hide()


func _cells_of(preview: Dictionary, key: String) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for tile in Array(preview.get(key, [])):
		cells.append(Vector2i(tile))
	return cells


# --- geometry ---------------------------------------------------------------

func _rebuild_bands() -> void:
	var tint := COLOUR_OK
	match _validity:
		"expensive":
			tint = COLOUR_WARN
		"invalid":
			tint = COLOUR_INVALID
	(_bands[BAND_FOOTPRINT] as MeshInstance3D).mesh = _pad_mesh(_footprint, tint, LIFT_FOOTPRINT, 0.0)
	(_bands[BAND_COVERAGE] as MeshInstance3D).mesh = _coverage_mesh()
	var ring: Array[Vector2i] = []
	for tile in _catchment:
		if not _footprint.has(tile):
			ring.append(tile)
	(_bands[BAND_CATCHMENT] as MeshInstance3D).mesh = _pad_mesh(ring, COLOUR_CATCHMENT,
		LIFT_CATCHMENT, 0.0)


func _pad_mesh(tiles: Array[Vector2i], colour: Color, lift: float, inset: float) -> ArrayMesh:
	var builder := _begin()
	for tile in tiles:
		_append_tile(builder, tile, colour, lift, inset)
	return _finish(builder)


## A mark on every place the station would draw from or deliver to, with a
## ribbon laid from the yard to each one: coverage is a relationship, and a ring
## of translucent tiles does not say which town inside it is the one that pays.
func _coverage_mesh() -> ArrayMesh:
	var builder := _begin()
	if _footprint.is_empty():
		return null
	var yard := _span_centre(_footprint)
	for entry in _sources:
		var tile := Vector2i(entry["tile"])
		var colour := COLOUR_LOAD if String(entry.get("role", "")) == "load" \
			else COLOUR_UNLOAD
		_append_tile(builder, tile, colour, LIFT_COVERAGE, COVERAGE_INSET)
		_append_ribbon(builder, yard, tile, colour)
	return _finish(builder)


## The middle of a footprint's cells, in world coordinates.
func _span_centre(tiles: Array[Vector2i]) -> Vector2:
	var low := Vector2i(tiles[0])
	var high := Vector2i(tiles[0])
	for tile in tiles:
		low = Vector2i(mini(tile.x, low.x), mini(tile.y, low.y))
		high = Vector2i(maxi(tile.x, high.x), maxi(tile.y, high.y))
	var middle := ((low + high) + Vector2i.ONE) / 2
	return Vector2(float(middle.x) + 0.5, float(middle.y) + 0.5)


func _begin() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(),
		"i": PackedInt32Array()}


func _finish(builder: Dictionary) -> ArrayMesh:
	var vertices: PackedVector3Array = builder["v"]
	if vertices.is_empty():
		return null
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = builder["n"]
	arrays[Mesh.ARRAY_COLOR] = builder["c"]
	arrays[Mesh.ARRAY_INDEX] = builder["i"]
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## One tile's quad, standing on the ground it covers.  The height is the terrain's
## own, so the band follows the valley up a hill instead of floating over it.
func _append_tile(builder: Dictionary, tile: Vector2i, colour: Color, lift: float,
		inset: float) -> void:
	var height := session.world.elevation_at(tile) + lift
	var x0 := float(tile.x) + inset
	var x1 := float(tile.x + 1) - inset
	var z0 := float(tile.y) + inset
	var z1 := float(tile.y + 1) - inset
	_append_quad(builder, [
		Vector3(x0, height, z0), Vector3(x1, height, z0),
		Vector3(x1, height, z1), Vector3(x0, height, z1)], colour)


## The ribbon from the yard to a covered place, each end resting on its own
## ground.  A flat ribbon across a hill would sink into it on one end.
func _append_ribbon(builder: Dictionary, from: Vector2, tile: Vector2i, colour: Color) -> void:
	var to := Vector2(float(tile.x) + 0.5, float(tile.y) + 0.5)
	if from.distance_squared_to(to) < 0.0001:
		return
	var here := session.world.elevation_at(Vector2i(int(from.x), int(from.y))) + LIFT_COVERAGE
	var there := session.world.elevation_at(tile) + LIFT_COVERAGE
	var direction := (to - from).normalized()
	var side := direction.orthogonal() * (LINK_WIDTH * 0.5)
	_append_quad(builder, [
		Vector3(from.x - side.x, here, from.y - side.y),
		Vector3(from.x + side.x, here, from.y + side.y),
		Vector3(to.x + side.x, there, to.y + side.y),
		Vector3(to.x - side.x, there, to.y - side.y)], colour)


func _append_quad(builder: Dictionary, corners: Array, colour: Color) -> void:
	var vertices: PackedVector3Array = builder["v"]
	var normals: PackedVector3Array = builder["n"]
	var colours: PackedColorArray = builder["c"]
	var indices: PackedInt32Array = builder["i"]
	var start := vertices.size()
	for corner in corners:
		vertices.append(Vector3(corner))
		normals.append(Vector3.UP)
		colours.append(colour)
	indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2,
		start + 3]))


func _overlay_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = "construction_ghost"
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color.WHITE
	return material
