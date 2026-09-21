class_name TestSession
extends RefCounted

## Fixtures built on the real composition root, so a test exercises exactly the
## wiring the shipped game uses — services, lookups and monthly roll-over —
## without loading a single node of presentation.
##
## Anything that costs money goes through the services; nothing here hands a
## service a hand-made entity.


static func create(map_name: String = "founders_valley") -> GameSession:
	var session := GameSession.new()
	if not session.start(map_name):
		push_error("could not start the session: " + session.last_error)
	return session


static func dispose(session: GameSession) -> void:
	if session != null:
		session.free()


# --- locating map content --------------------------------------------------

static func industry_by_definition(session: GameSession, definition_id: String) -> int:
	for industry_id in session.industries.industries():
		if session.industries.definition_of(industry_id) == definition_id:
			return industry_id
	return 0


static func town_containing(session: GameSession, needle: String) -> int:
	for town_id in session.towns.towns():
		if session.towns.name_of(town_id).to_lower().contains(needle.to_lower()):
			return town_id
	return 0


static func stations_near(session: GameSession, tile: Vector2i, radius: int = 6) -> Array[int]:
	var found: Array[int] = []
	for station_id in session.stations.stations():
		if WorldCoords.distance_tiles(session.stations.tile_of(station_id), tile) <= float(radius):
			found.append(station_id)
	return found


# --- construction helpers --------------------------------------------------

## The five collinear cells `lay_spur` would build around `anchor`.
static func spur_tiles(anchor: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for offset in 5:
		tiles.append(Vector2i(anchor.x - 2 + offset, anchor.y))
	return tiles


## Lays a straight run beside an entity: five collinear cells, so the middle of
## the run is real through line a station can claim as access.
static func lay_spur(session: GameSession, anchor: Vector2i) -> Dictionary:
	var tiles := spur_tiles(anchor)
	var built := session.builder.build_track_run(tiles)
	return {"ok": bool(built["ok"]), "tiles": tiles, "reason": String(built["reason"])}


## Builds a station that actually serves the entity at `tile`: legal placement
## *and* the entity inside its catchment, as load or as sink.  Placement alone is
## a weaker promise than the tool panel makes, so a fixture must not settle for
## it.  Returns the station id, or 0 when nothing works — which in a test means a
## real bug, not a skipped case.
static func station_for_tile(session: GameSession, tile: Vector2i, label: String = "",
		require_served: bool = true) -> int:
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var anchor := Vector2i(tile.x + dx, tile.y + dy)
			var preview := session.builder.preview_station("small_station", anchor)
			if not bool(preview["ok"]):
				continue
			if require_served and not preview_covers(preview, tile):
				continue
			var built := session.builder.build_station("small_station", anchor, label)
			if bool(built["ok"]):
				return int(built["id"])
	return 0


static func preview_covers(preview: Dictionary, tile: Vector2i) -> bool:
	for entry in preview.get("sources", []):
		if (entry["tile"] as Vector2i) == tile:
			return true
	return false


## The whole loop for one endpoint: spur, then a station that serves it.
static func serve(session: GameSession, tile: Vector2i, label: String = "",
		require_served: bool = true) -> int:
	var spur := lay_spur(session, Vector2i(tile.x, tile.y - 3))
	if not bool(spur["ok"]):
		push_warning("spur refused at %s: %s" % [tile, spur["reason"]])
	return station_for_tile(session, tile, label, require_served)


## Connects two stations' rail so a route between them can exist.
static func join(session: GameSession, from_station: int, to_station: int) -> Dictionary:
	var from_rail := session.stations.rail_access_tile(from_station)
	var to_rail := session.stations.rail_access_tile(to_station)
	return session.builder.build_rail(from_rail, to_rail)


## Builds the shipped world's working coal line — station at the colliery,
## station at the works, rail between them, and a hopper consist running it.
## This is the game's core loop assembled by the same calls the UI makes.
static func coal_line(session: GameSession) -> Dictionary:
	var mine := industry_by_definition(session, "coal_mine")
	var plant := industry_by_definition(session, "power_plant")
	var mine_station := serve(session, session.industries.tile_of(mine), "Blackedge Wharf")
	var plant_station := serve(session, session.industries.tile_of(plant), "Valley Gate Works")
	var joined := join(session, mine_station, plant_station)
	var bought := session.trains.purchase(mine_station, "steam_440", ["coal_hopper", "coal_hopper"])
	var result := {
		"ok": false, "reason": "", "mine": mine, "plant": plant,
		"mine_station": mine_station, "plant_station": plant_station,
		"train": 0, "route": 0, "mine_tile": session.industries.tile_of(mine),
		"plant_tile": session.industries.tile_of(plant),
	}
	if mine_station == 0 or plant_station == 0:
		result["reason"] = "stations refused"
		return result
	if not bool(joined["ok"]):
		result["reason"] = "rail refused: " + String(joined["reason"])
		return result
	if not bool(bought["ok"]):
		result["reason"] = "train refused: " + String(bought["reason"])
		return result
	var train := int(bought["id"])
	var stops: Array[Dictionary] = [
		{"station_id": mine_station, "load": ["coal"], "unload": []},
		{"station_id": plant_station, "load": [], "unload": ["coal"]},
	]
	var routed := session.trains.set_route(train, stops)
	if not bool(routed["ok"]):
		result["reason"] = "route refused: " + String(routed["reason"])
		return result
	result["ok"] = true
	result["train"] = train
	result["route"] = int(routed["id"])
	return result
