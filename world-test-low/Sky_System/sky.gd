class_name SkyScript
extends Node
## Step 4 of 4. Where everything above plays out: moves the Sun and Moon nodes and feeds the sky
## shader. Sky colours come from one 24-hour table at 3-hour points (like GTA SA's time cycle),
## tinted by the weather and blended across each 3-hour stop. Unchanged values are never re-sent.

# Sky at 0, 3, 6, 9, 12, 15, 18, 21 h, and how dark each point is (0 = day, 1 = full night)
const TOP: Array[Color] = [Color(0.065, 0.058, 0.227), Color(0.0, 0.14, 0.25), Color(0.86, 0.638, 0.43), Color(0.022, 0.368, 0.609), Color(0.335, 0.68, 0.99), Color(0.18, 0.52, 0.8), Color(0.93, 0.52, 0.441), Color(0.06, 0.052, 0.223)]
const HORIZON: Array[Color] = [Color(0.006, 0.045, 0.214), Color(0.23, 0.23, 0.37), Color(0.861, 0.522, 0.212), Color(0.75, 0.84, 0.97), Color(0.874, 0.936, 0.999), Color(0.81, 0.88, 0.96), Color(0.988, 0.755, 0.554), Color(0.193, 0.183, 0.526)]
const DARKNESS: Array[float] = [1.0, 1.0, 0.5, 0.0, 0.0, 0.0, 0.0, 1.0]

@export var sun: DirectionalLight3D
@export var moon: Node3D
@export var world_env: WorldEnvironment
## Distinct sky blend values per 3-hour stop. Each change re-renders the sky.
@export_range(16, 1024) var blend_steps: int = 128
## How much cloud or dust cuts sunlight.
@export_range(0.0, 1.0) var weather_dimming: float = 0.5
@export var moon_base_angular_size: float = 0.009

## Shader and light writes actually sent, for profiling.
var writes := 0
var _shader: ShaderMaterial
var _sent := {}
var _now: Array
var _next: Array
var _from: Array
var _to: Array
var _shown: Array
var _start_hour: float
var _end_hour: float
var _last_step := -1
var _retarget := true

func _ready() -> void:
	_shader = world_env.environment.sky.sky_material as ShaderMaterial

## From Weather Conditions on each 3-hour stop: the looks of the weather now and next.
func on_weather(now: Array, next: Array) -> void:
	_now = now
	_next = next
	_retarget = true

func on_minute(c: Celestial, t: TimeScript) -> void:
	var h := fposmod(c.days, 1.0) * 24.0
	var light := clampf(c.sun_height(), 0.0, 1.0)
	_put(&"sun_intensity", int(light * 64.0) / 64.0)
	var s := c.sun_rotation()
	# Below the horizon the light only costs a shadow pass, so switch it off and stop moving it.
	if sun and (s.x < 0.1 or sun.visible):
		sun.rotation = Vector3(s.x, s.y, sun.rotation.z)
		sun.visible = s.x < 0.1
		var dim := 1.0 - weather_dimming * maxf(_now[WeatherConditions.CLOUD], _now[WeatherConditions.DUST])
		var energy := lerpf(0.01, 0.8 * dim, light)
		if absf(energy - sun.light_energy) > 0.002:
			sun.light_energy = energy
			writes += 1
	var m := c.moon_rotation()
	if moon:
		moon.rotation = Vector3(m.x, m.y, 0.0)
	# The shader only draws above the horizon; stop feeding it once the moon is well below it.
	var dir := Vector3(cos(m.x) * sin(m.y), -sin(m.x), cos(m.x) * cos(m.y))
	var hidden := -moon_base_angular_size * 2.0
	if dir.y > hidden or _sent.get(&"moon_direction", Vector3.UP).y > hidden:
		_put(&"moon_direction", dir, moon_base_angular_size * 0.02)
		_put(&"moon_phase", c.moon_phase(), 0.0005)
		_put(&"moon_angular_size", moon_base_angular_size * c.moon_size(), moon_base_angular_size * 0.002)
	# Airglow and stars only once the sun is down.
	var glow := 0.0
	if light <= 0.0:
		glow = (0.35 if t.season == Celestial.Season.BEGA else 0.12) * _at(DARKNESS, h) * (1.0 - _now[WeatherConditions.WEIGHT]) * (0.75 + 0.25 * sin(t.year * 0.57))
		_put(&"star_rotation", c.star_rotation(), 0.005)
	_put(&"airglow_intensity", glow, 0.001)
	if glow > 0.0:
		# 0 at dusk, PI at midnight, TAU at dawn, so the airglow animation never snaps at midnight.
		_put(&"elapsed_time", fposmod(h - 18.0, 24.0) / 12.0 * TAU, 0.005)
	_blend(h, t)

# One from -> to colour blend per stop, starting from whatever is on screen so nothing snaps.
func _blend(h: float, t: TimeScript) -> void:
	if _retarget:
		_retarget = false
		_start_hour = h
		_end_hour = t.hour - t.hour % TimeScript.STOP_HOURS + TimeScript.STOP_HOURS
		_from = _shown if not _shown.is_empty() else _colours(h, _now)
		_to = _colours(_end_hour, _next)
		for i in 2:
			_put([&"from_top", &"from_horizon"][i], _from[i])
			_put([&"to_top", &"to_horizon"][i], _to[i])
		_last_step = -1
	var step := int(clampf((h - _start_hour) / maxf(_end_hour - _start_hour, 0.001), 0.0, 1.0) * blend_steps)
	if step != _last_step:
		_last_step = step
		var b := float(step) / blend_steps
		_shown = [_from[0].lerp(_to[0], b), _from[1].lerp(_to[1], b)]
		_put(&"sky_blend", b)

# The time-cycle colours at `hour`, darkened for night and tinted by the weather `w`.
func _colours(hour: float, w: Array) -> Array:
	var dark: float = _at(DARKNESS, hour)
	var weight: float = w[WeatherConditions.WEIGHT] * (1.0 - dark * 0.85)
	var top: Color = _at(TOP, hour).darkened(dark * 0.72).lerp(w[WeatherConditions.TOP].darkened(dark * 0.8), weight)
	var horizon: Color = _at(HORIZON, hour).darkened(dark * 0.68).lerp(w[WeatherConditions.HORIZON].darkened(dark * 0.78), weight)
	return [top, horizon]

# Blends between the two 3-hour table points either side of `hour`, wrapping past midnight.
static func _at(table: Array, hour: float):
	var i := int(fposmod(hour, 24.0) / 3.0) % 8
	return lerp(table[i], table[(i + 1) % 8], fposmod(hour, 3.0) / 3.0)

func _put(param: StringName, value, eps: float = 0.0) -> void:
	var last = _sent.get(param)
	if last != null and (value == last or (eps > 0.0 and (absf(value - last) if value is float else value.distance_to(last)) <= eps)):
		return
	_sent[param] = value
	_shader.set_shader_parameter(param, value)
	writes += 1
