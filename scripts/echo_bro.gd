class_name EchoBro
extends Node2D

## SPELLBROS level (Neven's spec, round 2 — the mirror echo read as silly):
## the crimson spellbrother hovers over the wizard's shoulder and BURNS the
## blob ahead, spending 1 shared mana per burn. While the pool lasts the
## gauntlets part before you; when it runs dry he fades to an ember and the
## blob lines must be stomped by hand until the fragment arcs above them
## refill the mana. His glow is the pool readout.

const HOVER := Vector2(14.0, -238.0)
const BURN_MIN_X := 40.0    # never torches something already underfoot
const BURN_MAX_X := 540.0   # roughly the lead the camera shows ahead
const BURN_MAX_DY := 430.0
const BURN_COST := 1
const BURN_COOLDOWN := 0.3  # one blob per beat: a swarm drains the pool visibly

var active := false
var t := randf() * TAU
var burn_cd := 0.0
var beam_t := 0.0
var beam_to := Vector2.ZERO


func _process(delta: float) -> void:
	t += delta
	burn_cd -= delta
	beam_t -= delta
	visible = active
	if not active:
		return
	var main = get_tree().get_first_node_in_group("main")
	if main == null or main.player == null:
		return
	var p = main.player
	global_position = p.global_position + HOVER + Vector2(0.0, sin(t * 2.4) * 10.0)
	queue_redraw()
	if p.dead or main.game_over or burn_cd > 0.0 or main.coins < BURN_COST:
		return
	for n in get_tree().get_nodes_in_group("blobs"):
		var b := n as SpikeBlob
		if b == null or not is_instance_valid(b) or b.dying:
			continue
		var dx: float = b.global_position.x - p.global_position.x
		if dx < BURN_MIN_X or dx > BURN_MAX_X:
			continue
		if absf(b.global_position.y - p.global_position.y) > BURN_MAX_DY:
			continue
		main.coins -= BURN_COST
		main.hud.update_coins(main.coins)
		main.audio.play("squish")
		main.float_text(b.global_position, "-1", Color("ff5566"))
		beam_to = b.global_position
		beam_t = 0.16
		b._pop()
		burn_cd = BURN_COOLDOWN
		break


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
