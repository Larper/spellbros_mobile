class_name Player
extends CharacterBody2D

## The auto-running commuter. Forward speed is fed by Main each frame;
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
var double_jumps := 0  # one stored double jump
var shielded := false  # purple shield orb: absorbs one lethal blob touch
var stomp_jump := false  # stomping an enemy refreshes one jump until landing
var gravity_dir := 1.0  # FLIPSIDE: -1 runs the ceiling; +1 the floor
var flip_cooldown := 0.0
var flip_buffer := 0.0  # taps buffer like jumps: a tap just before landing sticks
var aura: Node2D
var shield_fill: ColorRect
var shield_segments: Array[ColorRect] = []
var jump_orbs: Array[Node2D] = []


func _init() -> void:
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(BODY_W, BODY_H)
	cs.shape = rect
	add_child(cs)
	# Powerup indicators use persistent render nodes rather than custom draw
	# commands. This avoids renderer-specific command loss and keeps the effects
	# visible even if the game is paused on the exact pickup frame.
	aura = Node2D.new()
	aura.z_index = 40
	add_child(aura)

	# Focus Mode reads twice over: the camera-focus frame here, and the
	# headphones drawn onto the commuter himself (see _draw). The frame is made
	# of persistent ColorRects — the same dependable CanvasItems the HUD uses —
	# so the effect survives the Mobile renderer path that dropped the original
	# circle/Line2D shield.
	shield_fill = ColorRect.new()
	shield_fill.position = Vector2(-58, -65)
	shield_fill.size = Vector2(116, 114)
	shield_fill.color = Color(0.25, 0.75, 0.82, 0.10)
	shield_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aura.add_child(shield_fill)
	var focus_rects := [
		Rect2(-66, -73, 34, 7), Rect2(-66, -73, 7, 32),
		Rect2(32, -73, 34, 7), Rect2(59, -73, 7, 32),
		Rect2(-66, 48, 34, 7), Rect2(-66, 23, 7, 32),
		Rect2(32, 48, 34, 7), Rect2(59, 23, 7, 32),
	]
	for rect_data in focus_rects:
		var segment := ColorRect.new()
		segment.position = rect_data.position
		segment.size = rect_data.size
		segment.color = Color(0.55, 0.9, 0.92, 0.95)
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		aura.add_child(segment)
		shield_segments.append(segment)

	for i in range(3):
		var orb := Node2D.new()
		var glow := Polygon2D.new()
		glow.polygon = _disc(Vector2.ZERO, 14.0, 12)
		glow.color = Color(1.0, 0.78, 0.18, 0.38)
		orb.add_child(glow)
		var core := Polygon2D.new()
		core.polygon = _disc(Vector2.ZERO, 9.0, 12)
		core.color = Color(1.0, 0.82, 0.20, 1.0)
		orb.add_child(core)
		var shine := Polygon2D.new()
		shine.polygon = _disc(Vector2.ZERO, 4.0, 10)
		shine.color = Color(1.0, 0.98, 0.78, 1.0)
		orb.add_child(shine)
		aura.add_child(orb)
		jump_orbs.append(orb)
	aura.visible = false


func _physics_process(delta: float) -> void:
	time_alive += delta
	queue_redraw()
	refresh_powerup_visuals()

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
		# spend the stored charge for a full double jump
		velocity.y = JUMP_VELOCITY * gravity_dir
		double_jumps -= 1
		refresh_powerup_visuals()
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
	refresh_powerup_visuals()


## Keep held-powerup art in sync immediately. This is also called directly by
## pickups, so pausing on the collection frame cannot leave the HUD chip visible
## while the world-space effect is still waiting for another physics tick.
func refresh_powerup_visuals() -> void:
	var show_shield := not dead and shielded
	var show_jump := not dead and double_jumps > 0
	aura.visible = show_shield or show_jump
	aura.scale = Vector2(1.0, -1.0 if gravity_dir < 0.0 else 1.0)
	shield_fill.visible = show_shield
	for segment in shield_segments:
		segment.visible = show_shield
	if show_shield:
		var pulse := 0.5 + 0.5 * sin(time_alive * 6.0)
		shield_fill.color = Color(0.25, 0.75, 0.82, 0.08 + 0.06 * pulse)
		for segment in shield_segments:
			segment.color = Color(0.55, 0.9, 0.92, 0.78 + 0.22 * pulse)
	for i in range(jump_orbs.size()):
		var orb := jump_orbs[i]
		orb.visible = show_jump
		if show_jump:
			var a := time_alive * 3.0 + TAU * float(i) / 3.0
			orb.position = Vector2(cos(a) * 52.0, sin(a) * 36.0 - 8.0)
	var main = get_tree().get_first_node_in_group("main")
	if main != null and main.hud != null:
		main.hud.update_powerups(shielded, double_jumps > 0)


func die() -> void:
	if dead:
		return
	dead = true
	refresh_powerup_visuals()
	collision_mask = 0
	velocity = Vector2(-140.0, -700.0)
	died.emit()


