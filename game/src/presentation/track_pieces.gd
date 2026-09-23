class_name TrackPieces
extends RefCounted

## The named piece a connection mask means.
##
## §36 lists the canonical pieces — straight, diagonal, 45° curve, 90° curve,
## junction, slope — and says the renderer chooses the piece from connectivity.
## The rail bitmask is the only record of connectivity, so this module is the one
## place that reads it and answers "what piece of track is this?".  Two consumers
## need that answer and they must never disagree:
##
## * the renderer, which emits one half of track per connection and so has to know
##   how many halves a piece has;
## * anyone who wants to talk about the railway — the overlay, a diagnostic, a
##   future asset switch to modelled pieces — in words rather than in integers.
##
## A piece is therefore a *name*, and the name is derived, never stored: there is
## no piece table to keep in step with the network, because the network is the
## table.  When the day comes that pieces are real GLB meshes instead of merged
## geometry, these identifiers are the catalogue keys and nothing else changes.
##
## ## The shape rule
##
## A cell's planform is decided by the angle between its arms: two arms pointing
## at each other's opposite are a straight (or a diagonal, when both arms are
## diagonal); the further they bend away from that, the sharper the curve.  Three
## arms or more is a junction whatever the angles, because a junction is a
## statement about traffic, not about geometry.  A cell whose ground rises under
## the rail is a slope piece — the same planform drawn tilted, which is why slope
## wins over straight but never over junction: a junction on a hill is still the
## thing the player cares about.

const EMPTY := "empty"
const END := "end"
const STRAIGHT := "straight"
const DIAGONAL := "diagonal"
const CURVE_45 := "curve_45"
const CURVE_90 := "curve_90"
const JUNCTION := "junction"
const SLOPE := "slope"

## Every name this table can answer with, in the order §36 lists them.
## Three arms make a junction: the point at which a cell stops being a shape the
## train passes through and becomes a place traffic chooses between.
const JUNCTION_ARMS := 3

const PIECES: PackedStringArray = [
	STRAIGHT, DIAGONAL, CURVE_45, CURVE_90, JUNCTION, SLOPE, END, EMPTY,
]

const LABELS := {
	EMPTY: "no track",
	END: "buffer stop",
	STRAIGHT: "straight",
	DIAGONAL: "diagonal",
	CURVE_45: "45° curve",
	CURVE_90: "90° curve",
	JUNCTION: "junction",
	SLOPE: "slope",
}

## A mask is an integer over `RailDirections` bits; a rise is height steps between
## the cell and the ground its rail runs to.
static func piece_for(mask: int, rise_steps: int = 0) -> String:
	var arms := RailDirections.directions_in(mask)
	if arms.is_empty():
		return EMPTY
	if arms.size() == 1:
		return END
	if arms.size() >= JUNCTION_ARMS:
		return JUNCTION
	if rise_steps != 0:
		return SLOPE
	var bend := _deflection(arms[0], arms[1])
	if bend == 0:
		return DIAGONAL if RailDirections.is_diagonal(arms[0]) else STRAIGHT
	return CURVE_90 if bend >= 90 else CURVE_45


## The endpoints a piece is made of.  The renderer draws one half per direction
## and nothing else, so this list *is* the piece's construction — a straight gets
## two halves, a junction three or more, a buffer stop one.
static func halves_for(mask: int) -> Array[int]:
	return RailDirections.directions_in(mask)


## The piece a cell of a live network is.  `rise` is read from the ground under
## the two ends of the arm, so a line climbing a hill says "slope" without anyone
## having to mark it as one.
static func piece_at(grid: WorldGrid, tile: Vector2i) -> String:
	var mask := grid.rail_mask_at(tile)
	return piece_for(mask, _rise_at(grid, tile, mask))


static func label(piece: String) -> String:
	return String(LABELS.get(piece, piece))


static func is_curved(piece: String) -> bool:
	return piece == CURVE_45 or piece == CURVE_90


# --- the line itself -------------------------------------------------------
#
# Two things draw and ride the same railway: the renderer, which emits the ballast
# and the rails, and the rolling stock, which has to stand on them.  Both ask the
# same three questions — where is a cell's lane, how high is the tile surface
# between two cells, how high is the running surface — and any answer given twice
# can be given differently, which is exactly how a consist came to be drawn half a
# tile off the line and a hand's breadth above or below the rails on a slope.
# Everything here is asked once.

## How far the top of the ballast band stands over the ground it lies on.  Small:
## enough to clear the terrain sheet, not enough to read as an embankment.
const LIFT_BALLAST := 0.02
## How far the running surface — the top of the rail head — stands over the tile
## surface.  Not a rendering taste: this is the asset contract.  Rolling stock is
## compiled with its wheels resting at exactly this height (`RIDE_HEIGHT_TILES` in
## `art/railroad_art/conventions.py`, documented in `.agents/references/asset-scale.md`),
## so a vehicle standing on the tile surface has its wheels on the rail head only
## if the rails are drawn here.  `rr.py check` pins the two numbers together.
const RIDE_HEIGHT := 0.04
## How far a sleeper's top stands over the ground: above the ballast, below the
## rails, so the ties read as lying under the line rather than poking through it.
## Rails stand a little proud of the tie top, as they do on the ground.
const LIFT_TIE := 0.032


## The centre of the lane a cell carries, in world units on the ground plane.  The
## one reading of "where the train runs" for a cell; `WorldCoords` owns the centre
## convention, so this only names what the renderer means by it.
static func lane(tile: Vector2i) -> Vector2:
	return WorldCoords.tile_to_world_xz(tile)


## The tile surface `t` of the way from one cell's lane centre to the next cell's.
##
## This is not a fresh invention: it is the rule the rail band is built with.  Each
## drawn half runs from its own cell's height to the midpoint of the pair at the
## shared edge, so the two halves of a cell-to-cell step join into one straight
## slope, and a point taken on the same line at any `t` is on the drawn track.
static func surface(grid: WorldGrid, from_tile: Vector2i, to_tile: Vector2i, t: float) -> float:
	return lerpf(grid.elevation_at(from_tile), grid.elevation_at(to_tile), clampf(t, 0.0, 1.0))


## The rail head `t` of the way along a cell-to-cell step: the surface plus the
## ride height the stock is modelled to.
static func rail_head(grid: WorldGrid, from_tile: Vector2i, to_tile: Vector2i, t: float) -> float:
	return surface(grid, from_tile, to_tile, t) + RIDE_HEIGHT


## The ballast top `t` of the way along a cell-to-cell step.
static func ballast_top(grid: WorldGrid, from_tile: Vector2i, to_tile: Vector2i, t: float) -> float:
	return surface(grid, from_tile, to_tile, t) + LIFT_BALLAST


## The rail head at a cell's own lane centre — the same question with t = 0.
static func rail_head_at(grid: WorldGrid, tile: Vector2i) -> float:
	return rail_head(grid, tile, tile, 0.0)


## How much a pair of arms turns, in degrees: 0 for a through line, 45 for a
## gentle bend, 90 for a corner.  A hook — arms 45° apart — is a 135° turn and is
## drawn as the sharpest piece the vocabulary has, because nothing milder fits.
static func _deflection(first: int, second: int) -> int:
	var between := absf(RailDirections.BEARING_DEGREES[first] - RailDirections.BEARING_DEGREES[second])
	between = minf(between, 360.0 - between)
	return int(180.0 - between)


static func _rise_at(grid: WorldGrid, tile: Vector2i, mask: int) -> int:
	var here := grid.height_at(tile)
	var rise := 0
	for direction in RailDirections.directions_in(mask):
		var neighbour := tile + RailDirections.offset(direction)
		if not grid.in_bounds(neighbour):
			continue
		var delta := grid.height_at(neighbour) - here
		if absi(delta) > absi(rise):
			rise = delta
	return rise
