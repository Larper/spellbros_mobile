class_name Main
extends Node2D

## Game manager: owns the player, camera, spawner and HUD.
## Handles the tap input routing (jump vs. build) and the run's lifecycle.

const PLATFORM_COST := 1
const START_COINS := 3
const SPRING_EVERY := 4  # every Nth build is a spring pad
const BUILD_COOLDOWN := 0.15
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
var builds := 0
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
	player.sprung.connect(func() -> void: audio.play("boing"))
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
		return 470.0
	return minf(470.0 + (d - TerrainSpawner.PHASE_SPEED) * 0.9, 780.0)


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
	builds += 1
	audio.play("build")
	var plat := BuiltPlatform.new()
	plat.bouncy = builds % SPRING_EVERY == 0
	plat.global_position = world_pos.snapped(Vector2(20.0, 20.0))
	add_child(plat)
	hud.set_spring_ready(builds % SPRING_EVERY == SPRING_EVERY - 1)


func add_coin(amount: int = 1) -> void:
	if game_over:
		return
	coins += amount
	hud.update_coins(coins)
	audio.play("pickup")


## Small world-space text that floats up and fades ("+1", "+3", ...).
func float_text(world_pos: Vector2, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 48)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.12, 0.85))
	l.add_theme_constant_override("outline_size", 8)
	l.position = world_pos + Vector2(-30.0, -70.0)
	l.z_index = 50
	add_child(l)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 90.0, 0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.25)
	tw.chain().tween_callback(l.queue_free)


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
