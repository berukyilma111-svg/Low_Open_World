class_name TimeScript
extends Node
## Step 2 of 4. Reads the clock off Celestial's sun and counts it into the Ethiopian calendar:
## 60 minutes an hour, 24 hours a day, 30 days a month for 12 months, then Pagume until the Earth
## completes its orbit (5 days, or 6 every fourth year). Registers the season Celestial gives,
## then tells Weather Data when a 3-hour stop starts and Sky when a minute passes.

const STOP_HOURS := 3
const MONTH_NAMES = ["Month_1", "Month_2", "Month_3", "Month_4", "Month_5", "Month_6", "Month_7", "Month_8", "Month_9", "Month_10", "Month_11", "Month_12", "Month_13"]
const SEASON_NAMES = ["(MSKRM) / Harvest", "(BGA) / Dry Season", "(BLG) / Short Rains", "(KRMT) / Monsoon"]

@export var weather: WeatherData
@export var sky: SkyScript
@export var debug_label: Label

@export_group("Start date (Ethiopian calendar)")
@export var year: int = 2018
@export_range(1, 13) var month: int = 1
@export_range(1, 30) var day: int = 1
@export_range(0, 23) var hour: int = 12
@export_range(0, 59) var minute: int = 0

var season: int = 0
var day_of_year: int = 1
var _day_count := -1
var _minute_count := -1

## Where Celestial starts the Earth so its sun matches the start date above. Ethiopian leap
## years (year % 4 == 3) land where the orbit's quarter days add up, one orbit ahead of the year.
func start_days() -> float:
	return ceil((year + 1) * Celestial.ORBIT_DAYS) + (month - 1) * 30 + day - 1 + (hour * 60 + minute) / 1440.0

func advance(c: Celestial) -> void:
	var minutes := int(c.days * 1440.0)
	if minutes == _minute_count:
		return
	var first := _minute_count < 0
	_minute_count = minutes
	var days := int(c.days)
	var new_day := days != _day_count
	# One calendar step per midnight passed, even when time runs fast.
	while not first and _day_count < days:
		_day_count += 1
		_next_day(_day_count)
	_day_count = days
	var old_stop := hour / STOP_HOURS
	hour = (minutes / 60) % 24
	minute = minutes % 60
	day_of_year = (month - 1) * 30 + day
	if new_day:
		season = c.season()
	if first or new_day or hour / STOP_HOURS != old_stop:
		weather.on_stop(self)
	sky.on_minute(c, self)
	if debug_label:
		debug_label.text = "Year %d | %s %d | [%s] | %d:%02d %s" % [year, MONTH_NAMES[month - 1], day, SEASON_NAMES[season], 12 if hour % 12 == 0 else hour % 12, minute, "PM" if hour >= 12 else "AM"]

func _next_day(day_count: int) -> void:
	day += 1
	if month == 13:
		# Pagume runs until the Earth completes its orbit, then the new year starts.
		if int(day_count / Celestial.ORBIT_DAYS) - 1 > year:
			year += 1
			month = 1
			day = 1
	elif day > 30:
		day = 1
		month += 1
