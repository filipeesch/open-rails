class_name TestConstructionTool
extends TestBase

## The construction tool and its economy, driven headlessly.
##
## The UI tool drives exactly three domain calls — preview (hover), preview
## again while dragging, then commit — so that API is what a tool test must
## hold to the fire: same answer before the click as after it, one transaction
## per commit, and an undo that reverses both the track and the money.
## No UI nodes are imported here; the Shift-precision click is modelled as the
## single-tile commit the tool would issue for it.

var session: GameSession
var _build_failed_reasons: Array[String] = []
var _rail_built_signals: int = 0
var _rail_built_cost_total: float = 0.0
var _expired_labels: Array[String] = []


func setup() -> void:
	session = TestConstruction.blank_session(128, 128)
	_build_failed_reasons = []
	_rail_built_signals = 0
	_rail_built_cost_total = 0.0
	_expired_labels = []
	session.builder.build_failed.connect(_on_build_failed)
	session.builder.rail_built.connect(_on_rail_built)
	session.undo.action_expired.connect(_on_action_expired)


func teardown() -> void:
	TestConstruction.dispose(session)
	session = null


func _on_build_failed(reason: String) -> void:
	_build_failed_reasons.append(reason)


func _on_rail_built(_tiles: Array[Vector2i], cost: float) -> void:
	_rail_built_signals += 1
	_rail_built_cost_total += cost


func _on_action_expired(label: String) -> void:
	_expired_labels.append(label)


# --- 3.2 the tool interaction -------------------------------------------------

func test_drag_preview_confirm_lays_exactly_the_previewed_line() -> void:
	# Start: first click picks the start tile.  Hover: the tool previews a plan.
	var plan := session.builder.preview_rail(Vector2i(10, 10), Vector2i(15, 10))
	check_true(bool(plan.get("ok", false)), "hover preview is valid")
	var planned: Array[Vector2i] = plan["tiles"]
	check_eq(TestConstruction.rail_count(session), 0, "previewing changes nothing on the ground")
	check_near(TestConstruction.cash(session), session.economy.opening_balance,
		"previewing spends nothing", 0.001)
	# Confirm: the click commits the very plan the preview showed.
	var built := session.builder.build_rail(Vector2i(10, 10), Vector2i(15, 10))
	check_true(bool(built.get("ok", false)), "confirming the previewed plan builds")
	var committed: Array[Vector2i] = built["tiles"]
	check_eq(committed.size(), planned.size(), "commit lays the number of tiles previewed")
	check_eq(TestConstruction.rail_count(session), planned.size(), "exactly the previewed cells carry rail")
	check_eq(_rail_built_signals, 1, "one rail_built event covers the whole segment")
	check_near(_rail_built_cost_total, float(plan["cost"]), "the event carries the previewed cost", 0.001)


func test_drag_mode_preview_prices_diagonal_steps() -> void:
	# Drag mode draws the run by hand; the preview must price it the way commit
	# will charge it: one straight hop plus one diagonal hop.
	var run: Array[Vector2i] = [Vector2i(20, 20), Vector2i(21, 20), Vector2i(22, 21)]
	var preview := session.builder.preview_track_run(run)
	check_true(bool(preview.get("ok", false)), "a hand-drawn run previews legal")
	check_near(float(preview["cost"]), 950.0 + 1350.0, "drag preview prices the diagonal hop", 0.001)
	var built := session.builder.build_track_run(run)
	check_true(bool(built.get("ok", false)), "the hand-drawn run commits")
	check_near(TestConstruction.cash(session), session.economy.opening_balance - 2300.0,
		"commit charged exactly the previewed run cost", 0.001)


