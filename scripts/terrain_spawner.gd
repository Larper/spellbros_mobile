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
## Wind-down: a band's last meters return to calm, plain terrain before the
## next level's twist (FLIPSIDE: continuous floor + taps become jumps again;
## BRIDGES: blob-free easy gaps). RUNWAY_M: FLIPSIDE's opening stretch stays
## a plain continuous floor so the level banner registers before the first
## flip is ever asked for.
const WIND_DOWN_M := 45.0
const RUNWAY_M := 20.0

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

# SPELLBROS rhythm state: megas never twice in a row (the pool can't
# fund back-to-back crossing tolls)
var bros_mega_last := false

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
		# stair step up, beyond jump height: must build
		gap = rng.randf_range(150.0, 230.0)
		w = rng.randf_range(320.0, 480.0)
		dy = -rng.randf_range(240.0, 300.0)
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
		var far_y: float
		if flip_on_floor:
			far_y = clampf(floor_y + rng.randf_range(60.0, 110.0), 800.0, 940.0)
			_place_chunk(x, far_y, w)
			if rng.randf() < 0.7:
				# the reward for paying the bridge toll hangs over the emptiness
				_place_coin(Vector2(next_x + gap * 0.5, floor_y - 240.0))
				used = 1
		else:
			# mirrored off the ACTUAL face the wizard runs (never the drifted
			# floor bookkeeping: a far ceiling even a hair lower than the
			# takeoff face is a wall to an upward-falling runner)
			var face := flip_ceil_y \
					- rng.randf_range(60.0, minf(110.0, flip_ceil_y - 240.0))
			_place_ceiling(x, face, w)
			flip_ceil_y = face
			far_y = face + FLIP_CORRIDOR
			if rng.randf() < 0.7:
				_place_coin(Vector2(next_x + gap * 0.5, face + 240.0))
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

	# chain strip: the opposite surface, starting ov inside the current one
	var w := rng.randf_range(1.1 * v, 1.4 * v) if teach else rng.randf_range(0.75 * v, 1.1 * v)
	var start := next_x - ov
	flip_strip_start = start
	var used := 0
	if rng.randf() < 0.6:
		# crystals ride the FLIP TRANSIT itself: sampled from the corridor-
		# crossing free-fall arc (gravity 3300 from rest), fired from MID
		# window — chasing the mana IS taking the flip on time. Random
		# placements read as noise in this level (Neven), and the trail
		# starts 129 px off the surface (tau 0.28): a fragment hugging a
		# strip's edge baits the player toward the drop-off (Neven again).
		var x0 := start + 0.45 * ov
		for tau: float in [0.28, 0.42, 0.54]:
			var fall := 1650.0 * tau * tau
			var fy := (floor_y - 20.0 - fall) if flip_on_floor \
					else (floor_y - FLIP_CORRIDOR + 20.0 + fall)
			_place_coin(Vector2(x0 + v * tau, fy))
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


