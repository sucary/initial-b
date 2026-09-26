extends Line2D
class_name LapPath

signal crossed(total_crossings: int)

const STATE_TEXTURES := {
	PathEffects.State.ICE: [preload("res://assets/sprites/path-ice-normal.png"), preload("res://assets/sprites/path-ice-active.png")],
	PathEffects.State.MUD: [preload("res://assets/sprites/path-mud-normal.png"), preload("res://assets/sprites/path-mud-active.png")],
	PathEffects.State.LIGHTNING: [preload("res://assets/sprites/path-lightning-normal.png"), preload("res://assets/sprites/path-lightning-active.png")],
}
const TEXTURE_COLUMNS := 64.0
const TEXTURE_ROWS := 32.0
const TEXTURE_CORE_ROWS := 16.0
const END_DISSOLVE_LENGTH := 36.0
const CELL_SIZE := 128.0
const REVEAL_SECONDS := 10.0
const END_PARTICLE_AMOUNT := 18
const END_PARTICLE_LIFETIME := 0.8
const END_PARTICLE_SPREAD := 40.0
const END_PARTICLE_SPEED_MIN := 12.0
const END_PARTICLE_SPEED_MAX := 36.0
const END_PARTICLE_SIZE_MIN := 1.5
const END_PARTICLE_SIZE_MAX := 3.0

@export_range(8.0, 64.0, 2.0) var path_width := 20.0
@export_range(4.0, 32.0, 2.0) var sample_spacing := 12.0
@export_range(0.1, 2.0, 0.1) var crossing_window_seconds := 1.0

var is_following := false
var total_crossings := 0

var _ribbon: MeshInstance2D
var _ribbon_material: ShaderMaterial
var _distance_at_point := PackedFloat32Array()
var _full_path_length := 0.0
var _revealed_distance := 0.0
var _reveal_elapsed := 0.0
var _visible_end_segment := 0
var _visible_end_point := Vector2.ZERO
var _recording := PackedVector2Array()
var _recording_times := PackedFloat32Array()
var _replay_times := PackedFloat32Array()
var _replay_fractions := PackedFloat32Array()
var _segment_cells: Dictionary = {}
var _center_inside := false
var _last_outside_side := 0.0
var _entry_side := 0.0
var _entry_time := 0.0
var _entry_anchor := Vector2.ZERO
var _entry_tangent := Vector2.RIGHT
var _entry_near_end := false
var _head_particles: CPUParticles2D
var _tail_particles: CPUParticles2D
var _core_colors := {}


func _ready() -> void:
	width = path_width * TEXTURE_ROWS / TEXTURE_CORE_ROWS
	default_color = Color.TRANSPARENT
	_ribbon = MeshInstance2D.new()
	_ribbon.texture = STATE_TEXTURES[PathEffects.State.ICE][0]
	_ribbon.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_ribbon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var ribbon_shader := Shader.new()
	ribbon_shader.code = """shader_type canvas_item;
uniform float reveal_distance = 0.0;
uniform float path_length = 0.0;
uniform float tile_length = 80.0;
uniform float dissolve_length = 36.0;
uniform vec2 texture_size = vec2(64.0, 32.0);
float texel_hash(vec2 texel) {
	vec3 p = fract(vec3(texel.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
void fragment() {
	vec4 ink = texture(TEXTURE, UV);
	float along = UV.x * tile_length;
	if (ink.a < 0.01 || along > reveal_distance) discard;
	float end_distance = min(along, min(reveal_distance, path_length) - along);
	float solidity = clamp(end_distance / dissolve_length, 0.0, 1.0);
	float grain = texel_hash(floor(UV * texture_size));
	if (grain > solidity * solidity * 1.15) discard;
	COLOR = vec4(ink.rgb, ink.a * mix(0.4, 1.0, solidity));
}"""
	_ribbon_material = ShaderMaterial.new()
	_ribbon_material.shader = ribbon_shader
	_ribbon_material.set_shader_parameter("tile_length", _tile_length())
	_ribbon_material.set_shader_parameter("dissolve_length", END_DISSOLVE_LENGTH)
	_ribbon_material.set_shader_parameter("texture_size", Vector2(TEXTURE_COLUMNS, TEXTURE_ROWS))
	_ribbon.material = _ribbon_material
	add_child(_ribbon)
	_tail_particles = _end_particles(-1.0)
	_head_particles = _end_particles(1.0)
	for textures in STATE_TEXTURES.values():
		for texture in textures:
			var core_color: Color = texture.get_image().get_pixel(int(TEXTURE_COLUMNS * 0.5), int(TEXTURE_ROWS * 0.5))
			core_color.a = 1.0
			_core_colors[texture] = core_color
	set_appearance(PathEffects.State.ICE, false)
	visible = false


