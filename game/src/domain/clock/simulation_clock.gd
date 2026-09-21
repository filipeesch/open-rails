class_name SimulationClock
extends RefCounted

## Fixed-step clock, decoupled from rendering.
##
## Simulation advances in whole ticks at TICK_RATE; render frames only feed the
## accumulator.  A test can therefore step an exact number of ticks and get an
## exact result regardless of how fast the machine is.

signal tick_advanced(tick: int)
signal day_advanced(date: GameDate)
signal month_changed(date: GameDate)

const TICK_RATE := 20.0
const SPEEDS: Array[float] = [0.0, 1.0, 2.0, 4.0]
const SPEED_LABELS: PackedStringArray = ["⏸", "1×", "2×", "4×"]

## How much real time one tick represents at 1×, before the calendar ratio.
var tick_seconds: float = 1.0 / TICK_RATE

## Calendar ticks.  Tuned so a typical route stays readable at 1×.
var ticks_per_day: int = 24

var speed_index: int = 1
var tick_count: int = 0
var date: GameDate

var _accumulator: float = 0.0
var _ticks_this_month: int = 0
var _last_tick_micros: int = 0
var _tick_time_average: float = 0.0

var _subsystems: Array[Dictionary] = []


func _init(start_date: GameDate = null) -> void:
	date = start_date if start_date != null else GameDate.new(1850, 1, 1)


func configure(ticks_per_day_value: int, speed_value: int) -> void:
	ticks_per_day = maxi(1, ticks_per_day_value)
	set_speed_index(speed_value)


func clear_subsystems() -> void:
	_subsystems.clear()


func add_subsystem(label: String, callback: Callable) -> void:
	## Subsystems run in registration order, which is what makes a tick
	## reproducible.  Order is documented in GameSession.
	_subsystems.append({"label": label, "callback": callback})


func speed() -> float:
	return SPEEDS[speed_index]


func is_paused() -> bool:
	return speed() == 0.0


func set_speed_index(index: int) -> void:
	speed_index = clampi(index, 0, SPEEDS.size() - 1)


func set_speed(value: float) -> void:
	var best := 0
	var best_delta := 1e9
	for index in SPEEDS.size():
		var delta := absf(SPEEDS[index] - value)
		if delta < best_delta:
			best_delta = delta
			best = index
	set_speed_index(best)


func speed_label() -> String:
	return SPEED_LABELS[speed_index]


func feed(real_delta: float) -> int:
	## Returns how many whole ticks the caller must step.
	if is_paused():
		return 0
	_accumulator += real_delta * speed()
	var ticks := 0
	while _accumulator >= tick_seconds and ticks < 8:
		_accumulator -= tick_seconds
		ticks += 1
	return ticks


func step() -> void:
	var started := Time.get_ticks_usec()
	tick_count += 1
	for subsystem in _subsystems:
		subsystem["callback"].call()
	var elapsed := float(Time.get_ticks_usec() - started)
	_last_tick_micros = int(elapsed)
	_tick_time_average = elapsed if _tick_time_average <= 0.0 else lerpf(_tick_time_average, elapsed, 0.05)
	if tick_count % ticks_per_day == 0:
		if date.advance_days():
			_ticks_this_month = 0
			month_changed.emit(date)
		else:
			day_advanced.emit(date)
	_ticks_this_month += 1
	tick_advanced.emit(tick_count)


func step_ticks(count: int) -> void:
	for _index in count:
		step()


func tick_time_micros() -> int:
	return _last_tick_micros


func tick_time_average_micros() -> float:
	return _tick_time_average


func days_elapsed() -> int:
	return int(tick_count / float(ticks_per_day))


func to_dict() -> Dictionary:
	return {
		"tick_count": tick_count,
		"speed_index": speed_index,
		"ticks_per_day": ticks_per_day,
		"date": date.to_dict(),
	}


func from_dict(data: Dictionary) -> void:
	tick_count = int(data.get("tick_count", 0))
	_accumulator = 0.0
	ticks_per_day = int(data.get("ticks_per_day", ticks_per_day))
	set_speed_index(int(data.get("speed_index", 1)))
	date.from_dict(data.get("date", {}))
