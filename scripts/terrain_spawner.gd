class_name TerrainSpawner
extends Node2D

## Endless procedural terrain with staged difficulty phases:
##   0 m+    easy jumpable gaps, sparse mana, no enemies
##   40 m+   mega gaps appear (~every 2-3 gaps) that require building
##   80 m+   enemies start to spawn
##   120 m+  climb waves: terrain staircases up beyond jump height, then back down
##   190 m+  run speed ramps (constant used by Main)
##   260 m+  enemy swarms: higher chance, up to two per chunk
## Entity budget: max 2 things (enemies + mana) per chunk, 3 after 400 m,
## so mana stays scarce and every fragment matters.

const START_GROUND_Y := 880.0
const SPAWN_AHEAD := 2400.0
const CLEANUP_BEHIND := 1400.0

const PHASE_BUILD := 40.0
const PHASE_ENEMY := 80.0
const PHASE_CLIMB := 120.0
const PHASE_SPEED := 190.0
const PHASE_SWARM := 260.0
const PHASE_RICH := 400.0

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
	var d: float = (next_x - main.start_x) / 100.0
	var t := minf(d / 500.0, 1.0)
	var budget := 3 if d >= PHASE_RICH else 2

	_update_climb_state(d)

	var mega := climb_dir == 0 and d >= PHASE_BUILD \
			and rng.randf() < minf(0.4 + 0.1 * t, 0.5)
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
		gap = rng.randf_range(500.0, lerpf(700.0, 1000.0, t))
		w = rng.randf_range(500.0, 800.0)
		dy = rng.randf_range(-40.0, 160.0)
	else:
		gap = rng.randf_range(lerpf(140.0, 180.0, t), lerpf(240.0, 330.0, t))
		w = rng.randf_range(lerpf(520.0, 430.0, t), lerpf(950.0, 700.0, t))
		dy = rng.randf_range(-110.0, 170.0)

	var y_min := SKY_Y_MIN if climb_dir != 0 else BASE_Y_MIN
	var top_y := clampf(last_top_y + dy, y_min, BASE_Y_MAX)

	var x := next_x + gap
	_place_chunk(x, top_y, w)

	var used := 0

	# one crystal floating over a mega gap: reward for bridging it
	if mega:
		_place_coin(Vector2(next_x + gap * 0.5, minf(last_top_y, top_y) - 190.0))
		used += 1

	# enemies (never on climb stairs — those are about building)
	var enemies := 0
	if d >= PHASE_ENEMY and w > 480.0 and climb_dir == 0:
		var chance := 0.5 if d >= PHASE_SWARM else 0.35
		if rng.randf() < chance:
			enemies = 1
			if d >= PHASE_SWARM and w > 550.0 and used + 2 <= budget \
					and rng.randf() < 0.5:
				enemies = 2
	enemies = mini(enemies, budget - used)
	if enemies == 1:
		var blob := SpikeBlob.new(x + 70.0, x + w - 70.0)
		blob.position = Vector2(x + w * 0.5, top_y - 30.0)
		add_child(blob)
	elif enemies == 2:
		var mid := x + w * 0.5
		var a := SpikeBlob.new(x + 70.0, mid - 40.0)
		a.position = Vector2(x + w * 0.25, top_y - 30.0)
		add_child(a)
		var b := SpikeBlob.new(mid + 40.0, x + w - 70.0)
		b.position = Vector2(x + w * 0.75, top_y - 30.0)
		add_child(b)
	used += enemies

	# at most one crystal on the chunk itself; climb steps pay out more
	# reliably so stairs stay affordable
	var mana_chance := 0.65 if climb_dir != 0 else 0.5
	if used < budget and rng.randf() < mana_chance:
		var coin_y := top_y - 60.0 if rng.randf() < 0.7 else top_y - 250.0
		_place_coin(Vector2(x + rng.randf_range(80.0, w - 80.0), coin_y))
		used += 1

	next_x = x + w
	last_top_y = top_y
	return {
		"gap": gap, "width": w, "top_y": top_y, "mega": mega,
		"enemies": enemies, "entities": used, "climb": climb_dir,
	}


func _update_climb_state(d: float) -> void:
	if climb_dir == 0:
		flat_chunks_since_wave += 1
		# occasional set-piece: needs a breather of flat terrain first
		if d >= PHASE_CLIMB and last_top_y > 800.0 \
				and flat_chunks_since_wave >= 5 and rng.randf() < 0.22:
			climb_dir = -1
			climb_steps_left = 2 + rng.randi() % 3
	elif climb_dir == -1:
		if climb_steps_left <= 0 or last_top_y <= SKY_Y_MIN + 20.0:
			climb_dir = 1
	else:
		if last_top_y >= 860.0:
			climb_dir = 0
			flat_chunks_since_wave = 0


func _place_chunk(x: float, top_y: float, w: float) -> void:
	var chunk := GroundChunk.new(w)
	chunk.position = Vector2(x, top_y)
	add_child(chunk)


func _place_coin(pos: Vector2) -> void:
	var coin := ManaCrystal.new()
	coin.position = pos
	add_child(coin)