func _end_particles(drift: float) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.emitting = false
	particles.amount = END_PARTICLE_AMOUNT
	particles.lifetime = END_PARTICLE_LIFETIME
	particles.local_coords = false
	particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(END_DISSOLVE_LENGTH * 0.5, path_width * 0.5)
	particles.direction = Vector2(drift, 0.0)
	particles.spread = END_PARTICLE_SPREAD
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = END_PARTICLE_SPEED_MIN
	particles.initial_velocity_max = END_PARTICLE_SPEED_MAX
	particles.scale_amount_min = END_PARTICLE_SIZE_MIN
	particles.scale_amount_max = END_PARTICLE_SIZE_MAX
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	particles.color_ramp = fade
	add_child(particles)
	return particles


func _process(delta: float) -> void:
	if has_previous_path():
		_update_end_particles()
	if has_previous_path() and _revealed_distance < _full_path_length:
		_reveal_elapsed = minf(_reveal_elapsed + delta, REVEAL_SECONDS)
		_revealed_distance = _full_path_length * _reveal_elapsed / REVEAL_SECONDS
		_ribbon_material.set_shader_parameter("reveal_distance", _revealed_distance)
		while _visible_end_segment + 1 < points.size() - 1 and _distance_at_point[_visible_end_segment + 1] < _revealed_distance:
			_visible_end_segment += 1
		var start_distance := _distance_at_point[_visible_end_segment]
		var segment_length := _distance_at_point[_visible_end_segment + 1] - start_distance
		var fraction := clampf((_revealed_distance - start_distance) / maxf(segment_length, 0.001), 0.0, 1.0)
		_visible_end_point = points[_visible_end_segment].lerp(points[_visible_end_segment + 1], fraction)


func begin_lap() -> void:
	_recording = PackedVector2Array()
	_recording_times = PackedFloat32Array()


func record_position(world_position: Vector2, lap_time: float) -> void:
	var local_position := to_local(world_position)
	if _recording.is_empty() or _recording[-1].distance_to(local_position) >= sample_spacing:
		_recording.append(local_position)
		_recording_times.append(lap_time)


func complete_lap() -> void:
	if _recording.size() >= 2:
		_store_replay_timing()
		points = _smoothed_route(_recording)
		_build_ribbon()
		_build_segment_cells()
		_reveal_elapsed = 0.0
		_revealed_distance = 0.0
		_visible_end_segment = 0
		_visible_end_point = points[0]
		_ribbon_material.set_shader_parameter("reveal_distance", 0.0)
		visible = true
		_tail_particles.restart()
		_head_particles.restart()
	begin_lap()
	_reset_contact()


func has_previous_path() -> bool:
	return points.size() >= 2


