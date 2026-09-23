extends TestBase

## Save/load durability: versioned envelopes, atomic slots, exact round-trips.
##
## The point of this suite is fidelity, not plumbing: a coal line is built and
## run 800 ticks, the *entire* domain snapshot is compared byte-for-byte
## (rail masks, inventories, train batches, ledger, ids) after a load into a
## fresh session — and the money invariant must survive every path a file can
## take, including the bad ones (truncated, future-version, broken refs).

const SLOT_PREFIX := "zz-save-"
const SLOT_FULL := SLOT_PREFIX + "full"
const SLOT_TWICE := SLOT_PREFIX + "twice"
const SLOT_MONEY := SLOT_PREFIX + "money"
const SLOT_DELETE := SLOT_PREFIX + "delete"
const SLOT_CORRUPT := SLOT_PREFIX + "corrupt"
const SLOT_FUTURE := SLOT_PREFIX + "future"
const SLOT_OLD := SLOT_PREFIX + "old"
const SLOT_MIGRATE := SLOT_PREFIX + "migrate"
const SLOT_LIST_A := SLOT_PREFIX + "list-a"
const SLOT_LIST_B := SLOT_PREFIX + "list-b"
const SLOT_REFS := SLOT_PREFIX + "refs"
const SLOT_AUTOSAVE := SLOT_PREFIX + "autosave-direct"

## Autosave names the 6550-tick walk produces; teardown removes exactly these.
const AUTOSAVE_NAMES: PackedStringArray = [
	"autosave_1850_04", "autosave_1850_07", "autosave_1850_10",
	"autosave_1851_01", "autosave_1851_04", "autosave_1851_07",
]

const SLOTS: PackedStringArray = [
	SLOT_FULL, SLOT_TWICE, SLOT_MONEY, SLOT_DELETE, SLOT_CORRUPT, SLOT_FUTURE,
	SLOT_OLD, SLOT_MIGRATE, SLOT_LIST_A, SLOT_LIST_B, SLOT_REFS, SLOT_AUTOSAVE,
	"quicksave",
]

var session: GameSession
var _extra_sessions: Array[GameSession] = []
var _autosave_events: PackedStringArray = PackedStringArray()


func setup() -> void:
	_purge_test_files()
	session = TestSession.create()


func teardown() -> void:
	TestSession.dispose(session)
	session = null
	for other in _extra_sessions:
		TestSession.dispose(other)
	_extra_sessions.clear()
	_autosave_events.clear()
	_purge_test_files()


func _purge_test_files() -> void:
	DirAccess.make_dir_recursive_absolute(GameSession.SAVE_FOLDER)
	var directory := DirAccess.open(GameSession.SAVE_FOLDER)
	if directory == null:
		return
	# Autosaves are system-managed and capped by retention; a stray autosave
	# from a dev game run would poison the retention count — clear the class.
	for file in directory.get_files():
		var name := String(file)
		var stem := name.trim_suffix(".json").trim_suffix(".json.prev").trim_suffix(".tmp")
		if stem.begins_with(SLOT_PREFIX) or stem == "quicksave" or stem.begins_with("autosave_"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(
				GameSession.SAVE_FOLDER.path_join(name)))


func fresh_session() -> GameSession:
	var other := TestSession.create()
	_extra_sessions.append(other)
	return other


# --- round-trip fidelity ------------------------------------------------------

