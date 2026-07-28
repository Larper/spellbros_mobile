class_name EchoBro
extends Node2D

## FRIENDS level helper. The friend lives in a floating video-call bubble, so
## following above the commuter reads as a call overlay rather than a hovering
## body. A would-be-lethal notification costs one energy and is intercepted by
## a tossed, unbranded drink can.

const HOVER := Vector2(-72.0, -158.0)
const BURN_COST := 1
const THROW_TIME := 0.22

var active := false
var t := randf() * TAU
var beam_t := 0.0  # kept as the throw countdown for test/backward compatibility
var beam_to := Vector2.ZERO


## The follow runs on the PHYSICS tick, not the frame: physics interpolation
## smooths every other moving node from its physics transforms, so a node that
## repositioned itself per frame would be the one thing visibly lagging the
## commuter it is supposed to hover over.
func _physics_process(delta: float) -> void:
	t += delta
	beam_t = maxf(0.0, beam_t - delta)
	visible = active
	if not active:
		return
	var main = get_tree().get_first_node_in_group("main")
	if main == null or main.player == null:
		return
	global_position = main.player.global_position + HOVER \
			+ Vector2(0.0, sin(t * 2.4) * 5.0)
	queue_redraw()


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
	if not active:
		return
	var main = get_tree().get_first_node_in_group("main")
	var fueled: bool = main != null and main.coins >= BURN_COST
	var alpha := (0.96 if fueled else 0.40) + 0.04 * sin(t * 5.0)

	# The can travels on a short readable arc. Drawing it behind the call bubble
	# makes it look as if the friend throws it out of the video window.
	if beam_t > 0.0:
		_draw_throw(1.0 - beam_t / THROW_TIME)

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
