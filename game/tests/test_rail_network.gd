class_name TestRailNetwork
extends TestBase

## The rail graph is a bitmask per cell, and the rules that decide a cell are
## the rules the builder must not be able to route around. Pure domain: no
## nodes, no UI, no shipped map.

const STRAIGHT_COST := 950.0
const DIAGONAL_COST := 1350.0

var world: WorldGrid
var rail: RailService
var planner: RailPlanner
var data: DataRegistry


func setup() -> void:
	world = TestWorldFactory.blank(24, 24)
	data = DataRegistry.new()
	data.load_all()
	rail = RailService.new()
	rail.attach(world)
	planner = RailPlanner.new()
	planner.attach(world, rail, data)


# --- bitmask graph --------------------------------------------------------

func test_connecting_sets_both_cells() -> void:
	var a := Vector2i(5, 5)
	var b := Vector2i(4, 5)
	check_true(rail.network.connect_direction(a, RailDirections.W), "A links west")
	check_eq(rail.network.mask(a), RailDirections.bit(RailDirections.W), "A holds the west bit")
	check_eq(rail.network.mask(b), RailDirections.bit(RailDirections.E), "B holds the mirrored east bit")
	check_eq(rail.network.connection_count(a), 1, "A reports one connection")


func test_disconnect_clears_both_halves() -> void:
	var a := Vector2i(5, 5)
	var b := Vector2i(4, 5)
	rail.network.connect_direction(a, RailDirections.W)
	rail.network.disconnect_direction(a, RailDirections.W)
	check_eq(rail.network.mask(a), 0, "A's bit cleared")
	check_eq(rail.network.mask(b), 0, "B's mirrored bit cleared too")
	check_eq(rail.network.connected_tiles(a).size(), 0, "A has no neighbours left")


func test_remove_cell_orphans_neighbours() -> void:
	rail.commit_segment([Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6)])
	check_eq(rail.rail_tiles().size(), 3, "three cells of rail")
	var removed := rail.remove_cells([Vector2i(7, 6)])
	check_true(bool(removed["ok"]), "removal allowed")
	check_eq(rail.rail_tiles().size(), 2, "one cell removed")
	check_eq(rail.network.mask(Vector2i(6, 6)), 0, "left stub no longer points east")
	check_eq(rail.network.mask(Vector2i(8, 6)), 0, "right stub no longer points west")
	check_eq(world.occupancy_at(Vector2i(7, 6)), WorldGrid.Occupancy.NONE, "occupancy released")


func test_junction_curve_and_straight_classification() -> void:
	var hub := Vector2i(10, 10)
	rail.network.connect_direction(hub, RailDirections.N)
	check_false(rail.network.is_straight(hub), "a lone connection is a stub, not a through line")
	check_false(rail.network.is_curve(hub), "a lone connection is not a curve")
	check_false(rail.network.is_junction(hub), "a lone connection is not a junction")
	check_true(rail.network.has_rail(hub), "a stub is still a cell of the network")
	rail.network.connect_direction(hub, RailDirections.S)
	check_true(rail.network.is_straight(hub), "two opposite connections are straight")
	check_false(rail.network.is_junction(hub), "a straight line is not a junction")
	rail.network.connect_direction(hub, RailDirections.E)
	check_true(rail.network.is_junction(hub), "three connections form a junction")
	rail.network.remove_cell(hub)
	rail.network.connect_direction(hub, RailDirections.N)
	rail.network.connect_direction(hub, RailDirections.E)
	check_true(rail.network.is_curve(hub), "two perpendicular connections are a curve")


# --- terrain and grade rules ---------------------------------------------

func test_water_blocks_rail() -> void:
	var river := TestWorldFactory.with_water_column()
	var dry := RailService.new()
	dry.attach(river)
	check_eq(dry.cell_reason(Vector2i(12, 12)), "Cannot build on water", "water names its blocker")
	check_eq(dry.cell_reason(Vector2i(11, 12)), "", "dry ground beside it is buildable")


func test_rock_accepts_rail() -> void:
	world.terrain[world.index_of(Vector2i(3, 3))] = WorldGrid.Terrain.ROCK
	check_eq(rail.cell_reason(Vector2i(3, 3)), "", "rock is buildable — it only costs more")


func test_one_step_slope_is_allowed() -> void:
	var hill := TestWorldFactory.with_slope()
	var ramp := RailService.new()
	ramp.attach(hill)
	check_true(ramp.network.slope_ok(Vector2i(11, 8), Vector2i(12, 8)), "one height step is one grade")
	check_eq(ramp.network.slope_delta(Vector2i(11, 8), Vector2i(12, 8)), 1, "the step is one")


