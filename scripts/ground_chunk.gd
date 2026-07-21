class_name GroundChunk
extends StaticBody2D

## A slab of solid ground. Positioned by its top-left corner.
## FLIPSIDE ceilings are the same slab flipped: the bright walkable edge is
## the BOTTOM face.
## SPELLBROS mid-air platforms are the same slab THIN and ONE-WAY: jump or
## bounce up through it, land on top — a solid floater at hop height would
## bonk the wizard's head on every jump beneath it.

const THICK := 600.0

var width := 600.0
var thick := THICK
var ceiling := false


func _init(w: float, t: float = THICK, one_way: bool = false) -> void:
	width = w
	thick = t
	collision_layer = 1
	collision_mask = 0
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width, thick)
	cs.shape = rect
	cs.position = Vector2(width * 0.5, thick * 0.5)
	cs.one_way_collision = one_way
	add_child(cs)


func _draw() -> void:
	draw_rect(Rect2(0, 0, width, thick), Color("332a4d"))
	if ceiling:
		draw_rect(Rect2(0, thick - 12, width, 12), Color("7f6ce0"))
	else:
		draw_rect(Rect2(0, 0, width, 12), Color("7f6ce0"))
