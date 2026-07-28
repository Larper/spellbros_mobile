class_name EchoBro
extends Node2D

## FRIENDS level helper. The friend lives in a floating video-call bubble, so
## following above the commuter reads as a call overlay rather than a hovering
## body. A would-be-lethal notification costs one energy and is intercepted by
## a tossed, unbranded drink can.

const HOVER := Vector2(-72.0, -158.0)
const BURN_COST := 1
const THROW_TIME := 0.22

## The call is a call: it rings, it is answered, and at the end of the band it
## is hung up. Popping a fully-drawn video window into existence at the level
## boundary and deleting it at the next one read as a glitch (Neven).
## `calling` is driven by Main from the FRIENDS banner, so the phone starts
## ringing while the banner is still on screen and connects as the ground drops
## away; `active` still gates the guard itself, so nothing is intercepted
## before the band proper.
enum { OFF, RINGING, ANSWERING, LIVE, HANGUP }
const RING_TIME := 1.15
const ANSWER_TIME := 0.32
const HANGUP_TIME := 0.85
## The hang-up plays out in two beats: the red end-call button pops up over the
## window and is pressed, and only THEN does the window close. Collapsing the
## window on its own just read as the friend disappearing again.
const HANGUP_PRESS := 0.34
const RING_BEAT := 0.72  # matches the two-chirp ring sample's length

var active := false
var calling := false
var t := randf() * TAU
var beam_t := 0.0  # kept as the throw countdown for test/backward compatibility
var beam_to := Vector2.ZERO
var phase := OFF
var phase_t := 0.0
var ring_beat := 0.0


func _ready() -> void:
	visible = false  # nothing on screen until the phone actually rings


## The follow runs on the PHYSICS tick, not the frame: physics interpolation
## smooths every other moving node from its physics transforms, so a node that
## repositioned itself per frame would be the one thing visibly lagging the
## commuter it is supposed to hover over.
func _physics_process(delta: float) -> void:
	t += delta
	beam_t = maxf(0.0, beam_t - delta)
	_advance_call(delta)
	visible = phase != OFF
	if not visible:
		return
	var main = get_tree().get_first_node_in_group("main")
	if main == null or main.player == null:
		return
	# the ring-in slides down into the hover spot; the hang-up drops away
	global_position = main.player.global_position + HOVER \
			+ Vector2(0.0, sin(t * 2.4) * 5.0 - 190.0 * _slide())
	queue_redraw()


func _advance_call(delta: float) -> void:
	phase_t += delta
	match phase:
		OFF:
			if calling:
				_enter(RINGING)
		RINGING:
			if not calling:
				_enter(HANGUP)
			elif phase_t >= RING_TIME:
				_enter(ANSWERING)
			else:
				ring_beat -= delta
				if ring_beat <= 0.0:
					ring_beat = RING_BEAT
					_sfx("ring")
		ANSWERING:
			if phase_t >= ANSWER_TIME:
				_enter(LIVE)
		LIVE:
			if not calling:
				_enter(HANGUP)
		HANGUP:
			if calling:
				_enter(RINGING)  # re-entering the band mid-hang-up: ring again
			elif phase_t >= HANGUP_TIME:
				_enter(OFF)


func _enter(next: int) -> void:
	phase = next
	phase_t = 0.0
	match next:
		RINGING:
			ring_beat = 0.0  # first chirp on the very next tick
		ANSWERING:
			_sfx("pickup")   # the connect chime
		HANGUP:
			_sfx("hangup")


func _sfx(sfx_name: String) -> void:
	var main = get_tree().get_first_node_in_group("main")
	if main != null and main.audio != null:
		main.audio.play(sfx_name)


## 0 = parked in the hover spot, 1 = fully off-screen above it. Drives the
## slide on the way in and the drop on the way out.
func _slide() -> float:
	if phase == RINGING:
		# ease-out: the window arrives fast, then settles
		var k := clampf(phase_t / 0.45, 0.0, 1.0)
		return (1.0 - k) * (1.0 - k)
	if phase == HANGUP:
		return -0.35 * _closing() * _closing()  # drops away once the call ends
	return 0.0


## 0 while the end-call button is still being shown and pressed, ramping to 1
## as the window actually closes.
func _closing() -> float:
	return clampf((phase_t - HANGUP_PRESS) / (HANGUP_TIME - HANGUP_PRESS), 0.0, 1.0)


