class_name SkyLayer
extends Node
## Base for DaySky and NightSky. SkySystem drives every layer directly, in a fixed order; a layer
## never listens for events or reads the clock on its own. Override only the hooks you need.

var system: SkySystem
var writer: SkyWriter

func setup(s: SkySystem, w: SkyWriter) -> void:
	system = s
	writer = w

## True while this layer owns the sky colours at `hour`.
func owns(_hour: float) -> bool:
	return false

## Once per day, after SkySystem has updated the shared calendar.
func on_day(_t: TimeScript) -> void:
	pass

## Once per 3-hour stop, after SkySystem has rolled the weather.
func on_stop(_t: TimeScript) -> void:
	pass

## Every minute, whether or not this layer owns the sky (the sun and moon keep moving).
func track(_t: TimeScript) -> void:
	pass

## [top, horizon] sky colours for `hour` under `weather`, with the weather overlay applied.
func target(_hour: float, _weather: int) -> Array:
	return [Color.BLACK, Color.BLACK]

## Every minute while this layer owns the sky, after `track`.
func active(_t: TimeScript) -> void:
	pass

## Once, when this layer hands the sky over to the other one.
func released() -> void:
	pass
