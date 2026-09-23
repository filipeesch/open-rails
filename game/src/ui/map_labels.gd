class_name MapLabels
extends Control

## The map's only screen-space label layer, and the only place a place name is
## ever drawn as text.
##
## Spec §72 asks for zoom-dependent labels: far out the valley names its towns
## and its major works; at medium zoom the yards join them; close in the names
## withdraw unless the entity is selected, "so close views do not become covered
## by text".  The requirement that shapes this class is not the wording but the
## word *pooled*: a 256×256 valley with a hundred yards cannot afford a `Label`
## node per place, because the whole rendering budget in §112 is about not
## creating a node per thing.  So the pool is created once, at `POOL_SIZE`, and a
## scan only ever re-points and re-visibility-fits those nodes.  The node count
## of this control is a constant for the life of the session, and a test asserts
## exactly that.
##
## The layer projects through the camera rig rather than owning a camera, and it
## reads the world through the domain services.  It writes to nothing.

## How many labels exist, ever.  Anything past this is the next scan's problem,
## which is the honest trade for a fixed node budget.
const POOL_SIZE := 32
## §72's bands, in the rig's own unit: tiles of ground spanning the view.
## Far enough out that a place is a dot rather than a shape.
const TILES_FAR := 60.0
## Far enough out that naming the yards helps instead of cluttering.
const TILES_MEDIUM := 12.0
## Labels sit above the place they name, so the text never covers the model.
const LEADING := Vector2(0.0, -18.0)
## How far inside the window a place has to project before it earns a name.  A
## name half over the edge of the screen is unreadable, and one that lands on the
## top bar or the tool bar puts two layers claiming the same pixels.  The vertical
## figures carry `HEIGHT_ABOVE` too, because the text stands above the point it
## names rather than centred on it.
const HEIGHT_ABOVE := 44.0
const INSIDE_SIDE := 8.0
const INSIDE_TOP := float(GameTheme.CHROME_BAND) + HEIGHT_ABOVE
const INSIDE_BOTTOM := float(GameTheme.CHROME_BAND)

const TIER_CLOSE := 0
const TIER_MEDIUM := 1
const TIER_FAR := 2

signal labels_changed(shown: Array[Dictionary])

var session: GameSession
var rig: IsoCameraRig
var selection: SelectionService
## Orphans have no viewport, so the projection is stated.  A live viewport
## overrides it — the shipped path and the tested path are the same path.
var viewport_size := Vector2(1280.0, 720.0)

var _pool: Array[Label] = []
var _shown: Array[Dictionary] = []
var _dirty := true


## Wire the layer to a running session and its camera, and build the pool.
func attach(game_session: GameSession, camera_rig: IsoCameraRig) -> void:
	session = game_session
	rig = camera_rig
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_pool()
	rig.view_changed.connect(func(_size: float, _yaw: float) -> void: _dirty = true)
	session.stations.station_created.connect(func(_id: int) -> void: _dirty = true)
	session.stations.station_removed.connect(func(_id: int) -> void: _dirty = true)
	session.stations.station_renamed.connect(func(_id: int, _name: String) -> void: _dirty = true)
	session.stations.station_inventory_changed.connect(func(_id: int) -> void: _dirty = true)
	session.towns.town_added.connect(func(_id: int) -> void: _dirty = true)
	# A `selection` field set before this call is honoured; one handed over later
	# arrives through `attach_selection`.  Either way it is wired exactly once.
	if selection != null:
		wire_selection(selection)


## The selection is what lets a label survive a close view, so the layer needs
## to be told about it.  Optional: without it the zoom bands alone apply.  Safe
## to call twice — the wiring is one connection, not one per call.
func attach_selection(service: SelectionService) -> void:
	wire_selection(service)


func wire_selection(service: SelectionService) -> void:
	if service == null:
		return
	selection = service
	if not selection.selection_changed.is_connected(_on_selection):
		selection.selection_changed.connect(_on_selection)
	_dirty = true


