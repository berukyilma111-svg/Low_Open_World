extends Node

@export_group("References")
@export var Sun: DirectionalLight3D
@export var MoonTransform: Node3D
@export var world_env: WorldEnvironment
@export var debug_label: Label
var active_sky_material: ShaderMaterial

@export_group("Time Settings")
@export var minute_per_second: float = 60.0

@export_group("Date & Calendar (Ethiopian Specification)")
@export var year: int = 2018
@export_range(1, 13) var month: int = 1
@export_range(1, 30) var day: int = 1
@export_range(0, 23) var hour: int = 12
@export_range(0, 59) var minute: int = 0

@export_group("Geography")
@export var latitude: float = 10.7058
@export_range(0, 360) var north_offset_degrees: float = 0.0

# --- STATE VARIABLES ---
var active_time_stop: float = 0.0
var active_season: int = 0
var active_constellation: int = 0
var is_day: bool = true

var cached_moon_phase: float = 0.0
var cached_moon_altitude: float = 0.0
var cached_moon_azimuth: float = 0.0
var cached_moon_angular_size: float = 0.009
var cached_moon_direction: Vector3 = Vector3(0.0, -1.0, 0.0)
@export var moon_base_angular_size: float = 0.009

@export_group("Stars")
@export_range(0.0, 0.2, 0.001) var star_coverage: float = 0.015
@export_range(0.05, 0.9, 0.01) var star_max_size: float = 0.35


var _60_minute_count: float = 0.0
var time_of_day: float = 0.5
var day_of_year: int = 1
var total_days_passed: int = 0
var geographic_latitude_sin: float
var geographic_latitude_cos: float
var true_north_conversion: float
var orbit_speed: float
var seasonal_sun_altitude: float
var horizon_shift_bias: float
var earth_tilt_tan: float
var equation_of_time: float
var climate_blend: float

enum WEATHER_TYPE { CLEAR, CLOUDY, DRIZZLE, MONSOON, HEAVYRAIN, HAIL, RESIDUAL_SHOWER, MORNING_FOG, HEAT_WAVE, DUST_STORM, DRY_LIGHTNING, CONVECTIVE_RAIN }

const WEATHER = {
	"types": {
		WEATHER_TYPE.CLEAR: ["Clear", Color(0.44, 0.729, 1.0, 0.796), Color(0.89, 0.646, 0.347, 0.757), 0.6, 100, -1.0, -1.0],
		WEATHER_TYPE.CLOUDY: ["Cloudy", Color(0.357, 0.404, 0.451, 0.835), Color(0.498, 0.549, 0.6, 0.702), 0.6, 70, -1.0, -1.0],
		WEATHER_TYPE.DRIZZLE: ["Drizzle", Color(0.3, 0.35, 0.4), Color(0.4, 0.45, 0.5), 0.75, 45, -1.0, -1.0],
		WEATHER_TYPE.MONSOON: ["Monsoon Showers", Color(0.2, 0.25, 0.3), Color(0.3, 0.35, 0.4), 0.85, 35, -1.0, -1.0],
		WEATHER_TYPE.HEAVYRAIN: ["Downpour", Color(0.1, 0.15, 0.2), Color(0.2, 0.25, 0.3), 0.95, 25, -1.0, -1.0],
		WEATHER_TYPE.HAIL: ["Hail", Color(0.1, 0.15, 0.2), Color(0.2, 0.25, 0.3), 0.95, 8, -1.0, -1.0],
		WEATHER_TYPE.RESIDUAL_SHOWER: ["Residual Showers", Color(0.35, 0.4, 0.5), Color(0.45, 0.5, 0.55), 0.65, 35, -1.0, -1.0],
		WEATHER_TYPE.MORNING_FOG: ["Morning Fog", Color(0.6, 0.6, 0.65), Color(0.7, 0.7, 0.75), 0.8, 30, 5.0, 12.0],
		WEATHER_TYPE.HEAT_WAVE: ["Heat Wave", Color(0.9, 0.6, 0.3), Color(1.0, 0.8, 0.5), 0.4, 25, 12.0, 18.0],
		WEATHER_TYPE.DUST_STORM: ["Dust Storm", Color(0.6, 0.45, 0.3), Color(0.7, 0.55, 0.4), 0.9, 8, -1.0, -1.0],
		WEATHER_TYPE.DRY_LIGHTNING: ["Dry Lightning", Color(0.332, 0.296, 0.325, 1.0), Color(0.35, 0.3, 0.4), 0.7, 12, -1.0, -1.0],
		WEATHER_TYPE.CONVECTIVE_RAIN: ["Convective Rain", Color(0.15, 0.18, 0.25), Color(0.25, 0.28, 0.35), 0.85, 20, -1.0, -1.0]
	},
	"seasonal patterns": {
		0: [WEATHER_TYPE.CLEAR, WEATHER_TYPE.CLOUDY],
		1: [WEATHER_TYPE.CLEAR, WEATHER_TYPE.HEAT_WAVE, WEATHER_TYPE.DUST_STORM],
		2: [WEATHER_TYPE.CLOUDY, WEATHER_TYPE.CLEAR, WEATHER_TYPE.MORNING_FOG, WEATHER_TYPE.DRIZZLE, WEATHER_TYPE.RESIDUAL_SHOWER, WEATHER_TYPE.CONVECTIVE_RAIN, WEATHER_TYPE.DRY_LIGHTNING],
		3: [WEATHER_TYPE.CLOUDY, WEATHER_TYPE.MORNING_FOG, WEATHER_TYPE.MONSOON, WEATHER_TYPE.HEAVYRAIN, WEATHER_TYPE.HAIL]
	}
}