## Overall opacity of the window: fades up with the ring-in, out with the
## hang-up, solid in between.
func _call_alpha() -> float:
	if phase == RINGING:
		return clampf(phase_t / 0.3, 0.0, 1.0)
	if phase == HANGUP:
		return 1.0 - _closing()
	return 1.0


## Called by SpikeBlob on a would-be-lethal touch. The protection mechanic is
## unchanged: one energy is spent, then the caller removes the notification.
func try_guard(at: Vector2) -> bool:
	if not active:
		return false
	var main = get_tree().get_first_node_in_group("main")
	if main == null or main.coins < BURN_COST:
		return false
	main.coins -= BURN_COST
	main.hud.update_coins(main.coins)
	main.audio.play("squish")
	main.float_text(at, "MUTED  -1", Color("f4c15d"))
	beam_to = at
	beam_t = THROW_TIME
	return true


func _draw() -> void:
	if phase == OFF:
		return
	var main = get_tree().get_first_node_in_group("main")
	var ca := _call_alpha()
	if phase == RINGING:
		_draw_ringing(ca)
		return
	var fueled: bool = main != null and main.coins >= BURN_COST
	var alpha := ((0.96 if fueled else 0.40) + 0.04 * sin(t * 5.0)) * ca

	# The can travels on a short readable arc. Drawing it behind the call bubble
	# makes it look as if the friend throws it out of the video window.
	if beam_t > 0.0:
		_draw_throw(1.0 - beam_t / THROW_TIME)

	# ANSWERING opens the window out of the ringing pill's footprint; HANGUP
	# collapses it back to a line, the way a call window closes.
	var ws := _window_scale()
	if ws != Vector2.ONE:
		draw_set_transform(Vector2.ZERO, 0.0, ws)

	# Mobile-safe video-call card. Some devices drop custom circles/polygons on
	# this following CanvasItem, so the entire persistent portrait deliberately
	# uses pixel-art blocks and lines. It is still clearly a call window rather
	# than a person inexplicably floating in the world.
	draw_rect(Rect2(-53, -51, 110, 104), Color(0.02, 0.08, 0.12, 0.32 * alpha))
	draw_rect(Rect2(-50, -54, 100, 104), Color(0.06, 0.20, 0.27, 0.96 * alpha))
	draw_rect(Rect2(-50, -54, 100, 6), Color(0.43, 0.88, 0.86, alpha))
	draw_rect(Rect2(-50, 44, 100, 6), Color(0.43, 0.88, 0.86, alpha))
	draw_rect(Rect2(-50, -54, 6, 104), Color(0.43, 0.88, 0.86, alpha))
	draw_rect(Rect2(44, -54, 6, 104), Color(0.43, 0.88, 0.86, alpha))
	# Stepped speech tail.
	draw_rect(Rect2(-15, 50, 22, 5), Color(0.43, 0.88, 0.86, alpha))
	draw_rect(Rect2(-10, 55, 16, 5), Color(0.43, 0.88, 0.86, alpha))
	draw_rect(Rect2(-5, 60, 10, 5), Color(0.43, 0.88, 0.86, alpha))

	# Friend portrait: warm face, dark hair and casual orange hoodie.
	draw_rect(Rect2(-16, -34, 32, 35), Color(0.93, 0.66, 0.46, alpha))
	draw_rect(Rect2(-20, -28, 40, 22), Color(0.93, 0.66, 0.46, alpha))
	draw_rect(Rect2(-16, -36, 32, 9), Color(0.16, 0.12, 0.11, alpha))
	draw_rect(Rect2(-20, -31, 7, 16), Color(0.16, 0.12, 0.11, alpha))
	draw_rect(Rect2(7, -21, 4, 4), Color(0.08, 0.11, 0.13, alpha))
	draw_line(Vector2(7, -9), Vector2(13, -7), Color(0.55, 0.30, 0.24, alpha), 2.0)
	draw_rect(Rect2(-6, -6, 12, 9), Color(0.78, 0.48, 0.33, alpha))
	draw_rect(Rect2(-27, 3, 54, 34), Color(0.91, 0.42, 0.24, alpha))
	draw_rect(Rect2(-32, 12, 64, 25), Color(0.91, 0.42, 0.24, alpha))
	draw_line(Vector2(0, 4), Vector2(0, 35), Color(1.0, 0.76, 0.55, alpha), 3.0)
	# Throwing arm points out of the call window during an interception.
	if beam_t > 0.0:
		draw_line(Vector2(20, 9), Vector2(39, 17), Color(0.93, 0.66, 0.46, alpha), 8.0)

	# Camera, online status and red hang-up controls.
	draw_rect(Rect2(-40, -45, 14, 9), Color(0.42, 0.88, 0.86, alpha))
	draw_rect(Rect2(-26, -42, 6, 4), Color(0.42, 0.88, 0.86, alpha))
	draw_rect(Rect2(30, -44, 10, 10), Color(0.35, 0.86, 0.46, alpha))
	draw_rect(Rect2(-13, 38, 26, 7), Color(0.90, 0.25, 0.24, alpha))
	draw_rect(Rect2(-6, 40, 12, 2), Color(1.0, 0.84, 0.80, alpha))
	# the moment of connection: a green wash across the window that fades out
	if phase == ANSWERING:
		var flash := 1.0 - clampf(phase_t / ANSWER_TIME, 0.0, 1.0)
		draw_rect(Rect2(-50, -54, 100, 104), Color(0.35, 0.86, 0.46, 0.45 * flash))
	if ws != Vector2.ONE:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if phase == HANGUP:
		_draw_hangup_button()