func _build_pool() -> void:
	for index in POOL_SIZE:
		var label := Label.new()
		label.name = "Label%d" % index
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", GameTheme.FONT_BODY)
		label.add_theme_color_override("font_color", GameTheme.TEXT)
		label.add_theme_color_override("font_outline_color", GameTheme.BACKGROUND)
		label.add_theme_constant_override("outline_size", 4)
		label.visible = false
		add_child(label)
		_pool.append(label)


func _on_selection(kind: String, _entity_id: int, _tile: Vector2i) -> void:
	# The selected entity keeps its name at any zoom, so a selection changes what
	# the scan would otherwise choose.
	_dirty = true


## Recompute the visible set.  Cheap enough to call on a signal and on a month,
## and only actually scanned when something moved the view or the world.
func refresh() -> void:
	if not _dirty:
		return
	_scan()


## Force a scan even if nothing reported a change.
func refresh_now() -> void:
	_scan()


func _scan() -> void:
	_dirty = false
	_shown.clear()
	if session == null or rig == null:
		_all_hide()
		return
	var tier := tier()
	var candidates := _candidates(tier)
	var slot := 0
	for entry in candidates:
		if slot >= POOL_SIZE:
			break
		var tile: Vector2i = entry["tile"]
		var screen := rig.world_to_screen(
				rig.tile_to_world(Vector2(tile.x + 0.5, tile.y + 0.5)), _rect())
		if not _on_screen(screen):
			continue
		entry["screen"] = screen
		_shown.append(entry)
		slot += 1
	_paint()
	labels_changed.emit(_shown)


## The band the camera is in, from §72's three rows.
func tier() -> int:
	if rig == null:
		return TIER_CLOSE
	var tiles := rig.orthographic_tiles()
	if tiles >= TILES_FAR:
		return TIER_FAR
	if tiles >= TILES_MEDIUM:
		return TIER_MEDIUM
	return TIER_CLOSE


## Every named place the band allows, in the order the pool should spend itself:
## the selection first, then towns, yards and works.  Entity ids break ties, so
## two runs with the same view fill the pool with the same names.
func _candidates(tier_level: int) -> Array[Dictionary]:
	# Close in, a name would cover the thing it names.  §72 lets exactly one
	# exception through: whatever the player asked for.
	if tier_level == TIER_CLOSE:
		return _selected_entry_only()
	var out: Array[Dictionary] = []
	for town_id in session.towns.towns():
		out.append(_entry(SelectionService.KIND_TOWN, town_id,
				session.towns.name_of(town_id), session.towns.tile_of(town_id), 1))
	if tier_level != TIER_FAR:
		for station_id in session.stations.stations():
			out.append(_entry(SelectionService.KIND_STATION, station_id,
					session.stations.name_of(station_id),
					session.stations.tile_of(station_id), 2))
	for industry_id in session.industries.industries():
		if tier_level == TIER_FAR and not is_major_industry(industry_id):
			continue
		out.append(_entry(SelectionService.KIND_INDUSTRY, industry_id,
				session.industries.name_of(industry_id),
				session.industries.tile_of(industry_id), 3))
	out.sort_custom(_by_priority)
	if selection != null and selection.has_selection():
		# Selected first: it is the one name the player asked for.
		for index in out.size():
			if int(out[index]["id"]) == selection.selected_id \
					and String(out[index]["kind"]) == selection.selected_kind:
				out.push_front(out[index])
				out.remove_at(index + 1)
				break
	return out


