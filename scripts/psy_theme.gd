class_name PsyTheme
extends CanvasModulate

## Beat-synced psychedelia. Every kick flashes the whole canvas toward white
## while the tint's hue crawls through the full spectrum (~50 s per cycle);
## the background pulses a complementary color in the same rhythm. Driven by
## GameAudio.music_time() so the visuals stay locked to the psytrance loop
## instead of drifting on frame time. The HUD lives on a CanvasLayer and
## stays readable/untinted.
##
## UMBRA level: the same node becomes the darkness — the modulate drops to
## near-black (still breathing with the kick) and PointLight2D nodes made
## by make_light() carve out the visible world.

static var _light_gradient: GradientTexture2D

var audio: GameAudio
var main
var t := 0.0


func _ready() -> void:
	main = get_parent()
	audio = main.audio


func _process(delta: float) -> void:
	var mt: float = audio.music_time()
	# fall back to frame time when the music is stopped (game over, headless)
	t = mt if mt > 0.0 else t + delta
	var beat := 60.0 / GameAudio.BPM
	var pulse := exp(-5.0 * fmod(t, beat) / beat)
	var hue := fmod(t * 0.02, 1.0)
	var dark := darkness()
	# lights-out target: PITCH black (Neven: UMBRA played like a faster
	# FOUNDATIONS — now unlit stretches are truly invisible, and sight
	# itself is the resource: crystals beacon, built platforms are the
	# lanterns you throw ahead to find the way). Still thumps faintly.
	var v := 0.03 + 0.02 * pulse
	var lite := Color.from_hsv(hue, 0.32 - 0.22 * pulse, 1.0)
	var lite_bg := Color.from_hsv(fmod(hue + 0.5, 1.0), 0.6, 0.10 + 0.10 * pulse)
	color = lite.lerp(Color(v, v, v * 1.25), dark)
	RenderingServer.set_default_clear_color(
			lite_bg.lerp(Color(0.004, 0.003, 0.01), dark))


## 0 = full psychedelia, 1 = UMBRA pitch black. Never a hard cut (Neven):
## drains to black across the FLIPSIDE wind-down — starting as the UMBRA
## banner fires — and blooms back out across UMBRA's own calm wind-down,
## reaching full light exactly at the SPELLBROS boundary. Monotonic on both
## slopes: the world must never dip darker before brightening (it did: the
## old ramp-out started AT the boundary, after the halo had already cut).
## Main drives the wizard's halo from this same gradient.
func darkness() -> float:
	var d: float = main.distance_m
	return clampf(clampf((d - (Levels.start_m(Levels.UMBRA) - 60.0)) / 55.0, 0.0, 1.0)
			- clampf((d - (Levels.start_m(Levels.BROS) - 45.0)) / 45.0, 0.0, 1.0), 0.0, 1.0)


## Warm point light used by the wizard, crystals and lantern-platforms in
## UMBRA. Texture is a code-generated radial gradient — no asset files.
static func make_light(radius: float, energy: float) -> PointLight2D:
	if _light_gradient == null:
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.97, 0.9, 1.0))
		g.set_color(1, Color(1.0, 0.97, 0.9, 0.0))
		_light_gradient = GradientTexture2D.new()
		_light_gradient.gradient = g
		_light_gradient.fill = GradientTexture2D.FILL_RADIAL
		_light_gradient.fill_from = Vector2(0.5, 0.5)
		_light_gradient.fill_to = Vector2(0.5, 0.0)
		_light_gradient.width = 256
		_light_gradient.height = 256
	var l := PointLight2D.new()
	l.texture = _light_gradient
	l.texture_scale = radius / 128.0
	l.energy = energy
	return l