func test_shift_precision_click_lays_exactly_one_tile() -> void:
	# A Shift-style precision click commits the single tile under the cursor.
	# That maps to a one-tile commit through the same preview/commit API.
	var lone: Array[Vector2i] = [Vector2i(40, 40)]
	var preview := session.builder.preview_track_run(lone)
	check_true(bool(preview.get("ok", false)), "precision preview is legal")
	var first := session.builder.build_track_run(lone)
	check_true(bool(first.get("ok", false)), "precision commit accepted")
	check_eq(TestConstruction.rail_count(session), 1, "a precision click lays exactly one tile")
	# A second precision click next to the first extends the line by one tile.
	var next: Array[Vector2i] = [Vector2i(41, 40)]
	var second := session.builder.build_track_run(next)
	check_true(bool(second.get("ok", false)), "second precision commit accepted")
	check_eq(TestConstruction.rail_count(session), 2, "second precision click adds exactly one tile")
	check_true(session.rail.network.has_rail(Vector2i(40, 40)), "the first tile survives")
	check_true(session.rail.network.has_rail(Vector2i(41, 40)), "the second tile exists")
	check_true(session.rail.network.mask(Vector2i(40, 40)) & RailDirections.bit(RailDirections.E) != 0,
		"the pair spliced into a line, not two stray tiles")
	check_true(session.economy.is_consistent(), "ledger still explains the balance")


# --- 3.3 the preview data the renderer consumes --------------------------------

func test_preview_data_carries_validity_length_and_cost() -> void:
	var plan := session.builder.preview_rail(Vector2i(10, 10), Vector2i(15, 10))
	check_true(bool(plan.get("ok", false)), "straight plain run is valid")
	check_eq(int(plan["length"]), 6, "length readout counts tiles")
	check_near(float(plan["cost"]), 5 * 950.0, "cost readout is five straight hops", 0.001)
	check_false(bool(plan["expensive"]), "a straight line is green, not yellow")
	check_true(bool(plan["affordable"]), "affordability is part of the validity state")
	# Detouring a river wall makes the same route legal but expensive — yellow.
	TestConstruction.paint_water_column(session, 30, 0, 15)
	var detour := session.builder.preview_rail(Vector2i(28, 5), Vector2i(32, 5))
	check_true(bool(detour.get("ok", false)), "the planner detours around the wall")
	check_gt(float(detour["cost"]), float(plan["cost"]), "the detour costs more")
	check_true(bool(detour["expensive"]), "a costly detour reads as the yellow state")
	# Without cash it stays valid but unaffordable — the tool shows it as bad.
	session.economy.spend_allowing_deficit(TestConstruction.cash(session) - 1000.0,
		EconomyService.CATEGORY_OPERATING, "test drain")
	var broke := session.builder.preview_rail(Vector2i(10, 10), Vector2i(15, 10))
	check_true(bool(broke.get("ok", false)), "the line itself is still legal")
	check_false(bool(broke["affordable"]), "affordability flips to false when cash runs out")
	check_has(String(broke["warning"]), "Not enough cash", "preview names the money problem verbatim")


func test_invalid_preview_names_the_water_under_the_cursor() -> void:
	TestConstruction.paint_water_column(session, 34, 35, 45)
	var cursor := Vector2i(34, 40)
	var preview := session.builder.preview_rail(Vector2i(30, 40), cursor)
	check_false(bool(preview.get("ok", false)), "a plan ending on water is invalid")
	check_has(String(preview["reason"]), "water", "the reason names the obstruction type")
	check_eq(String(preview["reason"]), session.rail.cell_reason(cursor),
		"the reason is the specific rule for the tile at the cursor, not a generic failure")
	# A hand-drawn run stepping into the same water reports the same specific reason.
	var run: Array[Vector2i] = [Vector2i(32, 40), Vector2i(33, 40), cursor]
	var dragged := session.builder.preview_track_run(run)
	check_false(bool(dragged.get("ok", false)), "drag preview refuses the water step")
	check_eq(String(dragged["reason"]), "Cannot build on water", "drag mode names water too")
	# And commit refuses with the same words.
	session.builder.build_rail(Vector2i(30, 40), cursor)
	check_eq(_build_failed_reasons[_build_failed_reasons.size() - 1], String(preview["reason"]),
		"commit refuses with the preview's own reason")


# --- 3.4 the money path ---------------------------------------------------------