@export var weather_chance_override := {}
const SYNODIC_MONTH_DAYS: float = 29.53059
const MONTH_NAMES = ["Month_1", "Month_2", "Month_3", "Month_4", "Month_5", "Month_6", "Month_7", "Month_8", "Month_9", "Month_10", "Month_11", "Month_12", "Month_13"]
const SEASONS = ["(MSKRM) / Harvest", "(BGA) / Dry Season", "(BLG) / Short Rains", "(KRMT) / Monsoon"]
const TIME_STOPS: Array[float] = [0.0, 3.0, 6.0, 9.0, 12.0, 15.0, 18.0, 21.0, 24.0]

const BASE_TOP: Array[Color] = [Color(0.065, 0.058, 0.227, 1.0), Color(0.00, 0.14, 0.25, 1.0), Color(0.86, 0.638, 0.43, 1.0), Color(0.022, 0.368, 0.609, 1.0), Color(0.335, 0.68, 0.99, 1.0), Color(0.18, 0.52, 0.8, 1.0), Color(0.93, 0.52, 0.441, 1.0), Color(0.06, 0.052, 0.223, 1.0), Color(0.006, 0.045, 0.214, 1.0)]
const BASE_HORIZ: Array[Color] = [Color(0.006, 0.045, 0.214, 1.0), Color(0.23, 0.23, 0.37, 1.0), Color(0.861, 0.522, 0.212, 1.0), Color(0.75, 0.84, 0.97, 1.0), Color(0.874, 0.936, 0.999, 1.0), Color(0.81, 0.88, 0.96, 1.0), Color(0.988, 0.755, 0.554, 1.0), Color(0.193, 0.183, 0.526, 1.0), Color(0.065, 0.058, 0.227, 1.0)]

var current_time_idx: int = -1
var active_weather: int = WEATHER_TYPE.CLEAR
var next_weather: int = WEATHER_TYPE.CLEAR
var cached_w_act: Array = WEATHER["types"][WEATHER_TYPE.CLEAR]
var cached_weather_next: Array = WEATHER["types"][WEATHER_TYPE.CLEAR]

func _ready() -> void:
	var lat_rad: float = deg_to_rad(latitude)
	geographic_latitude_sin = sin(lat_rad)
	geographic_latitude_cos = cos(lat_rad)
	true_north_conversion = deg_to_rad(north_offset_degrees)
	_recalculate_calendar_totals()
	TimeStates()
	if world_env and world_env.environment and world_env.environment.sky:
		active_sky_material = world_env.environment.sky.sky_material as ShaderMaterial

func _process(delta: float) -> void:
	TimeIncrementation(delta)
	UpdateDynamicOrbits()
	CelestialPaths()
	ExecuteAtmospherePipeline()

func TimeIncrementation(delta: float) -> void:
	_60_minute_count += delta * minute_per_second
	if _60_minute_count >= 1.0:
		var p := int(_60_minute_count)
		minute += p
		_60_minute_count -= p
		while minute >= 60:
			minute -= 60
			hour += 1
			if hour >= 24:
				hour -= 24
				day += 1
				var days_in_month := 6 if (month == 13 and year % 4 == 3) else 5 if month == 13 else 30
				if day > days_in_month:
					day = 1
					month += 1
					if month > 13:
						month = 1
						year += 1
		_recalculate_calendar_totals()
		TimeStates()
		UpdateUI()
	time_of_day = (hour * 60 + minute + _60_minute_count) / 1440.0

func _recalculate_calendar_totals() -> void:
	day_of_year = (month - 1) * 30 + day
	total_days_passed = year * 365 + int(year / 4) + day_of_year

