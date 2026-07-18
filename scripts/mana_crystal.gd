class_name ManaCrystal
extends Area2D

## Spinning mana diamond. Overlap with the player collects it (+value mana).
## Rare golden variant (see make_golden) is worth 3.

var t := randf() * TAU
var collected := false
var value := 1


func make_golden() -> void:
	value = 3


func _init() -> void:
	collision_layer = 8
	collision_mask = 2
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 34.0
	cs.shape = circle
	add_child(cs)


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if collected:
		return
	var p := body as Player
	if p == null or p.dead:
		return
	collected = true
	set_deferred("monitoring", false)
	var main = get_tree().get_first_node_in_group("main")
	if main:
		main.add_coin(value)
		if value > 1:
			main.float_text(global_position, "+%d" % value, Color("ffd75e"))
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.8, 1.8), 0.15)
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(queue_free)


func _draw() -> void:
	var golden := value > 1
	var k := 1.25 if golden else 1.0  # golden runs a little bigger
	# spin illusion: width oscillates
	var hw := 16.0 * k * (0.35 + 0.65 * absf(sin(t * 3.0)))
	var glow := Color(1.0, 0.85, 0.3, 0.16) if golden else Color(0.32, 0.9, 1.0, 0.10)
	var body := Color("ffc832") if golden else Color("52e5ff")
	var core := Color("fff3c4") if golden else Color("ccf6ff")
	draw_circle(Vector2.ZERO, 30.0 * k, glow)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -24 * k), Vector2(hw, 0), Vector2(0, 24 * k), Vector2(-hw, 0),
	]), body)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -12 * k), Vector2(hw * 0.5, 0), Vector2(0, 12 * k), Vector2(-hw * 0.5, 0),
	]), core)
	if golden:
		# four sparkle ticks orbiting the gem
		for i in range(4):
			var a := t * 2.0 + TAU * 0.25 * float(i)
			var p := Vector2(cos(a), sin(a)) * 40.0
			draw_circle(p, 3.0, Color(1.0, 0.95, 0.6, 0.85))
