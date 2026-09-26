extends Node2D
class_name StartGrid

const SLOT_COUNT := 4
const FINISH_STRIP_HALF_DEPTH := 48.0
const POLE_GAP := 20.0
const KART_HALF_LENGTH := 30.0
const SLOT_SPACING := 120.0
const LANE_OFFSET := 70.0
const SLOT_HALF_WIDTH := 28.0
const LEG_LENGTH := 26.0
const LINE_WIDTH := 4.0
const LINE_COLOR := Color(0.95, 0.95, 0.92, 0.85)

var _slots: Array[Transform2D] = []


func build(track: RaceTrack) -> void:
	_slots.clear()
	var length := track.get_course_length()
	var scale_factor := track.global_scale.x
	for index in range(SLOT_COUNT):
		var behind := FINISH_STRIP_HALF_DEPTH + POLE_GAP + KART_HALF_LENGTH + SLOT_SPACING * index
		var section := track.get_road_section(length - behind / scale_factor)
		var side := 1.0 if index % 2 == 0 else -1.0
		var center: Vector2 = section.center + section.normal * LANE_OFFSET * side
		_slots.append(Transform2D(section.tangent.angle(), center))
	queue_redraw()


func slot_count() -> int:
	return _slots.size()


func slot_transform(index: int) -> Transform2D:
	return _slots[index]


func _draw() -> void:
	for slot in _slots:
		var forward := slot.x.normalized()
		var across := forward.orthogonal()
		var front := slot.origin + forward * (KART_HALF_LENGTH + LINE_WIDTH)
		var left := front + across * SLOT_HALF_WIDTH
		var right := front - across * SLOT_HALF_WIDTH
		draw_line(left, right, LINE_COLOR, LINE_WIDTH)
		draw_line(left, left - forward * LEG_LENGTH, LINE_COLOR, LINE_WIDTH)
		draw_line(right, right - forward * LEG_LENGTH, LINE_COLOR, LINE_WIDTH)
