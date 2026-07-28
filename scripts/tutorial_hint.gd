class_name TutorialHint
extends Node2D

## The opening instructions, PLAYED rather than written. One line of text
## asking someone to map "left half" and "right half" onto two different verbs
## is a lot to read while already running; this shows the thumb doing it.
##
## Two beats on a loop:
##   LEFT  — an arrow left of the commuter, a thumb swings in and taps, he jumps
##   RIGHT — an arrow right of him, a thumb taps, a step appears and he hops on
##
## Screen space, on the HUD layer, so it is unaffected by the camera. Drawn
## with the same flat blocks as the rest of the game; the caption uses the
## fallback font so it needs no theme wiring.

const BEAT := 2.9              # seconds per beat
const CYCLE := BEAT * 2.0
const TAP_AT := 1.15           # when the thumb makes contact, within a beat
const REACT := 0.85            # how long the commuter's reaction runs after it
const LOOPS := 2.0             # beats through before it bows out
const FADE := 1.2

## Panel spans y -110..170 in local space and everything lives inside it: the
## caption up top, the pavement across the middle, and enough room below for
## the thumb to swing up from off-panel without dangling into the live world.
const PANEL := Rect2(-284.0, -110.0, 568.0, 280.0)
const CAPTION_W := 528.0
const GROUND_Y := 44.0
const WIZ_X := -34.0
const REACH := 122.0           # how far left/right of him the thumb taps
const THUMB_REST := 120.0      # below the pavement at rest
const THUMB_TAP := 12.0        # below it at full contact

var t := 0.0


func _ready() -> void:
	z_index = 5
	# pausable, unlike the HUD it hangs off: the demo must not play itself out
	# behind the level menu while nobody is running yet
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _process(delta: float) -> void:
	t += delta
	# it lives on a CanvasLayer, so this is screen space — parked low and
	# centred, clear of the score and energy readouts up top
	var vp := get_viewport_rect().size
	position = Vector2(vp.x * 0.5, vp.y - 232.0)
	queue_redraw()
	if t > CYCLE * LOOPS + FADE:
		queue_free()


## 1 while playing, ramping to 0 over the last FADE seconds.
func _alpha() -> float:
	var live := CYCLE * LOOPS
	if t <= live:
		return minf(t / 0.4, 1.0)  # ease in so it does not pop
	return clampf(1.0 - (t - live) / FADE, 0.0, 1.0)


func _draw() -> void:
	var a := _alpha()
	if a <= 0.0:
		return
	var jump: bool = fmod(t, CYCLE) < BEAT     # beat 0 = jump, beat 1 = build
	var bt := fmod(t, BEAT)
	var tap_x := (WIZ_X - REACH) if jump else (WIZ_X + REACH)

	# an opaque-enough backing that the demo reads as an overlay rather than as
	# something happening in the level behind it
	draw_rect(PANEL, Color(0.03, 0.06, 0.10, 0.94 * a))
	draw_rect(Rect2(PANEL.position.x, PANEL.position.y, PANEL.size.x, 4.0),
			Color(0.43, 0.88, 0.86, 0.6 * a))
	draw_rect(Rect2(PANEL.position.x, PANEL.end.y - 4.0, PANEL.size.x, 4.0),
			Color(0.43, 0.88, 0.86, 0.6 * a))
	# the pavement he is running on
	draw_rect(Rect2(-244.0, GROUND_Y, 488.0, 7.0), Color(0.90, 0.85, 0.74, 0.85 * a))

	# --- the commuter, and whatever the tap did to him ---------------------
	var react := clampf((bt - TAP_AT) / REACT, 0.0, 1.0)
	var acted: bool = bt >= TAP_AT
	var wiz := Vector2(WIZ_X, GROUND_Y)
	if jump:
		# a clean hop in place: up and back down, stopping short of the caption
		if acted:
			wiz.y -= sin(react * PI) * 52.0
	else:
		# the built step appears under the tap, and he runs up onto it
		if acted:
			var pop := clampf(react / 0.28, 0.0, 1.0)
			var pad_w := 92.0 * (1.0 - pow(1.0 - pop, 3.0))
			draw_rect(Rect2(tap_x - pad_w * 0.5, GROUND_Y - 46.0, pad_w, 11.0),
					Color(0.96, 0.84, 0.55, a))
			draw_rect(Rect2(tap_x - pad_w * 0.5, GROUND_Y - 46.0, pad_w, 3.0),
					Color(1.0, 0.96, 0.82, a))
			var hop := clampf((react - 0.3) / 0.7, 0.0, 1.0)
			wiz.x = lerpf(WIZ_X, tap_x, hop)
			wiz.y = GROUND_Y - sin(hop * PI) * 26.0 - 46.0 * hop
	_draw_commuter(wiz, a)

	# --- the arrow, pointing at where the thumb is about to go -------------
	# below the height a built step occupies, above the pavement — an arrow at
	# mid-height ran straight through the pad it had just told you to make
	var pulse := 0.72 + 0.28 * sin(t * 6.0)
	_draw_arrow(WIZ_X + (-38.0 if jump else 38.0), tap_x + (34.0 if jump else -34.0),
			GROUND_Y - 18.0, a * pulse)

	# --- the thumb: swings in, presses, lifts away -------------------------
	var enter := clampf((bt - 0.2) / (TAP_AT - 0.2), 0.0, 1.0)
	var lift := clampf((bt - TAP_AT - 0.45) / 0.5, 0.0, 1.0)
	var rise := (1.0 - (1.0 - enter) * (1.0 - enter)) - lift
	var thumb := Vector2(tap_x, GROUND_Y + lerpf(THUMB_REST, THUMB_TAP, clampf(rise, 0.0, 1.0)))
	var press := 0.0
	if acted and bt < TAP_AT + 0.2:
		press = 1.0 - (bt - TAP_AT) / 0.2
	if rise > 0.01:
		if press > 0.0:
			_draw_ring(Vector2(tap_x, GROUND_Y - 4.0), 14.0 + 40.0 * (1.0 - press),
					Color(1.0, 1.0, 1.0, press * 0.75 * a))
		_draw_thumb(thumb, press, a * minf(rise * 2.0, 1.0))

	# --- caption ------------------------------------------------------------
	var font := ThemeDB.fallback_font
	var caption := "TAP LEFT  ›  JUMP" if jump else "TAP RIGHT  ›  BUILD  (1 energy)"
	draw_string(font, Vector2(-CAPTION_W * 0.5, -74.0), caption,
			HORIZONTAL_ALIGNMENT_CENTER, CAPTION_W, 30,
			Color(1.0, 1.0, 1.0, 0.94 * a))


