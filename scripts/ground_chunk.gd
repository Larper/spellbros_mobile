class_name GroundChunk
extends StaticBody2D

## A slab of solid ground. Positioned by its top-left corner.
## FLIPSIDE ceilings are the same slab flipped: the bright walkable edge is
## the BOTTOM face. STROBE slabs obey the music: solid for three beats,
## ghost (no collision) on the fourth — Main.strobe_ghost is the clock.

const THICK := 600.0

var width := 600.0
var ceiling := false
var strobe := false

var _cs: CollisionShape2D


func _init(w: float) -> void:
	width = w
	collision_layer = 1
	collision_mask = 0
	_cs = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width, THICK)
	_cs.shape = rect
	_cs.position = Vector2(width * 0.5, THICK * 0.5)
	add_child(_cs)


func _process(_delta: float) -> void:
	if not strobe:
		return
	_cs.set_deferred("disabled", Main.strobe_ghost)
	if Main.strobe_ghost:
		modulate.a = 0.18
	elif Main.strobe_warn:
		# telegraph: flicker through the beat before the drop
		modulate.a = 0.55 + 0.35 * absf(sin(Time.get_ticks_msec() * 0.045))
	else:
		modulate.a = 1.0


func _draw() -> void:
	draw_rect(Rect2(0, 0, width, THICK), Color("332a4d"))
	if ceiling:
		draw_rect(Rect2(0, THICK - 12, width, 12), Color("7f6ce0"))
	else:
		draw_rect(Rect2(0, 0, width, 12), Color("7f6ce0"))
