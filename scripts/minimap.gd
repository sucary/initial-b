extends Control
class_name Minimap

const FONT: FontFile = preload("res://assets/fonts/kart-pixel.fnt")
const PADDING := 10.0
const LEGEND_HEIGHT := 40.0
const LEGEND_FONT_SIZE := 24
const LEGEND_TEXT_COLOR := Color.WHITE
const ROAD_COLOR := Color(0.36, 0.39, 0.42)
const FINISH_COLOR := Color(0.95, 0.95, 0.92)
const LAP_COLORS := [Color(0.4, 0.84, 0.9), Color(0.95, 0.78, 0.26), Color(0.93, 0.45, 0.75)]
const PATH_WIDTH := 2.0

var routes: Array[PackedVector2Array] = []

var _world_to_map := Transform2D.IDENTITY
var _outer := PackedVector2Array()
var _inner := PackedVector2Array()
var _road := PackedVector2Array()
var _finish := PackedVector2Array()


func setup(track: RaceTrack) -> void:
	var contours := track.world_contours()
	var bounds := Rect2(contours[0][0], Vector2.ZERO)
	for point in contours[0]:
		bounds = bounds.expand(point)
	var area := _map_area()
	var map_scale := minf(area.size.x / bounds.size.x, area.size.y / bounds.size.y)
	var offset := area.position + (area.size - bounds.size * map_scale) * 0.5 - bounds.position * map_scale
	_world_to_map = Transform2D(0.0, Vector2.ONE * map_scale, 0.0, offset)
	_outer = _world_to_map * contours[0]
	_inner = _world_to_map * contours[1]
	_road = ring_polygon(_outer, _inner)
	var finish := track.get_road_section(0.0)
	_finish = PackedVector2Array([
		_world_to_map * (finish.center + finish.normal * finish.left),
		_world_to_map * (finish.center - finish.normal * finish.right),
	])
	queue_redraw()


func show_routes(new_routes: Array[PackedVector2Array]) -> void:
	routes = new_routes
	queue_redraw()


static func ring_polygon(outer: PackedVector2Array, inner: PackedVector2Array) -> PackedVector2Array:
	var hole := inner.duplicate()
	if Geometry2D.is_polygon_clockwise(hole) == Geometry2D.is_polygon_clockwise(outer):
		hole.reverse()
	var best := INF
	var outer_index := 0
	var hole_index := 0
	for i in range(outer.size()):
		for j in range(hole.size()):
			var gap := outer[i].distance_squared_to(hole[j])
			if gap < best:
				best = gap
				outer_index = i
				hole_index = j
	var ring := PackedVector2Array()
	for i in range(outer_index + 1):
		ring.append(outer[i])
	for j in range(hole.size() + 1):
		ring.append(hole[(hole_index + j) % hole.size()])
	for i in range(outer_index, outer.size()):
		ring.append(outer[i])
	return ring


func to_map(world_position: Vector2) -> Vector2:
	return _world_to_map * world_position


func lap_color(index: int) -> Color:
	return LAP_COLORS[index % LAP_COLORS.size()]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _map_area() -> Rect2:
	var box := size if size != Vector2.ZERO else custom_minimum_size
	return Rect2(Vector2.ONE * PADDING, box - Vector2(PADDING * 2.0, PADDING * 2.0 + LEGEND_HEIGHT))


func _draw() -> void:
	if _road.is_empty():
		return
	draw_colored_polygon(_road, ROAD_COLOR)
	draw_line(_finish[0], _finish[1], FINISH_COLOR, 2.0)
	for index in range(routes.size()):
		if routes[index].size() >= 2:
			draw_polyline(_world_to_map * routes[index], lap_color(index), PATH_WIDTH, true)
	var legend_y := roundf(size.y - PADDING - 4.0)
	var slot := (size.x - PADDING * 2.0) / maxi(routes.size(), 1)
	for index in range(routes.size()):
		var label := "LAP %d" % (index + 1)
		var label_width := FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LEGEND_FONT_SIZE).x
		var entry_width := 18.0 + label_width
		var left := roundf(PADDING + slot * (index + 0.5) - entry_width * 0.5)
		draw_rect(Rect2(left, legend_y - 12.0, 12.0, 6.0), lap_color(index))
		draw_string(FONT, Vector2(left + 18.0, legend_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, LEGEND_FONT_SIZE, LEGEND_TEXT_COLOR)
