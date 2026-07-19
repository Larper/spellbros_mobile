class_name StarPickup
extends Area2D

## Star of Levity: grants ONE stored mid-air jump (no stacking, no timer).
## Tap to jump while airborne to spend it. Sparkles orbit the wizard
## while the charge is held, so you always know you have it.

var t := randf() * TAU
var collected := false


func _init() -> void:
	collision_layer = 8
	collision_mask = 2
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 36.0
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
	p.air_jumps = 1
	var main = get_tree().get_first_node_in_group("main")
	if main:
		main.audio.play("pickup")
		main.float_text(global_position, "AIR JUMP!", Color("ffd75e"))
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(2.0, 2.0), 0.15)
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(queue_free)


func _draw() -> void:
	var bob := sin(t * 2.4) * 5.0
	draw_circle(Vector2(0.0, bob), 34.0, Color(1.0, 0.85, 0.3, 0.14))
	var pts := PackedVector2Array()
	for i in range(10):
		var r := 26.0 if i % 2 == 0 else 11.0
		var a := -PI * 0.5 + TAU * float(i) / 10.0 + sin(t * 1.7) * 0.25
		pts.append(Vector2(cos(a), sin(a)) * r + Vector2(0.0, bob))
	draw_colored_polygon(pts, Color("ffd75e"))
	draw_circle(Vector2(0.0, bob), 6.0, Color("fff6d8"))
