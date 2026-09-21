"""Project-level conventions that scale documents (asset-scale.md) fix but
`world.toml` does not carry yet.  They live in the library (hashed into every
cache key) so an asset script never hard-codes its own notion of a tile.
"""

#: Inner rail spacing, tile units (asset-scale.md "project decisions").
RAIL_GAUGE_TILES = 0.30

#: Rail top surface above the tile surface, tile units.
RIDE_HEIGHT_TILES = 0.04

#: Station platform height: exactly one HEIGHT_STEP (asset-scale.md).
PLATFORM_HEIGHT_STEPS = 1

#: Wheelset defaults from the rolling-stock reference table.
DRIVING_WHEEL_RADIUS_TILES = 0.11
LEADING_WHEEL_RADIUS_TILES = 0.06
BOILER_RADIUS_TILES = 0.14
LOCOMOTIVE_FRAME_LENGTH_TILES = 0.85

#: Default LOD decimation ratios (collapse ratio applied to the previous level).
DEFAULT_LOD_RATIOS = (0.45, 0.15)

#: Mechanical animation loop length in frames at the default 24 fps.
ANIMATION_LOOP_FRAMES = 24
ANIMATION_FPS = 24

#: Canonical runtime animation states (art-authoring spec).
CANONICAL_STATES = ("idle", "moving", "working", "loading", "unloading")
