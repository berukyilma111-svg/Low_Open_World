class_name PerformanceReadout
extends Label
## Debug readout of what the game costs while it runs: frame time against your frame budget,
## RAM and VRAM in use (and the highest seen), and how much is being drawn. Refreshes on a timer
## a couple of times a second, so it adds no per-frame work. Press P for a full benchmark report
## (see BenchmarkReport). Remove the node for release builds.

const FRAME_HISTORY_SIZE := 120  # frame-time samples kept for the benchmark report (60 s at 0.5 s)

@export var refresh_seconds: float = 0.5
@export var target_fps: int = 60  # the frame budget is 1000 / target_fps milliseconds

## Read by BenchmarkReport
var frame_ms_history := PackedFloat32Array()
var peak_vram := 0
var _peak_ram := 0

func _ready() -> void:
	var refresh_timer := Timer.new()
	refresh_timer.wait_time = refresh_seconds
	refresh_timer.timeout.connect(_refresh)
	add_child(refresh_timer)
	refresh_timer.start()

func _refresh() -> void:
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var frame_ms := 1000.0 / maxf(fps, 1.0)
	var budget_ms := 1000.0 / target_fps
	var script_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	# RAM: memory the engine and your scripts have allocated (reads 0 in release exports).
	var ram := OS.get_static_memory_usage()
	# VRAM: textures, meshes and other buffers Godot has put on the graphics card.
	var vram := int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	var texture_vram := int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
	_peak_ram = maxi(_peak_ram, ram)
	peak_vram = maxi(peak_vram, vram)
	frame_ms_history.append(frame_ms)
	if frame_ms_history.size() > FRAME_HISTORY_SIZE:
		frame_ms_history.remove_at(0)
	text = "FPS %d | Frame %.1f ms of %.1f ms budget (%d%%) | Scripts %.1f ms\n" % [fps, frame_ms, budget_ms, roundi(frame_ms / budget_ms * 100.0), script_ms]
	text += "RAM %s (peak %s) | VRAM %s (peak %s, textures %s)\n" % [String.humanize_size(ram), String.humanize_size(_peak_ram), String.humanize_size(vram), String.humanize_size(peak_vram), String.humanize_size(texture_vram)]
	text += "Draw calls %d | Objects %d | Triangles %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P:
		BenchmarkReport.print_and_save(self)
