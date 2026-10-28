class_name DaySky
extends Node
## Owns the sky from sunrise (6:30) to sunset (18:00): the sun's path over the day and year,
## sunlight strength, heat waves, and the daytime sky colours with the weather overlay applied.

const SUNRISE := 6.5
const SUNSET := 18.0

# Daytime sky at 6:00, 9:00, 12:00, 15:00, 18:00
const TOP: Array[Color] = [Color(0.86, 0.638, 0.43), Color(0.022, 0.368, 0.609), Color(0.335, 0.68, 0.99), Color(0.18, 0.52, 0.8), Color(0.93, 0.52, 0.441)]
const HORIZON: Array[Color] = [Color(0.861, 0.522, 0.212), Color(0.75, 0.84, 0.97), Color(0.874, 0.936, 0.999), Color(0.81, 0.88, 0.96), Color(0.988, 0.755, 0.554)]

@export var sun: DirectionalLight3D
## How much cloudy, rainy, foggy or dusty weather cuts sunlight.
@export_range(0.0, 1.0) var weather_dimming: float = 0.5
@export var heatwave_strength: float = 0.16

var system: SkySystem
var _climate: float

func setup(s: SkySystem) -> void:
	system = s

func owns(hour: float) -> bool:
	return hour >= SUNRISE and hour < SUNSET

# Seasonal sunlight only moves once a day.
func on_day(t: TimeScript) -> void:
	_climate = 0.5 + 0.5 * cos(TAU / t.year_length() * (t.day_of_year() - 105.0))

func on_stop(_t: TimeScript) -> void:
	var hot := WeatherTable.has_flag(system.current, WeatherTable.Flag.HEAT)
	system.put_global(&"heatwave_intensity", heatwave_strength if hot else 0.0)

func track(t: TimeScript) -> void:
	var tod := t.time_of_day()
	var sun_f := clampf(sin(tod * PI), 0.0, 1.0)
	# Quantised: the moon shader reads it to wash out by day, and each change re-renders the sky.
	system.put(&"sun_intensity", int(sun_f * 64.0) / 64.0)
	if not sun:
		return
	var angle := (tod + system.equation_of_time - 0.5) * TAU
	var c := cos(angle)
	var altitude := system.altitude(system.tilt_bias, c)
	# Below the horizon the light only costs a shadow pass, so switch it off and stop moving it.
	var up := altitude < 0.1
	if not up and not sun.visible:
		return
	sun.rotation = Vector3(altitude, system.azimuth(angle, c, system.tilt_tan), sun.rotation.z)
	sun.visible = up
	var dim := 1.0 - weather_dimming if WeatherTable.has_flag(system.current, WeatherTable.DIMMING_FLAGS) else 1.0
	var energy := lerpf(0.01, 0.8 * _climate * dim, sun_f)
	if absf(energy - sun.light_energy) > 0.002:
		sun.light_energy = energy
		system.writes += 1

func target(hour: float, w: int) -> Array:
	var o: Array = WeatherTable.data(w)
	var top := SkySystem.sample(TOP, hour - 6.0).lerp(o[WeatherTable.TOP], o[WeatherTable.WEIGHT])
	var horizon := SkySystem.sample(HORIZON, hour - 6.0).lerp(o[WeatherTable.HORIZON], o[WeatherTable.WEIGHT])
	return [top, horizon]
