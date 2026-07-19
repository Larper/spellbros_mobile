class_name GameTheme
extends Node

## Distance-driven color scheme manager. Every METERS_PER_THEME meters the
## world advances to the next palette in an endless cycle; colors blend
## smoothly over TRANSITION_TIME so there is never a hard pop.
##
## Shared value structure across EVERY palette (readability contract):
##   - background is always the darkest thing on screen (V ~= 0.08-0.12)
##   - ground fill sits just above it (V ~= 0.15-0.25), same hue family as
##     the background so terrain silhouettes (and therefore GAPS) read as
##     one dark mass against the even-darker sky
##   - ground edge is a bright hue-mate (V ~= 0.75+) tracing every walkable
##     surface, so landing spots are legible at speed
##   - crystals and enemies are the most saturated, brightest marks in the
##     scene, on hues far apart from each other AND from the ground edge,
##     so "collect me" vs "avoid me" never needs a second glance
##   - the wizard's violet robe + skin-tone head are deliberately NOT themed:
##     a constant, bright identity color that pops on every dark background
##
## Drawing scripts read colors each frame via GameTheme.active.color(i).
## No per-frame allocations: colors are blended in place inside
## pre-allocated PackedColorArrays.

signal theme_changed(index: int, music_variant: int, music_pitch: float)

enum {
	C_BG,             # clear color / sky
	C_GROUND,         # ground slab fill
	C_GROUND_EDGE,    # bright walkable-surface top line
	C_CRYSTAL,        # mana crystal body (also HUD mana color)
	C_CRYSTAL_CORE,   # inner sparkle of the crystal
	C_ENEMY,          # spike blob body
	C_ENEMY_SPIKE,    # spike blob spikes (darker shade of body)
	C_PLATFORM,       # built light-bridge body
	C_PLATFORM_EDGE,  # bright top line of the light-bridge
	C_ACCENT,         # secondary ground strata line (depth cue)
	C_ACCENT2,        # magic aura: built-platform glow
	C_COUNT,
}

const METERS_PER_THEME := 100.0
const TRANSITION_TIME := 1.6  # seconds of smooth blend on theme change

static var active: GameTheme

var palettes: Array[PackedColorArray] = []
var palette_names := PackedStringArray()
var palette_music := PackedInt32Array()    # music variant index per palette
var palette_pitch := PackedFloat32Array()  # music pitch_scale per palette

var current_index := 0
var blend := 1.0     # 0..1 progress of the current transition (1 = settled)
var dirty := false   # true on frames where colors were rewritten

var _from := PackedColorArray()  # snapshot of colors when a transition began
var _cols := PackedColorArray()  # live blended colors


func _init() -> void:
	_build_palettes()
	_cols = palettes[0].duplicate()
	_from = palettes[0].duplicate()
	active = self


func color(i: int) -> Color:
	return _cols[i]


## Called by Main each physics frame with the current run distance.
func advance(distance_m: float, delta: float) -> void:
	dirty = false
	var target := int(distance_m / METERS_PER_THEME) % palettes.size()
	if target != current_index:
		for i in range(C_COUNT):
			_from[i] = _cols[i]
		current_index = target
		blend = 0.0
		theme_changed.emit(target, palette_music[target], palette_pitch[target])
	if blend < 1.0:
		blend = minf(blend + delta / TRANSITION_TIME, 1.0)
		var t := blend * blend * (3.0 - 2.0 * blend)  # smoothstep ease
		var to := palettes[current_index]
		for i in range(C_COUNT):
			_cols[i] = _from[i].lerp(to[i], t)
		dirty = true
		RenderingServer.set_default_clear_color(_cols[C_BG])
		# Ground chunks only redraw while colors are actually moving;
		# everything else already queue_redraws every frame.
		get_tree().call_group("theme_redraw", "queue_redraw")


func _add_palette(pal_name: String, music_variant: int, music_pitch: float,
		cols: Array) -> void:
	var p := PackedColorArray()
	p.resize(C_COUNT)
	for i in range(C_COUNT):
		p[i] = cols[i]
	palettes.append(p)
	palette_names.append(pal_name)
	palette_music.append(music_variant)
	palette_pitch.append(music_pitch)


