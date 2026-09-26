extends StaticBody2D
class_name RaceTrack

const BOUNDARIES_PATH := "res://resources/track-boundaries.json"
const GRASS_COLOR := Color(0.405, 0.555, 0.225)
const ROAD_COLOR := Color(0.27, 0.29, 0.30)
const BARRIER_COLOR := Color(0.07, 0.085, 0.11)
const FINISH_DARK := Color(0.08, 0.09, 0.10)
const FINISH_LIGHT := Color(0.94, 0.94, 0.90)
var center_curve := Curve2D.new()
var centerline := PackedVector2Array()
var _boundary_segments := PackedVector2Array()


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var data := _load_track_data()
	if data.is_empty():
		return
	_build_curve(_points(data["centerline"]))
	var contours: Array[PackedVector2Array] = []
	for raw_contour in data["contours"]:
		contours.append(_points(raw_contour))
	if contours.size() != 2:
		push_error("Track requires an outer and inner road boundary")
		return
	_build_art(contours)
	_build_walls(contours)


func get_course_length() -> float:
	return center_curve.get_baked_length()


func get_progress_offset(world_position: Vector2) -> float:
	return center_curve.get_closest_offset(to_local(world_position))


func get_forward_at_offset(offset: float) -> Vector2:
	return center_curve.sample_baked_with_rotation(offset).x.normalized()

func get_road_section(offset: float) -> Dictionary:
	var sample := center_curve.sample_baked_with_rotation(fposmod(offset, get_course_length()))
	var tangent := sample.x.normalized()
	var normal := tangent.orthogonal()
	var center := global_transform * sample.origin
	var world_tangent := (global_transform.basis_xform(tangent)).normalized()
	return {
		"center": center,
		"tangent": world_tangent,
		"normal": world_tangent.orthogonal(),
		"left": _distance_to_wall(sample.origin, normal) * global_scale.x,
		"right": _distance_to_wall(sample.origin, -normal) * global_scale.x,
	}


func _distance_to_wall(origin: Vector2, direction: Vector2) -> float:
	var nearest := INF
	var reach := origin + direction * 1000.0
	for index in range(0, _boundary_segments.size(), 2):
		var hit: Variant = Geometry2D.segment_intersects_segment(origin, reach, _boundary_segments[index], _boundary_segments[index + 1])
		if hit != null:
			nearest = minf(nearest, origin.distance_to(hit))
	return nearest


func get_checkpoint_offsets() -> PackedFloat32Array:
	var length := center_curve.get_baked_length()
	return PackedFloat32Array([length * 0.25, length * 0.5, length * 0.75])


func _build_curve(points: PackedVector2Array) -> void:
	center_curve.bake_interval = 8.0
	for point in points:
		center_curve.add_point(point)
	center_curve.add_point(points[0])
	centerline = center_curve.get_baked_points()
	if centerline.size() > 1 and centerline[0].distance_to(centerline[-1]) < 1.0:
		centerline.resize(centerline.size() - 1)


func _load_track_data() -> Dictionary:
	var file := FileAccess.open(BOUNDARIES_PATH, FileAccess.READ)
	if file == null:
		push_error("Track boundary data is missing: " + BOUNDARIES_PATH)
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or not data.has("centerline") or not data.has("contours"):
		push_error("Invalid track boundary data")
		return {}
	return data


func _points(raw_points: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for raw_point in raw_points:
		points.append(Vector2(raw_point[0], raw_point[1]))
	return points


func _build_art(contours: Array[PackedVector2Array]) -> void:
	_add_fill(contours[0], ROAD_COLOR)
	_add_fill(contours[1], GRASS_COLOR)
	_add_finish_line()
	for contour in contours:
		var barrier := Line2D.new()
		barrier.points = contour
		barrier.width = 10.0
		barrier.default_color = BARRIER_COLOR
		barrier.joint_mode = Line2D.LINE_JOINT_ROUND
		barrier.antialiased = true
		add_child(barrier)


func _add_fill(contour: PackedVector2Array, fill_color: Color) -> void:
	var polygon := Polygon2D.new()
	var points := PackedVector2Array()
	for index in range(contour.size() - 1):
		points.append(contour[index])
	polygon.polygon = points
	polygon.color = fill_color
	polygon.antialiased = true
	add_child(polygon)


func _add_finish_line() -> void:
	for row in range(2):
		for column in range(10):
			var x := 580.0 + column * 20.0
			var y := 1232.0 + row * 18.0
			var check := Polygon2D.new()
			check.polygon = PackedVector2Array([
				Vector2(x, y), Vector2(x + 20.0, y),
				Vector2(x + 20.0, y + 18.0), Vector2(x, y + 18.0),
			])
			check.color = FINISH_LIGHT if (row + column) % 2 == 0 else FINISH_DARK
			add_child(check)


func _build_walls(contours: Array[PackedVector2Array]) -> void:
	var segments := PackedVector2Array()
	for contour in contours:
		for index in range(contour.size() - 1):
			segments.append(contour[index])
			segments.append(contour[index + 1])
	_boundary_segments = segments
	var wall := ConcavePolygonShape2D.new()
	wall.segments = segments
	var collision := CollisionShape2D.new()
	collision.shape = wall
	add_child(collision)
