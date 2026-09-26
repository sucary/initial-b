extends Control

const GAME_SCENE := "res://scenes/game.tscn"
const BLINK_SECONDS := 0.5

@onready var prompt_row: HBoxContainer = $Panel/PromptRow

var _time := 0.0
var _starting := false


func _process(delta: float) -> void:
	_time += delta
	prompt_row.visible = fmod(_time, BLINK_SECONDS * 2.0) < BLINK_SECONDS


func _unhandled_input(event: InputEvent) -> void:
	if _starting or event.is_echo():
		return
	if event.is_action_pressed("accelerate") or event.is_action_pressed("ui_accept"):
		_starting = true
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
