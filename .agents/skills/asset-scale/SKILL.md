# asset-scale

## Purpose
Owns canonical dimensions for everything that enters the world: tile scale,
height steps, rolling-stock dimensions, building sub-scale conventions (doors,
windows, floors, platform height, rail gauge). Scale is decided exactly once,
here and in `art/config/world.toml`.

## When to use
Before authoring any asset, whenever choosing a size, footprint or origin, and
whenever art and runtime disagree about how big something looks.

## Non-goals
Shape language (`art-style`), triangle budgets (`mesh-optimization`), colour
(`material-palette`). The runtime-side constants consumer is `iso-world`.

## Dependencies
- `art/config/world.toml` — single source: `tile_size = 1.0`,
  `height_step = 0.25`, chunk 32, map 256×256, camera and catchment values.
- Generated `game/src/domain/world/world_constants.gd` (`WorldConstants`) —
  runtime mirror; regenerate with `python tools/rr.py constants`, drift fails
  `python tools/rr.py check`.
- `.agents/references/asset-scale.md` — the full dimension table.

## Invariants
1. No asset script or gameplay module re-declares TILE_SIZE/HEIGHT_STEP;
   `rr.py check` diff-catches drift and exits non-zero.
2. Tile centre is `(x + 0.5) * TILE_SIZE`; elevation is
   `height * HEIGHT_STEP` — one convention, owned by `WorldCoords`.
3. An asset's declared `footprint` (tile units, `[length, width]`) matches
   the built mesh's largest horizontal extent within 5%.
4. Asset origins sit at the ground contact point (geometry centre over the
   footprint centre, base at local Z = 0) so ghosts and instancing land
   correctly.
5. Changing `tile_size` in world.toml changes rebuilt assets
   proportionally without editing any asset script.

## Public interfaces
- Art side: read world.toml via the config helpers inside the build context;
  size everything from those values.
- Runtime side: `WorldConstants.TILE_SIZE`, `WorldConstants.HEIGHT_STEP`,
  `WorldCoords.tile_to_world()` / `world_to_tile()`.
- Reference table: `.agents/references/asset-scale.md` (house ≈ 1 tile,
  factory 3–6 tiles, locomotive ≈ 0.85 long × 0.45 wide, wagon ≈ 0.7,
  platform height 0.25 = one height step; project-decided: gauge 0.30,
  floor 0.30, door 0.20×0.10, window 0.10×0.10).

## Implementation rules
- Compose from `railroad_art` primitives that take tile-relative arguments —
  never multiply by a literal `1.0` "because a tile is one unit".
- Heights used by gameplay (platforms, track ballast) must land on
  HEIGHT_STEP multiples (0.25 grid).
- If you need a dimension that isn't in the reference table: add it there
  first, with a rationale, then use it.
- Vertical clearances: machinery and roofs are designed so a camera at fixed
  pitch 35.264° never has them occlude gameplay-critical parts at default
  zoom.

## Validation
`python tools/rr.py art validate <id>` checks footprint-vs-mesh (5%
tolerance), origin placement and scale against world.toml. `python
tools/rr.py check` fails on constant drift between world.toml and
`world_constants.gd`.

## Common mistakes
- Hard-coding `0.5` as "half a tile" inside asset.py instead of deriving it.
- Authoring in metres and "scaling later" — export scale must be final.
- Origin at mesh centre-of-mass instead of ground contact ⇒ floating ghosts.
- Hand-editing `world_constants.gd` (it is generated and will be overwritten).

## Related skills
`voxel-modeling`, `material-palette`, `iso-world`, `gltf-export`,
`asset-validation`, `terrain-system`.
