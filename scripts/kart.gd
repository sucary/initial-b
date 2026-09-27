extends CharacterBody2D
class_name PlayerKart

signal tyre_hit
signal barrier_hit
signal curb_hit

const TOP_SPEED := 600.0
const FORWARD_ACCELERATION := 760.0
const REVERSE_ACCELERATION := 310.0
const REVERSE_RECOVERY_ACCELERATION := 900.0
const BRAKE_FORCE := 1300.0
const COAST_FORCE := 160.0
const NORMAL_GRIP := 8.0
const DRIFT_GRIP := 1.8
const NORMAL_TURN_RATE := 2.6
const DRIFT_TURN_RATE := 3.5
const HANDBRAKE_DRAG := 0.8
const HANDBRAKE_THROTTLE := 0.5
const SKID_MIN_SPEED := 60.0
const SKID_MIN_SLIP := 30.0
const REAR_WHEEL_OFFSET := Vector2(-13, 12)
const MAX_SPEED := 1000.0
const OVERSPEED_DRAG := 520.0
const BOUNCE := 0.35
const HARD_OBSTACLE_BOUNCE := 0.15
const HARD_OBSTACLE_GROUP := "hard_obstacle"
const BOUNCE_MIN_FACING := 0.5
const SIDE_SCRAPE_DRAG := 2.0
const FULL_STEER_SPEED := 180.0
const HIGH_SPEED_TURN_MIN := 0.45
const TURN_ACCELERATION_PENALTY := 1.0
const MAX_ACCELERATION_SCALE := 1.6
const OVERSPEED_ACCELERATION := 0.4
const SOFT_HIT_SPEED_KEPT := 0.55
const SOFT_HIT_COOLDOWN := 0.35

var skidding := false
var curb_rubbing := false
var speed_scale := 1.0
var acceleration_scale := 1.0
var turn_scale := 1.0

var _soft_hit_cooldown := 0.0
var _barrier_touching := false


func hit_soft_obstacle() -> void:
	if _soft_hit_cooldown > 0.0:
		return
	velocity *= SOFT_HIT_SPEED_KEPT
	_soft_hit_cooldown = SOFT_HIT_COOLDOWN
	tyre_hit.emit()


func set_path_modifiers(new_speed_scale: float, new_acceleration_scale: float, new_turn_scale: float) -> void:
	speed_scale = new_speed_scale
	acceleration_scale = new_acceleration_scale
	turn_scale = new_turn_scale


func steering_response(speed: float) -> float:
	var low_speed := clampf(speed / FULL_STEER_SPEED, 0.0, 1.0)
	var high_speed := clampf((speed - FULL_STEER_SPEED) / (MAX_SPEED - FULL_STEER_SPEED), 0.0, 1.0)
	return low_speed * lerpf(1.0, HIGH_SPEED_TURN_MIN, high_speed)


func turning_acceleration(turn_speed: float, speed: float) -> float:
	var speed_ratio := minf(speed / TOP_SPEED, 1.0)
	var sharpness := absf(turn_speed) / NORMAL_TURN_RATE
	return clampf(1.0 - TURN_ACCELERATION_PENALTY * sharpness * speed_ratio * speed_ratio, 0.0, 1.0)


func rear_wheels() -> PackedVector2Array:
	return PackedVector2Array([to_global(REAR_WHEEL_OFFSET), to_global(REAR_WHEEL_OFFSET * Vector2(1, -1))])


func top_speed() -> float:
	return minf(TOP_SPEED * speed_scale, MAX_SPEED)


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1
	if has_node("KartSprite") and has_node("CollisionShape2D"):
		_fit_collision_to_sprite($KartSprite, $CollisionShape2D)


func _fit_collision_to_sprite(sprite: Sprite2D, collision: CollisionShape2D) -> void:
	var image := sprite.texture.get_image()
	var origin := sprite.position - image.get_size() * 0.5 if sprite.centered else sprite.position
	var outline := PackedVector2Array()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0:
				for corner in [Vector2(x, y), Vector2(x + 1, y), Vector2(x, y + 1), Vector2(x + 1, y + 1)]:
					outline.append(origin + corner)
	var hull := Geometry2D.convex_hull(outline)
	hull.remove_at(hull.size() - 1)
	var shape := ConvexPolygonShape2D.new()
	shape.points = hull
	collision.shape = shape


