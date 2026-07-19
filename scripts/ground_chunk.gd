class_name GroundChunk
extends StaticBody2D

## A slab of solid ground. Positioned by its top-left corner.

const THICK := 600.0

var width := 600.0


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


func _ready() -> void:
	# Chunks draw once and stay static; during palette transitions the
	# theme manager pokes this group so the new colors actually show.
	add_to_group("theme_redraw")


func _draw() -> void:
	var th := GameTheme.active
	draw_rect(Rect2(0, 0, width, THICK), th.color(GameTheme.C_GROUND))
	# bright walkable-edge line, plus a fainter accent stratum for depth
	draw_rect(Rect2(0, 0, width, 12), th.color(GameTheme.C_GROUND_EDGE))
	draw_rect(Rect2(0, 12, width, 5), Color(th.color(GameTheme.C_ACCENT), 0.4))
