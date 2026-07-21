class_name BuiltPlatform
extends StaticBody2D

## A conjured light-bridge. One-way (jump up through it), crumbles after
## LIFETIME seconds with a blink warning. Collision is full-size instantly;
## only the visual scales in, so a panic-build under your feet still saves you.
## During the SPRINGS level (see Main._try_build) every build comes out as a
## green SPRING pad that launches the player ~1.6x jump height on landing.

const SIZE := Vector2(240.0, 24.0)
const BLINK_WINDOW := 1.2  # blink warning starts this long before crumbling

var lifetime := 4.0  # Main shortens this late-game (see Main.platform_life_for)
var age := 0.0
var visual_scale := 0.2
var bouncy := false
var solid := false  # FLIPSIDE: landable from both gravity directions
var lit := false    # UMBRA: built platforms are lanterns

var _cs: CollisionShape2D


func _init() -> void:
	collision_layer = 1
	collision_mask = 0
	_cs = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = SIZE
	_cs.shape = rect
	_cs.one_way_collision = true
	_cs.one_way_collision_margin = 24.0
	add_child(_cs)


func _ready() -> void:
	if solid:
		_cs.one_way_collision = false
	if lit:
		# UMBRA lantern: out-shines the wizard's own halo — thrown ahead,
		# a build reveals the next stretch of the way
		add_child(PsyTheme.make_light(420.0, 1.2))
	var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "visual_scale", 1.0, 0.18)


func _process(delta: float) -> void:
	age += delta
	if age >= lifetime:
		queue_free()
		return
	var blink_at := lifetime - BLINK_WINDOW
	if age >= blink_at:
		modulate.a = 0.45 + 0.4 * absf(sin((age - blink_at) * 14.0))
	queue_redraw()


func _draw() -> void:
	var s := SIZE * visual_scale
	var glow := Color(0.3, 0.9, 0.55, 0.22) if bouncy else Color(1.0, 0.72, 0.28, 0.18)
	var body := Color("61c68b") if bouncy else Color("f4d58d")
	var edge := Color("d9ffe7") if bouncy else Color("fff4d0")
	# soft glow
	draw_rect(Rect2(-s * 0.5 - Vector2(5, 5), s + Vector2(10, 10)), glow)
	# A temporary sticky-note/crosswalk laid into the route.
	draw_rect(Rect2(-s * 0.5, s), body)
	# bright top edge and printed guide lines
	draw_rect(Rect2(-s.x * 0.5, -s.y * 0.5, s.x, 5.0 * visual_scale), edge)
	if not bouncy:
		for i in range(4):
			var lx := (-72.0 + float(i) * 48.0) * visual_scale
			draw_rect(Rect2(lx, -5.0 * visual_scale,
					26.0 * visual_scale, 8.0 * visual_scale), Color("c98c4a"))
	if bouncy:
		# Green transit chevrons retain the spring-pad affordance.
		for i in range(3):
			var cx := (-60.0 + 60.0 * float(i)) * visual_scale
			draw_polyline(PackedVector2Array([
				Vector2(cx - 14.0, 4.0), Vector2(cx, -8.0), Vector2(cx + 14.0, 4.0),
			]), Color(0.06, 0.35, 0.15, 0.95), 5.0)
