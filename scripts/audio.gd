class_name GameAudio
extends Node

## Procedurally synthesized audio: chiptune-style SFX and looping
## background tracks, all generated into AudioStreamWAVs at startup.
## No asset files needed. As a child of Main this pauses with the tree.
##
## Music comes in several mood variants (one per palette family, see
## game_theme.gd); when the theme changes, set_music_variant crossfades
## to the matching loop, optionally pitch-shifted a few percent for a
## darker/brighter shade of the same mood. Variant 0 is rendered
## synchronously so play can start instantly; the rest render on a
## background thread (pure math, no engine access) and are collected on
## the first theme switch, which happens no earlier than ~100 m in.
## SFX are shared by all themes so they stay instantly recognizable.

const RATE := 22050
const MUSIC_DB := -13.0
const MUSIC_FADE := 2.0  # seconds of crossfade between mood loops

## Mood loop recipes. All share the same bones as the original track
## (8-bar loop, eighth-note arpeggio over held bass roots) so a switch
## feels like the SAME soundtrack changing mood, not a different song:
##   0 "twilight"  A natural minor i-VI-III-VII (Am-F-C-G), triangle arp,
##                 110 bpm -- wistful; the game's identity theme
##   1 "forest"    E dorian i-III-VII-IV (Em-G-D-A), soft sine arp,
##                 100 bpm -- dorian is the 'brighter minor': calm, woodsy
##   2 "ember"     D minor with major-V tension i-VI-iv-V (Dm-Bb-Gm-A),
##                 116 bpm -- the raised leading tone smolders
##   3 "dawn"      C major pop loop I-V-vi-IV (C-G-Am-F), dreamy sine arp
##                 with a rise-fall pattern, 105 bpm -- the sunrise
const MUSIC_VARIANTS := [
	{
		"bpm": 110.0, "arp_wave": 2, "bass_wave": 0,
		"arp_vol": 0.22, "bass_vol": 0.16,
		"pattern": [0, 1, 2, 1, 0, 1, 2, 1],
		"chords": [
			[220.0, 261.63, 329.63],    # A minor
			[174.61, 220.0, 261.63],    # F major
			[261.63, 329.63, 392.0],    # C major
			[196.0, 246.94, 293.66],    # G major
		],
		"bass": [110.0, 87.31, 130.81, 98.0],
	},
	{
		"bpm": 100.0, "arp_wave": 0, "bass_wave": 0,
		"arp_vol": 0.28, "bass_vol": 0.16,
		"pattern": [0, 1, 2, 1, 0, 1, 2, 1],
		"chords": [
			[164.81, 196.0, 246.94],    # E minor
			[196.0, 246.94, 293.66],    # G major
			[146.83, 185.0, 220.0],     # D major
			[220.0, 277.18, 329.63],    # A major (the dorian IV)
		],
		"bass": [82.41, 98.0, 73.42, 110.0],
	},
	{
		"bpm": 116.0, "arp_wave": 2, "bass_wave": 2,
		"arp_vol": 0.22, "bass_vol": 0.15,
		"pattern": [0, 1, 2, 1, 0, 1, 2, 1],
		"chords": [
			[146.83, 174.61, 220.0],    # D minor
			[116.54, 146.83, 174.61],   # Bb major
			[196.0, 233.08, 293.66],    # G minor
			[220.0, 277.18, 329.63],    # A major (raised leading tone)
		],
		"bass": [73.42, 58.27, 98.0, 110.0],
	},
	{
		"bpm": 105.0, "arp_wave": 0, "bass_wave": 0,
		"arp_vol": 0.28, "bass_vol": 0.15,
		"pattern": [0, 2, 1, 2, 0, 2, 1, 0],
		"chords": [
			[261.63, 329.63, 392.0],    # C major
			[196.0, 246.94, 293.66],    # G major
			[220.0, 261.63, 329.63],    # A minor
			[174.61, 220.0, 261.63],    # F major
		],
		"bass": [130.81, 98.0, 110.0, 87.31],
	},
]

var players := {}
var music_players: Array[AudioStreamPlayer] = []
var music_variants: Array = []  # AudioStreamWAV per variant; 1+ filled lazily
var active_music := 0           # which of the two music players is in front
var current_variant := 0
var current_pitch := 1.0

var _music_thread: Thread
var _music_tween: Tween


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

	# two music players so mood changes can crossfade
	for i in range(2):
		var p := AudioStreamPlayer.new()
		p.volume_db = MUSIC_DB
		add_child(p)
		music_players.append(p)

	music_variants.resize(MUSIC_VARIANTS.size())
	music_variants[0] = _make_wav(_render_music(0), true)
	_music_thread = Thread.new()
	_music_thread.start(_render_rest)


func _exit_tree() -> void:
	if _music_thread != null:
		_music_thread.wait_to_finish()
		_music_thread = null


func play(sfx: String) -> void:
	players[sfx].play()


func start_music() -> void:
	var p := music_players[active_music]
	p.stream = music_variants[current_variant]
	p.pitch_scale = current_pitch
	p.volume_db = MUSIC_DB
	p.play()


func stop_music() -> void:
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	for p in music_players:
		p.stop()


## Crossfade to another mood loop (called on theme changes).
func set_music_variant(variant: int, pitch: float) -> void:
	if variant == current_variant and is_equal_approx(pitch, current_pitch):
		return
	_ensure_variants()
	current_variant = variant
	current_pitch = pitch
	var old := music_players[active_music]
	active_music = 1 - active_music
	var next := music_players[active_music]
	next.stream = music_variants[variant]
	next.pitch_scale = pitch
	next.volume_db = -48.0
	next.play()
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(next, "volume_db", MUSIC_DB, MUSIC_FADE)
	_music_tween.tween_property(old, "volume_db", -48.0, MUSIC_FADE)
	_music_tween.chain().tween_callback(old.stop)


## Collect the background-rendered variants (instant once the thread is done).
func _ensure_variants() -> void:
	if _music_thread == null:
		return
	var bufs: Array = _music_thread.wait_to_finish()
	_music_thread = null
	for i in range(bufs.size()):
		music_variants[i + 1] = _make_wav(bufs[i], true)


## Thread body: render every variant after the first. Pure math on local
## buffers, so it is safe off the main thread.
func _render_rest() -> Array:
	var out := []
	for i in range(1, MUSIC_VARIANTS.size()):
		out.append(_render_music(i))
	return out


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


## Render one 8-bar mood loop from its MUSIC_VARIANTS recipe.
func _render_music(variant: int) -> PackedFloat32Array:
	var cfg: Dictionary = MUSIC_VARIANTS[variant]
	var step: float = 60.0 / cfg["bpm"] / 2.0  # eighth notes
	var chords: Array = cfg["chords"]
	var bass: Array = cfg["bass"]
	var pattern: Array = cfg["pattern"]

	var total := int(4.0 * 8.0 * step * RATE)
	var buf := PackedFloat32Array()
	buf.resize(total)

	for ci in range(4):
		_mix_into(buf, _sweep(bass[ci], bass[ci], 8.0 * step, cfg["bass_wave"],
				cfg["bass_vol"], 0.5), int(float(ci) * 8.0 * step * RATE))
		for s in range(8):
			var freq: float = chords[ci][pattern[s]]
			_mix_into(buf, _sweep(freq, freq, step * 0.95, cfg["arp_wave"],
					cfg["arp_vol"], 3.0), int((float(ci) * 8.0 + float(s)) * step * RATE))

	return buf


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
