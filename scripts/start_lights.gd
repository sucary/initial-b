extends HBoxContainer
class_name StartLights

signal go

const RED: Texture2D = preload("res://assets/sprites/start-light-red.png")
const GREEN: Texture2D = preload("res://assets/sprites/start-light-green.png")
const LIGHT_COUNT := 3
const LIGHT_SCALE := 2
const FIRST_LIGHT_DELAY := 0.5
const LIGHT_INTERVAL := 1.0
const GREEN_HOLD := 1.0
const FADE_SECONDS := 0.3
const UNLIT := Color(0.28, 0.28, 0.3)

var elapsed := 0.0
var started := false

var _lamps: Array[TextureRect] = []


func green_time() -> float:
	return FIRST_LIGHT_DELAY + LIGHT_INTERVAL * LIGHT_COUNT


func lit_count() -> int:
	if started:
		return LIGHT_COUNT
	return clampi(floori((elapsed - FIRST_LIGHT_DELAY) / LIGHT_INTERVAL) + 1, 0, LIGHT_COUNT)


func finish() -> void:
	elapsed = green_time()
	_update_lamps()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 16)
	for index in range(LIGHT_COUNT):
		var lamp := TextureRect.new()
		lamp.texture = RED
		lamp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		lamp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lamp.stretch_mode = TextureRect.STRETCH_SCALE
		lamp.custom_minimum_size = RED.get_size() * LIGHT_SCALE
		lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(lamp)
		_lamps.append(lamp)
	_update_lamps()


func _process(delta: float) -> void:
	if not visible:
		return
	elapsed += delta
	_update_lamps()


func _update_lamps() -> void:
	if not started and elapsed >= green_time():
		started = true
		go.emit()
	for index in range(_lamps.size()):
		var lamp := _lamps[index]
		lamp.texture = GREEN if started else RED
		lamp.modulate = Color.WHITE if started or index < lit_count() else UNLIT
	var fade_start := green_time() + GREEN_HOLD
	modulate.a = 1.0 - clampf((elapsed - fade_start) / FADE_SECONDS, 0.0, 1.0)
	if elapsed >= fade_start + FADE_SECONDS:
		visible = false