func test_cliff_blocks_rail() -> void:
	var escarpment := TestWorldFactory.with_cliff()
	var wall := RailService.new()
	wall.attach(escarpment)
	check_false(wall.network.slope_ok(Vector2i(11, 8), Vector2i(12, 8)), "a four-step cliff is impassable")
	check_true(wall.can_connect(Vector2i(11, 8), RailDirections.E).contains("Grade"), "and says why")


# --- connectivity ---------------------------------------------------------

func test_paths_walk_a_junction() -> void:
	rail.commit_segment([Vector2i(4, 8), Vector2i(5, 8), Vector2i(6, 8)])
	rail.commit_segment([Vector2i(5, 8), Vector2i(5, 9), Vector2i(5, 10)])
	var path := rail.find_path(Vector2i(4, 8), Vector2i(5, 10))
	check_eq(path.size(), 4, "four tiles through the junction")
	check_eq(path[1], Vector2i(5, 8), "the junction is crossed, not skipped")
	check_true(rail.is_reachable(Vector2i(4, 8), Vector2i(5, 10)), "reachable through the junction")
	check_false(rail.is_reachable(Vector2i(4, 8), Vector2i(20, 20)), "unbuilt ground is unreachable")
	check_eq(rail.reachable_from(Vector2i(4, 8)).size(), 5, "the whole network is five tiles")


func test_disconnected_networks_are_not_reachable() -> void:
	rail.commit_segment([Vector2i(2, 2), Vector2i(3, 2)])
	rail.commit_segment([Vector2i(6, 5), Vector2i(7, 5)])
	check_false(rail.is_reachable(Vector2i(2, 2), Vector2i(7, 5)), "separate networks stay separate")
	check_eq(rail.rail_tiles().size(), 4, "four cells of rail laid")
	var jump := rail.build_segment([Vector2i(3, 2), Vector2i(9, 9)])
	check_false(bool(jump["ok"]), "a segment may not teleport across the valley")
	check_has(String(jump["reason"]), "non-adjacent", "and it explains the refusal")
	check_eq(rail.rail_tiles().size(), 4, "a refused segment lays nothing down")
	rail.commit_segment([Vector2i(3, 2), Vector2i(4, 3), Vector2i(5, 4), Vector2i(6, 5)])
	check_true(rail.is_reachable(Vector2i(2, 2), Vector2i(7, 5)), "one continuous link joins them")


func test_revision_bumps_on_mutation() -> void:
	var before := rail.revision()
	rail.commit_segment([Vector2i(9, 9), Vector2i(10, 9)])
	check_neq(rail.revision(), before, "track_changed bumps the revision counter")


func test_track_signals_fire() -> void:
	var changes := {"added": 0, "removed": 0}
	rail.track_changed.connect(func(tiles: Array[Vector2i]) -> void: changes["added"] += tiles.size())
	rail.track_removed.connect(func(tiles: Array[Vector2i]) -> void: changes["removed"] += tiles.size())
	rail.commit_segment([Vector2i(14, 4), Vector2i(15, 4)])
	check_eq(int(changes["added"]), 2, "builders hear about new track")
	rail.remove_cells([Vector2i(14, 4), Vector2i(15, 4)])
	check_gt(int(changes["removed"]), 0, "builders hear about removed track too")


# --- planner --------------------------------------------------------------

func test_planner_prefers_cheap_straight_rail() -> void:
	var plan := planner.plan(Vector2i(6, 6), Vector2i(6, 16))
	check_true(bool(plan["ok"]), "a route exists")
	check_eq((plan["tiles"] as Array).size(), 11, "an eleven-tile run")
	check_near(float(plan["cost"]), 10.0 * STRAIGHT_COST, "ten straight segments billed", 0.01)


func test_planner_uses_diagonals_when_cheaper() -> void:
	var plan := planner.plan(Vector2i(6, 6), Vector2i(10, 10))
	check_true(bool(plan["ok"]), "diagonal route found")
	check_eq((plan["tiles"] as Array).size(), 5, "four diagonal hops")
	check_near(float(plan["cost"]), 4.0 * DIAGONAL_COST, "diagonals beat the longer orthogonal stair", 0.01)


func test_planner_avoids_impassible_grade() -> void:
	var escarpment := TestWorldFactory.with_cliff()
	var wall := RailService.new()
	wall.attach(escarpment)
	var climber := RailPlanner.new()
	climber.attach(escarpment, wall, data)
	check_false(bool(climber.plan(Vector2i(11, 12), Vector2i(13, 12))["ok"]), "the cliff is not crossable head-on")
	check_true(bool(climber.plan(Vector2i(5, 12), Vector2i(6, 12))["ok"]), "flat ground still plans")


func test_planner_reports_unreachable() -> void:
	var river := TestWorldFactory.with_water_column()
	var crossing := RailService.new()
	crossing.attach(river)
	var ferry := RailPlanner.new()
	ferry.attach(river, crossing, data)
	var plan := ferry.plan(Vector2i(8, 12), Vector2i(16, 12))
	check_false(bool(plan["ok"]), "no route across a river with no ford")
	check_neq(String(plan["reason"]), "", "and the player is told why")


