extends Control
class_name SpeedDashboard

const FONT: FontFile = preload("res://assets/fonts/kart-pixel.fnt")
const SPEED_DISPLAY_SCALE := 0.2
const NEEDLE_RESPONSE := 12.0
const DIAL_CENTER := Vector2(100, 100)
const DIAL_RADIUS := 80.0
const SWEEP_START := PI * 0.75
const SWEEP := PI * 1.5
const TICKS := 8
const PANEL_COLOR := Color(0.055, 0.065, 0.08, 0.78)
const TRACK_COLOR := Color(0.25, 0.27, 0.3)
const FILL_COLOR := Color(0.92, 0.94, 0.96)
const BOOST_COLOR := Color(1, 0.72, 0.2)
const NEEDLE_COLOR := Color(0.93, 0.28, 0.24)
const COUNTER_TOP := 196.0
const SLIDER_SIZE := Vector2(140, 8)
const MAX_FONT_SIZE := 12
const MAX_GAP := 4.0
const MAX_SHAKE := 2
const STROKE_SIZE := 4
const STROKE_COLOR := Color(0.055, 0.065, 0.08)

var speed := 0.0
var shown_speed := 0.0
var braid_count := 0
var window_fraction := 0.0
var maxed := false
var effect_color := BOOST_COLOR


func show_state(new_speed: float, new_braid_count: int, new_window_fraction: float, new_maxed: bool, new_effect_color: Color) -> void:
	speed = new_speed
	braid_count = new_braid_count
	window_fraction = clampf(new_window_fraction, 0.0, 1.0)
	maxed = new_maxed
	effect_color = new_effect_color


func speed_text() -> String:
	return str(roundi(shown_speed * SPEED_DISPLAY_SCALE))


func counter_text() -> String:
	if window_fraction <= 0.0 or braid_count <= 0:
		return ""
	return "%dX" % braid_count


func max_text() -> String:
	return "MAX" if maxed and not counter_text().is_empty() else ""


func shake_offset() -> Vector2:
	if max_text().is_empty():
		return Vector2.ZERO
	return Vector2(randi_range(-MAX_SHAKE, MAX_SHAKE), randi_range(-MAX_SHAKE, MAX_SHAKE))


func needle_angle() -> float:
	return SWEEP_START + SWEEP * clampf(shown_speed / PlayerKart.MAX_SPEED, 0.0, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(delta: float) -> void:
	shown_speed = lerpf(shown_speed, speed, 1.0 - exp(-NEEDLE_RESPONSE * delta))
	queue_redraw()


func _draw() -> void:
	draw_circle(DIAL_CENTER, DIAL_RADIUS + 10.0, PANEL_COLOR)
	var boost_start := SWEEP_START + SWEEP * PlayerKart.TOP_SPEED / PlayerKart.MAX_SPEED
	draw_arc(DIAL_CENTER, DIAL_RADIUS - 6.0, SWEEP_START, boost_start, 48, TRACK_COLOR, 8.0)
	draw_arc(DIAL_CENTER, DIAL_RADIUS - 6.0, boost_start, SWEEP_START + SWEEP, 16, BOOST_COLOR.darkened(0.45), 8.0)
	var fill_end := needle_angle()
	draw_arc(DIAL_CENTER, DIAL_RADIUS - 6.0, SWEEP_START, minf(fill_end, boost_start), 48, FILL_COLOR, 8.0)
	if fill_end > boost_start:
		draw_arc(DIAL_CENTER, DIAL_RADIUS - 6.0, boost_start, fill_end, 16, BOOST_COLOR, 8.0)
	for tick in range(TICKS + 1):
		var direction := Vector2.from_angle(SWEEP_START + SWEEP * tick / TICKS)
		draw_line(DIAL_CENTER + direction * (DIAL_RADIUS - 22.0), DIAL_CENTER + direction * (DIAL_RADIUS - 14.0), TRACK_COLOR, 2.0)
	draw_line(DIAL_CENTER, DIAL_CENTER + Vector2.from_angle(fill_end) * (DIAL_RADIUS - 18.0), NEEDLE_COLOR, 3.0)
	draw_circle(DIAL_CENTER, 6.0, NEEDLE_COLOR)
	draw_string(FONT, Vector2(0, DIAL_CENTER.y + 46.0), speed_text(), HORIZONTAL_ALIGNMENT_CENTER, DIAL_CENTER.x * 2.0, 24, FILL_COLOR)
	var counter := counter_text()
	if counter.is_empty():
		return
	var slider := Rect2(Vector2(DIAL_CENTER.x - SLIDER_SIZE.x * 0.5, COUNTER_TOP + 36.0), SLIDER_SIZE)
	var shake := shake_offset()
	slider.position += shake
	var tag := max_text()
	var counter_width := FONT.get_string_size(counter, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	var tag_width := FONT.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, MAX_FONT_SIZE).x if not tag.is_empty() else 0.0
	var left := DIAL_CENTER.x - (counter_width + (MAX_GAP + tag_width if not tag.is_empty() else 0.0)) * 0.5
	var baseline := COUNTER_TOP + 24.0
	_draw_stroked(Vector2(left, baseline) + shake, counter, 24)
	if not tag.is_empty():
		_draw_stroked(Vector2(left + counter_width + MAX_GAP, baseline) + shake, tag, MAX_FONT_SIZE)
	draw_rect(slider.grow(STROKE_SIZE * 0.5), STROKE_COLOR)
	draw_rect(slider, TRACK_COLOR)
	draw_rect(Rect2(slider.position, Vector2(slider.size.x * window_fraction, slider.size.y)), effect_color)


func _draw_stroked(position: Vector2, text: String, font_size: int) -> void:
	var reach := maxf(roundf(STROKE_SIZE * 0.5 * font_size / 24.0), 1.0)
	for offset in [Vector2(-reach, -reach), Vector2(0, -reach), Vector2(reach, -reach), Vector2(-reach, 0), Vector2(reach, 0), Vector2(-reach, reach), Vector2(0, reach), Vector2(reach, reach)]:
		draw_string(FONT, position + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, STROKE_COLOR)
	draw_string(FONT, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, effect_color)
