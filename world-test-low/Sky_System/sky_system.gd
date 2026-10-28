class_name SkySystem
extends Node
## The conductor between TimeScript and DaySky / NightSky. TimeScript calls it only when needed:
##   on_day    (each new day)     Earth's tilt and equation of time, shared by day and night
##   on_stop   (every 3 hours)    current / upcoming weather
##   on_minute (each game minute) DaySky moves the sun, NightSky the moon and airglow, and the
##                                owning side's colours are blended across the stop
## Nothing here, in DaySky or in NightSky keeps its own clock or listens for events.

## Emitted when the weather changes, for gameplay code (rain particles, sound, ...).
signal weather_changed(current: int, upcoming: int)

@export var day: DaySky
@export var night: NightSky
@export var world_env: WorldEnvironment
@export var weather_label: Label

@export_group("Geography")
@export var latitude: float = 10.7058
@export_range(0, 360) var north_offset_degrees: float = 0.0

@export_group("Sky")
## How many distinct blend values the shader gets per 3-hour stop. Each change re-renders the sky.
@export_range(16, 1024) var blend_steps: int = 128

@export_group("Weather")
@export var chance_override := {}

var current: int = WeatherTable.Type.CLEAR
var upcoming: int = WeatherTable.Type.CLEAR
## True while DaySky owns the sky colours, false while NightSky does.
var is_day := false
var is_night: bool:
	get: return not is_day
## Shader, light and global writes actually sent since start, for profiling.
var writes := 0
var sky: ShaderMaterial

# Calendar, shared by DaySky and NightSky (updated once per day)
var tilt: float
var tilt_bias: Vector2
var tilt_tan: float
var equation_of_time: float

var _lat_sin: float
var _lat_cos: float
var _north: float
var _started := false
var _retarget := true

# Last values sent to the shader, so unchanged ones are skipped
var _sent := {}

# Palette blend for the current stop
var _from: Array = [Color.BLACK, Color.BLACK]
var _to: Array = [Color.BLACK, Color.BLACK]
var _shown: Array = [Color.BLACK, Color.BLACK]
var _start_hour: float
var _end_hour: float
var _last_step := -1

func _ready() -> void:
	var lat := deg_to_rad(latitude)
	_lat_sin = sin(lat)
	_lat_cos = cos(lat)
	_north = deg_to_rad(north_offset_degrees)
	sky = world_env.environment.sky.sky_material as ShaderMaterial
	day.setup(self)
	night.setup(self)

# --- Each new day: Earth's tilt and the equation of time only move once a day ---
func on_day(t: TimeScript) -> void:
	var orbit := TAU / t.year_length()
	var d := float(t.day_of_year())
	tilt = 0.4092797 * sin(orbit * (d - 192.0))
	tilt_bias = tilt_bias_for(tilt)
	tilt_tan = tan(tilt)
	var eq := orbit * (d + 173.0)
	equation_of_time = (9.87 * sin(2.0 * eq) - 7.53 * cos(eq) - 1.5 * sin(eq)) * 0.000694444444
	day.on_day(t)

# --- Every 3 hours: weather is rolled fresh from the date, so midnight always sees the new season ---
func on_stop(t: TimeScript) -> void:
	var start := t.hour - t.hour % TimeScript.STOP_HOURS
	var next_hour := (start + TimeScript.STOP_HOURS) % 24
	# The stop after 21:00 is tomorrow. Only the forecast's blend target uses this; the stop itself
	# is always rolled from its real date when it arrives.
	var next_day := t.day_of_year() + (1 if next_hour == 0 else 0)
	var new_current := WeatherTable.roll(t.season(), t.day_of_year(), t.year, start, chance_override)
	var new_upcoming := WeatherTable.roll(t.season(), next_day, t.year, next_hour, chance_override)
	var changed := new_current != current or new_upcoming != upcoming or not _started
	current = new_current
	upcoming = new_upcoming
	if weather_label:
		weather_label.text = "%s => %s" % [WeatherTable.TYPES[current][WeatherTable.NAME], WeatherTable.TYPES[upcoming][WeatherTable.NAME]]
	if changed:
		weather_changed.emit(current, upcoming)
	day.on_stop(t)
	_retarget = true

# --- Every game minute: move the sun and moon, hand the sky between day and night, blend colours ---
func on_minute(t: TimeScript) -> void:
	var day_now := day.owns(t.time_of_day() * 24.0)
	if day_now != is_day or not _started:
		if day_now and _started:
			night.released()
		is_day = day_now
		_retarget = true
	day.track(t)
	night.track(t)
	if is_night:
		night.active(t)
	_palette(t, _retarget)
	_retarget = false
	_started = true

# One from -> to colour blend per stop, picked up from whatever is on screen.
func _palette(t: TimeScript, retarget: bool) -> void:
	var h := t.time_of_day() * 24.0
	if retarget:
		_start_hour = h
		_end_hour = t.hour - t.hour % TimeScript.STOP_HOURS + TimeScript.STOP_HOURS
		_from = _shown if _started else _target(_start_hour, current)
		_to = _target(_end_hour, upcoming)
		put(&"from_top", _from[0])
		put(&"from_horizon", _from[1])
		put(&"to_top", _to[0])
		put(&"to_horizon", _to[1])
		_last_step = -1
	var progress := clampf((h - _start_hour) / maxf(_end_hour - _start_hour, 0.001), 0.0, 1.0)
	var step_i := int(progress * blend_steps)
	if step_i == _last_step:
		return
	_last_step = step_i
	var b := float(step_i) / blend_steps
	_shown = [_from[0].lerp(_to[0], b), _from[1].lerp(_to[1], b)]
	put(&"sky_blend", b)

func _target(hour: float, w: int) -> Array:
	return day.target(hour, w) if is_day else night.target(hour, w)

# --- Writer: the only place that talks to the sky shader. Values that haven't moved by more than
# their tolerance are skipped, so unchanged values cost nothing. ---
func put(param: StringName, value, eps: float = 0.0) -> void:
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

func put_global(param: StringName, value) -> void:
	var key := StringName("global/" + param)
	if _sent.get(key) == value:
		return
	_sent[key] = value
	RenderingServer.global_shader_parameter_set(param, value)
	writes += 1

## The value last sent for `param`, or `fallback` if it was never sent.
func sent(param: StringName, fallback = null):
	return _sent.get(param, fallback)

# --- Geography, for any body crossing the sky ---
func tilt_bias_for(body_tilt: float) -> Vector2:
	return Vector2(_lat_sin * sin(body_tilt), _lat_cos * cos(body_tilt))

func altitude(bias: Vector2, cos_angle: float) -> float:
	return -asin(bias.x + bias.y * cos_angle)

func azimuth(angle: float, cos_angle: float, body_tilt_tan: float) -> float:
	return atan2(sin(angle), cos_angle * _lat_sin - body_tilt_tan * _lat_cos) + _north

## Picks the palette segment that is `hours_from_first` after the palette's first entry.
static func sample(colors: Array[Color], hours_from_first: float) -> Color:
	var i := clampi(int(hours_from_first / TimeScript.STOP_HOURS), 0, colors.size() - 2)
	var t := clampf(hours_from_first / TimeScript.STOP_HOURS - i, 0.0, 1.0)
	return colors[i].lerp(colors[i + 1], t)
