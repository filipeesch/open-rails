# Proposal

## Why

Cargo moving for money is what turns a railway diorama into a game, but before trains exist the world needs sources, sinks and a way for a station to claim them. The specification's core loop starts with "identify demand / production", and the anti-pattern it explicitly warns about — duplicated cargo when several stations overlap one town — has to be designed in here rather than patched later.

## What Changes

- Add data-driven towns (id, name, population, position, passenger and mail generation) that do not grow dynamically in V1.
- Add data-driven industries: Coal Mine (produces coal at a monthly rate into limited storage) and Power Plant (accepts coal with a consumption capacity), on a framework that supports multi-input chains such as iron + coal → steel without touching the cargo system.
- Add the single V1 station class with footprint, required rail alignment, catchment radius of 4 tiles and per-cargo storage.
- Add station placement UX showing footprint, required rail alignment, catchment on terrain, covered towns and industries, expected monthly cargo and cost, with an actionable reason when placement is invalid.
- Add monthly cargo generation with distance-weighted distribution across the eligible stations covering a source, guaranteeing a source's cargo is never duplicated.
- Add station inventories and cargo batches carrying cargo type, quantity, origin, destination and creation time — never one object per passenger.
- Add the shipped "Founder's Valley" 256 × 256 sandbox map with 2 towns, 2 coal mines, 2 power plants, water, forests, hills and plains.

## Capabilities

### New Capabilities
- `towns-and-industries`: Economic sources and sinks in the world, their production, storage and consumption rules.
- `stations`: Station placement, catchment coverage, and the storage a station holds for each cargo.
- `cargo-generation`: Turning world sources into station-allocated cargo batches over simulated time.

### Modified Capabilities
_(none)_

## Impact

- New `game/src/domain/towns/`, `game/src/domain/industries/`, `game/src/domain/stations/`, `game/src/domain/cargo/`.
- New data tree `game/data/{cargo,towns,industries,stations,economy}/` and map data `game/data/maps/founders_valley.json`.
- Reuses `rail-network` (stations must attach to rail) and `world-model` (occupancy, catchment maths).
- Cargo exists and accumulates in stations, but nothing transports it yet; that is `add-trains-routes-and-revenue`.