## The commuter in miniature: the same silhouette as the real one — backpack
## behind, blue jacket, dark hair — at a size that reads inside the panel.
func _draw_commuter(feet: Vector2, a: float) -> void:
	draw_rect(Rect2(feet.x - 17.0, feet.y - 31.0, 8.0, 20.0), Color(0.85, 0.42, 0.29, a))
	draw_rect(Rect2(feet.x - 9.0, feet.y - 48.0, 19.0, 17.0), Color(0.94, 0.74, 0.55, a))
	draw_rect(Rect2(feet.x - 9.0, feet.y - 50.0, 19.0, 7.0), Color(0.25, 0.19, 0.17, a))
	draw_rect(Rect2(feet.x + 4.0, feet.y - 41.0, 4.0, 4.0), Color(0.09, 0.15, 0.20, a))
	draw_rect(Rect2(feet.x - 12.0, feet.y - 32.0, 23.0, 24.0), Color(0.18, 0.50, 0.66, a))
	draw_rect(Rect2(feet.x - 8.0, feet.y - 8.0, 7.0, 9.0), Color(0.15, 0.22, 0.29, a))
	draw_rect(Rect2(feet.x + 2.0, feet.y - 8.0, 7.0, 9.0), Color(0.15, 0.22, 0.29, a))


func _draw_arrow(from_x: float, to_x: float, y: float, a: float) -> void:
	var dir := signf(to_x - from_x)
	draw_rect(Rect2(minf(from_x, to_x), y - 3.0, absf(to_x - from_x), 6.0),
			Color(1.0, 1.0, 1.0, 0.6 * a))
	draw_colored_polygon(PackedVector2Array([
		Vector2(to_x + dir * 17.0, y), Vector2(to_x, y - 14.0), Vector2(to_x, y + 14.0),
	]), Color(1.0, 1.0, 1.0, 0.85 * a))


## A thumb reaching up into the frame. `press` 0..1 squashes the tip the way a
## real one flattens against glass.
func _draw_thumb(at: Vector2, press: float, a: float) -> void:
	var squash := 1.0 - 0.16 * press
	var skin := Color(0.96, 0.78, 0.62, a)
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(-16.0, 8.0 * squash), at + Vector2(-12.0, -14.0 * squash),
		at + Vector2(3.0, -21.0 * squash), at + Vector2(16.0, -8.0 * squash),
		at + Vector2(19.0, 34.0), at + Vector2(-19.0, 40.0),
	]), skin)
	draw_rect(Rect2(at.x - 7.0, at.y - 13.0 * squash, 13.0, 10.0),
			Color(1.0, 0.90, 0.85, a))


## Ring drawn as a closed polyline rather than draw_arc: the Mobile renderer
## has dropped arcs issued after rectangles before (see ManaCrystal).
func _draw_ring(center: Vector2, radius: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(17):
		var ang := TAU * float(i) / 16.0
		pts.append(center + Vector2(cos(ang), sin(ang)) * radius)
	draw_polyline(pts, color, 3.0, true)
