class_name TerrainSpawner
extends Node2D

## Endless procedural terrain with staged difficulty phases (HARD tuning —
## see PHASE_* constants for the exact meters). The Levels ladder overlays
## themed bands on top: SPRINGS (deck sections split by spring-pad void
## crossings) and BLOB BRIDGES (_spawn_bridge_chunk). Phases:
##   PHASE_BUILD   mega gaps appear that require building
##   PHASE_ENEMY   enemies start to spawn
##   PHASE_CLIMB   climb waves: terrain staircases up beyond jump height
##   PHASE_SPEED   run speed ramps (constant used by Main)
##   PHASE_SWARM   enemy swarms, faster blobs, and chained double mega gaps
##   PHASE_VOID    the void: ground mostly vanishes; trails of fragments float
##                 in open sky and must be caught with well-placed platforms
## Entity budget: max 2 things (enemies + mana) per chunk, 3 after PHASE_RICH,
## so mana stays scarce and every fragment matters.

const START_GROUND_Y := 880.0
const SPAWN_AHEAD := 2400.0
const CLEANUP_BEHIND := 1400.0

const PHASE_BUILD := 25.0
const PHASE_ENEMY := 50.0
const PHASE_CLIMB := 85.0
const PHASE_SPEED := 110.0
const PHASE_SWARM := 170.0
const PHASE_RICH := 300.0
const PHASE_VOID := 1800.0  # the endgame after the SPELLBROS level

const FLIP_CORRIDOR := 560.0  # floor-to-ceiling height in the FLIPSIDE level
const FLIP_DEAD_CHANCE := 0.25  # dead zones: both surfaces gone, build to cross
## Corridor transit time: free-fall across FLIP_CORRIDOR from rest under
## gravity 3300 = sqrt(560/1650) s. Strip widths and the fragment trail are
## both derived from this one number, so they can never disagree about where
## a flip taken inside the shared window actually puts you down.
const FLIP_TRANSIT := 0.583
## Wind-down: a band's last meters return to calm, plain terrain before the
## next level's twist (FLIPSIDE: continuous floor + taps become jumps again;
## BRIDGES: blob-free easy gaps). RUNWAY_M: FLIPSIDE's opening stretch stays
## a plain continuous floor so the level banner registers before the first
## flip is ever asked for.
const WIND_DOWN_M := 45.0
const RUNWAY_M := 20.0
## SPELLBROS gets a LONGER hand-off (Neven: THE VOID must not appear
## until the blobs are gone and the ground has run long and calm) — the
## band is the game's loudest, so its exit breathes longer than 45 m.
## BROS_GROUND_M: the band's entry runway — the last ground it shows
## before the floor drops out and the sky fills with blobs.
const BROS_OUT_M := 60.0
const BROS_GROUND_M := 25.0

## Every level's first ~45 m (3-4 gaps) is a teach-in: the new mechanic in
## its gentlest form, no ambushes, before the band ramps to full intensity.
const TEACH_M := 45.0

## ---- HARD-MODE GAP TUNING -------------------------------------------------
## Jump math (Player: GRAVITY 3300, JUMP_VELOCITY -1170):
##   full-jump airtime back to takeoff height = 2*1170/3300 = 0.709 s
##     -> flat horizontal reach = 0.709 * v px at run speed v
##   landing R px HIGHER shortens the arc: t = (1170 + sqrt(1170^2 - 6600*R)) / 3300
##     R = 150 -> t = 0.541 s -> reach = 0.541 * v
## Normal gaps are sized as FRACTIONS of the live run speed so they stay
## jumpable at every point of the speed ramp:
##   GAP_MAX_FRAC 0.56 < 0.709 flat reach          (21% margin, flat landings)
##   gaps wider than GAP_RISE_FRAC 0.46 never rise (0.46 < 0.541 rising reach)
const GAP_MIN_FRAC := 0.34
const GAP_MAX_FRAC := 0.56
const GAP_RISE_FRAC := 0.46
const GAP_MAX_RISE := 150.0
## Mega gaps: wider than the 0.709*v flat reach, so they always demand a
## build. One platform bridges jump + 240 px deck + jump = 1.418*v + 240 px,
## which exceeds MEGA_MAX_FRAC * v for any speed -> always 1-mana solvable.
const MEGA_MIN_FRAC := 0.85
const MEGA_MAX_FRAC := 1.45
const MEGA_CHANCE_BASE := 0.55
const MEGA_CHANCE_MAX := 0.7
const DOUBLE_MEGA_CHANCE := 0.45  # from PHASE_SWARM a mega can chain a second

const ENEMY_CHANCE := 0.55
const SWARM_CHANCE := 0.8
const SWARM_DOUBLE := 0.7
const ENEMY_MIN_W := 420.0
const ENEMY_SPEED_BASE := 130.0
const ENEMY_SPEED_MAX := 260.0    # blobs patrol faster from PHASE_SWARM on
const ENEMY_SPEED_RAMP_END := 500.0

const CLIMB_CHANCE := 0.3
const CLIMB_COOLDOWN := 4         # flat chunks required between climb waves
## ---- STAIRCASE FLAVOURS ---------------------------------------------------
## A climb wave is one flavour end to end, so a staircase never lies about
## what it wants (Neven: steps that looked hoppable but were 250 px tall read
## as a bug, not a puzzle).
##   HOP    steps rise well inside the 207 px jump ceiling and the tread stays
##          inside the rising-jump reach — climbed on taps alone.
##   BUILD  steps stay deliberately unjumpable AND open a wide, obvious hole,
##          with a coffee hung in it at pad height: the cup IS the "build
##          here" marker.
const CLIMB_HOP_CHANCE := 0.5
const CLIMB_HOP_RISE_MIN := 100.0
const CLIMB_HOP_RISE_MAX := 145.0
const CLIMB_HOP_GAP_FRAC := 0.42  # cap vs. run speed; 0.42 < 0.557 rising reach
## BUILD-step geometry is measured in SECONDS OF FLIGHT, then multiplied by
## the live run speed — a fixed pixel gap is a different manoeuvre at 470 and
## at the 900 px/s cap. The 300-420 px version worked early and broke at the
## cap: the pad landed you a few frames from the next pillar's face, so the
## second hop had no room and you ran into the wall (Neven).
## The intended line, unchanged at every speed:
##   1. jump off the lower deck,
##   2. land on the pad built on the marker cup — the cup sits exactly where
##      that arc comes back DOWN through pad height,
##   3. jump off the pad onto the step.
## CLIMB_PAD_H is the pad TOP's height above the lower deck: 57 px under the
## 207 px jump ceiling on the way in, and it leaves at most 120 px for the
## second hop. RUNOUT is the pad centre -> step face distance, sized to sit
## mid-window for that second hop anywhere along the pad.
const CLIMB_PAD_H := 150.0
## 0.45 rather than the 0.40 mid-window figure: the pad's 120 px half-width is
## a quarter of a second at 470 px/s but only an eighth at 900, so the low-speed
## end is where a late take-off runs out of room. This keeps the worst corner
## (min speed, max rise, jumping off the pad's very last pixel) 33 px clear of
## the step's face instead of 9.
const CLIMB_BUILD_RUNOUT := 0.45
const CLIMB_BUILD_RISE_MIN := 250.0
const CLIMB_BUILD_RISE_MAX := 270.0

