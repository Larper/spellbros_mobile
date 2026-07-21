class_name Main
extends Node2D

## Game manager: owns the player, camera, spawner and HUD.
## Handles the tap input routing (jump vs. build) and the run's lifecycle.

const PLATFORM_COST := 1
const START_COINS := 0
const BUILD_COOLDOWN := 0.15
## Thumbs are imprecise and tend to land right of where the player aims, so
## every touch-build is nudged this many world px left of the tap (~one thumb
## width at the current zoom). Tuning knob from Neven's phone playtests.
const BUILD_TOUCH_NUDGE := 0

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
## Camera crop: zoom 1.25 -> visible world is 1536x864 (half 768x432), so the
## wizard reads bigger on a phone. The lead pushes him to ~22% from the left
## edge: what's behind him is dead space, what's ahead is the game.
const CAMERA_ZOOM := 1.25
const CAMERA_LEAD := 430.0  # world px ahead of the wizard the camera centers on
## The vertical frame is STATIC, Flappy Bird style: jumps, falls and gravity
## flips never move it (the old per-state retargeting is what jittered on
## every FLIPSIDE flip — Neven). At this zoom the frame spans y 188..1052,
## which holds the whole playfield at once: the deepest deck top (970) with
## ground below it, and the FLIPSIDE ceiling faces (240..380) overhead.
## ONE allowance (Neven): stair set-pieces may drift the frame UP. When a
## chunk top ahead rises past CAM_LIFT_TRIGGER the frame eases up just far
## enough to keep the stair tops (and the jumps off them) in view, then
## settles back to CAMERA_Y. Chunk tops are static world data, so the frame
## still never follows a jump or a fall; FLIPSIDE stays pinned.
const CAMERA_Y := 620.0
const CAM_LIFT_TRIGGER := 560.0
const CAM_LIFT_MAX := 300.0
const CAMERA_CHASE := 0.85  # fraction of run speed the camera keeps while the player is stalled
## The stall-crush never advances faster than base-speed pressure (0.85*470):
## at capped run speed the chase would otherwise eat the reaction window
## before a missed stair jump can be answered with a build.
const CAMERA_CHASE_CAP := 400.0
const RESTART_LOCKOUT_MS := 600.0
## Level banners run a short beat ahead of the boundary — enough to read,
## not so early the text lies about where you are (announcing SPRINGS a
## full wind-down early felt wrong to Neven). UMBRA is the exception: its
## banner stays synced to the darkness gradient, which ramps from 60 m out,
## because pitch black needs real preparation time.
const BANNER_LEAD_M := 18.0
const BANNER_LEAD_UMBRA_M := 45.0

static var session_best := 0.0
## -1 = show the level-select menu; otherwise the level index to auto-start
## (kept across scene reloads so death -> tap retries the same level fast)
static var auto_start_level := -1

var player: Player
var cam: Camera2D
var spawner: TerrainSpawner
var hud: Hud
var audio: GameAudio
var psy: PsyTheme
var bro: EchoBro
var wizard_light: PointLight2D

var coins := START_COINS
var start_level := 0
var start_offset_m := 0.0  # meters credited for starting at a later level
var cur_level := 0
var announced_level := 0  # banners run ahead of cur_level (wind-down preview)
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
	# UMBRA halo: wide enough to read the next gap's near edge (the old
	# 300 px saw barely past the wizard's feet and starved runs — Neven);
	# the dark still owns everything past it, so lantern-builds stay the
	# scouting tool
	wizard_light = PsyTheme.make_light(460.0, 1.2)
	wizard_light.enabled = false
	player.add_child(wizard_light)

	bro = EchoBro.new()
	add_child(bro)

	cam = Camera2D.new()
	cam.global_position = Vector2(player.global_position.x + CAMERA_LEAD, CAMERA_Y)
	cam.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	add_child(cam)
	cam.make_current()

	hud = Hud.new()
	add_child(hud)
	hud.update_coins(coins)
	hud.update_score(0)

	psy = PsyTheme.new()
	add_child(psy)

	if auto_start_level >= 0:
		begin_run(auto_start_level)
	elif Levels.load_unlocked() == 0:
		# nothing unlocked yet = no choice to offer: straight into the run
		begin_run(0)
	else:
		# level-select menu: world stays frozen until a start is chosen
		hud.show_menu(Levels.load_unlocked())
		get_tree().paused = true