func test_a_full_round_trip_preserves_the_whole_domain() -> void:
	var line := TestSession.coal_line(session)
	check_true(bool(line["ok"]), "a coal line is buildable for the round trip: " + String(line["reason"]))
	# A save worth round-tripping is one that has actually traded, so the wait here
	# is for the first ton rather than for a count of ticks: a loaded leg across the
	# valley is longer than a month of the calendar.
	TestSession.run_until(session, func() -> bool: return session.cargo.delivered_total() > 0.0,
			TestSession.DELIVERY_TICKS)

	var saved := session.saves.save(SLOT_FULL)
	check_true(bool(saved["ok"]), "the save wrote: " + String(saved.get("reason", "")))
	var before := session.snapshot()
	check_gt(session.cargo.delivered_total(), 0.0, "the world had actually delivered cargo")

	var loaded := fresh_session()
	var result := loaded.saves.load(SLOT_FULL)
	check_true(bool(result["ok"]), "the fresh session loads it: " + String(result.get("reason", "")))
	var after := loaded.snapshot()

	var problems: PackedStringArray = PackedStringArray()
	_deep_equal(before, after, "snapshot", problems)
	if not problems.is_empty():
		fail("snapshot differs after load:\n      " + "\n      ".join(problems))

	check_eq(loaded.ids.peek(), session.ids.peek(), "the entity id counter resumes exactly")
	check_eq(loaded.date().display_full(), session.date().display_full(), "the calendar date matches")
	check_eq(loaded.economy.cash, session.economy.cash, "cash is restored to the cent")
	check_eq(loaded.economy.ledger().size(), session.economy.ledger().size(), "the whole ledger came back")
	check_true(loaded.economy.is_consistent(), "opening + Σ ledger == cash in the loaded session")

	# Rail cells and the presence/mask bitmasks are compared exactly (as
	# base64 inside the snapshot above); this is the same claim in domain terms.
	check_eq(loaded.rail.rail_tiles().size(), session.rail.rail_tiles().size(), "same rail cells")
	for index in session.world.rail.size():
		if session.world.rail[index] != loaded.world.rail[index] \
				or session.world.rail_present[index] != loaded.world.rail_present[index]:
			fail("rail mask/presence byte %d differs" % index)
			break

	var train := int(line["train"])
	check_eq(loaded.trains.state_of(train), session.trains.state_of(train), "train state survives")
	var here := session.trains.position_tiles(train)
	var there := loaded.trains.position_tiles(train)
	check_near(here.x, there.x, "train position x matches after load")
	check_near(here.y, there.y, "train position y matches after load")
	check_near(float(session.trains.train(train)["progress"]), float(loaded.trains.train(train)["progress"]),
			"progress along the path matches")
	check_near(loaded.trains.total_revenue(train), session.trains.total_revenue(train),
			"per-train revenue matches")
	check_eq(loaded.trains.stock_of(train), session.trains.stock_of(train), "the consist matches")
	check_eq(loaded.trains.batches(train).size(), session.trains.batches(train).size(),
			"cargo batches survive")

	var route := int(line["route"])
	var path_a: PackedVector2Array = session.routes.path_of(route)
	var path_b: PackedVector2Array = loaded.routes.path_of(route)
	check_eq(path_b.size(), path_a.size(), "the route path rebuilt identically")
	for index in mini(path_a.size(), path_b.size()):
		if not path_a[index].is_equal_approx(path_b[index]):
			fail("route path point %d differs" % index)
			break
	var marks_a: PackedFloat64Array = session.routes.stop_ticks_of(route)
	var marks_b: PackedFloat64Array = loaded.routes.stop_ticks_of(route)
	check_eq(marks_b.size(), marks_a.size(), "stop markers round-trip")
	for index in mini(marks_a.size(), marks_b.size()):
		check_near(marks_b[index], marks_a[index], "stop marker %d matches" % index)
	check_eq(loaded.routes.station_ids(route), session.routes.station_ids(route), "route stops match")

	var mine_station := int(line["mine_station"])
	check_near(loaded.stations.inventory_of(mine_station, "coal"),
			session.stations.inventory_of(mine_station, "coal"),
			"the station's waiting coal survives")

	# The loaded game must go on playing, not sit as a museum piece.  The restored
	# train has to earn again, not merely hold its old revenue — so this waits for
	# the next ton to change hands, whenever the valley's own pace brings it.
	var delivered := loaded.cargo.delivered_total()
	TestSession.run_until(loaded, func() -> bool: return loaded.cargo.delivered_total() > delivered,
			TestSession.DELIVERY_TICKS)
	check_gt(loaded.cargo.delivered_total(), delivered, "the loaded train keeps working")
	check_gt(loaded.economy.cash, 0.0, "and the company still exists")
	check_true(loaded.economy.is_consistent(), "money still reconciles after resuming")


