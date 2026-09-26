extends CharacterBody2D
class_name PlayerKart

const TOP_SPEED := 590.0
const FORWARD_ACCELERATION := 760.0
const REVERSE_ACCELERATION := 310.0
const BRAKE_FORCE := 1300.0
const COAST_FORCE := 160.0
const NORMAL_GRIP := 8.0
const DRIFT_GRIP := 1.8
const NORMAL_TURN_RATE := 2.6
const DRIFT_TURN_RATE := 3.5


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1


func _physics_process(delta: float) -> void:
	var forward := Vector2.RIGHT.rotated(rotation)
	var longitudinal_speed := velocity.dot(forward)
	var throttle := Input.get_action_strength("accelerate")
	var brake := Input.get_action_strength("brake")
	var drifting := Input.is_action_pressed("handbrake")

	if throttle > 0.0:
		velocity += forward * FORWARD_ACCELERATION * throttle * delta
	if brake > 0.0:
		if longitudinal_speed > 25.0:
			velocity = velocity.move_toward(Vector2.ZERO, BRAKE_FORCE * brake * delta)
		else:
			velocity -= forward * REVERSE_ACCELERATION * brake * delta
	if throttle == 0.0 and brake == 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, COAST_FORCE * delta)

	var steer := Input.get_axis("steer_left", "steer_right")
	var speed_factor := clampf(absf(longitudinal_speed) / 180.0, 0.0, 1.0)
	if absf(longitudinal_speed) > 8.0:
		var turn_rate := DRIFT_TURN_RATE if drifting else NORMAL_TURN_RATE
		rotation += steer * turn_rate * speed_factor * signf(longitudinal_speed) * delta

	forward = Vector2.RIGHT.rotated(rotation)
	var sideways := forward.orthogonal()
	var grip := DRIFT_GRIP if drifting else NORMAL_GRIP
	velocity -= sideways * velocity.dot(sideways) * minf(grip * delta, 1.0)
	velocity = velocity.limit_length(TOP_SPEED)
	move_and_slide()