func TimeStates() -> void:
	orbit_speed = TAU / (366.0 if year % 4 == 3 else 365.0)
	var CurrentHour: float = hour + (minute / 60.0)
	is_day = (CurrentHour >= 6.5 and CurrentHour < 18.0)
	for i in range(TIME_STOPS.size() - 1):
		if CurrentHour >= TIME_STOPS[i] and CurrentHour < TIME_STOPS[i + 1]:
			if i != current_time_idx:
				_CaptureStopBounds(i)
			break
	active_season = 0 if month <= 3 else 1 if month <= 6 else 3 if month >= 10 else 2
	active_constellation = month - 1

func _CaptureStopBounds(i: int) -> void:
	current_time_idx = i
	active_weather = next_weather if current_time_idx != -1 else DetermineNextWeather(active_season, TIME_STOPS[i], WEATHER_TYPE.CLEAR)
	next_weather = DetermineNextWeather(active_season, TIME_STOPS[i + 1], active_weather)
	cached_w_act = WEATHER["types"][active_weather]
	cached_weather_next = WEATHER["types"][next_weather]

func ExecuteAtmospherePipeline() -> void:
	if not active_sky_material:
		return
	
	var current_hour := time_of_day * 24.0
	var night := _night_strength(current_hour)
	var idx := clampi(current_time_idx, 0, TIME_STOPS.size() - 2)
	var t := clampf((current_hour - TIME_STOPS[idx]) / (TIME_STOPS[idx + 1] - TIME_STOPS[idx]), 0.0, 1.0)

	var top_color = _lerp_dark(BASE_TOP[idx], BASE_TOP[idx + 1], t, night * 0.72)
	var horizon_color = _lerp_dark(BASE_HORIZ[idx], BASE_HORIZ[idx + 1], t, night * 0.68)
	var weather_top = _lerp_dark(cached_w_act[1], cached_weather_next[1], t, night * 0.8)
	var weather_horizon = _lerp_dark(cached_w_act[2], cached_weather_next[2], t, night * 0.78)
	var weather_weight = lerp(cached_w_act[3], cached_weather_next[3], t) * (1.0 - night * 0.85)

	active_sky_material.set_shader_parameter("top_color", top_color)
	active_sky_material.set_shader_parameter("horizon_color", horizon_color)
	active_sky_material.set_shader_parameter("weather_top_color", weather_top)
	active_sky_material.set_shader_parameter("weather_horizon_color", weather_horizon)
	active_sky_material.set_shader_parameter("weather_weight", weather_weight)
	active_sky_material.set_shader_parameter("ground_color", top_color)

	# AirglowMaterial:
	var solar_cycle := 0.75 + 0.25 * sin(float(year) * 0.57)
	active_sky_material.set_shader_parameter("airglow_intensity", _SeasonAirglow(active_season) * night * (1.0 - weather_weight) * solar_cycle)


	# StarMaterial:
	active_sky_material.set_shader_parameter("star_coverage", star_coverage)
	active_sky_material.set_shader_parameter("star_max_size", star_max_size)

	# Maps time continuously from dusk (0.0) through midnight (PI) to dawn (TAU) without midnight snaps
	var night_progress: float = 0.0
	if time_of_day >= 0.75:
		night_progress = (time_of_day - 0.75) / 0.5
	elif time_of_day < 0.25:
		night_progress = (time_of_day + 0.25) / 0.5
	active_sky_material.set_shader_parameter("elapsed_time", night_progress * TAU)

	var sun_f := clampf(sin(time_of_day * PI), 0.0, 1.0)
	var heatwave_active := (active_weather == WEATHER_TYPE.HEAT_WAVE)

	RenderingServer.global_shader_parameter_set("heatwave_intensity", Sun.light_energy * 0.2 if heatwave_active else 0.0)
	RenderingServer.global_shader_parameter_set("heatwave_frequency", 35.0 + (sun_f * 35.0))
	RenderingServer.global_shader_parameter_set("heatwave_speed", 10.0 + (sun_f * 2.0))

	if Sun:
		Sun.light_energy = lerpf(0.01, 0.8 * climate_blend, sun_f)
	
	active_sky_material.set_shader_parameter("moon_phase", cached_moon_phase)
	active_sky_material.set_shader_parameter("moon_direction", cached_moon_direction)
	active_sky_material.set_shader_parameter("moon_angular_size", cached_moon_angular_size)
	active_sky_material.set_shader_parameter("sun_intensity", sun_f)

func DetermineNextWeather(season: int, hour: float, current: int) -> int:
	var pool: Array = WEATHER["seasonal patterns"].get(season, [WEATHER_TYPE.CLEAR])
	var eligible: Array = []
	var total := 0
	
	for w in pool:
		var weather_array: Array = WEATHER["types"][w]
		if weather_array[5] >= 0.0 and (hour < weather_array[5] or hour > weather_array[6]):
			continue
		var weight := int(weather_chance_override.get(w, weather_array[4]))
		total += weight
		eligible.append([w, weight])
		
	if total <= 0:
		return WEATHER_TYPE.CLEAR
		
	var roll := ((day_of_year * 37 + int(hour) * 17 + year * 13) % total)
	for entry in eligible:
		roll -= entry[1]
		if roll < 0:
			return entry[0]
			
	return WEATHER_TYPE.CLEAR

