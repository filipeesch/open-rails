# Asset Scale

All dimensions are **game units** relative to the canonical world config
`art/config/world.toml` (single source of truth; drift fails
`python tools/rr.py check`). Never re-declare these numbers inside an asset
script or gameplay module — read `WorldConstants` (generated at
`game/src/domain/world/world_constants.gd`) on the runtime side and the TOML
on the art side.

## Canonical constants (art/config/world.toml)

| Key | Value |
|---|---|
| `tile_size` (TILE_SIZE) | 1.0 |
| `height_step` (HEIGHT_STEP) | 0.25 |
| `default_chunk` | 32 (→ 32×32 tiles, 64 chunks on a 256×256 map) |
| `map_width` / `map_height` | 256 × 256 |
| camera default yaw / fixed pitch | 45° / 35.264° |
| zoom close / default / far | 4 / 28 / 96 tiles |
| station `catchment_tiles` | 4.0 |

Coordinate convention (per `add-world-and-camera` design): tile centre is at
`(x + 0.5) * TILE_SIZE`; world elevation is `height * HEIGHT_STEP`.

## Size table (spec §8)

| Asset class | Size |
|---|---|
| Small house | ~1 tile |
| Large house | 1–2 tiles |
| Factory / large industry | 3–6 tiles |
| Locomotive | ~0.8–1 tile long (reference build uses frame length 0.85) |
| Wagon | ~0.7 tile long |
| `steam_440` declared footprint | `[1.0, 0.45]` (length × width, tile units) |

A declared `footprint` in `asset.toml` is in tile units and must match the
built mesh's largest horizontal extent within 5% (art-authoring spec).

## Rolling-stock reference dimensions (spec §23 primitives example)

| Dimension | Value |
|---|---|
| Locomotive frame length | 0.85 |
| Boiler radius | 0.14 |
| Cab width | 0.24 |
| Chimney height | 0.22 |
| Driving wheel radius | 0.11 (count 2 per side) |
| Leading wheel radius | 0.06 (count 2 per side) |

## Sub-scale conventions — project decisions (spec §82 says these are owned
here but does not fix values)

- Rail gauge (inner rail spacing): **0.30**, rails centred in the tile;
  chosen so the 0.45-wide wagon/locomotive overhangs the gauge like period
  stock.
- Wagon width: **0.45** (matches `steam_440` footprint width).
- Coupler ride height / rail top: **0.04** above the tile surface; track base
  ballast sits on the terrain surface.
- Station platform height: **0.25** = exactly one HEIGHT_STEP, so platforms
  align with terrain steps and wagon floors.
- Floor height (one storey of a house): **0.30**; door: **0.20 tall × 0.10
  wide**; window: **0.10 × 0.10**, sill at 0.12. Diorama proportions —
  oversized heads, undersized doors read "miniature".
- Tree: canopy within a 1-tile footprint, height 0.8–1.5; rocks/bushes ≤ 0.3.
- Props (fence post, telephone pole): footprint ≤ 0.1; pole height 0.7.

Anything outside this table: add it here with a rationale *before* using it
in an asset, so `asset-scale` remains the only place scale is decided.
