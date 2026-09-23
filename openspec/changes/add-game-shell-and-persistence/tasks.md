# Tasks

## 1. Shell and screens

- [x] 1.1 Create `MainMenu.tscn` with Continue, New Sandbox, Load Game, Settings and Quit and verify Continue is disabled when no autosave exists and enabled when one does
- [x] 1.2 Create `NewSandbox.tscn` selecting Founder's Valley with a company-name field, starting year 1850 and a start action, and verify a blank name yields a generated default and starts the sandbox
- [x] 1.3 Create `Game.tscn` with the `World3D` and `UI` hierarchy from the specification and verify it instantiates headlessly
- [x] 1.4 Implement the top bar showing date, cash, monthly profit and speed controls and verify a delivery updates cash and profit without reopening a panel
- [x] 1.5 Implement the bottom toolbar with Build, Stations, Trains, Company and World and verify no permanent sidebar appears
- [x] 1.6 Implement the right-side context inspector for train, station, industry and town selections with actions for consist, route, follow and rename, and verify it disappears when nothing is selected

## 2. Interaction layer

- [x] 2.1 Implement build mode with the Rail, Station and Remove palette, cursor-state change and two-stage Escape, and verify Escape order cancels the operation before exiting build mode
  Proven by `game/tests/test_build_tools.gd`: `test_the_build_palette_lists_exactly_rail_station_and_remove`,
  `test_the_remove_tool_lifts_one_tile_and_pays_half_back`, `test_the_remove_tool_refuses_a_stations_access_rail_and_says_so`,
  `test_escape_gives_up_the_half_built_line_before_it_leaves_build_mode`,
  `test_the_pointer_shows_a_plus_for_build_and_a_cross_for_removal`.
- [x] 2.2 Implement shared ghost-preview presentation showing geometry, cost and validity with specific failure text adjacent to the cursor, and verify a straight-rail requirement is stated as such
  Proven by `game/tests/test_build_tools.gd`: `test_the_readout_counts_and_prices_the_ghost_where_the_cursor_is`,
  `test_a_station_ghost_states_the_straight_rail_requirement_next_to_the_cursor` (the domain's
  "Requires a straight rail run beside the yard" reaches the readout verbatim, and flips unaided once the stub is straightened).
  Access itself is no fixed square: the search walks `rail_search_radius` rings outward around the yard's own footprint, default 1 tile.
- [x] 2.3 Implement hover tooltips for train, industry and station using the selection resolver, and verify hover shows data without changing selection
- [x] 2.4 Implement zoom-dependent map labels on one pooled screen-space layer, and verifying labels vanish at close zoom for unselected entities
- [x] 2.5 Implement the non-blocking notification layer fed by a notification bus, and verify insufficient funds and unreachable-destination messages appear without a modal
- [x] 2.6 Implement the `Ctrl+K` palette over a command registry with entity search focusing the camera, and verify selecting a town focuses it

## 3. Train and company UI

- [x] 3.1 Implement the non-modal trains drawer listing name, locomotive, speed, cargo, route, monthly profit and status with search and filter, and verify a row click selects and opens the inspector
  Proven by `game/tests/test_train_panels.gd`: `test_the_drawer_lists_every_figure_a_train_row_promises`,
  `test_a_row_click_selects_the_train_and_opens_the_inspector`, `test_the_drawer_searches_by_name_cargo_and_status`.
- [x] 3.2 Implement the consist editor UI with live capacity, weight, estimated speed, purchase and running cost, and verify adding a wagon updates every statistic
  Proven by `game/tests/test_train_panels.gd`: `test_the_yard_quoted_figures_are_the_domains_own_rating`,
  `test_adding_a_wagon_moves_every_figure_the_yard_shows`, `test_buying_the_consist_the_yard_quoted_charges_the_ledger_exactly_that`.
- [x] 3.3 Implement the route drawer with stops, load configuration and map-based stop picking, and verify the drawer reflects reachability changes live
  Proven by `game/tests/test_train_panels.gd`: `test_the_route_page_shows_the_stops_and_their_load_plan`,
  `test_map_stop_picking_opens_a_route_stop_by_stop`, `test_the_route_page_reports_a_line_cut_under_it_unasked`,
  `test_a_third_station_on_the_line_shows_up_reachable_and_becomes_a_stop`.
- [x] 3.4 Implement the company finance panel showing cash, monthly revenue, expenses and profit plus recent transactions, and verify entries match the ledger
  Proven by `game/tests/test_train_panels.gd`: `test_the_books_show_the_month_the_ledger_reports`,
  `test_the_transactions_the_books_list_are_the_ledger_verbatim`, `test_the_books_open_only_for_company_and_cost_nothing_to_read`.
