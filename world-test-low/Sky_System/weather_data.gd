class_name WeatherData
extends Node
## Step 3 of 4. The season unlocks a pool of weather. Every 3-hour stop picks the weather for now
## and a forecast for the next stop from that pool, then hands both to Weather Conditions.

enum Type { CLEAR, CLOUDY, DRIZZLE, MONSOON, HEAVYRAIN, HAIL, RESIDUAL_SHOWER, MORNING_FOG, HEAT_WAVE, DUST_STORM, DRY_LIGHTNING, CONVECTIVE_RAIN }

# [name, roll chance, allowed from hour, allowed to hour (-1 = any hour)]
const TYPES = {
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

# Weather each Celestial.Season can bring
const SEASON_POOLS = {
	Celestial.Season.HARVEST: [Type.CLEAR, Type.CLOUDY],
	Celestial.Season.BEGA: [Type.CLEAR, Type.HEAT_WAVE, Type.DUST_STORM],
	Celestial.Season.BELG: [Type.CLOUDY, Type.CLEAR, Type.MORNING_FOG, Type.DRIZZLE, Type.RESIDUAL_SHOWER, Type.CONVECTIVE_RAIN, Type.DRY_LIGHTNING],
	Celestial.Season.KIREMT: [Type.CLOUDY, Type.MORNING_FOG, Type.MONSOON, Type.HEAVYRAIN, Type.HAIL],
}

@export var conditions: WeatherConditions
@export var debug_label: Label
@export var chance_override := {}

var current: int = Type.CLEAR
var upcoming: int = Type.CLEAR

func on_stop(t: TimeScript) -> void:
	var start := t.hour - t.hour % TimeScript.STOP_HOURS
	var next := (start + TimeScript.STOP_HOURS) % 24
	current = _roll(t.season, t.day_of_year, t.year, start)
	# The forecast after 21:00 is for tomorrow; the stop itself is rolled again when it arrives.
	upcoming = _roll(t.season, t.day_of_year + (1 if next == 0 else 0), t.year, next)
	if debug_label:
		debug_label.text = "%s => %s" % [TYPES[current][0], TYPES[upcoming][0]]
	conditions.apply(current, upcoming)

# Same date and hour always give the same weather, so nothing is remembered between stops.
func _roll(season: int, day_of_year: int, year: int, hour: int) -> int:
	var eligible: Array = []
	var total := 0
	for w in SEASON_POOLS[season]:
		var entry: Array = TYPES[w]
		if entry[2] >= 0 and (hour < entry[2] or hour > entry[3]):
			continue
		var chance := int(chance_override.get(w, entry[1]))
		total += chance
		eligible.append([w, chance])
	if total <= 0:
		return Type.CLEAR
	var r := (day_of_year * 37 + hour * 17 + year * 13) % total
	for e in eligible:
		r -= e[1]
		if r < 0:
			return e[0]
	return Type.CLEAR