func test_commit_charges_exactly_one_track_transaction() -> void:
	var before := TestConstruction.cash(session)
	var ledger_before := TestConstruction.ledger_size(session)
	var built := session.builder.build_rail(Vector2i(10, 10), Vector2i(14, 10))
	check_true(bool(built.get("ok", false)), "five-cell straight line builds")
	var cost := float(built["cost"])
	check_near(cost, 4 * 950.0, "five cells means four straight hops", 0.001)
	check_eq(TestConstruction.ledger_size(session), ledger_before + 1,
		"one commit is exactly one ledger transaction")
	var track_rows := TestConstruction.live_transactions_in(session, EconomyService.CATEGORY_TRACK)
	check_eq(track_rows.size(), 1, "the single new row is a track-construction row")
	check_near(track_rows[0].amount, -cost, "the row is the negative of the previewed cost", 0.001)
	check_near(TestConstruction.cash(session), before - cost, "cash dropped by exactly the cost", 0.001)
	check_true(session.economy.is_consistent(), "opening balance plus ledger still equals cash")


func test_insufficient_funds_refuses_without_building_anything() -> void:
	session.economy.spend_allowing_deficit(TestConstruction.cash(session) - 1000.0,
		EconomyService.CATEGORY_OPERATING, "test drain")
	var cash_before := TestConstruction.cash(session)
	var ledger_before := TestConstruction.ledger_size(session)
	var preview := session.builder.preview_rail(Vector2i(10, 10), Vector2i(14, 10))
	check_false(bool(preview["affordable"]), "the preview already knows the line is out of reach")
	var failed := session.builder.build_rail(Vector2i(10, 10), Vector2i(14, 10))
	check_false(bool(failed.get("ok", false)), "commit refuses the unaffordable line")
	check_has(String(failed["reason"]), "Not enough cash", "the refusal says why")
	check_eq(TestConstruction.rail_count(session), 0, "the refusal leaves zero rail cells behind")
	check_near(TestConstruction.cash(session), cash_before, "cash is untouched by the refusal", 0.001)
	check_eq(TestConstruction.ledger_size(session), ledger_before, "a refusal writes no ledger row")
	check_eq(_build_failed_reasons.size(), 1, "the refusal was announced once")


# --- 3.5 the remove tool --------------------------------------------------------

func test_remove_refuses_to_lift_the_rail_a_station_uses() -> void:
	var spur := TestSession.lay_spur(session, Vector2i(60, 60))
	check_true(bool(spur["ok"]), "a five-cell spur lays beside the town square")
	var spur_tiles: Array[Vector2i] = spur["tiles"]
	var station_id := TestSession.station_for_tile(session, spur_tiles[2], "Coalgate Halt", false)
	check_true(station_id != 0, "a station accepts the spur for access")
	var access := session.stations.rail_access_tile(station_id)
	check_neq(access, StationService.NO_RAIL_ACCESS, "the station has a rail access tile")
	var refused := session.builder.remove_track([access])
	check_false(bool(refused.get("ok", false)), "removal of the station's access rail is refused")
	check_has(String(refused["reason"]), session.stations.name_of(station_id),
		"the refusal names the station that depends on the rail")
	check_true(session.rail.network.has_rail(access), "the refused tile still carries rail")
	check_true(session.economy.is_consistent(), "a refused removal moves no money")


func test_remove_permits_independent_rail_and_refunds_it() -> void:
	var run := TestConstruction.east_run(Vector2i(10, 12), 3)
	var built := session.builder.build_track_run(run)
	check_true(bool(built.get("ok", false)), "an independent three-cell line lays")
	var cash_after_build := TestConstruction.cash(session)
	var refund_expected := session.builder.refund_for(run)
	var removed := session.builder.remove_track(run)
	check_true(bool(removed.get("ok", false)), "independent rail removes freely")
	check_near(float(removed["refund"]), refund_expected, "refund matches the published formula", 0.001)
	check_near(TestConstruction.cash(session), cash_after_build + refund_expected,
		"the refund landed in cash", 0.001)
	check_eq(TestConstruction.rail_count(session), 0, "the removed cells are gone")
	check_true(session.economy.is_consistent(), "the refund is a ledger row, not a cash edit")