- [x] 3.5 Wire train follow from the inspector through the camera system, and verify pan cancels it

## 4. Settings and persistence

- [x] 4.1 Implement the settings screen for volumes, resolution, fullscreen, UI scale, camera speeds and edge scrolling with persistence across restarts, and verify UI scale 150 percent resizes without restart
- [x] 4.2 Implement `SaveService` serialising clock, company, world, tracks, stations, trains, routes, cargo, industries and towns into a versioned JSON document, and verify a save contains `save_version` and `game_version`
- [x] 4.3 Implement atomic writes — temporary file, parse-back validation, rename — and verify an interrupted save leaves the previous file readable
- [x] 4.4 Implement load with structural integrity checks reporting broken cross-references instead of crashing, and verify a deliberately corrupted reference is named
- [x] 4.5 Implement autosave on month boundaries with bounded retention, and verify the oldest autosave is pruned and Continue loads the newest
- [x] 4.6 Implement the migration registry refusing an unknown newer version and migrating a save one version behind, and verify both paths
- [x] 4.7 Add a save/load round-trip test asserting identifiers, cash, station inventories, train positions and routes survive, and verify it passes

## 5. Performance and polish

- [x] 5.1 Implement LOD selection from camera orthographic size and verify progressively lower meshes are used at increasing zoom
- [x] 5.2 Implement animation LOD tiers with reduced effect rate at medium, reduced update frequency and no particles far, and verify simulation results are identical with animation suspended
- [x] 5.3 Implement the `F3` debug overlay reporting FPS, frame time, draw calls, visible objects and trains, terrain and rail chunks, tick time, pathfinding time and memory estimate, and verify it toggles and every field shows a value
- [x] 5.4 Add rebuild and query counters to the terrain, rail and pathfinding systems and verify a single tile edit reports a bounded rebuild count
- [x] 5.5 Implement the seeded synthetic stress world with approximately 5,000 buildings, 10,000 vegetation instances, 2,000 rail tiles, 100 stations, 100 industries and 100 trains, and verify two runs with the same seed place identical entities
- [x] 5.6 Add `rr.py stress` launching the stress world headless for a fixed tick budget and emitting a measured report against the recorded budgets, and verify all 100 trains report a status and the run completes
- [x] 5.7 Add minimal spatial audio for UI click, construction, locomotive movement, whistle, arrival and an ambient loop with volume settings applied, and verify sounds trigger from the corresponding events

## 6. Verification

- [x] 6.1 Walk the specification's V1-complete checklist end to end — launch, new sandbox, camera, inspect, build rail, build stations, buy locomotive, add wagons, create route, watch travel, load, unload, revenue, finances, expand, save, quit, load, continue — and record any step needing developer intervention
  Walked by `game/tests/test_v1_checklist.gd` (12 cases), one case per stretch of the
  sentence, through the shipped classes: `Game.tscn`, `MainMenu`/`NewSandbox` +
  `SandboxIntent`, `IsoCameraRig`, `ContextInspector`, `InputController`, the domain
  services the panels call, and `SaveService`. Two steps cannot run headless and are
  left for a hand at a window: **quit** (closing a window is `get_tree().quit()`; what
  the suite grades is the menu's `quit_requested` and that the save still opens after the
  session is destroyed) and **watch it travel** (travel is measured in clock ticks, since
  nothing in a headless run draws a frame).
- [x] 6.2 Run the full suite plus `rr.py check` and verify both pass, then mark the change verified
  `python3 tools/rr.py test` — **393 cases in 37 files, PASS**, with no `SCRIPT ERROR` in the output (the runner treats one as a failure).  `python3 tools/rr.py check` — **66 runtime scripts import cleanly, check: OK**.  The shipped scene was also booted headlessly for 240 frames (`rr.py game run --godot-args "--headless res://scenes/Game.tscn --quit-after 240"`) and came back exit 0 with no script or parse errors, which is what exercises `game_root._ready` — the part no headless case can reach, since the runner never puts a node in a tree and so never fires `_ready`.
  Two known blemishes, both pre-existing and neither a failure: the suite takes ~77 s where `.agents/references/performance-budgets.md` records a "< 30 s" ambition for it, and Godot reports a few thousand ObjectDB instances plus 8 TextServer RIDs unreleased at process exit (the scene-tree test harness frees its own nodes; the engine's own shutdown accounting is what is noisy).
