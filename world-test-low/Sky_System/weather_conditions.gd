class_name WeatherConditions
extends Node
## Step 3b. What each weather looks like and does: how it tints the sky, how much cloud, rain,
## dust and heat it brings, how strong the sunlight is, how much fog it lays down and how hard the
## wind blows. Sends the cloud, rain, dust, heat and wind values to project-wide shader globals,
## ready for future shaders, then hands the whole profile on to Sky, which plays out the tint,
## sunlight and fog.

# Fields of each entry in WEATHER_PROFILES
enum { SKY_TOP_TINT, SKY_HORIZON_TINT, TINT_STRENGTH, CLOUD_AMOUNT, RAIN_AMOUNT, DUST_AMOUNT, HEAT_AMOUNT, SUN_STRENGTH, FOG_AMOUNT }

# [sky top tint, sky horizon tint, tint strength, cloud, rain, dust, heat, sun strength, fog].
# Clear has no tint: a clear sky is just the time-of-day colours in sky.gd. Sun strength is the
# share of full sunlight that gets through; fog is how far Sky's fog wall closes in (1 = closest).
const WEATHER_PROFILES = {
	WeatherData.Type.CLEAR: [Color(0.44, 0.729, 1.0), Color(0.89, 0.646, 0.347), 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0],
	WeatherData.Type.CLOUDY: [Color(0.357, 0.404, 0.451), Color(0.498, 0.549, 0.6), 0.6, 0.6, 0.0, 0.0, 0.0, 0.7, 0.0],
	WeatherData.Type.DRIZZLE: [Color(0.3, 0.35, 0.4), Color(0.4, 0.45, 0.5), 0.75, 0.7, 0.3, 0.0, 0.0, 0.6, 0.15],
	WeatherData.Type.MONSOON: [Color(0.2, 0.25, 0.3), Color(0.3, 0.35, 0.4), 0.85, 0.85, 0.7, 0.0, 0.0, 0.45, 0.3],
	WeatherData.Type.HEAVYRAIN: [Color(0.1, 0.15, 0.2), Color(0.2, 0.25, 0.3), 0.95, 1.0, 1.0, 0.0, 0.0, 0.3, 0.45],
	WeatherData.Type.HAIL: [Color(0.1, 0.15, 0.2), Color(0.2, 0.25, 0.3), 0.95, 1.0, 0.6, 0.0, 0.0, 0.3, 0.35],
	WeatherData.Type.RESIDUAL_SHOWER: [Color(0.35, 0.4, 0.5), Color(0.45, 0.5, 0.55), 0.65, 0.6, 0.3, 0.0, 0.0, 0.65, 0.1],
	WeatherData.Type.MORNING_FOG: [Color(0.6, 0.6, 0.65), Color(0.7, 0.7, 0.75), 0.8, 0.8, 0.0, 0.0, 0.0, 0.5, 0.8],
	WeatherData.Type.HEAT_WAVE: [Color(0.9, 0.6, 0.3), Color(1.0, 0.8, 0.5), 0.4, 0.0, 0.0, 0.0, 1.0, 1.0, 0.05],
	WeatherData.Type.DUST_STORM: [Color(0.6, 0.45, 0.3), Color(0.7, 0.55, 0.4), 0.9, 0.0, 0.0, 0.9, 0.0, 0.4, 0.6],
	WeatherData.Type.DRY_LIGHTNING: [Color(0.332, 0.296, 0.325), Color(0.35, 0.3, 0.4), 0.7, 0.6, 0.0, 0.0, 0.0, 0.6, 0.0],
	WeatherData.Type.CONVECTIVE_RAIN: [Color(0.15, 0.18, 0.25), Color(0.25, 0.28, 0.35), 0.85, 0.9, 0.8, 0.0, 0.0, 0.35, 0.35],
}

# The shader global each amount is sent to (declared in project.godot)
const SHADER_GLOBAL_FOR_AMOUNT = {
	CLOUD_AMOUNT: &"cloud_amount",
	RAIN_AMOUNT: &"rain_amount",
	DUST_AMOUNT: &"dust_amount",
	HEAT_AMOUNT: &"heatwave_intensity",
}

# Wind strength range for each weather (0 = still, 1 = strongest). A strength inside the range is
# picked each time the weather starts, so no two periods of the same weather blow identically.
const WIND_STRENGTH_RANGE = {
	WeatherData.Type.CLEAR: Vector2(0.1, 0.3),
	WeatherData.Type.CLOUDY: Vector2(0.2, 0.4),
	WeatherData.Type.DRIZZLE: Vector2(0.3, 0.5),
	WeatherData.Type.MONSOON: Vector2(0.5, 0.7),
	WeatherData.Type.HEAVYRAIN: Vector2(0.6, 0.8),
	WeatherData.Type.HAIL: Vector2(0.6, 0.9),
	WeatherData.Type.RESIDUAL_SHOWER: Vector2(0.3, 0.5),
	WeatherData.Type.MORNING_FOG: Vector2(0.0, 0.1),
	WeatherData.Type.HEAT_WAVE: Vector2(0.0, 0.2),
	WeatherData.Type.DUST_STORM: Vector2(0.6, 1.0),
	WeatherData.Type.DRY_LIGHTNING: Vector2(0.4, 0.7),
	WeatherData.Type.CONVECTIVE_RAIN: Vector2(0.5, 0.8),
}
# Most the wind direction can swing when the weather changes (radians; PI / 4 = 45 degrees)
const WIND_DIRECTION_SWING := PI / 4.0

@export var sky: SkyScript
@export var heatwave_strength: float = 0.16  # heatwave_intensity sent during a heat wave

## The world's wind, for scripts to read; shaders read the wind_strength and wind_direction globals.
var wind_strength := 0.0
var wind_direction := Vector2.RIGHT  # horizontal and normalised: x = world X, y = world Z
var _last_sent_amounts := {}
var _random := RandomNumberGenerator.new()

func _ready() -> void:
	_random.randomize()
	wind_direction = Vector2.RIGHT.rotated(_random.randf() * TAU)

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
	_set_wind(current_weather)
	sky.set_weather_profiles(current_profile, WEATHER_PROFILES[next_weather])

# Picks a wind strength from the weather's range and swings the direction a little from where
# it was, then publishes both as shader globals (declared in project.godot).
func _set_wind(weather: int) -> void:
	var strength_range: Vector2 = WIND_STRENGTH_RANGE[weather]
	wind_strength = _random.randf_range(strength_range.x, strength_range.y)
	wind_direction = wind_direction.rotated(_random.randf_range(-WIND_DIRECTION_SWING, WIND_DIRECTION_SWING))
	RenderingServer.global_shader_parameter_set(&"wind_strength", wind_strength)
	RenderingServer.global_shader_parameter_set(&"wind_direction", wind_direction)
