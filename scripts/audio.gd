class_name GameAudio
extends Node

## Procedurally synthesized audio: chiptune-style SFX and a looping
## background track, all generated into AudioStreamWAVs at startup.
## No asset files needed. As a child of Main this pauses with the tree.

const RATE := 22050
const BPM := 145.0  # psytrance tempo; PsyTheme locks the visuals to this

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

	# boing: springy rising triangle for spring-pad launches
	_add_sfx("boing", _sweep(160.0, 640.0, 0.25, 2, 0.45, 2.0), -6.0, 2)

	music = AudioStreamPlayer.new()
	music.stream = _make_psytrance()
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


## Full-on psytrance, 8 bars of 4/4 at BPM: four-on-the-floor kick, rolling
## 16th offbeat bass (the classic kick-b-b-b gallop), offbeat open hats and
## an E-phrygian acid line that swells across the loop. Loops seamlessly.
func _make_psytrance() -> AudioStreamWAV:
	var beat := 60.0 / BPM
	var s16 := beat / 4.0
	var beats := 32
	var buf := PackedFloat32Array()
	buf.resize(int(float(beats) * beat * RATE))

	# sub drone on low E glues the loop together
	_mix_into(buf, _sweep(41.2, 41.2, float(beats) * beat, 0, 0.06, 0.0), 0)

	# 2-bar acid sequence (E phrygian), repeated with a volume swell
	var seq := [164.81, 174.61, 164.81, 196.0, 220.0, 164.81, 246.94, 220.0,
			164.81, 174.61, 329.63, 246.94, 220.0, 196.0, 174.61, 164.81,
			164.81, 293.66, 164.81, 246.94, 220.0, 196.0, 164.81, 174.61,
			196.0, 220.0, 246.94, 293.66, 329.63, 246.94, 220.0, 174.61]

	for b in range(beats):
		var at := int(float(b) * beat * RATE)
		# kick: clicky sine drop 160 -> 45 Hz on every beat
		_mix_into(buf, _sweep(160.0, 45.0, 0.32 * beat, 0, 0.55, 9.0), at)
		# rolling bass on 16ths 2..4 (square growl + sine sub, gated short)
		for k in range(1, 4):
			var t0 := int((float(b) + float(k) * 0.25) * beat * RATE)
			_mix_into(buf, _sweep(82.41, 82.41, s16 * 0.85, 1, 0.20, 7.0), t0)
			_mix_into(buf, _sweep(82.41, 82.41, s16 * 0.85, 0, 0.22, 6.0), t0)
		# offbeat open hat
		_mix_into(buf, _sweep(0.0, 0.0, 0.10, 3, 0.16, 14.0), at + int(0.5 * beat * RATE))
		# acid 16ths, swelling from whisper to lead over the 8 bars
		var swell := 0.05 + 0.10 * (float(b) / float(beats))
		for k in range(4):
			var f: float = seq[(b * 4 + k) % seq.size()]
			var t1 := int((float(b) + float(k) * 0.25) * beat * RATE)
			_mix_into(buf, _sweep(f, f * 1.01, s16 * 0.9, 1, swell, 5.0), t1)

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
