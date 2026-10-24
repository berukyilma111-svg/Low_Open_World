class_name SkyFeed
extends Node
## Shared by DayScript and NightScript: the geography for a body crossing the sky, where the sun
## is on any given hour, and the one way to hand the sky shader a "from -> to" state. Whichever
## script owns the current hour (sun up = Day, sun down = Night) feeds the shader; at a handover
## the new owner starts from whatever is on screen, so nothing snaps.

@export var time: TimeScript
@export var weather: WeatherScript
@export var world_env: WorldEnvironment

@export_group("Geography")
@export var latitude: float = 10.7058
@export_range(0, 360) var north_offset_degrees: float = 0.0

## How many distinct blend values the shader gets per sky step. Each change re-renders the sky.
@export_range(4, 256) var blend_steps: int = 24

# The sky colour is re-aimed every half hour so it follows the sun's height through sunrise and sunset.
const SKY_STEP_HOURS := 0.5
# The sun's centre is this far below the horizon when its top edge disappears.
const HORIZON_ALTITUDE := -0.833

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
# Sun geometry for the current day
var _sun_tilt: float
var _sun_bias: Vector2
var _sun_tilt_tan: float
var _equation_of_time: float

func _ready() -> void:
	var lat := deg_to_rad(latitude)
	_lat_sin = sin(lat)
	_lat_cos = cos(lat)
	_north = deg_to_rad(north_offset_degrees)
	sky = world_env.environment.sky.sky_material as ShaderMaterial
	time.day_changed.connect(_on_day_changed)
	time.minute_ticked.connect(_on_minute)
	weather.weather_changed.connect(_on_weather_changed)

# Earth's tilt and the equation of time only move once a day.
func _on_day_changed() -> void:
	var orbit := TAU / time.year_length()
	var d := float(time.day_of_year)
	_sun_tilt = 0.4092797 * sin(orbit * (d - 192.0))
	_sun_bias = _tilt_bias(_sun_tilt)
	_sun_tilt_tan = tan(_sun_tilt)
	var eq := orbit * (d + 173.0)
	_equation_of_time = (9.87 * sin(2.0 * eq) - 7.53 * cos(eq) - 1.5 * sin(eq)) * 0.000694444444

func _sun_angle(hour: float) -> float:
	return (hour / 24.0 + _equation_of_time - 0.5) * TAU

## Degrees the sun is above (+) or below (-) the horizon at `hour` today.
func sun_altitude(hour: float) -> float:
	return rad_to_deg(asin(_sun_bias.x + _sun_bias.y * cos(_sun_angle(hour))))

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
	var hour := time.hours()
	var mine := _owns(hour)
	if mine != active:
		active = mine
		if active:
			_retarget()
	elif active and (hour >= _end_hour or hour < _start_hour):
		_retarget()
	if active:
		_push_blend()

func _on_weather_changed() -> void:
	if active:
		_retarget()

func _retarget() -> void:
	_start_hour = time.hours()
	_end_hour = (floorf(_start_hour / SKY_STEP_HOURS) + 1.0) * SKY_STEP_HOURS
	# The last step of a stop blends into the next stop's weather
	var w := weather.upcoming if _end_hour >= (time.stop + 1) * TimeScript.STOP_HOURS else weather.current
	if _shown_valid:
		_from = [shown_top, shown_horizon]
	else:
		_from = _target(_start_hour, weather.current)
	_to = _target(fposmod(_end_hour, 24.0), w)
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

# Colour at `x` along a curve: `first` sits at keys[0], `rest` at the following keys (ascending).
static func _curve(keys: Array[float], first: Color, rest: Array[Color], x: float) -> Color:
	if x <= keys[1]:
		return first.lerp(rest[0], clampf(inverse_lerp(keys[0], keys[1], x), 0.0, 1.0))
	for i in range(1, keys.size() - 1):
		if x <= keys[i + 1]:
			return rest[i - 1].lerp(rest[i], inverse_lerp(keys[i], keys[i + 1], x))
	return rest[-1]
