class_name BuiltPlatform
extends StaticBody2D

## A conjured light-bridge. One-way (jump up through it), crumbles after
## LIFETIME seconds with a blink warning. Collision is full-size instantly;
## only the visual scales in, so a panic-build under your feet still saves you.

const SIZE := Vector2(240.0, 24.0)
const BLINK_WINDOW := 1.2  # blink warning starts this long before crumbling

var lifetime := 4.0  # Main shortens this late-game (see Main.platform_life_for)
var age := 0.0
var visual_scale := 0.2


func _init() -> void:
	collision_layer = 1
	collision_mask = 0
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = SIZE
	cs.shape = rect
	cs.one_way_collision = true
	cs.one_way_collision_margin = 24.0
	add_child(cs)


func _ready() -> void:
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
	var th := GameTheme.active
	var s := SIZE * visual_scale
	# soft magic aura in the theme's second accent
	draw_rect(Rect2(-s * 0.5 - Vector2(5, 5), s + Vector2(10, 10)),
			Color(th.color(GameTheme.C_ACCENT2), 0.22))
	# body
	draw_rect(Rect2(-s * 0.5, s), Color(th.color(GameTheme.C_PLATFORM), 0.92))
	# bright top edge
	draw_rect(Rect2(-s.x * 0.5, -s.y * 0.5, s.x, 5.0 * visual_scale),
			Color(th.color(GameTheme.C_PLATFORM_EDGE), 0.95))
