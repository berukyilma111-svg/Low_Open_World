class_name SkySystem
extends Node
## Everything downstream of TimeScript, run as one ordered pipeline each time the clock moves:
##   1. calendar  (per day)    Earth's tilt, equation of time, seasonal sunlight
##   2. weather   (per stop)   current / upcoming weather, rolled fresh from the date
##   3. celestial (per minute) sun light, sun and moon in the sky
##   4. palette   (per minute) day or night sky colours with the weather overlay, blended over the stop
##   5. airglow   (per minute) night-time glow, only while it can be seen
## TimeScript calls `step`; nothing here keeps its own clock or listens for events. Every shader
## and light write goes through a change check, so values that haven't moved cost nothing.

## Emitted when the current weather changes, for gameplay code (rain particles, sound, ...).
signal weather_changed(current: int, upcoming: int)

const SUNRISE := 6.5
const SUNSET := 18.0
const SYNODIC_MONTH_DAYS := 29.53059
const ANOMALISTIC_MONTH_DAYS := 27.55

# Daytime sky at 6:00, 9:00, 12:00, 15:00, 18:00
const DAY_TOP: Array[Color] = [Color(0.86, 0.638, 0.43), Color(0.022, 0.368, 0.609), Color(0.335, 0.68, 0.99), Color(0.18, 0.52, 0.8), Color(0.93, 0.52, 0.441)]
const DAY_HORIZON: Array[Color] = [Color(0.861, 0.522, 0.212), Color(0.75, 0.84, 0.97), Color(0.874, 0.936, 0.999), Color(0.81, 0.88, 0.96), Color(0.988, 0.755, 0.554)]
# Night sky at 18:00, 21:00, 0:00, 3:00, 6:00, and how dark each point is (0 = untouched, 1 = full night)
const NIGHT_TOP: Array[Color] = [Color(0.93, 0.52, 0.441), Color(0.06, 0.052, 0.223), Color(0.065, 0.058, 0.227), Color(0.0, 0.14, 0.25), Color(0.86, 0.638, 0.43)]
const NIGHT_HORIZON: Array[Color] = [Color(0.988, 0.755, 0.554), Color(0.193, 0.183, 0.526), Color(0.006, 0.045, 0.214), Color(0.23, 0.23, 0.37), Color(0.861, 0.522, 0.212)]
const DARKNESS: Array[float] = [0.0, 1.0, 1.0, 1.0, 0.5]

@export var sun: DirectionalLight3D
@export var moon: Node3D
@export var world_env: WorldEnvironment
@export var weather_label: Label

@export_group("Geography")
@export var latitude: float = 10.7058
@export_range(0, 360) var north_offset_degrees: float = 0.0

@export_group("Sky")
## How many distinct blend values the shader gets per 3-hour stop. Each change re-renders the sky.
@export_range(16, 1024) var blend_steps: int = 128
## How much cloudy, rainy, foggy or dusty weather cuts sunlight.
@export_range(0.0, 1.0) var weather_dimming: float = 0.5
@export var moon_base_angular_size: float = 0.009

@export_group("Weather")
@export var chance_override := {}
@export var heatwave_strength: float = 0.16

var current: int = WeatherTable.Type.CLEAR
var upcoming: int = WeatherTable.Type.CLEAR
var is_day := false
var is_night: bool:
	get: return not is_day
## Shader and light writes actually sent since start, for profiling.
var writes := 0

var sky: ShaderMaterial
var _lat_sin: float
var _lat_cos: float
var _north: float
var _moon_glow: float
var _started := false

# Calendar (per day)
var _tilt: float
var _tilt_bias_v: Vector2
var _tilt_tan: float
var _equation_of_time: float
var _climate: float

# Palette (per stop): what is on screen, and the stop's from -> to colours
var _from: Array = [Color.BLACK, Color.BLACK]
var _to: Array = [Color.BLACK, Color.BLACK]
var _shown: Array = [Color.BLACK, Color.BLACK]
var _start_hour: float
var _end_hour: float
var _last_step := -1

# Last values sent, so unchanged ones are skipped
var _sent := {}
var _moon_shown := true
var _heatwave := -1.0

func _ready() -> void:
	var lat := deg_to_rad(latitude)
	_lat_sin = sin(lat)
	_lat_cos = cos(lat)
	_north = deg_to_rad(north_offset_degrees)
	sky = world_env.environment.sky.sky_material as ShaderMaterial
	var corona = sky.get_shader_parameter("moon_corona_size")
	_moon_glow = moon_base_angular_size * 1.07 * (corona if corona != null else 1.6)

