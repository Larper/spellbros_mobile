class_name Main
extends Node2D

## Game manager: owns the player, camera, spawner and HUD.
## Handles the tap input routing (jump vs. build) and the run's lifecycle.

const PLATFORM_COST := 1
const START_COINS := 0
const BUILD_COOLDOWN := 0.15

## ---- HARD-MODE SPEED / PLATFORM TUNING ------------------------------------
## Speed ramps from TerrainSpawner.PHASE_SPEED. The spawner sizes all normal
## gaps as fractions of run_speed_for(d) (max 0.56*v vs the 0.709*v flat jump
## reach), so ramp and cap can be pushed without creating unjumpable gaps.
## Ramp 1.5/m from 110 m hits the 900 cap at ~397 m, just before the void.
const BASE_SPEED := 470.0
const SPEED_RAMP := 1.5   # px/s gained per meter past PHASE_SPEED
const SPEED_CAP := 900.0
## Conjured platforms crumble faster late-game: 4.0 s early, shrinking to
## PLATFORM_LIFE_LATE between PLATFORM_DECAY_START..END meters.
const PLATFORM_LIFE := 4.0
const PLATFORM_LIFE_LATE := 2.4
const PLATFORM_DECAY_START := 300.0
const PLATFORM_DECAY_END := 600.0
const CAMERA_LEAD := 288.0  # keeps the wizard ~35% from the left edge
const CAMERA_CHASE := 0.85  # fraction of run speed the camera keeps while the player is stalled
const RESTART_LOCKOUT_MS := 600.0

static var session_best := 0.0

var player: Player
var cam: Camera2D
var spawner: TerrainSpawner
var hud: Hud
var audio: GameAudio

var coins := START_COINS
var distance_m := 0.0
var game_over := false
var game_over_at := 0.0
var build_cooldown := 0.0
var start_x := 0.0
var shake := 0.0


func _ready() -> void:
	add_to_group("main")
	RenderingServer.set_default_clear_color(Color("191129"))

	audio = GameAudio.new()
	add_child(audio)
	audio.start_music()

	spawner = TerrainSpawner.new()
	spawner.main = self
	add_child(spawner)

	player = Player.new()
	player.global_position = Vector2(260.0, TerrainSpawner.START_GROUND_Y - Player.BODY_H * 0.5)
	player.died.connect(_on_player_died)
	player.jumped.connect(func() -> void: audio.play("jump"))
	add_child(player)
	start_x = player.global_position.x

	cam = Camera2D.new()
	cam.global_position = Vector2(player.global_position.x + CAMERA_LEAD, 620.0)
	add_child(cam)
	cam.make_current()

	hud = Hud.new()
	add_child(hud)
	hud.update_coins(coins)
	hud.update_score(0)


func _physics_process(delta: float) -> void:
	build_cooldown = maxf(0.0, build_cooldown - delta)

	if not game_over:
		distance_m = maxf(distance_m, (player.global_position.x - start_x) / 100.0)
		player.run_speed = run_speed_for(distance_m)
		hud.update_score(int(distance_m))
		if player.global_position.y > cam.global_position.y + 820.0:
			player.die()

	if not player.dead:
		# The camera never waits: it holds the lead while the player keeps
		# pace, but keeps rolling if they get stuck (e.g. wedged under a
		# pillar) — get unstuck or be crushed against the screen edge.
		var pace_x := player.global_position.x + CAMERA_LEAD
		var auto_x := cam.global_position.x + player.run_speed * CAMERA_CHASE * delta
		cam.global_position.x = maxf(auto_x, pace_x)
		var half_w := get_viewport().get_visible_rect().size.x * 0.5
		if player.global_position.x < cam.global_position.x - half_w - 30.0:
			player.die()
	var target_y := clampf(player.global_position.y - 150.0, 150.0, 760.0)
	cam.global_position.y = lerpf(cam.global_position.y, target_y, 1.0 - pow(0.002, delta))

	if shake > 0.0:
		shake = maxf(0.0, shake - delta * 30.0)
		cam.offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	else:
		cam.offset = Vector2.ZERO


func run_speed_for(d: float) -> float:
	if d < TerrainSpawner.PHASE_SPEED:
		return BASE_SPEED
	return minf(BASE_SPEED + (d - TerrainSpawner.PHASE_SPEED) * SPEED_RAMP, SPEED_CAP)


func platform_life_for(d: float) -> float:
	var f := clampf((d - PLATFORM_DECAY_START) / (PLATFORM_DECAY_END - PLATFORM_DECAY_START), 0.0, 1.0)
	return lerpf(PLATFORM_LIFE, PLATFORM_LIFE_LATE, f)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_handle_tap(event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		# PC convenience: Space jumps, R restarts
		if event.keycode == KEY_SPACE:
			if game_over:
				_maybe_restart()
			else:
				player.try_jump()
		elif event.keycode == KEY_R and game_over:
			_maybe_restart()


func _handle_tap(screen_pos: Vector2) -> void:
	if game_over:
		_maybe_restart()
		return
	var world_pos: Vector2 = get_canvas_transform().affine_inverse() * screen_pos
	if player.tap_rect().has_point(world_pos):
		player.try_jump()
	else:
		_try_build(world_pos)


func _maybe_restart() -> void:
	if Time.get_ticks_msec() - game_over_at > RESTART_LOCKOUT_MS:
		get_tree().reload_current_scene()


func _try_build(world_pos: Vector2) -> void:
	if build_cooldown > 0.0:
		return
	if coins < PLATFORM_COST:
		hud.flash_no_mana()
		return
	coins -= PLATFORM_COST
	hud.update_coins(coins)
	build_cooldown = BUILD_COOLDOWN
	audio.play("build")
	var plat := BuiltPlatform.new()
	plat.lifetime = platform_life_for(distance_m)
	plat.global_position = world_pos.snapped(Vector2(20.0, 20.0))
	add_child(plat)


func add_coin() -> void:
	if game_over:
		return
	coins += 1
	hud.update_coins(coins)
	audio.play("pickup")


func _on_player_died() -> void:
	if game_over:
		return
	game_over = true
	game_over_at = Time.get_ticks_msec()
	shake = 14.0
	audio.stop_music()
	audio.play("death")
	session_best = maxf(session_best, distance_m)
	hud.show_game_over(int(distance_m), int(session_best))