func test_saving_twice_keeps_the_ledger_invariant() -> void:
	var line := TestSession.coal_line(session)
	check_true(bool(line["ok"]), "line built: " + String(line["reason"]))
	session.advance_ticks(300)
	check_true(bool(session.saves.save(SLOT_TWICE)["ok"]), "first save over the slot")
	session.advance_ticks(300)
	var second := session.saves.save(SLOT_TWICE)
	check_true(bool(second["ok"]), "the same slot is saved again over itself")

	var loaded := fresh_session()
	check_true(bool(loaded.saves.load(SLOT_TWICE)["ok"]), "the slot loads back")
	check_true(loaded.economy.is_consistent(), "opening + Σ ledger == cash after the double save")

	# Read the file itself: the ledger written must justify the cash written.
	var read := SaveWriter.read_json(session.saves.slot_path(SLOT_TWICE))
	check_true(bool(read["ok"]), "the file parses")
	var economy := Dictionary(Dictionary(read["data"])["data"]["economy"])
	var sum := 0.0
	for entry in Array(economy["transactions"]):
		sum += float(entry["amount"])
	check_near(float(economy["opening_balance"]) + sum, float(economy["cash"]),
			"opening balance + Σ ledger == cash inside the file")


func test_load_restores_money_exactly() -> void:
	var line := TestSession.coal_line(session)
	check_true(bool(line["ok"]), "line built: " + String(line["reason"]))
	session.advance_ticks(200)
	session.economy.company_name = "Purser & Sons"
	check_true(bool(session.saves.save(SLOT_MONEY)["ok"]), "saved at a moment of money")
	var cash_saved := session.economy.cash
	var rows_saved := session.economy.ledger().size()
	var movement_saved := session.economy.net_movement()

	# Time has to actually move the money on before the save is compared against a
	# world that has moved: what the train earns, and what it costs to keep, are
	# paid out at the pace the trains run at, not at a count of ticks picked here.
	TestSession.run_until(session,
			func() -> bool: return session.economy.cash != cash_saved,
			TestSession.DELIVERY_TICKS)
	check_neq(session.economy.cash, cash_saved, "time moved the money on")

	var result := session.saves.load(SLOT_MONEY)
	check_true(bool(result["ok"]), "loading that moment back: " + String(result.get("reason", "")))
	check_eq(int(roundf(session.economy.cash * 100.0)), int(roundf(cash_saved * 100.0)),
			"cash returns to the exact cent it held")
	check_eq(session.economy.ledger().size(), rows_saved, "the ledger has exactly its old rows")
	check_near(session.economy.net_movement(), movement_saved, "Σ ledger returns too")
	check_eq(session.economy.company_name, "Purser & Sons", "company name travels with the money")
	check_true(session.economy.is_consistent(), "and the invariant holds on the restored pair")


func test_quicksave_and_quickload_return_to_the_moment() -> void:
	var line := TestSession.coal_line(session)
	check_true(bool(line["ok"]), "line built: " + String(line["reason"]))
	session.advance_ticks(150)
	var quick := session.saves.quicksave()
	check_true(bool(quick["ok"]), "quicksave wrote: " + String(quick.get("reason", "")))
	var mark := session.snapshot()

	session.advance_ticks(400)
	var back := session.saves.quickload()
	check_true(bool(back["ok"]), "quickload restores: " + String(back.get("reason", "")))
	var problems: PackedStringArray = PackedStringArray()
	_deep_equal(mark, session.snapshot(), "quicksave", problems)
	if not problems.is_empty():
		fail("quickload did not restore the moment:\n      " + "\n      ".join(problems))


func test_quickload_without_a_quicksave_is_refused() -> void:
	var result := session.saves.quickload()
	check_false(bool(result["ok"]), "there is nothing to load")
	check_gt(String(result.get("reason", "")).length(), 0, "and the refusal carries a reason")


# --- bad files refuse cleanly ---------------------------------------------------

func test_a_truncated_save_is_refused_without_wounding_the_session() -> void:
	var line := TestSession.coal_line(session)
	check_true(bool(line["ok"]), "line built: " + String(line["reason"]))
	session.advance_ticks(100)
	var path := session.saves.slot_path(SLOT_CORRUPT)
	check_true(bool(session.saves.save(SLOT_CORRUPT)["ok"]), "a good save exists")
	var text := FileAccess.get_file_as_string(path)
	var half := FileAccess.open(path, FileAccess.WRITE)
	half.store_string(text.substr(0, int(text.length() * 0.4)))
	half.close()

	var mark := session.snapshot()
	var cash_before := session.economy.cash
	var result := session.saves.load(SLOT_CORRUPT)
	check_false(bool(result["ok"]), "the truncated file is refused")
	check_gt(String(result.get("reason", "")).length(), 0, "with a reason")
	check_eq(session.economy.cash, cash_before, "the running session kept its money")
	var problems: PackedStringArray = PackedStringArray()
	_deep_equal(mark, session.snapshot(), "surviving-session", problems)
	if not problems.is_empty():
		fail("a refused load must not change the session:\n      " + "\n      ".join(problems))
	session.advance_ticks(5)
	check_true(session.economy.is_consistent(), "and the game still ticks after the refusal")


