class_name DayScript
extends SkyFeed
## Owns the sky from sunrise (6:30) to sunset (18:00): the sun's path over the day and year,
## sunlight strength, and the daytime sky colours with the weather overlay applied.

const SUNRISE := 6.5
const SUNSET := 18.0

# Daytime sky at 6:00, 9:00, 12:00, 15:00, 18:00
const TOP: Array[Color] = [Color(0.86, 0.638, 0.43), Color(0.022, 0.368, 0.609), Color(0.335, 0.68, 0.99), Color(0.18, 0.52, 0.8), Color(0.93, 0.52, 0.441)]
const HORIZON: Array[Color] = [Color(0.861, 0.522, 0.212), Color(0.75, 0.84, 0.97), Color(0.874, 0.936, 0.999), Color(0.81, 0.88, 0.96), Color(0.988, 0.755, 0.554)]

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

var _tilt_bias_v: Vector2
var _tilt_tan: float
var _equation_of_time: float
var _climate: float
var _sun_distance: float
var _last_intensity := -1
var _sent_state := Vector3(-1.0, -1.0, -1.0)

func _ready() -> void:
	super()
	time.day_changed.connect(_on_day_changed)

# Earth's tilt, equation of time and seasonal sunlight only move once a day.
func _on_day_changed() -> void:
	var orbit := TAU / time.year_length()
	var d := float(time.day_of_year)
	var tilt := 0.4092797 * sin(orbit * (d - 192.0))
	_tilt_bias_v = _tilt_bias(tilt)
	_tilt_tan = tan(tilt)
	var eq := orbit * (d + 173.0)
	_equation_of_time = (9.87 * sin(2.0 * eq) - 7.53 * cos(eq) - 1.5 * sin(eq)) * 0.000694444444
	_climate = 0.5 + 0.5 * cos(orbit * (d - 105.0))
	# Earth is closest to the sun in early January (day ~115 of the Ethiopian year): the disc looks ~3% bigger
	_sun_distance = 1.0 + 0.017 * cos(orbit * (d - 115.0))

func _owns(hour: float) -> bool:
	return hour >= SUNRISE and hour < SUNSET

func _target(hour: float, w: int) -> Array:
	var o: Array = weather.data(w)
	var top := _palette(TOP, hour - 6.0).lerp(o[WeatherScript.TOP], o[WeatherScript.WEIGHT])
	var horizon := _palette(HORIZON, hour - 6.0).lerp(o[WeatherScript.HORIZON], o[WeatherScript.WEIGHT])
	return [top, horizon]

func _track() -> void:
	var tod := time.time_of_day()
	var angle := (tod + _equation_of_time - 0.5) * TAU
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
		sun.rotation.x = _altitude(_tilt_bias_v, c)
		sun.rotation.y = _azimuth(angle, c, _tilt_tan)
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
