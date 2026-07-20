class_name SpikeBlob
extends Area2D

## Stationary blob enemy. Stomp from above kills it (player bounces and
## earns +1 mana bounty); touching it from the side or below kills the
## player. Blobs used to patrol, but static enemies read far better at
## late-game run speeds (Neven's call) — and they're plain circles now,
## no spiky heads.

## Aim-assist window: natural contact width is ~60 px (28 half-body +
## 32 radius); anything inside ASSIST_HALF_W while falling past the crown
## band still counts as a stomp.
const ASSIST_HALF_W := 95.0
const ASSIST_TOP := 44.0
const ASSIST_BOT := 8.0

var speed := 130.0  # kept for spawner compatibility; static blobs ignore it
var left_x := 0.0
var right_x := 0.0
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
	if not dying:
		_stomp_assist()


## Aim assist (Neven): the miss that hurt in BLOB BRIDGES was sailing just
## past a blob's edge and falling into the gap below. While the wizard is
## FALLING and his feet sweep the band around the blob's crown, a slight
## horizontal miss still registers as a stomp. Rising and side touches
## stay lethal — the forgiveness is in the aim, not the timing.
func _stomp_assist() -> void:
	var m = get_tree().get_first_node_in_group("main")
	if m == null:
		return
	var p: Player = m.player
	if p == null or p.dead or p.velocity.y < 120.0:
		return
	if absf(p.global_position.x - global_position.x) > ASSIST_HALF_W:
		return
	var feet: float = p.global_position.y + Player.BODY_H * 0.5
	if feet > global_position.y - ASSIST_TOP and feet < global_position.y + ASSIST_BOT:
		_squash(p)


func _on_body_entered(body: Node2D) -> void:
	if dying:
		return
	var p := body as Player
	if p == null or p.dead:
		return
	# Direct contact: a stomp only while FALLING with the feet above the
	# blob's midline — side and rising touches kill. Near-miss forgiveness
	# lives in _stomp_assist(), not here (the old any-contact-from-above
	# rule made blobs feel like trampolines).
	var feet: float = p.global_position.y + Player.BODY_H * 0.5
	var stomped: bool = p.velocity.y > 0.0 and feet < global_position.y + 10.0
	if stomped:
		_squash(p)
	else:
		_lethal(p)


## A touch that would kill: the purple shield absorbs one such hit — the
## bubble pops, the blob pops with it (no bounce, no bounty), the run lives.
func _lethal(p: Player) -> void:
	var main = get_tree().get_first_node_in_group("main")
	# SPELLBROS: the echo brother intercepts one hit per recharge
	if main and main.bro and main.bro.try_guard(global_position):
		_pop()
		return
	if p.shielded:
		p.break_shield()
		if main:
			main.audio.play("squish")
			main.float_text(global_position, "SHIELD SPENT", Color("b98cff"))
		_pop()
		return
	p.die()


func _squash(p: Player) -> void:
	p.bounce()
	var main = get_tree().get_first_node_in_group("main")
	if main:
		main.audio.play("squish")
		# Stomp bounty: enemies count against the same entity budget as
		# crystals, so a brave stomp IS the chunk's mana income.
		main.add_coin()
		main.float_text(global_position, "+1", Color("52e5ff"))
	_pop()


## Shared death visual: squash-fade, collisions off.
func _pop() -> void:
	dying = true
	set_deferred("monitoring", false)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.5, 0.15), 0.12)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.18)
	tw.tween_callback(queue_free)


func _draw() -> void:
	var squish := 1.0 + sin(t * 6.0) * 0.06
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(2.0 - squish, squish))
	# soft warning glow, then the body — circles only
	draw_circle(Vector2.ZERO, 36.0, Color(1.0, 0.33, 0.47, 0.16))
	draw_circle(Vector2.ZERO, 30.0, Color("ff5577"))
	# eyes, front-facing
	draw_circle(Vector2(-9, -4), 6.0, Color.WHITE)
	draw_circle(Vector2(9, -4), 6.0, Color.WHITE)
	draw_circle(Vector2(-9, -4), 3.0, Color("1c1430"))
	draw_circle(Vector2(9, -4), 3.0, Color("1c1430"))
