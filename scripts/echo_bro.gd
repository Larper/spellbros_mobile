class_name EchoBro
extends Node2D

## SPELLBROS level (Neven's spec, round 3): the crimson spellbrother hovers
## over the wizard's shoulder as a MANA-FUELED SHIELD. He never hunts —
## stomps are the player's income and he must not touch them — but a blob
## contact that WOULD KILL is burned out of existence for 1 mana. Broke
## means unprotected: his glow is the pool readout, bright while a burn is
## affordable, ember-faint when the next mistake is lethal.

const HOVER := Vector2(14.0, -238.0)
const BURN_COST := 1

var active := false
var t := randf() * TAU
var beam_t := 0.0
var beam_to := Vector2.ZERO


func _process(delta: float) -> void:
	t += delta
	beam_t -= delta
	visible = active
	if not active:
		return
	var main = get_tree().get_first_node_in_group("main")
	if main == null or main.player == null:
		return
	global_position = main.player.global_position + HOVER + Vector2(0.0, sin(t * 2.4) * 10.0)
	queue_redraw()


## Called by SpikeBlob on a would-be-lethal touch. True = the brother
## burns the blob instead, spending BURN_COST from the shared pool.
func try_guard(at: Vector2) -> bool:
	if not active:
		return false
	var main = get_tree().get_first_node_in_group("main")
	if main == null or main.coins < BURN_COST:
		return false
	main.coins -= BURN_COST
	main.hud.update_coins(main.coins)
	main.audio.play("squish")
	main.float_text(at, "-1", Color("ff5566"))
	beam_to = at
	beam_t = 0.16
	return true


func _draw() -> void:
	if not active:
		return
	var main = get_tree().get_first_node_in_group("main")
	var fueled: bool = main != null and main.coins >= BURN_COST
	# ember-faint with an empty pool: his glow IS the mana readout
	var a := (0.95 if fueled else 0.35) + 0.05 * sin(t * 5.0)
	if beam_t > 0.0:
		var to := to_local(beam_to)
		draw_line(Vector2(10.0, -10.0), to, Color(1.0, 0.35, 0.3, 0.8), 7.0)
		draw_line(Vector2(10.0, -10.0), to, Color(1.0, 0.8, 0.4, 0.9), 3.0)
	# the wizard's silhouette in crimson
	var robe := PackedVector2Array([
		Vector2(-26, 40), Vector2(26, 40), Vector2(14, -6), Vector2(-14, -6),
	])
	draw_colored_polygon(robe, Color(0.82, 0.2, 0.3, a))
	draw_circle(Vector2(0, -16), 16.0, Color(1.0, 0.78, 0.66, a))
	var hat := PackedVector2Array([
		Vector2(-20, -24), Vector2(20, -24), Vector2(2, -62),
	])
	draw_colored_polygon(hat, Color(0.66, 0.12, 0.24, a))
	draw_rect(Rect2(-24, -28, 48, 7), Color(0.5, 0.08, 0.2, a))
	draw_circle(Vector2(8, -16), 3.4, Color(0.15, 0.03, 0.06, a))
