class_name TestBase
extends RefCounted

## Base class for headless simulation tests.
##
## A test file lives under `res://tests/`, is named `test_*.gd`, extends this
## class and declares methods named `test_*`.  Assertions record failures
## instead of throwing, so a single case can report every problem it found.

var failures: PackedStringArray = PackedStringArray()
var _current_case: String = ""
var _assertions: int = 0


func set_current_case(case_name: String) -> void:
	_current_case = case_name
	failures.clear()
	_assertions = 0


## Optional per-case fixture.  The runner calls it before every `test_*` method
## so a suite can build a fresh world instead of leaking state between cases.
func setup() -> void:
	pass


func teardown() -> void:
	pass


## Stations a train has left the platform at, oldest first.  Cases that care
## about the moment the doors close watch this instead of guessing from a state
## string one tick late.
var departures: Array[int] = []


func watch_departures(trains: TrainService) -> void:
	departures.clear()
	if not trains.train_departed.is_connected(_note_departure):
		trains.train_departed.connect(_note_departure)


func _note_departure(_train_id: int, station_id: int) -> void:
	departures.append(station_id)


## Calendar months the clock has rolled over since `watch_months` was called.
## Stepping a fixed number of ticks cannot express "run for two months" — the
## calendar months are different lengths.
var months_observed: int = 0


func watch_months(clock: SimulationClock) -> void:
	months_observed = 0
	if not clock.month_changed.is_connected(_note_month):
		clock.month_changed.connect(_note_month)


func _note_month(_date: GameDate) -> void:
	months_observed += 1


## Drop a JSON document into the user directory for tests that exercise the
## data-driven side of the game (definitions, saves, mods).
func write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


## Run the simulation for `count` calendar months.  Returns false if the cap was
## hit first, which in a test means the clock is not rolling over.
func run_months(clock: SimulationClock, count: int, cap: int = 4000) -> bool:
	var started := months_observed
	var ticks := 0
	while months_observed < started + count and ticks < cap:
		clock.step_ticks(1)
		ticks += 1
	return months_observed >= started + count


## How many assertions this case actually reached.  A case that reached zero is
## a case that aborted early (usually a script error), not a passing one.
func assertion_count() -> int:
	return _assertions


func describe() -> String:
	return _current_case


func check(condition: bool, message: String) -> void:
	_assertions += 1
	if not condition:
		failures.append("assert failed: " + message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	_assertions += 1
	if not _values_equal(actual, expected):
		failures.append("%s\n      expected: %s\n      actual:   %s" % [message, _show(expected), _show(actual)])


func check_near(actual: float, expected: float, message: String, tolerance: float = 0.0001) -> void:
	_assertions += 1
	if absf(actual - expected) > tolerance:
		failures.append("%s\n      expected: %s (+/-%s)\n      actual:   %s" % [message, expected, tolerance, actual])


func check_lt(actual: float, limit: float, message: String) -> void:
	_assertions += 1
	if not (actual < limit):
		failures.append("%s\n      expected < %s\n      actual:   %s" % [message, limit, actual])


func check_gt(actual: float, limit: float, message: String) -> void:
	_assertions += 1
	if not (actual > limit):
		failures.append("%s\n      expected > %s\n      actual:   %s" % [message, limit, actual])


func check_le(actual: float, limit: float, message: String) -> void:
	_assertions += 1
	if not (actual <= limit + 0.000001):
		failures.append("%s\n      expected <= %s\n      actual:   %s" % [message, limit, actual])


func check_ge(actual: float, limit: float, message: String) -> void:
	_assertions += 1
	if not (actual >= limit - 0.000001):
		failures.append("%s\n      expected >= %s\n      actual:   %s" % [message, limit, actual])


func check_neq(actual: Variant, unexpected: Variant, message: String) -> void:
	_assertions += 1
	if _values_equal(actual, unexpected):
		failures.append("%s\n      expected anything but: %s" % [message, _show(unexpected)])


func check_true(condition: bool, message: String) -> void:
	check(condition, message)


func check_false(condition: bool, message: String) -> void:
	check(not condition, message)


func check_has(haystack: String, needle: String, message: String) -> void:
	_assertions += 1
	if not haystack.contains(needle):
		failures.append("%s\n      '%s' does not contain '%s'" % [message, haystack, needle])


func fail(message: String) -> void:
	_assertions += 1
	failures.append(message)


func _values_equal(actual: Variant, expected: Variant) -> bool:
	if typeof(actual) == TYPE_FLOAT or typeof(expected) == TYPE_FLOAT:
		return absf(float(actual) - float(expected)) < 0.000001
	return actual == expected


func _show(value: Variant) -> String:
	match typeof(value):
		TYPE_ARRAY:
			var parts: PackedStringArray = []
			for item in value:
				parts.append(_show(item))
			return "[" + ", ".join(parts) + "]"
		TYPE_DICTIONARY:
			var keys: Array = value.keys()
			keys.sort()
			var parts: PackedStringArray = []
			for key in keys:
				parts.append("%s=%s" % [key, _show(value[key])])
			return "{" + ", ".join(parts) + "}"
		TYPE_VECTOR2I:
			return "(%d, %d)" % [value.x, value.y]
		TYPE_STRING:
			return "'%s'" % value
	return str(value)
