class_name SkyFeed
extends Node
## Shared by DayScript and NightScript: the geography for a body crossing the sky, and the one
## way to hand the sky shader a "from -> to" state. Whichever script owns the current hour feeds
## the shader; at a handover the new owner starts from whatever is on screen, so nothing snaps.

@export var time: TimeScript
@export var weather: WeatherScript
@export var world_env: WorldEnvironment

@export_group("Geography")
@export var latitude: float = 10.7058
@export_range(0, 360) var north_offset_degrees: float = 0.0

## How many distinct blend values the shader gets per 3-hour stop. Each change re-renders the sky.
@export_range(16, 1024) var blend_steps: int = 128

static var shown_top: Color
static var shown_horizon: Color
static var _shown_valid := false

var sky: ShaderMaterial
var active := false
var _lat_sin: float
var _lat_cos: float
var _north: float
var _from: Array = [Color.BLACK, Color.BLACK]
var _to: Array = [Color.BLACK, Color.BLACK]
var _start_hour: float
var _end_hour: float
var _last_step := -1

func _ready() -> void:
	var lat := deg_to_rad(latitude)
	_lat_sin = sin(lat)
	_lat_cos = cos(lat)
	_north = deg_to_rad(north_offset_degrees)
	sky = world_env.environment.sky.sky_material as ShaderMaterial
	time.minute_ticked.connect(_on_minute)
	weather.weather_changed.connect(_on_weather_changed)

# --- Overridden by DayScript / NightScript ---
func _owns(_hour: float) -> bool:
	return false

func _target(_hour: float, _weather: int) -> Array:
	return [Color.BLACK, Color.BLACK]

func _track() -> void:
	pass

# --- Sky feed ---
func _on_minute() -> void:
	_track()
	var mine := _owns(time.hours())
	if mine != active:
		active = mine
		if active:
			_retarget()
	if active:
		_push_blend()

func _on_weather_changed() -> void:
	if active:
		_retarget()

func _retarget() -> void:
	_start_hour = time.hours()
	_end_hour = (time.stop + 1) * TimeScript.STOP_HOURS
	if _shown_valid:
		_from = [shown_top, shown_horizon]
	else:
		_from = _target(_start_hour, weather.current)
	_to = _target(_end_hour, weather.upcoming)
	sky.set_shader_parameter("from_top", _from[0])
	sky.set_shader_parameter("from_horizon", _from[1])
	sky.set_shader_parameter("to_top", _to[0])
	sky.set_shader_parameter("to_horizon", _to[1])
	_last_step = -1
	_push_blend()

func _push_blend() -> void:
	var t := clampf((time.hours() - _start_hour) / maxf(_end_hour - _start_hour, 0.001), 0.0, 1.0)
	var step := int(t * blend_steps)
	if step == _last_step:
		return
	_last_step = step
	var b := float(step) / blend_steps
	shown_top = _from[0].lerp(_to[0], b)
	shown_horizon = _from[1].lerp(_to[1], b)
	_shown_valid = true
	sky.set_shader_parameter("sky_blend", b)

# --- Geography helpers ---
func _tilt_bias(tilt: float) -> Vector2:
	return Vector2(_lat_sin * sin(tilt), _lat_cos * cos(tilt))

func _altitude(bias: Vector2, cos_angle: float) -> float:
	return -asin(bias.x + bias.y * cos_angle)

func _azimuth(angle: float, cos_angle: float, tilt_tan: float) -> float:
	return atan2(sin(angle), cos_angle * _lat_sin - tilt_tan * _lat_cos) + _north

# Picks the palette segment that `hour` falls in, `hours_from_first` after the palette's first entry.
static func _palette(colors: Array[Color], hours_from_first: float) -> Color:
	var i := clampi(int(hours_from_first / TimeScript.STOP_HOURS), 0, colors.size() - 2)
	var t := clampf(hours_from_first / TimeScript.STOP_HOURS - i, 0.0, 1.0)
	return colors[i].lerp(colors[i + 1], t)
