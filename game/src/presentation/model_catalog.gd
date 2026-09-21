class_name ModelCatalog
extends RefCounted

## Loads runtime GLBs from `game/generated/`, falling back to a primitive
## placeholder when an asset has not been built yet.
##
## The fallback is not a stub for lazy authoring: it keeps the game playable and
## measurable before the Blender pass has run, and it makes a missing asset
## obvious in-world rather than invisible.

const MODEL_ROOT := "res://generated/models"
const MANIFEST_ROOT := "res://generated/manifests"

var _cache := {}
var _missing: PackedStringArray = PackedStringArray()
var _from_file := 0
var _from_placeholder := 0


func model(asset_id: String) -> ModelResource:
	if _cache.has(asset_id):
		return _cache[asset_id]
	var model := _load(asset_id)
	_cache[asset_id] = model
	return model


func has_asset(asset_id: String) -> bool:
	return model(asset_id).authored


func missing() -> PackedStringArray:
	return _missing


func authored_count() -> int:
	return _from_file


func placeholder_count() -> int:
	return _from_placeholder


func manifest(asset_id: String) -> Dictionary:
	var path := MANIFEST_ROOT.path_join(asset_id + ".json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _load(asset_id: String) -> ModelResource:
	var path := MODEL_ROOT.path_join(asset_id + ".glb")
	if ResourceLoader.exists(path):
		var packed: PackedScene = load(path)
		if packed != null:
			_from_file += 1
			var authored := ModelResource.new()
			authored.scene = packed
			authored.authored = true
			apply_shared_material(authored)
			return authored
	_missing.append(asset_id)
	_from_placeholder += 1
	var placeholder := ModelResource.new()
	placeholder.scene = _placeholder_scene(asset_id)
	placeholder.authored = false
	return placeholder


## Every asset shares one vertex-colour material: colour comes from the mesh, so
## a hundred station types cost one material.  The override is baked into the
## packed scene — setting it on a throwaway instance would be discarded, and the
## next `instantiate()` would hand back the asset's own imported materials.
func apply_shared_material(model: ModelResource) -> void:
	var material := shared_material()
	var root := model.scene.instantiate()
	_walk(root, material)
	var rebaked := PackedScene.new()
	var error := rebaked.pack(root)
	root.free()
	if error == OK:
		model.scene = rebaked


var _shared: StandardMaterial3D = null


func shared_material() -> StandardMaterial3D:
	if _shared == null:
		_shared = StandardMaterial3D.new()
		_shared.vertex_color_use_as_albedo = true
		_shared.roughness = 0.85
		_shared.metallic = 0.0
	return _shared


func company_material(primary: Color, secondary: Color) -> StandardMaterial3D:
	## The company livery is one parameterised material; a train overrides it
	## rather than owning a material instance per consist.
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = primary
	material.roughness = 0.6
	material.metallic = 0.15
	return material


func instantiate(asset_id: String, scale: float = 1.0) -> Node3D:
	var model := model(asset_id)
	var instance := model.scene.instantiate()
	var root := instance as Node3D
	if root != null and absf(scale - 1.0) > 0.0001:
		root.scale = Vector3.ONE * scale
	return root


func _walk(node: Node, material: Material) -> void:
	for child in node.get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.material_override = material
		_walk(child, material)


class ModelResource extends Resource:
	var scene: PackedScene
	var authored: bool = false


# --- placeholders ---------------------------------------------------------

const PLACEHOLDER_SHAPE := {
	"small_station": {"size": Vector3(2.6, 0.9, 1.6), "roof": "gable", "colour": Color(0.61, 0.29, 0.23)},
	"coal_mine": {"size": Vector3(2.4, 1.1, 2.4), "roof": "flat", "colour": Color(0.42, 0.42, 0.45)},
	"power_plant": {"size": Vector3(3.2, 1.4, 2.2), "roof": "flat", "colour": Color(0.48, 0.47, 0.50)},
	"town_house": {"size": Vector3(0.8, 0.7, 0.8), "roof": "gable", "colour": Color(0.68, 0.55, 0.40)},
	"steam_440": {"size": Vector3(0.4, 0.34, 0.95), "roof": "flat", "colour": Color(0.24, 0.25, 0.28)},
	"passenger_coach": {"size": Vector3(0.42, 0.32, 0.7), "roof": "flat", "colour": Color(0.60, 0.27, 0.17)},
	"mail_car": {"size": Vector3(0.42, 0.32, 0.7), "roof": "flat", "colour": Color(0.30, 0.42, 0.56)},
	"coal_hopper": {"size": Vector3(0.42, 0.34, 0.66), "roof": "flat", "colour": Color(0.30, 0.30, 0.33)},
}


func _placeholder_scene(asset_id: String) -> PackedScene:
	var shape: Dictionary = PLACEHOLDER_SHAPE.get(asset_id,
		{"size": Vector3(0.8, 0.8, 0.8), "roof": "flat", "colour": Color(0.55, 0.55, 0.55)})
	var root := Node3D.new()
	root.name = asset_id
	var block := BoxMesh.new()
	block.size = shape["size"]
	var instance := MeshInstance3D.new()
	instance.name = "Body"
	instance.mesh = block
	instance.position = Vector3(0, shape["size"].y * 0.5, 0)
	instance.material_override = _tinted_material(shape["colour"])
	root.add_child(instance)
	# `PackedScene.pack()` stores the root and every node owned by it — and only
	# those.  Without an owner the children are dropped and the placeholder
	# instantiates as an invisible empty node, which is the one thing a missing
	# asset must never be.
	instance.owner = root
	if String(shape["roof"]) == "gable":
		var prism := PrismMesh.new()
		prism.size = Vector3(shape["size"].x, shape["size"].y * 0.45, shape["size"].z)
		var roof := MeshInstance3D.new()
		roof.name = "Roof"
		roof.mesh = prism
		roof.position = Vector3(0, shape["size"].y + prism.size.y * 0.22, 0)
		roof.rotation_degrees = Vector3(0, 90, 0)
		roof.material_override = _tinted_material(Color(0.29, 0.29, 0.32))
		root.add_child(roof)
		roof.owner = root
	var packed := PackedScene.new()
	var error := packed.pack(root)
	if error != OK:
		push_error("could not pack the placeholder for '%s': %d" % [asset_id, error])
	root.free()
	return packed


## The `Mesh` behind an asset id — what a `MultiMesh` instances, since an
## instanced layer takes a mesh rather than a scene.  An authored asset gives up
## its first surface; an unbuilt one gives up its placeholder block, so instanced
## scenery exists and is measurable before the Blender pass has run.
var _meshes := {}


func mesh_for(asset_id: String) -> Mesh:
	if _meshes.has(asset_id):
		var cached: Mesh = _meshes[asset_id]
		return cached
	var model := model(asset_id)
	var probe := model.scene.instantiate()
	var mesh := _first_mesh(probe)
	probe.free()
	if mesh == null:
		var block := BoxMesh.new()
		block.size = Vector3(0.8, 0.8, 0.8)
		mesh = block
	_meshes[asset_id] = mesh
	return mesh


func _first_mesh(node: Node) -> Mesh:
	for child in node.get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance != null and mesh_instance.mesh != null:
			return mesh_instance.mesh
		var nested := _first_mesh(child)
		if nested != null:
			return nested
	return null


## Placeholder tints are cached per colour: a town of twenty houses still draws
## with one material, because materials follow colour and never instance count.
var _tints := {}


func _tinted_material(colour: Color) -> StandardMaterial3D:
	var key := colour.to_html()
	if _tints.has(key):
		var cached: StandardMaterial3D = _tints[key]
		return cached
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.85
	_tints[key] = material
	return material
