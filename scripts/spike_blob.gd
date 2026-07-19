class_name SpikeBlob
extends Area2D

## Patrolling enemy. Stomp from above kills it (player bounces and earns
## +1 mana bounty); touching it from the side or below kills the player.

var speed := 130.0  # set by TerrainSpawner.enemy_speed_for(); ramps late-game
var left_x := 0.0
var right_x := 0.0
var dir := -1.0
var t := randf() * TAU
var dying := false


func _init(l: float, r: float) -> void:
	left_x = l
	right_x = r
	collision_layer = 4
	collision_mask = 2
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 32.0
	cs.shape = circle
	add_child(cs)


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	t += delta
	queue_redraw()
	if dying:
		return
	position.x += speed * dir * delta
	if position.x < left_x:
		dir = 1.0
	elif position.x > right_x:
		dir = -1.0


func _on_body_entered(body: Node2D) -> void:
	if dying:
		return
	var p := body as Player
	if p == null or p.dead:
		return
	var stomped: bool = p.velocity.y > 40.0 and p.global_position.y < global_position.y - 10.0
	if stomped:
		_squash(p)
	else:
		p.die()


func _squash(p: Player) -> void:
	dying = true
	set_deferred("monitoring", false)
	p.bounce()
	var main = get_tree().get_first_node_in_group("main")
	if main:
		main.audio.play("squish")
		# Stomp bounty: enemies count against the same entity budget as
		# crystals, so a brave stomp IS the chunk's mana income.
		main.add_coin()
		main.float_text(global_position, "+1", Color("52e5ff"))
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.5, 0.15), 0.12)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.18)
	tw.tween_callback(queue_free)


func _draw() -> void:
	var squish := 1.0 + sin(t * 6.0) * 0.06
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(2.0 - squish, squish))
	# spikes across the top
	for i in range(5):
		var sx := -24.0 + 12.0 * float(i)
		draw_colored_polygon(PackedVector2Array([
			Vector2(sx - 6, -16), Vector2(sx + 6, -16), Vector2(sx, -40),
		]), Color("d63d68"))
	# body
	draw_circle(Vector2.ZERO, 30.0, Color("ff5577"))
	# eyes track walk direction
	draw_circle(Vector2(-9, -4), 6.0, Color.WHITE)
	draw_circle(Vector2(9, -4), 6.0, Color.WHITE)
	draw_circle(Vector2(-9 + 2.5 * dir, -4), 3.0, Color("1c1430"))
	draw_circle(Vector2(9 + 2.5 * dir, -4), 3.0, Color("1c1430"))
