extends Camera2D

var target: Node2D


func _ready() -> void:
	ignore_rotation = false
	zoom = Vector2(1.5, 1.5)


func snap_to_target() -> void:
	if target == null:
		return
	global_position = target.global_position
	global_rotation = target.global_rotation + PI * 0.5


func _process(delta: float) -> void:
	if target == null:
		return
	global_position = global_position.lerp(target.global_position, 1.0 - exp(-7.0 * delta))
	global_rotation = lerp_angle(global_rotation, target.global_rotation + PI * 0.5, 1.0 - exp(-5.0 * delta))