func step(t: TimeScript, tiers: int) -> void:
	if tiers & TimeScript.Tier.DAY:
		_calendar(t)
	var retarget := not _started
	if tiers & TimeScript.Tier.STOP:
		retarget = _weather(t) or retarget
	var h := t.hours()
	var day_now := h >= SUNRISE and h < SUNSET
	if day_now != is_day:
		is_day = day_now
		retarget = true
	_celestial(t)
	_palette(t, retarget)
	_airglow(t)
	_started = true

# --- 1. Calendar: Earth's tilt, equation of time and seasonal sunlight only move once a day ---
func _calendar(t: TimeScript) -> void:
	var orbit := TAU / t.year_length()
	var d := float(t.day_of_year)
	_tilt = 0.4092797 * sin(orbit * (d - 192.0))
	_tilt_bias_v = _tilt_bias(_tilt)
	_tilt_tan = tan(_tilt)
	var eq := orbit * (d + 173.0)
	_equation_of_time = (9.87 * sin(2.0 * eq) - 7.53 * cos(eq) - 1.5 * sin(eq)) * 0.000694444444
	_climate = 0.5 + 0.5 * cos(orbit * (d - 105.0))

# --- 2. Weather: rolled from the date, so the stop after midnight sees tomorrow's season ---
func _weather(t: TimeScript) -> bool:
	var start := t.stop * TimeScript.STOP_HOURS
	var next := t.next_stop_date()
	var new_current := WeatherTable.roll(t.season, t.day_of_year, t.year, start, chance_override)
	var new_upcoming := WeatherTable.roll(next[0], next[1], next[2], fmod(start + TimeScript.STOP_HOURS, 24.0), chance_override)
	var changed := new_current != current or new_upcoming != upcoming or not _started
	current = new_current
	upcoming = new_upcoming
	var heat := heatwave_strength if WeatherTable.has_flag(current, WeatherTable.Flag.HEAT) else 0.0
	if heat != _heatwave:
		_heatwave = heat
		RenderingServer.global_shader_parameter_set("heatwave_intensity", heat)
		writes += 1
	if weather_label:
		weather_label.text = "%s => %s" % [WeatherTable.TYPES[current][WeatherTable.NAME], WeatherTable.TYPES[upcoming][WeatherTable.NAME]]
	if changed:
		weather_changed.emit(current, upcoming)
	# A new stop always needs a new blend target, even when the weather stayed the same.
	return true

# --- 3. Celestial: sun light and the sun / moon in the sky ---
func _celestial(t: TimeScript) -> void:
	var tod := t.time_of_day()
	var sun_f := clampf(sin(tod * PI), 0.0, 1.0)
	if sun:
		var angle := (tod + _equation_of_time - 0.5) * TAU
		var c := cos(angle)
		var altitude := _altitude(_tilt_bias_v, c)
		# Below the horizon the light only costs a shadow pass, so switch it off and stop moving it.
		var up := altitude < 0.1
		if up or sun.visible:
			sun.rotation = Vector3(altitude, _azimuth(angle, c, _tilt_tan), sun.rotation.z)
			sun.visible = up
			var dim := 1.0 - weather_dimming if WeatherTable.has_flag(current, WeatherTable.DIMMING_FLAGS) else 1.0
			var energy := lerpf(0.01, 0.8 * _climate * dim, sun_f)
			if absf(energy - sun.light_energy) > 0.002:
				sun.light_energy = energy
				writes += 1
	_put(&"sun_intensity", int(sun_f * 64.0) / 64.0)

	var tt := t.total_days + tod
	var tilt := -_tilt + 0.0897 * sin(tt * 0.22997)
	var phase := fmod(tt, SYNODIC_MONTH_DAYS) / SYNODIC_MONTH_DAYS
	var m_angle := (tod - phase - 1.0) * TAU
	var mc := cos(m_angle)
	var m_alt := _altitude(_tilt_bias(tilt), mc)
	var m_az := _azimuth(m_angle, mc, tan(tilt))
	if moon:
		moon.rotation = Vector3(m_alt, m_az, 0.0)
	var dir := Vector3(cos(m_alt) * sin(m_az), sin(m_alt), cos(m_alt) * cos(m_az))
	# The shader only draws above the horizon: once the moon and its glow are fully below it, stop
	# feeding it (after one last write that puts it out of sight).
	var visible := dir.y > -_moon_glow
	if visible or _moon_shown:
		_moon_shown = visible
		var swing := lerpf(0.93, 1.07, 0.5 + 0.5 * cos(TAU * fmod(tt, ANOMALISTIC_MONTH_DAYS) / ANOMALISTIC_MONTH_DAYS))
		_put(&"moon_direction", dir, moon_base_angular_size * 0.02)
		_put(&"moon_phase", phase, 0.0005)
		_put(&"moon_angular_size", moon_base_angular_size * swing, moon_base_angular_size * 0.002)

