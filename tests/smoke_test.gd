extends SceneTree

## Headless smoke test: run with
##   godot --headless --path . -s res://tests/smoke_test.gd
## Loads the real game scene, drives its public entry points, then probes
## the terrain spawner at forced distances to verify the difficulty phases
## and AUDITS every sampled chunk for beatability against the jump math:
##   flat reach = 0.709 * v ; landing R px higher -> (1170+sqrt(1170^2-6600R))/3300 * v
##   one built platform bridges 1.418 * v + 240 px.
## Prints "SMOKE RESULT: PASS" only if every check holds.

var main
var fails := 0


func _initialize() -> void:
	# scratch save: keeps tests deterministic and never touches real progress
	Levels.save_path = "user://smoke_progress.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Levels.save_path))
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	current_scene = main
	_run_tests.call_deferred()


func _check(ok: bool, label: String) -> void:
	if not ok:
		fails += 1
		print("  FAIL: " + label)


func _run_tests() -> void:
	await create_timer(0.3).timeout
	# first launch (nothing unlocked): no menu, the run starts immediately
	print("TEST boot: menu=%s paused=%s coins=%d (expect false false 0)" % [
		main.hud.menu_root.visible, paused, main.coins])
	_check(not main.hud.menu_root.visible and not paused and main.coins == 0,
			"first launch runs immediately")
	# setup, checked before the wizard reaches the first teaching crystal
	var p = main.player
	print("TEST setup: player=%s on_floor=%s coins=%d (expect %d = START_COINS)" % [p != null, p.is_on_floor(), main.coins, main.START_COINS])
	_check(p != null and main.coins == main.START_COINS, "setup")
	# the menu itself (reached via game over / later launches): one row per level
	main.hud.show_menu(1)
	var rows: int = main.hud.level_list.get_child_count()
	var menu_ok: bool = main.hud.menu_root.visible and rows == Levels.count()
	main.hud.hide_menu()
	print("TEST menu: rows=%d (expect %d) shown_then_hidden=%s" % [
		rows, Levels.count(), menu_ok and not main.hud.menu_root.visible])
	_check(menu_ok and not main.hud.menu_root.visible, "menu rows")

	await create_timer(1.0).timeout

	# level ladder mapping + unlock/best persistence (on a scratch save file)
	var map_ok: bool = Levels.level_for(0.0) == 0 and Levels.level_for(299.0) == 0 \
			and Levels.level_for(300.0) == Levels.SPRINGS \
			and Levels.level_for(650.0) == Levels.BRIDGES \
			and Levels.level_for(1000.0) == Levels.FLIPSIDE \
			and Levels.level_for(1300.0) == Levels.UMBRA \
			and Levels.level_for(1600.0) == Levels.BROS \
			and Levels.level_for(1900.0) == Levels.VOID
	var real_path: String = Levels.save_path
	Levels.save_path = "user://test_progress.cfg"
	Levels.unlock(2)
	Levels.save_best(1, 234)
	Levels.save_best(1, 100)  # a worse run must not overwrite the best
	var persist_ok: bool = Levels.load_unlocked() == 2 and Levels.best_for(1) == 234
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_progress.cfg"))
	Levels.save_path = real_path
	print("TEST levels: map_ok=%s persist_ok=%s (expect true true)" % [map_ok, persist_ok])
	_check(map_ok and persist_ok, "levels api")

	# debug late spawn: the menu's ↑/↓ offset credits meters past the level
	# start (no awaits here — distance_m must be read before physics runs)
	Levels.debug_spawn_m = 250.0
	main.begin_run(0)
	var dbg_mid: bool = main.distance_m == 250.0 and main.start_offset_m == 250.0 \
			and main.coins == 2 and main.cur_level == 0
	# a deep offset lands in a LATER level: that level's rules must govern
	Levels.debug_spawn_m = 1100.0
	main.begin_run(0)
	var dbg_deep: bool = main.distance_m == 1100.0 and main.cur_level == Levels.FLIPSIDE \
			and main.coins == 2 + Levels.FLIPSIDE
	Levels.debug_spawn_m = 0.0
	main.begin_run(0)
	var dbg_zero: bool = main.distance_m == 0.0 and main.coins == main.START_COINS \
			and main.cur_level == 0
	Main.auto_start_level = -1
	main.hud.show_menu(0)
	var evk := InputEventKey.new()
	evk.keycode = KEY_UP
	evk.pressed = true
	main.hud._unhandled_input(evk)
	var key_step: bool = Levels.debug_spawn_m == 25.0
	var evw := InputEventMouseButton.new()
	evw.button_index = MOUSE_BUTTON_WHEEL_UP
	evw.pressed = true
	evw.shift_pressed = true
	main.hud._spawn_row_input(evw)
	var wheel_step: bool = Levels.debug_spawn_m == 125.0
	main.hud.hide_menu()
	Levels.debug_spawn_m = 0.0
	print("TEST debugspawn: mid=%s deep=%s zero=%s key=%s wheel=%s (expect all true)" % [
		dbg_mid, dbg_deep, dbg_zero, key_step, wheel_step])
	_check(dbg_mid and dbg_deep and dbg_zero and key_step and wheel_step, "debug late spawn")

	# build a platform ahead of the wizard (seed mana; the run now starts at 0)
	main.coins = 3
	var coins_before: int = main.coins
	main._try_build(Vector2(p.global_position.x + 500.0, p.global_position.y - 120.0))
	await create_timer(0.1).timeout
	var plat_count := 0
	for c in main.get_children():
		if c is BuiltPlatform:
			plat_count += 1
	print("TEST build: coins %d -> %d (expect -1), platforms=%d (expect 1)" % [coins_before, main.coins, plat_count])
	_check(main.coins == coins_before - 1 and plat_count == 1, "build")

	# jump
	var y_before: float = p.global_position.y
	p.try_jump()
	await create_timer(0.25).timeout
	print("TEST jump: y %.0f -> %.0f (expect lower value = rose)" % [y_before, p.global_position.y])
	_check(p.global_position.y < y_before, "jump")

	# stomp refresh: bouncing off an enemy grants one air jump until landing
	p.global_position.y -= 400.0
	p.bounce()
	await create_timer(0.3).timeout
	var fall_vel: float = p.velocity.y
	p.try_jump()
	await create_timer(0.1).timeout
	print("TEST stompjump: vel %.0f -> %.0f (expect falling, then jump < -700)" % [fall_vel, p.velocity.y])
	_check(p.velocity.y < -700.0, "stompjump")

	# camera eases down when the terrain ahead sits lower (next-pillar visibility)
	var y_saved: float = p.global_position.y
	p.global_position.y = 500.0
	var t_flat: float = main.camera_target_y()
	var low_chunk := GroundChunk.new(300.0)
	low_chunk.position = Vector2(p.global_position.x + 300.0, 1500.0)
	main.spawner.add_child(low_chunk)
	var t_low: float = main.camera_target_y()
	low_chunk.queue_free()
	p.global_position.y = y_saved
	print("TEST camahead: target flat %.0f, low pillar ahead %.0f (expect >= 200 px lower)" % [t_flat, t_low])
	_check(t_low - t_flat >= 200.0, "camera pillar lookdown")

	# no-mana path must refuse to build
	main.coins = 0
	main.build_cooldown = 0.0
	main._try_build(Vector2(p.global_position.x + 300.0, 500.0))
	print("TEST nomana: coins=%d (expect 0, no free platform)" % main.coins)
	_check(main.coins == 0, "nomana")

	# mobile controls: tap left of the wizard = jump, tap right = build
	var wiz_x: float = (main.get_canvas_transform() * p.global_position).x
	p.jump_buffer = 0.0
	main._handle_tap(Vector2(wiz_x - 300.0, 500.0))
	var left_jumps: bool = p.jump_buffer > 0.0
	main.coins = 1
	main.build_cooldown = 0.0
	var tap_screen := Vector2(wiz_x + 300.0, 500.0)
	main._handle_tap(tap_screen)
	print("TEST taproute: left_jumps=%s (expect true) coins=%d (expect 0, right tap built)" % [
		left_jumps, main.coins])
	_check(left_jumps and main.coins == 0, "tap routing")
	# thumb compensation: the platform lands BUILD_TOUCH_NUDGE left of the tap
	var tap_world: Vector2 = main.get_canvas_transform().affine_inverse() * tap_screen
	var newest: BuiltPlatform = null
	for c in main.get_children():
		if c is BuiltPlatform:
			newest = c
	var nudge_err: float = absf(newest.global_position.x - (tap_world.x - main.BUILD_TOUCH_NUDGE))
	print("TEST buildnudge: plat_x=%.0f tap_x=%.0f err=%.0f (expect <= 10 = snap grid)" % [
		newest.global_position.x, tap_world.x, nudge_err])
	_check(nudge_err <= 10.001, "build nudge left")
	p.jump_buffer = 0.0

	# jump-zone floor: with the wizard crushed toward the left edge, a tap
	# right of him but left of his NORMAL position must still jump, not build
	var x_keep: float = p.global_position.x
	p.global_position.x = main.cam.global_position.x - 600.0  # screen x ~210
	main.coins = 1
	main.build_cooldown = 0.0
	main._handle_tap(Vector2(300.0, 500.0))
	var floor_jumps: bool = p.jump_buffer > 0.0 and main.coins == 1
	p.global_position.x = x_keep
	p.jump_buffer = 0.0
	main.coins = 0
	print("TEST jumpzone: crushed-left tap jumps=%s (expect true, no build)" % floor_jumps)
	_check(floor_jumps, "jump zone floor")

	# stomp bounty: squishing a blob pays +1 mana and bounces the player
	main.coins = 2
	var blob := SpikeBlob.new(0.0, 100.0)
	blob.global_position = p.global_position + Vector2(0.0, 60.0)
	main.add_child(blob)
	p.velocity.y = 300.0  # falling onto it
	blob._on_body_entered(p)
	print("TEST stomp: coins=%d (expect 3) blob_dying=%s vel_y=%.0f (expect -1000) player_alive=%s" % [
		main.coins, blob.dying, p.velocity.y, not p.dead])
	_check(main.coins == 3 and blob.dying and not p.dead, "stomp bounty")
	blob.queue_free()

	# side hit still kills: bounty must not make blobs safe to touch
	var blob2 := SpikeBlob.new(0.0, 100.0)
	blob2.global_position = p.global_position + Vector2(60.0, 0.0)
	main.add_child(blob2)
	p.velocity.y = 0.0
	blob2._on_body_entered(p)
	print("TEST sidehit: dead=%s (expect true) coins=%d (expect still 3)" % [p.dead, main.coins])
	_check(p.dead and main.coins == 3, "side hit lethal")
	blob2.queue_free()
	# revive for the remaining tests (same run, fresh wizard state)
	p.dead = false
	p.collision_mask = 1
	p.rotation = 0.0
	p.velocity = Vector2.ZERO
	main.game_over = false
	main.hud.over_root.visible = false

	# purple shield: absorbs exactly one lethal blob touch
	var sh := ShieldPickup.new()
	sh.global_position = p.global_position
	main.add_child(sh)
	sh._on_body_entered(p)
	var got_shield: bool = p.shielded
	var blob4 := SpikeBlob.new(0.0, 100.0)
	blob4.global_position = p.global_position + Vector2(60.0, 0.0)
	main.add_child(blob4)
	p.velocity.y = 0.0
	blob4._on_body_entered(p)
	var saved: bool = not p.dead and not p.shielded and blob4.dying
	var blob5 := SpikeBlob.new(0.0, 100.0)
	blob5.global_position = p.global_position + Vector2(60.0, 0.0)
	main.add_child(blob5)
	blob5._on_body_entered(p)
	print("TEST shield: granted=%s saved_once=%s then_lethal=%s (expect all true)" % [
		got_shield, saved, p.dead])
	_check(got_shield and saved and p.dead, "shield powerup")
	blob4.queue_free()
	blob5.queue_free()
	p.dead = false
	p.collision_mask = 1
	p.rotation = 0.0
	p.velocity = Vector2.ZERO
	main.game_over = false
	main.hud.over_root.visible = false

	# aim assist: a slight horizontal miss, falling past the blob's crown,
	# still registers as a stomp (the forgiveness Neven asked for)
	var blob3 := SpikeBlob.new(0.0, 100.0)
	blob3.global_position = p.global_position + Vector2(80.0, 50.0)
	main.add_child(blob3)
	main.coins = 3
	p.velocity.y = 400.0
	blob3._stomp_assist()
	print("TEST stompassist: dying=%s coins=%d (expect true 4) alive=%s" % [
		blob3.dying, main.coins, not p.dead])
	_check(blob3.dying and main.coins == 4 and not p.dead, "stomp aim assist")
	blob3.queue_free()
	p.velocity = Vector2.ZERO

	# the shield orb never precedes the first blob: the counter must come
	# after the threat it answers
	main.spawner.enemy_seen = false
	main.spawner.climb_dir = 0
	main.spawner.climb_steps_left = 0
	main.spawner.flat_chunks_since_wave = 99
	main.spawner.force_mega = false
	main.spawner.last_top_y = TerrainSpawner.START_GROUND_Y
	var first_enemy := -1
	var first_shield := -1
	for i in range(300):
		main.spawner.next_x = 80.0 * 100.0 + main.start_x
		var sc: Dictionary = main.spawner._spawn_chunk()
		if first_enemy == -1 and sc["enemies"] > 0:
			first_enemy = i
		if first_shield == -1 and sc["shields"] > 0:
			first_shield = i
	print("TEST shieldorder: first_enemy=%d first_shield=%d (expect both >= 0, enemy strictly first)" % [
		first_enemy, first_shield])
	_check(first_enemy >= 0 and first_shield > first_enemy, "shield only after first enemy")

	# park the wizard on a fresh platform so the star test starts grounded
	main.coins = 5
	main.build_cooldown = 0.0
	main._try_build(Vector2(p.global_position.x + 200.0, 700.0))
	p.global_position = Vector2(p.global_position.x + 200.0, 640.0)
	p.velocity = Vector2.ZERO
	await create_timer(0.1).timeout

	# Star of Levity: pickup stores one double jump; tapping mid-air spends it
	var star := StarPickup.new()
	star.global_position = p.global_position
	main.add_child(star)
	star._on_body_entered(p)
	var granted: int = p.double_jumps
	p.global_position.y -= 500.0
	p.velocity = Vector2.ZERO
	await create_timer(0.3).timeout  # fall until floor state and coyote expire
	var airborne: bool = not p.is_on_floor() and p.coyote <= 0.0
	p.try_jump()
	await create_timer(0.1).timeout
	print("TEST star: granted=%d (expect 1) airborne=%s (expect true) vel_y=%.0f (expect < -500) charges_left=%d (expect 0)" % [
		granted, airborne, p.velocity.y, p.double_jumps])
	_check(granted == 1 and airborne and p.velocity.y < -500.0 and p.double_jumps == 0,
			"star of levity")

	# orange fragment: a single crystal worth +3 mana
	main.coins = 0
	var oc := ManaCrystal.new()
	oc.amount = 3
	main.add_child(oc)
	oc.collect()
	print("TEST orange: coins=%d (expect 3)" % main.coins)
	_check(main.coins == 3, "orange fragment +3")
	oc.queue_free()

	# SPRINGS level: builds inside its band are launcher pads, outside not
	main.distance_m = 350.0
	main.coins = 2
	main.build_cooldown = 0.0
	main._try_build(Vector2(p.global_position.x + 3000.0, 300.0))
	main.distance_m = 20.0
	main.build_cooldown = 0.0
	main._try_build(Vector2(p.global_position.x + 3300.0, 300.0))
	var all_pads := []
	for c in main.get_children():
		if c is BuiltPlatform:
			all_pads.append(c)
	var pad_in: BuiltPlatform = all_pads[all_pads.size() - 2]
	var pad_out: BuiltPlatform = all_pads[all_pads.size() - 1]
	print("TEST springlevel: in-band bouncy=%s (expect true) outside=%s (expect false) coins=%d (expect 0)" % [
		pad_in.bouncy, pad_out.bouncy, main.coins])
	_check(pad_in.bouncy and not pad_out.bouncy and main.coins == 0, "springs level builds")

	# spring launch: landing on a pad flings the player harder than a jump
	var pad0: BuiltPlatform = pad_in
	pad0.age = 0.0  # fresh lifetime so it cannot crumble mid-test
	p.global_position = pad0.global_position + Vector2(-80.0, -70.0)
	p.velocity = Vector2.ZERO
	var min_vy := 0.0
	for i in range(12):
		await create_timer(0.05).timeout
		min_vy = minf(min_vy, p.velocity.y)
	print("TEST springlaunch: min_vel_y=%.0f (expect <= -1200, stronger than jump -1170)" % min_vy)
	_check(min_vy <= -1200.0, "spring launch")
	# park the wizard back on a fresh normal platform for the remaining tests
	main.coins = 5
	main.build_cooldown = 0.0
	main._try_build(Vector2(p.global_position.x + 200.0, 700.0))
	p.global_position = Vector2(p.global_position.x + 200.0, 640.0)
	p.velocity = Vector2.ZERO
	await create_timer(0.1).timeout

	# banner lead: SPRINGS is announced a short beat before 300 m, not a
	# whole wind-down early (Neven: 45 m ahead read as "too early")
	main.announced_level = 0
	main.hud.banner_label.text = ""
	main.distance_m = Levels.start_m(Levels.SPRINGS) - main.BANNER_LEAD_M - 10.0
	await create_timer(0.05).timeout
	var banner_quiet: bool = main.hud.banner_label.text == ""
	main.distance_m = Levels.start_m(Levels.SPRINGS) - main.BANNER_LEAD_M + 2.0
	await create_timer(0.05).timeout
	print("TEST bannerlead: quiet_before=%s text=\"%s\" (expect true, LEVEL 2: SPRINGS)" % [
		banner_quiet, main.hud.banner_label.text])
	_check(banner_quiet and main.hud.banner_label.text == "LEVEL 2: SPRINGS",
			"banner fires on its short lead")
	main.distance_m = 20.0

	# FLIPSIDE: buffered grounded flip, spam guard, solid builds
	main.distance_m = 950.0
	p.flip_cooldown = 0.0
	main._jump_pressed()
	await create_timer(0.07).timeout  # buffered flip fires on a grounded frame
	var flipped: bool = p.gravity_dir < 0.0
	main._jump_pressed()  # airborne + inside cooldown: must not flip again
	await create_timer(0.07).timeout
	var still_flipped: bool = p.gravity_dir < 0.0
	p.flip_buffer = 0.0
	p.gravity_dir = 1.0
	p.velocity = Vector2.ZERO
	main.coins = 1
	main.build_cooldown = 0.0
	main._try_build(Vector2(p.global_position.x + 3600.0, 300.0))
	var flip_pad: BuiltPlatform = null
	for c in main.get_children():
		if c is BuiltPlatform:
			flip_pad = c
	print("TEST flipside: flip=%s spam_guard=%s solid_build=%s (expect all true)" % [
		flipped, still_flipped, not flip_pad._cs.one_way_collision])
	_check(flipped and still_flipped and not flip_pad._cs.one_way_collision, "flipside")

	# the reported bug: a tap moments BEFORE touchdown must still flip
	main.coins = 1
	main.build_cooldown = 0.0
	main._try_build(Vector2(p.global_position.x + 200.0, 700.0))
	p.global_position = Vector2(p.global_position.x + 200.0, 620.0)
	p.velocity = Vector2(0.0, 350.0)  # falling, a few frames above the pad
	p.flip_cooldown = 0.0
	p.try_flip()  # airborne: buffers, must fire on touchdown
	await create_timer(0.12).timeout
	print("TEST flipbuffer: flipped_on_landing=%s (expect true)" % [p.gravity_dir < 0.0])
	_check(p.gravity_dir < 0.0, "flip buffered across landing")
	p.flip_buffer = 0.0
	p.gravity_dir = 1.0
	p.velocity = Vector2.ZERO

	# no hover/hop cheese: flips only from a surface or coyote — airborne
	# taps are refused outright (a mid-air flip is a disguised jump)
	p.global_position.y -= 400.0
	p.velocity = Vector2.ZERO
	await create_timer(0.25).timeout  # airborne, coyote expired
	p.flip_cooldown = 0.0
	p.try_flip()
	print("TEST flipcheese: airborne_flip_refused=%s (expect true, gravity unchanged)" % [
		p.gravity_dir > 0.0])
	_check(p.gravity_dir > 0.0, "no airborne flip")
	p.flip_buffer = 0.0
	p.velocity = Vector2.ZERO

	# wind-down hand-back: in the band's last stretch a tap is a JUMP again
	# and a leftover ceiling gravity rights itself on the next physics frame
	main.distance_m = Levels.start_m(Levels.UMBRA) - 20.0
	p.gravity_dir = -1.0
	p.jump_buffer = 0.0
	main._jump_pressed()
	var outro_jumps: bool = p.jump_buffer > 0.0
	await create_timer(0.05).timeout
	# the UMBRA banner must already have fired here, 20 m BEFORE the band
	var early_banner: bool = main.hud.banner_label.text == "LEVEL 5: UMBRA"
	print("TEST flipoutro: tap_jumps=%s (expect true) gravity=%.0f (expect 1) banner=\"%s\" (expect LEVEL 5: UMBRA)" % [
		outro_jumps, p.gravity_dir, main.hud.banner_label.text])
	_check(outro_jumps and p.gravity_dir > 0.0, "flipside wind-down hand-back")
	_check(early_banner, "UMBRA announced during the wind-down")
	# and the darkness is mid-gradient, not a hard cut: dimmer than the
	# psychedelic bands, brighter than UMBRA's floor
	main.psy._process(0.016)
	var mid_dark: float = main.psy.color.v
	main.distance_m = 20.0
	main.psy._process(0.016)
	var lite_v: float = main.psy.color.v
	main.distance_m = Levels.start_m(Levels.UMBRA) + 100.0
	main.psy._process(0.016)
	var full_dark: float = main.psy.color.v
	main.distance_m = Levels.start_m(Levels.UMBRA) - 20.0
	print("TEST umbrafade: lite=%.2f mid=%.2f dark=%.2f (expect strictly dimming)" % [
		lite_v, mid_dark, full_dark])
	_check(full_dark < mid_dark and mid_dark < lite_v, "umbra gradient in")
	p.jump_buffer = 0.0
	p.velocity = Vector2.ZERO

	# opening runway: taps still JUMP right after the boundary — the first
	# flip is only asked for once the runway ends
	main.distance_m = Levels.start_m(Levels.FLIPSIDE) + 10.0
	p.jump_buffer = 0.0
	p.flip_buffer = 0.0
	main._jump_pressed()
	var runway_jumps: bool = p.jump_buffer > 0.0 and p.flip_buffer <= 0.0
	print("TEST fliprunway: tap_jumps=%s (expect true)" % runway_jumps)
	_check(runway_jumps, "flipside runway taps jump")
	p.jump_buffer = 0.0

	# UMBRA: the world darkens, builds become lanterns, crystals beacon
	main.distance_m = 1300.0
	main.psy._process(0.016)
	var dark_ok: bool = main.psy.color.v < 0.4
	main.coins = 1
	main.build_cooldown = 0.0
	main._try_build(Vector2(p.global_position.x + 3900.0, 300.0))
	var lantern: BuiltPlatform = null
	for c in main.get_children():
		if c is BuiltPlatform:
			lantern = c
	var lantern_lit := false
	for c in lantern.get_children():
		if c is PointLight2D:
			lantern_lit = true
	main.spawner._place_coin(Vector2(main.start_x + 1300.0 * 100.0, -8500.0))
	var beacon := false
	for c in main.spawner.get_children():
		if c is ManaCrystal and c.position.y < -8000.0:
			for cc in c.get_children():
				if cc is PointLight2D:
					beacon = true
			c.queue_free()
	print("TEST umbra: dark=%s lantern=%s beacon=%s (expect all true)" % [
		dark_ok, lantern_lit, beacon])
	_check(dark_ok and lantern_lit and beacon, "umbra darkness")

	# SPELLBROS: the echo brother activates, mirrors, and banks crystals
	main.distance_m = 1600.0
	p.set_physics_process(false)  # hold the wizard still so the bro stays put
	await create_timer(0.1).timeout
	var bro_on: bool = main.bro.active and main.bro.visible
	var coins_pre: int = main.coins
	main.spawner._place_coin(main.bro.global_position)
	await create_timer(0.15).timeout
	p.set_physics_process(true)
	print("TEST echobro: active=%s coins %d -> %d (expect +1, bro collected)" % [
		bro_on, coins_pre, main.coins])
	_check(bro_on and main.coins == coins_pre + 1, "echo bro")

	# the bond, consequential: the bro intercepts one kill, then recharges
	var gblob := SpikeBlob.new(0.0, 100.0)
	gblob.global_position = p.global_position + Vector2(60.0, 0.0)
	main.add_child(gblob)
	p.velocity.y = 0.0
	gblob._on_body_entered(p)
	var guarded: bool = not p.dead and gblob.dying and main.bro.guard_cd > 0.0
	var gblob2 := SpikeBlob.new(0.0, 100.0)
	gblob2.global_position = p.global_position + Vector2(60.0, 0.0)
	main.add_child(gblob2)
	gblob2._on_body_entered(p)
	print("TEST broguard: guarded=%s (expect true) recharging_lethal=%s (expect true)" % [
		guarded, p.dead])
	_check(guarded and p.dead, "echo bro guardian")
	gblob.queue_free()
	gblob2.queue_free()
	p.dead = false
	p.collision_mask = 1
	p.rotation = 0.0
	p.velocity = Vector2.ZERO
	main.game_over = false
	main.hud.over_root.visible = false
	main.distance_m = 20.0
	main.bro.active = false

	# SHIFT+U dev cheat: every level unlocks as a starting point
	var evu := InputEventKey.new()
	evu.keycode = KEY_U
	evu.shift_pressed = true
	evu.pressed = true
	main.hud._unhandled_input(evu)
	print("TEST unlockcheat: unlocked=%d (expect %d)" % [
		Levels.load_unlocked(), Levels.count() - 1])
	_check(Levels.load_unlocked() == Levels.count() - 1, "shift+U unlocks all")

	# speed: flat before PHASE_SPEED, then ramps at SPEED_RAMP, capped
	var s0: float = main.run_speed_for(TerrainSpawner.PHASE_SPEED - 10.0)
	var s1: float = main.run_speed_for(TerrainSpawner.PHASE_SPEED + 100.0)
	var s2: float = main.run_speed_for(2000.0)
	print("TEST speed: pre-ramp %.0f (expect %.0f) | +100m %.0f (expect %.0f) | far %.0f (expect cap %.0f)" % [
		s0, main.BASE_SPEED, s1, main.BASE_SPEED + 100.0 * main.SPEED_RAMP, s2, main.SPEED_CAP])
	_check(s0 == main.BASE_SPEED, "speed base")
	_check(absf(s1 - (main.BASE_SPEED + 100.0 * main.SPEED_RAMP)) < 0.01, "speed ramp")
	_check(s2 == main.SPEED_CAP, "speed cap")

	# late-game platform decay
	var life_early: float = main.platform_life_for(0.0)
	var life_late: float = main.platform_life_for(2000.0)
	print("TEST platlife: early %.1fs (expect %.1f) late %.1fs (expect %.1f)" % [
		life_early, main.PLATFORM_LIFE, life_late, main.PLATFORM_LIFE_LATE])
	_check(life_early == main.PLATFORM_LIFE and life_late == main.PLATFORM_LIFE_LATE, "platform decay")

	# enemy speed ramp
	var es_early: float = main.spawner.enemy_speed_for(TerrainSpawner.PHASE_ENEMY)
	var es_late: float = main.spawner.enemy_speed_for(2000.0)
	print("TEST blobspeed: early %.0f (expect %.0f) late %.0f (expect %.0f)" % [
		es_early, TerrainSpawner.ENEMY_SPEED_BASE, es_late, TerrainSpawner.ENEMY_SPEED_MAX])
	_check(es_early == TerrainSpawner.ENEMY_SPEED_BASE and es_late == TerrainSpawner.ENEMY_SPEED_MAX, "enemy speed ramp")

	# pause freezes the world, resume unfreezes it
	var x_before: float = p.global_position.x
	main.hud._toggle_pause()
	await create_timer(0.4).timeout
	var frozen: bool = absf(p.global_position.x - x_before) < 0.01
	print("TEST pause: paused=%s frozen=%s (expect true true)" % [paused, frozen])
	_check(paused and frozen, "pause")
	main.hud._toggle_pause()
	await create_timer(0.2).timeout
	var moving: bool = absf(p.global_position.x - x_before) > 1.0
	print("TEST resume: paused=%s moving=%s (expect false true)" % [paused, moving])
	_check(not paused and moving, "resume")

	# audio: 6 synthesized SFX plus the looping psytrance track
	print("TEST audio: sfx=%d (expect 6) music_len=%.1fs (expect ~13.2) looping=%s" % [
		main.audio.players.size(), main.audio.music.stream.get_length(),
		main.audio.music.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD])
	_check(main.audio.players.size() == 6, "audio")

	# psytrance clock: 8 bars of 4/4 at BPM, beat-synced theme installed
	print("TEST psybeat: bpm=%.0f len=%.2fs (expect %.2f = 32 beats) theme=%s" % [
		GameAudio.BPM, main.audio.music.stream.get_length(), 32.0 * (60.0 / GameAudio.BPM),
		main.psy is PsyTheme])
	_check(absf(main.audio.music.stream.get_length() - 32.0 * (60.0 / GameAudio.BPM)) < 0.01,
			"psytrance loop length")
	_check(main.psy is PsyTheme and main.psy.is_processing(), "psy theme active")

	# stall crush: a player stuck behind the advancing camera dies
	p.global_position.x = main.cam.global_position.x - 1300.0
	await create_timer(0.3).timeout
	print("TEST crush: dead=%s game_over=%s (expect true true)" % [p.dead, main.game_over])
	_check(p.dead and main.game_over, "crush")

	await create_timer(1.0).timeout
	print("TEST endrun: game_over=%s distance=%dm" % [main.game_over, int(main.distance_m)])

	# level-band probes + beatability audit: 80 chunks per distance band
	print("TEST phases (80 chunks each):")
	print("  band     mega enem maxEnt climb void pilr star brdg flip sprg  minTop  pace  gap/reach mana/ch builds/ch  bad")
	for d: float in [15.0, 45.0, 80.0, 130.0, 230.0, 350.0, 700.0, 1000.0, 1300.0, 1600.0, 1900.0]:
		var s := _probe(d, 80)
		print("  d=%4dm  %3d  %3d  %4d  %4d  %3d  %3d  %3d  %3d  %3d  %3d  %5d  %.2f/s  %.2f      %.2f    %.2f      %3d" % [
			int(d), s["mega"], s["enemies"], s["max_entities"], s["climbs"],
			s["voids"], s["pillars"], s["stars"], s["bridge"], s["flip"], s["spring"],
			int(s["min_top"]), s["pace"],
			s["gap_ratio"], s["mana"], s["builds"], s["bad"]])
		_check(s["bad"] == 0, "beatability at d=%d" % int(d))
		# spring crossings (5-fragment arc trails) are exempt like the void:
		# their trails ARE the pad economy, not chunk clutter
		_check(s["max_entities"] <= (3 if d >= TerrainSpawner.PHASE_RICH else 2) \
				or s["voids"] > 0 or s["svoid"] > 0,
				"entity budget at d=%d" % int(d))
	# level/phase-shape expectations, derived from the constants so they
	# stay valid while tuning configs
	var pre := _probe(TerrainSpawner.PHASE_BUILD - 10.0, 80)
	_check(pre["mega"] == 0 and pre["enemies"] == 0 and pre["climbs"] == 0, "pre-phase calm")
	_check(pre["stars"] == 0, "no stars pre-enemy")
	var early := _probe((TerrainSpawner.PHASE_BUILD + TerrainSpawner.PHASE_ENEMY) * 0.5, 80)
	_check(early["mega"] >= 20 and early["enemies"] == 0, "megas live before enemies")
	var mid := _probe((TerrainSpawner.PHASE_ENEMY + TerrainSpawner.PHASE_CLIMB) * 0.5, 80)
	_check(mid["enemies"] > 0 and mid["climbs"] == 0, "enemies live before climbs")
	# FOUNDATIONS ends in the swarm zone (from PHASE_SWARM): densest enemies
	# (enemies per ELIGIBLE chunk; climb waves carry none and dilute raw counts)
	var swarm := _probe(TerrainSpawner.PHASE_SWARM + 60.0, 80)
	_check(swarm["enemy_rate"] > mid["enemy_rate"], "swarms denser than early enemies")
	_check(mid["stars"] + swarm["stars"] > 0, "stars spawn after enemy phase")
	# foundations climb waves (from PHASE_CLIMB, inside level 0)
	var climbb := _probe(130.0, 80)
	_check(climbb["climbs"] > 0 and climbb["min_top"] < 650.0, "climb waves live")
	# FOUNDATIONS wind-down: the band's last meters are calm plain hops —
	# no swarm slams into the SPRINGS teach-in
	var windb := _probe(Levels.start_m(Levels.SPRINGS) - 20.0, 80)
	_check(windb["mega"] == 0 and windb["enemies"] == 0 and windb["climbs"] == 0
			and windb["bad"] == 0, "foundations wind-down calm")
	# SPRINGS band, void-like: pillar diagonals, no enemies, pads affordable
	var springb := _probe(Levels.start_m(Levels.SPRINGS) + 50.0, 80)
	_check(springb["spring"] == 80 and springb["enemies"] == 0 and springb["mega"] == 0,
			"springs void band")
	_check(springb["mana"] >= springb["builds"] * 0.8, "springs pad economy")
	# the rhythm: easy deck sections split by void crossings (~1 in 3-5)
	_check(springb["svoid"] > 8 and springb["svoid"] < 40, "springs deck/void rhythm")
	# BLOB BRIDGES band: EVERY gap is a blob bridge (singles and doubles),
	# and the chain geometry holds exactly — first blob one edge-jump out,
	# doubles one passive bounce apart
	var bridgeb := _probe(Levels.start_m(Levels.BRIDGES) + 50.0, 80)
	_check(bridgeb["bridge"] == 80 and bridgeb["enemies"] > 80 and bridgeb["climbs"] == 0,
			"blob bridges band: every gap a blob bridge, doubles present")
	_check(bridgeb["b1err"] < 0.5 and bridgeb["bsperr"] < 0.5, "bridges flow geometry")
	# bridges wind-down: the corridor is entered calm — no blobs at the end
	var bridge_out := _probe(Levels.start_m(Levels.FLIPSIDE) - 20.0, 80)
	_check(bridge_out["bridge"] == 80 and bridge_out["enemies"] == 0,
			"bridges wind-down calm")
	# FLIPSIDE band: all corridor chunks, no enemies, chains + some dead zones
	var flipb := _probe(Levels.start_m(Levels.FLIPSIDE) + 50.0, 80)
	_check(flipb["flip"] == 80 and flipb["enemies"] == 0, "flipside corridor band")
	_check(flipb["dead"] > 0 and flipb["dead"] < 40, "flipside dead zones present but not dominant")
	# dead zones must be affordable: crystals in the band outpay the builds
	_check(flipb["mana"] >= flipb["builds"] * 0.8, "flipside build economy")
	# UMBRA and SPELLBROS run the standard generator (their twists live in
	# lighting and the echo bro); the band loop above already audits them
	var voidb := _probe(TerrainSpawner.PHASE_VOID + 120.0, 80)
	_check(voidb["voids"] > 20 and voidb["mega"] == 0 and voidb["enemies"] == 0, "void endgame")
	# teach-ins: every level's first ~45 m is its mechanic in gentle form
	var teach_spring := _probe(Levels.start_m(Levels.SPRINGS) + 10.0, 80)
	_check(teach_spring["spring"] == 80 and teach_spring["enemies"] == 0 \
			and teach_spring["climbs"] == 0, "springs teach-in is calm")
	var teach_bridge := _probe(Levels.start_m(Levels.BRIDGES) + 10.0, 80)
	_check(teach_bridge["bridge"] == 80 and teach_bridge["enemies"] == 80,
			"bridges teach-in: single blobs only")
	# FLIPSIDE opening runway (first ~20 m): continuous plain floor
	var runway := _probe(Levels.start_m(Levels.FLIPSIDE) + 10.0, 80)
	_check(runway["flip"] == 80 and runway["dead"] == 0 and runway["min_top"] >= 800.0,
			"flipside opening runway")
	# then the teach-in proper: chain strips, no dead zones yet
	var teach_flip := _probe(Levels.start_m(Levels.FLIPSIDE) + 30.0, 80)
	_check(teach_flip["flip"] == 80 and teach_flip["dead"] == 0,
			"flipside teach-in: chains, no dead zones")
	# FLIPSIDE wind-down: continuous floor near the deck, no dead zones
	var outro := _probe(Levels.start_m(Levels.UMBRA) - 20.0, 80)
	_check(outro["flip"] == 80 and outro["dead"] == 0 and outro["min_top"] >= 800.0,
			"flipside outro floor")
	var teach_void := _probe(TerrainSpawner.PHASE_VOID + 10.0, 80)
	_check(teach_void["pillars"] > voidb["pillars"], "void teach-in: denser pillars")

	print("SMOKE RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)


func _probe(d: float, n: int) -> Dictionary:
	main.distance_m = d
	# reset pattern state so probes are independent of each other
	main.spawner.climb_dir = 0
	main.spawner.climb_steps_left = 0
	main.spawner.flat_chunks_since_wave = 99
	main.spawner.force_mega = false
	main.spawner.last_top_y = TerrainSpawner.START_GROUND_Y
	main.spawner.spring_deck_left = 3
	main.spawner.enemy_seen = true  # probes sample mid-run behavior
	main.spawner.flip_on_floor = true
	main.spawner.flip_strip_start = 0.0
	var stats := {"mega": 0, "enemies": 0, "max_entities": 0, "climbs": 0,
			"voids": 0, "pillars": 0, "stars": 0, "bridge": 0, "flip": 0,
			"dead": 0, "spring": 0, "svoid": 0,
			"min_top": 9999.0, "bad": 0, "b1err": 0.0, "bsperr": 0.0,
			"mana": 0.0, "builds": 0.0, "pace": 0.0, "gap_ratio": 0.0,
			"enemy_rate": 0.0}
	var span := 0.0
	var ratio_sum := 0.0
	var ratio_n := 0
	var eligible := 0
	for i in range(n):
		# pin the spawn cursor so every sampled chunk sits at exactly d meters
		main.spawner.next_x = d * 100.0 + main.start_x
		var s: Dictionary = main.spawner._spawn_chunk()
		var v: float = s["speed"]
		if s["mega"]:
			stats["mega"] += 1
		stats["enemies"] += s["enemies"]
		stats["max_entities"] = maxi(stats["max_entities"], int(s["entities"]))
		if s["climb"] != 0:
			stats["climbs"] += 1
		if s["void"]:
			stats["voids"] += 1
		if s["pillar"]:
			stats["pillars"] += 1
		stats["stars"] += s["stars"]
		if s.get("bridge", false):
			stats["bridge"] += 1
		if s.get("flip", false):
			stats["flip"] += 1
		if s.get("dead", false):
			stats["dead"] += 1
		if s.get("spring", false):
			stats["spring"] += 1
		if s.get("svoid", false):
			stats["svoid"] += 1
		stats["min_top"] = minf(stats["min_top"], s["top_y"])
		if s["climb"] == 0 and not s["void"] and not s["pillar"]:
			eligible += 1
		span += s["gap"] + s["width"]
		stats["mana"] += float(s["entities"] - s["enemies"] - s["stars"])
		# --- beatability audit ---
		var one_build := 1.418 * v + 240.0  # jump + platform deck + jump
		if s["void"]:
			stats["builds"] += ceilf(s["gap"] / one_build)
		elif s.get("bridge", false):
			if s.get("bkind", "blob") == "out":
				# blob-free wind-down: a plain jump must clear it
				if s["gap"] > 0.68 * v:
					stats["bad"] += 1
			else:
				# blob gap: the stomp chain is the line, one build the fallback
				stats["builds"] += 1.0
				if s["gap"] > one_build:
					stats["bad"] += 1
				# flow geometry: first blob one edge-jump out (0.5*v), a
				# double's second one passive bounce later (0.6*v), and the
				# bounce off the last blob (0.71*v of carry) must land
				# INSIDE the far deck, never past it
				stats["b1err"] = maxf(stats["b1err"], absf(s["b1"] - 0.5 * v))
				var blast: float = s["b1"]
				if s["blobs"] == 2:
					stats["bsperr"] = maxf(stats["bsperr"],
							absf(s["b2"] - s["b1"] - 0.6 * v))
					blast = s["b2"]
				var land_in: float = 0.71 * v - (s["gap"] - blast)
				if land_in < 50.0 or land_in > s["width"] - 30.0:
					stats["bad"] += 1
		elif s.get("dead", false):
			# dead zone: no jump exists in FLIPSIDE, so the crossing is
			# run-off fall + one pad + run-off fall onto the LOWER far deck
			stats["builds"] += 1.0
			if s["gap"] > 0.5 * v + 240.0:
				stats["bad"] += 1
		elif s.get("spring", false):
			if s.get("svoid", false):
				# two-pad crossing: jump/fall to pad 1 (~0.42*v in), half an
				# arc to its apex (0.45*v, 241 px above takeoff), then a full
				# second launch from apex height down/up to the far deck
				stats["builds"] += 2.0
				var t_sp := (1500.0 + sqrt(maxf(0.0, 2250000.0 - 6600.0 * (s["rise"] - 241.0)))) / 3300.0
				if s["rise"] > 260.0 or s["gap"] > (0.42 + 0.45 + 0.92 * t_sp) * v:
					stats["bad"] += 1
			else:
				# deck pillar: a plain jump must clear it
				var disc_s: float = 1170.0 * 1170.0 - 6600.0 * s["rise"]
				if disc_s < 0.0 or s["gap"] > v * (1170.0 + sqrt(disc_s)) / 3300.0:
					stats["bad"] += 1
		elif s.get("flip", false):
			# chain strip: needs a real shared flip window (0.25 s of travel)
			# AND enough strip beyond it to land the ~0.54 s flip transit
			if s["overlap"] < 0.25 * v or s["width"] + s["overlap"] < 0.62 * v:
				stats["bad"] += 1
		elif s["climb"] == -1:
			stats["builds"] += 1.0  # each up-stair is one platform
		elif s["mega"]:
			stats["builds"] += 1.0
			if s["gap"] > one_build:
				stats["bad"] += 1
		elif s["climb"] == 0 or s["climb"] == 1:
			var rise: float = s["rise"]
			var disc := 1170.0 * 1170.0 - 6600.0 * rise
			if disc < 0.0:
				stats["bad"] += 1  # would need to rise above max jump height
			else:
				var reach := v * (1170.0 + sqrt(disc)) / 3300.0
				ratio_sum += s["gap"] / reach
				ratio_n += 1
				if s["gap"] > reach:
					stats["bad"] += 1
	stats["pace"] = float(n) / (span / maxf(main.run_speed_for(d), 1.0))
	stats["gap_ratio"] = ratio_sum / maxf(float(ratio_n), 1.0)
	stats["mana"] = stats["mana"] / float(n)
	stats["builds"] = stats["builds"] / float(n)
	stats["enemy_rate"] = float(stats["enemies"]) / maxf(float(eligible), 1.0)
	return stats
