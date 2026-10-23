class_name TimeScript
extends Node
## Top of the chain: advances the Ethiopian calendar clock and announces what changed.
## Nothing downstream keeps its own time; everything reacts to these signals.

signal minute_ticked
signal stop_changed(stop: int)
signal day_changed
signal season_changed(season: int)

const STOP_HOURS := 3.0
const MONTH_NAMES = ["Month_1", "Month_2", "Month_3", "Month_4", "Month_5", "Month_6", "Month_7", "Month_8", "Month_9", "Month_10", "Month_11", "Month_12", "Month_13"]
const SEASON_NAMES = ["(MSKRM) / Harvest", "(BGA) / Dry Season", "(BLG) / Short Rains", "(KRMT) / Monsoon"]

@export var debug_label: Label
@export var minute_per_second: float = 60.0

@export_group("Date & Calendar (Ethiopian Specification)")
@export var year: int = 2018
@export_range(1, 13) var month: int = 1
@export_range(1, 30) var day: int = 1
@export_range(0, 23) var hour: int = 12
@export_range(0, 59) var minute: int = 0

var season: int = 0
var stop: int = 0
var day_of_year: int = 1
var total_days: int = 0
var _minute_fraction: float = 0.0

func _ready() -> void:
	_update_date()
	stop = int(hour / STOP_HOURS)
	# Downstream nodes connect in their own _ready, so announce the starting state once they are listening.
	_announce.call_deferred()

func _announce() -> void:
	season_changed.emit(season)
	day_changed.emit()
	stop_changed.emit(stop)
	_tick()

func _process(delta: float) -> void:
	_minute_fraction += delta * minute_per_second
	if _minute_fraction < 1.0:
		return
	var steps := int(_minute_fraction)
	_minute_fraction -= steps
	minute += steps
	var new_day := false
	while minute >= 60:
		minute -= 60
		hour += 1
		if hour >= 24:
			hour = 0
			new_day = true
			_advance_day()
	# Date first, then stop: weather rolled at midnight must already see the new season.
	if new_day:
		var old_season := season
		_update_date()
		day_changed.emit()
		if season != old_season:
			season_changed.emit(season)
	var new_stop := int(hour / STOP_HOURS)
	if new_stop != stop:
		stop = new_stop
		stop_changed.emit(stop)
	_tick()

func _tick() -> void:
	minute_ticked.emit()
	if debug_label:
		debug_label.text = "Year %d | %s %d | [%s] | %d:%02d %s" % [year, MONTH_NAMES[month - 1], day, SEASON_NAMES[season], 12 if hour % 12 == 0 else hour % 12, minute, "PM" if hour >= 12 else "AM"]

func hours() -> float:
	return hour + minute / 60.0

func time_of_day() -> float:
	return (hour * 60 + minute) / 1440.0

func year_length() -> float:
	return 366.0 if year % 4 == 3 else 365.0

func _advance_day() -> void:
	day += 1
	var days_in_month := 30 if month < 13 else (6 if year % 4 == 3 else 5)
	if day > days_in_month:
		day = 1
		month += 1
		if month > 13:
			month = 1
			year += 1

func _update_date() -> void:
	day_of_year = (month - 1) * 30 + day
	total_days = year * 365 + int(year / 4) + day_of_year
	season = 0 if month <= 3 else 1 if month <= 6 else 2 if month <= 9 else 3
