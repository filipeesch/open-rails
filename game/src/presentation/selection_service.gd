class_name SelectionService
extends Node

## Where the pointer is, and what it is pointing at.
##
## Selection is a ray march over the terrain heightfield followed by an
## occupancy lookup — no physics bodies, no picking colliders, nothing to keep
## in sync with the world.

signal tile_hovered(tile: Vector2i)
signal tile_unhovered()
signal selection_changed(kind: String, entity_id: int, tile: Vector2i)
signal hover_cargo(station_id: int, summary: Array[Dictionary])

const KIND_NONE := "none"
const KIND_RAIL := "rail"
const KIND_STATION := "station"
const KIND_INDUSTRY := "industry"
const KIND_TOWN := "town"
const KIND_TRAIN := "train"
const KIND_TERRAIN := "terrain"

const RAY_STEP := 0.5
const RAY_LENGTH := 460.0
## How many parts a flagged march step is cut into to find where the ray actually
## went under ground: at this pitch a step can fall entirely outside the touch.
const CONTACT_SUBSTEPS := 64
## The contact search then bisects its span to a thousandth of a tile, which is
## where the bisection stops and where the settle below is measured from.
const REFINE_LIMIT := 24
const REFINE_ACCURACY := 0.001
## How far into the surface the finished hit is settled, in world units: twice the
## convergence tolerance, so an answer is never balanced on a seam.
const REFINE_SETTLE := 0.002
## Tile-space radius for a train hit when resolving from a tile (a tool commit,
## a palette jump).
const TRAIN_PICK_RADIUS := 1.4
## Screen-space pick radius as a fraction of viewport height, so a train is the
## same size target to click at 96 tiles as at 4.
const TRAIN_PICK_SCREEN := 0.026
## How far below the map floor a ray may travel before it is given up on.
const FLOOR_Y := -4.0

var session: GameSession
var camera_rig: IsoCameraRig

## Viewport to assume when this node is not inside a scene tree.  The live
## viewport always wins; an explicit size lets a headless host drive the same
## pick path the player uses instead of a second, test-only one.
var viewport_size := Vector2.ZERO

var hovered_tile := Vector2i(-1, -1)
var hovered_kind := KIND_NONE
var hovered_id := 0
var selected_kind := KIND_NONE
var selected_id := 0
var selected_tile := Vector2i(-1, -1)

var _hover_cargo_station := 0


func attach(game_session: GameSession, rig: IsoCameraRig) -> void:
	session = game_session
	camera_rig = rig


func configure(game_session: GameSession, rig: IsoCameraRig) -> void:
	attach(game_session, rig)


# --- hover ----------------------------------------------------------------

## Screen position in viewport pixels: what is under the pointer, no selection.
func point_at(screen: Vector2) -> void:
	var tile := pick_tile(screen)
	if tile == Vector2i(-1, -1):
		clear_hover()
		return
	var hit := resolve_entity(tile, screen)
	var kind: String = hit["kind"]
	var entity_id: int = hit["id"]
	var moved := tile != hovered_tile
	hovered_tile = tile
	hovered_kind = kind
	hovered_id = entity_id
	if moved:
		tile_hovered.emit(tile)
	if kind == KIND_STATION and (moved or entity_id != _hover_cargo_station):
		_hover_cargo_station = entity_id
		hover_cargo.emit(entity_id, session.cargo.available_summary(entity_id))
	elif kind != KIND_STATION:
		_hover_cargo_station = 0


func clear_hover() -> void:
	if hovered_tile == Vector2i(-1, -1) and hovered_kind == KIND_NONE:
		return
	hovered_tile = Vector2i(-1, -1)
	hovered_kind = KIND_NONE
	hovered_id = 0
	_hover_cargo_station = 0
	tile_unhovered.emit()


# --- resolving ------------------------------------------------------------

## What the player would be clicking at this tile, in the order it is drawn:
## a train on top of everything, then a station, industry or town footprint,
## then track, then bare ground.  `screen` may be (-1, -1) when the caller has a
## tile but no pixel — a keyboard commit, a palette jump — and the train test
## then falls back to a world-space radius.
func resolve_entity(tile: Vector2i, screen: Vector2) -> Dictionary:
	if not session.world.in_bounds(tile):
		return {"kind": KIND_NONE, "id": 0}
	var train_id := 0
	if screen.x >= 0.0 and screen.y >= 0.0:
		train_id = train_at_screen(screen)
	else:
		train_id = nearest_train(Vector2(tile.x + 0.5, tile.y + 0.5))
	if train_id != 0:
		return {"kind": KIND_TRAIN, "id": train_id}
	var owner_id: int = session.world.occupancy_entity(tile)
	match session.world.occupancy_at(tile):
		WorldGrid.Occupancy.STATION:
			return {"kind": KIND_STATION, "id": owner_id}
		WorldGrid.Occupancy.INDUSTRY:
			return {"kind": KIND_INDUSTRY, "id": owner_id}
		WorldGrid.Occupancy.TOWN:
			return {"kind": KIND_TOWN, "id": owner_id}
	if session.world.is_rail(tile):
		return {"kind": KIND_RAIL, "id": 0}
	return {"kind": KIND_TERRAIN, "id": 0}