func _draw() -> void:
	# Ceiling-runner: mirror the whole sprite vertically. Always setting the
	# transform also clears a previous flipped draw on renderers that cache it.
	draw_set_transform(Vector2.ZERO, 0.0,
			Vector2(1.0, -1.0 if gravity_dir < 0.0 else 1.0))
	var bob := 0.0
	if not dead and is_on_floor():
		bob = sin(time_alive * 14.0) * 2.0

	# Draw the face first. On the Mobile renderer an early silhouette remains
	# reliable even when later body polygons are batched; the soft octagon also
	# reads as a person rather than the old headless, robot-like torso.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-12, -44 + bob), Vector2(11, -44 + bob),
		Vector2(19, -36 + bob), Vector2(19, -19 + bob),
		Vector2(12, -10 + bob), Vector2(-12, -10 + bob),
		Vector2(-19, -19 + bob), Vector2(-19, -36 + bob),
	]), Color("efbd8c"))
	draw_rect(Rect2(-16, -44 + bob, 32, 10), Color("3f302b"))
	draw_rect(Rect2(-19, -38 + bob, 7, 15), Color("3f302b"))
	draw_rect(Rect2(-6, -12 + bob, 12, 10), Color("d99d70"))
	draw_rect(Rect2(14, -29 + bob, 6, 9), Color("e4a978"))
	draw_rect(Rect2(7, -27 + bob, 5, 5), Color("182532"))
	draw_line(Vector2(8, -15 + bob), Vector2(14, -13 + bob), Color("9b5f4a"), 2.0)

	# FOCUS MODE: he puts the headphones on. Blue over-ear cans, the
	# noise-cancelling sort, drawn straight after the head so the band sits over
	# the hair. The commuter is a PROFILE facing right — one eye at x 7, the
	# nose bump at 14, the back of his head at -19 — so this is a side view of
	# headphones: ONE cup, over the ear behind the eye, and the band arcing
	# from it across the crown to vanish behind the far side of his head. A
	# left-and-right pair put one cup on his face and one on his skull (Neven).
	if shielded and not dead:
		var band := Color("223350")
		var cup := Color("1b2b45")
		# the near cup, over the EAR — back third of the head, well clear of the
		# cheek and the eye at x 7. Sitting it mid-head read as a cup strapped
		# to his face.
		draw_colored_polygon(PackedVector2Array([
			Vector2(-13, -34 + bob), Vector2(-1, -34 + bob), Vector2(2, -29 + bob),
			Vector2(2, -21 + bob), Vector2(-1, -16 + bob), Vector2(-13, -16 + bob),
			Vector2(-16, -21 + bob), Vector2(-16, -29 + bob),
		]), cup)
		# headband: up off the cup and over the crown, tucking back into the
		# hair before the forehead — past that it is behind his head from here
		draw_polyline(PackedVector2Array([
			Vector2(-9, -33 + bob), Vector2(-13, -42 + bob), Vector2(-6, -49 + bob),
			Vector2(4, -50 + bob), Vector2(11, -46 + bob), Vector2(14, -41 + bob),
		]), band, 6.0, true)
		# the cup's outer plate and its one control dot. Kept close in tone: a
		# bright panel here read as a tiny screen.
		draw_rect(Rect2(-12, -30 + bob, 10, 11), Color("3d6094"))
		draw_rect(Rect2(-8, -25 + bob, 3, 3), Color("a8cbe8"))

	# Backpack behind the body: the everyday-life silhouette reads before any
	# facial detail does, even at phone scale.
	draw_rect(Rect2(-27, -7 + bob, 15, 34), Color("d96b4b"))
	draw_rect(Rect2(-30, 1 + bob, 5, 18), Color("f4a261"))
	# Legs and practical sneakers.
	var step := sin(time_alive * 20.0) if not dead else 0.0
	draw_rect(Rect2(-15 + step * 3.0, 18 + bob, 11, 24), Color("26384a"))
	draw_rect(Rect2(5 - step * 3.0, 18 + bob, 11, 24), Color("26384a"))
	# Jacket, bright enough to stay visible against every city palette.
	var jacket := PackedVector2Array([
		Vector2(-18, -8 + bob), Vector2(17, -8 + bob),
		Vector2(21, 24 + bob), Vector2(-21, 24 + bob),
	])
	draw_colored_polygon(jacket, Color("2f80a8"))
	draw_line(Vector2(0, -6 + bob), Vector2(0, 23 + bob), Color("bde7ef"), 3.0)
	draw_line(Vector2(14, 0 + bob), Vector2(27, 15 + bob), Color("2f80a8"), 9.0)
	# Phone in the forward hand.
	draw_rect(Rect2(23, 9 + bob, 10, 16), Color("182532"))
	draw_rect(Rect2(25, 11 + bob, 6, 10), Color("8dd8df"))
	# Feet scamper; the white soles keep the run cycle readable.
	if not dead:
		draw_rect(Rect2(-17 + step * 5.0, 38 + bob, 15, 6), Color("f3f4ef"))
		draw_rect(Rect2(5 - step * 5.0, 38 + bob, 15, 6), Color("f3f4ef"))


func _disc(center: Vector2, radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		points.append(center + Vector2(cos(a), sin(a)) * radius)
	return points
