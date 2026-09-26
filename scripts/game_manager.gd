extends Node2D
class_name GameManager

const TOTAL_LAPS := 3
const PROGRESS_TOLERANCE := 8.0

@export_range(30.0, 600.0, 5.0) var race_time_limit_seconds := 180.0

@onready var track: RaceTrack = $Track
@onready var kart: PlayerKart = $Kart
@onready var camera: Camera2D = $Camera
@onready var lap_label: Label = $HUD/RacePanel/LapLabel
@onready var time_label: Label = $HUD/RacePanel/TimeLabel
@onready var result_panel: ColorRect = $HUD/ResultPanel
@onready var result_label: Label = $HUD/ResultPanel/ResultLabel

var completed_laps := 0
var time_left := 0.0
var _checkpoint_offsets := PackedFloat32Array()
var _next_checkpoint := 0
var _track_length := 0.0
var _previous_offset := 0.0
var _previous_local_position := Vector2.ZERO
var _race_over := false


func _ready() -> void:
	var start := track.get_start_transform()
	kart.global_position = track.to_global(start.origin)
	kart.global_rotation = track.global_rotation + start.get_rotation()
	camera.target = kart
	camera.snap_to_target()

	_checkpoint_offsets = track.get_checkpoint_offsets()
	_track_length = track.get_course_length()
	_previous_local_position = track.to_local(kart.global_position)
	_previous_offset = track.get_progress_offset(kart.global_position)
	time_left = race_time_limit_seconds
	result_panel.visible = false
	_update_hud()


func _physics_process(delta: float) -> void:
	if _race_over:
		return

	time_left = maxf(0.0, time_left - delta)
	if time_left <= 0.0:
		_end_race(false)
		return

	var local_position := track.to_local(kart.global_position)
	var current_offset := track.get_progress_offset(kart.global_position)
	var progress := current_offset - _previous_offset
	if progress > _track_length * 0.5:
		progress -= _track_length
	elif progress < -_track_length * 0.5:
		progress += _track_length

	var movement := local_position - _previous_local_position
	var forward := track.get_forward_at_offset(current_offset)
	if progress > 0.0 and progress <= movement.length() * 1.5 + PROGRESS_TOLERANCE and movement.dot(forward) > 0.0:
		_check_gate_crossing(progress)

	_previous_offset = current_offset
	_previous_local_position = local_position
	_update_hud()


func _check_gate_crossing(progress: float) -> void:
	var gate_offset := 0.0
	if _next_checkpoint < _checkpoint_offsets.size():
		gate_offset = _checkpoint_offsets[_next_checkpoint]
	var distance_to_gate := fposmod(gate_offset - _previous_offset, _track_length)
	if distance_to_gate <= 0.0001 or distance_to_gate > progress:
		return

	if _next_checkpoint < _checkpoint_offsets.size():
		_next_checkpoint += 1
		return

	completed_laps += 1
	_next_checkpoint = 0
	if completed_laps >= TOTAL_LAPS:
		_end_race(true)


func _end_race(won: bool) -> void:
	_race_over = true
	kart.velocity = Vector2.ZERO
	kart.set_physics_process(false)
	result_panel.visible = true
	if won:
		var elapsed := race_time_limit_seconds - time_left
		result_label.text = "FINISHED!\nTIME %s\nPRESS R TO RESTART" % _format_time(elapsed)
	else:
		result_label.text = "TIME UP!\nPRESS R TO RESTART"
	_update_hud()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		get_tree().call_deferred("reload_current_scene")


func _update_hud() -> void:
	lap_label.text = "LAP %d / %d" % [mini(completed_laps + 1, TOTAL_LAPS), TOTAL_LAPS]
	time_label.text = "TIME %s" % _format_time(time_left)


func _format_time(seconds: float) -> String:
	var total_seconds := ceili(maxf(seconds, 0.0))
	return "%02d:%02d" % [total_seconds / 60, total_seconds % 60]
