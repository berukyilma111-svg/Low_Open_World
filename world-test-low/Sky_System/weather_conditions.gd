class_name WeatherConditions
extends Node
## Step 3b. What each weather looks like and does: its sky tint, and how much cloud, rain, dust and
## heat it brings. Sends those amounts to project-wide shader globals, ready for future cloud,
## rain, dust and heat shaders, then hands the sky tints on to Sky.

# Fields of each entry in LOOKS
enum { TOP, HORIZON, WEIGHT, CLOUD, RAIN, DUST, HEAT }

# [top tint, horizon tint, tint weight, cloud, rain, dust, heat]
const LOOKS = {
	WeatherData.Type.CLEAR: [Color(0.44, 0.729, 1.0), Color(0.89, 0.646, 0.347), 0.6, 0.0, 0.0, 0.0, 0.0],
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

# Shader globals for CLOUD, RAIN, DUST and HEAT, in that order (declared in project.godot)
const GLOBALS: Array[StringName] = [&"cloud_amount", &"rain_amount", &"dust_amount", &"heatwave_intensity"]

@export var sky: SkyScript
@export var heatwave_strength: float = 0.16

var _sent: Array[float] = [-1.0, -1.0, -1.0, -1.0]

func apply(current: int, upcoming: int) -> void:
	var now: Array = LOOKS[current]
	for i in GLOBALS.size():
		var amount: float = now[CLOUD + i] * (heatwave_strength if CLOUD + i == HEAT else 1.0)
		if amount != _sent[i]:
			_sent[i] = amount
			RenderingServer.global_shader_parameter_set(GLOBALS[i], amount)
	sky.on_weather(now, LOOKS[upcoming])
