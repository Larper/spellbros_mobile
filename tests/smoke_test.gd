extends SceneTree

## Headless smoke test: run with
##   godot --headless --path . -s res://tests/smoke_test.gd
## Loads the real game scene, drives its public entry points, then probes
## the terrain spawner at forced distances to verify the difficulty phases.

var main


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	current_scene = main
	_run_tests.call_deferred()


func _run_tests() -> void:
	await create_timer(1.0).timeout
	var p = main.player
	print("TEST setup: player=%s on_floor=%s coins=%d (expect 3)" % [p != null, p.is_on_floor(), main.coins])

	# build a platform ahead of the wizard
	var coins_before: int = main.coins
	main._try_build(Vector2(p.global_position.x + 500.0, p.global_position.y - 120.0))
	await create_timer(0.1).timeout
	var plat_count := 0
	for c in main.get_children():
		if c is BuiltPlatform:
			plat_count += 1
	print("TEST build: coins %d -> %d (expect -1), platforms=%d (expect 1)" % [coins_before, main.coins, plat_count])

	# jump
	var y_before: float = p.global_position.y
	p.try_jump()
	await create_timer(0.25).timeout
	print("TEST jump: y %.0f -> %.0f (expect lower value = rose)" % [y_before, p.global_position.y])

	# stomp refresh: bouncing off an enemy grants one air jump until landing
	p.global_position.y -= 400.0
	p.bounce()
	await create_timer(0.3).timeout
	var fall_vel: float = p.velocity.y
	p.try_jump()
	await create_timer(0.1).timeout
	print("TEST stompjump: vel %.0f -> %.0f (expect falling, then jump < -700)" % [fall_vel, p.velocity.y])

	# no-mana path must refuse to build
	main.coins = 0
	main.build_cooldown = 0.0
	main._try_build(Vector2(p.global_position.x + 300.0, 500.0))
	print("TEST nomana: coins=%d (expect 0, no free platform)" % main.coins)

	# stomp bounty: squishing a blob pays +1 mana and bounces the player
	main.coins = 2
	var blob := SpikeBlob.new(0.0, 100.0)
	blob.global_position = p.global_position + Vector2(0.0, 60.0)
	main.add_child(blob)
	p.velocity.y = 300.0  # falling onto it
	blob._on_body_entered(p)
	print("TEST stomp: coins=%d (expect 3) blob_dying=%s vel_y=%.0f (expect -880) player_alive=%s" % [
		main.coins, blob.dying, p.velocity.y, not p.dead])
	blob.queue_free()

	# side hit still kills: bounty must not make blobs safe to touch
	var blob2 := SpikeBlob.new(0.0, 100.0)
	blob2.global_position = p.global_position + Vector2(60.0, 0.0)
	main.add_child(blob2)
	p.velocity.y = 0.0
	blob2._on_body_entered(p)
	print("TEST sidehit: dead=%s (expect true) coins=%d (expect still 3)" % [p.dead, main.coins])
	blob2.queue_free()
	# revive for the remaining tests (same run, fresh wizard state)
	p.dead = false
	p.collision_mask = 1
	p.rotation = 0.0
	p.velocity = Vector2.ZERO
	main.game_over = false
	main.hud.over_root.visible = false

	# golden crystal: worth 3 mana, with a spawn rate of ~10%
	main.coins = 0
	var gold := ManaCrystal.new()
	gold.make_golden()
	main.add_child(gold)
	gold._on_body_entered(p)
	var goldens := 0
	for i in range(400):
		main.spawner._place_coin(Vector2(-9000.0, -9000.0))
	for c in main.spawner.get_children():
		if c is ManaCrystal and c.position.y < -8000.0:
			if c.value == 3:
				goldens += 1
			c.queue_free()
	print("TEST gold: coins=%d (expect 3) spawn_rate=%.1f%% of 400 (expect ~10%%)" % [
		main.coins, goldens / 4.0])
	gold.queue_free()

	# spring platform: every 4th build is a green launcher pad
	main.coins = 10
	main.builds = 0
	var spring_flags := []
	var ready_after_3 := false
	for i in range(4):
		main.build_cooldown = 0.0
		main._try_build(Vector2(p.global_position.x + 3000.0 + 300.0 * float(i), 300.0))
		if i == 2:
			ready_after_3 = main.hud.spring_label.visible
	var new_plats := []
	for c in main.get_children():
		if c is BuiltPlatform and c.global_position.y < 320.0:
			new_plats.append(c)
	for plat in new_plats:
		spring_flags.append(plat.bouncy)
	print("TEST spring: flags=%s (expect [false, false, false, true]) hud_ready_after_3=%s (expect true) hud_after_4=%s (expect false)" % [
		spring_flags, ready_after_3, main.hud.spring_label.visible])

	# spring launch: landing on the pad flings the player ~1.6x jump height
	var pad: BuiltPlatform = new_plats[3]
	pad.age = 0.0  # fresh lifetime so it cannot crumble mid-test
	p.global_position = pad.global_position + Vector2(-80.0, -70.0)
	p.velocity = Vector2.ZERO
	var min_vy := 0.0
	for i in range(12):
		await create_timer(0.05).timeout
		min_vy = minf(min_vy, p.velocity.y)
	print("TEST springlaunch: min_vel_y=%.0f (expect <= -1200, stronger than jump -1170)" % min_vy)
	# park the wizard on a fresh normal platform so later tests start grounded
	main.coins = 5
	main.build_cooldown = 0.0
	main._try_build(Vector2(p.global_position.x + 200.0, 700.0))
	p.global_position = Vector2(p.global_position.x + 200.0, 640.0)
	p.velocity = Vector2.ZERO
	await create_timer(0.1).timeout

	# Star of Levity: pickup stores one air jump; tapping mid-air spends it
	var star := StarPickup.new()
	star.global_position = p.global_position
	main.add_child(star)
	star._on_body_entered(p)
	var granted: int = p.air_jumps
	p.global_position.y -= 500.0
	p.velocity = Vector2.ZERO
	await create_timer(0.3).timeout  # fall until floor state and coyote expire
	var airborne: bool = not p.is_on_floor() and p.coyote <= 0.0
	p.try_jump()
	await create_timer(0.1).timeout
	print("TEST star: granted=%d (expect 1) airborne=%s (expect true) vel_y=%.0f (expect < -500) charges_left=%d (expect 0)" % [
		granted, airborne, p.velocity.y, p.air_jumps])

	# speed phases: flat until 190 m, then ramps, capped at 780
	print("TEST speed: d=100 %.0f (expect 470) | d=260 %.0f (expect 533) | d=700 %.0f (expect 780)" % [
		main.run_speed_for(100.0), main.run_speed_for(260.0), main.run_speed_for(700.0)])

	# pause freezes the world, resume unfreezes it
	var x_before: float = p.global_position.x
	main.hud._toggle_pause()
	await create_timer(0.4).timeout
	var frozen: bool = absf(p.global_position.x - x_before) < 0.01
	print("TEST pause: paused=%s frozen=%s (expect true true)" % [paused, frozen])
	main.hud._toggle_pause()
	await create_timer(0.2).timeout
	var moving: bool = absf(p.global_position.x - x_before) > 1.0
	print("TEST resume: paused=%s moving=%s (expect false true)" % [paused, moving])

	# audio: 6 synthesized SFX plus a looping music track
	print("TEST audio: sfx=%d (expect 6) music_len=%.1fs (expect ~8.7) looping=%s" % [
		main.audio.players.size(), main.audio.music.stream.get_length(),
		main.audio.music.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD])

	# stall crush: a player stuck behind the advancing camera dies
	p.global_position.x = main.cam.global_position.x - 1300.0
	await create_timer(0.3).timeout
	print("TEST crush: dead=%s game_over=%s (expect true true)" % [p.dead, main.game_over])

	await create_timer(1.0).timeout
	print("TEST endrun: game_over=%s distance=%dm" % [main.game_over, int(main.distance_m)])

	# difficulty phase probes: 40 chunks per distance band
	print("TEST phases (40 chunks each):")
	for d: float in [20.0, 60.0, 100.0, 160.0, 350.0, 550.0]:
		var s := _probe(d, 40)
		print("  d=%4dm  mega=%2d  enemies=%2d  maxPerChunk=%d  climbChunks=%2d  voids=%2d  pillars=%2d  stars=%2d  minTopY=%4d" % [
			int(d), s["mega"], s["enemies"], s["max_entities"], s["climbs"],
			s["voids"], s["pillars"], s["stars"], int(s["min_top"])])
	print("  expect: d=20 all zeros | d=60 mega~14+ enemies=0 stars=0 | d=100 enemies>0 climb=0")
	print("  expect: d=160 climbChunks>0 minTopY<650 | d=350 more enemies, maxPerChunk<=2")
	print("  expect: d=550 mostly voids, some pillars, no mega/enemies/climb")
	print("  expect: stars only at 100/160/350 (rare; a few across those bands)")
	quit()


func _probe(d: float, n: int) -> Dictionary:
	main.distance_m = d
	var stats := {"mega": 0, "enemies": 0, "max_entities": 0, "climbs": 0,
			"voids": 0, "pillars": 0, "stars": 0, "min_top": 9999.0}
	for i in range(n):
		# pin the spawn cursor so every sampled chunk sits at exactly d meters
		main.spawner.next_x = d * 100.0 + main.start_x
		var s: Dictionary = main.spawner._spawn_chunk()
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
		stats["min_top"] = minf(stats["min_top"], s["top_y"])
	return stats
