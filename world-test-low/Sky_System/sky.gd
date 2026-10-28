class_name SkyScript
extends Node
## Step 4 of 4. Where everything above plays out: moves the Sun and Moon nodes, feeds the sky
## shader and sets the distance fog. The sky's look (colours from one 24-hour table like GTA SA's
## time cycle, plus the weather's sunlight and fog) is blended across each 3-hour weather period.
## The fog takes the horizon colour, so it matches the sky. Unchanged values are never re-sent.

# Sky colours at 0, 3, 6, 9, 12, 15, 18 and 21 h, and how dark each point is (0 = day, 1 = night)
const SKY_TOP_BY_HOUR: Array[Color] = [Color(0.065, 0.058, 0.227), Color(0.0, 0.14, 0.25), Color(0.86, 0.638, 0.43), Color(0.022, 0.368, 0.609), Color(0.335, 0.68, 0.99), Color(0.18, 0.52, 0.8), Color(0.93, 0.52, 0.441), Color(0.06, 0.052, 0.223)]
const SKY_HORIZON_BY_HOUR: Array[Color] = [Color(0.006, 0.045, 0.214), Color(0.23, 0.23, 0.37), Color(0.861, 0.522, 0.212), Color(0.75, 0.84, 0.97), Color(0.874, 0.936, 0.999), Color(0.81, 0.88, 0.96), Color(0.988, 0.755, 0.554), Color(0.193, 0.183, 0.526)]
const DARKNESS_BY_HOUR: Array[float] = [1.0, 1.0, 0.5, 0.0, 0.0, 0.0, 0.0, 1.0]

# Fields of a sky look: what is blended across each weather period
enum { LOOK_TOP_COLOUR, LOOK_HORIZON_COLOUR, LOOK_SUN_STRENGTH, LOOK_FOG_AMOUNT }

@export var sun: DirectionalLight3D
@export var moon: Node3D
@export var world_env: WorldEnvironment
@export_range(16, 1024) var blend_steps: int = 128  # sky colour updates per weather period; each one re-renders the sky
@export var draw_distance: float = 400.0  # where the fog wall is solid on a clear day; match Camera3D Far to it
@export_range(0.0, 1.0) var fog_begin_share: float = 0.6  # the fog starts at this share of the way to the wall
@export var moon_base_angular_size: float = 0.05  # radius in radians (the real moon is ~0.0045)

@onready var _sky_shader := world_env.environment.sky.sky_material as ShaderMaterial
var _last_sent_values := {}
var _current_weather_profile: Array
var _next_weather_profile: Array
var _look_on_screen: Array
var _blend_start_look: Array
var _blend_end_look: Array
var _blend_start_hour: float
var _blend_end_hour: float
var _last_blend_step := -1

## Called by Weather Conditions at the start of each 3-hour weather period.
func set_weather_profiles(current_profile: Array, next_profile: Array) -> void:
	_current_weather_profile = current_profile
	_next_weather_profile = next_profile
	_blend_end_look = []  # empty = start a new blend on the next minute

## Called by Time every new game minute.
func update_sky(celestial: Celestial, time: TimeScript) -> void:
	var hour := fposmod(celestial.elapsed_days, 1.0) * 24.0
	_blend_sky_look(hour, time)
	var sunlight := clampf(celestial.sun_height(), 0.0, 1.0)
	_send_to_shader(&"sun_intensity", int(sunlight * 64.0) / 64.0)
	_update_sun(celestial.sun_node_rotation(), sunlight)
	_update_moon(celestial)
	var airglow := 0.0
	if sunlight <= 0.0:  # airglow and stars only once the sun is down
		var season_glow := 0.35 if time.season == Celestial.Season.BEGA else 0.12
		var clear_sky: float = 1.0 - _current_weather_profile[WeatherConditions.CLOUD_AMOUNT]
		airglow = season_glow * _sample_by_hour(DARKNESS_BY_HOUR, hour) * 0.4 * clear_sky * (0.75 + 0.25 * sin(time.year * 0.57))
		_send_to_shader(&"star_rotation", celestial.star_field_rotation(), 0.005)
	_send_to_shader(&"airglow_intensity", airglow, 0.001)
	if airglow > 0.0:  # runs 0 at dusk, PI at midnight, TAU at dawn, so it never jumps at midnight
		_send_to_shader(&"elapsed_time", fposmod(hour - 18.0, 24.0) / 12.0 * TAU, 0.005)

func _update_sun(sun_rotation: Vector2, sunlight: float) -> void:
	if sun_rotation.x < 0.1 or sun.visible:  # once down, the light is switched off and left alone
		sun.rotation = Vector3(sun_rotation.x, sun_rotation.y, sun.rotation.z)
		sun.visible = sun_rotation.x < 0.1  # still up
		sun.light_energy = lerpf(0.01, 0.8 * _look_on_screen[LOOK_SUN_STRENGTH], sunlight)

