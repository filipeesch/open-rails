# Tasks

## 1. Rail data and graph

- [x] 1.1 Implement the eight-direction connection bitmask over `WorldGrid.rail` with reciprocal-link maintenance, and verify adding an east connection creates the neighbour's west connection
- [x] 1.2 Implement rail cell iteration and neighbour derivation purely from the mask, and verify a derived graph matches a hand-authored connection set
- [x] 1.3 Implement `can_connect` returning a typed rejection reason covering water, occupied land, excessive slope and out-of-bounds, and verify each reason is distinguishable in a test
- [x] 1.4 Implement the slope rule allowing at most one height step between adjacent connected cells, and verify a one-step climb passes and a two-step climb fails with the slope reason
- [x] 1.5 Implement junction detection for cells with three or more connections and verify every branch is offered to a traversal, and verify grade separation is not representable
- [x] 1.6 Implement A* pathfinding over the rail graph with reachability queries, and verify a disconnected query reports no path and an L-shaped line returns only existing connections
- [x] 1.7 Emit `track_changed` with the affected tile list on every commit, and verify one event covers a whole multi-tile segment

## 2. Construction planner

- [x] 2.1 Implement the tile-lattice A* planner with terrain cost, slope penalty, turn penalty and reuse bonus, and verify a cheaper-turn plan wins at equal length
- [x] 2.2 Implement reuse of existing rail so a plan joins the network instead of duplicating it, and verify no parallel duplicate track is proposed
- [x] 2.3 Cache plan results against start, goal and network revision and verify hovering the same tile twice performs no new search
- [x] 2.4 Implement the invalid-path case returning the principal obstruction reason, and verify a water-crossing plan reports water

## 3. Construction tool and economy

- [x] 3.1 Implement minimal `EconomyService` with cash, spend, refund, ledger entries and an insufficient-funds reason, and verify the ledger sum equals cash after a series of charges
- [x] 3.2 Implement the rail tool's start-drag-preview-confirm interaction with Shift single-tile precision mode, and verify a Shift click places exactly one tile
- [x] 3.3 Implement the rail preview renderer with green, yellow and red validity colouring plus length and cost readout, and verify an invalid route shows its specific reason adjacent to the cursor
  Completed later, in `add-map-economy-sources` 3.2: the preview renderer had a `show_ghost` nobody called, so the shipped game drew no rail ghost at all.  `RailRenderer.attach_build_controller(input)` connects the tool's own signals (and yields the ground to `StationGhost` while the station tool is in hand), and the declared-but-unused `ghost_material` is now on the ghost node — without a vertex-colour material the green/yellow/red verdict was baked into vertices nothing read.  Proved by `tests/test_build_tools.gd::test_the_rail_ghost_is_drawn_in_the_world_in_the_domain_s_own_colour`, which reads the ghost's first vertex colour for both the legal green and the refused red.
- [x] 3.4 Implement commit that charges one track-construction transaction through `EconomyService` and refuses on insufficient funds without building, and verify both paths
- [x] 3.5 Implement the Remove tool with protection for rail a station depends on, and verify a dependent removal is refused naming the station
- [x] 3.6 Implement `UndoService` command pairs reversing construction and its ledger transaction on `Ctrl+Z` with a bounded history, and verify undo restores both track and cash

## 4. Track rendering

- [x] 4.1 Implement the connection-mask to track-piece lookup covering straight, diagonal, 45 and 90 degree curves, junction and slope pieces, and verify representative masks select the expected piece
  `TrackPieces` (presentation) is the one reader of the mask: `piece_for(mask, rise)` answers
  `straight / diagonal / curve_45 / curve_90 / junction / slope`, plus the two cases §36 left
  implicit (`end` for a single arm, `empty` for none). The renderer no longer enumerates bits
  by hand — it emits `TrackPieces.halves_for(mask)` and keeps a per-chunk census, so
  `piece_of(tile)`, `piece_counts()` and geometry (10 triangles per half) are three readings
  of one table. Junction beats slope beats shape; a buffer stop stays a stop on a hill.
- [x] 4.2 Batch pieces per chunk into `MultiMeshInstance3D` sets and verify a 500-tile railway's node count scales with chunks not tiles
- [x] 4.3 Rebuild only dirty chunks on track change and verify a rebuild counter stays within the affected chunk set
- [x] 4.4 Position pieces at terrain elevation with slope pieces bridging their endpoint heights, and verify no piece intersects the terrain on a climb
- [x] 4.5 Verify identical connection sets built through different code paths produce identical piece selection

## 5. Verification

- [x] 5.1 Add a headless construction test that drags a route across varied terrain, commits, previews an invalid case and undoes, and verify track, cash and chunk rebuild counters all return to expectations
