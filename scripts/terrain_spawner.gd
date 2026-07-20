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

# SPRINGS rhythm state: pillars left in the current easy deck section;
# when it reaches 0 the next chunk is a void crossing
var spring_deck_left := 3


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

	_update_climb_state(d)

	var teach := _is_teach(d)
	var mega: bool = not teach and climb_dir == 0 and d >= PHASE_BUILD \
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
	elif teach:
		# teach-in: easy gaps, wide decks, near-flat — room to meet the twist
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

	# enemies (never on climb stairs — those are about building — and never
	# in a teach-in stretch)
	var enemies := 0
	if d >= PHASE_ENEMY and w > ENEMY_MIN_W and climb_dir == 0 and not teach:
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
	# reliably so stairs stay affordable
	var mana_chance := MANA_CHANCE_CLIMB if climb_dir != 0 else MANA_CHANCE
	if used < budget and rng.randf() < mana_chance:
		var coin_y := top_y - 60.0 if rng.randf() < 0.7 else top_y - 250.0
		_place_coin(Vector2(x + rng.randf_range(80.0, w - 80.0), coin_y))
		used += 1

	# rare Star of Levity: a stored air-jump, hung high to invite a leap.
	# Competes for the same entity budget so it never inflates the economy.
	var stars := 0
	if d >= PHASE_ENEMY and used < budget and rng.randf() < 0.08:
		_place_star(Vector2(x + rng.randf_range(100.0, w - 100.0), top_y - 280.0))
		used += 1
		stars = 1

	var rise := maxf(0.0, last_top_y - top_y)
	next_x = x + w
	last_top_y = top_y
	return {
		"gap": gap, "width": w, "top_y": top_y, "mega": mega,
		"enemies": enemies, "entities": used, "climb": climb_dir,
		"void": false, "pillar": false, "stars": stars,
		"rise": rise, "speed": v,
	}


## SPRINGS level (Neven's spec, round 2): an alternating rhythm, not one
## relentless diagonal. DECK sections — a few pillars at near-level /
## gentle-staircase heights with plain jumpable gaps — are breathers that
## cost no mana. Between sections come VOID CROSSINGS (_spawn_spring_void).
func _spawn_spring_chunk(d: float, v: float) -> Dictionary:
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
	var used := 0
	if rng.randf() < 0.35:
		_place_coin(Vector2(x + rng.randf_range(80.0, w - 80.0), top_y - 60.0))
		used = 1
	next_x = x + w
	last_top_y = top_y
	return {
		"gap": gap, "width": w, "top_y": top_y, "mega": false,
		"enemies": 0, "entities": used, "climb": 0,
		"void": false, "pillar": false, "spring": true, "svoid": false,
		"stars": 0, "rise": rise, "speed": v,
	}


## The void crossing between deck sections: open sky far beyond any jump,
## with a diagonal trail of fragments rising toward a higher far deck. The
## intended move: drop ONE spring pad in the gap (every build here launches
## at -1500, a 341 px rise), ride the launch up the fragment diagonal, land
## on the next deck section. The 3-crystal trail out-pays the 1-mana pad.
func _spawn_spring_void(d: float, v: float) -> Dictionary:
	var teach := _is_teach(d)
	spring_deck_left = 2 + rng.randi() % 3  # 2-4 easy pillars follow
	var gap := (rng.randf_range(0.65, 0.8) if teach else rng.randf_range(0.8, 1.0)) * v
	var up := rng.randf_range(60.0, 120.0) if teach else rng.randf_range(100.0, 200.0)
	var w := rng.randf_range(420.0, 540.0) if teach else rng.randf_range(380.0, 500.0)
	var far_y := clampf(last_top_y - up, 360.0, 900.0)
	var rise := maxf(0.0, last_top_y - far_y)
	var x := next_x + gap
	_place_chunk(x, far_y, w)
	# the fragment diagonal: takeoff edge up to the far deck's crown
	for i in range(3):
		var f := (float(i) + 1.0) / 4.0
		_place_coin(Vector2(next_x + gap * f,
				lerpf(last_top_y - 90.0, far_y - 110.0, f)))
	next_x = x + w
	last_top_y = far_y
	return {
		"gap": gap, "width": w, "top_y": far_y, "mega": false,
		"enemies": 0, "entities": 3, "climb": 0,
		"void": false, "pillar": false, "spring": true, "svoid": true,
		"stars": 0, "rise": rise, "speed": v,
	}


