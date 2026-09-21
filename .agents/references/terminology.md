# Terminology

Canonical vocabulary for the whole repository. Use these words in code,
docs, commit messages and UI strings; synonyms listed here are *not* used.

| Term | Meaning | Avoid saying |
|---|---|---|
| **tile** | One logical world cell, `Vector2i (x, y)`, TILE_SIZE 1.0 wide | cell, square, pixel |
| **height step** | One unit of elevation = 0.25 game units (HEIGHT_STEP) | meter, voxel |
| **chunk** | A 32×32-tile render unit (terrain mesh / track batch / scenery group) | sector, zone |
| **WorldGrid** | The typed-array world state (`terrain/height/occupancy_kind/occupancy_id/rail`) | world map, tilemap |
| **occupancy** | Which entity kind + stable ID owns a tile | blocker |
| **rail cell** | A tile whose `rail` bitmask is non-zero | track tile (reserve "track" for the mesh) |
| **connection mask** | The per-cell 8-bit mask `N,NE,E,SE,S,SW,W,NW` | node flags |
| **rail graph** | The undirected graph derived from connection masks | rail map |
| **planner** | A* query proposing a rail route during construction | router (that's trains) |
| **ghost** | The semi-transparent preview of a build before commit | hologram, shadow |
| **catchment** | The 4-tile-radius area around a station whose sources it serves | radius, zone |
| **source** | A town or producing industry that emits cargo | producer entity |
| **sink** | A consuming industry (V1: power plant) | drain |
| **cargo type** | Data-defined transportable: `passengers`, `mail`, `coal` | resource, good |
| **batch** | An aggregated pile of one cargo type sharing origin/destination | lot, stack |
| **packet** | Conceptual cargo record: type, quantity, origin, destination, created_at | item |
| **consist** | A locomotive plus its ordered wagons | train composition |
| **rolling stock** | Data-defined locomotives and wagons | vehicles |
| **route** | Ordered list of station stops with load/unload settings | path (path is the resolved rail cells) |
| **path** | The resolved list of `(cell, direction)` a train follows | route |
| **dwell** | Time a train spends at a stop for loading/unloading | pause |
| **tick** | One fixed 20 Hz simulation step | frame (frames are render-side) |
| **month boundary** | The instant `SimulationClock` emits `month_changed` | end of month event |
| **ledger transaction** | One recorded money mutation: date, amount, category, description | log line |
| **EconomyService** | The only service allowed to mutate company cash | money manager |
| **asset** | One `art/assets/<category>/<id>/` folder (asset.py + asset.toml) | model, prop |
| **manifest** | Generated JSON at `game/generated/manifests/<id>.json` describing a GLB | metadata file |
| **footprint** | Declared asset size in tile units `[length, width]` | bounding box |
| **lod_class** | Asset's triangle-budget category (prop/tree/house/station/industry/wagon/locomotive) | detail level |
| **LOD0/1/2** | close / normal gameplay / distant silhouette meshes | high/mid/low (use these names) |
| **attachment point** | Named local-space socket in a manifest (coupling, chimney, loading) | socket, marker |
| **wheel phase** | Presentation-only `fmod(distance / circumference, 1)` driving rod animation | rotation speed |
| **company colour** | Runtime-tintable `company_primary` / `company_secondary` material params | skin, livery (livery = the resulting look) |
| **diorama** | The overall visual goal: a miniature railway model | toy box |
| **GameSession** | The composition-root `Node` owning all domain services | game manager |
| **service** | A domain object owning one entity family (`TrainService`, …) | system, manager |
| **definition (def)** | An immutable JSON-backed record (`CargoDef`, `TownDef`…) loaded by `DataRegistry` | config object |
| **instance** | The runtime state of one def placed in the world (station #17) | object |
| **stress world** | The synthetic scalability map (2×10⁴-scale content) driven by `rr.py stress` | benchmark scene |

Two terms come from Godot and are used verbatim: **autoload** (application
settings only, never simulation state) and **MultiMeshInstance3D** (the only
allowed way to draw repeated static scenery/track).
