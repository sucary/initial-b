extends Node2D
class_name GameManager

const TOTAL_LAPS := 3
const PROGRESS_TOLERANCE := 96.0
const PATH_START_AFTER_FINISH := 52.0
const PATH_END_BEFORE_FINISH := 18.0
const SHADOW_FADE_SECONDS := 0.3
const TITLE_SCENE := "res://scenes/title.tscn"

@export_range(30.0, 600.0, 5.0) var race_time_limit_seconds := 120.0

@onready var track: RaceTrack = $Track
@onready var lap_path: LapPath = $PreviousLapPath
@onready var kart: PlayerKart = $Kart
@onready var kart_shadow: Sprite2D = $KartShadow
@onready var start_grid: StartGrid = $StartGrid
@onready var skid_marks: SkidMarks = $SkidMarks
@onready var course: CourseObjects = $Course
@onready var camera: RaceCamera = $Camera
@onready var lap_label: Label = $HUD/RacePanel/LapLabel
@onready var time_label: Label = $HUD/RacePanel/TimeLabel
@onready var speed_dashboard: SpeedDashboard = $HUD/SpeedDashboard
@onready var start_lights: StartLights = $HUD/StartLights
@onready var minimap: Minimap = $HUD/ResultPanel/Lines/Minimap
@onready var result_panel: ColorRect = $HUD/ResultPanel
@onready var finished_label: Label = $HUD/ResultPanel/Lines/FinishedLabel
@onready var time_up_label: Label = $HUD/ResultPanel/Lines/TimeUpLabel
@onready var finish_time_label: Label = $HUD/ResultPanel/Lines/FinishTimeLabel
@onready var _finish_time_template := finish_time_label.text

var completed_laps := 0
var time_left := 0.0
var _checkpoint_offsets := PackedFloat32Array()
var _next_checkpoint := 0
var _track_length := 0.0
var _previous_offset := 0.0
var _previous_local_position := Vector2.ZERO
var _race_over := false
var _path_recording_armed := false
var path_effects := PathEffects.new()
var audio: RaceAudio
var _lap_started_at := 0.0
var _racing := false
var _lap_routes: Array[PackedVector2Array] = []


func _ready() -> void:
	audio = RaceAudio.new()
	add_child(audio)
	start_grid.build(track)
	var pole := start_grid.slot_transform(0)
	kart.global_position = pole.origin
	kart.global_rotation = pole.get_rotation()
	camera.target = kart
	camera.snap_to_target()
	kart.set_physics_process(false)
	start_lights.go.connect(_on_go)
	start_lights.red_lit.connect(func(): audio.play("countdown"))
	kart.tyre_hit.connect(func(): audio.play_collision("tyre_hit"))
	kart.barrier_hit.connect(func(): audio.play_collision("barrier_hit"))
	kart.curb_hit.connect(func(): audio.play_collision("curb_hit"))
	path_effects.state_changed.connect(_on_state_changed)
	lap_path.begin_lap()
	lap_path.crossed.connect(_on_path_crossed)
	course.build(track, randi(), $TrackArt)
	minimap.setup(track)
	course.item_box_taken.connect(_on_item_box_taken)

	_checkpoint_offsets = track.get_checkpoint_offsets()
	_track_length = track.get_course_length()
	_previous_local_position = track.to_local(kart.global_position)
	_previous_offset = track.get_progress_offset(kart.global_position)
	time_left = race_time_limit_seconds
	result_panel.visible = false
	_update_shadow(0.0)
	_update_hud()


