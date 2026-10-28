class_name NightSky
extends SkyLayer
## Owns the sky from sunset (18:00) to sunrise (6:30): the moon's path, phase and size over the
## month and year, airglow, and the night sky colours with the weather overlay applied.
## The moon keeps moving by day too (it can be up in daylight); only airglow needs the night.

const SYNODIC_MONTH_DAYS := 29.53059
const ANOMALISTIC_MONTH_DAYS := 27.55

# Night sky at 18:00, 21:00, 0:00, 3:00, 6:00, and how dark each point is (0 = untouched, 1 = full night)
const TOP: Array[Color] = [Color(0.93, 0.52, 0.441), Color(0.06, 0.052, 0.223), Color(0.065, 0.058, 0.227), Color(0.0, 0.14, 0.25), Color(0.86, 0.638, 0.43)]
const HORIZON: Array[Color] = [Color(0.988, 0.755, 0.554), Color(0.193, 0.183, 0.526), Color(0.006, 0.045, 0.214), Color(0.23, 0.23, 0.37), Color(0.861, 0.522, 0.212)]
const DARKNESS: Array[float] = [0.0, 1.0, 1.0, 1.0, 0.5]

@export var moon: Node3D
@export var moon_base_angular_size: float = 0.009

var _moon_glow: float
var _moon_shown := true

func setup(s: SkySystem, w: SkyWriter) -> void:
	super(s, w)
	var corona = w.get_default(&"moon_corona_size")
	# Largest the moon and its glow can get, so "fully below the horizon" is never cut short.
	_moon_glow = moon_base_angular_size * 1.07 * (corona if corona != null else 1.6)

func owns(hour: float) -> bool:
	return hour >= DaySky.SUNSET or hour < DaySky.SUNRISE

func track(t: TimeScript) -> void:
	var tod := t.time_of_day()
	var days := t.total_days + tod
	var tilt := -system.tilt + 0.0897 * sin(days * 0.22997)
	var phase := fmod(days, SYNODIC_MONTH_DAYS) / SYNODIC_MONTH_DAYS
	var angle := (tod - phase - 1.0) * TAU
	var c := cos(angle)
	var altitude := system.altitude(system.tilt_bias_for(tilt), c)
	var azimuth := system.azimuth(angle, c, tan(tilt))
	if moon:
		moon.rotation = Vector3(altitude, azimuth, 0.0)
	var dir := Vector3(cos(altitude) * sin(azimuth), sin(altitude), cos(altitude) * cos(azimuth))
	# The shader only draws above the horizon: once the moon and its glow are fully below it, stop
	# feeding it (after one last write that puts it out of sight).
	var visible := dir.y > -_moon_glow
	if not visible and not _moon_shown:
		return
	_moon_shown = visible
	var swing := lerpf(0.93, 1.07, 0.5 + 0.5 * cos(TAU * fmod(days, ANOMALISTIC_MONTH_DAYS) / ANOMALISTIC_MONTH_DAYS))
	writer.put(&"moon_direction", dir, moon_base_angular_size * 0.02)
	writer.put(&"moon_phase", phase, 0.0005)
	writer.put(&"moon_angular_size", moon_base_angular_size * swing, moon_base_angular_size * 0.002)

func target(hour: float, w: int) -> Array:
	var since_dusk := fposmod(hour - DaySky.SUNSET, 24.0)
	var dark := darkness(since_dusk)
	var o: Array = WeatherTable.data(w)
	var weight: float = o[WeatherTable.WEIGHT] * (1.0 - dark * 0.85)
	var top := SkySystem.sample(TOP, since_dusk).darkened(dark * 0.72).lerp(o[WeatherTable.TOP].darkened(dark * 0.8), weight)
	var horizon := SkySystem.sample(HORIZON, since_dusk).darkened(dark * 0.68).lerp(o[WeatherTable.HORIZON].darkened(dark * 0.78), weight)
	return [top, horizon]

func active(t: TimeScript) -> void:
	_update_airglow(t)

func released() -> void:
	writer.put(&"airglow_intensity", 0.0)

func _update_airglow(t: TimeScript) -> void:
	var since_dusk := fposmod(t.hours() - DaySky.SUNSET, 24.0)
	var solar_cycle := 0.75 + 0.25 * sin(t.year * 0.57)
	var season_glow := 0.35 if t.season == 1 else 0.12
	var clear_sky: float = 1.0 - WeatherTable.data(system.current)[WeatherTable.WEIGHT]
	var intensity := season_glow * darkness(since_dusk) * clear_sky * solar_cycle
	writer.put(&"airglow_intensity", intensity, 0.001)
	# The shader skips airglow at zero intensity, so its animation clock only matters while it shows.
	if writer.sent(&"airglow_intensity", 0.0) > 0.0:
		# Runs 0 at dusk through PI at midnight to TAU at dawn, so the airglow never snaps at midnight.
		writer.put(&"elapsed_time", since_dusk / 12.0 * TAU, 0.005)

static func darkness(since_dusk: float) -> float:
	var i := clampi(int(since_dusk / TimeScript.STOP_HOURS), 0, DARKNESS.size() - 2)
	return lerpf(DARKNESS[i], DARKNESS[i + 1], clampf(since_dusk / TimeScript.STOP_HOURS - i, 0.0, 1.0))