## FLIPSIDE level: a two-surface corridor of FLIP CHAINS — alternating
## floor and ceiling strips that share ONLY an overlap window (ov), so the
## run is a sustained rhythm of flip-run-flip-run, never longer than ~0.5 s
## on one surface. The flip transit takes ~0.54 s of fall, so strips are
## sized (>= 0.75*v) to guarantee a landing on the far strip when flipping
## anywhere in the shared window.
## DEAD ZONES (FLIP_DEAD_CHANCE, floor side only): both surfaces vanish for
## 0.8-1.2*v — beyond any jump, but one solid built platform (they work
## from both gravities here) always bridges it. Mana pressure, meet flips.
func _spawn_flip_chunk(d: float, v: float) -> Dictionary:
	var teach := _is_teach(d)
	# teach-in: wider flip windows, longer strips, no dead zones yet
	var ov := (0.45 if teach else 0.30) * v
	var floor_y := clampf(last_top_y + rng.randf_range(-40.0, 40.0), 800.0, 940.0)

	# dead zone: only rolled while the wizard's lane is the floor. There is
	# no jump in this level, so crossing = run off the edge, catch yourself
	# on ONE pad built near deck height, run off it again. Gaps are sized
	# for a single pad and the far deck steps DOWN so the drift has room.
	if not teach and flip_on_floor and rng.randf() < FLIP_DEAD_CHANCE:
		var gap := rng.randf_range(0.45 * v, 0.7 * v)
		var w := rng.randf_range(0.7 * v, 1.0 * v)
		var far_y := clampf(floor_y + rng.randf_range(60.0, 110.0), 800.0, 940.0)
		var x := next_x + gap
		_place_chunk(x, far_y, w)
		var used := 0
		if rng.randf() < 0.7:
			# the reward for paying the bridge toll hangs over the emptiness
			_place_coin(Vector2(next_x + gap * 0.5, floor_y - 240.0))
			used = 1
		next_x = x + w
		last_top_y = far_y
		return {
			"gap": gap, "width": w, "top_y": far_y, "mega": false,
			"enemies": 0, "entities": used, "climb": 0,
			"void": false, "pillar": false, "flip": true, "dead": true,
			"overlap": ov, "stars": 0, "rise": 0.0, "speed": v,
		}

	# chain strip: the opposite surface, starting ov inside the current one
	var w := rng.randf_range(1.1 * v, 1.4 * v) if teach else rng.randf_range(0.75 * v, 1.1 * v)
	var start := next_x - ov
	if flip_on_floor:
		_place_ceiling(start, floor_y - FLIP_CORRIDOR, w)
	else:
		_place_chunk(start, floor_y, w)
		last_top_y = floor_y
	flip_on_floor = not flip_on_floor
	var used := 0
	if rng.randf() < 0.5:
		# crystal mid-corridor over the flip window: timing is the detour
		_place_coin(Vector2(start + ov * 0.5, floor_y - FLIP_CORRIDOR * 0.5))
		used = 1
	next_x = start + w
	return {
		"gap": -ov, "width": w, "top_y": floor_y, "mega": false,
		"enemies": 0, "entities": used, "climb": 0,
		"void": false, "pillar": false, "flip": true, "dead": false,
		"overlap": ov, "stars": 0, "rise": 0.0, "speed": v,
	}


## BLOB BRIDGES level: sparse pillars split by gaps wider than any jump,
## with drifting sky blobs hovering over each gap. Chain stomps to cross
## (each stomp refreshes the air jump and pays the +1 bounty) — or spend
## 1 mana to bridge the old-fashioned way.
func _spawn_bridge_chunk(d: float, v: float, budget: int) -> Dictionary:
	# teach-in: the narrowest bridge gaps, wide pillars, always one blob
	var teach := _is_teach(d)
	var gap := rng.randf_range(0.75 * v, 0.85 * v) if teach else rng.randf_range(0.75 * v, 1.05 * v)
	var w := rng.randf_range(400.0, 500.0) if teach else rng.randf_range(280.0, 400.0)
	var top_y := clampf(last_top_y + rng.randf_range(-60.0, 60.0), BASE_Y_MIN, BASE_Y_MAX)
	var x := next_x + gap
	_place_chunk(x, top_y, w)

	# stepping-stone blobs, one per jump-length of gap, at stomp height
	var blobs := 1 if teach or gap < 0.9 * v else 2
	blobs = mini(blobs, budget)
	var deck_y := minf(last_top_y, top_y)
	var seg := gap / float(blobs)
	for j in range(blobs):
		var left := next_x + seg * float(j) + 60.0
		var right := next_x + seg * float(j + 1) - 60.0
		var b := SpikeBlob.new(left, right)
		b.position = Vector2((left + right) * 0.5, deck_y - 90.0)
		b.speed = enemy_speed_for(d)
		add_child(b)

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
		"void": false, "pillar": false, "bridge": true, "stars": 0,
		"rise": rise, "speed": v,
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


func _place_star(pos: Vector2) -> void:
	var star := StarPickup.new()
	star.position = pos
	add_child(star)


func _place_coin(pos: Vector2) -> void:
	var coin := ManaCrystal.new()
	coin.position = pos
	# UMBRA: crystals carry their own light so they beacon through the dark
	var d: float = (pos.x - main.start_x) / 100.0 + main.start_offset_m
	coin.lit = Levels.level_for(d) == Levels.UMBRA
	add_child(coin)
