# Proposal

## Why

Milestones 5–7 are the first complete gameplay loop and the point at which the project becomes a tycoon game: buy a train, define a route, watch cargo move, earn revenue, pay operating costs. Until that loop closes end to end nothing else in the spec can be evaluated, and the specification names it as the build-health test: if the coal-delivery scenario breaks, the build is not healthy.

## What Changes

- Add externally-defined rolling stock: one 4-4-0 steam locomotive and Passenger Coach, Mail Car and Coal Hopper wagons, so new stock needs no change to the train engine.
- Add train purchase from a starting station with a visual consist editor (add, remove, reorder) and live statistics for capacity, weight, estimated maximum speed, purchase cost and running cost.
- Add deterministic non-physical train movement along the rail graph with A* paths derived from the route, per-tick state (current track, position, speed, route, destination, path, cargo) and trains passing through one another since signals and collisions are deferred.
- Add wheel phase derived from distance travelled over wheel circumference so wheels never visually slide, with animation LOD that suspends visuals offscreen while simulation continues.
- Add the route editor: ordered stops, per-stop load/unload configuration, station picking directly on the map, reachability validation and recalculation when the network changes.
- Add loading and unloading with dwell time proportional to cargo amount and station-side cargo transfer.
- Add the revenue model `quantity × base_rate × distance × delivery_quality` with time-sensitivity decay for passengers and mail, and the company ledger where every money mutation flows through `EconomyService`.
- Add monthly accounting (revenue, expenses, profit), construction and wagon purchase expenses, train operating cost and track maintenance, with construction blocked but the railway still operating when cash runs out.
- Add the fixed-step 20 Hz simulation clock with Paused/1×/2×/4× speeds and a day/month/year calendar starting January 1850.
- Add the core-loop integration test from the specification as a mandatory gate.

## Capabilities

### New Capabilities
- `rolling-stock`: Data-defined locomotives and wagons, consist composition and purchase.
- `train-operations`: Deterministic movement, mechanical animation coupling, dwell and train state.
- `routes`: Ordered station stops with loading instructions, reachability and recalculation.
- `cargo-delivery`: Loading, unloading, delivery quality and revenue recognition.
- `company-economy`: Cash, ledger, monthly accounting and the single money-mutation boundary.
- `simulation-clock`: Fixed-step simulation timing, game speeds and calendar progression.

### Modified Capabilities
_(none)_

## Impact

- New `game/src/domain/{trains,routes,cargo,economy,clock}/` and `game/src/presentation/trains/`.
- New UI: train management drawer, consist editor, route drawer.
- Consumes generated GLB assets and manifests from `add-art-pipeline` and the cargo sources from `add-map-economy-sources`.
- Every service publishes typed events (`train_created`, `train_arrived`, `cargo_delivered`, `money_changed`, `month_changed`) that UI subscribes to; simulation never calls UI.