func _physics_process(delta: float) -> void:
	_soft_hit_cooldown = maxf(_soft_hit_cooldown - delta, 0.0)
	var was_touching_barrier := _barrier_touching
	_barrier_touching = false
	curb_rubbing = false
	var starting_speed := velocity.length()
	var forward := Vector2.RIGHT.rotated(rotation)
	var longitudinal_speed := velocity.dot(forward)
	var throttle := Input.get_action_strength("accelerate")
	var brake := Input.get_action_strength("brake")
	var drifting := Input.is_action_pressed("handbrake")
	var steer := Input.get_axis("steer_left", "steer_right")
	var turn_rate := DRIFT_TURN_RATE if drifting else NORMAL_TURN_RATE
	var turn_speed := steer * turn_rate * turn_scale * steering_response(absf(longitudinal_speed))

	if throttle > 0.0:
		var push := FORWARD_ACCELERATION * minf(acceleration_scale, MAX_ACCELERATION_SCALE) * turning_acceleration(turn_speed, velocity.length())
		if velocity.length() > TOP_SPEED:
			push *= OVERSPEED_ACCELERATION
		if longitudinal_speed < 0.0:
			push = maxf(push, REVERSE_RECOVERY_ACCELERATION)
		elif drifting:
			push *= HANDBRAKE_THROTTLE
		velocity += forward * push * throttle * delta
	if drifting:
		velocity *= maxf(1.0 - HANDBRAKE_DRAG * delta, 0.0)
	var slip := absf(velocity.dot(Vector2.RIGHT.rotated(rotation).orthogonal()))
	skidding = drifting and velocity.length() > SKID_MIN_SPEED and slip > SKID_MIN_SLIP
	if brake > 0.0:
		if longitudinal_speed > 25.0:
			velocity = velocity.move_toward(Vector2.ZERO, BRAKE_FORCE * brake * delta)
		else:
			velocity -= forward * REVERSE_ACCELERATION * brake * delta
	if throttle == 0.0 and brake == 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, COAST_FORCE * delta)

	if absf(longitudinal_speed) > 8.0:
		rotation += turn_speed * signf(longitudinal_speed) * delta

	forward = Vector2.RIGHT.rotated(rotation)
	var sideways := forward.orthogonal()
	var grip := DRIFT_GRIP if drifting else NORMAL_GRIP
	var gripped := velocity - sideways * velocity.dot(sideways) * minf(grip * delta, 1.0)
	if drifting or gripped.is_zero_approx():
		velocity = gripped
	else:
		velocity = gripped.normalized() * velocity.length()
	var allowed_speed := maxf(top_speed(), starting_speed - OVERSPEED_DRAG * delta)
	velocity = velocity.limit_length(minf(allowed_speed, MAX_SPEED))
	var moving_velocity := velocity
	move_and_slide()
	if get_slide_collision_count() == 0:
		return
	var collision := get_slide_collision(0)
	var normal := collision.get_normal()
	var heading := Vector2.RIGHT.rotated(rotation)
	var hit_barrier := collision.get_collider() is Node and (collision.get_collider() as Node).is_in_group(HARD_OBSTACLE_GROUP)
	if hit_barrier:
		_barrier_touching = true
	if absf(heading.dot(normal)) > BOUNCE_MIN_FACING and moving_velocity.dot(normal) < 0.0:
		velocity = moving_velocity.bounce(normal) * (HARD_OBSTACLE_BOUNCE if hit_barrier else BOUNCE)
		if moving_velocity.length() > 80.0:
			if hit_barrier:
				barrier_hit.emit()
			else:
				curb_hit.emit()
	else:
		velocity *= maxf(1.0 - SIDE_SCRAPE_DRAG * delta, 0.0)
		if hit_barrier:
			if not was_touching_barrier and moving_velocity.length() > 60.0:
				barrier_hit.emit()
		else:
			curb_rubbing = moving_velocity.length() > 45.0
