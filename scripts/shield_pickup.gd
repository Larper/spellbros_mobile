class_name ShieldPickup
extends Area2D

## Purple shield orb (FOUNDATIONS): one blob mistake forgiven. While held,
## a violet bubble rings the wizard; a lethal blob touch pops the bubble
## and the blob instead of you. No stacking, no timer.

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
	p.shielded = true
	p.refresh_powerup_visuals()
	var main = get_tree().get_first_node_in_group("main")
	if main:
		main.audio.play("pickup")
		main.float_text(global_position, "FOCUS MODE!", Color("7bd5d6"))
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(2.0, 2.0), 0.15)
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(queue_free)


func _draw() -> void:
	var bob := sin(t * 2.4) * 5.0
	# Noise-cancelling headphones: one interruption can be ignored.
	draw_circle(Vector2(0.0, bob), 35.0, Color(0.3, 0.82, 0.84, 0.14))
	draw_arc(Vector2(0.0, 2 + bob), 23.0, PI, TAU, 24, Color("7bd5d6"), 7.0)
	draw_rect(Rect2(-28, -1 + bob, 10, 24), Color("31949a"))
	draw_rect(Rect2(18, -1 + bob, 10, 24), Color("31949a"))
	draw_circle(Vector2(-23, 11 + bob), 7.0, Color("d9ffff"))
	draw_circle(Vector2(23, 11 + bob), 7.0, Color("d9ffff"))
