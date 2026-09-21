class_name GameDate
extends RefCounted

## Day / month / year calendar.  Days advance as ticks accumulate; the calendar
## knows nothing about trains or money.

const MONTH_NAMES: PackedStringArray = [
	"Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
]

const DAYS_IN_MONTH: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

var year: int = 1850
var month: int = 1
var day: int = 1


func _init(p_year: int = 1850, p_month: int = 1, p_day: int = 1) -> void:
	year = p_year
	month = p_month
	day = p_day


func days_in_current_month() -> int:
	return DAYS_IN_MONTH[month - 1]


func advance_days() -> bool:
	## Advances one day.  Returns true when a calendar month rolled over.
	day += 1
	if day > days_in_current_month():
		day = 1
		month += 1
		if month > 12:
			month = 1
			year += 1
		return true
	return false


func month_key() -> int:
	return year * 100 + month


func previous_month_key() -> int:
	if month == 1:
		return (year - 1) * 100 + 12
	return year * 100 + (month - 1)


func months_since(other: GameDate) -> float:
	return (year - other.year) * 12.0 + (month - other.month) + (day - other.day) / 30.0


func clone() -> GameDate:
	return GameDate.new(year, month, day)


func display() -> String:
	return "%s %d" % [MONTH_NAMES[month - 1], year]


func display_full() -> String:
	return "%d %s %d" % [day, MONTH_NAMES[month - 1], year]


func to_dict() -> Dictionary:
	return {"year": year, "month": month, "day": day}


func from_dict(data: Dictionary) -> void:
	year = int(data.get("year", 1850))
	month = int(data.get("month", 1))
	day = int(data.get("day", 1))
