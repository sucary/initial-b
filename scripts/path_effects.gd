extends RefCounted
class_name PathEffects

signal state_changed(state: State, source: Source)

enum State { ICE, MUD, LIGHTNING }
enum Source { ITEM_BOX, BRAID, TIMER }

const BRAID_WINDOW_SECONDS := 2.5
const STATE_TIMER_SECONDS := 10.0
const CROSSING_MULTIPLIER_STEP := 0.5
const MAX_EFFECT_MULTIPLIER := 3.0
const FOLLOW_DECAY_PER_SECOND := 4.0
const STATE_BLEND_SECONDS := 0.3
const MUD_SLOW_ONSET_PER_SECOND := 2.0
const MUD_RECOVERY_PER_SECOND := 0.35
const BRAID_BOOST_STEP := 0.1
const MAX_BRAID_BOOST := 1.4
const BRAID_THRESHOLD_MIN := 5
const BRAID_THRESHOLD_MAX := 7
const ICE_TURN_PER_MULTIPLIER := 0.3
const MUD_SPEED_PER_MULTIPLIER := 0.18
const MUD_TURN_PER_MULTIPLIER := 0.2
const MUD_MIN_SCALE := 0.4
const LIGHTNING_ACCELERATION_PER_MULTIPLIER := 0.5
const LIGHTNING_SPEED_PER_MULTIPLIER := 0.06

var state: State = State.ICE
var effect_crossings := 0
var braid_crossings := 0
var braid_threshold := BRAID_THRESHOLD_MIN
var window_left := 0.0
var state_timer := 0.0
var following := false
var decaying_multiplier := 1.0
var blend_left := 0.0
var mud_slow := 1.0

var _rng := RandomNumberGenerator.new()
var _item_box_pending := false
var _item_box_state := -1
var _blend_from := Vector3.ONE


func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	braid_threshold = _roll_braid_threshold()


func register_crossing() -> void:
	var braiding := window_left > 0.0
	if not braiding:
		effect_crossings = 0
		braid_crossings = 0
	effect_crossings += 1
	window_left = BRAID_WINDOW_SECONDS
	if braiding:
		braid_crossings += 1


func pick_up_item_box(box_state: int = -1) -> void:
	_item_box_pending = true
	_item_box_state = box_state


func advance(delta: float, is_following: bool, timer_running: bool = true) -> void:
	following = is_following
	blend_left = maxf(blend_left - delta, 0.0)
	decaying_multiplier = move_toward(decaying_multiplier, 1.0, FOLLOW_DECAY_PER_SECOND * delta)
	if window_left > 0.0:
		window_left = maxf(window_left - delta, 0.0)
		if window_left == 0.0:
			if following:
				decaying_multiplier = maxf(decaying_multiplier, _crossing_multiplier())
			effect_crossings = 0
			braid_crossings = 0
	if not following and window_left == 0.0:
		decaying_multiplier = 1.0
	if timer_running:
		state_timer += delta

	if _item_box_pending:
		_item_box_pending = false
		braid_crossings = 0
		_change_state(_item_box_state if _item_box_state >= 0 else _random_other_state(), Source.ITEM_BOX)
	elif braid_crossings >= braid_threshold:
		braid_crossings = 0
		braid_threshold = _roll_braid_threshold()
		_change_state(_random_other_state(), Source.BRAID)
	elif state_timer >= STATE_TIMER_SECONDS:
		_change_state(_random_other_state(), Source.TIMER)

	var mud_target := _mud_speed(effect_multiplier()) if state == State.MUD else 1.0
	var mud_rate := MUD_SLOW_ONSET_PER_SECOND if mud_target < mud_slow else MUD_RECOVERY_PER_SECOND
	mud_slow = move_toward(mud_slow, mud_target, mud_rate * delta)


func is_active() -> bool:
	return effect_multiplier() > 0.0


func is_braiding() -> bool:
	return window_left > 0.0 and effect_crossings >= 2


func effect_multiplier() -> float:
	if window_left > 0.0:
		return maxf(_crossing_multiplier(), decaying_multiplier)
	return decaying_multiplier if following else 0.0


func _crossing_multiplier() -> float:
	return minf(1.0 + CROSSING_MULTIPLIER_STEP * effect_crossings, MAX_EFFECT_MULTIPLIER)


func is_maxed() -> bool:
	return window_left > 0.0 and _crossing_multiplier() >= MAX_EFFECT_MULTIPLIER and braid_boost() >= MAX_BRAID_BOOST


func braid_boost() -> float:
	if not is_braiding():
		return 1.0
	return minf(1.0 + BRAID_BOOST_STEP * (effect_crossings - 1), MAX_BRAID_BOOST)


func speed_scale() -> float:
	return _blended_scales().x * mud_slow * braid_boost()


func acceleration_scale() -> float:
	return _blended_scales().y * braid_boost()


func turn_scale() -> float:
	return _blended_scales().z


func _blended_scales() -> Vector3:
	var target := _state_scales(state, effect_multiplier())
	if blend_left <= 0.0:
		return target
	return _blend_from.lerp(target, 1.0 - blend_left / STATE_BLEND_SECONDS)


func _state_scales(for_state: State, multiplier: float) -> Vector3:
	match for_state:
		State.ICE:
			return Vector3(1.0, 1.0, 1.0 + ICE_TURN_PER_MULTIPLIER * multiplier)
		State.MUD:
			return Vector3(1.0, 1.0, maxf(1.0 - MUD_TURN_PER_MULTIPLIER * multiplier, MUD_MIN_SCALE))
		State.LIGHTNING:
			var lightning_speed := 1.0 + LIGHTNING_SPEED_PER_MULTIPLIER * multiplier
			var lightning_acceleration := 1.0 + LIGHTNING_ACCELERATION_PER_MULTIPLIER * multiplier
			return Vector3(lightning_speed, lightning_acceleration, 1.0)
	return Vector3.ONE


func _mud_speed(multiplier: float) -> float:
	return maxf(1.0 - MUD_SPEED_PER_MULTIPLIER * multiplier, MUD_MIN_SCALE)


func _change_state(new_state: int, source: Source) -> void:
	_blend_from = _blended_scales()
	blend_left = STATE_BLEND_SECONDS
	state = new_state as State
	state_timer = 0.0
	if source != Source.ITEM_BOX:
		effect_crossings = 0
		braid_crossings = 0
		window_left = 0.0
		decaying_multiplier = 1.0
	state_changed.emit(state, source)


func _random_other_state() -> int:
	return (state + _rng.randi_range(1, State.size() - 1)) % State.size()


func _roll_braid_threshold() -> int:
	return _rng.randi_range(BRAID_THRESHOLD_MIN, BRAID_THRESHOLD_MAX)
