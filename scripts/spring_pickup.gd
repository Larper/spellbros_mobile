class_name SpringPickup
extends Area2D

## Green endgame powerup (>= 300 m): grants SPRING_BUILDS charges — the next
## builds come out as green spring pads (still 1 mana each) that launch the
## player ~1.6x jump height on landing. The HUD counts charges down.

const SPRING_BUILDS := 3

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
	var main = get_tree().get_first_node_in_group("main")
	if main:
		main.add_springs(SPRING_BUILDS)
		main.audio.play("pickup")
		main.float_text(global_position, "SPRING x%d" % SPRING_BUILDS, Color("7dff9a"))
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(2.0, 2.0), 0.15)
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(queue_free)


func _draw() -> void:
	var bob := sin(t * 2.4) * 5.0
	draw_circle(Vector2(0.0, bob), 34.0, Color(0.4, 1.0, 0.5, 0.14))
	# coil: three up-chevrons stacked like a compressed spring
	for i in range(3):
		var cy := bob + 12.0 - 12.0 * float(i) + sin(t * 3.2 + float(i)) * 2.0
		draw_polyline(PackedVector2Array([
			Vector2(-16.0, cy + 8.0), Vector2(0.0, cy - 4.0), Vector2(16.0, cy + 8.0),
		]), Color("7dff9a"), 6.0)
	draw_circle(Vector2(0.0, bob - 18.0), 5.0, Color("d8ffe2"))