## SPELLBROS level (Neven's spec, round 6): UMBRA's structure, SATURATED
## with blobs. The band must read as IMPOSSIBLE on first sight — "WTF" —
## until the player realizes the brother is burning the wall away for
## mana instead of letting them die. The skeleton is still the standard
## generator's — plain gaps under the rise rule, mega gaps (one built
## platform), climb staircases up and down — but now EVERYTHING is blob
## country: the staircases carry squatters on their steps (round 5 left
## them bare — Neven), every deck runs a cramped irregular wall
## (spacings mostly 0.12-0.22*v), and LONG decks (~40%, 5-9*v) stack
## 2-3 STOREYS of dense mid-air one-way platforms — most of them
## blob-ridden too, some carrying a fragment or the band's star spot.
## Stomp what lines up, let the brother burn what doesn't (1 mana each),
## refill from the thick fragment arcs (some orange +3) and the stomp
## bounties. Geometry guarantees: the first deck blob stays clear of the
## entry landing, and every deck keeps >= 0.7*v of tail so the bounce
## off its LAST blob (0.663*v of carry) lands ON deck, never in the
## next gap. Teach-in: short mild decks — no megas, no stairs, no
## floaters (the wall of the full band hits right after the banner).
func _spawn_bros_chunk(d: float, v: float) -> Dictionary:
	# wind-down into THE VOID: plain calm hops, nothing left to burn
	if PHASE_VOID - d <= WIND_DOWN_M:
		climb_dir = 0
		climb_steps_left = 0
		var out_gap := rng.randf_range(0.36, 0.46) * v
		var out_w := rng.randf_range(500.0, 700.0)
		var out_y := clampf(last_top_y + rng.randf_range(-30.0, 30.0), 780.0, 920.0)
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
			"void": false, "pillar": false, "bros": true, "gkind": "out",
			"blobs": 0, "pads": 0, "stars": 0, "rise": out_rise, "speed": v,
		}
	var teach := _is_teach(d)
	if not teach:
		_update_climb_state(d)
	# staircases, straight from the standard generator (UMBRA's structure):
	# up-steps rise beyond jump height and demand one build each — blob-free,
	# stairs are about building — and down-steps are easy drops
	if climb_dir != 0:
		var sgap := rng.randf_range(150.0, 230.0 if climb_dir == -1 else 240.0)
		var sw := rng.randf_range(320.0, 480.0) if climb_dir == -1 \
				else rng.randf_range(360.0, 520.0)
		var sdy := -rng.randf_range(240.0, 300.0) if climb_dir == -1 \
				else rng.randf_range(200.0, 280.0)
		if climb_dir == -1:
			climb_steps_left -= 1
		var s_y := clampf(last_top_y + sdy, SKY_Y_MIN, BASE_Y_MAX)
		var sx := next_x + sgap
		_place_chunk(sx, s_y, sw)
		# the stairs are blob country too (round 5 left them bare — Neven):
		# most steps carry a patrolling squatter right where the build
		# lands — stomp it on arrival or pay the brother a fragment
		var sblobs := 0
		if rng.randf() < 0.75:
			sblobs = 1
			var sb := SpikeBlob.new(sx + 60.0, sx + sw - 60.0)
			sb.position = Vector2(sx + rng.randf_range(90.0, sw - 90.0), s_y - 30.0)
			sb.speed = enemy_speed_for(d)
			add_child(sb)
		var s_used := sblobs
		if rng.randf() < MANA_CHANCE_CLIMB:
			_place_coin(Vector2(sx + rng.randf_range(80.0, sw - 80.0), s_y - 60.0))
			s_used += 1
		var s_rise := maxf(0.0, last_top_y - s_y)
		next_x = sx + sw
		last_top_y = s_y
		return {
			"gap": sgap, "width": sw, "top_y": s_y, "mega": false,
			"enemies": sblobs, "entities": s_used, "climb": climb_dir,
			"void": false, "pillar": false, "bros": true, "gkind": "gaunt",
			"blobs": sblobs, "pads": 0, "stars": 0, "rise": s_rise, "speed": v,
		}
	# the gap: standard-rule plain jump, or a mega demanding one built
	# platform — never two megas in a row, none in the teach-in
	var mega_gap: bool = not teach and not bros_mega_last and rng.randf() < 0.3
	bros_mega_last = mega_gap
	var gap: float
	var dy: float
	if mega_gap:
		gap = rng.randf_range(0.95, 1.25) * v
		dy = rng.randf_range(-40.0, 160.0)
	else:
		gap = rng.randf_range(GAP_MIN_FRAC, 0.5 if teach else GAP_MAX_FRAC) * v
		# the standard rise rule: wide gaps never land higher
		dy = rng.randf_range(0.0 if gap > GAP_RISE_FRAC * v else -GAP_MAX_RISE, 170.0)
	if teach:
		dy = rng.randf_range(-40.0, 40.0)
	var top_y := clampf(last_top_y + dy, BASE_Y_MIN, 940.0)
	if mega_gap:
		# the reward for paying the crossing toll hangs over the emptiness
		_place_coin(Vector2(next_x + gap * 0.5, minf(last_top_y, top_y) - 190.0))
	# the deck: short pillars or long gauntlets, ~40% long
	var long_deck: bool = not teach and rng.randf() < 0.4
	var w: float
	if teach:
		w = rng.randf_range(2.0, 2.6) * v
	elif long_deck:
		w = rng.randf_range(5.0, 9.0) * v
	else:
		w = rng.randf_range(1.2, 1.7) * v
	var lead := minf(rng.randf_range(0.5, 0.7) * v, w - 0.7 * v)
	var x := next_x + gap
	_place_chunk(x, top_y, w)
	var espeed := enemy_speed_for(d)
	# THE AIR IS FULL over long decks: 2-3 STOREYS of dense one-way
	# platforms, each 150-185 px above the one below (hop-up-able:
	# < 207 max jump) and blob-ridden like the deck itself. One storey
	# was cheesable (Neven: build a private lane right above it and run
	# the whole band untouched) — now every buildable lane inside the
	# static frame is already blob country, and above the top storey the
	# wizard flies blind over the camera. Blob-free pads pay a fragment
	# or the band's one easy-to-take star spot instead.
	var pads := 0
	var pblobs := 0
	var pad_rise := 0.0
	var storeys := 0
	var pad_spans: Array = []
	var pu := 0
	var coins := 0
	if long_deck:
		var base := top_y
		for st in range(2 + (1 if rng.randf() < 0.5 else 0)):
			var pr := rng.randf_range(150.0, 185.0)
			var lvl_y := base - pr
			if lvl_y < 320.0:
				break  # stay inside the static frame (view top is 188)
			storeys += 1
			pad_rise = maxf(pad_rise, pr)
			var px := rng.randf_range(0.4, 0.9) * v
			while px + 0.5 * v < w - 0.5 * v:
				var pw := rng.randf_range(0.42, 0.6) * v
				_place_float(x + px, lvl_y, pw)
				if st == 0:
					# only the first storey shadows the deck's coin arcs
					pad_spans.append([px, px + pw])
				pads += 1
				if rng.randf() < 0.7:
					pblobs += 1
					var pb := SpikeBlob.new(x + px + 50.0, x + px + pw - 50.0)
					pb.position = Vector2(x + px + pw * 0.5, lvl_y - 30.0)
					pb.speed = espeed
					add_child(pb)
				elif pu == 0 and rng.randf() < 0.2:
					pu = _maybe_star(x + px, pw, lvl_y, 1.0)
				else:
					_place_coin(Vector2(x + px + pw * 0.5, lvl_y - 60.0))
					coins += 1
				px += pw + rng.randf_range(0.35, 0.7) * v
			base = lvl_y
	# the blob line: fill the deck, keeping the landable tail free
	var bxs: Array = [lead]
	while true:
		var sp: float
		if teach:
			sp = rng.randf_range(0.5, 0.8) * v
		else:
			var r := rng.randf()
			if r < 0.75:
				sp = rng.randf_range(0.12, 0.22) * v  # the cramped wall
			elif r < 0.92:
				sp = rng.randf_range(0.25, 0.42) * v
			else:
				sp = rng.randf_range(0.5, 0.7) * v  # a rare breather
		if bxs[bxs.size() - 1] + sp > w - 0.7 * v:
			break
		bxs.append(bxs[bxs.size() - 1] + sp)
	var k := bxs.size()
	var smin := 0.0
	var smax := 0.0
	for i in range(k):
		var bx: float = x + bxs[i]
		var b := SpikeBlob.new(bx - 40.0, bx + 40.0)
		b.position = Vector2(bx, top_y - 30.0)
		b.speed = espeed
		add_child(b)
		if i > 0:
			var sp: float = bxs[i] - bxs[i - 1]
			smin = sp if smin == 0.0 else minf(smin, sp)
			smax = maxf(smax, sp)
	for i in range(k - 1):
		# thick arcs: burning through the wall costs, so the wall pays
		if rng.randf() < 0.45:
			var cx: float = (bxs[i] + bxs[i + 1]) * 0.5
			# never under a floater: a fragment at deck-200 inside a pad's
			# span visually collides with the slab hanging at deck~175
			var covered := false
			for span: Array in pad_spans:
				if cx >= span[0] and cx <= span[1]:
					covered = true
					break
			if covered:
				continue
			var amt := 3 if rng.randf() < 0.22 else 1
			_place_coin(Vector2(x + cx, top_y - 200.0), amt)
			coins += 1
	var rise := maxf(0.0, last_top_y - top_y)
	next_x = x + w
	last_top_y = top_y
	return {
		"gap": gap, "width": w, "top_y": top_y, "mega": mega_gap,
		"enemies": k + pblobs,
		"entities": k + pblobs + coins + pu + (1 if mega_gap else 0),
		"climb": 0, "void": false, "pillar": false, "bros": true,
		"gkind": "gaunt", "mgap": mega_gap, "long": long_deck, "blobs": k,
		"pads": pads, "pblobs": pblobs, "pad_rise": pad_rise, "storeys": storeys,
		"lead": lead, "smin": smin, "smax": smax, "tail": w - bxs[k - 1],
		"stars": pu, "rise": rise, "speed": v,
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
	elif climb_dir == -1:
		if climb_steps_left <= 0 or last_top_y <= SKY_Y_MIN + 20.0:
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


## Thin one-way slab hovering over a long SPELLBROS deck: jump or stomp-
## bounce up THROUGH it, land on top, run a blob-free stretch, drop off
## the end back into the wall.
func _place_float(x: float, top_y: float, w: float) -> void:
	var chunk := GroundChunk.new(w, 26.0, true)
	chunk.position = Vector2(x, top_y)
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
