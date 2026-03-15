extends RefCounted

class_name ProceduralMusic

const _MUSIC_SAMPLE_RATE: float = 44100.0
const _MUSIC_STEPS_PER_CHORD: int = 8
const _MUSIC_PROGRESS_ROOTS: Array[float] = [82.41, 69.30, 51.91, 55.00] # E, C#, G#, A
const _MUSIC_MELODY_BY_CHORD: Array[Array] = [
	[329.63, 369.99, 415.30, 493.88, 415.30, 369.99, 329.63, 369.99], # E
	[277.18, 329.63, 369.99, 415.30, 369.99, 329.63, 277.18, 329.63], # C#m
	[415.30, 369.99, 329.63, 369.99, 415.30, 493.88, 415.30, 369.99], # G#m
	[440.00, 415.30, 369.99, 329.63, 369.99, 415.30, 440.00, 369.99], # A
]
const _MUSIC_CHORD_TONES: Array[Array] = [
	[329.63, 415.30, 493.88], # E
	[277.18, 329.63, 415.30], # C#m
	[415.30, 493.88, 622.25], # G#m
	[440.00, 554.37, 659.25], # A
]

var _player: AudioStreamPlayer = null
var _playback: AudioStreamGeneratorPlayback = null
var _phase: float = 0.0
var _bass_phase: float = 0.0
var _time: float = 0.0
var _step_seconds: float = 0.30
var _volume_db: float = -16.0
var _lead_square_amp: float = 0.040
var _lead_secondary_amp: float = 0.026
var _lead_secondary_mul: float = 0.5
var _lead_secondary_square: bool = false
var _bass_amp: float = 0.018
var _pad_amp: float = 0.026
var _gate_start: float = 0.94
var _gate_falloff: float = 0.10

func configure_preset(preset_name: String) -> void:
	match preset_name:
		"arena":
			_step_seconds = 0.26
			_volume_db = -17.0
			_lead_square_amp = 0.042
			_lead_secondary_amp = 0.028
			_lead_secondary_mul = 2.0
			_lead_secondary_square = false
			_bass_amp = 0.022
			_pad_amp = 0.030
			_gate_start = 0.92
			_gate_falloff = 0.12
		_:
			_step_seconds = 0.34
			_volume_db = -16.0
			_lead_square_amp = 0.040
			_lead_secondary_amp = 0.026
			_lead_secondary_mul = 0.5
			_lead_secondary_square = false
			_bass_amp = 0.018
			_pad_amp = 0.026
			_gate_start = 0.94
			_gate_falloff = 0.10

func setup(player: AudioStreamPlayer, enabled: bool) -> void:
	_player = player
	if _player == null:
		return
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = int(_MUSIC_SAMPLE_RATE)
	stream.buffer_length = 0.25
	_player.stream = stream
	_player.volume_db = _volume_db
	if enabled:
		_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback

func set_enabled(enabled: bool) -> void:
	if _player == null:
		return
	if enabled:
		if not _player.playing:
			_player.play()
		if _playback == null:
			_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	else:
		_player.stop()
		_playback = null

func stream_frames(music_state_source: Object) -> void:
	if _playback == null or music_state_source == null:
		return
	if not bool(music_state_source.get("music_enabled")):
		return
	var intensity: float = clampf(_read_factor(music_state_source, "music_intensity", 1.0), 0.2, 2.0)
	var speed: float = clampf(_read_factor(music_state_source, "music_speed", 1.0), 0.5, 1.8)
	var tone: float = clampf(_read_factor(music_state_source, "music_tone", 1.0), 0.7, 1.4)
	var step_seconds: float = _step_seconds / speed
	var frames_available: int = _playback.get_frames_available()
	for _i in range(frames_available):
		var step_idx: int = int(floor(_time / step_seconds))
		var chord_idx: int = int(floor(float(step_idx) / _MUSIC_STEPS_PER_CHORD)) % _MUSIC_PROGRESS_ROOTS.size()
		var step_in_chord: int = step_idx % _MUSIC_STEPS_PER_CHORD
		var lead_freq: float = float(_MUSIC_MELODY_BY_CHORD[chord_idx][step_in_chord]) * tone
		var root_freq: float = _MUSIC_PROGRESS_ROOTS[chord_idx] * tone
		var chord_tones: Array = _MUSIC_CHORD_TONES[chord_idx]
		_phase += TAU * lead_freq / _MUSIC_SAMPLE_RATE
		_bass_phase += TAU * root_freq / _MUSIC_SAMPLE_RATE
		var lead_square: float = 1.0 if sin(_phase) >= 0.0 else -1.0
		var lead_secondary: float
		if _lead_secondary_square:
			lead_secondary = 1.0 if sin(_phase * _lead_secondary_mul) >= 0.0 else -1.0
		else:
			lead_secondary = sin(_phase * _lead_secondary_mul)
		var bass_square: float = 1.0 if sin(_bass_phase) >= 0.0 else -1.0
		var pad: float = (
			sin(_time * TAU * float(chord_tones[0]) * tone) +
			sin(_time * TAU * float(chord_tones[1]) * tone) +
			sin(_time * TAU * float(chord_tones[2]) * tone)
		) / 3.0
		var step_phase: float = fmod(_time, step_seconds) / step_seconds
		var gate: float = _gate_start - step_phase * _gate_falloff
		var sample: float = (
			lead_square * _lead_square_amp +
			lead_secondary * _lead_secondary_amp +
			bass_square * _bass_amp +
			pad * _pad_amp
		) * gate * intensity
		sample = clampf(sample, -0.95, 0.95)
		_playback.push_frame(Vector2(sample, sample))
		_time += 1.0 / _MUSIC_SAMPLE_RATE

func teardown() -> void:
	if _player != null:
		_player.stop()
	_playback = null

func _read_factor(source: Object, key: String, fallback: float) -> float:
	var value: Variant = source.get(key)
	if value == null:
		return fallback
	return float(value)
