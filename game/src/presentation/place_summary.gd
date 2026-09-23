class_name PlaceSummary
extends RefCounted

## The second line of a place's name: the one number that tells a player whether
## to care about the thing they are looking at.
##
## Spec §71 and §72 want the same line twice — once pinned to the map at a
## distance, once under the cursor up close.  Two classes writing that sentence
## separately would drift the moment someone reworded one of them, so the
## wording lives here.  It reads domain state through the services and formats
## it; it owns nothing, decides nothing, and holds no node.

## The one line for a place, or "" when the place has nothing worth saying.
static func line_for(session: GameSession, kind: String, entity_id: int) -> String:
	match kind:
		SelectionService.KIND_STATION:
			return station_line(session, entity_id)
		SelectionService.KIND_TOWN:
			return town_line(session, entity_id)
		SelectionService.KIND_INDUSTRY:
			return industry_line(session, entity_id)
		SelectionService.KIND_TRAIN:
			return train_line(session, entity_id)
	return ""


## "37 cargo waiting" — the yard's reason to exist, summed across cargos.  A yard
## with nothing waiting says so plainly, because an empty yard is information.
static func station_line(session: GameSession, station_id: int) -> String:
	var waiting := 0.0
	for entry in session.cargo.available_summary(station_id):
		waiting += float(entry["amount"])
	if waiting <= 0.0:
		return "nothing waiting"
	return "%s cargo waiting" % _count(waiting)


## A town is its people, and the number the railway is measured against.
static func town_line(session: GameSession, town_id: int) -> String:
	return "%s people" % _count(float(session.towns.population_of(town_id)))


## A working place names what it moves and how much is stacked ready for it.
static func industry_line(session: GameSession, industry_id: int) -> String:
	var definition := session.industries.def_of(industry_id)
	if definition == null:
		return ""
	var cargo_id := _primary_cargo(definition)
	if cargo_id == "":
		return definition.display_name.to_lower()
	var stored := session.industries.inventory_of(industry_id, cargo_id)
	if stored <= 0.0:
		return "%s ready" % definition.display_name.to_lower()
	return "%s %s waiting" % [session.data.cargo_display(cargo_id).to_lower(), _count(stored)]


## A train's status plus where it is going: enough to decide whether to select it.
static func train_line(session: GameSession, train_id: int) -> String:
	var status := session.trains.state_label(train_id)
	var speed := session.trains.speed_kmh(train_id)
	if status == "":
		return ""
	return "%s · %.0f km/h" % [status, speed]


## The cargo a works is known for: what it produces if it produces, else what it
## consumes.  V1 works each handle a single cargo, so this is the whole answer.
static func _primary_cargo(definition: DataRegistry.IndustryDef) -> String:
	if not definition.produces.is_empty():
		return String(definition.produces[0].get("cargo", ""))
	if not definition.accepts.is_empty():
		return String(definition.accepts[0].get("cargo", ""))
	return ""


## Counts are read at a glance, so they are whole numbers with a thousands
## separator and no decimal point: "37", "1,240".
static func _count(amount: float) -> String:
	var whole := int(round(amount))
	var digits := str(absi(whole))
	var grouped := ""
	for index in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0:
			grouped += ","
		grouped += digits[index]
	return ("-" + grouped) if whole < 0 else grouped