func test_a_future_save_version_is_refused_with_an_explanation() -> void:
	var document := session.saves.document("manual")
	document["save_version"] = SaveService.SAVE_VERSION + 7
	var path := session.saves.slot_path(SLOT_FUTURE)
	check_true(bool(SaveWriter.write_json(path, document)["ok"]), "a too-new file exists")
	var cash_before := session.economy.cash
	var result := session.saves.load(SLOT_FUTURE)
	check_false(bool(result["ok"]), "the loader refuses a newer schema")
	check_has(String(result.get("reason", "")), "newer", "and says why: " + String(result.get("reason", "")))
	check_eq(session.economy.cash, cash_before, "the session never felt it")


func test_an_unmigratable_old_version_names_the_version_range() -> void:
	var document := session.saves.document("manual")
	document["save_version"] = 0
	var path := session.saves.slot_path(SLOT_OLD)
	check_true(bool(SaveWriter.write_json(path, document)["ok"]), "a v0 file exists")
	var result := session.saves.load(SLOT_OLD)
	check_false(bool(result["ok"]), "no migration means no load")
	var reason := String(result.get("reason", ""))
	check_has(reason, "0", "the reason names the range: " + reason)
	check_has(reason, str(SaveService.SAVE_VERSION), "from v0 to the current version")


func test_a_registered_migration_upgrades_an_old_save() -> void:
	var line := TestSession.coal_line(session)
	check_true(bool(line["ok"]), "line built: " + String(line["reason"]))
	session.advance_ticks(100)
	check_true(bool(session.saves.save(SLOT_MIGRATE)["ok"]), "a current save exists")
	var read := SaveWriter.read_json(session.saves.slot_path(SLOT_MIGRATE))
	var document := Dictionary(read["data"])
	document["save_version"] = 0
	check_true(bool(SaveWriter.write_json(session.saves.slot_path(SLOT_OLD), document)["ok"]),
			"the same content re-stamped as v0")
	var cash_at_save := session.economy.cash

	var loaded := fresh_session()
	loaded.saves.register_migration(0, Callable(self, "_migrate_v0"))
	var result := loaded.saves.load(SLOT_OLD)
	check_true(bool(result["ok"]), "the chain runs and loads: " + String(result.get("reason", "")))
	check_near(loaded.economy.cash, cash_at_save, "the migrated save carries the money")
	check_true(loaded.economy.is_consistent(), "and reconciles")


func test_route_stop_for_a_missing_station_is_reported() -> void:
	var line := TestSession.coal_line(session)
	check_true(bool(line["ok"]), "line built: " + String(line["reason"]))
	var good := session.snapshot()
	check_true(session.saves.verify_refs(good).is_empty(), "the real snapshot verifies clean")

	var bad := good.duplicate(true)
	var routes := Dictionary(bad["routes"])
	var first := Dictionary(Array(routes["routes"])[0])
	var stop := Dictionary(Array(first["stops"])[0])
	stop["station_id"] = 987654
	var path := session.saves.slot_path(SLOT_REFS)
	var document := {"save_version": SaveService.SAVE_VERSION, "game_version": "test",
		"header": {}, "data": bad}
	check_true(bool(SaveWriter.write_json(path, document)["ok"]), "the broken file is written")

	var problems := session.saves.verify_refs(bad)
	check_gt(problems.size(), 0, "verify_refs reports the dangling stop")
	check_has("; ".join(problems), "987654", "and names the missing station")

	var cash_before := session.economy.cash
	var result := session.saves.load(SLOT_REFS)
	check_false(bool(result["ok"]), "the load is refused")
	check_has(String(result.get("reason", "")), "987654", "the refusal names the cause")
	check_eq(session.economy.cash, cash_before, "untouched session, unchanged money")


# --- slots, listing, deletion ----------------------------------------------------

func test_delete_removes_the_file() -> void:
	check_true(bool(session.saves.save(SLOT_DELETE)["ok"]), "the save exists")
	var path := session.saves.slot_path(SLOT_DELETE)
	check_true(FileAccess.file_exists(path), "on disk")
	var listed := _slots_in_list()
	check_true(listed.has(SLOT_DELETE), "and in list_saves")
	var removed := session.saves.delete(SLOT_DELETE)
	check_true(bool(removed["ok"]), "delete answers ok")
	check_false(FileAccess.file_exists(path), "the file is really gone")
	check_false(_slots_in_list().has(SLOT_DELETE), "and no longer listed")
	var again := session.saves.delete(SLOT_DELETE)
	check_false(bool(again["ok"]), "deleting a missing slot is a refusal, not a lie")