const MANA_CHANCE := 0.45
const MANA_CHANCE_CLIMB := 0.65

const BASE_Y_MIN := 690.0
const BASE_Y_MAX := 970.0
const SKY_Y_MIN := 250.0

var main  # Main, untyped to avoid a cyclic class reference
var next_x := 0.0
var last_top_y := START_GROUND_Y
var rng := RandomNumberGenerator.new()

# climb wave state: 0 = level terrain, -1 = climbing, +1 = descending
var climb_dir := 0
var climb_steps_left := 0
var climb_hop := false  # this wave's flavour (see CLIMB_HOP_CHANCE)
var flat_chunks_since_wave := 99  # ready for a wave from the start of the phase

# double-mega combo: set when a mega rolls the chain, forces the next chunk mega
var force_mega := false

# void phase: height the fragment trail wanders around
var void_y := START_GROUND_Y - 120.0

# FLIPSIDE chain state: which surface the wizard's current lane is on
# (true on entering the band — he arrives running the floor)
var flip_on_floor := true
var flip_strip_start := 0.0  # left edge of the last chain strip placed
var flip_ceil_y := 0.0  # walkable face y of the last ceiling strip placed

# SPRINGS rhythm state: pillars left in the current easy deck section;
# when it reaches 0 the next chunk is a void crossing
var spring_deck_left := 3

# SPELLBROS sky state: the height the floating blob field wanders around
var bros_line := 650.0

# Guaranteed star showcase (Neven): FOUNDATIONS must serve the double
# jump between 110 and 150 m so it's met and understood before the
# themed bands. One flag per run; forced near the window's end if the
# rolls never landed it. The SHIELD never spawns anywhere at or before
# SPELLBROS (i.e. nowhere): a held shield intercepts the lethal touch
# BEFORE the brother's burn, pre-empting the band's whole reveal — and
# a shield can be carried any distance, so no earlier band may serve
# one either. The pickup class stays for the dev grant.
var star_given := false


func _ready() -> void:
	rng.randomize()
	# long, safe runway with a couple of teaching crystals
	_place_chunk(0.0, START_GROUND_Y, 2000.0)
	_place_coin(Vector2(900.0, START_GROUND_Y - 60.0))
	_place_coin(Vector2(1400.0, START_GROUND_Y - 60.0))
	next_x = 2000.0


func _process(_delta: float) -> void:
	var cam_x: float = main.cam.global_position.x
	while next_x < cam_x + SPAWN_AHEAD:
		_spawn_chunk()
	for c in get_children():
		var n := c as Node2D
		if n == null:
			continue
		var right := n.global_position.x
		if n is GroundChunk:
			right += n.width
		if right < cam_x - CLEANUP_BEHIND:
			n.queue_free()


## Spawns one chunk (and its gap before it). Returns stats for tests.
## Difficulty is gated by where the chunk WILL BE (in meters), not by the
## player's current distance — chunks spawn ~27 m ahead, so gating on player
## distance made every phase arrive visibly late.
func _spawn_chunk() -> Dictionary:
	# start_offset_m credits the meters skipped when starting at a later level
	var d: float = (next_x - main.start_x) / 100.0 + main.start_offset_m
	var t := minf(d / 500.0, 1.0)
	var v: float = main.run_speed_for(d)
	var budget := 3 if d >= PHASE_RICH else 2

	if d >= PHASE_VOID:
		return _spawn_void_segment()

	var lv := Levels.level_for(d)
	if lv == Levels.SPRINGS:
		return _spawn_spring_chunk(d, v)
	if lv == Levels.BRIDGES:
		return _spawn_bridge_chunk(d, v, budget)
	if lv == Levels.FLIPSIDE:
		return _spawn_flip_chunk(d, v)
	if lv == Levels.BROS:
		return _spawn_bros_chunk(d, v)

	# wind-down (standing rule: gentle hand-offs on BOTH edges): the last
	# meters of every standard-generator band drop megas, enemies and climb
	# waves and return to calm plain hops, so the next level's teach-in is
	# entered composed — the old FOUNDATIONS ended slamming a swarm straight
	# into the SPRINGS boundary
	var wind: bool = lv + 1 < Levels.count() \
			and Levels.start_m(lv + 1) - d <= WIND_DOWN_M
	if wind:
		climb_dir = 0
		climb_steps_left = 0
	else:
		_update_climb_state(d)

	var teach := _is_teach(d)
	var calm := teach or wind
	var mega: bool = not calm and climb_dir == 0 and d >= PHASE_BUILD \
			and (force_mega or rng.randf() < minf(MEGA_CHANCE_BASE + 0.15 * t, MEGA_CHANCE_MAX))
	force_mega = false
	var gap: float
	var w: float
	var dy: float

	if climb_dir == -1:
		if climb_hop:
			# HOP staircase: the same close tread as before, but every step
			# is now genuinely jumpable — no mana, no stopping, just rhythm
			gap = minf(rng.randf_range(150.0, 230.0), CLIMB_HOP_GAP_FRAC * v)
			w = rng.randf_range(320.0, 480.0)
			dy = -rng.randf_range(CLIMB_HOP_RISE_MIN, CLIMB_HOP_RISE_MAX)
		else:
			# BUILD staircase: a step unmistakably out of reach, over a hole
			# sized in flight time so the pad-then-hop line has the same room
			# at 900 px/s as at 470. The marker cup goes in at climb_pad_x.
			gap = climb_pad_x(v) + CLIMB_BUILD_RUNOUT * v
			w = rng.randf_range(380.0, 520.0)
			dy = -rng.randf_range(CLIMB_BUILD_RISE_MIN, CLIMB_BUILD_RISE_MAX)
		climb_steps_left -= 1
	elif climb_dir == 1:
		# stair step back down: easy drops
		gap = rng.randf_range(150.0, 240.0)
		w = rng.randf_range(360.0, 520.0)
		dy = rng.randf_range(200.0, 280.0)
	elif mega:
		gap = rng.randf_range(MEGA_MIN_FRAC * v, MEGA_MAX_FRAC * v)
		w = rng.randf_range(520.0, 820.0)
		dy = rng.randf_range(-40.0, 160.0)
		if d >= PHASE_SWARM and rng.randf() < DOUBLE_MEGA_CHANCE:
			force_mega = true
	elif calm:
		# teach-in / wind-down: easy gaps, wide decks, near-flat — room to
		# meet the twist (entering) or to breathe before the next one (leaving)
		gap = rng.randf_range(GAP_MIN_FRAC * v, 0.44 * v)
		w = rng.randf_range(700.0, 950.0)
		dy = rng.randf_range(-60.0, 60.0)
	else:
		gap = rng.randf_range(GAP_MIN_FRAC * v, GAP_MAX_FRAC * v)
		w = rng.randf_range(lerpf(520.0, 400.0, t), lerpf(950.0, 640.0, t))
		# wide gaps never land higher: rising landings cut reach to 0.541*v
		dy = rng.randf_range(0.0 if gap > GAP_RISE_FRAC * v else -GAP_MAX_RISE, 170.0)

	var y_min := SKY_Y_MIN if climb_dir != 0 else BASE_Y_MIN
	var top_y := clampf(last_top_y + dy, y_min, BASE_Y_MAX)

	var x := next_x + gap
	_place_chunk(x, top_y, w)

	var used := 0

	# BUILD-staircase marker: a cup floating in the hole exactly where a pad
	# belongs — it is the whole point of this flavour. See the coffee, build
	# under it, collect it on the way up, and the step has paid for itself.
	# The cup is the pad's CENTRE, so it hangs half a slab below the pad top.
	if climb_dir == -1 and not climb_hop:
		_place_coin(Vector2(next_x + climb_pad_x(v),
				last_top_y - CLIMB_PAD_H + BuiltPlatform.SIZE.y * 0.5))
		used += 1

	# one crystal floating over a mega gap: reward for bridging it
	if mega:
		_place_coin(Vector2(next_x + gap * 0.5, minf(last_top_y, top_y) - 190.0))
		used += 1

	# UMBRA: a lit fragment at the START of EVERY deck — the beacon marks
	# where footing begins, and the richer income funds the lantern-builds
	# that sight demands. Unconditional (Neven: a deck whose only fragment
	# sat mid-deck read as a missing left edge); placed before enemies so
	# light always wins the budget.
	var beacon := 0
	if lv == Levels.UMBRA:
		_place_coin(Vector2(x + 90.0, top_y - 60.0))
		used += 1
		beacon = 1

	# GUARANTEED star showcase (see the flag): between ~110-150 m —
	# mid-deck, at running height, on a chunk kept enemy-free — the
	# pickup must be walked into, never fought for
	var stars := 0
	if lv == 0 and climb_dir == 0 and w >= 400.0 and not star_given \
			and d >= 110.0 and (d >= 140.0 or rng.randf() < 0.3):
		_place_star(Vector2(x + w * 0.5, top_y - 60.0))
		star_given = true
		stars = 1
		used += 1

	# enemies (never on climb stairs — those are about building — never in
	# a teach-in stretch, and never sharing a deck with the showcase star)
	var enemies := 0
	if d >= PHASE_ENEMY and w > ENEMY_MIN_W and climb_dir == 0 and not calm \
			and stars == 0:
		var chance := SWARM_CHANCE if d >= PHASE_SWARM else ENEMY_CHANCE
		if rng.randf() < chance:
			enemies = 1
			if d >= PHASE_SWARM and w > 520.0 and used + 2 <= budget \
					and rng.randf() < SWARM_DOUBLE:
				enemies = 2
	enemies = mini(enemies, budget - used)
	var espeed := enemy_speed_for(d)
	if enemies == 1:
		var blob := SpikeBlob.new(x + 70.0, x + w - 70.0)
		blob.position = Vector2(x + w * 0.5, top_y - 30.0)
		blob.speed = espeed
		add_child(blob)
	elif enemies == 2:
		var mid := x + w * 0.5
		var a := SpikeBlob.new(x + 70.0, mid - 40.0)
		a.position = Vector2(x + w * 0.25, top_y - 30.0)
		a.speed = espeed
		add_child(a)
		var b := SpikeBlob.new(mid + 40.0, x + w - 70.0)
		b.position = Vector2(x + w * 0.75, top_y - 30.0)
		b.speed = espeed
		add_child(b)
	used += enemies

	# at most one crystal on the chunk itself; climb steps pay out more
	# reliably so stairs stay affordable. UMBRA runs rich: mana is sight.
	var mana_chance := MANA_CHANCE_CLIMB if climb_dir != 0 else MANA_CHANCE
	if lv == Levels.UMBRA:
		mana_chance = 0.65
	if used < budget and rng.randf() < mana_chance:
		if lv == Levels.UMBRA:
			# route light: the second fragment sits mid/far deck at running
			# height, never stacked over (or floating above) the deck-start
			# beacon — two lit points on one deck must read as "run on",
			# not as a confusing cluster at the left edge (Neven)
			_place_coin(Vector2(x + rng.randf_range(w * 0.5, w - 80.0), top_y - 60.0))
		else:
			var coin_y := top_y - 60.0 if rng.randf() < 0.7 else top_y - 250.0
			_place_coin(Vector2(x + rng.randf_range(80.0, w - 80.0), coin_y))
		used += 1

	# rare Star of Levity: a stored double jump. MID-DECK at RUNNING height
	# on an enemy-free deck — powerups spawned up at apex height were hard
	# to pick up and read as bait (Neven, twice). Same entity budget.
	if d >= PHASE_ENEMY and used < budget and enemies == 0 and not mega \
			and stars == 0 and rng.randf() < 0.1:
		_place_star(Vector2(x + rng.randf_range(w * 0.35, w * 0.65), top_y - 60.0))
		used += 1
		stars = 1

	var rise := maxf(0.0, last_top_y - top_y)
	next_x = x + w
	last_top_y = top_y
	return {
		"gap": gap, "width": w, "top_y": top_y, "mega": mega,
		"enemies": enemies, "entities": used, "climb": climb_dir,
		"void": false, "pillar": false, "stars": stars,
		"beacon": beacon, "rise": rise, "speed": v,
		"hop": climb_dir == -1 and climb_hop,
	}


## SPRINGS level (Neven's spec, round 2): an alternating rhythm, not one
## relentless diagonal. DECK sections — a few pillars at near-level /
## gentle-staircase heights with plain jumpable gaps — are breathers that
## cost no mana. Between sections come VOID CROSSINGS (_spawn_spring_void).
func _spawn_spring_chunk(d: float, v: float) -> Dictionary:
	# wind-down (Neven: the hand-off into BLOB BRIDGES must be as calm as
	# FLIPSIDE's into UMBRA): one continuous floor, before any deck/void roll
	if Levels.start_m(Levels.BRIDGES) - d <= WIND_DOWN_M:
		return _spawn_spring_outro(v)
	if spring_deck_left <= 0:
		return _spawn_spring_void(d, v)
	spring_deck_left -= 1
	var teach := _is_teach(d)
	var gap := (rng.randf_range(0.34, 0.42) if teach else rng.randf_range(0.36, 0.5)) * v
	var w := rng.randf_range(420.0, 560.0) if teach else rng.randf_range(340.0, 480.0)
	# staircase drift, always within plain-jump reach (rise <= 110 keeps
	# ~16% margin at gap 0.5*v); after a crossing pushed the deck skyward,
	# bias the stairs back down toward the base band
	var dy := rng.randf_range(-110.0, 110.0)
	if teach:
		dy = rng.randf_range(-60.0, 60.0)
	elif last_top_y < 560.0:
		dy = rng.randf_range(20.0, 130.0)
	var top_y := clampf(last_top_y + dy, 420.0, 940.0)
	var rise := maxf(0.0, last_top_y - top_y)
	var x := next_x + gap
	_place_chunk(x, top_y, w)
	# a fragment IN the pillar gap (Neven: springing the holes between
	# pillars ran the pool dry — the flight path itself must pay). Hung
	# over the gap above the higher rim, where both a plain jump and a
	# spring launch sweep it; sometimes the ORANGE +3.
	var gfrag := 0
	if rng.randf() < 0.6:
		var fy := minf(last_top_y, top_y) - rng.randf_range(160.0, 230.0)
		_place_coin(Vector2(next_x + gap * 0.5, fy), 3 if rng.randf() < 0.2 else 1)
		gfrag = 1
	var pu := _maybe_star(x, w, top_y, 0.05)
	var used := gfrag + pu
	if pu == 0 and rng.randf() < 0.35:
		_place_coin(Vector2(x + rng.randf_range(80.0, w - 80.0), top_y - 60.0))
		used += 1
	next_x = x + w
	last_top_y = top_y
	return {
		"gap": gap, "width": w, "top_y": top_y, "mega": false,
		"enemies": 0, "entities": used, "climb": 0,
		"void": false, "pillar": false, "spring": true, "svoid": false,
		"gfrag": gfrag, "stars": pu, "rise": rise, "speed": v,
	}


## The void crossing between deck sections (Neven round 3: DOUBLE the old
## width — one lazy pad was never a real reason to build). Far beyond any
## single launch: the line is run off the edge, pad, launch, second pad AT
## THE APEX, launch again, land the higher far deck. The fragment trail is
## sampled from that exact two-arc flight path (launch -1500, gravity 3300),
## so flying the intended line sweeps the crystals up naturally — and one
## fragment near the apex is sometimes the ORANGE +3, funding both pads
## with interest.
func _spawn_spring_void(d: float, v: float) -> Dictionary:
	var teach := _is_teach(d)
	spring_deck_left = 2 + rng.randi() % 3  # 2-4 easy pillars follow
	var gap := (rng.randf_range(1.1, 1.3) if teach else rng.randf_range(1.45, 1.7)) * v
	var up := rng.randf_range(80.0, 160.0) if teach else rng.randf_range(100.0, 220.0)
	var w := rng.randf_range(420.0, 540.0)
	var far_y := clampf(last_top_y - up, 340.0, 900.0)
	var rise := maxf(0.0, last_top_y - far_y)
	var x := next_x + gap
	_place_chunk(x, far_y, w)
	# pad 1 lands ~1/4 in (a beat of falling after running off, ~60 px down);
	# arc 1 peaks 0.45 s later at 341-60=281 px above takeoff, where pad 2 goes
	var y0 := last_top_y
	var pad1_x := 0.25 * gap
	var apex_x := pad1_x + 0.45 * v
	for i in range(5):
		var fx := gap * (0.34 + 0.15 * float(i))
		var tau: float
		var fy: float
		if fx <= apex_x:
			tau = (fx - pad1_x) / v
			fy = y0 + 60.0 - (1500.0 * tau - 1650.0 * tau * tau)
		else:
			tau = (fx - apex_x) / v
			fy = y0 - 281.0 - (1500.0 * tau - 1650.0 * tau * tau)
		var pos := Vector2(next_x + fx, fy)
		if i == 2 and rng.randf() < 0.3:
			_place_coin(pos, 3)  # the orange, riding the highest stretch
		else:
			_place_coin(pos)
	next_x = x + w
	last_top_y = far_y
	return {
		"gap": gap, "width": w, "top_y": far_y, "mega": false,
		"enemies": 0, "entities": 5, "climb": 0,
		"void": false, "pillar": false, "spring": true, "svoid": true,
		"stars": 0, "rise": rise, "speed": v,
	}


## SPRINGS wind-down (last WIND_DOWN_M meters): one continuous floor —
## overlapping strips, no voids, no spring pads, no fragments hung in
## holes — gliding DOWN from wherever the last deck section or crossing
## ended (as high as 340) back into the BRIDGES entry band before the
## first blob is ever shown. Strips only ever step DOWN (110-150 px, an
## easy run-off drop inside the overlap): a rise inside an overlap is a
## lip that stops the auto-runner dead — the FLIPSIDE runway lesson.
## 110 * 4 chunks >= the worst 440 px descent, so the floor always
## reaches the 780+ band in time for the BRIDGES teach-in clamp.
func _spawn_spring_outro(v: float) -> Dictionary:
	var start := next_x - 0.2 * v
	var w := (next_x - start) + rng.randf_range(0.9 * v, 1.2 * v)
	var dy := rng.randf_range(110.0, 150.0) if last_top_y < 770.0 else 0.0
	var out_y := clampf(last_top_y + dy, 420.0, 920.0)
	_place_chunk(start, out_y, w)
	var used := 0
	if rng.randf() < 0.35:
		_place_coin(Vector2(start + w * 0.6, out_y - 60.0))
		used = 1
	var gap := start - next_x  # negative: strips overlap what came before
	next_x = start + w
	last_top_y = out_y
	return {
		"gap": gap, "width": w, "top_y": out_y, "mega": false,
		"enemies": 0, "entities": used, "climb": 0,
		"void": false, "pillar": false, "spring": true, "svoid": false,
		"sout": true, "gfrag": 0, "stars": 0, "rise": 0.0, "speed": v,
	}


## FLIPSIDE level: a two-surface corridor of FLIP CHAINS — alternating
## floor and ceiling strips that share ONLY an overlap window (ov), so the
## run is a sustained rhythm of flip-run-flip-run, never longer than ~0.5 s
## on one surface. The flip transit takes ~0.54 s of fall, so strips are
## sized (>= 0.75*v) to guarantee a landing on the far strip when flipping
## anywhere in the shared window.
## DEAD ZONES (FLIP_DEAD_CHANCE, from EITHER lane): both surfaces vanish —
## beyond any jump, but one solid built platform (they work from both
## gravities here) always bridges it. Mana pressure, meet flips.
func _spawn_flip_chunk(d: float, v: float) -> Dictionary:
	var teach := _is_teach(d)
	# wind-down: hand the run back to plain floor before the next level
	var out_left := Levels.start_m(Levels.UMBRA) - d
	if out_left <= WIND_DOWN_M:
		return _spawn_flip_outro(v)
	# opening runway: one continuous plain floor — time to read the
	# FLIPSIDE banner before the first flip (Neven landed out of BRIDGES
	# straight into a flip prompt with no time to react).
	# EXACTLY at last_top_y: runway strips overlap what came before, and
	# any height drift inside that overlap is a lip that wedges (or drops)
	# the wizard right at the boundary — the step bug Neven hit.
	if d - Levels.start_m(Levels.FLIPSIDE) < RUNWAY_M:
		var run_y := clampf(last_top_y, 800.0, 920.0)
		var run_start := next_x - 0.3 * v
		var run_w := (next_x - run_start) + rng.randf_range(1.0 * v, 1.4 * v)
		_place_chunk(run_start, run_y, run_w)
		flip_on_floor = true
		flip_strip_start = run_start
		last_top_y = run_y
		var run_gap := run_start - next_x
		next_x = run_start + run_w
		return {
			"gap": run_gap, "width": run_w, "top_y": run_y, "mega": false,
			"enemies": 0, "entities": 0, "climb": 0,
			"void": false, "pillar": false, "flip": true, "dead": false,
			"runway": true, "overlap": -run_gap, "stars": 0, "rise": 0.0,
			"speed": v,
		}
	# teach-in: wider flip windows, longer strips, no dead zones yet
	var ov := (0.45 if teach else 0.30) * v
	var floor_y := clampf(last_top_y + rng.randf_range(-40.0, 40.0), 800.0, 940.0)

	# dead zone, rolled from EITHER lane (round 2 only cut the floor —
	# Neven: ceiling runs should meet gaps too). There is no jump in this
	# level, so crossing = run off the edge, catch yourself on ONE solid
	# pad built near the lost surface's height, run off it again. The far
	# strip always steps AWAY from the corridor middle (down for floor
	# runs, UP for ceiling runs) so the run-off drift has room to land.
	# A ceiling cut needs that headroom to exist inside the 800..940 floor
	# band, so it only rolls while the corridor rides low (face >= 310).
	# None near the wind-down: no hole right where gravity is handed back.
	var dead_ok := flip_on_floor or flip_ceil_y >= 310.0
	if not teach and dead_ok and out_left > WIND_DOWN_M + 20.0 \
			and rng.randf() < FLIP_DEAD_CHANCE:
		var gap := rng.randf_range(0.45 * v, 0.7 * v)
		var w := rng.randf_range(0.7 * v, 1.0 * v)
		var x := next_x + gap
		var used := 0
		# The cup rides the exact line you fall along after running off the
		# lost edge — the free-fall drop at mid-gap, measured in the wizard's
		# OWN gravity direction. The old placement hung it 240 px the other
		# way, out in the corridor: a marker for a crossing nobody can make,
		# pointing away from the pad that actually saves you (Neven).
		var fall_mid := 1650.0 * pow(gap * 0.5 / v, 2.0)
		var far_y: float
		if flip_on_floor:
			far_y = clampf(floor_y + rng.randf_range(60.0, 110.0), 800.0, 940.0)
			_place_chunk(x, far_y, w)
			if rng.randf() < 0.7:
				# the reward for paying the bridge toll hangs over the emptiness
				_place_coin(Vector2(next_x + gap * 0.5, last_top_y + fall_mid))
				used = 1
		else:
			# mirrored off the ACTUAL face the wizard runs (never the drifted
			# floor bookkeeping: a far ceiling even a hair lower than the
			# takeoff face is a wall to an upward-falling runner)
			var from_face := flip_ceil_y
			var face := flip_ceil_y \
					- rng.randf_range(60.0, minf(110.0, flip_ceil_y - 240.0))
			_place_ceiling(x, face, w)
			flip_ceil_y = face
			far_y = face + FLIP_CORRIDOR
			if rng.randf() < 0.7:
				_place_coin(Vector2(next_x + gap * 0.5, from_face - fall_mid))
				used = 1
		next_x = x + w
		last_top_y = far_y
		return {
			"gap": gap, "width": w, "top_y": far_y, "mega": false,
			"enemies": 0, "entities": used, "climb": 0,
			"void": false, "pillar": false, "flip": true, "dead": true,
			"dceil": not flip_on_floor,
			"overlap": ov, "stars": 0, "rise": 0.0, "speed": v,
		}

	# chain strip: the opposite surface, starting ov inside the current one.
	# It must outlast the whole shared window PLUS the transit that window can
	# start: a flip taken at the very last moment (ov in) touches down
	# FLIP_TRANSIT*v later, and a strip ending before that drops the run into
	# the hole. The old 0.75*v floor was 0.13*v short of that (Neven: chasing
	# the coffee off the end of the strip).
	var w := rng.randf_range(ov + FLIP_TRANSIT * v + 0.20 * v,
			ov + FLIP_TRANSIT * v + 0.45 * v)
	var start := next_x - ov
	flip_strip_start = start
	var used := 0
	if rng.randf() < 0.6:
		# Crystals mark the DESTINATION, not the transit. The old trail was
		# sampled along the corridor-crossing arc, which hung cups out past
		# the end of the surface the wizard was still standing on — follow
		# them without flipping and you ran straight off the edge (Neven).
		# They now hug the FAR strip at running height, starting just past
		# the earliest possible touchdown: the coffee says "be over there",
		# and flipping EARLY sweeps up more of it than flipping late.
		var far_face := (floor_y - FLIP_CORRIDOR) if flip_on_floor else floor_y
		# fragments sit off the WALKABLE face: below a ceiling, above a floor
		var side := 1.0 if flip_on_floor else -1.0
		for i in range(3):
			var fx := start + (FLIP_TRANSIT + 0.10 + 0.16 * float(i)) * v
			_place_coin(Vector2(fx, far_face + side * 60.0))
		used = 3
	if flip_on_floor:
		_place_ceiling(start, floor_y - FLIP_CORRIDOR, w)
		flip_ceil_y = floor_y - FLIP_CORRIDOR
	else:
		_place_chunk(start, floor_y, w)
		last_top_y = floor_y
	flip_on_floor = not flip_on_floor
	next_x = start + w
	return {
		"gap": -ov, "width": w, "top_y": floor_y, "mega": false,
		"enemies": 0, "entities": used, "climb": 0,
		"void": false, "pillar": false, "flip": true, "dead": false,
		"arc": used == 3, "overlap": ov, "stars": 0, "rise": 0.0, "speed": v,
	}


## The corridor's wind-down (last WIND_DOWN_M meters of FLIPSIDE): one
## continuous floor — no ceilings, no dead zones, no gaps — while Main
## rights gravity and taps become jumps again, so the level boundary can
## never eat a habitual flip into a hole (how Neven died). The first outro
## strip reaches back under the final ceiling strip: wherever the hand-back
## drops a ceiling runner, ground is waiting.
func _spawn_flip_outro(v: float) -> Dictionary:
	var floor_y := clampf(last_top_y, 800.0, 940.0)
	var start := next_x - 0.3 * v
	if not flip_on_floor:
		start = minf(start, flip_strip_start)
		flip_on_floor = true
	var gap := start - next_x  # negative: outro strips overlap what came before
	var w := (next_x - start) + rng.randf_range(0.9 * v, 1.2 * v)
	_place_chunk(start, floor_y, w)
	var used := 0
	if rng.randf() < 0.4:
		_place_coin(Vector2(start + w * 0.6, floor_y - 60.0))
		used = 1
	last_top_y = floor_y
	next_x = start + w
	return {
		"gap": gap, "width": w, "top_y": floor_y, "mega": false,
		"enemies": 0, "entities": used, "climb": 0,
		"void": false, "pillar": false, "flip": true, "dead": false,
		"overlap": -gap, "stars": 0, "rise": 0.0, "speed": v,
	}


## BLOB BRIDGES level, round 4 (Neven: too easy — the passive chain alone
## carried whole runs). Every non-wind-down gap still carries 1 or 2 blobs
## at the shared stomp height (deck - 90), and the layout is still derived
## from the bounce math (STOMP_BOUNCE -1000, gravity 3300):
##   - a ground jump falls through crown height ~0.58*v after the tap, so
##     the FIRST blob sits exactly 0.5*v past the takeoff edge: tap AT the
##     edge and the stomp lands (the ±95 px aim assist covers the rest);
##   - a PASSIVE double's second blob sits 0.6*v after the first (one
##     no-tap bounce, 0.606 s of hang) — the flow Neven liked;
##   - an ACTIVE double's second blob sits 1.3*v out: reachable ONLY by
##     riding the bounce down and spending the stomp-refresh jump LATE
##     (taps 0.39-0.60 s after the stomp fall through crown height
##     1.19-1.31*v out; the ±95 px assist does the rest). Later taps
##     carry farther, and the max possible carry is ~1.31*v — so at
##     1.3*v overshooting is geometrically impossible. 1.08*v (the
##     at-apex figure) and 1.2*v both got overshot by natural late taps
##     (Neven, twice): the tap is aimed, not timed — wait until the
##     falling wizard lines up with the crown;
##   - the bounce off the LAST blob falls back to deck level in 0.71 s, so
##     the far edge sits 0.50-0.56*v past it: the chain always lands INSIDE
##     the next deck.
## The band alternates the three: land-jump-stomp flow one gap, apex-tap
## gap-jump the next — never one rhythm long enough to go on autopilot.
func _spawn_bridge_chunk(d: float, v: float, budget: int) -> Dictionary:
	# wind-down: the last stretch before FLIPSIDE goes blob-free with plain
	# jumps and wide decks — the corridor is entered calm, not mid-panic
	if Levels.start_m(Levels.FLIPSIDE) - d <= WIND_DOWN_M:
		var out_gap := rng.randf_range(0.38, 0.48) * v
		var out_w := rng.randf_range(500.0, 700.0)
		# 800+ matches the runway's clamp band, so the hand-off can't step
		var out_y := clampf(last_top_y + rng.randf_range(-30.0, 30.0), 800.0, 920.0)
		var out_x := next_x + out_gap
		_place_chunk(out_x, out_y, out_w)
		var out_used := 0
		if rng.randf() < 0.4:
			_place_coin(Vector2(out_x + rng.randf_range(80.0, out_w - 80.0), out_y - 60.0))
			out_used = 1
		var out_rise := maxf(0.0, last_top_y - out_y)
		next_x = out_x + out_w
		last_top_y = out_y
		return {
			"gap": out_gap, "width": out_w, "top_y": out_y, "mega": false,
			"enemies": 0, "entities": out_used, "climb": 0,
			"void": false, "pillar": false, "bridge": true, "bkind": "out",
			"stars": 0, "rise": out_rise, "speed": v,
		}
	# teach-in: singles only and wide decks; the full band mixes singles,
	# passive doubles and ACTIVE doubles (the apex-tap gap-jump)
	var teach := _is_teach(d)
	var top_y := clampf(last_top_y + rng.randf_range(-30.0, 30.0), 780.0, 920.0)
	var blob_xs: Array = [0.5 * v]  # px past the takeoff edge, see above
	var active := false
	if not teach:
		var kind := rng.randf()
		if kind < 0.35:
			active = true
			blob_xs.append(0.5 * v + 1.3 * v)
		elif kind < 0.65:
			blob_xs.append(0.5 * v + 0.6 * v)
	# the far edge lands the passive bounce mid-deck; doubles trim the top
	# of the range so the fallback build (1.418*v + 240) still bridges them
	# (an active double's gap needs two)
	var last_bx: float = blob_xs[blob_xs.size() - 1]
	var gap: float = last_bx \
			+ rng.randf_range(0.50, 0.58 if blob_xs.size() == 1 else 0.56) * v
	var w := rng.randf_range(400.0, 500.0) if teach else rng.randf_range(240.0, 290.0)
	var blobs := mini(blob_xs.size(), budget)
	var x := next_x + gap
	_place_chunk(x, top_y, w)

	var deck_y := minf(last_top_y, top_y)
	for i in range(blobs):
		var bx: float = next_x + blob_xs[i]
		var b := SpikeBlob.new(bx - 40.0, bx + 40.0)
		b.position = Vector2(bx, deck_y - 90.0)
		b.speed = enemy_speed_for(d)
		add_child(b)

	# NO powerups in this band (Neven): a stored double jump lets the wizard
	# sail clean over the blob line, and the chain IS the level — nothing
	# may spawn here that lets the player skip playing it
	var used := blobs
	if used < budget and rng.randf() < 0.5:
		_place_coin(Vector2(x + rng.randf_range(80.0, w - 80.0), top_y - 60.0))
		used += 1

	var rise := maxf(0.0, last_top_y - top_y)
	next_x = x + w
	last_top_y = top_y
	return {
		"gap": gap, "width": w, "top_y": top_y, "mega": false,
		"enemies": blobs, "entities": used, "climb": 0,
		"void": false, "pillar": false, "bridge": true, "bkind": "blob",
		"blobs": blobs, "b1": blob_xs[0],
		"b2": blob_xs[1] if blobs == 2 else 0.0, "bact": active,
		"stars": 0, "rise": rise, "speed": v,
	}


## SPELLBROS level (Neven's spec, round 8): THE GROUND VANISHES. After
## ~25 m of entry runway the band is OPEN SKY — no pillars, no decks,
## no staircases — filled with an irregular field of floating blobs
## (BLOB BRIDGES' hovering crowns, but scattered: wandering line
## height, jittered spacings and altitudes, some stacked verticals) and
## a THICK rain of mana fragments. The band must read as IMPOSSIBLE —
## "WTF" — until the reveal: the brother burns every lethal contact
## for 1 mana. Traversal is the three verbs at once: BUILD a platform
## to run from (1 mana), STOMP what lines up (bounce + refresh jump
## + 1 mana bounty — blobs ARE income), and let the brother BURN what
## doesn't (1 mana). The economy must stay net-positive: fragments ride
## the inter-blob stomp arcs (some orange +3), and the audit asserts
## fragment income alone outpays the build demand. Every blob stays at
## y >= 340: crown + bounce + refresh jump tops out 40 px under the
## band's death ceiling (see Main), so legit flight never clips it.
## Teach-in: sparser blobs, richer fragments, no vertical stacks.
func _spawn_bros_chunk(d: float, v: float) -> Dictionary:
	# wind-down into THE VOID (Neven: the endgame must not appear until
	# the blobs are gone and the ground has run long and calm): the last
	# BROS_OUT_M meters are ONE continuous floor of overlapping strips —
	# no gaps, no blobs — catching the wizard out of the sky (last_top_y
	# still holds the entry runway's 780-920 height, so the floor appears
	# under the blob field) and only ever stepping DOWN inside the
	# overlap (a rise inside an overlap is a lip that stops the
	# auto-runner: the FLIPSIDE runway lesson).
	if PHASE_VOID - d <= BROS_OUT_M:
		climb_dir = 0
		climb_steps_left = 0
		var start := next_x - 0.2 * v
		var out_w := (next_x - start) + rng.randf_range(0.9 * v, 1.2 * v)
		var dy := rng.randf_range(110.0, 150.0) if last_top_y < 770.0 else 0.0
		var out_y := clampf(last_top_y + dy, 250.0, 920.0)
		_place_chunk(start, out_y, out_w)
		var out_used := 0
		if rng.randf() < 0.4:
			_place_coin(Vector2(start + out_w * 0.6, out_y - 60.0))
			out_used = 1
		# the endgame's fragment trail picks up where this floor leaves off
		void_y = clampf(out_y - 120.0, 340.0, 800.0)
		var out_gap := start - next_x  # negative: strips overlap seamlessly
		next_x = start + out_w
		last_top_y = out_y
		return {
			"gap": out_gap, "width": out_w, "top_y": out_y, "mega": false,
			"enemies": 0, "entities": out_used, "climb": 0,
			"void": false, "pillar": false, "bros": true, "gkind": "out",
			"blobs": 0, "pads": 0, "stars": 0, "rise": 0.0, "speed": v,
		}
	# entry runway (~25 m): the last ground the band shows — plain calm
	# decks while the banner lands and the brother fades in overhead.
	# No blobs: the WTF wall must hit as one picture, not trickle in.
	if d - Levels.start_m(Levels.BROS) < BROS_GROUND_M:
		var rgap := rng.randf_range(0.36, 0.44) * v
		var rw := rng.randf_range(1.2, 1.8) * v
		var r_y := clampf(last_top_y + rng.randf_range(-30.0, 30.0), 780.0, 920.0)
		var rx := next_x + rgap
		_place_chunk(rx, r_y, rw)
		var r_used := 0
		if rng.randf() < 0.5:
			_place_coin(Vector2(rx + rng.randf_range(80.0, rw - 80.0), r_y - 60.0))
			r_used = 1
		var r_rise := maxf(0.0, last_top_y - r_y)
		next_x = rx + rw
		last_top_y = r_y
		return {
			"gap": rgap, "width": rw, "top_y": r_y, "mega": false,
			"enemies": 0, "entities": r_used, "climb": 0,
			"void": false, "pillar": false, "bros": true, "gkind": "run",
			"blobs": 0, "stars": 0, "rise": r_rise, "speed": v,
		}
	# THE SKY: a segment of open air. The blob field rides a wandering
	# line (clamped 450-800: with ±110 jitter no blob tops y 340, the
	# death-ceiling guarantee), spacings and altitudes jittered so no
	# bounce rhythm survives, ~30% of crowns stacking a vertical partner.
	var teach := _is_teach(d)
	var L := rng.randf_range(1.0, 1.8) * v
	bros_line = clampf(bros_line + rng.randf_range(-160.0, 160.0), 450.0, 800.0)
	var espeed := enemy_speed_for(d)
	var xs: Array = []
	var bys: Array = []
	var cx := rng.randf_range(0.15, 0.3) * v
	while cx < L - 0.1 * v:
		xs.append(cx)
		bys.append(bros_line + rng.randf_range(-110.0, 110.0))
		cx += (rng.randf_range(0.35, 0.7) if teach else rng.randf_range(0.18, 0.45)) * v
	var k := 0
	var smin := 0.0
	var smax := 0.0
	var min_by := 999.0
	for i in range(xs.size()):
		var bx: float = next_x + xs[i]
		var by: float = bys[i]
		var b := SpikeBlob.new(bx - 40.0, bx + 40.0)
		b.position = Vector2(bx, by)
		b.speed = espeed
		add_child(b)
		k += 1
		min_by = minf(min_by, by)
		if i > 0:
			var sp: float = xs[i] - xs[i - 1]
			smin = sp if smin == 0.0 else minf(smin, sp)
			smax = maxf(smax, sp)
		# vertical stacks thicken the wall (never in the teach-in); the
		# upper partner keeps the y >= 360 ceiling margin
		if not teach and rng.randf() < 0.3:
			var dv := rng.randf_range(170.0, 260.0)
			var by2: float = by - dv if by - dv >= 360.0 and rng.randf() < 0.5 \
					else minf(by + dv, 880.0)
			var b2 := SpikeBlob.new(bx - 40.0, bx + 40.0)
			b2.position = Vector2(bx, by2)
			b2.speed = espeed
			add_child(b2)
			k += 1
			min_by = minf(min_by, by2)
	# the mana rain (Neven: he MUST come out ahead): a fragment rides
	# most inter-blob stomp arcs, some orange +3, plus strays — richer
	# through the teach-in while the verbs are still being learned
	var coins := 0
	for i in range(xs.size() - 1):
		if rng.randf() < (0.8 if teach else 0.6):
			var fy: float = minf(bys[i], bys[i + 1]) - rng.randf_range(130.0, 180.0)
			_place_coin(Vector2(next_x + (xs[i] + xs[i + 1]) * 0.5, maxf(fy, 360.0)),
					3 if not teach and rng.randf() < 0.2 else 1)
			coins += 1
	if rng.randf() < 0.5:
		_place_coin(Vector2(next_x + rng.randf_range(0.2, 0.8) * L,
				clampf(bros_line + rng.randf_range(-200.0, 60.0), 360.0, 860.0)))
		coins += 1
	next_x += L
	return {
		"gap": L, "width": 0.0, "top_y": bros_line, "mega": false,
		"enemies": k, "entities": k + coins, "climb": 0,
		"void": false, "pillar": false, "bros": true, "gkind": "sky",
		"blobs": k, "smin": smin, "smax": smax, "min_by": min_by,
		"stars": 0, "rise": 0.0, "speed": v,
	}


## The endgame: mostly open sky. Fragment trails must be caught with
## well-placed platforms to sustain the mana economy; a rare narrow
## pillar offers solid ground from time to time.
func _spawn_void_segment() -> Dictionary:
	var d: float = (next_x - main.start_x) / 100.0 + main.start_offset_m
	var v: float = main.run_speed_for(d)
	void_y = clampf(void_y + rng.randf_range(-140.0, 140.0), 340.0, 800.0)

	# teach-in: solid pillars twice as often, shorter fragment trails
	var teach := _is_teach(d)
	if rng.randf() < (0.6 if teach else 0.3):
		# gap as a fraction of live speed (0.62 < 0.709 flat reach) so pillars
		# stay jumpable no matter what speed the void is entered at
		var gap := rng.randf_range(0.42 * v, 0.62 * v)
		var w := rng.randf_range(220.0, 340.0)
		var top_y := clampf(void_y + 120.0, 500.0, 940.0)
		var x := next_x + gap
		_place_chunk(x, top_y, w)
		var ents := 0
		if rng.randf() < 0.7:
			_place_coin(Vector2(x + w * 0.5, top_y - 60.0))
			ents = 1
		next_x = x + w
		last_top_y = top_y
		void_y = top_y - 160.0
		return {"gap": gap, "width": w, "top_y": top_y, "mega": false,
				"enemies": 0, "entities": ents, "climb": 0,
				"void": false, "pillar": true, "stars": 0,
				"rise": 0.0, "speed": v}

	var length := rng.randf_range(700.0, 1000.0) if teach else rng.randf_range(900.0, 1500.0)
	var n := int(length / 380.0) + 1
	for i in range(n):
		var cx := next_x + length * (float(i) + 0.5) / float(n)
		var cy := clampf(void_y + rng.randf_range(-70.0, 70.0), 320.0, 820.0)
		_place_coin(Vector2(cx, cy))
	next_x += length
	return {"gap": length, "width": 0.0, "top_y": void_y, "mega": false,
			"enemies": 0, "entities": n, "climb": 0,
			"void": true, "pillar": false, "stars": 0,
			"rise": 0.0, "speed": v}


func _update_climb_state(d: float) -> void:
	if climb_dir == 0:
		flat_chunks_since_wave += 1
		# occasional set-piece: needs a breather of flat terrain first
		if d >= PHASE_CLIMB and last_top_y > 800.0 and not _is_teach(d) \
				and flat_chunks_since_wave >= CLIMB_COOLDOWN and rng.randf() < CLIMB_CHANCE:
			climb_dir = -1
			climb_steps_left = 2 + rng.randi() % 3
			# the flavour is chosen once per wave and holds for every step
			climb_hop = rng.randf() < CLIMB_HOP_CHANCE
	elif climb_dir == -1:
		# A wave turns around while there is still room for a FULL step. The
		# old check let one last step get clamped against SKY_Y_MIN, which
		# quietly emitted a stair of some other height than the flavour asked
		# for — and for BUILD steps that broke the pad geometry outright.
		var headroom := CLIMB_HOP_RISE_MAX if climb_hop else CLIMB_BUILD_RISE_MAX
		if climb_steps_left <= 0 or last_top_y - headroom <= SKY_Y_MIN:
			climb_dir = 1
	else:
		if last_top_y >= 860.0:
			climb_dir = 0
			flat_chunks_since_wave = 0


## Blob patrol speed ramps from PHASE_SWARM so late enemies are harder to
## time a stomp on (still well below run speed, so never unavoidable).
## True inside a level's opening teach-in stretch (never in FOUNDATIONS,
## which has its own phase curve).
func _is_teach(d: float) -> bool:
	var lv := Levels.level_for(d)
	return lv > 0 and d - Levels.start_m(lv) < TEACH_M


## Where the jump off a BUILD step's lower deck comes back DOWN through pad
## height — so where the marker cup, and therefore the pad, belongs. It falls
## straight out of the jump arc (GRAVITY 3300, JUMP_VELOCITY -1170) and scales
## with the run speed, which is the whole fix: at the 900 px/s cap the wizard
## is still rising 400 px out, so a pad parked mid-gap at a fixed 150-210 px
## was somewhere he simply never passed through.
func climb_pad_x(v: float) -> float:
	return v * (1170.0 + sqrt(1170.0 * 1170.0 - 6600.0 * CLIMB_PAD_H)) / 3300.0


func enemy_speed_for(d: float) -> float:
	var f := clampf((d - PHASE_SWARM) / (ENEMY_SPEED_RAMP_END - PHASE_SWARM), 0.0, 1.0)
	return lerpf(ENEMY_SPEED_BASE, ENEMY_SPEED_MAX, f)


func _place_chunk(x: float, top_y: float, w: float) -> void:
	var chunk := GroundChunk.new(w)
	chunk.position = Vector2(x, top_y)
	add_child(chunk)


## Ceiling slab for FLIPSIDE: its BOTTOM face (at ceil_y) is the walkable
## surface once gravity is flipped; the slab fills the screen upward.
func _place_ceiling(x: float, ceil_y: float, w: float) -> void:
	var chunk := GroundChunk.new(w)
	chunk.ceiling = true
	chunk.position = Vector2(x, ceil_y - GroundChunk.THICK)
	add_child(chunk)


## Occasional Star of Levity for the themed bands (Neven: powerups in
## later levels too, always easy to take): mid-deck at running height,
## walked into mid-flow. SPRINGS decks and SPELLBROS floaters roll this;
## BLOB BRIDGES never does (a stored double jump would let the wizard
## skip the chain the band is about). Never a shield — see the
## star_given comment block.
func _maybe_star(x: float, w: float, top_y: float, chance: float) -> int:
	if rng.randf() >= chance:
		return 0
	_place_star(Vector2(x + w * 0.5, top_y - 60.0))
	return 1


func _place_star(pos: Vector2) -> void:
	var star := StarPickup.new()
	star.position = pos
	add_child(star)


func _place_coin(pos: Vector2, amount: int = 1) -> void:
	var coin := ManaCrystal.new()
	coin.amount = amount
	coin.position = pos
	# UMBRA: crystals carry their own light so they beacon through the dark
	var d: float = (pos.x - main.start_x) / 100.0 + main.start_offset_m
	coin.lit = Levels.level_for(d) == Levels.UMBRA
	add_child(coin)
