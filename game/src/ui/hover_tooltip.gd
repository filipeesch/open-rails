class_name HoverTooltip
extends PanelContainer

## The pointer's one-line answer, and the reason the inspector can stay closed.
##
## Spec §71: hover provides *lightweight* information — the name of the thing and
## the one number that matters — and it "should not replace selection for
## detailed information".  That sentence is the whole design.  This panel reads
## the hover state the selection resolver already computes and never calls
## `select()`, so the act of asking a question cannot change the answer to the
## next one: the player's selection, the inspector, the camera and the follow
## target all stay exactly where they were while the tooltip is up.  A tooltip
## that selected would make every sweep of the mouse a change of context.
##
## It is one panel with two labels, re-pointed at whatever is under the pointer —
## not one panel per entity type, and nothing per tile.

## The tip sits ahead of and below the cursor, clear of the icon and of the thing
## it is describing.
const OFFSET := Vector2(16.0, 20.0)
## ...unless that would push it off screen, in which case it flips to the other
## side of the cursor rather than clipping.
const EDGE_MARGIN := 8.0

var session: GameSession
var selection: SelectionService
## Orphans have no viewport; the clamp needs one stated.  A live viewport wins.
var viewport_size := Vector2(1280.0, 720.0)

var title_label: Label
var detail_label: Label
var _kind: String = SelectionService.KIND_NONE
var _entity_id := 0
var _cursor := Vector2.ZERO


## Wire the tip to a session and to the selection resolver's hover channel.
func attach(game_session: GameSession, service: SelectionService) -> void:
	session = game_session
	selection = service
	_build_shell()
	selection.tile_hovered.connect(func(_tile: Vector2i) -> void: refresh())
	selection.tile_unhovered.connect(func() -> void: hide_tip())
	selection.hover_cargo.connect(func(_id: int, _summary: Array[Dictionary]) -> void: refresh())
	visible = false


func _build_shell() -> void:
	theme = GameTheme.build()
	add_theme_stylebox_override("panel", GameTheme.panel(GameTheme.PANEL))
	custom_minimum_size = Vector2(150, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	add_child(column)

	title_label = GameTheme.body("", GameTheme.TEXT)
	title_label.add_theme_font_size_override("font_size", GameTheme.FONT_STRONG)
	column.add_child(title_label)

	detail_label = GameTheme.body("", GameTheme.TEXT_DIM)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.custom_minimum_size = Vector2(140, 0)
	column.add_child(detail_label)


## Re-read the hover state.  Called by the hover signals and by anything that
## changes what a hovered entity holds.
func refresh() -> void:
	if selection == null or session == null:
		return
	set_hover(selection.hovered_kind, selection.hovered_id)


## Show the tip for one entity, or hide it for `KIND_NONE`.  Public because the
## hover channel is not the only honest way to be told what is under a pointer.
func set_hover(kind: String, entity_id: int) -> void:
	if kind == SelectionService.KIND_NONE or entity_id == 0 or not _has_details(kind):
		hide_tip()
		return
	_kind = kind
	_entity_id = entity_id
	title_label.text = name_of(kind, entity_id)
	detail_label.text = PlaceSummary.line_for(session, kind, entity_id)
	visible = true


func hide_tip() -> void:
	_kind = SelectionService.KIND_NONE
	_entity_id = 0
	title_label.text = ""
	detail_label.text = ""
	visible = false


## Move the tip to a cursor position in viewport pixels, kept on screen.
func move_to(cursor: Vector2) -> void:
	_cursor = cursor
	if not visible:
		return
	var wanted := cursor + OFFSET
	var size := get_minimum_size()
	var rect := _rect()
	if wanted.x + size.x > rect.size.x - EDGE_MARGIN:
		wanted.x = cursor.x - OFFSET.x - size.x
	if wanted.y + size.y > rect.size.y - EDGE_MARGIN:
		wanted.y = cursor.y - OFFSET.y - size.y
	position = Vector2(maxf(EDGE_MARGIN, wanted.x), maxf(EDGE_MARGIN, wanted.y))


## The shipped path: follow the real pointer while the tip is up.  An orphan has
## no viewport, so this stays quiet — the position is then whatever `move_to`
## last said, which is exactly how a test drives it.
func _process(_delta: float) -> void:
	if not visible or not is_inside_tree():
		return
	move_to(get_viewport().get_mouse_position())


# --- what the tip says -----------------------------------------------------

## Only the four things a player can point at have a lightweight answer.  Bare
## ground and a lone piece of track deliberately say nothing: there is no number
## worth interrupting a view for.
func _has_details(kind: String) -> bool:
	return kind == SelectionService.KIND_STATION \
			or kind == SelectionService.KIND_TOWN \
			or kind == SelectionService.KIND_INDUSTRY \
			or kind == SelectionService.KIND_TRAIN


func name_of(kind: String, entity_id: int) -> String:
	match kind:
		SelectionService.KIND_STATION:
			return session.stations.name_of(entity_id)
		SelectionService.KIND_TOWN:
			return session.towns.name_of(entity_id)
		SelectionService.KIND_INDUSTRY:
			return session.industries.name_of(entity_id)
		SelectionService.KIND_TRAIN:
			return session.trains.name_of(entity_id)
	return ""


## The line a player would read, as one string — what a test asserts instead of
## reaching into the labels.
func text() -> String:
	var detail := detail_label.text
	if title_label.text == "":
		return ""
	return title_label.text if detail == "" else "%s\n%s" % [title_label.text, detail]


func is_showing() -> bool:
	return visible and _entity_id != 0


func showing_id() -> int:
	return _entity_id


func showing_kind() -> String:
	return _kind


func _rect() -> Rect2:
	if is_inside_tree() and get_viewport() != null:
		return Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	return Rect2(Vector2.ZERO, viewport_size)
