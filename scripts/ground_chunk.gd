class_name GroundChunk
extends StaticBody2D

## A slab of solid ground. Positioned by its top-left corner.
## FLIPSIDE ceilings are the same slab flipped: the bright walkable edge is
## the BOTTOM face.

const THICK := 600.0

var width := 600.0
var ceiling := false


func _init(w: float) -> void:
	width = w
	collision_layer = 1
	collision_mask = 0
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width, THICK)
	cs.shape = rect
	cs.position = Vector2(width * 0.5, THICK * 0.5)
	add_child(cs)


func _draw() -> void:
	draw_rect(Rect2(0, 0, width, THICK), Color("332a4d"))
	if ceiling:
		draw_rect(Rect2(0, THICK - 12, width, 12), Color("7f6ce0"))
	else:
		draw_rect(Rect2(0, 0, width, 12), Color("7f6ce0"))
