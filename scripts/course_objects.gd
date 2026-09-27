extends Node2D
class_name CourseObjects

signal item_box_taken(state: int)

const TYRE_TEXTURE: Texture2D = preload("res://assets/sprites/tyre-stack.png")
const BARRIER_TEXTURE: Texture2D = preload("res://assets/sprites/traffic-barrier.png")
const ROAD_COLOR := Color8(0x44, 0x49, 0x4b)
const ROAD_COLOR_TOLERANCE := 0.06

var layout: CourseLayout

var _obstacle_root: Node2D
var _box_root: Node2D
var _art: Sprite2D
var _art_image: Image


func build(track: RaceTrack, seed_value: int, art: Sprite2D = null) -> void:
	_art = art
	layout = CourseLayout.new(track, seed_value)
	layout.generate_obstacles()
	_obstacle_root = Node2D.new()
	_box_root = Node2D.new()
	add_child(_obstacle_root)
	add_child(_box_root)
	for obstacle in layout.obstacles:
		_obstacle_root.add_child(_hard_obstacle(obstacle) if obstacle.hard else _soft_obstacle(obstacle))


func respawn_item_boxes() -> void:
	for box in _box_root.get_children():
		box.queue_free()
	for data in layout.generate_item_boxes():
		var box := ItemBox.new()
		box.state = data.state
		box.position = data.position
		box.rotation = data.rotation
		box.taken.connect(item_box_taken.emit)
		_box_root.add_child(box)


func item_boxes() -> Array[Node]:
	return _box_root.get_children().filter(func(box): return not box.is_queued_for_deletion())


func obstacle_nodes() -> Array[Node]:
	return _obstacle_root.get_children()


func is_drawn_road(world_position: Vector2) -> bool:
	if _art_image == null:
		_art_image = _art.texture.get_image()
	var pixel := Vector2i((_art.to_local(world_position) - _art.offset).floor())
	if not Rect2i(Vector2i.ZERO, _art_image.get_size()).has_point(pixel):
		return false
	var color := _art_image.get_pixelv(pixel)
	return color.a > 0.9 and absf(color.r - ROAD_COLOR.r) < ROAD_COLOR_TOLERANCE and absf(color.g - ROAD_COLOR.g) < ROAD_COLOR_TOLERANCE and absf(color.b - ROAD_COLOR.b) < ROAD_COLOR_TOLERANCE


func _hard_obstacle(data: Dictionary) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group(PlayerKart.HARD_OBSTACLE_GROUP)
	body.position = data.position
	body.rotation = data.rotation
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(34, 18)
	shape.shape = rectangle
	body.add_child(shape)
	body.add_child(_sprite(BARRIER_TEXTURE))
	return body


func _soft_obstacle(data: Dictionary) -> SoftObstacle:
	var body := SoftObstacle.new()
	body.position = data.position
	body.rotation = data.rotation
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0
	shape.shape = circle
	body.add_child(shape)
	body.add_child(_sprite(TYRE_TEXTURE))
	return body


func _sprite(texture: Texture2D) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return sprite
