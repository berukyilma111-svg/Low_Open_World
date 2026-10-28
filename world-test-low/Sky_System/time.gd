class_name TimeScript
extends Node
## Step 2 of 4. Reads the clock off Celestial's sun and counts it into the Ethiopian calendar:
## 60 minutes an hour, 24 hours a day, 30 days a month for 12 months, then Pagume until the Earth
## completes its orbit (5 days, or 6 every fourth year). Records the season Celestial gives, tells
## Weather Data when a new 3-hour weather period starts, and tells Sky every new minute.

const WEATHER_PERIOD_HOURS := 3
const MONTH_NAMES = ["Month_1", "Month_2", "Month_3", "Month_4", "Month_5", "Month_6", "Month_7", "Month_8", "Month_9", "Month_10", "Month_11", "Month_12", "Month_13"]
const SEASON_NAMES = ["(MSKRM) / Harvest", "(BGA) / Dry Season", "(BLG) / Short Rains", "(KRMT) / Monsoon"]
const COMPASS_POINTS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

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
var _last_elapsed_day := -1
var _last_elapsed_minute := -1

## Where Celestial starts the Earth so its sun matches the start date above. Ethiopian leap
## years (year % 4 == 3) land where the orbit's quarter days add up, one orbit ahead of the year.
func start_date_as_elapsed_days() -> float:
	var new_year_day := ceilf((year + 1) * Celestial.DAYS_PER_ORBIT)
	return new_year_day + (month - 1) * 30 + (day - 1) + (hour * 60 + minute) / 1440.0

## Called by Celestial every frame. Does nothing until a new game minute has passed.
func update_from_celestial(celestial: Celestial) -> void:
	var elapsed_minute := int(celestial.elapsed_days * 1440.0)
	if elapsed_minute == _last_elapsed_minute:
		return
	var is_first_update := _last_elapsed_minute < 0
	_last_elapsed_minute = elapsed_minute
	var elapsed_day := int(celestial.elapsed_days)
	var is_new_day := elapsed_day != _last_elapsed_day
	# One calendar step per midnight passed, even when time runs fast.
	while not is_first_update and _last_elapsed_day < elapsed_day:
		_last_elapsed_day += 1
		_advance_calendar_one_day(_last_elapsed_day)
	_last_elapsed_day = elapsed_day
	var previous_weather_period := hour / WEATHER_PERIOD_HOURS
	hour = (elapsed_minute / 60) % 24
	minute = elapsed_minute % 60
	day_of_year = (month - 1) * 30 + day
	if is_new_day:
		season = celestial.current_season()
	if is_first_update or is_new_day or hour / WEATHER_PERIOD_HOURS != previous_weather_period:
		weather.pick_weather_for_period(self)
	sky.update_sky(celestial, self)
	_show_debug_text()

func _advance_calendar_one_day(elapsed_day: int) -> void:
	day += 1
	if month == 13:
		# Pagume runs until the Earth completes its orbit, then the new year starts.
		var completed_orbits := int(elapsed_day / Celestial.DAYS_PER_ORBIT)
		if completed_orbits - 1 > year:
			year += 1
			month = 1
			day = 1
	elif day > 30:
		day = 1
		month += 1

func _show_debug_text() -> void:
	if debug_label:
		var clock_hour := 12 if hour % 12 == 0 else hour % 12
		debug_label.text = "Year %d | %s %d | [%s] | %d:%02d %s" % [year, MONTH_NAMES[month - 1], day, SEASON_NAMES[season], clock_hour, minute, "PM" if hour >= 12 else "AM"]
		var wind := weather.conditions
		debug_label.text += " | Wind blowing %s at %d%%" % [_compass_point(wind.wind_direction), roundi(wind.wind_strength * 100.0)]

# The compass point a horizontal direction heads toward, with north as world -Z and east as +X.
static func _compass_point(direction: Vector2) -> String:
	var heading := atan2(direction.x, -direction.y)  # 0 = north, turning clockwise
	return COMPASS_POINTS[posmod(roundi(heading / (TAU / 8.0)), 8)]