func test_list_saves_carries_the_header_facts() -> void:
	var line := TestSession.coal_line(session)
	check_true(bool(line["ok"]), "line built: " + String(line["reason"]))
	session.advance_ticks(400)
	session.economy.company_name = "Test & Sons"
	check_true(bool(session.saves.save(SLOT_LIST_A)["ok"]), "first slot saved")
	session.advance_ticks(100)
	check_true(bool(session.saves.save(SLOT_LIST_B)["ok"]), "second slot saved")

	var rows := session.saves.list_saves()
	var by_name := {}
	for row in rows:
		by_name[String(row["slot"])] = row
	check_true(by_name.has(SLOT_LIST_A) and by_name.has(SLOT_LIST_B), "both slots are listed")
	var row: Dictionary = by_name[SLOT_LIST_B]
	check_false(bool(row["corrupt"]), "readable rows are not marked corrupt")
	check_eq(int(row["save_version"]), SaveService.SAVE_VERSION, "the schema version is stated")
	check_eq(String(row["company"]), "Test & Sons", "the company name is in the header")
	check_eq(String(row["map"]), "founders_valley", "the map name is in the header")
	check_eq(int(row["year"]), session.date().year, "the in-game year is in the header")
	check_near(float(row["cash"]), session.economy.cash, "the cash figure matches")
	check_gt(String(row["saved_at"]).length(), 0, "and there is a real timestamp")
	check_eq(String(rows[0]["slot"]), SLOT_LIST_B, "newest first")


func test_invalid_slot_names_never_escape_the_folder() -> void:
	check_false(SaveService.is_valid_slot("../evil"), "no path traversal")
	check_false(SaveService.is_valid_slot("a/b"), "no subfolders")
	check_false(SaveService.is_valid_slot(""), "not empty")
	check_true(SaveService.is_valid_slot("spring_1850-save"), "sensible names are fine")
	var result := session.saves.save("../evil")
	check_false(bool(result["ok"]), "and the save itself refuses")


# --- autosave ---------------------------------------------------------------------

func test_autosave_every_three_months_prunes_and_never_mutates() -> void:
	_autosave_events.clear()
	session.autosave_performed.connect(_on_autosave_event)
	# Six autosave boundaries at the every-3 schedule: Apr, Jul, Oct 1850 and Jan,
	# Apr, Jul 1851.  The distance to that is derived from the clock's own pace —
	# `ticks_per_day` is tuning, and a memorised tick count stops short of the
	# months it is meant to cross the moment the tuning moves.
	var month_ticks := session.clock.ticks_per_day * 30
	session.advance_ticks(19 * month_ticks + 8)
	check_eq(_autosave_events.size(), 6, "six month boundaries at the every-3 schedule fired")

	var kept := 0
	var gone := 0
	for name in AUTOSAVE_NAMES:
		var path := GameSession.SAVE_FOLDER.path_join(name + ".json")
		if FileAccess.file_exists(path):
			kept += 1
		else:
			gone += 1
	check_eq(kept, SaveService.AUTOSAVE_RETENTION, "retention keeps the newest five")
	check_eq(gone, 1, "and pruned the oldest")
	check_has(session.saves.latest_autosave(), "autosave_1851_07", "Continue would load the newest")

	# An autosave must be a pure read: no ledger rows, no cash, no drift.
	var cash_before := session.economy.cash
	var rows_before := session.economy.ledger().size()
	var mark := session.snapshot()
	var direct := session.saves.autosave()
	check_true(bool(direct["ok"]), "a direct autosave() also writes: " + String(direct.get("reason", "")))
	check_eq(session.economy.cash, cash_before, "autosave wrote no money")
	check_eq(session.economy.ledger().size(), rows_before, "autosave recorded no transaction")
	var problems: PackedStringArray = PackedStringArray()
	_deep_equal(mark, session.snapshot(), "autosave-purity", problems)
	if not problems.is_empty():
		fail("autosave mutated the session:\n      " + "\n      ".join(problems))
	session.autosave_performed.disconnect(_on_autosave_event)


