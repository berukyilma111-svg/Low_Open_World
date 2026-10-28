class_name WeatherConditions
extends Node
## Step 3b. What each weather looks like and does: how it tints the sky, and how much cloud,
## rain, dust and heat it brings. Sends those amounts to project-wide shader globals, ready for
## future cloud, rain, dust and heat shaders, then hands the sky tints on to Sky.

# Fields of each entry in WEATHER_PROFILES
enum { SKY_TOP_TINT, SKY_HORIZON_TINT, TINT_STRENGTH, CLOUD_AMOUNT, RAIN_AMOUNT, DUST_AMOUNT, HEAT_AMOUNT }

# [sky top tint, sky horizon tint, tint strength, cloud, rain, dust, heat]. Clear has no tint: a
# clear sky is just the time-of-day colours in sky.gd.
const WEATHER_PROFILES = {
	WeatherData.Type.CLEAR: [Color(0.44, 0.729, 1.0), Color(0.89, 0.646, 0.347), 0.0, 0.0, 0.0, 0.0, 0.0],
	WeatherData.Type.CLOUDY: [Color(0.357, 0.404, 0.451), Color(0.498, 0.549, 0.6), 0.6, 0.6, 0.0, 0.0, 0.0],
	WeatherData.Type.DRIZZLE: [Color(0.3, 0.35, 0.4), Color(0.4, 0.45, 0.5), 0.75, 0.7, 0.3, 0.0, 0.0],
	WeatherData.Type.MONSOON: [Color(0.2, 0.25, 0.3), Color(0.3, 0.35, 0.4), 0.85, 0.85, 0.7, 0.0, 0.0],
	WeatherData.Type.HEAVYRAIN: [Color(0.1, 0.15, 0.2), Color(0.2, 0.25, 0.3), 0.95, 1.0, 1.0, 0.0, 0.0],
	WeatherData.Type.HAIL: [Color(0.1, 0.15, 0.2), Color(0.2, 0.25, 0.3), 0.95, 1.0, 0.6, 0.0, 0.0],
	WeatherData.Type.RESIDUAL_SHOWER: [Color(0.35, 0.4, 0.5), Color(0.45, 0.5, 0.55), 0.65, 0.6, 0.3, 0.0, 0.0],
	WeatherData.Type.MORNING_FOG: [Color(0.6, 0.6, 0.65), Color(0.7, 0.7, 0.75), 0.8, 0.8, 0.0, 0.0, 0.0],
	WeatherData.Type.HEAT_WAVE: [Color(0.9, 0.6, 0.3), Color(1.0, 0.8, 0.5), 0.4, 0.0, 0.0, 0.0, 1.0],
	WeatherData.Type.DUST_STORM: [Color(0.6, 0.45, 0.3), Color(0.7, 0.55, 0.4), 0.9, 0.0, 0.0, 0.9, 0.0],
	WeatherData.Type.DRY_LIGHTNING: [Color(0.332, 0.296, 0.325), Color(0.35, 0.3, 0.4), 0.7, 0.6, 0.0, 0.0, 0.0],
	WeatherData.Type.CONVECTIVE_RAIN: [Color(0.15, 0.18, 0.25), Color(0.25, 0.28, 0.35), 0.85, 0.9, 0.8, 0.0, 0.0],
}

# The shader global each amount is sent to (declared in project.godot)
const SHADER_GLOBAL_FOR_AMOUNT = {
	CLOUD_AMOUNT: &"cloud_amount",
	RAIN_AMOUNT: &"rain_amount",
	DUST_AMOUNT: &"dust_amount",
	HEAT_AMOUNT: &"heatwave_intensity",
}

@export var sky: SkyScript
@export var heatwave_strength: float = 0.16  # heatwave_intensity sent during a heat wave

var _last_sent_amounts := {}

## Called by Weather Data at the start of each 3-hour weather period.
func apply_weather(current_weather: int, next_weather: int) -> void:
	var current_profile: Array = WEATHER_PROFILES[current_weather]
	for amount_field in SHADER_GLOBAL_FOR_AMOUNT:
		var amount: float = current_profile[amount_field]
		if amount_field == HEAT_AMOUNT:
			amount *= heatwave_strength
		if _last_sent_amounts.get(amount_field) != amount:
			_last_sent_amounts[amount_field] = amount
			RenderingServer.global_shader_parameter_set(SHADER_GLOBAL_FOR_AMOUNT[amount_field], amount)
	sky.set_weather_profiles(current_profile, WEATHER_PROFILES[next_weather])