## The selected place, and only it, at a zoom where nothing else is named.  A
## selection that is not a named place — a length of track, bare ground, a train
## in motion — names nothing: the inspector is where those are read.
func _selected_entry_only() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if selection == null or not selection.has_selection():
		return out
	var kind := selection.selected_kind
	var entity_id := selection.selected_id
	if kind == SelectionService.KIND_TOWN:
		out.append(_entry(kind, entity_id, session.towns.name_of(entity_id),
				session.towns.tile_of(entity_id), 0))
	elif kind == SelectionService.KIND_STATION:
		out.append(_entry(kind, entity_id, session.stations.name_of(entity_id),
				session.stations.tile_of(entity_id), 0))
	elif kind == SelectionService.KIND_INDUSTRY:
		out.append(_entry(kind, entity_id, session.industries.name_of(entity_id),
				session.industries.tile_of(entity_id), 0))
	return out


func _entry(kind: String, entity_id: int, place_name: String, tile: Vector2i,
		priority: int) -> Dictionary:
	return {
		"kind": kind,
		"id": entity_id,
		"text": place_name,
		"detail": PlaceSummary.line_for(session, kind, entity_id),
		"tile": tile,
		"priority": priority,
	}


func _by_priority(a: Dictionary, b: Dictionary) -> bool:
	if int(a["priority"]) != int(b["priority"]):
		return int(a["priority"]) < int(b["priority"])
	return int(a["id"]) < int(b["id"])


## Whether a works is worth naming from far out.  V1's works are all valley
## scale — a mine and a plant, both of them the reason a line exists — so every
## industry qualifies today; the rule is written as a question about the
## definition so a hedgerow-scale industry could decline the honour later.
func is_major_industry(industry_id: int) -> bool:
	var definition := session.industries.def_of(industry_id)
	if definition == null:
		return false
	return definition.produces.size() + definition.accepts.size() > 0


func _paint() -> void:
	for index in _pool.size():
		var label := _pool[index]
		if index >= _shown.size():
			label.visible = false
			continue
		var entry := _shown[index]
		var detail := String(entry["detail"])
		label.text = String(entry["text"]) if detail == "" \
				else "%s\n%s" % [entry["text"], detail]
		label.position = (entry["screen"] as Vector2) + LEADING \
				- Vector2(label.get_minimum_size().x * 0.5, 0.0)
		label.visible = true


func _all_hide() -> void:
	for label in _pool:
		label.visible = false


func _on_screen(screen: Vector2) -> bool:
	if not is_finite(screen.x) or not is_finite(screen.y):
		# The rig's way of saying the point is behind the camera.  There is no
		# pixel to put a name at, and an unnamed stretch of valley reads better
		# than a name pinned to ground it is not on.
		return false
	return screen.x >= INSIDE_SIDE and screen.x <= viewport_size.x - INSIDE_SIDE \
			and screen.y >= INSIDE_TOP and screen.y <= viewport_size.y - INSIDE_BOTTOM


## The rectangle pixels are measured in: the live viewport when there is one, the
## authored size otherwise.  Same convention the entity label layer uses, so a
## headless host and a window project a name to the same pixel.
func _rect() -> Rect2:
	if is_inside_tree() and get_viewport() != null:
		var live := get_viewport().get_visible_rect()
		if live.size.x > 0.0 and live.size.y > 0.0:
			viewport_size = live.size
	return Rect2(Vector2.ZERO, viewport_size)


# --- what a test asks the layer about ---------------------------------------

## The labels currently shown, with their kind, id, text and screen position.
func visible_labels() -> Array[Dictionary]:
	return _shown.duplicate(true)


## The pool's size — a constant, and the point of the whole class.
func pool_size() -> int:
	return _pool.size()


func shown_count() -> int:
	return _shown.size()


## Whether a given entity is named on the map right now.
func is_showing(entity_id: int) -> bool:
	for entry in _shown:
		if int(entry["id"]) == entity_id:
			return true
	return false


func text_of(entity_id: int) -> String:
	for entry in _shown:
		if int(entry["id"]) == entity_id:
			return String(entry["text"])
	return ""


## How many live `Label` nodes this control owns.  It must never exceed the pool.
func label_nodes() -> int:
	var count := 0
	for child in get_children():
		if child is Label:
			count += 1
	return count