func test_planner_caches_per_revision() -> void:
	var before := planner.search_calls()
	planner.plan(Vector2i(6, 6), Vector2i(9, 6))
	check_eq(planner.search_calls(), before + 1, "the first plan searches")
	planner.plan(Vector2i(6, 6), Vector2i(9, 6))
	check_eq(planner.search_calls(), before + 1, "the second plan is served from cache")
	rail.commit_segment([Vector2i(4, 4), Vector2i(4, 5)])
	planner.plan(Vector2i(6, 6), Vector2i(9, 6))
	check_eq(planner.search_calls(), before + 2, "editing track invalidates the cache")


func test_planner_marks_expensive_detours() -> void:
	var riverbend := TestWorldFactory.with_water_wall(24, 24, 10, 0, 17)
	var crossing := RailService.new()
	crossing.attach(riverbend)
	var ferry := RailPlanner.new()
	ferry.attach(riverbend, crossing, data)
	var cheap := ferry.mark_expensive(ferry.plan(Vector2i(6, 6), Vector2i(8, 6)))
	check_false(bool(cheap["expensive"]), "a direct route is not flagged")
	var detour := ferry.mark_expensive(ferry.plan(Vector2i(8, 12), Vector2i(12, 12)))
	check_true(bool(detour["ok"]), "the river is passable by going around")
	check_true(bool(detour["expensive"]), "but the long way is flagged for the yellow ghost")


func test_relaying_a_lifted_section_rejoins_the_line() -> void:
	## Lifting a section and putting it back has to restore the line, not leave a
	## pair of dead ends facing the stubs it was cut from.
	rail.commit_segment([Vector2i(4, 6), Vector2i(5, 6), Vector2i(6, 6), Vector2i(7, 6)])
	check_true(rail.is_reachable(Vector2i(4, 6), Vector2i(7, 6)), "the line starts whole")
	var gap: Array[Vector2i] = [Vector2i(5, 6), Vector2i(6, 6)]
	check_true(bool(rail.remove_cells(gap)["ok"]), "the middle can be lifted")
	check_false(rail.is_reachable(Vector2i(4, 6), Vector2i(7, 6)), "and the line is broken")
	check_eq(rail.reachable_from(Vector2i(4, 6)).size(), 1, "only the stub is left standing")
	check_true(bool(rail.commit_segment(gap)["ok"]), "the same ground can be relaid")
	check_true(rail.is_reachable(Vector2i(4, 6), Vector2i(7, 6)), "and the line carries trains again")
	check_eq(rail.reachable_from(Vector2i(4, 6)).size(), 4, "with nothing lost in the splice")
	check_true(rail.reachable_tiles(Vector2i(4, 6)).has(Vector2i(7, 6)),
			"the tile-keyed flood finds the far stub — route reachability asks it by tile")
	check_true(rail.network.mask(Vector2i(4, 6)) & RailDirections.bit(RailDirections.E) != 0,
			"the joint is a real connection, not two cells sharing an edge")


func test_corner_contact_between_two_lines_is_not_a_junction() -> void:
	## Two lines that only graze at a corner must stay separate: a train may not
	## slip diagonally past the cell it ought to turn through.
	rail.commit_segment([Vector2i(4, 8), Vector2i(5, 8), Vector2i(6, 8)])
	rail.commit_segment([Vector2i(5, 9), Vector2i(5, 10)])
	check_true(rail.network.has_rail(Vector2i(6, 8)), "the first line is laid")
	check_true(rail.network.has_rail(Vector2i(5, 9)), "and the second touches it at a corner")
	check_false(rail.network.mask(Vector2i(6, 8)) & RailDirections.bit(RailDirections.SW) != 0,
			"no diagonal joint was forged between them")
	var path := rail.find_path(Vector2i(6, 8), Vector2i(5, 10))
	check_eq(path.size(), 4, "the way round still goes through the corner cell")
	check_eq(path[1], Vector2i(5, 8), "step by step, not diagonally past it")


