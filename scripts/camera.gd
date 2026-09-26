extends Camera2D

const ACCELERATE_LOOK_AHEAD := 150.0
const BRAKE_LOOK_BEHIND := 90.0
const LOOK_RESPONSE := 2.0

var target: Node2D
var _look_distance := 0.0


func _ready() -> void:
	ignore_rotation = false
	zoom = Vector2(1.3, 1.3)


func snap_to_target() -> void:
	if target == null:
		return
	_look_distance = 0.0
	global_position = target.global_position
	global_rotation = target.global_rotation + PI * 0.5


func _process(delta: float) -> void:
	if target == null:
		return
	var forward := Vector2.RIGHT.rotated(target.global_rotation)
	var desired_look_distance := Input.get_action_strength("accelerate") * ACCELERATE_LOOK_AHEAD - Input.get_action_strength("brake") * BRAKE_LOOK_BEHIND
	_look_distance = lerpf(_look_distance, desired_look_distance, 1.0 - exp(-LOOK_RESPONSE * delta))
	var desired_position := target.global_position + forward * _look_distance
	global_position = global_position.lerp(desired_position, 1.0 - exp(-7.0 * delta))
	global_rotation = lerp_angle(global_rotation, target.global_rotation + PI * 0.5, 1.0 - exp(-5.0 * delta))
