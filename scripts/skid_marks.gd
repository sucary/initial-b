extends Node2D
class_name SkidMarks

const MARK_COLOR := Color(0.07, 0.07, 0.08, 0.55)
const MARK_WIDTH := 4.0
const SAMPLE_SPACING := 6.0
const HOLD_SECONDS := 6.0
const FADE_SECONDS := 2.0
const MAX_POINTS := 1200

var strokes: Array[Dictionary] = []
var _active: Dictionary = {}
var _clock := 0.0


func add_marks(left: Vector2, right: Vector2) -> void:
	if _active.is_empty():
		_active = {"left": PackedVector2Array([left]), "right": PackedVector2Array([right]), "ended_at": INF}
		strokes.append(_active)
	elif _active.left[-1].distance_to(left) >= SAMPLE_SPACING:
		_active.left.append(left)
		_active.right.append(right)
	_trim()
	queue_redraw()


func end_stroke() -> void:
	if _active.is_empty():
		return
	_active.ended_at = _clock
	_active = {}


func point_count() -> int:
	var total := 0
	for stroke in strokes:
		total += stroke.left.size()
	return total


func stroke_alpha(stroke: Dictionary) -> float:
	return 1.0 - clampf((_clock - stroke.ended_at - HOLD_SECONDS) / FADE_SECONDS, 0.0, 1.0)


func _process(delta: float) -> void:
	_clock += delta
	if strokes.is_empty():
		return
	strokes = strokes.filter(func(stroke: Dictionary) -> bool: return stroke_alpha(stroke) > 0.0)
	queue_redraw()


func _trim() -> void:
	while point_count() > MAX_POINTS and strokes.size() > 1:
		strokes.pop_front()


func _draw() -> void:
	for stroke in strokes:
		if stroke.left.size() < 2:
			continue
		var color := MARK_COLOR
		color.a *= stroke_alpha(stroke)
		draw_polyline(stroke.left, color, MARK_WIDTH)
		draw_polyline(stroke.right, color, MARK_WIDTH)
