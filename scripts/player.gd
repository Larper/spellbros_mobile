class_name Player
extends CharacterBody2D

## The auto-running wizard. Forward speed is fed by Main each frame;
## jumping has coyote time + a small input buffer so taps feel forgiving.

signal died
signal jumped
signal sprung

const BODY_W := 56.0
const BODY_H := 80.0
const GRAVITY := 3300.0
const JUMP_VELOCITY := -1170.0
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.12
## Strong enough that bounce + a tap at its apex reaches ~1.1*v — the
## BLOB BRIDGES chain (stomp, tap, stomp across a deck) depends on it.
const STOMP_BOUNCE := -1000.0
const SPRING_LAUNCH := -1500.0  # ~1.6x jump height

var run_speed := 470.0
var dead := false
var coyote := 0.0
var jump_buffer := 0.0
var time_alive := 0.0
var double_jumps := 0  # Star of Levity charge: one stored double jump
var shielded := false  # purple shield orb: absorbs one lethal blob touch
var stomp_jump := false  # stomping an enemy refreshes one jump until landing
var gravity_dir := 1.0  # FLIPSIDE: -1 runs the ceiling; +1 the floor
var flip_cooldown := 0.0
var flip_buffer := 0.0  # taps buffer like jumps: a tap just before landing sticks


func _init() -> void:
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(BODY_W, BODY_H)
	cs.shape = rect
	add_child(cs)


func _physics_process(delta: float) -> void:
	time_alive += delta
	queue_redraw()

	if dead:
		velocity.y += GRAVITY * delta
		global_position += velocity * delta
		rotation += 6.0 * delta
		return

	velocity.x = run_speed
	velocity.y += GRAVITY * delta * gravity_dir
	up_direction = Vector2.UP if gravity_dir > 0.0 else Vector2.DOWN
	flip_cooldown -= delta

	if is_on_floor():
		coyote = COYOTE_TIME
		stomp_jump = false
	else:
		coyote -= delta

	# buffered gravity flip fires on the first grounded frame (FLIPSIDE)
	if flip_buffer > 0.0 and flip_cooldown <= 0.0 \
			and (is_on_floor() or coyote > 0.0):
		flip_buffer = 0.0
		gravity_dir = -gravity_dir
		velocity.y = 0.0
		coyote = 0.0
		flip_cooldown = 0.18
		jumped.emit()
	flip_buffer -= delta

	# the free stomp refresh (or coyote) is consumed before a precious star charge
	if jump_buffer > 0.0 and (coyote > 0.0 or stomp_jump):
		velocity.y = JUMP_VELOCITY * gravity_dir
		coyote = 0.0
		stomp_jump = false
		jump_buffer = 0.0
		jumped.emit()
	elif jump_buffer > 0.0 and double_jumps > 0 and not is_on_floor():
		# spend the Star of Levity charge for a full double jump
		velocity.y = JUMP_VELOCITY * gravity_dir
		double_jumps -= 1
		jump_buffer = 0.0
		jumped.emit()
	jump_buffer -= delta

	move_and_slide()

	# spring pads always launch on landing
	for i in range(get_slide_collision_count()):
		var col := get_slide_collision(i)
		if col.get_normal().y < -0.5 and col.get_collider() is BuiltPlatform \
				and col.get_collider().bouncy:
			velocity.y = SPRING_LAUNCH
			coyote = 0.0
			sprung.emit()
			break


func try_jump() -> void:
	jump_buffer = JUMP_BUFFER


## FLIPSIDE: request a gravity flip. Buffered like a jump (0.12 s), but it
## only EXECUTES from a surface or the coyote window — once airborne the
## wizard is committed until landing, because any true mid-air flip doubles
## as a disguised jump (flip up, flip back = hop over floor gaps without
## ever touching the ceiling). The recovery tool for a bad flip is a BUILD:
## pads are solid in this level and catch the wizard from either gravity.
func try_flip() -> void:
	if dead:
		return
	flip_buffer = JUMP_BUFFER


func bounce() -> void:
	velocity.y = STOMP_BOUNCE
	stomp_jump = true


## Called by SpikeBlob when the shield absorbs a lethal touch.
func break_shield() -> void:
	shielded = false


func die() -> void:
	if dead:
		return
	dead = true
	collision_mask = 0
	velocity = Vector2(-140.0, -700.0)
	died.emit()


func _draw() -> void:
	if gravity_dir < 0.0:
		# ceiling-runner: mirror the whole sprite vertically
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, -1.0))
	var bob := 0.0
	if not dead and is_on_floor():
		bob = sin(time_alive * 14.0) * 2.0

	# robe
	var robe := PackedVector2Array([
		Vector2(-26, 40), Vector2(26, 40), Vector2(14, -6), Vector2(-14, -6),
	])
	draw_colored_polygon(robe, Color("8b6cff"))
	# head
	draw_circle(Vector2(0, -16 + bob), 16.0, Color("ffd9b3"))
	# hat
	var hat := PackedVector2Array([
		Vector2(-20, -24 + bob), Vector2(20, -24 + bob), Vector2(2, -62 + bob),
	])
	draw_colored_polygon(hat, Color("5b3df0"))
	draw_rect(Rect2(-24, -28 + bob, 48, 7), Color("4a2fd0"))
	# eye (facing right)
	draw_circle(Vector2(8, -16 + bob), 3.4, Color("1c1430"))
	# feet scamper
	if not dead:
		var step := sin(time_alive * 20.0)
		draw_rect(Rect2(-16 + step * 5.0, 38, 12, 6), Color("2f2650"))
		draw_rect(Rect2(6 - step * 5.0, 38, 12, 6), Color("2f2650"))
	# shield bubble: a violet ring while the one-hit protection is held
	if shielded:
		draw_circle(Vector2(0, -8), 54.0, Color(0.6, 0.4, 1.0, 0.12))
		draw_arc(Vector2(0, -8), 54.0, 0.0, TAU, 40,
				Color(0.73, 0.55, 1.0, 0.6 + 0.2 * sin(time_alive * 6.0)), 4.0)
	# Star of Levity charge: gold sparkles orbit while a double jump is stored
	if double_jumps > 0:
		for i in range(3):
			var a := time_alive * 3.0 + TAU * float(i) / 3.0
			var sp := Vector2(cos(a) * 44.0, sin(a) * 30.0 - 8.0)
			draw_circle(sp, 4.0, Color(1.0, 0.85, 0.35, 0.9))
			draw_circle(sp, 2.0, Color(1.0, 0.97, 0.8, 0.95))