## The red end-call button: pops up over the window, gets pressed, and the
## window only closes behind it. Sits slightly low so it reads as a control
## laid over the call rather than part of the picture.
func _draw_hangup_button() -> void:
	var fade := clampf(1.0 - (phase_t - HANGUP_PRESS) / 0.26, 0.0, 1.0)
	if fade <= 0.0:
		return
	var pop := clampf(phase_t / 0.13, 0.0, 1.0)
	var s := 1.0 - pow(1.0 - pop, 3.0)
	var pressed: bool = phase_t >= HANGUP_PRESS - 0.09
	if pressed:
		s *= 0.86
	# low in the window, and small enough to leave the friend's face visible —
	# it is a control laid over the call, not a lid slammed on it
	var at := Vector2(0.0, 27.0)
	draw_set_transform(at, 0.0, Vector2(s, s))
	draw_colored_polygon(_disc(Vector2.ZERO, 22.0, 16), Color(0.45, 0.06, 0.07, 0.5 * fade))
	draw_colored_polygon(_disc(Vector2.ZERO, 18.0, 16), Color(0.86, 0.19, 0.18, fade))
	draw_colored_polygon(_disc(Vector2.ZERO, 14.0, 16), Color(0.95, 0.31, 0.28, fade))
	# handset rotated the way an end-call icon always is
	draw_set_transform(at, 2.36, Vector2(s, s))
	draw_rect(Rect2(-8.0, -3.0, 16.0, 5.0), Color(1.0, 0.94, 0.93, fade))
	draw_rect(Rect2(-9.5, -1.5, 5.0, 7.0), Color(1.0, 0.94, 0.93, fade))
	draw_rect(Rect2(4.5, -1.5, 5.0, 7.0), Color(1.0, 0.94, 0.93, fade))
	# a white flash on the press itself
	if pressed and phase_t < HANGUP_PRESS + 0.07:
		draw_set_transform(at, 0.0, Vector2(s, s))
		draw_colored_polygon(_disc(Vector2.ZERO, 18.0, 16),
				Color(1.0, 0.96, 0.94, 0.5 * fade))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Window scale through the connect and the hang-up. ANSWERING grows out of
## the ringing pill's footprint (92x52 vs the live window's 100x104); HANGUP
## squashes vertically to a closing line.
func _window_scale() -> Vector2:
	if phase == ANSWERING:
		var k := clampf(phase_t / ANSWER_TIME, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 3.0)
		return Vector2(lerpf(0.9, 1.0, e), lerpf(0.5, 1.0, e))
	if phase == HANGUP:
		var k := _closing()
		return Vector2(lerpf(1.0, 0.82, k), lerpf(1.0, 0.1, k))
	return Vector2.ONE


