class_name Celestial
extends Node
## Step 1 of 4. Where the sun, moon and stars are, and nothing else: moves no nodes, touches no
## shaders. Each frame it turns the Earth and carries it along its orbit, then hands itself to
## Time, which reads the clock off the sun. Everything else is worked out from `days` when asked.

const ORBIT_DAYS := 365.25          # one orbit; the extra quarter day gives Pagume a 6th day every 4th year
const AXIAL_TILT := 0.4090928       # 23.44 degrees
const NEW_YEAR_LONGITUDE := 2.9496  # the sun's place on its yearly path on Meskerem 1 (~11 September)
const SYNODIC_MONTH := 29.53059     # new moon to new moon
const ANOMALISTIC_MONTH := 27.55    # the moon's nearest point to the next one (its size swing)
const SIDEREAL_TURNS := (ORBIT_DAYS + 1.0) / ORBIT_DAYS  # stars turn once more a year than the sun

enum Season { HARVEST, BEGA, BELG, KIREMT }
# Ethiopia's seasons follow the rain belt, which trails the sun north and south. The sun's
# declination (radians) where each season starts, while it heads north and while it heads south.
const NORTH_BELG := -0.0936         # -5.4 deg: short rains as the sun climbs back north
const NORTH_KIREMT := 0.3945        # 22.6 deg: main rains near the sun's northern turn
const SOUTH_HARVEST := 0.0759       # 4.35 deg: rains end as the sun heads south
const SOUTH_BEGA := -0.3992         # -22.9 deg: dry season around the sun's southern turn

@export var time: TimeScript
## Game minutes per real second.
@export var minute_per_second: float = 60.0
@export var latitude: float = 10.7058
@export_range(0, 360) var north_offset_degrees: float = 0.0

## Earth turns since the calendar's epoch: the whole part counts days, the fraction is where the
## sun is in today's sky (0 = midnight, 0.5 = noon).
var days: float
var _lat_sin: float
var _lat_cos: float
var _north: float

func _ready() -> void:
	_lat_sin = sin(deg_to_rad(latitude))
	_lat_cos = cos(deg_to_rad(latitude))
	_north = deg_to_rad(north_offset_degrees)
	days = time.start_days()

func _process(delta: float) -> void:
	days += delta * minute_per_second / 1440.0
	time.advance(self)

func declination() -> float:
	return asin(sin(AXIAL_TILT) * sin(_longitude()))

func season() -> int:
	var dec := declination()
	if cos(_longitude()) >= 0.0:  # sun heading north
		return Season.BEGA if dec < NORTH_BELG else Season.BELG if dec < NORTH_KIREMT else Season.KIREMT
	return Season.KIREMT if dec > SOUTH_HARVEST else Season.HARVEST if dec > SOUTH_BEGA else Season.BEGA

## Height of the sun: 1 straight overhead, 0 on the horizon, negative below it.
func sun_height() -> float:
	return _height(declination(), _hour_angle(0.0))

## Sun direction as a node rotation (x = -altitude, y = azimuth).
func sun_rotation() -> Vector2:
	return _rotation(declination(), _hour_angle(0.0))

## 0 = new moon, 0.5 = full moon.
func moon_phase() -> float:
	return fmod(days, SYNODIC_MONTH) / SYNODIC_MONTH

## Moon direction as a node rotation. It rides with the sun at new moon and opposite it at full
## moon, its orbit tipped 5 degrees.
func moon_rotation() -> Vector2:
	var dec := declination() * cos(moon_phase() * TAU) + 0.0897 * sin(days * 0.22997)
	return _rotation(dec, _hour_angle(-moon_phase()))

## How big the moon looks against its average size (0.93 far away to 1.07 close).
func moon_size() -> float:
	return lerpf(0.93, 1.07, 0.5 + 0.5 * cos(TAU * fmod(days, ANOMALISTIC_MONTH) / ANOMALISTIC_MONTH))

## How far the stars have turned (radians). Plumbing for a future star field.
func star_rotation() -> float:
	return fposmod(days * SIDEREAL_TURNS, 1.0) * TAU

func _longitude() -> float:
	return NEW_YEAR_LONGITUDE + fmod(days, ORBIT_DAYS) / ORBIT_DAYS * TAU

func _hour_angle(offset: float) -> float:
	return (fposmod(days, 1.0) + offset - 0.5) * TAU

func _height(dec: float, hour_angle: float) -> float:
	return _lat_sin * sin(dec) + _lat_cos * cos(dec) * cos(hour_angle)

func _rotation(dec: float, hour_angle: float) -> Vector2:
	var azimuth := atan2(sin(hour_angle), cos(hour_angle) * _lat_sin - tan(dec) * _lat_cos)
	return Vector2(-asin(_height(dec, hour_angle)), azimuth + _north)