func UpdateDynamicOrbits() -> void:
	var d_frac = day_of_year + time_of_day
	var t_frac = total_days_passed + time_of_day

	var o_ang = orbit_speed * (d_frac - 192.0)
	var e_tilt = 0.4092797 * sin(o_ang)
	earth_tilt_tan = tan(e_tilt)

	var sun_bias := _tilt_to_altitude_bias(e_tilt)
	seasonal_sun_altitude = sun_bias.x
	horizon_shift_bias = sun_bias.y

	var eq = orbit_speed * (d_frac + 173.0)
	equation_of_time = (9.87 * sin(2.0 * eq) - 7.53 * cos(eq) - 1.5 * sin(eq)) * 0.000694444444
	climate_blend = 0.5 + 0.5 * cos(orbit_speed * (d_frac - 105.0))

	# --- Single moon solve for this frame: tilt, phase, altitude, azimuth, direction, size ---
	var moon_tilt = -e_tilt + 0.0897 * sin(t_frac * 0.22997)
	var moon_bias := _tilt_to_altitude_bias(moon_tilt)
	var seasonal_moon_altitude = moon_bias.x
	var moon_horizon_bias = moon_bias.y
	var moon_tilt_tan = tan(moon_tilt)

	cached_moon_phase = _moon_phase()
	var m_ang = (time_of_day - cached_moon_phase - 1.0) * TAU
	var m_cos = cos(m_ang)

	cached_moon_altitude = _altitude(seasonal_moon_altitude, moon_horizon_bias, m_cos)
	cached_moon_azimuth = _azimuth(m_ang, m_cos, moon_tilt_tan)
	cached_moon_direction = Vector3(
		cos(cached_moon_altitude) * sin(cached_moon_azimuth),
		sin(cached_moon_altitude),
		cos(cached_moon_altitude) * cos(cached_moon_azimuth)
	).normalized()

	var anomalistic_angle = TAU * fmod(t_frac, 27.55) / 27.55
	var anomalistic_swing = lerp(0.93, 1.07, 0.5 + 0.5 * cos(anomalistic_angle))
	cached_moon_angular_size = moon_base_angular_size * anomalistic_swing

func CelestialPaths() -> void:
	if Sun:
		var sun_angle = _sun_angle()
		var sun_cos = cos(sun_angle)
		Sun.rotation.x = _altitude(seasonal_sun_altitude, horizon_shift_bias, sun_cos)
		Sun.rotation.y = _azimuth(sun_angle, sun_cos, earth_tilt_tan)
	if MoonTransform:
		MoonTransform.rotation.x = cached_moon_altitude
		MoonTransform.rotation.y = cached_moon_azimuth

func UpdateUI() -> void:
	if debug_label:
		debug_label.text = "Year %d | %s %d | [%s] | %s => %s | %d:%02d %s" % [year, MONTH_NAMES[month - 1], day, SEASONS[active_season], WEATHER["types"][active_weather][0], WEATHER["types"][next_weather][0], 12 if hour % 12 == 0 else hour % 12, minute, "PM" if hour >= 12 else "AM"]

func _night_strength(hour: float) -> float:
	if hour >= 5.5 and hour < 6.5:
		return smoothstep(6.5, 5.5, hour)
	if hour >= 18.0 and hour < 19.0:
		return smoothstep(18.0, 19.0, hour)
	return 1.0 if (hour < 5.5 or hour >= 19.0) else 0.0

func _SeasonAirglow(season: int) -> float:
	return 0.35 if season == 1 else 0.12

func _sun_angle() -> float:
	return (time_of_day + equation_of_time - 0.5) * TAU

func _moon_phase() -> float:
	return fmod(total_days_passed + time_of_day, SYNODIC_MONTH_DAYS) / SYNODIC_MONTH_DAYS

func _azimuth(angle: float, c: float, tilt_tan: float) -> float:
	return atan2(sin(angle), c * geographic_latitude_sin - tilt_tan * geographic_latitude_cos) + true_north_conversion

func _altitude(seasonal_alt: float, horizon_bias: float, cos_angle: float) -> float:
	return -asin(seasonal_alt + horizon_bias * cos_angle)

func _tilt_to_altitude_bias(tilt: float) -> Vector2:
	return Vector2(geographic_latitude_sin * sin(tilt), geographic_latitude_cos * cos(tilt))

func _lerp_dark(a: Color, b: Color, t: float, strength: float) -> Color:
	return lerp(a, b, t).darkened(strength)