## The incoming-call pill: a compact card with the caller's thumbnail, a
## shaking handset and ")))" ring waves pulsing out of it. Blocks and lines
## only, for the same renderer reasons as the live window above.
func _draw_ringing(a: float) -> void:
	var ring := fmod(t * 2.2, 1.0)
	var shake := sin(t * 26.0) * 2.0
	draw_rect(Rect2(-43, -25, 92, 52), Color(0.02, 0.08, 0.12, 0.32 * a))
	draw_rect(Rect2(-46, -28, 92, 52), Color(0.06, 0.20, 0.27, 0.96 * a))
	draw_rect(Rect2(-46, -28, 92, 4), Color(0.43, 0.88, 0.86, a))
	draw_rect(Rect2(-46, 20, 92, 4), Color(0.43, 0.88, 0.86, a))
	draw_rect(Rect2(-46, -28, 4, 52), Color(0.43, 0.88, 0.86, a))
	draw_rect(Rect2(42, -28, 4, 52), Color(0.43, 0.88, 0.86, a))
	# caller thumbnail: the same warm face and orange hoodie as the live window
	draw_rect(Rect2(-38, -19, 20, 15), Color(0.93, 0.66, 0.46, a))
	draw_rect(Rect2(-38, -21, 20, 5), Color(0.16, 0.12, 0.11, a))
	draw_rect(Rect2(-40, -3, 24, 15), Color(0.91, 0.42, 0.24, a))
	# a name bar and a status line stand in for text at this size
	draw_rect(Rect2(-11, -17, 32, 6), Color(0.85, 0.94, 0.95, 0.9 * a))
	draw_rect(Rect2(-11, -7, 20, 4), Color(0.55, 0.75, 0.80, 0.8 * a))
	# handset, rattling in its cradle
	var hx := 24.0
	draw_rect(Rect2(hx - 7, 2 + shake, 14, 5), Color(0.35, 0.86, 0.46, a))
	draw_rect(Rect2(hx - 8, 5 + shake, 5, 8), Color(0.35, 0.86, 0.46, a))
	draw_rect(Rect2(hx + 3, 5 + shake, 5, 8), Color(0.35, 0.86, 0.46, a))
	for i in range(3):
		var q := fmod(ring + float(i) * 0.33, 1.0)
		var r := 9.0 + 15.0 * q
		draw_polyline(PackedVector2Array([
			Vector2(hx + r * 0.55, 4.0 - r * 0.55 + shake),
			Vector2(hx + r, 5.0 + shake),
			Vector2(hx + r * 0.55, 6.0 + r * 0.55 + shake),
		]), Color(0.35, 0.86, 0.46, (1.0 - q) * a), 2.5, true)


func _draw_throw(progress: float) -> void:
	var p := clampf(progress, 0.0, 1.0)
	var from := Vector2(32, 8)
	var to := to_local(beam_to)
	var control := (from + to) * 0.5 + Vector2(0, -105)
	var pos := _bezier(from, control, to, p)
	var prev := _bezier(from, control, to, maxf(0.0, p - 0.07))

	# Pale motion trail along the last section of the arc.
	for i in range(1, 4):
		var q := maxf(0.0, p - float(i) * 0.06)
		var trail := _bezier(from, control, to, q)
		draw_colored_polygon(_disc(trail, 5.0 - float(i), 8),
				Color(1.0, 0.91, 0.67, 0.45 / float(i)))

	# Unbranded gold can with a pale lid and a simple white label.
	var angle := (pos - prev).angle() + p * TAU * 1.4
	draw_set_transform(pos, angle, Vector2.ONE)
	draw_rect(Rect2(-7, -13, 14, 26), Color("e8a93f"))
	draw_rect(Rect2(-7, -13, 14, 4), Color("fff2d3"))
	draw_rect(Rect2(-7, 9, 14, 4), Color("b97828"))
	draw_rect(Rect2(-5, -4, 10, 7), Color("fff2d3"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Foam pop starts just before impact, while the notification is still in its
	# squash-fade, so the throw visibly causes the removal.
	if p > 0.58:
		var burst := (p - 0.58) / 0.42
		for i in range(6):
			var a := TAU * float(i) / 6.0
			var edge := to + Vector2(cos(a), sin(a)) * (15.0 + 25.0 * burst)
			draw_line(to, edge, Color(1.0, 0.95, 0.78, 0.9 - 0.4 * burst), 4.0)
			draw_colored_polygon(_disc(edge, 4.0, 8),
					Color(1.0, 0.98, 0.88, 0.85 - 0.4 * burst))


func _bezier(a: Vector2, control: Vector2, b: Vector2, p: float) -> Vector2:
	var inv := 1.0 - p
	return inv * inv * a + 2.0 * inv * p * control + p * p * b


func _disc(center: Vector2, radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		points.append(center + Vector2(cos(a), sin(a)) * radius)
	return points