func update_contact(kart_transform: Transform2D, elapsed_seconds: float) -> void:
	if not has_previous_path():
		is_following = false
		return

	var center := to_local(kart_transform.origin)
	var nearest := _nearest_segment(center)
	var radius := path_width * 0.5
	var center_inside: bool = nearest.distance_squared <= radius * radius

	if center_inside and not _center_inside:
		_entry_side = _last_outside_side
		_entry_time = elapsed_seconds
		_entry_anchor = nearest.closest
		_entry_tangent = nearest.tangent
		_entry_near_end = _near_path_end(center)
	elif not center_inside and _center_inside:
		var exit_side := signf(_entry_tangent.cross(center - _entry_anchor))
		if _entry_side * exit_side < 0.0 and elapsed_seconds - _entry_time < crossing_window_seconds and not _entry_near_end and not _near_path_end(center):
			total_crossings += 1
			crossed.emit(total_crossings)

	if not center_inside:
		_last_outside_side = 0.0
		if nearest.distance_squared <= path_width * path_width * 2.25:
			_last_outside_side = signf(nearest.tangent.cross(center - nearest.closest))

	_center_inside = center_inside
	is_following = center_inside


func replay_start_time() -> float:
	return _replay_times[0] if has_previous_path() else INF


func replay_end_time() -> float:
	return _replay_times[-1] if has_previous_path() else -INF


func replay_transform(lap_time: float) -> Transform2D:
	var index := clampi(_replay_times.bsearch(lap_time) - 1, 0, _replay_times.size() - 2)
	var span := maxf(_replay_times[index + 1] - _replay_times[index], 0.0001)
	var weight := clampf((lap_time - _replay_times[index]) / span, 0.0, 1.0)
	var fraction := lerpf(_replay_fractions[index], _replay_fractions[index + 1], weight)
	var distance := fraction * _full_path_length
	var segment := clampi(_distance_at_point.bsearch(distance) - 1, 0, points.size() - 2)
	var segment_length := maxf(_distance_at_point[segment + 1] - _distance_at_point[segment], 0.0001)
	var along := clampf((distance - _distance_at_point[segment]) / segment_length, 0.0, 1.0)
	var start := points[segment]
	var end := points[segment + 1]
	return global_transform * Transform2D((end - start).angle(), start.lerp(end, along))


func set_appearance(state: PathEffects.State, active: bool) -> void:
	var texture: Texture2D = STATE_TEXTURES[state][1 if active else 0]
	_ribbon.texture = texture
	_tail_particles.color = _core_colors[texture]
	_head_particles.color = _core_colors[texture]


func _update_end_particles() -> void:
	var tail_direction := (points[1] - points[0]).normalized()
	_tail_particles.position = points[0] + tail_direction * END_DISSOLVE_LENGTH * 0.5
	_tail_particles.rotation = tail_direction.angle()
	var head_direction := (points[_visible_end_segment + 1] - points[_visible_end_segment]).normalized()
	_head_particles.position = _visible_end_point - head_direction * END_DISSOLVE_LENGTH * 0.5
	_head_particles.rotation = head_direction.angle()
	_head_particles.emitting = _revealed_distance > END_DISSOLVE_LENGTH


func _smoothed_route(route: PackedVector2Array) -> PackedVector2Array:
	var smooth := PackedVector2Array()
	for index in range(route.size()):
		if index == 0 or index == route.size() - 1:
			smooth.append(route[index])
			continue
		var weighted := Vector2.ZERO
		var total_weight := 0.0
		for offset in range(-3, 4):
			var neighbor := clampi(index + offset, 0, route.size() - 1)
			var weight := float(4 - absi(offset))
			weighted += route[neighbor] * weight
			total_weight += weight
		smooth.append(weighted / total_weight)
	for pass_index in range(2):
		var next := PackedVector2Array([smooth[0]])
		for index in range(smooth.size() - 1):
			var start := smooth[index]
			var end := smooth[index + 1]
			next.append(start.lerp(end, 0.25))
			next.append(start.lerp(end, 0.75))
		next.append(smooth[-1])
		smooth = next
	return smooth


func _store_replay_timing() -> void:
	_replay_times = _recording_times.duplicate()
	_replay_fractions = PackedFloat32Array([0.0])
	var travelled := 0.0
	for index in range(1, _recording.size()):
		travelled += _recording[index - 1].distance_to(_recording[index])
		_replay_fractions.append(travelled)
	for index in range(_replay_fractions.size()):
		_replay_fractions[index] /= maxf(travelled, 0.0001)