func _update_moon(celestial: Celestial) -> void:
	var moon_rotation := celestial.moon_node_rotation()
	moon.rotation = Vector3(moon_rotation.x, moon_rotation.y, 0.0)
	var direction := Vector3(cos(moon_rotation.x) * sin(moon_rotation.y), -sin(moon_rotation.x), cos(moon_rotation.x) * cos(moon_rotation.y))
	# The shader only draws above the horizon, so stop sending once the moon is well below it.
	var below_horizon := -moon_base_angular_size * 2.0
	if direction.y > below_horizon or _last_sent_values.get(&"moon_direction", Vector3.UP).y > below_horizon:
		_send_to_shader(&"moon_direction", direction, moon_base_angular_size * 0.02)
		_send_to_shader(&"moon_phase", celestial.moon_phase(), 0.0005)
		_send_to_shader(&"moon_angular_size", moon_base_angular_size * celestial.moon_size_multiplier(), moon_base_angular_size * 0.002)

# Fades from the look on screen to this weather period's end look, so nothing jumps.
func _blend_sky_look(hour: float, time: TimeScript) -> void:
	if _blend_end_look.is_empty():
		_blend_start_hour = hour
		_blend_end_hour = time.hour - time.hour % TimeScript.WEATHER_PERIOD_HOURS + TimeScript.WEATHER_PERIOD_HOURS
		_blend_start_look = _look_on_screen if not _look_on_screen.is_empty() else _sky_look_at(hour, _current_weather_profile)
		_blend_end_look = _sky_look_at(_blend_end_hour, _next_weather_profile)
		_send_to_shader(&"from_top", _blend_start_look[LOOK_TOP_COLOUR])
		_send_to_shader(&"from_horizon", _blend_start_look[LOOK_HORIZON_COLOUR])
		_send_to_shader(&"to_top", _blend_end_look[LOOK_TOP_COLOUR])
		_send_to_shader(&"to_horizon", _blend_end_look[LOOK_HORIZON_COLOUR])
		_last_blend_step = -1
	var progress := clampf((hour - _blend_start_hour) / maxf(_blend_end_hour - _blend_start_hour, 0.001), 0.0, 1.0)
	var blend_step := int(progress * blend_steps)
	if blend_step != _last_blend_step:
		_last_blend_step = blend_step
		var blend := float(blend_step) / blend_steps
		# Each field of the look (colours, sun strength, fog) moves the same share of the way.
		_look_on_screen = range(_blend_start_look.size()).map(func(field): return lerp(_blend_start_look[field], _blend_end_look[field], blend))
		_send_to_shader(&"sky_blend", blend)
		_send_to_shader(&"sun_strength", _look_on_screen[LOOK_SUN_STRENGTH], 0.01)  # mutes the sunrise/sunset glow
		_update_fog()

# GTA SA-style distance fog: a wall that fades the world out between the fog start and the wall,
# in the sky's horizon colour so the edge of the world melts into the sky. The weather's fog
# amount pulls the wall closer (1 = a fifth of the draw distance). The Environment's fog mode,
# curve and sky affect are fixed in the editor; the sky itself is never fogged.
func _update_fog() -> void:
	world_env.environment.fog_depth_end = lerpf(draw_distance, draw_distance * 0.2, _look_on_screen[LOOK_FOG_AMOUNT])
	world_env.environment.fog_depth_begin = world_env.environment.fog_depth_end * fog_begin_share
	world_env.environment.fog_light_color = _look_on_screen[LOOK_HORIZON_COLOUR]

# The sky's look at `hour`: colours darkened for night and tinted by the weather, plus the
# weather's sunlight and fog.
func _sky_look_at(hour: float, weather_profile: Array) -> Array:
	var darkness: float = _sample_by_hour(DARKNESS_BY_HOUR, hour)
	var tint_strength: float = weather_profile[WeatherConditions.TINT_STRENGTH] * (1.0 - darkness * 0.85)
	var top: Color = _sample_by_hour(SKY_TOP_BY_HOUR, hour).darkened(darkness * 0.72)
	var horizon: Color = _sample_by_hour(SKY_HORIZON_BY_HOUR, hour).darkened(darkness * 0.68)
	top = top.lerp(weather_profile[WeatherConditions.SKY_TOP_TINT].darkened(darkness * 0.8), tint_strength)
	horizon = horizon.lerp(weather_profile[WeatherConditions.SKY_HORIZON_TINT].darkened(darkness * 0.78), tint_strength)
	return [top, horizon, weather_profile[WeatherConditions.SUN_STRENGTH], weather_profile[WeatherConditions.FOG_AMOUNT]]

# Blends the two 3-hourly table entries either side of `hour`, wrapping past midnight.
static func _sample_by_hour(table: Array, hour: float):
	var index := int(fposmod(hour, 24.0) / 3.0) % 8
	return lerp(table[index], table[(index + 1) % 8], fposmod(hour, 3.0) / 3.0)

# Sends a value to the sky shader unless it has moved less than `min_change` since the last send.
func _send_to_shader(parameter: StringName, value, min_change: float = 0.0) -> void:
	if _last_sent_values.has(parameter):
		var last_value = _last_sent_values[parameter]
		var change: float = absf(value - last_value) if value is float else (value.distance_to(last_value) if value is Vector3 else 1.0)
		if value == last_value or change <= min_change:
			return
	_last_sent_values[parameter] = value
	_sky_shader.set_shader_parameter(parameter, value)
