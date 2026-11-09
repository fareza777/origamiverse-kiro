class_name OVPaperAudio
extends Node
## Runtime-synthesized paper sound design. No audio files ship with the apps, so there is nothing to license.
## Add one instance as an autoload-style child and call play("fold"), play_note(i), set_ambience("dawn").

const RATE: int = 22050
const MOODS: Dictionary = {
	# Root frequency and chord ratios for each ambience loop.
	"dawn": {"root": 196.0, "ratios": [1.0, 1.5, 2.0, 2.5], "wind": 0.10, "bright": 0.6},
	"dusk": {"root": 174.6, "ratios": [1.0, 1.2, 1.5, 2.0], "wind": 0.12, "bright": 0.45},
	"night": {"root": 146.8, "ratios": [1.0, 1.189, 1.5, 1.782], "wind": 0.16, "bright": 0.3},
	"studio": {"root": 220.0, "ratios": [1.0, 1.25, 1.5, 1.875], "wind": 0.05, "bright": 0.5},
}
const PENTATONIC: Array[float] = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1174.66, 1318.5]

var haptics_enabled: bool = true
var _streams: Dictionary = {}
var _notes: Array[AudioStreamWAV] = []
var _players: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _music_fade: Tween
var _mood: String = ""
var _ambience_cache: Dictionary = {}
var _thread: Thread
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_rng.seed = 7
	_streams["fold"] = _make_crinkle(0.32, 18, 0.9)
	_streams["fold_soft"] = _make_crinkle(0.22, 9, 0.6)
	_streams["snap"] = _make_snap()
	_streams["step"] = _make_step()
	_streams["ui"] = _make_tick(980.0, 0.035)
	_streams["ui_back"] = _make_tick(660.0, 0.04)
	_streams["error"] = _make_error()
	_streams["whoosh"] = _make_whoosh(0.45)
	_streams["unlock"] = _make_bell(392.0, 1.4, 0.55)
	for f in PENTATONIC:
		_notes.append(_make_bell(f, 1.1, 0.4))
	for i in 8:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.volume_db = -80.0
	add_child(_music)


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


static func _ensure_bus(name: String) -> void:
	if AudioServer.get_bus_index(name) == -1:
		AudioServer.add_bus()
		var idx: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, name)
		AudioServer.set_bus_send(idx, "Master")


static func set_bus_volume(name: String, linear: float) -> void:
	_ensure_bus(name)
	var idx: int = AudioServer.get_bus_index(name)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


func play(name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	var s: AudioStreamWAV = _streams.get(name)
	if s == null:
		return
	_play_stream(s, pitch, volume_db)


## Plays note `index` of a pentatonic bell scale (wraps), used for collectibles and combos.
func play_note(index: int, volume_db: float = -2.0) -> void:
	var i: int = posmod(index, _notes.size())
	var octave: float = 1.0 if index < _notes.size() else 2.0
	_play_stream(_notes[i], octave, volume_db)


func play_fanfare() -> void:
	for i in 5:
		get_tree().create_timer(0.11 * i).timeout.connect(play_note.bind([0, 2, 4, 5, 7][i], -3.0))


func _play_stream(s: AudioStream, pitch: float, volume_db: float) -> void:
	for p in _players:
		if not p.playing:
			p.stream = s
			p.pitch_scale = pitch * _rng.randf_range(0.97, 1.03)
			p.volume_db = volume_db
			p.play()
			return
	var p0: AudioStreamPlayer = _players[0]
	p0.stream = s
	p0.pitch_scale = pitch
	p0.volume_db = volume_db
	p0.play()


func haptic(ms: int = 18, amplitude: float = 0.5) -> void:
	if haptics_enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms, amplitude)


## Crossfades to a generated ambience loop. Generation happens on a worker thread.
func set_ambience(mood: String) -> void:
	if mood == _mood:
		return
	_mood = mood
	if _ambience_cache.has(mood):
		_start_music(_ambience_cache[mood])
		return
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = Thread.new()
	_thread.start(_generate_ambience_threaded.bind(mood))


func stop_ambience() -> void:
	_mood = ""
	if _music_fade:
		_music_fade.kill()
	_music_fade = create_tween()
	_music_fade.tween_property(_music, "volume_db", -80.0, 0.8)
	_music_fade.tween_callback(_music.stop)


func _generate_ambience_threaded(mood: String) -> void:
	var s: AudioStreamWAV = make_ambience(mood)
	call_deferred("_on_ambience_ready", mood, s)


func _on_ambience_ready(mood: String, s: AudioStreamWAV) -> void:
	_ambience_cache[mood] = s
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	if mood == _mood:
		_start_music(s)


func _start_music(s: AudioStreamWAV) -> void:
	if _music_fade:
		_music_fade.kill()
	_music.stream = s
	_music.volume_db = -40.0
	_music.play()
	_music_fade = create_tween()
	_music_fade.tween_property(_music, "volume_db", -6.0, 2.0)


# ---------------------------------------------------------------- synthesis