func _on_autosave_event(path: String) -> void:
	_autosave_events.append(path)


# --- migration under test ------------------------------------------------------------

func _migrate_v0(document: Dictionary) -> Dictionary:
	var migrated := document.duplicate(true)
	migrated["save_version"] = 1
	return migrated


# --- helpers ------------------------------------------------------------------------

func _slots_in_list() -> Dictionary:
	var seen := {}
	for row in session.saves.list_saves():
		seen[String(row["slot"])] = true
	return seen


func _deep_equal(a: Variant, b: Variant, label: String, problems: PackedStringArray) -> void:
	if problems.size() > 16:
		return
	if typeof(a) == TYPE_DICTIONARY:
		if typeof(b) != TYPE_DICTIONARY:
			problems.append("%s: dictionary became %s" % [label, type_string(typeof(b))])
			return
		for key in a.keys():
			if not b.has(key):
				problems.append("%s.%s: missing after load" % [label, str(key)])
			else:
				_deep_equal(a[key], b[key], "%s.%s" % [label, str(key)], problems)
		for key in b.keys():
			if not a.has(key):
				problems.append("%s.%s: appeared after load" % [label, str(key)])
		return
	if typeof(a) == TYPE_ARRAY:
		if typeof(b) != TYPE_ARRAY:
			problems.append("%s: array became %s" % [label, type_string(typeof(b))])
			return
		if a.size() != b.size():
			problems.append("%s: length %d -> %d" % [label, a.size(), b.size()])
			return
		for index in a.size():
			_deep_equal(a[index], b[index], "%s[%d]" % [label, index], problems)
		return
	if typeof(a) == TYPE_FLOAT or typeof(b) == TYPE_FLOAT:
		if absf(float(a) - float(b)) > 0.0001:
			problems.append("%s: %s != %s" % [label, str(a), str(b)])
		return
	if a != b:
		problems.append("%s: %s != %s" % [label, str(a), str(b)])


# --- the envelope and the atomic trail ----------------------------------------

func test_a_written_save_says_which_schema_and_which_build_wrote_it() -> void:
	## A save outlives the build that wrote it.  The two versions that decide
	## whether it can be read at all are stated in the file, not in the reader.
	check_true(bool(session.saves.save(SLOT_FULL)["ok"]), "the slot was written")
	var read := SaveWriter.read_json(session.saves.slot_path(SLOT_FULL))
	check_true(bool(read["ok"]), "and it reads back as JSON")
	var document := Dictionary(read["data"])
	check_eq(int(document["save_version"]), SaveService.SAVE_VERSION,
		"the schema version the loader will migrate from")
	check_eq(String(document["game_version"]), SaveService.GAME_VERSION,
		"and the build that produced it")
	var header := Dictionary(document["header"])
	check_eq(String(header["map"]), session.map_id, "which valley this save belongs to")
	check_near(float(header["cash"]), session.economy.cash, "what the company held at the moment of writing", 0.0001)
	check_has(String(header["date"]), "185", "and the day it was written, in game terms")


func test_an_interrupted_write_leaves_the_save_the_player_already_owns() -> void:
	## The whole point of temp-parse-rename is that the live slot is only ever
	## replaced by a file that was already proven readable.
	var first := session.saves.save(SLOT_TWICE)
	check_true(bool(first["ok"]), "the first save wrote")
	var first_cash := session.economy.cash
	session.economy.spend(2500.0, EconomyService.CATEGORY_MAINTENANCE, "Bills")
	check_true(bool(session.saves.save(SLOT_TWICE)["ok"]), "the second save wrote over it")

	var path := session.saves.slot_path(SLOT_TWICE)
	check_false(FileAccess.file_exists(path + SaveWriter.TEMP_SUFFIX),
		"no half-written temporary is left in the folder")
	var previous := path + ".prev"
	check_true(FileAccess.file_exists(previous),
		"the generation the rename replaced is kept")
	var older := SaveWriter.read_json(previous)
	check_true(bool(older["ok"]), "and it still parses — that is the file to fall back to")
	check_near(float(Dictionary(Dictionary(older["data"])["header"])["cash"]), first_cash, "it is the older money, not the newer money", 0.0001)
	var live := SaveWriter.read_json(path)
	check_near(float(Dictionary(Dictionary(live["data"])["header"])["cash"]), session.economy.cash, "while the slot itself holds the newer save", 0.0001)
