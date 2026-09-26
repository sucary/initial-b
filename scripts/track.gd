extends StaticBody2D
class_name RaceTrack

const CURVE_HANDLE_SCALE := 0.18
const BOUNDARIES_PATH := "res://resources/track-boundaries.json"
const GRASS_COLOR := Color(0.405, 0.555, 0.225)
const ROAD_COLOR := Color(0.27, 0.29, 0.30)
const BARRIER_COLOR := Color(0.07, 0.085, 0.11)
const FINISH_DARK := Color(0.08, 0.09, 0.10)
const FINISH_LIGHT := Color(0.94, 0.94, 0.90)
const WAYPOINTS := [
	Vector2(676, 1250),
	Vector2(676, 360),
	Vector2(940, 124),
	Vector2(1180, 260),
	Vector2(1380, 530),
	Vector2(1700, 530),
	Vector2(1820, 540),
	Vector2(1926, 360),
	Vector2(2100, 130),
	Vector2(2340, 130),
	Vector2(2610, 380),
	Vector2(2530, 640),
	Vector2(2320, 720),
	Vector2(1700, 840),
	Vector2(1380, 960),
	Vector2(1360, 1070),
	Vector2(1600, 1160),
	Vector2(2450, 1160),
	Vector2(2680, 1360),
	Vector2(2620, 1610),
	Vector2(2380, 1700),
	Vector2(2000, 1700),
	Vector2(1860, 1580),
	Vector2(1800, 1490),
	Vector2(1650, 1484),
	Vector2(1500, 1580),
	Vector2(1300, 1700),
	Vector2(1000, 1700),
	Vector2(760, 1600),
	Vector2(676, 1440),
]

var center_curve := Curve2D.new()
var centerline := PackedVector2Array()


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_build_curve()
	var contours := _load_boundaries()
	if contours.size() != 2:
		push_error("Track requires an outer and inner road boundary")
		return
	_build_art(contours)
	_build_walls(contours)


func get_start_transform() -> Transform2D:
	return center_curve.sample_baked_with_rotation(center_curve.get_baked_length() - 110.0)


func get_course_length() -> float:
	return center_curve.get_baked_length()


func get_progress_offset(world_position: Vector2) -> float:
	return center_curve.get_closest_offset(to_local(world_position))


func get_forward_at_offset(offset: float) -> Vector2:
	return center_curve.sample_baked_with_rotation(offset).x.normalized()

func get_checkpoint_offsets() -> PackedFloat32Array:
	var length := center_curve.get_baked_length()
	return PackedFloat32Array([length * 0.25, length * 0.5, length * 0.75])


func _build_curve() -> void:
	center_curve.bake_interval = 24.0
	for index in WAYPOINTS.size():
		var previous: Vector2 = WAYPOINTS[(index - 1 + WAYPOINTS.size()) % WAYPOINTS.size()]
		var following: Vector2 = WAYPOINTS[(index + 1) % WAYPOINTS.size()]
		var handle: Vector2 = (following - previous) * CURVE_HANDLE_SCALE
		center_curve.add_point(WAYPOINTS[index], -handle, handle)
	var closing_handle: Vector2 = (WAYPOINTS[1] - WAYPOINTS[-1]) * CURVE_HANDLE_SCALE
	center_curve.add_point(WAYPOINTS[0], -closing_handle, closing_handle)
	centerline = center_curve.get_baked_points()
	if centerline.size() > 1 and centerline[0].distance_to(centerline[-1]) < 1.0:
		centerline.resize(centerline.size() - 1)


func _load_boundaries() -> Array[PackedVector2Array]:
	var contours: Array[PackedVector2Array] = []
	var file := FileAccess.open(BOUNDARIES_PATH, FileAccess.READ)
	if file == null:
		push_error("Track boundary data is missing: " + BOUNDARIES_PATH)
		return contours
	var data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Invalid track boundary data")
		return contours
	for raw_contour in data["contours"]:
		var points := PackedVector2Array()
		for raw_point in raw_contour:
			points.append(Vector2(raw_point[0], raw_point[1]))
		contours.append(points)
	return contours


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
	var wall := ConcavePolygonShape2D.new()
	wall.segments = segments
	var collision := CollisionShape2D.new()
	collision.shape = wall
	add_child(collision)
