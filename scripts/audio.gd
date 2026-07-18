class_name GameAudio
extends Node

## Procedurally synthesized audio: chiptune-style SFX and a looping
## background track, all generated into AudioStreamWAVs at startup.
## No asset files needed. As a child of Main this pauses with the tree.

const RATE := 22050

var music: AudioStreamPlayer
var players := {}


func _ready() -> void:
	# jump: quick rising square sweep
	_add_sfx("jump", _sweep(280.0, 660.0, 0.18, 1, 0.35, 3.0), -9.0, 2)

	# pickup: bright two-note sine bling
	var pickup := _sweep(880.0, 880.0, 0.06, 0, 0.35, 2.0)
	pickup.append_array(_sweep(1318.5, 1318.5, 0.1, 0, 0.35, 4.0))
	_add_sfx("pickup", pickup, -7.0, 3)

	# build: soft shimmering triangle arpeggio
	var build := _sweep(523.25, 523.25, 0.05, 2, 0.3, 2.0)
	build.append_array(_sweep(659.25, 659.25, 0.05, 2, 0.3, 2.0))
	build.append_array(_sweep(784.0, 784.0, 0.12, 2, 0.3, 5.0))
	_add_sfx("build", build, -9.0, 3)

	# squish: falling square + noise splat
	var squish := _sweep(400.0, 90.0, 0.16, 1, 0.4, 4.0)
	_mix_into(squish, _sweep(0.0, 0.0, 0.16, 3, 0.2, 6.0), 0)
	_add_sfx("squish", squish, -7.0, 2)

	# death: long sad descending square
	_add_sfx("death", _sweep(660.0, 70.0, 0.6, 1, 0.4, 2.5), -5.0, 1)

	music = AudioStreamPlayer.new()
	music.stream = _make_music()
	music.volume_db = -13.0
	add_child(music)


func play(sfx: String) -> void:
	players[sfx].play()


func start_music() -> void:
	music.play()


func stop_music() -> void:
	music.stop()


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


## Mellow 8-bar loop: Am - F - C - G, triangle arpeggio over a sine bass.
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