func _physics_process(delta: float) -> void:
	if _race_over or not _racing:
		return

	time_left = maxf(0.0, time_left - delta)
	if time_left <= 0.0:
		_end_race(false)
		return

	var local_position := track.to_local(kart.global_position)
	var current_offset := track.get_progress_offset(kart.global_position)
	var wrapped_forward := current_offset < _previous_offset - _track_length * 0.5
	var progress := current_offset - _previous_offset
	if progress > _track_length * 0.5:
		progress -= _track_length
	elif progress < -_track_length * 0.5:
		progress += _track_length

	var movement := local_position - _previous_local_position
	var forward := track.get_forward_at_offset(current_offset)
	if progress > 0.0 and progress <= movement.length() * 1.5 + PROGRESS_TOLERANCE and movement.dot(forward) > 0.0:
		var laps_before := completed_laps
		_check_gate_crossing(progress)
		if wrapped_forward:
			_path_recording_armed = true
			_lap_started_at = _elapsed()
			if completed_laps == laps_before:
				lap_path.begin_lap()

	var lap_time := _elapsed() - _lap_started_at
	if _path_recording_armed and current_offset >= PATH_START_AFTER_FINISH and current_offset <= _track_length - PATH_END_BEFORE_FINISH:
		lap_path.record_position(kart.global_position, lap_time)
	_update_shadow(lap_time)
	lap_path.update_contact(kart.global_transform, race_time_limit_seconds - time_left)
	if kart.skidding:
		var wheels := kart.rear_wheels()
		skid_marks.add_marks(wheels[0], wheels[1])
	else:
		skid_marks.end_stroke()
	audio.update_kart(kart.velocity.length(), kart.top_speed(), Input.get_action_strength("accelerate"), kart.skidding, kart.curb_rubbing, delta)
	path_effects.advance(delta, lap_path.is_following, lap_path.has_previous_path())
	kart.set_path_modifiers(path_effects.speed_scale(), path_effects.acceleration_scale(), path_effects.turn_scale())
	lap_path.set_appearance(path_effects.state, path_effects.is_active())

	_previous_offset = current_offset
	_previous_local_position = local_position
	_update_hud()


func _on_go() -> void:
	audio.play("go")
	audio.start_engine()
	_racing = true
	kart.set_physics_process(true)
	camera.follows_input = true


func _elapsed() -> float:
	return race_time_limit_seconds - time_left


func _update_shadow(lap_time: float) -> void:
	var start := lap_path.replay_start_time()
	var end := lap_path.replay_end_time()
	kart_shadow.visible = lap_time >= start and lap_time <= end
	if not kart_shadow.visible:
		return
	kart_shadow.global_transform = lap_path.replay_transform(lap_time)
	kart_shadow.modulate.a = clampf(minf(lap_time - start, end - lap_time) / SHADOW_FADE_SECONDS, 0.0, 1.0)


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
	audio.play("finish_line")
	var recorded_route := lap_path.world_recording().size() >= 2
	lap_path.complete_lap()
	if recorded_route:
		_lap_routes.append(lap_path.world_route())
	course.respawn_item_boxes()
	_next_checkpoint = 0
	if completed_laps >= TOTAL_LAPS:
		_end_race(true)


func _end_race(won: bool) -> void:
	_race_over = true
	audio.stop_engine()
	if won:
		audio.play_win_after_finish()
	else:
		audio.play("time_up")
	kart.velocity = Vector2.ZERO
	kart.set_physics_process(false)
	camera.follows_input = false
	result_panel.visible = true
	finished_label.visible = won
	time_up_label.visible = not won
	finish_time_label.visible = won
	finish_time_label.text = _finish_time_template.replace("{time}", _format_time(time_left))
	var routes := _lap_routes.duplicate()
	var unfinished := lap_path.world_recording()
	if not won and unfinished.size() >= 2:
		routes.append(unfinished)
	minimap.show_routes(routes)
	_update_hud()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		get_tree().call_deferred("reload_current_scene")
	elif _race_over and event.is_action_pressed("brake") and not event.is_echo():
		get_tree().change_scene_to_file.call_deferred(TITLE_SCENE)


func _update_hud() -> void:
	lap_label.text = "LAP %d / %d" % [mini(completed_laps + 1, TOTAL_LAPS), TOTAL_LAPS]
	time_label.text = "TIME %s" % _format_time(time_left)
	speed_dashboard.show_state(kart.velocity.length(), path_effects.effect_crossings, path_effects.window_left / PathEffects.BRAID_WINDOW_SECONDS, path_effects.is_maxed(), lap_path.state_color(path_effects.state))


func _on_path_crossed(_total_crossings: int) -> void:
	path_effects.register_crossing()
	var crossing_pitch := minf(1.0 + path_effects.effect_crossings * 0.06, 1.55)
	if path_effects.state == PathEffects.State.MUD:
		crossing_pitch = maxf(1.0 - (path_effects.effect_crossings - 1) * 0.05, 0.55)
	audio.play("crossing", crossing_pitch)


func _on_item_box_taken(state: int) -> void:
	audio.play("pickup")
	path_effects.pick_up_item_box(state)


func _on_state_changed(_state: int, source: int) -> void:
	if source == PathEffects.Source.BRAID:
		audio.play("state_change")
	elif source == PathEffects.Source.TIMER:
		audio.play("state_change", 1.0, -7.0)


func _format_time(seconds: float) -> String:
	var total_seconds := ceili(maxf(seconds, 0.0))
	return "%02d:%02d" % [total_seconds / 60, total_seconds % 60]
