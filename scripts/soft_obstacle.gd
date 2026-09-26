extends RigidBody2D
class_name SoftObstacle

const PUSH_STRENGTH := 0.9
const CONTACT_RADIUS := 22.0


func _ready() -> void:
	gravity_scale = 0.0
	linear_damp = 3.5
	angular_damp = 4.0
	mass = 2.0
	collision_layer = 4
	collision_mask = 1 | 4
	var contact := Area2D.new()
	contact.collision_layer = 0
	contact.collision_mask = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = CONTACT_RADIUS
	shape.shape = circle
	contact.add_child(shape)
	add_child(contact)
	contact.body_entered.connect(_on_contact)


func _on_contact(body: Node2D) -> void:
	if body is PlayerKart:
		var kart := body as PlayerKart
		var away := (global_position - kart.global_position).normalized()
		apply_central_impulse((kart.velocity + away * kart.velocity.length() * 0.5) * mass * PUSH_STRENGTH)
		kart.hit_soft_obstacle()
