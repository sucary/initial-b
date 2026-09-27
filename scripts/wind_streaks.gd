extends Node2D
class_name WindStreaks

const NOSE_OFFSET := 30.0
const NOSE_HALF_WIDTH := 8.0
const SPLAY := 0.38
const AMOUNT := 10
const LIFETIME := 0.24
const SPEED_MIN := 800.0
const SPEED_MAX := 1200.0
const STREAK_LENGTH := 14
const STREAK_WIDTH := 4
const FAINTEST := 0.04

var intensity := 0.0

var _emitters: Array[CPUParticles2D] = []


func _ready() -> void:
	var texture := ImageTexture.create_from_image(_wedge())
	for side in [-1.0, 1.0]:
		var emitter := CPUParticles2D.new()
		emitter.emitting = false
		emitter.amount = AMOUNT
		emitter.lifetime = LIFETIME
		emitter.texture = texture
		emitter.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		emitter.position = Vector2(NOSE_OFFSET, NOSE_HALF_WIDTH * side)
		emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		emitter.emission_rect_extents = Vector2(4.0, 3.0)
		emitter.direction = Vector2(-1.0, SPLAY * side).normalized()
		emitter.spread = 4.0
		emitter.gravity = Vector2.ZERO
		emitter.initial_velocity_min = SPEED_MIN
		emitter.initial_velocity_max = SPEED_MAX
		emitter.particle_flag_align_y = true
		var fade := Gradient.new()
		fade.set_color(0, Color(1, 1, 1, 0))
		fade.add_point(0.25, Color(1, 1, 1, 0.85))
		fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
		emitter.color_ramp = fade
		add_child(emitter)
		_emitters.append(emitter)


func _wedge() -> Image:
	var image := Image.create(STREAK_WIDTH, STREAK_LENGTH, false, Image.FORMAT_RGBA8)
	for y in range(STREAK_LENGTH):
		var along := float(y) / (STREAK_LENGTH - 1)
		var half_width := lerpf(0.5, STREAK_WIDTH * 0.5, along)
		for x in range(STREAK_WIDTH):
			if absf(x + 0.5 - STREAK_WIDTH * 0.5) <= half_width:
				image.set_pixel(x, y, Color(1, 1, 1, lerpf(0.4, 1.0, along)))
	return image


func _process(_delta: float) -> void:
	var kart := get_parent() as CharacterBody2D
	if kart == null:
		return
	var overspeed := kart.velocity.length() - PlayerKart.TOP_SPEED
	intensity = clampf(overspeed / (PlayerKart.MAX_SPEED - PlayerKart.TOP_SPEED), 0.0, 1.0)
	var strength := intensity * intensity
	modulate.a = lerpf(FAINTEST, 1.0, strength)
	for emitter in _emitters:
		emitter.emitting = overspeed > 1.0
		emitter.initial_velocity_min = SPEED_MIN * lerpf(0.6, 1.0, strength)
		emitter.initial_velocity_max = SPEED_MAX * lerpf(0.6, 1.0, strength)


func emitting() -> bool:
	return _emitters.any(func(emitter: CPUParticles2D) -> bool: return emitter.emitting)


func spray_directions() -> Array[Vector2]:
	var directions: Array[Vector2] = []
	for emitter in _emitters:
		directions.append(emitter.direction)
	return directions