# --- selection ------------------------------------------------------------

## The click entry point: pick the pixel, then select what it hit.
func select_at_screen(screen: Vector2) -> void:
	var tile := pick_tile(screen)
	if tile == Vector2i(-1, -1):
		return
	select_at(tile, screen)


## Select what is at this tile as seen from this pixel (see `resolve_entity`).
## Empty ground selects nothing, so it clears the selection.
func select_at(tile: Vector2i, screen: Vector2) -> void:
	var hit := resolve_entity(tile, screen)
	var kind: String = hit["kind"]
	if kind == KIND_NONE:
		return
	if kind == KIND_TERRAIN:
		clear_selection()
		return
	select(kind, int(hit["id"]), tile)


func select(kind: String, entity_id: int, tile: Vector2i) -> void:
	selected_kind = kind
	selected_id = entity_id
	selected_tile = tile
	selection_changed.emit(kind, entity_id, tile)


func select_tile(tile: Vector2i) -> void:
	select_at(tile, Vector2(-1.0, -1.0))


func select_station(station_id: int) -> void:
	select(KIND_STATION, station_id, session.stations.tile_of(station_id))


func select_train(train_id: int) -> void:
	select(KIND_TRAIN, train_id, Vector2i(session.trains.position_tiles(train_id)))


func clear_selection() -> void:
	# An empty selection clearing itself is not a change: every panel listening to
	# `selection_changed` would redraw for a key press that did nothing.
	if selected_kind == KIND_NONE and selected_id == 0 and selected_tile == Vector2i(-1, -1):
		return
	select(KIND_NONE, 0, Vector2i(-1, -1))


func has_selection() -> bool:
	return selected_kind != KIND_NONE


func selection_label() -> String:
	match selected_kind:
		KIND_STATION:
			return session.stations.name_of(selected_id)
		KIND_INDUSTRY:
			return session.industries.name_of(selected_id)
		KIND_TOWN:
			return session.towns.name_of(selected_id)
		KIND_TRAIN:
			return session.trains.name_of(selected_id)
		KIND_RAIL:
			return "Track"
		KIND_TERRAIN:
			return session.world.terrain_name(selected_tile)
	return ""


func selection_entity_id() -> int:
	return selected_id


func selection_kind_name() -> String:
	return selected_kind


# --- hit testing ----------------------------------------------------------

## The rectangle pixels are measured in: the live viewport, or the authored size.
func viewport_rect() -> Rect2:
	var viewport := get_viewport()
	if viewport != null:
		var live := viewport.get_visible_rect()
		if live.size.x > 0.0 and live.size.y > 0.0:
			return live
	return Rect2(Vector2.ZERO, viewport_size)


## The camera ray behind a viewport pixel, or empty when there is nothing to
## project through.
func pick_ray(screen: Vector2) -> Dictionary:
	if camera_rig == null:
		return {}
	return camera_rig.screen_to_ray(screen, viewport_rect())


## The point EntityRenderer draws this train at, so the click target and the
## picture can never disagree.
func train_anchor(train_id: int) -> Vector3:
	var tiles := session.trains.position_tiles(train_id)
	var tile := Vector2i(floori(tiles.x), floori(tiles.y))
	return Vector3(tiles.x, session.world.elevation_at(tile) + 0.02, tiles.y)


## Train whose drawn position projects within the pick radius of this pixel.
## Screen space, so a train stays clickable at every zoom — while the world
## stays completely body-free.
func train_at_screen(screen: Vector2) -> int:
	if session == null or camera_rig == null:
		return 0
	var rect := viewport_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return 0
	var best := 0
	var best_distance := TRAIN_PICK_SCREEN * rect.size.y
	for train_id in session.trains.trains():
		var pixel := _screen_pixel(train_anchor(train_id), rect)
		var distance := pixel.distance_to(screen)
		if distance <= best_distance:
			best_distance = distance
			best = train_id
	return best


func nearest_train(world_point: Vector2) -> int:
	var best := 0
	var best_distance := TRAIN_PICK_RADIUS
	for train_id in session.trains.trains():
		var distance := world_point.distance_to(session.trains.position_tiles(train_id))
		if distance < best_distance:
			best_distance = distance
			best = train_id
	return best


