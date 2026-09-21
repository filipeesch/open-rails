class_name RailDirections
extends RefCounted

## The eight rail directions, their tile offsets, reciprocals and weights.
##
## A rail cell stores connections as a bitmask over these bits.  Everything
## downstream — graph traversal, piece selection, junction detection — is
## derived from that mask, never from a parallel structure.

const N := 0
const NE := 1
const E := 2
const SE := 3
const S := 4
const SW := 5
const W := 6
const NW := 7
const COUNT := 8

const OFFSETS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]

const NAMES: PackedStringArray = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

## Straight hops cost 1.0, diagonal hops sqrt(2) so a diagonal is never chosen
## where a straight pair is equally cheap.
const STEP_COST: PackedFloat64Array = [
	1.0, 1.4142135623730951, 1.0, 1.4142135623730951,
	1.0, 1.4142135623730951, 1.0, 1.4142135623730951,
]

## Compass bearing of each direction in degrees, used by the track renderer to
## choose a piece and by the camera-independent minimap later.
const BEARING_DEGREES: PackedFloat64Array = [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]


static func bit(direction: int) -> int:
	return 1 << direction


static func opposite(direction: int) -> int:
	return (direction + 4) % COUNT


static func offset(direction: int) -> Vector2i:
	return OFFSETS[direction]


static func name_of(direction: int) -> String:
	return NAMES[direction]


static func cost(direction: int) -> float:
	return STEP_COST[direction]


static func is_diagonal(direction: int) -> bool:
	return direction % 2 == 1


static func mask_of(direction: int) -> int:
	return 1 << direction


static func count_connections(mask: int) -> int:
	var total := 0
	var value := mask
	while value != 0:
		total += value & 1
		value >>= 1
	return total


static func directions_in(mask: int) -> Array[int]:
	var out: Array[int] = []
	for direction in range(COUNT):
		if mask & (1 << direction) != 0:
			out.append(direction)
	return out


static func has(mask: int, direction: int) -> bool:
	return mask & (1 << direction) != 0


static func neighbors(tile: Vector2i, mask: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for direction in directions_in(mask):
		out.append(tile + OFFSETS[direction])
	return out


## Turning cost is applied when consecutive steps differ in bearing, which is
## what makes the planner prefer straight runs over zig-zags.
static func turn_penalty(previous: int, next: int, weight: float) -> float:
	if previous < 0 or previous == next:
		return 0.0
	var delta := absi(BEARING_DEGREES[previous] - BEARING_DEGREES[next])
	delta = int(minf(delta, 360.0 - delta))
	return weight * (delta / 180.0)


static func from_name(looked: String) -> int:
	for index in range(COUNT):
		if NAMES[index] == looked:
			return index
	return -1