func test_removing_scattered_isolated_stubs_refunds_nothing() -> void:
	# Two lone precision tiles were each laid for free (no hop was priced into
	# them); removing them together must not mint a refund for a hop that
	# never existed between them.
	var first: Array[Vector2i] = [Vector2i(70, 70)]
	var second: Array[Vector2i] = [Vector2i(74, 74)]
	session.builder.build_track_run(first)
	session.builder.build_track_run(second)
	var cash_after_lay := TestConstruction.cash(session)
	var both: Array[Vector2i] = [Vector2i(70, 70), Vector2i(74, 74)]
	var removed := session.builder.remove_track(both)
	check_true(bool(removed.get("ok", false)), "isolated stubs remove together")
	check_near(float(removed["refund"]), 0.0, "no phantom hop is refunded", 0.001)
	check_near(TestConstruction.cash(session), cash_after_lay, "removing free stubs mints no money", 0.001)
	check_true(session.economy.is_consistent(), "the ledger balances after the joint removal")


# --- 3.6 undo --------------------------------------------------------------------

func test_undo_reverses_both_the_track_and_its_ledger_transaction() -> void:
	var opening := TestConstruction.cash(session)
	var ledger_before := TestConstruction.ledger_size(session)
	var built := session.builder.build_rail(Vector2i(10, 10), Vector2i(14, 10))
	var cost := float(built["cost"])
	check_near(TestConstruction.cash(session), opening - cost, "build took its money first", 0.001)
	# Ctrl+Z at the service level: one undo pops the newest command.
	var label := session.undo.undo()
	check_eq(label, "Build 5 tiles of track", "Ctrl+Z pops the newest construction")
	check_eq(TestConstruction.rail_count(session), 0, "undo lifted every rail cell of the command")
	check_near(TestConstruction.cash(session), opening, "undo restored cash to the cent", 0.000001)
	check_eq(TestConstruction.ledger_size(session), ledger_before + 2,
		"the ledger keeps the charge and its explicit reversal, never a rewrite")
	var track_rows := TestConstruction.live_transactions_in(session, EconomyService.CATEGORY_TRACK)
	check_eq(track_rows.size(), 0, "the track charge no longer counts as live")
	check_true(session.economy.is_consistent(), "opening + live ledger still equals cash")
	check_false(session.undo.can_undo(), "an emptied history says there is nothing left to undo")


func test_undo_of_a_later_tile_keeps_the_line_it_joined() -> void:
	var spine := TestConstruction.east_run(Vector2i(20, 30), 3)
	var first := session.builder.build_track_run(spine)
	check_true(bool(first.get("ok", false)), "the original three-cell line lays")
	var cash_before_extension := TestConstruction.cash(session)
	var stub: Array[Vector2i] = [Vector2i(23, 30)]
	var second := session.builder.build_track_run(stub)
	check_true(bool(second.get("ok", false)), "the one-cell extension lays and splices on")
	check_eq(TestConstruction.rail_count(session), 4, "four cells after the extension")
	var label := session.undo.undo()
	check_eq(label, "Build 1 tiles of track", "undo reverses the newest command only")
	check_eq(TestConstruction.rail_count(session), 3, "undo lifted the extension cell")
	check_false(session.rail.network.has_rail(Vector2i(23, 30)), "the extension cell is gone")
	for tile in spine:
		check_true(session.rail.network.has_rail(tile),
			"the older paid-for line survived the undo at " + str(tile))
	check_near(TestConstruction.cash(session), cash_before_extension,
		"cash returned exactly to the pre-extension balance", 0.000001)


func test_undo_history_is_bounded_and_evicts_the_oldest() -> void:
	var limit := session.undo.DEFAULT_DEPTH
	check_eq(limit, 40, "the bounded history depth found in UndoService is 40")
	# A unique first command, then enough one-cell precision commits to overflow it.
	var lead := session.builder.build_track_run(TestConstruction.east_run(Vector2i(5, 100), 5))
	check_true(bool(lead.get("ok", false)), "the unique lead command committed")
	for tile in TestConstruction.scattered_tiles(Vector2i(2, 110), 41, 2):
		var single: Array[Vector2i] = [tile]
		session.builder.build_track_run(single)
	check_eq(session.undo.depth(), limit, "pushing 41 further commands still holds only 40")
	check_eq(_expired_labels.size(), 2, "exactly two commands aged out of the window")
	check_eq(_expired_labels[0], "Build 5 tiles of track",
		"the oldest command is the first to be evicted")
	for label in _expired_labels:
		check_neq(label, "", "evictions are announced with their label")


