class_name TimeScript
extends Node
## Top of the chain and the only clock: advances the Ethiopian calendar, works out which tiers
## changed this frame, and pushes them straight into the sky pipeline. Nothing downstream keeps its
## own time or listens for its own events.

## Emitted after the sky has been updated, for gameplay code that wants to follow the clock.
signal ticked(tiers: int)

## What changed this frame. A higher tier always comes with every lower one it implies.
enum Tier { MINUTE = 1, STOP = 2, DAY = 4, SEASON = 8 }
const ALL_TIERS := Tier.MINUTE | Tier.STOP | Tier.DAY | Tier.SEASON

const STOP_HOURS := 3.0
const STOPS_PER_DAY := 8
const MONTH_NAMES = ["Month_1", "Month_2", "Month_3", "Month_4", "Month_5", "Month_6", "Month_7", "Month_8", "Month_9", "Month_10", "Month_11", "Month_12", "Month_13"]
const SEASON_NAMES = ["(MSKRM) / Harvest", "(BGA) / Dry Season", "(BLG) / Short Rains", "(KRMT) / Monsoon"]

@export var sky: SkySystem
@export var debug_label: Label
@export var minute_per_second: float = 60.0

@export_group("Date & Calendar (Ethiopian Specification)")
@export var year: int = 2018
@export_range(1, 13) var month: int = 1
@export_range(1, 30) var day: int = 1
@export_range(0, 23) var hour: int = 12
@export_range(0, 59) var minute: int = 0

var season: int = 0
var stop: int = 0
var day_of_year: int = 1
var total_days: int = 0
var _minute_fraction: float = 0.0

func _ready() -> void:
	_update_date()
	stop = int(hour / STOP_HOURS)
	# Run the whole pipeline once the rest of the scene is ready, so frame one is already correct.
	_push.call_deferred(ALL_TIERS)

func _process(delta: float) -> void:
	_minute_fraction += delta * minute_per_second
	if _minute_fraction < 1.0:
		return
	var steps := int(_minute_fraction)
	_minute_fraction -= steps
	minute += steps
	var tiers: int = Tier.MINUTE
	while minute >= 60:
		minute -= 60
		hour += 1
		if hour >= 24:
			hour = 0
			tiers |= Tier.DAY
			_advance_day()
	# Date first, then stop: weather rolled at midnight must already see the new season.
	if tiers & Tier.DAY:
		var old_season := season
		_update_date()
		if season != old_season:
			tiers |= Tier.SEASON
	var new_stop := int(hour / STOP_HOURS)
	if new_stop != stop or tiers & Tier.DAY:
		stop = new_stop
		tiers |= Tier.STOP
	_push(tiers)

func _push(tiers: int) -> void:
	if sky:
		sky.step(self, tiers)
	ticked.emit(tiers)
	if debug_label:
		debug_label.text = "Year %d | %s %d | [%s] | %d:%02d %s" % [year, MONTH_NAMES[month - 1], day, SEASON_NAMES[season], 12 if hour % 12 == 0 else hour % 12, minute, "PM" if hour >= 12 else "AM"]

func hours() -> float:
	return hour + minute / 60.0

func time_of_day() -> float:
	return (hour * 60 + minute) / 1440.0

func year_length() -> float:
	return 366.0 if year % 4 == 3 else 365.0

## [season, day_of_year, year] of the stop after the current one, crossing midnight if needed.
func next_stop_date() -> Array:
	if stop < STOPS_PER_DAY - 1:
		return [season, day_of_year, year]
	var d := date_after(year, month, day)
	return [season_of(d.y), (d.y - 1) * 30 + d.z, d.x]

func _advance_day() -> void:
	var d := date_after(year, month, day)
	year = d.x
	month = d.y
	day = d.z

func _update_date() -> void:
	day_of_year = (month - 1) * 30 + day
	total_days = year * 365 + int(year / 4) + day_of_year
	season = season_of(month)

## The calendar date one day after year/month/day, as (year, month, day).
static func date_after(y: int, m: int, d: int) -> Vector3i:
	d += 1
	var days_in_month := 30 if m < 13 else (6 if y % 4 == 3 else 5)
	if d > days_in_month:
		d = 1
		m += 1
		if m > 13:
			m = 1
			y += 1
	return Vector3i(y, m, d)

static func season_of(m: int) -> int:
	return 0 if m <= 3 else 1 if m <= 6 else 2 if m <= 9 else 3
