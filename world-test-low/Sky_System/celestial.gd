class_name Celestial
extends Node
## Step 1 of 4. Where the sun, moon and stars are, and nothing else: moves no nodes, touches no
## shaders. Each frame it turns the Earth and carries it along its orbit, then hands itself to
## Time, which reads the clock off the sun. Everything else is worked out from `elapsed_days`.

const DAYS_PER_ORBIT := 365.25            # the extra quarter day gives Pagume a 6th day every 4th year
const EARTH_AXIAL_TILT := 0.4090928       # 23.44 degrees, in radians
const SUN_ORBIT_ANGLE_AT_NEW_YEAR := 2.9496  # where the sun is on its yearly path on Meskerem 1 (~11 September)
const DAYS_PER_MOON_PHASE_CYCLE := 29.53059  # new moon to new moon
const DAYS_PER_MOON_DISTANCE_CYCLE := 27.55  # closest to the Earth, to closest again
const STAR_TURNS_PER_DAY := (DAYS_PER_ORBIT + 1.0) / DAYS_PER_ORBIT  # one extra turn a year

enum Season { HARVEST, BEGA, BELG, KIREMT }
# Ethiopia's seasons follow the rain belt, which trails the sun north and south across the year.
# Each season starts when the sun reaches a set declination (how far north of the equator it is,
# in radians). The north-bound and south-bound boundaries differ because the rains lag the sun.
const BELG_STARTS_HEADING_NORTH := -0.0936    # -5.4 degrees
const KIREMT_STARTS_HEADING_NORTH := 0.3945   # 22.6 degrees
const HARVEST_STARTS_HEADING_SOUTH := 0.0759  # 4.35 degrees
const BEGA_STARTS_HEADING_SOUTH := -0.3992    # -22.9 degrees

@export var time: TimeScript
@export var minute_per_second: float = 60.0  # game minutes per real second
@export var latitude: float = 10.7058
@export_range(0, 360) var north_offset_degrees: float = 0.0

## Days since the calendar began. The whole part counts days; the fraction is where the sun is
## in today's sky (0 = midnight, 0.5 = noon).
var elapsed_days: float
var _latitude_sin: float
var _latitude_cos: float
var _north_offset: float

func _ready() -> void:
	_latitude_sin = sin(deg_to_rad(latitude))
	_latitude_cos = cos(deg_to_rad(latitude))
	_north_offset = deg_to_rad(north_offset_degrees)
	elapsed_days = time.start_date_as_elapsed_days()

func _process(delta: float) -> void:
	elapsed_days += delta * minute_per_second / 1440.0
	time.update_from_celestial(self)

## How far north of the equator the sun is (radians).
func sun_declination() -> float:
	return asin(sin(EARTH_AXIAL_TILT) * sin(_sun_orbit_angle()))

func current_season() -> int:
	var declination := sun_declination()
	var sun_heading_north := cos(_sun_orbit_angle()) >= 0.0
	if sun_heading_north:
		if declination < BELG_STARTS_HEADING_NORTH:
			return Season.BEGA
		return Season.BELG if declination < KIREMT_STARTS_HEADING_NORTH else Season.KIREMT
	if declination > HARVEST_STARTS_HEADING_SOUTH:
		return Season.KIREMT
	return Season.HARVEST if declination > BEGA_STARTS_HEADING_SOUTH else Season.BEGA

## How high the sun is: 1 straight overhead, 0 on the horizon, negative below it.
func sun_height() -> float:
	return _height_above_horizon(sun_declination(), _angle_from_noon(0.0))

## The sun's direction as a node rotation (x = tilt down from the horizon, y = compass heading).
func sun_node_rotation() -> Vector2:
	return _node_rotation(sun_declination(), _angle_from_noon(0.0))

## 0 = new moon, 0.5 = full moon.
func moon_phase() -> float:
	return fmod(elapsed_days, DAYS_PER_MOON_PHASE_CYCLE) / DAYS_PER_MOON_PHASE_CYCLE

## The moon's direction as a node rotation. It rides with the sun at new moon and opposite it at
## full moon, with its orbit tipped 5 degrees.
func moon_node_rotation() -> Vector2:
	var declination := sun_declination() * cos(moon_phase() * TAU) + 0.0897 * sin(elapsed_days * 0.22997)
	return _node_rotation(declination, _angle_from_noon(-moon_phase()))

## How big the moon looks compared with its average size (0.93 far away, 1.07 close).
func moon_size_multiplier() -> float:
	var distance_cycle := fmod(elapsed_days, DAYS_PER_MOON_DISTANCE_CYCLE) / DAYS_PER_MOON_DISTANCE_CYCLE
	return lerpf(0.93, 1.07, 0.5 + 0.5 * cos(TAU * distance_cycle))

## How far the stars have turned (radians). Plumbing for a future star field.
func star_field_rotation() -> float:
	return fposmod(elapsed_days * STAR_TURNS_PER_DAY, 1.0) * TAU

func _sun_orbit_angle() -> float:
	return SUN_ORBIT_ANGLE_AT_NEW_YEAR + fmod(elapsed_days, DAYS_PER_ORBIT) / DAYS_PER_ORBIT * TAU

# How far a body has turned past its highest point today (radians; 0 = noon for the sun).
func _angle_from_noon(day_offset: float) -> float:
	return (fposmod(elapsed_days, 1.0) + day_offset - 0.5) * TAU

func _height_above_horizon(declination: float, angle_from_noon: float) -> float:
	return _latitude_sin * sin(declination) + _latitude_cos * cos(declination) * cos(angle_from_noon)

func _node_rotation(declination: float, angle_from_noon: float) -> Vector2:
	var heading := atan2(sin(angle_from_noon), cos(angle_from_noon) * _latitude_sin - tan(declination) * _latitude_cos)
	return Vector2(-asin(_height_above_horizon(declination, angle_from_noon)), heading + _north_offset)
