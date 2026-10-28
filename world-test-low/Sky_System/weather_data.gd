class_name WeatherData
extends Node
## Step 3 of 4. The season unlocks a pool of weather. At the start of every 3-hour weather period
## it picks the weather for now and for the next period from that pool, then hands both to
## Weather Conditions.

enum Type { CLEAR, CLOUDY, DRIZZLE, MONSOON, HEAVYRAIN, HAIL, RESIDUAL_SHOWER, MORNING_FOG, HEAT_WAVE, DUST_STORM, DRY_LIGHTNING, CONVECTIVE_RAIN }

# Fields of each entry in WEATHER_TYPES
enum { NAME, CHANCE, EARLIEST_HOUR, LATEST_HOUR }

# [name, chance of being picked, earliest hour, latest hour (-1 = any hour)]
const WEATHER_TYPES = {
	Type.CLEAR: ["Clear", 100, -1, -1],
	Type.CLOUDY: ["Cloudy", 70, -1, -1],
	Type.DRIZZLE: ["Drizzle", 45, -1, -1],
	Type.MONSOON: ["Monsoon Showers", 35, -1, -1],
	Type.HEAVYRAIN: ["Downpour", 25, -1, -1],
	Type.HAIL: ["Hail", 8, -1, -1],
	Type.RESIDUAL_SHOWER: ["Residual Showers", 35, -1, -1],
	Type.MORNING_FOG: ["Morning Fog", 30, 5, 12],
	Type.HEAT_WAVE: ["Heat Wave", 25, 12, 18],
	Type.DUST_STORM: ["Dust Storm", 8, -1, -1],
	Type.DRY_LIGHTNING: ["Dry Lightning", 12, -1, -1],
	Type.CONVECTIVE_RAIN: ["Convective Rain", 20, -1, -1],
}

# The weather each Celestial.Season can bring
const SEASON_WEATHER_POOLS = {
	Celestial.Season.HARVEST: [Type.CLEAR, Type.CLOUDY],
	Celestial.Season.BEGA: [Type.CLEAR, Type.HEAT_WAVE, Type.DUST_STORM],
	Celestial.Season.BELG: [Type.CLOUDY, Type.CLEAR, Type.MORNING_FOG, Type.DRIZZLE, Type.RESIDUAL_SHOWER, Type.CONVECTIVE_RAIN, Type.DRY_LIGHTNING],
	Celestial.Season.KIREMT: [Type.CLOUDY, Type.MORNING_FOG, Type.MONSOON, Type.HEAVYRAIN, Type.HAIL],
}

@export var conditions: WeatherConditions
@export var debug_label: Label
@export var chance_override := {}  # weather type -> chance, to replace the chance above

var current_weather: int = Type.CLEAR
var next_weather: int = Type.CLEAR

## Called by Time when a new 3-hour weather period starts.
func pick_weather_for_period(time: TimeScript) -> void:
	var period_start_hour := time.hour - time.hour % TimeScript.WEATHER_PERIOD_HOURS
	var next_period_hour := (period_start_hour + TimeScript.WEATHER_PERIOD_HOURS) % 24
	# The period after 21:00 starts tomorrow. It is picked again for real when it arrives.
	var next_period_day := time.day_of_year + (1 if next_period_hour == 0 else 0)
	current_weather = _pick_from_season_pool(time.season, time.day_of_year, time.year, period_start_hour)
	next_weather = _pick_from_season_pool(time.season, next_period_day, time.year, next_period_hour)
	if debug_label:
		debug_label.text = "%s => %s" % [WEATHER_TYPES[current_weather][NAME], WEATHER_TYPES[next_weather][NAME]]
	conditions.apply_weather(current_weather, next_weather)

# The same date and hour always give the same weather, so nothing is remembered between periods.
func _pick_from_season_pool(season: int, day_of_year: int, year: int, hour: int) -> int:
	var allowed_types: Array = []
	var total_chance := 0
	for weather_type in SEASON_WEATHER_POOLS[season]:
		var info: Array = WEATHER_TYPES[weather_type]
		var has_hour_limit: bool = info[EARLIEST_HOUR] >= 0
		if has_hour_limit and (hour < info[EARLIEST_HOUR] or hour > info[LATEST_HOUR]):
			continue
		var chance := int(chance_override.get(weather_type, info[CHANCE]))
		total_chance += chance
		allowed_types.append([weather_type, chance])
	if total_chance <= 0:
		return Type.CLEAR
	var pick := (day_of_year * 37 + hour * 17 + year * 13) % total_chance
	for allowed in allowed_types:
		pick -= allowed[1]
		if pick < 0:
			return allowed[0]
	return Type.CLEAR
