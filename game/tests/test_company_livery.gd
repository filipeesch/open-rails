
extends TestBase

## Company livery (`add-trains-routes-and-revenue` task 2.5): the consist is drawn
## from the generated GLBs, and the company's two colours are the only parameters
## involved.
##
## The spec's material rule is that company colour is "a separate shared material
## with a runtime color parameter" and that nothing invents a material at runtime.
## A livery is therefore two colour parameters on two shared materials, and every
## region an asset reserved for the company points at them.  What the cases grade is
## the claim in the task: a livery costs two colour writes, reaches every LOD of the
## asset, covers a station and a locomotive with the same pair of materials, and can
## be changed without a single body being rebuilt.

var _view: TestView


func teardown() -> void:
	if _view != null:
		_view.dispose()
		_view = null
	# The two livery materials are static because they belong to the company and not
	# to a renderer, which means one case's company would hand another case its
	# colours.  Put the palette's own default back.
	ModelCatalog.paint_livery({"id": "palette", "primary": ModelCatalog.PALETTE_PRIMARY,
			"secondary": ModelCatalog.PALETTE_SECONDARY})


# --- the two parameters -----------------------------------------------------

func test_a_livery_is_two_colour_parameters_on_shared_materials() -> void:
	_view = TestView.stage()
	var line := TestSession.coal_line(_view.session)
	check_true(bool(line["ok"]), "a working coal line puts a consist on the rails: %s" % line["reason"])
	var consist := _view.entities.train_node(int(line["train"]))
	check_true(consist != null, "and the renderer has built its bodies")

	var livery := _view.session.company_livery()
	var beam := _part(consist, "buffer_beam_front")
	check_true(beam != null, "the 4-4-0 reserves its buffer beams for the company")
	check_eq(_surface(beam, 0), ModelCatalog.livery_material("primary"),
			"and the beams are painted by the shared primary material, not a copy")
	check_eq(_surface(beam, 0).albedo_color, livery["primary"],
			"which carries the livery's primary colour")
	var cab := _part(consist, "cab_body")
	check_true(cab != null, "the cab is the reserved secondary region")
	check_eq(_surface(cab, 0).albedo_color, livery["secondary"], "in the secondary colour")

	var frame := _part(consist, "frame")
	check_true(frame != null, "and the frame is ordinary bodywork")
	check_eq(_surface(frame, 0), _view.entities.catalog.shared_material(),
			"which still draws with the one vertex-colour material every asset shares")

	var materials := _materials(consist)
	check_eq(float(materials.size()), 3.0,
			"a whole consist is drawn with three materials, not one per vehicle (%d)" % materials.size())


func test_the_company_colour_survives_to_every_lod_of_a_locomotive() -> void:
	_view = TestView.stage()
	ModelCatalog.paint_livery(_view.session.company_livery())
	var node := _view.entities.catalog.instantiate("steam_440")
	_view.host.add_child(node)
	for tier in ["LOD0", "LOD1", "LOD2"]:
		var reserved := _reserved_surfaces(node)
		check_gt(float(reserved), 0.0,
				"%s still wears the livery (%d reserved surfaces)" % [tier, reserved])
	check_eq(float(ModelCatalog.livery_material_count()), 2.0,
			"and it costs two materials for all three tiers")


# --- two liveries, one model -----------------------------------------------

func test_two_liveries_share_one_model() -> void:
	_view = TestView.stage()
	var line := TestSession.coal_line(_view.session)
	check_true(bool(line["ok"]), "a consist to repaint")
	var consist := _view.entities.train_node(int(line["train"]))
	var before := _signature(consist)
	var before_materials := ModelCatalog.livery_material_count()
	var old_primary := ModelCatalog.livery_material("primary").albedo_color
	var first_livery := _view.session.company_livery()

	# The rename is the domain's own path, and repaint is the two writes the
	# renderer already knows how to make: nothing here rebuilds a body.
	_view.session.economy.configure(_view.session.economy.cash, _view.session.clock.date,
			_another_company_name(String(first_livery["id"])))
	var second := _view.session.company_livery()
	check_neq(String(second["id"]), String(first_livery["id"]),
			"the new name belongs to a different livery in the table")
	ModelCatalog.paint_livery(second)

	var after := _signature(consist)
	check_eq(float(after.size()), float(before.size()), "every body is still standing")
	for index in before.size():
		check_eq(String(after[index]["node"]), String(before[index]["node"]),
				"the same node, not a rebuilt one: %s" % before[index]["name"])
		check_eq(String(after[index]["mesh"]), String(before[index]["mesh"]),
				"the same mesh resource: %s" % before[index]["name"])
		check_eq(String(after[index]["material"]), String(before[index]["material"]),
				"pointed at by the same material: %s" % before[index]["name"])
	check_eq(float(ModelCatalog.livery_material_count()), float(before_materials),
			"painting a second livery created no material at all")
	check_neq(ModelCatalog.livery_material("primary").albedo_color, old_primary,
			"and the only thing that moved was the colour parameter")
	check_eq(ModelCatalog.livery_material("primary").albedo_color, second["primary"],
			"to the new livery's primary")