## Start (or restart) the run from the given unlocked level's boundary.
func begin_run(i: int) -> void:
	start_level = i
	# debug_spawn_m (menu wheel/arrows): spawn deeper in — even past the
	# chosen band's end — so the true level at the landing spot governs
	start_offset_m = Levels.start_m(i) + Levels.debug_spawn_m
	cur_level = Levels.level_for(start_offset_m)
	announced_level = cur_level
	distance_m = start_offset_m
	# any start past 0 m gets a small stake so the terrain there is playable
	# on arrival (mega gaps demand mana from PHASE_BUILD on)
	coins = START_COINS if start_offset_m <= 0.0 else 2 + cur_level
	hud.update_coins(coins)
	hud.update_score(int(distance_m))
	hud.hide_menu()
	if start_offset_m > 0.0:
		hud.show_level_banner("LEVEL %d: %s" % [cur_level + 1, Levels.level_name(cur_level)])
	Main.auto_start_level = i
	get_tree().paused = false


## Back to the level-select menu (game-over panel button).
func to_menu() -> void:
	Main.auto_start_level = -1
	get_tree().paused = false
	get_tree().reload_current_scene()


func _physics_process(delta: float) -> void:
	build_cooldown = maxf(0.0, build_cooldown - delta)

	if not game_over:
		distance_m = maxf(distance_m, (player.global_position.x - start_x) / 100.0 + start_offset_m)
		player.run_speed = run_speed_for(distance_m)
		hud.update_score(int(distance_m))
		hud.update_powerups(player.shielded, player.double_jumps > 0)
		# crossing a level boundary unlocks it as a starting point
		var lv := Levels.level_for(distance_m)
		if lv > cur_level:
			cur_level = lv
			Levels.unlock(lv)
		# the banner still runs AHEAD of the boundary (announcing a level as
		# it starts is too late to prepare), but only by its own short lead
		var nxt := announced_level + 1
		if nxt < Levels.count() and distance_m + banner_lead_for(nxt) >= Levels.start_m(nxt):
			# level_for swallows skipped bands when distance jumps (late starts)
			announced_level = Levels.level_for(distance_m + banner_lead_for(nxt))
			hud.show_level_banner("LEVEL %d: %s" % [announced_level + 1,
					Levels.level_name(announced_level)])
			audio.play("pickup")
		# per-level state: darkness light, the echo brother, gravity hygiene
		wizard_light.enabled = lv == Levels.UMBRA
		bro.active = lv == Levels.BROS
		var flip_zone := in_flip_zone()
		if not flip_zone and player.gravity_dir < 0.0:
			player.gravity_dir = 1.0  # the wind-down / next level rights the world
		if flip_zone and player.global_position.y < CAMERA_Y - 710.0:
			player.die()  # flew off the top with no ceiling to catch you
		if player.global_position.y > CAMERA_Y + 710.0:
			player.die()  # ~280 world px below the zoomed view's bottom edge

	if not player.dead:
		# The camera never waits: it holds the lead while the player keeps
		# pace, but keeps rolling if they get stuck (e.g. wedged under a
		# pillar) — get unstuck or be crushed against the screen edge.
		var pace_x := player.global_position.x + CAMERA_LEAD
		var chase := minf(player.run_speed * CAMERA_CHASE, CAMERA_CHASE_CAP)
		var auto_x := cam.global_position.x + chase * delta
		cam.global_position.x = maxf(auto_x, pace_x)
		var half_w := get_viewport().get_visible_rect().size.x * 0.5 / CAMERA_ZOOM
		if player.global_position.x < cam.global_position.x - half_w - 30.0:
			player.die()
	cam.global_position.y = lerpf(cam.global_position.y, camera_target_y(),
			1.0 - pow(0.002, delta))

	if shake > 0.0:
		shake = maxf(0.0, shake - delta * 30.0)
		cam.offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	else:
		cam.offset = Vector2.ZERO


## CAMERA_Y always — except the staircase allowance (see the constants).
## Reads only terrain, never the wizard: jumps and falls cannot move it.
func camera_target_y() -> float:
	if in_flip_zone():
		return CAMERA_Y
	return CAMERA_Y - clampf((CAM_LIFT_TRIGGER - _highest_ground_ahead()) * 0.9,
			0.0, CAM_LIFT_MAX)