func test_undo_after_eviction_and_redo_is_refused_safely() -> void:
	session.builder.build_track_run(TestConstruction.east_run(Vector2i(5, 100), 5))
	for tile in TestConstruction.scattered_tiles(Vector2i(2, 110), 41, 2):
		var single: Array[Vector2i] = [tile]
		session.builder.build_track_run(single)
	# Drain the surviving window; the evicted command must never come back.
	var popped_anything := false
	for _step in 40:
		var label := session.undo.undo()
		if label == "Build 5 tiles of track":
			popped_anything = true
		check_neq(label, "Build 5 tiles of track",
			"the evicted command can never be undone again")
	check_false(popped_anything, "no undo ever replayed the evicted command")
	check_eq(TestConstruction.rail_count(session), 6,
		"only the evicted commands' rail is still standing: the 5-tile line and one evicted tile")
	check_false(session.undo.can_undo(), "the window is drained")
	# Redo does not exist, so there is nothing to redo: the service must refuse
	# the empty stack safely rather than crash.
	check_false(session.undo.has_method("redo"), "no redo channel exists to misuse")
	check_eq(session.undo.undo(), "", "undo on the empty stack is a safe no-op")
	session.undo.clear()
	check_eq(session.undo.depth(), 0, "clear empties the stack")
	check_eq(session.undo.undo(), "", "undo after clear is still a safe no-op")


func test_removal_is_undoable_and_rebuilds_the_line_and_the_money() -> void:
	var run := TestConstruction.east_run(Vector2i(10, 12), 3)
	session.builder.build_track_run(run)
	var cash_after_build := TestConstruction.cash(session)
	var removed := session.builder.remove_track(run)
	var refund := float(removed["refund"])
	check_true(bool(removed.get("ok", false)), "the removal went through")
	check_near(TestConstruction.cash(session), cash_after_build + refund, "refund paid", 0.001)
	var label := session.undo.undo()
	check_eq(label, "Remove 3 tiles of track", "undo pops the removal")
	check_eq(TestConstruction.rail_count(session), 3, "the lifted line is back")
	check_true(session.rail.network.is_straight(Vector2i(11, 12)),
		"the restored line reconnected as a through line")
	check_near(TestConstruction.cash(session), cash_after_build,
		"undoing the removal clawed the refund back to the cent", 0.000001)
	check_true(session.economy.is_consistent(), "the ledger still balances the books")


# --- 5.1 the whole loop --------------------------------------------------------

