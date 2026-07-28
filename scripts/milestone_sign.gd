class_name MilestoneSign
extends Node2D

## A gantry sign hanging over the route, counting down to the next part of the
## day: "COMMUTE 80m", then "COMMUTE 40m".
##
## The point is the run that DOESN'T get there. A player who dies at 238 m has
## still read two signs telling them COMMUTE exists and is close, which is the
## whole reason they might go again — the level-select menu can only tell you
## that after you have already found it. So these appear before EVERY boundary,
## not just the first.
##
## Hung at a fixed height rather than on the terrain: deck tops move around,
## and a sign that ducks behind a building is a sign nobody reads.

const WIDTH := 250.0
const HEIGHT := 86.0

var label := ""
var metres := 0
var t := 0.0


func _ready() -> void:
	# BEHIND everything that is actually played: coffee, notifications, pads,
	# the commuter. A sign is scenery, and scenery that hides a pickup you were
	# about to take is worse than no sign at all (Neven watched one swallow a
	# coffee). Buildings will occlude it during a tall climb wave — that is
	# what being in the background means, and it is the right trade.
	z_index = -10


func _physics_process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	var sway := sin(t * 1.6) * 2.0
	var top := -HEIGHT * 0.5 + sway
	# the mast it hangs from, running up out of frame
	draw_rect(Rect2(-7.0, top - 260.0, 14.0, 260.0), Color("2b3b49"))
	draw_rect(Rect2(-24.0, top - 10.0, 48.0, 12.0), Color("2b3b49"))
	# board: dark green, the colour every road sign in the world already uses
	draw_rect(Rect2(-WIDTH * 0.5 - 4.0, top - 4.0, WIDTH + 8.0, HEIGHT + 8.0),
			Color("1b2b31"))
	draw_rect(Rect2(-WIDTH * 0.5, top, WIDTH, HEIGHT), Color("1f5f4a"))
	draw_rect(Rect2(-WIDTH * 0.5 + 6.0, top + 6.0, WIDTH - 12.0, 3.0),
			Color(1.0, 1.0, 1.0, 0.55))
	draw_rect(Rect2(-WIDTH * 0.5 + 6.0, top + HEIGHT - 9.0, WIDTH - 12.0, 3.0),
			Color(1.0, 1.0, 1.0, 0.55))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-WIDTH * 0.5 + 10.0, top + 40.0), label,
			HORIZONTAL_ALIGNMENT_CENTER, WIDTH - 20.0, 30, Color(1, 1, 1, 0.96))
	draw_string(font, Vector2(-WIDTH * 0.5 + 10.0, top + 74.0), "%d m" % metres,
			HORIZONTAL_ALIGNMENT_CENTER, WIDTH - 20.0, 28, Color("ffd75e"))
