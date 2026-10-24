class_name DayScript
extends SkyFeed
## Owns the sky while the sun is up, from sunrise to sunset: the sun's path over the day and year,
## sunlight strength, and the daytime sky colours with the weather overlay applied.

# Sky at the horizon (0 degrees) when the sun rises and when it sets
const DAWN_TOP := Color(0.86, 0.638, 0.43)
const DAWN_HORIZON := Color(0.861, 0.522, 0.212)
const DUSK_TOP := Color(0.93, 0.52, 0.441)
const DUSK_HORIZON := Color(0.988, 0.755, 0.554)
# Then by sun height in degrees: golden hour, morning/afternoon, midday
const ALTITUDES: Array[float] = [0.0, 6.0, 20.0, 60.0]
const TOP: Array[Color] = [Color(0.4, 0.45, 0.6), Color(0.022, 0.368, 0.609), Color(0.335, 0.68, 0.99)]
const HORIZON: Array[Color] = [Color(0.97, 0.78, 0.55), Color(0.75, 0.84, 0.97), Color(0.874, 0.936, 0.999)]

@export var sun: DirectionalLight3D
## How much cloudy, rainy, foggy or dusty weather cuts sunlight.
@export_range(0.0, 1.0) var weather_dimming: float = 0.5
## Hours either side of solar noon that glare builds and fades over.
@export_range(0.5, 6.0, 0.5) var glare_hours: float = 3.0
## How much glare adds to sunlight.
@export_range(0.0, 1.0) var glare_light: float = 0.25

# How dry each season is: glare only shows on clear, dry days
const SEASON_DRYNESS: Array[float] = [0.6, 1.0, 0.3, 0.1]

var is_day: bool:
	get: return active

var _climate: float
var _sun_distance: float
var _last_intensity := -1
var _sent_state := Vector3(-1.0, -1.0, -1.0)

# Seasonal sunlight only moves once a day.
func _on_day_changed() -> void:
	super()
	var orbit := TAU / time.year_length()
	var d := float(time.day_of_year)
	_climate = 0.5 + 0.5 * cos(orbit * (d - 105.0))
	# Earth is closest to the sun in early January (day ~115 of the Ethiopian year): the disc looks ~3% bigger
	_sun_distance = 1.0 + 0.017 * cos(orbit * (d - 115.0))

func _owns(hour: float) -> bool:
	return sun_altitude(hour) >= HORIZON_ALTITUDE

func _target(hour: float, w: int) -> Array:
	var alt := sun_altitude(hour)
	var dawn := hour < 12.0
	var o: Array = weather.data(w)
	var top := _curve(ALTITUDES, DAWN_TOP if dawn else DUSK_TOP, TOP, alt).lerp(o[WeatherScript.TOP], o[WeatherScript.WEIGHT])
	var horizon := _curve(ALTITUDES, DAWN_HORIZON if dawn else DUSK_HORIZON, HORIZON, alt).lerp(o[WeatherScript.HORIZON], o[WeatherScript.WEIGHT])
	return [top, horizon]

func _track() -> void:
	var tod := time.time_of_day()
	var angle := _sun_angle(time.hours())
	var c := cos(angle)
	var sun_f := clampf(sin(tod * PI), 0.0, 1.0)
	var overcast := weather.has_flag(WeatherScript.DIMMING_FLAGS)
	var hour := time.hours()
	# Glare: peaks at solar noon on clear, dry days
	var midday := clampf(1.0 - absf(hour - (12.0 - _equation_of_time * 24.0)) / glare_hours, 0.0, 1.0)
	var glare := 0.0 if overcast else midday * midday * SEASON_DRYNESS[time.season] * sun_f
	# Heat shimmer: the air keeps warming after noon and peaks around 14:00
	var afternoon := clampf(sin((hour - 8.0) / 12.0 * PI), 0.0, 1.0)
	var heat := 1.0 if weather.has_flag(WeatherScript.Flag.HEAT) else 0.5 if time.season == 1 else 0.0
	var haze: float = weather.data(weather.current)[WeatherScript.WEIGHT] if weather.has_flag(WeatherScript.Flag.DUST | WeatherScript.Flag.FOG) else 0.0
	if sun:
		sun.rotation.x = _altitude(_sun_bias, c)
		sun.rotation.y = _azimuth(angle, c, _sun_tilt_tan)
		var dim := 1.0 - weather_dimming if overcast else 1.0
		sun.light_energy = lerpf(0.01, 0.8 * _climate * dim, sun_f) * (1.0 + glare_light * glare)
	# Each send re-renders the sky's lighting, so only send when a value moves by 1/64
	var state := Vector3(glare, _sun_distance * (1.0 + heat * afternoon * afternoon) * (1.0 + haze * 0.5), haze)
	if not state.snapped(Vector3.ONE / 64.0).is_equal_approx(_sent_state):
		_sent_state = state.snapped(Vector3.ONE / 64.0)
		sky.set_shader_parameter("sun_state", _sent_state)
	var intensity := int(sun_f * 64.0)
	if intensity != _last_intensity:
		_last_intensity = intensity
		sky.set_shader_parameter("sun_intensity", intensity / 64.0)