func test_integration_drag_commit_preview_invalid_undo_returns_everything() -> void:
	# Varied terrain: plain, a one-step plateau the route must climb, and a
	# river the invalid preview will walk into.
	TestConstruction.set_height_column(session, 10, 0, 40, 1)
	TestConstruction.set_height_column(session, 11, 0, 40, 1)
	TestConstruction.paint_water_column(session, 20, 15, 25)
	var renderer := RailRenderer.new()
	renderer.attach(session.world, session.rail)
	var rail0 := TestConstruction.rail_count(session)
	var cash0 := TestConstruction.cash(session)
	var ledger0 := TestConstruction.ledger_size(session)
	var rebuilds0 := renderer.rebuild_count()
	renderer.tick()
	# Drag the route: hover preview across the plain and up the climb.
	var plan := session.builder.preview_rail(Vector2i(6, 20), Vector2i(16, 20))
	check_true(bool(plan.get("ok", false)), "the climb route is legal")
	var expected_cells := int(plan["length"])
	check_gt(expected_cells, 10, "the route spans the climb")
	var cost := float(plan["cost"])
	check_gt(cost, 10 * 950.0, "the climb surcharges above ten flat hops")
	# Commit it.
	var built := session.builder.build_rail(Vector2i(6, 20), Vector2i(16, 20))
	check_true(bool(built.get("ok", false)), "the climbed route commits")
	check_eq(TestConstruction.rail_count(session) - rail0, expected_cells, "the planned cells exist")
	# The renderer follows: dirty chunks only.
	var rebuilds_after_build := renderer.rebuild_count()
	check_le(float(rebuilds_after_build - rebuilds0), 4.0, "commit dirtied at most a local chunk set")
	renderer.tick()
	# Preview the invalid case walking into the river at the cursor.
	var cursor := Vector2i(20, 20)
	var bad := session.builder.preview_rail(Vector2i(16, 20), cursor)
	check_false(bool(bad.get("ok", false)), "the river preview is refused")
	check_has(String(bad["reason"]), "water", "the refusal names the water at the cursor")
	renderer.show_ghost(TestConstruction.east_run(cursor, 1), "invalid")
	check_eq(renderer.ghost_tiles().size(), 1, "the ghost shows the blocked footprint")
	renderer.hide_ghost()
	# Committing that invalid route must refuse without touching the ground.
	var refused := session.builder.build_rail(Vector2i(16, 20), cursor)
	check_false(bool(refused.get("ok", false)), "the invalid commit is refused")
	check_eq(TestConstruction.rail_count(session), rail0 + expected_cells,
		"the refused invalid attempt never touched the ground")
	# Ctrl+Z the whole construction.
	var label := session.undo.undo()
	check_has(label, "Build", "the undo popped the construction")
	renderer.tick()
	renderer.tick()
	check_eq(TestConstruction.rail_count(session), rail0, "the rail is exactly back where it started")
	check_near(TestConstruction.cash(session), cash0, "cash is exactly back where it started", 0.000001)
	check_eq(TestConstruction.ledger_size(session), ledger0 + 2,
		"the ledger keeps the charge plus its reversal and nothing else")
	var rebuild_delta := renderer.rebuild_count() - rebuilds0
	check_ge(float(rebuild_delta), 2.0, "both the commit and the undo reached the renderer")
	check_le(float(rebuild_delta), 8.0,
		"rebuilds stayed inside the affected chunk set, never the whole world")
	check_true(session.economy.is_consistent(), "and the books still balance at the end")
	renderer.free()


func test_a_single_cell_is_charged_like_any_other_track() -> void:
	## Track is priced by the hop between two cells, so a lone cell had no hop to
	## price — and was free.  The moment precision building can lay one cell at a
	## time, free means a railway for nothing, so a cell pays the straight rate.
	var lone: Array[Vector2i] = [Vector2i(60, 60)]
	check_near(session.builder.run_cost(lone), 950.0, "a single cell is priced at the straight rate")
	var preview := session.builder.preview_track_run(lone)
	check_near(float(preview["cost"]), 950.0, "and the ghost says so before the click", 0.001)
	var spent := TestConstruction.cash(session)
	var built := session.builder.build_track_run(lone)
	check_true(bool(built.get("ok", false)), "the cell is laid: " + String(built.get("reason", "")))
	check_near(TestConstruction.cash(session), spent - 950.0, "and the ledger charged for it", 0.001)

	var removed := session.builder.remove_track(lone)
	check_true(bool(removed.get("ok", false)), "and it can be lifted again")
	check_near(float(removed["refund"]), 475.0, "a lifted cell pays back half its price", 0.001)

	## Laying two cells one at a time must never come out cheaper than laying them
	## together, or the tool would teach players to game its own pricing.
	var together: Array[Vector2i] = [Vector2i(70, 70), Vector2i(71, 70)]
	var apart := session.builder.run_cost(lone) + session.builder.run_cost([Vector2i(71, 70)])
	check_ge(apart, session.builder.run_cost(together),
		"two precision cells cost at least what one drag of the same two costs")

	## The other side of the same rule: a tile set that is not a run has no hops
	## to price, and must not be priced as though it had — that is how a removal
	## would start paying out money that was never paid in.
	var scattered: Array[Vector2i] = [Vector2i(80, 80), Vector2i(90, 80)]
	check_near(session.builder.run_cost(scattered), 0.0,
		"a scattered set of cells is priced at nothing, not at an invented hop", 0.001)
	check_true(session.economy.is_consistent(), "and the ledger still explains every cent")
