class_name SkyWriter
extends RefCounted
## The only thing that talks to the sky shader. Remembers what it last sent and skips any value
## that hasn't moved by more than its tolerance, so unchanged values cost nothing.

## Shader, light and global writes actually sent since start, for profiling.
var writes := 0

var _sky: ShaderMaterial
var _sent := {}

func _init(sky: ShaderMaterial) -> void:
	_sky = sky

func put(param: StringName, value, eps: float = 0.0) -> void:
	if _sent.has(param):
		var last = _sent[param]
		if eps > 0.0:
			if value is float:
				if absf(value - last) <= eps:
					return
			elif value is Vector3:
				if value.distance_to(last) <= eps:
					return
		elif value == last:
			return
	_sent[param] = value
	_sky.set_shader_parameter(param, value)
	writes += 1

## The value last sent for `param`, or `fallback` if it was never sent.
func sent(param: StringName, fallback = null):
	return _sent.get(param, fallback)

func put_global(param: StringName, value) -> void:
	var key := StringName("global/" + param)
	if _sent.get(key) == value:
		return
	_sent[key] = value
	RenderingServer.global_shader_parameter_set(param, value)
	writes += 1

func get_default(param: StringName):
	return _sky.get_shader_parameter(param)