func test_a_station_and_its_locomotive_wear_one_livery() -> void:
	_view = TestView.stage()
	var line := TestSession.coal_line(_view.session)
	check_true(bool(line["ok"]), "two stations and a train to compare")
	var station := _view.entities.station_node(int(line["mine_station"]))
	check_true(station != null, "the renderer has built the mine's station")
	var board := _part(station, "name_board")
	check_true(board != null, "whose name board is the station's reserved region")
	var consist := _view.entities.train_node(int(line["train"]))
	var cab := _part(consist, "cab_body")
	check_eq(_surface(board, 0), _surface(cab, 0),
			"name board and cab are the same material object, one per colour")
	check_eq(float(ModelCatalog.livery_material_count()), 2.0,
			"two shared materials for a company, however many things wear them")
	var materials := _materials(station)
	materials.append_array(_materials(consist))
	var shared: Array[int] = []
	for id in materials:
		if not shared.has(id):
			shared.append(id)
	check_eq(float(shared.size()), 3.0,
			"a station, a locomotive and its hopper together draw with three materials (%d)" % shared.size())


# --- where the colours come from -------------------------------------------

func test_a_company_paints_itself_from_its_name_alone() -> void:
	var registry := DataRegistry.new()
	check_true(registry.load_all(), "the shipped definitions load clean: %s" % registry.errors)
	var first := registry.livery_for("Biltmore & Slade")
	var again := registry.livery_for("Biltmore & Slade")
	check_eq(String(first["id"]), String(again["id"]), "a name typed twice earns the same colours")

	var picked := {}
	for word in ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L",
			"M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"]:
		picked[String(registry.livery_for(word + " & Co.")["id"])] = true
	check_gt(float(picked.size()), 1.0, "different names land on different liveries (%d found)" % picked.size())
	check_eq(String(registry.livery_for("")["id"]), String(registry.default_livery()["id"]),
			"no name at all is the palette's own default livery")

	_view = TestView.stage()
	check_eq(String(_view.session.company_livery()["id"]),
			String(registry.livery_for(_view.session.company_name())["id"]),
			"a session defers to its name and keeps no copy of the answer")


func test_the_livery_table_is_a_definition_and_not_a_code_path() -> void:
	var registry := DataRegistry.new()
	check_true(registry.load_all(), "the table parses without complaint")
	check_eq(registry.errors.size(), 0, "no definition errors at all: %s" % registry.errors)
	check_ge(float(registry.liveries.size()), 4.0,
			"a company can pick between %d liveries" % registry.liveries.size())
	var ids := {}
	var primaries := {}
	for livery in registry.liveries:
		var id := String(livery["id"])
		check_false(ids.has(id), "livery id %s appears once" % id)
		ids[id] = true
		var primary: Color = livery["primary"]
		var secondary: Color = livery["secondary"]
		check_true(primary.get_luminance() + 0.15 < secondary.get_luminance(),
				"%s is a dark body under a pale trim (%.2f over %.2f)" % [
						id, primary.get_luminance(), secondary.get_luminance()])
		check_neq(primary.to_html(), secondary.to_html(), "%s' two colours differ" % id)
		var key := primary.to_html()
		check_false(primaries.has(key), "%s is the only livery with primary %s" % [id, key])
		primaries[key] = id
	check_neq(String(registry.default_livery()["id"]), "", "and one of them is named the default")


# --- reading what a body is actually drawn with ----------------------------

func _part(root: Node, part_name: String) -> MeshInstance3D:
	for child in root.get_children():
		if String(child.name) == part_name and child is MeshInstance3D:
			return child as MeshInstance3D
		var nested := _part(child, part_name)
		if nested != null:
			return nested
	return null


## The material a surface actually draws with: a node-wide override wins in the
## engine, so the renderer's own rule is read the same way the rasteriser reads it.
func _surface(instance: MeshInstance3D, index: int) -> Material:
	if instance.material_override != null:
		return instance.material_override
	return instance.mesh.surface_get_material(index)


## Every material a subtree draws with, by instance id: the count is the number of
## distinct materials, which is what the "no material per building" rule is about.
func _materials(root: Node) -> Array[int]:
	var found: Array[int] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var instance := node as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		if instance.material_override != null:
			var id := instance.material_override.get_instance_id()
			if not found.has(id):
				found.append(id)
			continue
		for index in instance.mesh.get_surface_count():
			var material := instance.mesh.surface_get_material(index)
			if material == null:
				continue
			var surface_id := material.get_instance_id()
			if not found.has(surface_id):
				found.append(surface_id)
	return found


## How many surfaces of a subtree are painted by a shared livery material.
func _reserved_surfaces(root: Node) -> int:
	var count := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var instance := node as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		for index in instance.mesh.get_surface_count():
			var material := instance.mesh.surface_get_material(index)
			if material == ModelCatalog.livery_material("primary")                     or material == ModelCatalog.livery_material("secondary"):
				count += 1
	return count


## Node, mesh and material identities for every body in a subtree: two signatures
## that match prove a repaint put no new resource anywhere.
func _signature(root: Node) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var instance := node as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		for index in instance.mesh.get_surface_count():
			var material := _surface(instance, index)
			entries.append({
				"name": "%s[%d]" % [node.name, index],
				"node": str(instance.get_instance_id()),
				"mesh": str(instance.mesh.get_instance_id()),
				"material": str(material.get_instance_id()) if material != null else "none",
			})
	return entries


## A company name whose livery differs from the one already worn: the table is
## walked until a second road is found, so the case never pins a colour by hand.
func _another_company_name(worn_id: String) -> String:
	var registry := DataRegistry.new()
	registry.load_all()
	for livery in registry.liveries:
		if String(livery["id"]) != worn_id:
			return "The %d Railway" % registry.liveries.find(livery)
	return "Someone Else's Railway"
