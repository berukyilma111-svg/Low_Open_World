class_name NightScript
extends SkyFeed
## Owns the sky from sunset (18:00) to sunrise (6:30): the moon's path, phase and size over the
## month and year, airglow, and the night sky colours with the weather overlay applied.

const SYNODIC_MONTH_DAYS := 29.53059
const ANOMALISTIC_MONTH_DAYS := 27.55

# Night sky at 18:00, 21:00, 0:00, 3:00, 6:00, and how dark each point is (0 = untouched, 1 = full night)
const TOP: Array[Color] = [Color(0.93, 0.52, 0.441), Color(0.06, 0.052, 0.223), Color(0.065, 0.058, 0.227), Color(0.0, 0.14, 0.25), Color(0.86, 0.638, 0.43)]
const HORIZON: Array[Color] = [Color(0.988, 0.755, 0.554), Color(0.193, 0.183, 0.526), Color(0.006, 0.045, 0.214), Color(0.23, 0.23, 0.37), Color(0.861, 0.522, 0.212)]
const DARKNESS: Array[float] = [0.0, 1.0, 1.0, 1.0, 0.5]

@export var moon: Node3D
@export var moon_base_angular_size: float = 0.009

@export_group("Stars")
@export_range(0.0, 0.2, 0.001) var star_coverage: float = 0.015
@export_range(0.05, 0.9, 0.01) var star_max_size: float = 0.35

var is_night: bool:
	get: return active

var _earth_tilt: float

func _ready() -> void:
	super()
	time.day_changed.connect(_on_day_changed)
	sky.set_shader_parameter("star_coverage", star_coverage)
	sky.set_shader_parameter("star_max_size", star_max_size)

func _on_day_changed() -> void:
	_earth_tilt = 0.4092797 * sin(TAU / time.year_length() * (time.day_of_year - 192.0))

func _owns(hour: float) -> bool:
	return hour >= DayScript.SUNSET or hour < DayScript.SUNRISE

func _target(hour: float, w: int) -> Array:
	var since_dusk := fposmod(hour - DayScript.SUNSET, 24.0)
	var dark := _darkness(since_dusk)
	var o: Array = weather.data(w)
	var weight: float = o[WeatherScript.WEIGHT] * (1.0 - dark * 0.85)
	var top := _palette(TOP, since_dusk).darkened(dark * 0.72).lerp(o[WeatherScript.TOP].darkened(dark * 0.8), weight)
	var horizon := _palette(HORIZON, since_dusk).darkened(dark * 0.68).lerp(o[WeatherScript.HORIZON].darkened(dark * 0.78), weight)
	return [top, horizon]

func _track() -> void:
	var tod := time.time_of_day()
	var t := time.total_days + tod
	var tilt := -_earth_tilt + 0.0897 * sin(t * 0.22997)
	var phase := fmod(t, SYNODIC_MONTH_DAYS) / SYNODIC_MONTH_DAYS
	var angle := (tod - phase - 1.0) * TAU
	var c := cos(angle)
	var altitude := _altitude(_tilt_bias(tilt), c)
	var azimuth := _azimuth(angle, c, tan(tilt))
	if moon:
		moon.rotation = Vector3(altitude, azimuth, 0.0)
	var swing := lerpf(0.93, 1.07, 0.5 + 0.5 * cos(TAU * fmod(t, ANOMALISTIC_MONTH_DAYS) / ANOMALISTIC_MONTH_DAYS))
	sky.set_shader_parameter("moon_phase", phase)
	sky.set_shader_parameter("moon_angular_size", moon_base_angular_size * swing)
	sky.set_shader_parameter("moon_direction", Vector3(cos(altitude) * sin(azimuth), sin(altitude), cos(altitude) * cos(azimuth)))
	if active:
		_update_airglow()

func _released() -> void:
	sky.set_shader_parameter("airglow_intensity", 0.0)

func _update_airglow() -> void:
	var since_dusk := fposmod(time.hours() - DayScript.SUNSET, 24.0)
	var solar_cycle := 0.75 + 0.25 * sin(time.year * 0.57)
	var season_glow := 0.35 if time.season == 1 else 0.12
	var clear_sky: float = 1.0 - weather.data(weather.current)[WeatherScript.WEIGHT]
	sky.set_shader_parameter("airglow_intensity", season_glow * _darkness(since_dusk) * clear_sky * solar_cycle)
	# Runs 0 at dusk through PI at midnight to TAU at dawn, so the airglow never snaps at midnight.
	sky.set_shader_parameter("elapsed_time", since_dusk / 12.0 * TAU)

static func _darkness(since_dusk: float) -> float:
	var i := clampi(int(since_dusk / TimeScript.STOP_HOURS), 0, DARKNESS.size() - 2)
	return lerpf(DARKNESS[i], DARKNESS[i + 1], clampf(since_dusk / TimeScript.STOP_HOURS - i, 0.0, 1.0))
