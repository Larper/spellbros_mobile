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
	# City blocks: the collision slab is unchanged, but it now reads as a
	# building/sidewalk section instead of a fantasy platform.
	draw_rect(Rect2(0, 0, width, thick), Color("263642"))
	if thick > 80.0:
		var facade_top := 26.0 if not ceiling else maxf(12.0, thick - 250.0)
		var facade_bottom := minf(thick - 24.0, facade_top + 220.0)
		# Only emit a complete window when it fits inside BOTH axes. The old
		# ranges stopped on each origin, allowing the body to cross an edge.
		var wx := 28
		while float(wx) + 38.0 <= width - 12.0:
			var wy := int(facade_top)
			while float(wy) + 30.0 <= facade_bottom:
				var lit := int(wx / 92 + wy / 70)
				var window_color := Color("f4c86b") if lit % 3 == 0 else Color("496273")
				draw_rect(Rect2(float(wx), float(wy), 38.0, 30.0), window_color)
				wy += 70
			wx += 92
	if ceiling:
		draw_rect(Rect2(0, thick - 14, width, 14), Color("e7d9bd"))
		var x := 18
		while float(x) + 46.0 <= width - 12.0:
			draw_rect(Rect2(float(x), thick - 10.0, 46.0, 5.0), Color("f3b94f"))
			x += 86
	else:
		draw_rect(Rect2(0, 0, width, 14), Color("e7d9bd"))
		var x := 18
		while float(x) + 46.0 <= width - 12.0:
			draw_rect(Rect2(float(x), 4.0, 46.0, 5.0), Color("f3b94f"))
			x += 86
