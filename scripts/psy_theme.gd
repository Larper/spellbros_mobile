class_name PsyTheme
extends CanvasModulate

## Beat-synced urban day cycle. The world moves from warm morning light through
## cool workday blue and sunset, while a restrained pulse follows the lo-fi
## soundtrack. Driven by GameAudio.music_time() so visual motion never drifts.
## The HUD lives on a CanvasLayer and stays readable/untinted.
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
	var dark := darkness()
	var d: float = main.distance_m
	var morning := Color("fff0cf")
	var daytime := Color("e5f5f3")
	var sunset := Color("f4d0bf")
	var evening := Color("dce8f5")
	var lite: Color
	var lite_bg: Color
	if d < Levels.start_m(Levels.BRIDGES):
		var day_t := clampf(d / Levels.start_m(Levels.BRIDGES), 0.0, 1.0)
		lite = morning.lerp(daytime, day_t)
		lite_bg = Color("17445a").lerp(Color("286577"), day_t)
	elif d < Levels.start_m(Levels.UMBRA):
		var sunset_t := clampf((d - Levels.start_m(Levels.BRIDGES)) /
				(Levels.start_m(Levels.UMBRA) - Levels.start_m(Levels.BRIDGES)), 0.0, 1.0)
		lite = daytime.lerp(sunset, sunset_t)
		lite_bg = Color("286577").lerp(Color("6b4054"), sunset_t)
	else:
		var evening_t := clampf((d - Levels.start_m(Levels.UMBRA)) / 600.0, 0.0, 1.0)
		lite = sunset.lerp(evening, evening_t)
		lite_bg = Color("342c52").lerp(Color("172b46"), evening_t)
	lite = lite.lerp(Color.WHITE, 0.05 + 0.05 * pulse)
	# lights-out target: PITCH black (Neven: UMBRA played like a faster
	# FOUNDATIONS — now unlit stretches are truly invisible, and sight
	# itself is the resource: crystals beacon, built platforms are the
	# lanterns you throw ahead to find the way). Still thumps faintly.
	var v := 0.03 + 0.02 * pulse
	color = lite.lerp(Color(v, v, v * 1.25), dark)
	RenderingServer.set_default_clear_color(
			lite_bg.lerp(Color(0.004, 0.006, 0.012), dark))


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
