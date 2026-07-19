class_name ManaCrystal
extends Area2D

## Spinning mana diamond. Overlap with the player collects it (+1 coin).

var t := randf() * TAU
var collected := false
var lit := false  # UMBRA: crystals beacon through the dark


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
		main.add_coin()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.8, 1.8), 0.15)
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(queue_free)


func _draw() -> void:
	# spin illusion: width oscillates
	var hw := 16.0 * (0.35 + 0.65 * absf(sin(t * 3.0)))
	draw_circle(Vector2.ZERO, 30.0, Color(0.32, 0.9, 1.0, 0.10))
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -24), Vector2(hw, 0), Vector2(0, 24), Vector2(-hw, 0),
	]), Color("52e5ff"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -12), Vector2(hw * 0.5, 0), Vector2(0, 12), Vector2(-hw * 0.5, 0),
	]), Color("ccf6ff"))