func test_every_way_a_cell_refuses_rail_names_its_own_reason() -> void:
	## Four different refusals, four different sentences.  A player who is told
	## "cannot build here" with no cause cannot act on it, and the ghost would be
	## reduced to shrugging.
	var river := TestWorldFactory.with_water_column()
	var svc := RailService.new()
	svc.attach(river)
	check_eq(svc.cell_reason(Vector2i(-1, 5)), "Outside the map", "the edge of the valley says edge")
	check_eq(svc.cell_reason(Vector2i(12, 12)), "Cannot build on water", "a river says water")
	river.set_occupancy(Vector2i(5, 5), WorldGrid.Occupancy.STATION, 7)
	check_has(svc.cell_reason(Vector2i(5, 5)).to_lower(), "station", "a platform says platform")
	river.set_occupancy(Vector2i(6, 5), WorldGrid.Occupancy.INDUSTRY, 9)
	check_has(svc.cell_reason(Vector2i(6, 5)).to_lower(), "industry", "and a works says works")
	var cliff := TestWorldFactory.with_cliff()
	var wall := RailService.new()
	wall.attach(cliff)
	check_has(wall.can_connect(Vector2i(11, 8), RailDirections.E), "Grade", "a cliff says grade")
	var reasons := {}
	reasons[svc.cell_reason(Vector2i(-1, 5))] = true
	reasons[svc.cell_reason(Vector2i(12, 12))] = true
	reasons[svc.cell_reason(Vector2i(5, 5))] = true
	reasons[svc.cell_reason(Vector2i(6, 5))] = true
	check_eq(reasons.size(), 4, "and no two of them are the same sentence")


func test_a_plan_lays_hands_on_the_line_it_meets_rather_than_beside_it() -> void:
	## A route that runs alongside track the player already paid for is a route
	## that charges them twice for one railway.  A plan crossing an existing line
	## is expected to walk it, at the reuse price.
	var run: Array[Vector2i] = []
	for x in range(4, 13):
		run.append(Vector2i(x, 10))
	rail.commit_segment(run)
	var plan := planner.plan(Vector2i(4, 10), Vector2i(12, 10))
	check_true(bool(plan["ok"]), "the existing line answers the query: " + String(plan["reason"]))
	var planned: Array[Vector2i] = plan["tiles"]
	check_gt(float(planned.size()), 8.0, "the plan is the length of the line, not a shortcut")
	var duplicates := 0
	for tile in planned:
		if not rail.network.has_rail(tile):
			duplicates += 1
	check_eq(duplicates, 0, "no cell is proposed that the line does not already hold")
	check_lt(float(plan["cost"]), float(planned.size()) * STRAIGHT_COST,
		"and rail already in the ground is not charged for again at the full rate")


func test_a_crossing_is_one_cell_with_four_ways_because_nothing_passes_over_anything() -> void:
	## V1 has no bridges and no tunnels, so the only answer to two lines meeting
	## is a junction: one cell, one mask, four connections.  A second layer per
	## cell would be the beginning of grade separation, and there is nowhere to
	## put it — the network is a byte per cell.
	check_eq(world.rail.size(), world.total_tiles(), "one byte of rail per cell, and no more")
	var east_west: Array[Vector2i] = []
	var north_south: Array[Vector2i] = []
	for x in range(8, 14):
		east_west.append(Vector2i(x, 10))
	for y in range(8, 14):
		north_south.append(Vector2i(10, y))
	rail.commit_segment(east_west)
	rail.commit_segment(north_south)
	var cross := Vector2i(10, 10)
	var mask := rail.network.mask(cross)
	var ways := 0
	for direction in 8:
		if mask & RailDirections.bit(direction) != 0:
			ways += 1
	check_eq(ways, 4, "the meeting point carries all four connections in one mask")
	check_true(rail.network.is_junction(cross), "and the graph calls it a junction")


func test_laying_rail_through_a_wood_cuts_the_trees_it_runs_over() -> void:
	## Scenery has no owner, no economics and no player intent behind it, so
	## construction displaces it — otherwise a tree keeps drawing through the
	## ballast.  A town, industry or station owns its ground and is refused
	## upstream, which is why only the scenery kind is displaced here.
	var line: Array[Vector2i] = [Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6)]
	world.set_occupancy(Vector2i(7, 6), WorldGrid.Occupancy.SCENERY, 1)
	world.set_occupancy(Vector2i(9, 6), WorldGrid.Occupancy.SCENERY, 1)
	world.set_occupancy(Vector2i(7, 7), WorldGrid.Occupancy.INDUSTRY, 4242)

	rail.commit_segment(line)

	check_eq(world.occupancy_at(Vector2i(7, 6)), WorldGrid.Occupancy.RAIL, "the tree under the rail is gone")
	check_eq(world.occupancy_entity(Vector2i(7, 6)), 0, "and no scenery code points at the ballast")
	check_eq(world.occupancy_at(Vector2i(6, 6)), WorldGrid.Occupancy.RAIL, "bare ground is recorded as rail too")
	check_eq(world.occupancy_at(Vector2i(9, 6)), WorldGrid.Occupancy.SCENERY, "the tree beside the line stands")
	check_eq(world.occupancy_entity(Vector2i(7, 7)), 4242, "and owned ground is never touched by a rail commit")
	check_true(rail.network.has_rail(Vector2i(7, 6)), "the cell is rail in the graph as well as in occupancy")