# --- 4. Palette: one from -> to blend per stop, picked up from whatever is on screen ---
func _palette(t: TimeScript, retarget: bool) -> void:
	var h := t.hours()
	if retarget:
		_start_hour = h
		_end_hour = (t.stop + 1) * TimeScript.STOP_HOURS
		_from = _shown if _started else _target(_start_hour, current)
		_to = _target(_end_hour, upcoming)
		_put(&"from_top", _from[0])
		_put(&"from_horizon", _from[1])
		_put(&"to_top", _to[0])
		_put(&"to_horizon", _to[1])
		_last_step = -1
	var b_t := clampf((h - _start_hour) / maxf(_end_hour - _start_hour, 0.001), 0.0, 1.0)
	var step_i := int(b_t * blend_steps)
	if step_i == _last_step:
		return
	_last_step = step_i
	var b := float(step_i) / blend_steps
	_shown = [_from[0].lerp(_to[0], b), _from[1].lerp(_to[1], b)]
	_put(&"sky_blend", b)

func _target(hour: float, w: int) -> Array:
	var o: Array = WeatherTable.data(w)
	if is_day:
		var top := _sample(DAY_TOP, hour - 6.0).lerp(o[WeatherTable.TOP], o[WeatherTable.WEIGHT])
		var horizon := _sample(DAY_HORIZON, hour - 6.0).lerp(o[WeatherTable.HORIZON], o[WeatherTable.WEIGHT])
		return [top, horizon]
	var since_dusk := fposmod(hour - SUNSET, 24.0)
	var dark := _darkness(since_dusk)
	var weight: float = o[WeatherTable.WEIGHT] * (1.0 - dark * 0.85)
	var n_top := _sample(NIGHT_TOP, since_dusk).darkened(dark * 0.72).lerp(o[WeatherTable.TOP].darkened(dark * 0.8), weight)
	var n_horizon := _sample(NIGHT_HORIZON, since_dusk).darkened(dark * 0.68).lerp(o[WeatherTable.HORIZON].darkened(dark * 0.78), weight)
	return [n_top, n_horizon]

# --- 5. Airglow: only at night, and only fed to the shader while it is actually visible ---
func _airglow(t: TimeScript) -> void:
	var intensity := 0.0
	var since_dusk := fposmod(t.hours() - SUNSET, 24.0)
	if is_night:
		var solar_cycle := 0.75 + 0.25 * sin(t.year * 0.57)
		var season_glow := 0.35 if t.season == 1 else 0.12
		var clear_sky: float = 1.0 - WeatherTable.data(current)[WeatherTable.WEIGHT]
		intensity = season_glow * _darkness(since_dusk) * clear_sky * solar_cycle
	_put(&"airglow_intensity", intensity, 0.001)
	# The shader skips airglow at zero intensity, so its animation clock only matters while it shows.
	if _sent[&"airglow_intensity"] > 0.0:
		# Runs 0 at dusk through PI at midnight to TAU at dawn, so the airglow never snaps at midnight.
		_put(&"elapsed_time", since_dusk / 12.0 * TAU, 0.005)

# --- Writer: the only place that talks to the sky shader ---
func _put(param: StringName, value, eps: float = 0.0) -> void:
	if _sent.has(param):
		var last = _sent[param]
		if eps > 0.0:
			if value is float:
				if absf(value - last) <= eps:
					return
			elif value is Vector3:
				if value.distance_to(last) <= eps:
					return
		elif value == last:
			return
	_sent[param] = value
	sky.set_shader_parameter(param, value)
	writes += 1

# --- Geography helpers ---
func _tilt_bias(tilt: float) -> Vector2:
	return Vector2(_lat_sin * sin(tilt), _lat_cos * cos(tilt))

func _altitude(bias: Vector2, cos_angle: float) -> float:
	return -asin(bias.x + bias.y * cos_angle)

func _azimuth(angle: float, cos_angle: float, tilt_tan: float) -> float:
	return atan2(sin(angle), cos_angle * _lat_sin - tilt_tan * _lat_cos) + _north

# Picks the palette segment that is `hours_from_first` after the palette's first entry.
static func _sample(colors: Array[Color], hours_from_first: float) -> Color:
	var i := clampi(int(hours_from_first / TimeScript.STOP_HOURS), 0, colors.size() - 2)
	var t := clampf(hours_from_first / TimeScript.STOP_HOURS - i, 0.0, 1.0)
	return colors[i].lerp(colors[i + 1], t)

static func _darkness(since_dusk: float) -> float:
	var i := clampi(int(since_dusk / TimeScript.STOP_HOURS), 0, DARKNESS.size() - 2)
	return lerpf(DARKNESS[i], DARKNESS[i + 1], clampf(since_dusk / TimeScript.STOP_HOURS - i, 0.0, 1.0))
