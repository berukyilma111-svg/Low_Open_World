class_name WeatherData
extends Node
## Step 3 of 4. Weather as a chain: each 3-hour weather period's weather is picked from what the
## current weather can realistically turn into (FOLLOWERS), limited to what the season allows.
## Only the very first period is picked straight from the season's pool. The chain carries on
## overnight, and picks are random, so every playthrough has different weather.

enum Type { CLEAR, CLOUDY, DRIZZLE, MONSOON, HEAVYRAIN, HAIL, RESIDUAL_SHOWER, MORNING_FOG, HEAT_WAVE, DUST_STORM, DRY_LIGHTNING, CONVECTIVE_RAIN }

# Fields of each entry in WEATHER_TYPES
enum { NAME, CHANCE, EARLIEST_HOUR, LATEST_HOUR }

# [name, chance when picked from the pool, earliest hour, latest hour (-1 = any hour)]
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

# What each weather can turn into next, and how likely each is (weights within a row)
const FOLLOWERS = {
	Type.CLEAR: {Type.CLEAR: 50, Type.CLOUDY: 25, Type.HEAT_WAVE: 10, Type.MORNING_FOG: 8, Type.DUST_STORM: 7},
	Type.CLOUDY: {Type.CLOUDY: 35, Type.CLEAR: 20, Type.DRIZZLE: 15, Type.MONSOON: 10, Type.CONVECTIVE_RAIN: 8, Type.MORNING_FOG: 7, Type.DRY_LIGHTNING: 5},
	Type.MORNING_FOG: {Type.CLEAR: 50, Type.CLOUDY: 35, Type.DRIZZLE: 15},
	Type.DRIZZLE: {Type.DRIZZLE: 35, Type.CLOUDY: 30, Type.RESIDUAL_SHOWER: 20, Type.MONSOON: 15},
	Type.MONSOON: {Type.MONSOON: 40, Type.HEAVYRAIN: 25, Type.RESIDUAL_SHOWER: 20, Type.CLOUDY: 15},
	Type.HEAVYRAIN: {Type.MONSOON: 40, Type.RESIDUAL_SHOWER: 35, Type.HEAVYRAIN: 15, Type.HAIL: 10},
	Type.HAIL: {Type.HEAVYRAIN: 45, Type.RESIDUAL_SHOWER: 35, Type.CLOUDY: 20},
	Type.RESIDUAL_SHOWER: {Type.CLOUDY: 40, Type.DRIZZLE: 25, Type.CLEAR: 20, Type.MORNING_FOG: 15},
	Type.CONVECTIVE_RAIN: {Type.HEAVYRAIN: 35, Type.RESIDUAL_SHOWER: 30, Type.CLOUDY: 20, Type.HAIL: 15},
	Type.DRY_LIGHTNING: {Type.CLOUDY: 40, Type.CONVECTIVE_RAIN: 25, Type.CLEAR: 20, Type.DUST_STORM: 15},
	Type.HEAT_WAVE: {Type.HEAT_WAVE: 40, Type.CLEAR: 40, Type.DUST_STORM: 15, Type.DRY_LIGHTNING: 5},
	Type.DUST_STORM: {Type.CLEAR: 55, Type.DUST_STORM: 30, Type.CLOUDY: 15},
}

@export var conditions: WeatherConditions
@export var debug_label: Label

var current_weather: int = Type.CLEAR
var next_weather: int = Type.CLEAR
var _has_started := false
var _random := RandomNumberGenerator.new()

func _ready() -> void:
	_random.randomize()

## Called by Time when a new 3-hour weather period starts.
func pick_weather_for_period(time: TimeScript) -> void:
	var period_start_hour := time.hour - time.hour % TimeScript.WEATHER_PERIOD_HOURS
	var next_period_hour := (period_start_hour + TimeScript.WEATHER_PERIOD_HOURS) % 24
	if not _has_started:
		current_weather = _pick_from_season_pool(time.season, period_start_hour)
		_has_started = true
	elif _fits_hours(next_weather, period_start_hour):
		current_weather = next_weather  # last period's forecast comes true
	else:  # time jumped past the forecast's hours
		current_weather = _pick_follower(current_weather, time.season, period_start_hour)
	next_weather = _pick_follower(current_weather, time.season, next_period_hour)
	if debug_label:
		debug_label.text = "%s => %s" % [WEATHER_TYPES[current_weather][NAME], WEATHER_TYPES[next_weather][NAME]]
	conditions.apply_weather(current_weather, next_weather)

# Picks what `weather_type` turns into, preferring followers the season has. Right after a season
# change there may be none: the weather then winds down through its usual followers (a downpour
# eases into residual showers, then cloud) until the chain reaches the new season's weather.
func _pick_follower(weather_type: int, season: int, period_start_hour: int) -> int:
	var in_season := {}
	var winding_down := {}
	for follower in FOLLOWERS[weather_type]:
		if _fits_hours(follower, period_start_hour):
			winding_down[follower] = FOLLOWERS[weather_type][follower]
			if follower in SEASON_WEATHER_POOLS[season]:
				in_season[follower] = FOLLOWERS[weather_type][follower]
	if not in_season.is_empty():
		return _weighted_random_pick(in_season)
	if not winding_down.is_empty():
		return _weighted_random_pick(winding_down)
	return _pick_from_season_pool(season, period_start_hour)

func _pick_from_season_pool(season: int, period_start_hour: int) -> int:
	var choices := {}
	for weather_type in SEASON_WEATHER_POOLS[season]:
		if _fits_hours(weather_type, period_start_hour):
			choices[weather_type] = WEATHER_TYPES[weather_type][CHANCE]
	return _weighted_random_pick(choices) if not choices.is_empty() else Type.CLEAR

# Morning Fog and Heat Wave only happen at certain hours: the whole 3-hour period must fit.
func _fits_hours(weather_type: int, period_start_hour: int) -> bool:
	var info: Array = WEATHER_TYPES[weather_type]
	if info[EARLIEST_HOUR] < 0:
		return true
	return period_start_hour >= info[EARLIEST_HOUR] and period_start_hour + TimeScript.WEATHER_PERIOD_HOURS <= info[LATEST_HOUR]

# `choices` maps weather type -> weight; a weight of 30 is three times as likely as 10.
func _weighted_random_pick(choices: Dictionary) -> int:
	var total_weight := 0
	for weight in choices.values():
		total_weight += weight
	var pick := _random.randi_range(1, total_weight)
	for weather_type in choices:
		pick -= choices[weather_type]
		if pick <= 0:
			return weather_type
	return choices.keys()[0]
