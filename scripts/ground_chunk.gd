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


## Deterministic per-building variation, keyed off the chunk's own world
## position. It must be stable — a building may be redrawn at any time and
## must never change — but no two neighbours may share a rhythm.
func _vary(salt: int, lo: float, hi: float) -> float:
	var h := absi(int(position.x) * 131071 + int(position.y) * 8191 + salt * 2749)
	return lo + (hi - lo) * (float(h % 997) / 997.0)


func _draw() -> void:
	# City blocks: the collision slab is unchanged, but it now reads as a
	# building/sidewalk section instead of a fantasy platform.
	#
	# EVERY repeating detail here varies per building. The windows used to sit
	# on a fixed 92 px pitch and the kerb dashes on a fixed 86 px one, so at the
	# 900 px/s cap both swept past a given point at ~10 Hz — the exact band
	# where a regular high-contrast pattern stops reading as motion and starts
	# reading as flicker. That, on top of the display's own persistence, is
	# what made the city uncomfortable to look at at speed (Neven). Varying
	# pitch, phase and row offset means no single beat ever builds up, and the
	# lit windows gave up most of their contrast for the same reason.
	draw_rect(Rect2(0, 0, width, thick), Color("263642"))
	if thick > 80.0:
		var facade_top := 26.0 if not ceiling else maxf(12.0, thick - 250.0)
		var facade_bottom := minf(thick - 24.0, facade_top + 220.0)
		var pitch := _vary(1, 74.0, 118.0)
		var row := _vary(2, 58.0, 84.0)
		var wx := 16.0 + _vary(3, 0.0, pitch)
		var col := 0
		# Only emit a complete window when it fits inside BOTH axes. The old
		# ranges stopped on each origin, allowing the body to cross an edge.
		while wx + 38.0 <= width - 12.0:
			# each column starts at its own height, so the rows never line up
			# into a second grid running the other way
			var wy := facade_top + _vary(10 + col, 0.0, 18.0)
			while wy + 30.0 <= facade_bottom:
				var tone := (col * 3 + int(wy / row)) % 7
				var window_color := Color("3b5163")
				if tone == 0 or tone == 4:
					window_color = Color("c9a05a")  # a light on, not a beacon
				elif tone == 2:
					window_color = Color("556c80")
				draw_rect(Rect2(wx, wy, 38.0, 30.0), window_color)
				wy += row
			wx += pitch
			col += 1
	# kerb (or roof) line: the solid strip is a single edge and stays, but its
	# dashes get the same varied pitch and a softer paint
	var strip_y := (thick - 14.0) if ceiling else 0.0
	var dash_y := (thick - 10.0) if ceiling else 4.0
	draw_rect(Rect2(0, strip_y, width, 14), Color("e7d9bd"))
	var dash := _vary(4, 70.0, 108.0)
	var dx := 12.0 + _vary(5, 0.0, dash)
	while dx + 46.0 <= width - 12.0:
		draw_rect(Rect2(dx, dash_y, 46.0, 5.0), Color("e0b06a"))
		dx += dash
