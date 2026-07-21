class_name ManaCrystal
extends Area2D

## Coffee/energy pickup. Overlap with the player collects it (+amount).
## amount > 1 draws a larger takeaway cup (SPRINGS: +3, pays pad tolls).

var t := randf() * TAU
var collected := false
var lit := false  # UMBRA: crystals beacon through the dark
var amount := 1


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
	if lit:
		add_child(PsyTheme.make_light(260.0, 0.9))


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	var p := body as Player
	if p == null or p.dead:
		return
	collect()


## Shared collection path — the player body via signal, or the SPELLBROS
## echo brother directly (he's a spirit; physics can't see him).
func collect() -> void:
	if collected:
		return
	collected = true
	set_deferred("monitoring", false)
	var main = get_tree().get_first_node_in_group("main")
	if main:
		main.add_coin(amount)
		if amount > 1:
			main.float_text(global_position, "+%d" % amount, Color("ffb14d"))
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.8, 1.8), 0.15)
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(queue_free)


func _draw() -> void:
	# A small coffee break is ordinary, instantly legible, and preserves the
	# exact same collision/economy as the old spinning crystal.
	var big := amount > 1
	var bob := sin(t * 2.4) * 4.0
	var halo := Color(1.0, 0.68, 0.25, 0.18) if big else Color(0.38, 0.84, 0.88, 0.13)
	draw_circle(Vector2(0.0, bob), 37.0 if big else 31.0, halo)
	if big:
		# Takeaway cup: the rare +3 pickup.
		draw_colored_polygon(PackedVector2Array([
			Vector2(-17, -17 + bob), Vector2(17, -17 + bob),
			Vector2(13, 22 + bob), Vector2(-13, 22 + bob),
		]), Color("ee8f45"))
		draw_rect(Rect2(-20, -22 + bob, 40, 8), Color("fff0cf"))
		draw_rect(Rect2(-9, -2 + bob, 18, 6), Color("ffe1a6"))
	else:
		# Reusable mug: the common +1 pickup.
		# Draw the handle first as a chunky C; the Mobile renderer was dropping
		# arcs after the cup body and leaving only a blue square.
		draw_colored_polygon(PackedVector2Array([
			Vector2(10, -7 + bob), Vector2(27, -7 + bob),
			Vector2(32, -2 + bob), Vector2(32, 10 + bob),
			Vector2(27, 16 + bob), Vector2(10, 16 + bob),
			Vector2(10, 10 + bob), Vector2(24, 10 + bob),
			Vector2(26, 7 + bob), Vector2(26, 1 + bob),
			Vector2(23, -1 + bob), Vector2(10, -1 + bob),
		]), Color("bdecef"))
		draw_colored_polygon(PackedVector2Array([
			Vector2(-18, -12 + bob), Vector2(15, -12 + bob),
			Vector2(12, 18 + bob), Vector2(-15, 18 + bob),
		]), Color("58b8bf"))
		draw_rect(Rect2(-19, -14 + bob, 35, 6), Color("e8fbf7"))
		draw_rect(Rect2(-11, 0 + bob, 17, 4), Color("d6f3ee"))
	# Steam makes both variants read as coffee rather than a generic token.
	draw_polyline(PackedVector2Array([
		Vector2(-10, -20 + bob), Vector2(-14, -25 + bob),
		Vector2(-10, -30 + bob), Vector2(-13, -35 + bob),
	]), Color(1, 1, 1, 0.65), 2.5, true)
	draw_polyline(PackedVector2Array([
		Vector2(5, -22 + bob), Vector2(9, -27 + bob),
		Vector2(5, -32 + bob), Vector2(9, -37 + bob),
	]), Color(1, 1, 1, 0.5), 2.5, true)