func _build_ribbon() -> void:
	var ribbon_data := _create_ribbon_mesh(points)
	_distance_at_point = ribbon_data["distances"]
	_full_path_length = ribbon_data["length"]
	_ribbon_material.set_shader_parameter("path_length", _full_path_length)
	_ribbon.mesh = ribbon_data["mesh"] as ArrayMesh


func _create_ribbon_mesh(route: PackedVector2Array) -> Dictionary:
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var distance := 0.0
	var distances := PackedFloat32Array()
	var half_width := width * 0.5
	for index in range(route.size()):
		var previous := route[maxi(index - 1, 0)]
		var following := route[mini(index + 1, route.size() - 1)]
		var tangent := (following - previous).normalized()
		var normal := tangent.orthogonal()
		if index > 0:
			distance += route[index - 1].distance_to(route[index])
		distances.append(distance)
		vertices.append(route[index] - normal * half_width)
		vertices.append(route[index] + normal * half_width)
		uvs.append(Vector2(distance / _tile_length(), 0.0))
		uvs.append(Vector2(distance / _tile_length(), 1.0))
		if index + 1 < route.size():
			var first := index * 2
			indices.append_array(PackedInt32Array([first, first + 1, first + 2, first + 1, first + 3, first + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var ribbon_mesh := ArrayMesh.new()
	ribbon_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {"mesh": ribbon_mesh, "distances": distances, "length": distance}


func _tile_length() -> float:
	return TEXTURE_COLUMNS * path_width / TEXTURE_CORE_ROWS


func _nearest_segment(local_position: Vector2) -> Dictionary:
	var best_distance_squared := INF
	var best_closest := Vector2.ZERO
	var best_tangent := Vector2.RIGHT
	for index in _candidate_indices(local_position):
		var start_distance := _distance_at_point[index]
		if start_distance >= _revealed_distance:
			continue
		var start := points[index]
		var end := points[index + 1]
		if _distance_at_point[index + 1] > _revealed_distance:
			var fraction := (_revealed_distance - start_distance) / maxf(_distance_at_point[index + 1] - start_distance, 0.001)
			end = start.lerp(end, fraction)
		var segment := end - start
		if segment.length_squared() < 0.01:
			continue
		var closest := Geometry2D.get_closest_point_to_segment(local_position, start, end)
		var distance_squared := closest.distance_squared_to(local_position)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_closest = closest
			best_tangent = segment.normalized()
	return {
		"distance_squared": best_distance_squared,
		"closest": best_closest,
		"tangent": best_tangent,
	}


func _candidate_indices(local_position: Vector2) -> Array:
	var cell := Vector2i(floori(local_position.x / CELL_SIZE), floori(local_position.y / CELL_SIZE))
	return _segment_cells.get(cell, [])


func _build_segment_cells() -> void:
	_segment_cells.clear()
	var margin := path_width * 1.5
	for index in range(points.size() - 1):
		var start := points[index]
		var end := points[index + 1]
		var left := floori((minf(start.x, end.x) - margin) / CELL_SIZE)
		var right := floori((maxf(start.x, end.x) + margin) / CELL_SIZE)
		var top := floori((minf(start.y, end.y) - margin) / CELL_SIZE)
		var bottom := floori((maxf(start.y, end.y) + margin) / CELL_SIZE)
		for cell_x in range(left, right + 1):
			for cell_y in range(top, bottom + 1):
				var cell := Vector2i(cell_x, cell_y)
				var indices: Array = _segment_cells.get(cell, [])
				indices.append(index)
				_segment_cells[cell] = indices


func _near_path_end(local_position: Vector2) -> bool:
	var end_radius_squared := path_width * path_width
	return local_position.distance_squared_to(points[0]) <= end_radius_squared or local_position.distance_squared_to(_visible_end_point) <= end_radius_squared


func _reset_contact() -> void:
	_center_inside = false
	_last_outside_side = 0.0
	_entry_side = 0.0
	is_following = false
