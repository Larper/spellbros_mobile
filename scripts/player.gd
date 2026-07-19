class_name Player
extends CharacterBody2D

## The auto-running wizard. Forward speed is fed by Main each frame;
## jumping has coyote time + a small input buffer so taps feel forgiving.

signal died
signal jumped

const BODY_W := 56.0
const BODY_H := 80.0
const GRAVITY := 3300.0
const JUMP_VELOCITY := -1170.0
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.12
const STOMP_BOUNCE := -880.0

var run_speed := 470.0
var dead := false
var coyote := 0.0
var jump_buffer := 0.0
var time_alive := 0.0
var air_jumps := 0  # Star of Levity charge: one stored mid-air jump
var stomp_jump := false  # stomping an enemy refreshes one jump until landing


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
	velocity.y += GRAVITY * delta

	if is_on_floor():
		coyote = COYOTE_TIME
		stomp_jump = false
	else:
		coyote -= delta

	# the free stomp refresh (or coyote) is consumed before a precious star charge
	if jump_buffer > 0.0 and (coyote > 0.0 or stomp_jump):
		velocity.y = JUMP_VELOCITY
		coyote = 0.0
		stomp_jump = false
		jump_buffer = 0.0
		jumped.emit()
	elif jump_buffer > 0.0 and air_jumps > 0 and not is_on_floor():
		# spend the Star of Levity charge for a full mid-air jump
		velocity.y = JUMP_VELOCITY
		air_jumps -= 1
		jump_buffer = 0.0
		jumped.emit()
	jump_buffer -= delta

	move_and_slide()


func try_jump() -> void:
	jump_buffer = JUMP_BUFFER


func bounce() -> void:
	velocity.y = STOMP_BOUNCE
	stomp_jump = true


func die() -> void:
	if dead:
		return
	dead = true
	collision_mask = 0
	velocity = Vector2(-140.0, -700.0)
	died.emit()


func tap_rect() -> Rect2:
	# Generous hitbox (~2.6x the body) so jump vs. build never misfires.
	var size := Vector2(BODY_W, BODY_H) * 2.6
	return Rect2(global_position - size * 0.5, size)


func _draw() -> void:
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
	# Star of Levity charge: gold sparkles orbit while an air jump is stored
	if air_jumps > 0:
		for i in range(3):
			var a := time_alive * 3.0 + TAU * float(i) / 3.0
			var sp := Vector2(cos(a) * 44.0, sin(a) * 30.0 - 8.0)
			draw_circle(sp, 4.0, Color(1.0, 0.85, 0.35, 0.9))
			draw_circle(sp, 2.0, Color(1.0, 0.97, 0.8, 0.95))
