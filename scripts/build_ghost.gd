class_name BuildGhost
extends Node2D

## PC-only aim preview: a translucent outline of the step that WOULD be built,
## parked under the mouse at all times. A thumb is already resting on the glass
## where it aims, but a mouse is not — without a preview, the only way to learn
## where a pad lands is to spend the energy and look (Neven).
##
## It lives on a CanvasLayer, so its position IS the mouse's screen position and
## nothing about the camera can move it. Two things made the first version jitter
## left and right, and both are structural rather than cosmetic:
##   * it positioned itself in WORLD space from get_canvas_transform(), which in
##     _process is still last frame's camera — so every frame the ghost was
##     off by however far the camera had moved since;
##   * physics interpolation then re-derived that transform from the last two
##     PHYSICS ticks, exactly the trap EchoBro was moved out of.
## Drawing in screen space and opting out of interpolation removes both. The
## pad's world size is matched by scaling the drawing by the camera zoom.
##
## It asks Main whether a click here would build at all, so the preview never
## appears over the jump side of the screen, and turns red when energy is short.
## Runs in ALWAYS mode so it can hide itself while the tree is paused (level
## menu, pause panel) instead of freezing mid-air.

var main  # Main, untyped to avoid a cyclic class reference


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# a cursor must be exact THIS frame; there is nothing to smooth
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# screen space is zoomed world space: 240 world px of pad reads as 300 px
	scale = Vector2(Main.CAMERA_ZOOM, Main.CAMERA_ZOOM)
	visible = false


func _process(_delta: float) -> void:
	if main == null or main.player == null or main.game_over or get_tree().paused:
		visible = false
		return
	var vp := get_viewport()
	var screen_pos := vp.get_mouse_position()
	if not Rect2(Vector2.ZERO, vp.get_visible_rect().size).has_point(screen_pos):
		visible = false
		return
	# the jump half of the screen builds nothing: showing a pad there would be
	# a preview of something the click will not do
	if not main.tap_builds(screen_pos):
		visible = false
		return
	position = screen_pos
	visible = true
	queue_redraw()


func _draw() -> void:
	var s := BuiltPlatform.SIZE
	var affordable: bool = main.coins >= Main.PLATFORM_COST
	var lv: int = Levels.level_for(main.distance_m)
	var tint := Color("61c68b") if lv == Levels.SPRINGS else Color("f4d58d")
	if not affordable:
		tint = Color("ff6688")
	var rect := Rect2(-s * 0.5, s)
	draw_rect(rect, Color(tint, 0.16))
	draw_rect(rect, Color(tint, 0.85 if affordable else 0.65), false, 3.0)
	# centre tick: the pad is built dead on this line, so it is the one pixel
	# worth aiming with
	draw_line(Vector2(0.0, -s.y * 0.5 - 14.0), Vector2(0.0, s.y * 0.5 + 14.0),
			Color(tint, 0.55), 2.0)