## The seven moods, each ~100 m long; a full lap of the cycle is 700 m
## (nicely past the 470 m void phase, so long runs see every mood).
func _build_palettes() -> void:
	# 0 TWILIGHT INDIGO -- analogous indigo->violet base with a cyan
	# complement. This is the game's original look, kept as the anchor:
	# violet ground family recedes, cyan crystals sit almost opposite
	# violet on the wheel so pickups burn through, and the pink enemy is
	# a warm counterpoint to both. Music: the original wistful A-minor
	# arpeggio.
	_add_palette("Twilight Indigo", 0, 1.0, [
		Color("191129"),  # bg: near-black indigo
		Color("332a4d"),  # ground: muted violet
		Color("7f6ce0"),  # edge: luminous periwinkle
		Color("52e5ff"),  # crystal: electric cyan (complement of violet)
		Color("ccf6ff"),  # crystal core: icy white-cyan
		Color("ff5577"),  # enemy: hot pink-red (warm vs the cool field)
		Color("d63d68"),  # enemy spikes: deeper crimson-pink
		Color("5cd9ff"),  # platform: conjured cyan light
		Color("d9fbff"),  # platform edge: near-white cyan
		Color("9d8cff"),  # accent: soft violet strata
		Color("52c8ff"),  # accent2: cyan aura
	])

	# 1 FOREST DUSK -- split-complementary on green: an analogous
	# green/teal terrain family, with the crystal jumping to warm gold
	# (yellow sits far from green while feeling like fireflies in a
	# forest) and the enemy to red-orange, green's direct complement --
	# the classic "poison berry in foliage" danger read. Saturation on
	# the big ground areas is kept low so the two warm accents own all
	# the attention. Music: E-dorian, the "brighter minor" -- calm and
	# woodsy, on a soft sine arp at a slower 100 bpm.
	_add_palette("Forest Dusk", 1, 1.0, [
		Color("0d1a14"),  # bg: black-green
		Color("22382a"),  # ground: mossy pine
		Color("6fd08c"),  # edge: fresh leaf green
		Color("ffd45e"),  # crystal: firefly gold
		Color("fff0bd"),  # crystal core: pale candlelight
		Color("ff6b52"),  # enemy: red-orange (complement of green)
		Color("d94a35"),  # enemy spikes: brick red
		Color("a8f0c0"),  # platform: pale mint light
		Color("eafff2"),  # platform edge: white-mint
		Color("4fa06a"),  # accent: deep leaf strata
		Color("8ce8a8"),  # accent2: soft green aura
	])

	# 2 EMBER DUSK -- split-complementary on orange: a warm analogous
	# sweep (maroon bg -> ember ground -> orange edge) answered by
	# orange's two split complements: teal crystals (cool water against
	# fire = maximum pickup pop) and a magenta-violet enemy that reads
	# alien and hostile amid the warmth. Music: D minor with a raised
	# leading tone (i-VI-iv-V), a touch faster -- smoldering tension.
	_add_palette("Ember Dusk", 2, 1.0, [
		Color("1f0c10"),  # bg: charred maroon
		Color("452028"),  # ground: dark ember clay
		Color("ff9350"),  # edge: glowing ember orange
		Color("3fe8cf"),  # crystal: cool teal (split complement)
		Color("c9fff4"),  # crystal core: pale seafoam
		Color("e14dff"),  # enemy: magenta-violet (other split complement)
		Color("b02fd6"),  # enemy spikes: deep orchid
		Color("ffc178"),  # platform: warm amber light
		Color("ffefd6"),  # platform edge: cream
		Color("c2543a"),  # accent: rust strata
		Color("ff9e5c"),  # accent2: ember aura
	])

	# 3 ABYSSAL TEAL -- monochromatic teal with warm complements: the
	# whole world is one deep-sea hue in four values (a proven scheme for
	# calm cohesion), which lets the two warm intruders carry all
	# contrast -- golden crystals (near-complement of teal, like
	# treasure light) and a coral enemy. Music: the dorian loop pitched
	# down ~6% -- same calm, but darker and heavier, like pressure at
	# depth.
	_add_palette("Abyssal Teal", 1, 0.94, [
		Color("041518"),  # bg: lightless deep water
		Color("0e3238"),  # ground: dark teal rock
		Color("2fd7c0"),  # edge: bioluminescent teal
		Color("ffd166"),  # crystal: sunken gold
		Color("ffedbd"),  # crystal core: pale gold
		Color("ff6b8a"),  # enemy: warm coral
		Color("e04a6a"),  # enemy spikes: deep coral
		Color("8ef2ff"),  # platform: pale aqua light
		Color("e8fdff"),  # platform edge: white-aqua
		Color("1c6a72"),  # accent: mid-teal strata
		Color("46e0e8"),  # accent2: aqua aura
	])

	# 4 AURORA NIGHT -- complementary green/magenta over a near-neutral
	# night blue: the base is desaturated enough to host BOTH poles of a
	# complementary pair without clashing -- aurora green owns the
	# terrain edges, magenta owns the enemies, and icy cyan crystals
	# bridge the two. Highest-drama palette in the cycle. Music: the
	# original minor loop pitched up ~6% -- familiar melody, thinner
	# and shimmering, like cold clear air.
	_add_palette("Aurora Night", 0, 1.06, [
		Color("0a0d1d"),  # bg: polar night blue
		Color("1c2340"),  # ground: slate blue
		Color("72f5a8"),  # edge: aurora green
		Color("5ce1ff"),  # crystal: ice cyan
		Color("d8f8ff"),  # crystal core: white ice
		Color("ff4fd0"),  # enemy: aurora magenta (complement of green)
		Color("d32ba8"),  # enemy spikes: deep magenta
		Color("b8ffd9"),  # platform: pale aurora light
		Color("effff6"),  # platform edge: white-green
		Color("5b6bb0"),  # accent: blue strata
		Color("7ef7b8"),  # accent2: green aura
	])

	# 5 ROSE DAWN -- analogous plum->rose->peach warmth, with mint
	# crystals at rose's complement and a violet enemy pulled from just
	# beyond the analogous range (split-complementary structure again,
	# rotated). Feels like first light after the aurora's cold peak.
	# Music: the one major-key loop in the cycle (C-G-Am-F on a dreamy
	# sine arp) -- the emotional sunrise of the soundtrack.
	_add_palette("Rose Dawn", 3, 1.0, [
		Color("1f0f1e"),  # bg: pre-dawn plum
		Color("43203a"),  # ground: dark rosewood
		Color("ff8fa3"),  # edge: dawn rose
		Color("7bf5cf"),  # crystal: dewdrop mint (complement of rose)
		Color("e2fff4"),  # crystal core: white mint
		Color("8f5bff"),  # enemy: vivid violet (cool outlier on warm field)
		Color("6a3ae0"),  # enemy spikes: deep indigo-violet
		Color("ffc9d9"),  # platform: pale rose light
		Color("fff0f5"),  # platform edge: white-rose
		Color("b0526e"),  # accent: dusty rose strata
		Color("ff9e7d"),  # accent2: peach aura
	])

	# 6 MOONLIT ASH -- near-achromatic slate + twin vivid accents: the
	# terrain is drained to cool grays (a monochrome value study), so
	# amber crystals and a crimson enemy are the ONLY saturated marks on
	# screen -- the strongest figure/ground separation in the cycle, a
	# palate cleanser before looping back to Twilight Indigo. Music: the
	# tense minor loop pitched down ~6% -- hushed and grave.
	_add_palette("Moonlit Ash", 2, 0.94, [
		Color("121218"),  # bg: moonless slate
		Color("2b2b36"),  # ground: ash gray
		Color("aab3c8"),  # edge: moonlit silver
		Color("ffc44d"),  # crystal: lantern amber
		Color("ffeec2"),  # crystal core: warm white
		Color("ff3d5e"),  # enemy: blood crimson
		Color("d1264a"),  # enemy spikes: dark crimson
		Color("cfe3ff"),  # platform: cold moonlight
		Color("f2f8ff"),  # platform edge: white
		Color("565c70"),  # accent: graphite strata
		Color("b8cdf0"),  # accent2: silver aura
	])
