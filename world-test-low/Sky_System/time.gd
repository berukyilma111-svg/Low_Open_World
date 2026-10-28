class_name TimeScript
extends Node
## The only clock. Counts minutes like a stopwatch and calls the sky only at the points in time
## that need it: every minute, every 3-hour stop, and every new day.

const STOP_HOURS := 3
const MONTH_NAMES = ["Month_1", "Month_2", "Month_3", "Month_4", "Month_5", "Month_6", "Month_7", "Month_8", "Month_9", "Month_10", "Month_11", "Month_12", "Month_13"]
const SEASON_NAMES = ["(MSKRM) / Harvest", "(BGA) / Dry Season", "(BLG) / Short Rains", "(KRMT) / Monsoon"]

@export var sky: SkySystem
@export var debug_label: Label
@export var minute_per_second: float = 60.0

@export_group("Date & Calendar (Ethiopian Specification)")
@export var year: int = 2018
@export_range(1, 13) var month: int = 1
@export_range(1, 30) var day: int = 1
@export_range(0, 23) var hour: int = 12
@export_range(0, 59) var minute: int = 0

var _minute_fraction: float = 0.0

func _ready() -> void:
	# Give the sky the starting state once the rest of the scene is ready.
	_start.call_deferred()

func _start() -> void:
	sky.on_day(self)
	sky.on_stop(self)
	_on_minutes_passed()

func _process(delta: float) -> void:
	_minute_fraction += delta * minute_per_second
	if _minute_fraction < 1.0:
		return
	# More than one minute can pass in a frame when time runs fast.
	while _minute_fraction >= 1.0:
		_minute_fraction -= 1.0
		_increment_minute()
	_on_minutes_passed()

func _increment_minute() -> void:
	minute += 1
	if minute < 60:
		return
	minute = 0
	hour += 1
	if hour >= 24:
		hour = 0
		_increment_day()
		sky.on_day(self)
	if hour % STOP_HOURS == 0:
		sky.on_stop(self)

func _increment_day() -> void:
	day += 1
	var days_in_month := 30 if month <= 12 else (6 if year % 4 == 3 else 5)
	if day <= days_in_month:
		return
	day = 1
	month += 1
	if month > 13:
		month = 1
		year += 1

func _on_minutes_passed() -> void:
	sky.on_minute(self)
	if debug_label:
		debug_label.text = "Year %d | %s %d | [%s] | %d:%02d %s" % [year, MONTH_NAMES[month - 1], day, SEASON_NAMES[season()], 12 if hour % 12 == 0 else hour % 12, minute, "PM" if hour >= 12 else "AM"]

# --- Read by the sky; worked out from the date when asked, nothing stored ---
func hours() -> float:
	return hour + minute / 60.0

func time_of_day() -> float:
	return (hour * 60 + minute) / 1440.0

func stop() -> int:
	return hour / STOP_HOURS

func day_of_year() -> int:
	return (month - 1) * 30 + day

func total_days() -> int:
	return year * 365 + year / 4 + day_of_year()

func season() -> int:
	return 0 if month <= 3 else 1 if month <= 6 else 2 if month <= 9 else 3

func year_length() -> float:
	return 366.0 if year % 4 == 3 else 365.0
