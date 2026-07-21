class_name GameAudio
extends Node

## Procedurally synthesized audio: everyday foley-like SFX and a looping
## background track, all generated into AudioStreamWAVs at startup.
## No asset files needed. As a child of Main this pauses with the tree.

const RATE := 22050
const BPM := 112.0  # relaxed city-groove tempo; PsyTheme locks to this

var music: AudioStreamPlayer
var players := {}


func _ready() -> void:
	# jump: soft sneaker whoosh instead of an arcade square-wave chirp
	var jump := _sweep(220.0, 520.0, 0.16, 2, 0.24, 5.0)
	_mix_into(jump, _sweep(0.0, 0.0, 0.08, 3, 0.06, 14.0), 0)
	_add_sfx("jump", jump, -8.0, 2)

	# pickup: warm coffee-shop counter bell
	var pickup := _sweep(659.25, 659.25, 0.08, 0, 0.30, 3.0)
	pickup.append_array(_sweep(987.77, 987.77, 0.14, 0, 0.26, 5.0))
	_add_sfx("pickup", pickup, -7.0, 3)

	# build: three tidy pencil/notepad taps
	var build := _sweep(310.0, 260.0, 0.045, 2, 0.24, 9.0)
	build.append_array(_sweep(390.0, 340.0, 0.045, 2, 0.22, 9.0))
	build.append_array(_sweep(520.0, 460.0, 0.09, 2, 0.20, 10.0))
	_add_sfx("build", build, -9.0, 3)

	# Original two-note chat chime for dismissing a notification. It has the
	# familiar messenger association without copying a third-party audio asset.
	var squish := _sweep(880.0, 880.0, 0.075, 0, 0.28, 5.0)
	var chat_gap := PackedFloat32Array()
	chat_gap.resize(int(0.025 * RATE))
	squish.append_array(chat_gap)
	squish.append_array(_sweep(1318.51, 1318.51, 0.15, 0, 0.32, 6.0))
	_mix_into(squish, _sweep(440.0, 440.0, 0.07, 2, 0.08, 8.0), 0)
	_add_sfx("squish", squish, -7.0, 2)

	# missed-step cue: muted descending transit chime
	_add_sfx("death", _sweep(440.0, 110.0, 0.65, 2, 0.32, 3.5), -6.0, 1)

	# boing: springy rising triangle for spring-pad launches
	_add_sfx("boing", _sweep(160.0, 640.0, 0.25, 2, 0.45, 2.0), -6.0, 2)

	music = AudioStreamPlayer.new()
	music.stream = _make_city_groove()
	music.volume_db = -13.0
	add_child(music)


func play(sfx: String) -> void:
	players[sfx].play()


func start_music() -> void:
	music.play()


func stop_music() -> void:
	music.stop()


## Seconds into the music, mix-accurate; 0.0 while stopped. PsyTheme uses
## this as the beat clock so the visuals never drift from the kick.
func music_time() -> float:
	if not music.playing:
		return 0.0
	return music.get_playback_position() + AudioServer.get_time_since_last_mix()


func _add_sfx(sfx_name: String, samples: PackedFloat32Array, db: float, poly: int) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = _make_wav(samples, false)
	p.volume_db = db
	p.max_polyphony = poly
	add_child(p)
	players[sfx_name] = p


## One oscillator note/sweep. wave: 0 sine, 1 square, 2 triangle, 3 noise.
func _sweep(f0: float, f1: float, dur: float, wave: int, vol: float, decay: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / float(n)
		phase += lerpf(f0, f1, t) / RATE
		var s: float
		match wave:
			0:
				s = sin(phase * TAU)
			1:
				s = 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
			2:
				s = 4.0 * absf(fmod(phase, 1.0) - 0.5) - 1.0
			_:
				s = randf_range(-1.0, 1.0)
		var env := minf(float(i) / (0.005 * RATE), 1.0) * exp(-decay * t)
		out[i] = s * vol * env
	return out


func _mix_into(buf: PackedFloat32Array, samples: PackedFloat32Array, offset: int) -> void:
	for i in range(samples.size()):
		var j := offset + i
		if j < buf.size():
			buf[j] += samples[i]


## Eight-bar lo-fi city groove: soft kick, rim taps, brushed hats, round bass,
## and a small electric-piano figure. Still fully generated at startup.
func _make_city_groove() -> AudioStreamWAV:
	var beat := 60.0 / BPM
	var beats := 32
	var buf := PackedFloat32Array()
	buf.resize(int(float(beats) * beat * RATE))
	var roots := [110.0, 87.31, 130.81, 98.0]  # Am, F, C, G
	var chords := [
		[220.0, 261.63, 329.63], [174.61, 220.0, 261.63],
		[261.63, 329.63, 392.0], [196.0, 246.94, 293.66],
	]
	for b in range(beats):
		var at := int(float(b) * beat * RATE)
		var ci := int(b / 8)
		# Soft kick on one and three; rim/noise tap on two and four.
		if b % 4 == 0 or b % 4 == 2:
			_mix_into(buf, _sweep(105.0, 48.0, 0.22, 0, 0.30, 10.0), at)
		else:
			_mix_into(buf, _sweep(850.0, 520.0, 0.045, 2, 0.12, 18.0), at)
			_mix_into(buf, _sweep(0.0, 0.0, 0.055, 3, 0.05, 22.0), at)
		# Round bass plus a brushed offbeat hat.
		var root_freq: float = roots[ci]
		_mix_into(buf, _sweep(root_freq, root_freq, beat * 0.72, 0, 0.16, 4.0), at)
		_mix_into(buf, _sweep(0.0, 0.0, 0.065, 3, 0.055, 18.0),
				at + int(0.5 * beat * RATE))
		# Alternating chord tones keep the loop moving without demanding focus.
		for k in range(2):
			var note: float = chords[ci][(b * 2 + k) % 3]
			var note_at := at + int(float(k) * 0.5 * beat * RATE)
			_mix_into(buf, _sweep(note, note, beat * 0.42, 2, 0.075, 5.0), note_at)

	return _make_wav(buf, true)


## (unused on this branch) Mellow 8-bar loop: Am - F - C - G.
func _make_music() -> AudioStreamWAV:
	var step := 60.0 / 110.0 / 2.0  # eighth notes at 110 bpm
	var chords := [
		[220.0, 261.63, 329.63],   # A minor
		[174.61, 220.0, 261.63],   # F major
		[261.63, 329.63, 392.0],   # C major
		[196.0, 246.94, 293.66],   # G major
	]
	var bass := [110.0, 87.31, 130.81, 98.0]
	var arp_idx := [0, 1, 2, 1, 0, 1, 2, 1]

	var total := int(4.0 * 8.0 * step * RATE)
	var buf := PackedFloat32Array()
	buf.resize(total)

	for ci in range(4):
		_mix_into(buf, _sweep(bass[ci], bass[ci], 8.0 * step, 0, 0.16, 0.5),
				int(float(ci) * 8.0 * step * RATE))
		for s in range(8):
			var freq: float = chords[ci][arp_idx[s]]
			_mix_into(buf, _sweep(freq, freq, step * 0.95, 2, 0.22, 3.0),
					int((float(ci) * 8.0 + float(s)) * step * RATE))

	return _make_wav(buf, true)


func _make_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav
