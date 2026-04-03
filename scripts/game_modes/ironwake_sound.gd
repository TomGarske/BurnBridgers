class_name IronwakeSound
extends RefCounted

var arena: Node = null

# SFX player pool — allows overlapping sounds (e.g. broadside of 14 cannons).
const SFX_POOL_SIZE: int = 4
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next: int = 0

# Dedicated ambient player (loops continuously, separate from SFX pool).
var _ambient_player: AudioStreamPlayer = null


func init(arena_node: Node) -> void:
	arena = arena_node


func _ensure_sfx_pool() -> void:
	if _sfx_players.size() >= SFX_POOL_SIZE:
		return
	for i in range(SFX_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "IronwakeSfx_%d" % i
		arena.add_child(player)
		_sfx_players.append(player)


func _get_next_player() -> AudioStreamPlayer:
	_ensure_sfx_pool()
	var player: AudioStreamPlayer = _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % SFX_POOL_SIZE
	return player


## Legacy compatibility — ensures at least the pool exists.
func ensure_audio_player() -> void:
	_ensure_sfx_pool()


func _sfx_scale() -> float:
	if GameManager != null:
		return float(GameManager.sfx_volume)
	return 1.0


# ---------------------------------------------------------------------------
# Cannon hit sound (existing — impact on hull)
# ---------------------------------------------------------------------------
func play_cannon_hit_sound() -> void:
	var player: AudioStreamPlayer = _get_next_player()
	var vol: float = _sfx_scale()
	var mix_rate: int = 44100
	var duration_sec: float = 0.16
	var sample_count: int = maxi(1, int(duration_sec * float(mix_rate)))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in range(sample_count):
		var t: float = float(i) / float(mix_rate)
		var env: float = exp(-t * 22.0)
		var s: float = (
			sin(t * TAU * 112.0) * 0.52
			+ sin(t * TAU * 268.0) * 0.28
			+ sin(t * TAU * 440.0) * 0.14
		) * env * 0.48 * vol
		s = clampf(s, -1.0, 1.0)
		var v: int = int(clampi(int(s * 32767.0), -32768, 32767))
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.mix_rate = mix_rate
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	wav.data = data
	player.stream = wav
	player.play()


# ---------------------------------------------------------------------------
# UI tone (existing — helm lock, sail, fire mode feedback)
# ---------------------------------------------------------------------------
func play_tone(freq_hz: float, duration_sec: float, volume: float) -> void:
	var player: AudioStreamPlayer = _get_next_player()
	var vol: float = _sfx_scale()
	var mix_rate: int = 44100
	var sample_count: int = maxi(1, int(duration_sec * mix_rate))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in range(sample_count):
		var t: float = float(i) / float(mix_rate)
		var envelope: float = clampf(1.0 - (float(i) / float(sample_count)), 0.0, 1.0)
		var sine: float = sin(t * TAU * freq_hz)
		var buzz: float = sign(sin(t * TAU * freq_hz * 0.5))
		var s: float = (sine * 0.65 + buzz * 0.35) * envelope * volume * vol
		var v: int = int(clampi(int(s * 32767.0), -32768, 32767))
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.mix_rate = mix_rate
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	wav.data = data
	player.stream = wav
	player.play()


# ---------------------------------------------------------------------------
# Cannon fire discharge — deep boom when cannons fire (close / player)
# ---------------------------------------------------------------------------
func play_cannon_fire_sound() -> void:
	var player: AudioStreamPlayer = _get_next_player()
	var vol: float = _sfx_scale()
	var mix_rate: int = 44100
	var duration_sec: float = 0.28
	var sample_count: int = maxi(1, int(duration_sec * float(mix_rate)))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	# Seeded noise for deterministic "crack" texture.
	var noise_state: int = 48271
	for i in range(sample_count):
		var t: float = float(i) / float(mix_rate)
		var env: float = exp(-t * 14.0)
		# Low-frequency boom: 55 Hz + 82 Hz sub-harmonics.
		var boom: float = sin(t * TAU * 55.0) * 0.50 + sin(t * TAU * 82.0) * 0.30
		# White noise burst for the crack (fast decay).
		var noise_env: float = exp(-t * 35.0)
		noise_state = (noise_state * 48271) % 2147483647
		var noise: float = (float(noise_state) / 1073741823.5 - 1.0) * noise_env * 0.25
		var s: float = (boom + noise) * env * 0.55 * vol
		s = clampf(s, -1.0, 1.0)
		var v: int = int(clampi(int(s * 32767.0), -32768, 32767))
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.mix_rate = mix_rate
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	wav.data = data
	player.stream = wav
	player.play()


# ---------------------------------------------------------------------------
# Cannon fire distant — muffled boom heard when opponents fire
# ---------------------------------------------------------------------------
func play_cannon_fire_distant() -> void:
	var player: AudioStreamPlayer = _get_next_player()
	var vol: float = _sfx_scale() * 0.35
	var mix_rate: int = 44100
	var duration_sec: float = 0.35
	var sample_count: int = maxi(1, int(duration_sec * float(mix_rate)))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in range(sample_count):
		var t: float = float(i) / float(mix_rate)
		var env: float = exp(-t * 9.0)  # Slower decay = more distant rumble.
		# Only low frequencies — no noise crack.
		var boom: float = sin(t * TAU * 55.0) * 0.55 + sin(t * TAU * 72.0) * 0.30
		var s: float = boom * env * 0.45 * vol
		s = clampf(s, -1.0, 1.0)
		var v: int = int(clampi(int(s * 32767.0), -32768, 32767))
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.mix_rate = mix_rate
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	wav.data = data
	player.stream = wav
	player.play()


# ---------------------------------------------------------------------------
# Ambient ocean loop — continuous filtered noise wash
# ---------------------------------------------------------------------------
func start_ocean_ambient() -> void:
	if _ambient_player != null:
		return
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.name = "OceanAmbient"
	arena.add_child(_ambient_player)

	var vol: float = _sfx_scale() * 0.12
	var mix_rate: int = 22050  # Lower sample rate is fine for ambient noise.
	var loop_sec: float = 3.0
	var sample_count: int = int(loop_sec * float(mix_rate))
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	# Generate filtered noise with wave-like volume swell.
	var noise_state: int = 73939
	var prev_sample: float = 0.0
	for i in range(sample_count):
		var t: float = float(i) / float(mix_rate)
		# Simple low-pass: average current noise with previous sample.
		noise_state = (noise_state * 48271) % 2147483647
		var raw_noise: float = float(noise_state) / 1073741823.5 - 1.0
		var filtered: float = prev_sample * 0.85 + raw_noise * 0.15
		prev_sample = filtered
		# Wave-like swell: slow sine modulation.
		var swell: float = 0.6 + 0.4 * sin(t * TAU * 0.15)
		var s: float = filtered * swell * 0.3 * vol
		s = clampf(s, -1.0, 1.0)
		var v: int = int(clampi(int(s * 32767.0), -32768, 32767))
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF

	var wav := AudioStreamWAV.new()
	wav.mix_rate = mix_rate
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = sample_count
	wav.data = data
	_ambient_player.stream = wav
	_ambient_player.play()


func stop_ocean_ambient() -> void:
	if _ambient_player != null:
		_ambient_player.stop()
		_ambient_player.queue_free()
		_ambient_player = null
