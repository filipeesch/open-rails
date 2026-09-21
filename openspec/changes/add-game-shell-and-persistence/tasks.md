# Tasks

## 1. Shell and screens

- [x] 1.1 Create `MainMenu.tscn` with Continue, New Sandbox, Load Game, Settings and Quit and verify Continue is disabled when no autosave exists and enabled when one does
- [x] 1.2 Create `NewSandbox.tscn` selecting Founder's Valley with a company-name field, starting year 1850 and a start action, and verify a blank name yields a generated default and starts the sandbox
- [x] 1.3 Create `Game.tscn` with the `World3D` and `UI` hierarchy from the specification and verify it instantiates headlessly
- [x] 1.4 Implement the top bar showing date, cash, monthly profit and speed controls and verify a delivery updates cash and profit without reopening a panel
- [x] 1.5 Implement the bottom toolbar with Build, Stations, Trains, Company and World and verify no permanent sidebar appears
- [x] 1.6 Implement the right-side context inspector for train, station, industry and town selections with actions for consist, route, follow and rename, and verify it disappears when nothing is selected

## 2. Interaction layer

- [ ] 2.1 Implement build mode with the Rail, Station and Remove palette, cursor-state change and two-stage Escape, and verify Escape order cancels the operation before exiting build mode
- [ ] 2.2 Implement shared ghost-preview presentation showing geometry, cost and validity with specific failure text adjacent to the cursor, and verify a straight-rail requirement is stated as such
- [ ] 2.3 Implement hover tooltips for train, industry and station using the selection resolver, and verify hover shows data without changing selection
- [ ] 2.4 Implement zoom-dependent map labels on one pooled screen-space layer, and verifying labels vanish at close zoom for unselected entities
- [x] 2.5 Implement the non-blocking notification layer fed by a notification bus, and verify insufficient funds and unreachable-destination messages appear without a modal
- [x] 2.6 Implement the `Ctrl+K` palette over a command registry with entity search focusing the camera, and verify selecting a town focuses it

## 3. Train and company UI

- [ ] 3.1 Implement the non-modal trains drawer listing name, locomotive, speed, cargo, route, monthly profit and status with search and filter, and verify a row click selects and opens the inspector
- [ ] 3.2 Implement the consist editor UI with live capacity, weight, estimated speed, purchase and running cost, and verify adding a wagon updates every statistic
- [ ] 3.3 Implement the route drawer with stops, load configuration and map-based stop picking, and verify the drawer reflects reachability changes live
- [ ] 3.4 Implement the company finance panel showing cash, monthly revenue, expenses and profit plus recent transactions, and verify entries match the ledger
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

- [ ] 5.1 Implement LOD selection from camera orthographic size and verify progressively lower meshes are used at increasing zoom
- [ ] 5.2 Implement animation LOD tiers with reduced effect rate at medium, reduced update frequency and no particles far, and verify simulation results are identical with animation suspended
- [x] 5.3 Implement the `F3` debug overlay reporting FPS, frame time, draw calls, visible objects and trains, terrain and rail chunks, tick time, pathfinding time and memory estimate, and verify it toggles and every field shows a value
- [x] 5.4 Add rebuild and query counters to the terrain, rail and pathfinding systems and verify a single tile edit reports a bounded rebuild count
- [ ] 5.5 Implement the seeded synthetic stress world with approximately 5,000 buildings, 10,000 vegetation instances, 2,000 rail tiles, 100 stations, 100 industries and 100 trains, and verify two runs with the same seed place identical entities
- [ ] 5.6 Add `rr.py stress` launching the stress world headless for a fixed tick budget and emitting a measured report against the recorded budgets, and verify all 100 trains report a status and the run completes
- [ ] 5.7 Add minimal spatial audio for UI click, construction, locomotive movement, whistle, arrival and an ambient loop with volume settings applied, and verify sounds trigger from the corresponding events

## 6. Verification

- [ ] 6.1 Walk the specification's V1-complete checklist end to end — launch, new sandbox, camera, inspect, build rail, build stations, buy locomotive, add wagons, create route, watch travel, load, unload, revenue, finances, expand, save, quit, load, continue — and record any step needing developer intervention
- [ ] 6.2 Run the full suite plus `rr.py check` and verify both pass, then mark the change verified
