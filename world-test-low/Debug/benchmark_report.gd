class_name BenchmarkReport
extends RefCounted
## The report printed when P is pressed (see PerformanceReadout). Measured: frame time over the
## last minute against the frame budget, RAM and VRAM totals, and what is being drawn. Estimated:
## each mesh's and texture's share of VRAM, and the size of each Sky_System script's data tables
## (Godot has no per-script memory API). Printed to the Output panel and saved to a file in user://.

const SKY_RADIANCE_SIZES = [32, 64, 128, 256, 512, 1024, 2048]  # Sky.radiance_size options, in pixels

static func print_and_save(readout: PerformanceReadout) -> void:
	var scene := readout.get_tree().current_scene
	var lines := PackedStringArray(["===== BENCHMARK %s =====" % Time.get_datetime_string_from_system()])
	_add_frame_time(lines, readout)
	_add_memory(lines, readout)
	_add_vram_by_element(lines, scene)
	_add_script_data(lines, scene)
	var report := "\n".join(lines)
	print(report)
	var path := "user://benchmark_%s.txt" % Time.get_datetime_string_from_system().replace(":", "-")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(report)
		print("Benchmark saved to ", ProjectSettings.globalize_path(path))

static func _add_frame_time(lines: PackedStringArray, readout: PerformanceReadout) -> void:
	var samples := readout.frame_ms_history
	var budget_ms := 1000.0 / readout.target_fps
	lines.append("\n-- Frame time (measured, last %d s) --" % roundi(samples.size() * readout.refresh_seconds))
	if samples.is_empty():
		lines.append("No samples yet: wait a second and press P again.")
		return
	var sorted_samples := Array(samples)
	sorted_samples.sort()
	var best_ms: float = sorted_samples[0]
	var worst_ms: float = sorted_samples[-1]
	var average_ms: float = sorted_samples.reduce(func(sum, frame_ms): return sum + frame_ms, 0.0) / samples.size()
	lines.append("Budget  %.1f ms (%d FPS)" % [budget_ms, readout.target_fps])
	lines.append("Average %.1f ms = %d%% of budget, %.1f ms headroom" % [average_ms, roundi(average_ms / budget_ms * 100.0), budget_ms - average_ms])
	lines.append("Best %.1f ms | Worst %.1f ms = %d%% of budget" % [best_ms, worst_ms, roundi(worst_ms / budget_ms * 100.0)])
	lines.append("Scripts %.2f ms | Physics %.2f ms (this frame)" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
		lines.append("WARNING: V-Sync is on, so frame times are held to the monitor's rate. Turn it off to see the real cost.")

static func _add_memory(lines: PackedStringArray, readout: PerformanceReadout) -> void:
	var vram := int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	var texture_vram := int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
	var buffer_vram := int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED))
	lines.append("\n-- Memory (measured) --")
	lines.append("RAM  %s now | %s highest this session (0 in release exports)" % [String.humanize_size(OS.get_static_memory_usage()), String.humanize_size(OS.get_static_memory_peak_usage())])
	lines.append("VRAM %s now | %s highest seen by the readout" % [String.humanize_size(vram), String.humanize_size(readout.peak_vram)])
	lines.append("     textures %s | meshes and other buffers %s | everything else %s" % [String.humanize_size(texture_vram), String.humanize_size(buffer_vram), String.humanize_size(maxi(vram - texture_vram - buffer_vram, 0))])
	lines.append("Draw calls %d | Objects drawn %d | Triangles %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	lines.append("Objects %d | Nodes %d | Resources %d | Orphan nodes %d (should stay 0; growth means a leak)" % [Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)])

# Each mesh and texture in the scene with its estimated VRAM, biggest first. A mesh or texture
# shared by several nodes is counted once, under the first node that uses it.
static func _add_vram_by_element(lines: PackedStringArray, scene: Node) -> void:
	var counted := {}
	var elements := []  # [estimated bytes, description]
	for node: GeometryInstance3D in scene.find_children("*", "GeometryInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh if node is MeshInstance3D else null
		if mesh and not counted.has(mesh):
			counted[mesh] = true
			elements.append([_mesh_bytes(mesh), "mesh     %s (%s)" % [scene.get_path_to(node), mesh.get_class()]])
		for material in _materials_of(node, mesh):
			for texture in _textures_of(material):
				if not counted.has(texture):
					counted[texture] = true
					elements.append([texture.get_width() * texture.get_height() * 4 * 4 / 3, "texture  %s on %s (%dx%d)" % [texture.resource_path.get_file(), scene.get_path_to(node), texture.get_width(), texture.get_height()]])
	for world_env: WorldEnvironment in scene.find_children("*", "WorldEnvironment", true, false):
		if not world_env.environment or not world_env.environment.sky:
			continue
		var size: int = SKY_RADIANCE_SIZES[world_env.environment.sky.radiance_size]
		elements.append([size * size * 6 * 8 * 4 / 3, "sky      radiance map %dx%d, 6 faces (%s)" % [size, size, scene.get_path_to(world_env)]])
	elements.sort_custom(func(a, b): return a[0] > b[0])
	var total: int = elements.reduce(func(sum, element): return sum + element[0], 0)
	lines.append("\n-- VRAM by element (estimated: textures as uncompressed RGBA with mipmaps, so an upper bound) --")
	for element in elements.slice(0, 15):  # the 15 biggest
		lines.append("%10s  %s" % [String.humanize_size(element[0]), element[1]])
	lines.append("%10s  total of %d elements; the rest of measured VRAM is the engine's own buffers (screen, shadows)" % [String.humanize_size(total), elements.size()])

static func _mesh_bytes(mesh: Mesh) -> int:
	var bytes := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		bytes += arrays[Mesh.ARRAY_VERTEX].size() * 32  # position, normal, tangent and UV: ~32 bytes a vertex
		bytes += (arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null else 0) * 4  # 4 bytes an index
	return bytes

# The override material, plus each mesh surface's material (mesh is null for non-mesh nodes).
static func _materials_of(node: GeometryInstance3D, mesh: Mesh) -> Array:
	var materials := [node.material_override] if node.material_override else []
	for surface in (mesh.get_surface_count() if mesh else 0):
		var surface_material := (node as MeshInstance3D).get_active_material(surface)
		if surface_material:
			materials.append(surface_material)
	return materials

# Every texture a material uses: a standard material's texture slots, or a shader's parameters.
static func _textures_of(material: Material) -> Array:
	var standard_material := material as BaseMaterial3D
	var shader_material := material as ShaderMaterial
	var values := []
	if standard_material:
		values = range(BaseMaterial3D.TEXTURE_MAX).map(func(slot): return standard_material.get_texture(slot))
	elif shader_material and shader_material.shader:
		values = shader_material.shader.get_shader_uniform_list().map(func(uniform): return shader_material.get_shader_parameter(uniform.name))
	return values.filter(func(value): return value is Texture2D)

# Every node running a Sky_System script, with the size of that script's constant tables (the
# weather tables, colour tables and so on): roughly the RAM each one holds.
static func _add_script_data(lines: PackedStringArray, scene: Node) -> void:
	lines.append("\n-- Sky system script data (estimated RAM; per-function time is in Debugger > Profiler) --")
	for node in scene.find_children("*", "Node", true, false):
		var script: Script = node.get_script()
		if script and script.resource_path.begins_with("res://Sky_System"):
			var bytes := var_to_bytes(script.get_script_constant_map()).size()
			lines.append("%10s  %s (%s)" % [String.humanize_size(bytes), node.name, script.resource_path.get_file()])
