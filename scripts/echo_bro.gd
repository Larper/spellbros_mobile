class_name EchoBro
extends Node2D

## SPELLBROS level: the brother wizard — a cyan spirit echo mirroring the
## player's arc through the camera's center line (you jump down, he jumps
## up). He phases through terrain and enemies and cannot die, but every
## crystal he touches is banked mana you didn't have to detour for:
## steering two arcs with one thumb is the level's skill.

const COLLECT_RADIUS := 70.0

var active := false
var t := 0.0


func _process(delta: float) -> void:
	t += delta
	visible = active
	if not active:
		return
	var main = get_tree().get_first_node_in_group("main")
	if main == null or main.player.dead:
		return
	# mirror the wizard through the camera's horizontal center line
	global_position.x = main.player.global_position.x - 60.0
	global_position.y = 2.0 * main.cam.global_position.y - main.player.global_position.y
	queue_redraw()
	# spirit hands: physics can't see him, so he grabs crystals by distance
	for c in main.spawner.get_children():
		if c is ManaCrystal and not c.collected \
				and c.global_position.distance_to(global_position) < COLLECT_RADIUS:
			c.collect()  # the orange +3 already floats its own text
			if c.amount == 1:
				main.float_text(c.global_position, "+1", Color("7ef2e0"))


func _draw() -> void:
	if not active:
		return
	# translucent cyan echo of the wizard, drawn upside down (he's a mirror)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, -1.0))
	var a := 0.5 + 0.15 * sin(t * 5.0)
	var robe := PackedVector2Array([
		Vector2(-26, 40), Vector2(26, 40), Vector2(14, -6), Vector2(-14, -6),
	])
	draw_colored_polygon(robe, Color(0.35, 0.9, 0.85, a * 0.8))
	draw_circle(Vector2(0, -16), 16.0, Color(0.7, 1.0, 0.95, a * 0.7))
	var hat := PackedVector2Array([
		Vector2(-20, -24), Vector2(20, -24), Vector2(2, -62),
	])
	draw_colored_polygon(hat, Color(0.3, 0.85, 0.8, a * 0.8))
	draw_circle(Vector2(8, -16), 3.4, Color(0.05, 0.2, 0.2, a))