static func _to_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w: AudioStreamWAV = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _make_crinkle(dur: float, grains: int, gain: float) -> AudioStreamWAV:
	var n: int = int(dur * RATE)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	for g in grains:
		var start: int = int(_rng.randf() * n * 0.85)
		var glen: int = int(_rng.randf_range(0.004, 0.02) * RATE)
		var amp: float = _rng.randf_range(0.25, 1.0) * (1.0 - float(start) / n)
		var hp_prev: float = 0.0
		var lp: float = 0.0
		var cutoff: float = _rng.randf_range(0.25, 0.6)
		for i in glen:
			var idx: int = start + i
			if idx >= n:
				break
			var x: float = _rng.randf_range(-1.0, 1.0)
			var hp: float = x - hp_prev
			hp_prev = x
			lp += (hp - lp) * cutoff
			var env: float = exp(-6.0 * float(i) / glen)
			out[idx] += lp * amp * env
	_normalize(out, gain)
	return _to_wav(out)


func _make_snap() -> AudioStreamWAV:
	var n: int = int(0.14 * RATE)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var prev: float = 0.0
	for i in n:
		var t: float = float(i) / RATE
		var click: float = 0.0
		if i < int(0.006 * RATE):
			var x: float = _rng.randf_range(-1.0, 1.0)
			click = (x - prev) * exp(-t * 600.0)
			prev = x
		var thump: float = sin(TAU * (140.0 - t * 300.0) * t) * exp(-t * 32.0) * 0.8
		out[i] = click * 0.9 + thump
	_normalize(out, 0.85)
	return _to_wav(out)


func _make_step() -> AudioStreamWAV:
	var n: int = int(0.05 * RATE)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var lp: float = 0.0
	for i in n:
		var t: float = float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.18
		out[i] = lp * exp(-t * 90.0) + sin(TAU * 210.0 * t) * exp(-t * 70.0) * 0.3
	_normalize(out, 0.45)
	return _to_wav(out)


func _make_tick(freq: float, dur: float) -> AudioStreamWAV:
	var n: int = int(dur * RATE)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t: float = float(i) / RATE
		out[i] = sin(TAU * freq * t) * exp(-t * 120.0) * minf(1.0, t * 2000.0)
	_normalize(out, 0.35)
	return _to_wav(out)


func _make_error() -> AudioStreamWAV:
	var n: int = int(0.22 * RATE)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t: float = float(i) / RATE
		var f: float = 170.0 if t < 0.1 else 130.0
		var tri: float = 2.0 * absf(2.0 * fmod(f * t, 1.0) - 1.0) - 1.0
		out[i] = tri * exp(-fmod(t, 0.1) * 18.0) * minf(1.0, t * 800.0)
	_normalize(out, 0.4)
	return _to_wav(out)


func _make_whoosh(dur: float) -> AudioStreamWAV:
	var n: int = int(dur * RATE)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var lp: float = 0.0
	for i in n:
		var x: float = float(i) / n
		var cutoff: float = 0.03 + 0.25 * sin(PI * x)
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * cutoff
		out[i] = lp * sin(PI * x)
	_normalize(out, 0.5)
	return _to_wav(out)


func _make_bell(freq: float, dur: float, gain: float) -> AudioStreamWAV:
	var n: int = int(dur * RATE)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t: float = float(i) / RATE
		var attack: float = minf(1.0, t * 400.0)
		var s: float = sin(TAU * freq * t) * exp(-t * 3.2)
		s += sin(TAU * freq * 2.76 * t) * exp(-t * 6.0) * 0.35
		s += sin(TAU * freq * 5.4 * t) * exp(-t * 11.0) * 0.15
		out[i] = s * attack
	_normalize(out, gain)
	return _to_wav(out)


## Seamless ambience loop: every partial completes an integer number of cycles over the loop length.
static func make_ambience(mood: String, seconds: float = 8.0) -> AudioStreamWAV:
	var cfg: Dictionary = MOODS.get(mood, MOODS["dawn"])
	var n: int = int(seconds * RATE)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var voices: Array = []
	for r in cfg.ratios:
		var f: float = roundf(float(cfg.root) * float(r) * seconds) / seconds
		voices.append(f)
	var lfo_f: float = 1.0 / seconds
	var bright: float = cfg.bright
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(mood)
	var wind: PackedFloat32Array = PackedFloat32Array()
	wind.resize(n)
	var lp: float = 0.0
	for i in n:
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.02
		wind[i] = lp
	# Crossfade the wind's tail into its head so the noise layer loops cleanly too.
	var xf: int = int(0.5 * RATE)
	for i in xf:
		var a: float = float(i) / xf
		wind[i] = wind[i] * a + wind[n - xf + i] * (1.0 - a)
	for i in n:
		var t: float = float(i) / RATE
		var s: float = 0.0
		for v in voices.size():
			var f: float = voices[v]
			var phase_lfo: float = 0.5 + 0.5 * sin(TAU * lfo_f * t * (v % 2 + 1) + v * 1.7)
			var tone: float = sin(TAU * f * t) + bright * 0.25 * sin(TAU * f * 2.0 * t)
			s += tone * (0.35 + 0.65 * phase_lfo) / float(voices.size())
		var gust: float = 0.5 + 0.5 * sin(TAU * lfo_f * t + 0.6)
		out[i] = s * 0.32 + wind[i] * float(cfg.wind) * 4.0 * gust
	var peak: float = 0.0
	for v2 in out:
		peak = maxf(peak, absf(v2))
	if peak > 0.0:
		for i in n:
			out[i] *= 0.5 / peak
	return _to_wav(out, true)


static func _normalize(buf: PackedFloat32Array, gain: float) -> void:
	var peak: float = 0.0
	for v in buf:
		peak = maxf(peak, absf(v))
	if peak <= 0.0:
		return
	var k: float = gain / peak
	for i in buf.size():
		buf[i] *= k
