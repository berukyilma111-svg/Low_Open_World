class_name WeatherTable
extends RefCounted
## Weather data and the roll that picks it. Pure: the same season, date and hour always give the
## same weather, so nothing has to be remembered between stops. SkySystem calls `roll` on each stop.

enum Type { CLEAR, CLOUDY, DRIZZLE, MONSOON, HEAVYRAIN, HAIL, RESIDUAL_SHOWER, MORNING_FOG, HEAT_WAVE, DUST_STORM, DRY_LIGHTNING, CONVECTIVE_RAIN }
enum Flag { CLOUDS = 1, RAIN = 2, HAIL = 4, FOG = 8, HEAT = 16, DUST = 32, WIND = 64, LIGHTNING = 128 }

# Fields of each entry in TYPES
enum { NAME, TOP, HORIZON, WEIGHT, CHANCE, FROM_HOUR, TO_HOUR, FLAGS }

# [name, top overlay, horizon overlay, overlay weight, roll chance, allowed from hour, allowed to hour (-1 = any), flags]
const TYPES = {
	Type.CLEAR: ["Clear", Color(0.44, 0.729, 1.0), Color(0.89, 0.646, 0.347), 0.6, 100, -1.0, -1.0, 0],
	Type.CLOUDY: ["Cloudy", Color(0.357, 0.404, 0.451), Color(0.498, 0.549, 0.6), 0.6, 70, -1.0, -1.0, Flag.CLOUDS],
	Type.DRIZZLE: ["Drizzle", Color(0.3, 0.35, 0.4), Color(0.4, 0.45, 0.5), 0.75, 45, -1.0, -1.0, Flag.CLOUDS | Flag.RAIN],
	Type.MONSOON: ["Monsoon Showers", Color(0.2, 0.25, 0.3), Color(0.3, 0.35, 0.4), 0.85, 35, -1.0, -1.0, Flag.CLOUDS | Flag.RAIN | Flag.WIND],
	Type.HEAVYRAIN: ["Downpour", Color(0.1, 0.15, 0.2), Color(0.2, 0.25, 0.3), 0.95, 25, -1.0, -1.0, Flag.CLOUDS | Flag.RAIN | Flag.WIND],
	Type.HAIL: ["Hail", Color(0.1, 0.15, 0.2), Color(0.2, 0.25, 0.3), 0.95, 8, -1.0, -1.0, Flag.CLOUDS | Flag.HAIL | Flag.WIND],
	Type.RESIDUAL_SHOWER: ["Residual Showers", Color(0.35, 0.4, 0.5), Color(0.45, 0.5, 0.55), 0.65, 35, -1.0, -1.0, Flag.CLOUDS | Flag.RAIN],
	Type.MORNING_FOG: ["Morning Fog", Color(0.6, 0.6, 0.65), Color(0.7, 0.7, 0.75), 0.8, 30, 5.0, 12.0, Flag.FOG],
	Type.HEAT_WAVE: ["Heat Wave", Color(0.9, 0.6, 0.3), Color(1.0, 0.8, 0.5), 0.4, 25, 12.0, 18.0, Flag.HEAT],
	Type.DUST_STORM: ["Dust Storm", Color(0.6, 0.45, 0.3), Color(0.7, 0.55, 0.4), 0.9, 8, -1.0, -1.0, Flag.DUST | Flag.WIND],
	Type.DRY_LIGHTNING: ["Dry Lightning", Color(0.332, 0.296, 0.325), Color(0.35, 0.3, 0.4), 0.7, 12, -1.0, -1.0, Flag.CLOUDS | Flag.LIGHTNING | Flag.WIND],
	Type.CONVECTIVE_RAIN: ["Convective Rain", Color(0.15, 0.18, 0.25), Color(0.25, 0.28, 0.35), 0.85, 20, -1.0, -1.0, Flag.CLOUDS | Flag.RAIN | Flag.LIGHTNING],
}

# Weather that can occur in each TimeScript season
const SEASON_POOLS = {
	0: [Type.CLEAR, Type.CLOUDY],
	1: [Type.CLEAR, Type.HEAT_WAVE, Type.DUST_STORM],
	2: [Type.CLOUDY, Type.CLEAR, Type.MORNING_FOG, Type.DRIZZLE, Type.RESIDUAL_SHOWER, Type.CONVECTIVE_RAIN, Type.DRY_LIGHTNING],
	3: [Type.CLOUDY, Type.MORNING_FOG, Type.MONSOON, Type.HEAVYRAIN, Type.HAIL],
}

const DIMMING_FLAGS := Flag.CLOUDS | Flag.RAIN | Flag.HAIL | Flag.FOG | Flag.DUST

static func has_flag(type: int, flag: int) -> bool:
	return (TYPES[type][FLAGS] & flag) != 0

static func data(type: int) -> Array:
	return TYPES[type]

static func roll(season: int, day_of_year: int, year: int, hour: float, chance_override: Dictionary = {}) -> int:
	var eligible: Array = []
	var total := 0
	for w in SEASON_POOLS.get(season, [Type.CLEAR]):
		var entry: Array = TYPES[w]
		if entry[FROM_HOUR] >= 0.0 and (hour < entry[FROM_HOUR] or hour > entry[TO_HOUR]):
			continue
		var chance := int(chance_override.get(w, entry[CHANCE]))
		total += chance
		eligible.append([w, chance])
	if total <= 0:
		return Type.CLEAR
	var r := (day_of_year * 37 + int(hour) * 17 + year * 13) % total
	for e in eligible:
		r -= e[1]
		if r < 0:
			return e[0]
	return Type.CLEAR
