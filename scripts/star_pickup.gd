class_name StarPickup
extends Area2D

## Double Jump pickup: grants ONE stored mid-air jump (no stacking, no timer).
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
	p.double_jumps = 1
	p.refresh_powerup_visuals()
	# the star hangs at jump-apex height, so it is ALWAYS taken mid-air: a
	# tap still buffered from the way up would spend the fresh charge on
	# this very physics frame — the player never even sees the held orbs.
	# Spending the star must take a NEW tap.
	p.jump_buffer = 0.0
	var main = get_tree().get_first_node_in_group("main")
	if main:
		main.audio.play("pickup")
		main.float_text(global_position, "DOUBLE JUMP!", Color("ffd75e"))
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(2.0, 2.0), 0.15)
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(queue_free)


func _draw() -> void:
	var bob := sin(t * 2.4) * 5.0
	draw_circle(Vector2(0.0, bob), 34.0, Color(1.0, 0.85, 0.3, 0.14))
	# Golden running shoe = one stored double jump.
	var shoe := PackedVector2Array([
		Vector2(-25, -8 + bob), Vector2(-5, -12 + bob), Vector2(3, 2 + bob),
		Vector2(25, 8 + bob), Vector2(24, 18 + bob), Vector2(-20, 18 + bob),
		Vector2(-28, 9 + bob),
	])
	draw_colored_polygon(shoe, Color("f4c64e"))
	draw_line(Vector2(-21, 19 + bob), Vector2(25, 19 + bob), Color("fff4c2"), 5.0)
	for i in range(3):
		draw_line(Vector2(-5 + i * 7, 1 + bob), Vector2(2 + i * 7, -1 + bob),
				Color("fff4c2"), 2.5)
