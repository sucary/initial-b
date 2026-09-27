extends Node
class_name RaceAudio

const CLIPS := {
	"countdown": preload("res://assets/audio/countdown.wav"),
	"go": preload("res://assets/audio/go.wav"),
	"pickup": preload("res://assets/audio/pickup.wav"),
	"crossing": preload("res://assets/audio/crossing.wav"),
	"state_change": preload("res://assets/audio/state_change.wav"),
	"finish_line": preload("res://assets/audio/finish_line.wav"),
	"result_win": preload("res://assets/audio/result_win.wav"),
	"tyre_hit": preload("res://assets/audio/tyre_hit.wav"),
	"barrier_hit": preload("res://assets/audio/barrier_hit.wav"),
	"curb_hit": preload("res://assets/audio/curb_hit.wav"),
	"time_up": preload("res://assets/audio/time_up.wav"),
	"engine": preload("res://assets/audio/engine_loop.wav"),
	"skid": preload("res://assets/audio/skid_loop.wav"),
	"curb_rub": preload("res://assets/audio/curb_rub_loop.wav"),
}

const VOLUME_DB := {
	"countdown": -18.0,
	"go": -19.0,
	"pickup": -17.0,
	"crossing": -11.0,
	"state_change": -11.0,
	"finish_line": -5.0,
	"result_win": -6.0,
	"tyre_hit": -5.0,
	"barrier_hit": -9.0,
	"curb_hit": -18.0,
	"time_up": -6.0,
	"engine": -24.0,
	"skid": -12.0,
	"curb_rub": -24.0,
}

var _players: Dictionary = {}
var _running := false
var _last_collision_ms: Dictionary = {}
var _curb_rub_hold := 0.0
var _engine_speed := 0.0
var _last_speed := 0.0
var _default_rev := 0.0
var _choke_phase := 0.0
var _skid_mix := 0.0


func _ready() -> void:
	for name in CLIPS:
		var player := AudioStreamPlayer.new()
		player.stream = CLIPS[name]
		player.bus = "Master"
		player.volume_db = VOLUME_DB[name]
		if name == "engine" or name == "skid" or name == "curb_rub":
			var loop_stream := player.stream as AudioStreamWAV
			loop_stream.loop_begin = 0
			loop_stream.loop_end = roundi(loop_stream.get_length() * loop_stream.mix_rate)
			loop_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		add_child(player)
		_players[name] = player


func play(name: String, pitch: float = 1.0, volume_offset_db: float = 0.0) -> void:
	var player: AudioStreamPlayer = _players[name]
	player.pitch_scale = pitch
	player.volume_db = VOLUME_DB[name] + volume_offset_db
	player.play()


func play_win_after_finish() -> void:
	var finish: AudioStreamPlayer = _players["finish_line"]
	finish.finished.connect(func(): play("result_win"), CONNECT_ONE_SHOT)


func start_engine() -> void:
	_running = true
	_engine_speed = 0.0
	_last_speed = 0.0
	_default_rev = 0.0
	_choke_phase = 0.0
	var engine: AudioStreamPlayer = _players["engine"]
	engine.pitch_scale = 0.72
	engine.volume_db = -24.0
	engine.play()


func update_kart(speed: float, max_speed: float, throttle: float, skidding: bool, curb_rubbing: bool, delta: float) -> void:
	if not _running:
		return
	var speed_drop_rate := maxf((_last_speed - speed) / maxf(delta, 0.0001), 0.0)
	_last_speed = speed
	_engine_speed = lerpf(_engine_speed, speed, 1.0 - exp(-7.0 * delta))
	if speed > PlayerKart.TOP_SPEED:
		_default_rev = 1.0
	else:
		_default_rev = move_toward(_default_rev, clampf(throttle, 0.0, 1.0), delta / 1.5)
		if speed_drop_rate > PlayerKart.COAST_FORCE + 100.0:
			var drop_strength := clampf((speed_drop_rate - 260.0) / 1800.0, 0.0, 1.0)
			var speed_rev := clampf(speed / PlayerKart.TOP_SPEED, 0.0, 1.0)
			var quick_rev := lerpf(_default_rev, speed_rev, 1.0 - exp(-delta * lerpf(6.0, 32.0, drop_strength)))
			_default_rev = minf(_default_rev, quick_rev)
	var normal_fraction := clampf(_engine_speed / PlayerKart.TOP_SPEED, 0.0, 1.0)
	var effect_fraction := clampf((_engine_speed - PlayerKart.TOP_SPEED) / (PlayerKart.MAX_SPEED - PlayerKart.TOP_SPEED), 0.0, 1.0)
	var boosted := max_speed > PlayerKart.TOP_SPEED + 1.0
	var boost_release := clampf((_engine_speed - PlayerKart.TOP_SPEED) / 140.0, 0.0, 1.0) if boosted else 0.0
	var choke := clampf((_default_rev - 0.86) / 0.14, 0.0, 1.0) * (1.0 - boost_release)
	_choke_phase = fposmod(_choke_phase + delta * 10.0, 1.0)
	var limiter_wave := 0.5 + 0.5 * sin(TAU * _choke_phase)
	var engine: AudioStreamPlayer = _players["engine"]
	var target_pitch := lerpf(0.72, 1.42, _default_rev) + 0.53 * effect_fraction
	engine.pitch_scale = target_pitch * (1.0 - 0.075 * choke * limiter_wave)
	var target_volume := lerpf(-24.0, -9.0, _default_rev) + 2.5 * effect_fraction - 3.0 * choke * limiter_wave
	engine.volume_db = lerpf(engine.volume_db, target_volume, 1.0 - exp(-9.0 * delta))
	_skid_mix = move_toward(_skid_mix, 1.0 if skidding else 0.0, delta * (16.0 if skidding else 8.0))
	var skid: AudioStreamPlayer = _players["skid"]
	if _skid_mix > 0.0 and not skid.playing:
		skid.play()
	elif _skid_mix == 0.0 and skid.playing:
		skid.stop()
	if _skid_mix > 0.0:
		var drift_speed := clampf(speed / PlayerKart.MAX_SPEED, 0.0, 1.0)
		skid.pitch_scale = lerpf(0.86, 1.24, drift_speed)
		skid.volume_db = lerpf(-35.0, lerpf(-12.0, -4.0, normal_fraction), _skid_mix)
	_curb_rub_hold = 0.1 if curb_rubbing else maxf(0.0, _curb_rub_hold - delta)
	var rub: AudioStreamPlayer = _players["curb_rub"]
	if _curb_rub_hold > 0.0 and not rub.playing:
		rub.play()
	elif _curb_rub_hold == 0.0 and rub.playing:
		rub.stop()
	if _curb_rub_hold > 0.0:
		var speed_fraction := clampf(speed / 600.0, 0.0, 1.0)
		var contact_fraction := clampf(_curb_rub_hold / 0.1, 0.0, 1.0)
		rub.volume_db = lerpf(-50.0, lerpf(-24.0, -12.0, speed_fraction), contact_fraction)
		rub.pitch_scale = lerpf(0.85, 1.25, speed_fraction)


func play_collision(name: String) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last_collision_ms.get(name, -1000)) < 180:
		return
	_last_collision_ms[name] = now
	play(name)


func stop_engine() -> void:
	_running = false
	_curb_rub_hold = 0.0
	_skid_mix = 0.0
	(_players["engine"] as AudioStreamPlayer).stop()
	(_players["skid"] as AudioStreamPlayer).stop()
	(_players["curb_rub"] as AudioStreamPlayer).stop()