func _screen_pixel(point: Vector3, rect: Rect2) -> Vector2:
	# `world_to_screen` speaks pixels relative to the rect, and the rect's own
	# origin turns that into a pixel of the window.  A point behind the camera has
	# no pixel: the infinities travel on, the distance test below fails against
	# them, and a train the player cannot see is never picked.
	return rect.position + camera_rig.world_to_screen(point, rect)


# --- picking --------------------------------------------------------------

## The tile under a viewport pixel.
func pick_tile(screen: Vector2) -> Vector2i:
	var ray := pick_ray(screen)
	if ray.is_empty():
		return Vector2i(-1, -1)
	var origin: Vector3 = ray["origin"]
	var direction: Vector3 = ray["direction"]
	return pick_at(origin, direction)


## March the camera ray down to the heightfield and return the first thing it
## touches.
##
## Two things make this more than a loop.  A step can straddle the lip of a
## terrace, and at this pitch the ray comes down at not much more than the rate
## the terraces drop, so a sample tested only against the tile it lands in can
## pass over a step's edge and report the pick a whole tile late — the pixel shows
## the higher ground and the game answers with the tile below it.  The march
## therefore tests the highest ground its step crossed.  And because "somewhere in
## the last half tile" is not where the pixel is pointing, that step is then
## searched properly and the touch bisected out of it.
func pick_at(origin: Vector3, direction: Vector3) -> Vector2i:
	if session == null or direction.length_squared() <= 0.000001:
		return Vector2i(-1, -1)
	var grid: WorldGrid = session.world
	var above := origin
	var walked := 0.0
	while walked < RAY_LENGTH:
		var point := origin + direction * walked
		if point.y < FLOOR_Y:
			return Vector2i(-1, -1)
		var tile := WorldCoords.world_to_tile(point)
		if not grid.in_bounds(tile):
			if point.y <= 0.0:
				return Vector2i(-1, -1)
		elif point.y <= _step_ceiling(above, point, grid):
			var hit := _first_contact(above, point, grid, direction)
			if hit != Vector2i(-1, -1):
				return hit
		above = point
		walked += RAY_STEP
	return Vector2i(-1, -1)


## The topmost ground a march step passed over.  A step shorter than a tile
## touches at most the four tiles around the rectangle it swept, so the highest of
## those is the surface the ray could have struck anywhere inside it.
func _step_ceiling(from: Vector3, to: Vector3, grid: WorldGrid) -> float:
	var high := grid.elevation_at(WorldCoords.world_to_tile(from))
	high = maxf(high, grid.elevation_at(WorldCoords.world_to_tile(to)))
	high = maxf(high, grid.elevation_at(WorldCoords.world_to_tile(Vector3(from.x, 0.0, to.z))))
	high = maxf(high, grid.elevation_at(WorldCoords.world_to_tile(Vector3(to.x, 0.0, from.z))))
	return high


## The first point inside this step at which the ray is genuinely under the ground
## it is over, or nothing when the conservative test above flagged a step the ray
## only looked like it was entering — over the lip of a terrace and clear of it.
func _first_contact(above: Vector3, below: Vector3, grid: WorldGrid, direction: Vector3) -> Vector2i:
	var previous := above
	for substep in CONTACT_SUBSTEPS:
		var point := above.lerp(below, float(substep + 1) / float(CONTACT_SUBSTEPS))
		var tile := WorldCoords.world_to_tile(point)
		if grid.in_bounds(tile) and point.y <= grid.elevation_at(tile):
			return _refine_hit(previous, point, direction)
		previous = point
	return Vector2i(-1, -1)


func _refine_hit(above: Vector3, below: Vector3, direction: Vector3) -> Vector2i:
	var grid: WorldGrid = session.world
	var high := above
	var low := below
	for _pass in REFINE_LIMIT:
		var middle := high.lerp(low, 0.5)
		var tile := WorldCoords.world_to_tile(middle)
		if grid.in_bounds(tile) and middle.y <= grid.elevation_at(tile):
			low = middle
		else:
			high = middle
		if high.distance_to(low) <= REFINE_ACCURACY:
			break
	# A heightfield is a staircase, so a ray can meet the surface at a riser: the
	# exact crossing is then a tile seam, and a point exactly on a seam belongs to
	# whichever side the last bit of floating point lands on.  Settling a
	# five-hundredth of a tile into the surface names the ground the player is
	# actually looking at, and names it the same way every time.
	return WorldCoords.world_to_tile(low + direction * REFINE_SETTLE)
