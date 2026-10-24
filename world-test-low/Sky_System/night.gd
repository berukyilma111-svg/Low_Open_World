class_name NightScript
extends SkyFeed
## Owns the sky while the sun is down, from sunset to sunrise: the moon's path, phase and size over
## the month and year, and the night sky colours with the weather overlay and airglow applied.

const SYNODIC_MONTH_DAYS := 29.53059
const ANOMALISTIC_MONTH_DAYS := 27.55

# Night sky by how far the sun is below the horizon, in degrees: the sunset/sunrise colours at 0
# (shared with DayScript), then blue hour, nautical twilight and full night.
const DEPTHS: Array[float] = [0.0, 6.0, 12.0, 18.0]
const TOP: Array[Color] = [Color(0.16, 0.2, 0.42), Color(0.05, 0.07, 0.2), Color(0.015, 0.018, 0.06)]
const HORIZON: Array[Color] = [Color(0.55, 0.38, 0.5), Color(0.12, 0.12, 0.3), Color(0.03, 0.04, 0.1)]
# Airglow sits in the same band as the horizon, so it is mixed into the horizon colour.
const AIRGLOW := Color(0.12, 0.42, 0.32)

@export var moon: Node3D
@export var moon_base_angular_size: float = 0.009
## How far the moon must move across the sky before the shader is told about it.
@export_range(0.05, 5.0, 0.05) var moon_step_degrees: float = 0.5

var is_night: bool:
	get: return active

var _sent_direction := Vector3.ZERO
var _step_cos: float

func _ready() -> void:
	super()
	_step_cos = cos(deg_to_rad(moon_step_degrees))

func _owns(hour: float) -> bool:
	return sun_altitude(hour) < HORIZON_ALTITUDE

func _target(hour: float, w: int) -> Array:
	var depth := -sun_altitude(hour)
	var dawn := hour < 12.0
	var dark := clampf(depth / 18.0, 0.0, 1.0)
	var o: Array = weather.data(w)
	var weight: float = o[WeatherScript.WEIGHT] * (1.0 - dark * 0.85)
	var top := _curve(DEPTHS, DayScript.DAWN_TOP if dawn else DayScript.DUSK_TOP, TOP, depth).lerp(o[WeatherScript.TOP].darkened(dark * 0.8), weight)
	var horizon := _curve(DEPTHS, DayScript.DAWN_HORIZON if dawn else DayScript.DUSK_HORIZON, HORIZON, depth).lerp(o[WeatherScript.HORIZON].darkened(dark * 0.78), weight)
	return [top, horizon + AIRGLOW * dark * (1.0 - o[WeatherScript.WEIGHT]) * 0.15]

func _track() -> void:
	var tod := time.time_of_day()
	var t := time.total_days + tod
	var tilt := -_sun_tilt + 0.0897 * sin(t * 0.22997)
	var phase := fmod(t, SYNODIC_MONTH_DAYS) / SYNODIC_MONTH_DAYS
	var angle := (tod - phase - 1.0) * TAU
	var c := cos(angle)
	var altitude := _altitude(_tilt_bias(tilt), c)
	var azimuth := _azimuth(angle, c, tan(tilt))
	if moon:
		moon.rotation = Vector3(altitude, azimuth, 0.0)
	# Every sky uniform change re-renders the sky's lighting, so only resend the moon when it is
	# visible (above the horizon, not washed out by daylight) and has moved a noticeable amount.
	var direction := Vector3(cos(altitude) * sin(azimuth), sin(altitude), cos(altitude) * cos(azimuth))
	if direction.y < -0.05 or sin(tod * PI) >= 0.8:
		return
	if direction.dot(_sent_direction) > _step_cos:
		return
	_sent_direction = direction
	var swing := lerpf(0.93, 1.07, 0.5 + 0.5 * cos(TAU * fmod(t, ANOMALISTIC_MONTH_DAYS) / ANOMALISTIC_MONTH_DAYS))
	sky.set_shader_parameter("moon_phase", phase)
	sky.set_shader_parameter("moon_angular_size", moon_base_angular_size * swing)
	sky.set_shader_parameter("moon_direction", direction)