func _highest_ground_ahead() -> float:
	# Top y of the HIGHEST floor chunk overlapping [player.x, player.x + 700]
	# (the lift sees stairs coming before the wizard climbs them); 9999 if none.
	var px := player.global_position.x
	var highest := 9999.0
	for c in spawner.get_children():
		var g := c as GroundChunk
		if g == null or g.ceiling:
			continue
		if g.position.x <= px + 700.0 and g.position.x + g.width >= px:
			highest = minf(highest, g.position.y)
	return highest


func banner_lead_for(lv: int) -> float:
	if lv == Levels.UMBRA:
		return BANNER_LEAD_UMBRA_M
	if lv == Levels.FLIPSIDE:
		# fires ON the boundary: the opening runway IS the reading room, and
		# announcing during the bridges wind-down was still too soon (Neven)
		return 0.0
	return BANNER_LEAD_M


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
		# PC convenience: Space jumps, R restarts; S/D are dev grants so
		# the powerup visuals are testable without hunting for pickups
		if event.keycode == KEY_SPACE:
			if game_over:
				_maybe_restart()
			else:
				_jump_pressed()
		elif event.keycode == KEY_R and game_over:
			_maybe_restart()
		elif event.keycode == KEY_S and not game_over:
			player.shielded = true
			float_text(player.global_position + Vector2(0, -50), "SHIELD!", Color("b98cff"))
		elif event.keycode == KEY_D and not game_over:
			player.double_jumps = 1
			float_text(player.global_position + Vector2(0, -50), "DOUBLE JUMP!", Color("ffd75e"))


func _handle_tap(screen_pos: Vector2) -> void:
	if game_over:
		_maybe_restart()
		return
	# Mobile controls: the wizard splits the screen. Tap anywhere to his
	# left to jump, anywhere to his right to build a platform there.
	# The divider never drops below the wizard's normal resting position:
	# when the crush-camera pushes him toward the left edge (stalled while
	# stair-building), the jump zone must not shrink away right when jumps
	# matter most.
	var world_pos: Vector2 = get_canvas_transform().affine_inverse() * screen_pos
	# LAST-SECOND SAVE (Neven): a tap clearly below the wizard's feet — in
	# his FALL direction, so it mirrors on the FLIPSIDE ceiling — and not
	# far behind him is a BUILD even inside the jump zone: dropping a pad
	# under yourself mid-fall must never read as a jump. Jump taps live at
	# or above wizard height, or well off to the left; both keep working.
	var below: float = (world_pos.y - player.global_position.y) * player.gravity_dir
	if below > 110.0 and world_pos.x > player.global_position.x - 240.0:
		world_pos.x -= BUILD_TOUCH_NUDGE
		_try_build(world_pos)
		return
	var player_screen_x: float = (get_canvas_transform() * player.global_position).x
	var divider_x: float = maxf(player_screen_x,
			get_viewport().get_visible_rect().size.x * 0.5 - CAMERA_LEAD * CAMERA_ZOOM)
	if screen_pos.x < divider_x:
		_jump_pressed()
	else:
		world_pos.x -= BUILD_TOUCH_NUDGE
		_try_build(world_pos)


## True while the tap action is the gravity flip: inside FLIPSIDE minus the
## opening runway (a plain floor while the banner registers — taps still
## jump) and minus the wind-down stretch at the far end (continuous floor,
## control handed back BEFORE the boundary, so crossing into the next level
## never eats a habitual flip into a hole).
func in_flip_zone() -> bool:
	return distance_m >= Levels.start_m(Levels.FLIPSIDE) + TerrainSpawner.RUNWAY_M \
			and distance_m < Levels.start_m(Levels.UMBRA) - TerrainSpawner.WIND_DOWN_M


## The jump tap doubles as the gravity flip inside FLIPSIDE.
func _jump_pressed() -> void:
	if in_flip_zone():
		player.try_flip()
	else:
		player.try_jump()


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
	var lv := Levels.level_for(distance_m)
	plat.bouncy = lv == Levels.SPRINGS  # every SPRINGS build is a launcher
	plat.solid = lv == Levels.FLIPSIDE  # landable from both gravities
	plat.lit = lv == Levels.UMBRA       # built lanterns mark your trail
	plat.lifetime = platform_life_for(distance_m)
	plat.global_position = world_pos.snapped(Vector2(20.0, 20.0))
	add_child(plat)


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
	if Levels.debug_spawn_m <= 0.0:  # debug spawns never pollute the bests
		Levels.save_best(start_level, int(distance_m))
	hud.show_game_over(int(distance_m), Levels.best_for(start_level),
			Levels.level_name(start_level))
