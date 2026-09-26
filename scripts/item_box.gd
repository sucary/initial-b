extends Area2D
class_name ItemBox

signal taken(state: int)

const TEXTURES := {
	-1: preload("res://assets/sprites/item-box-random.png"),
	PathEffects.State.ICE: preload("res://assets/sprites/item-box-ice.png"),
	PathEffects.State.MUD: preload("res://assets/sprites/item-box-mud.png"),
	PathEffects.State.LIGHTNING: preload("res://assets/sprites/item-box-lightning.png"),
}
const PULSE_SPEED := 4.0
const PULSE_SIZE := 0.07

var state := -1

var _sprite: Sprite2D
var _time := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 18.0
	shape.shape = circle
	add_child(shape)
	_sprite = Sprite2D.new()
	_sprite.texture = TEXTURES[state]
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_time = randf() * TAU
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	_sprite.scale = Vector2.ONE * (1.0 + PULSE_SIZE * sin(_time * PULSE_SPEED))


func _on_body_entered(body: Node2D) -> void:
	if body is PlayerKart:
		taken.emit(state)
		queue_free()
