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
	await create_timer(1.0).timeout
	var p = main.player
	print("TEST setup: player=%s on_floor=%s coins=%d (expect %d = START_COINS)" % [p != null, p.is_on_floor(), main.coins, main.START_COINS])
	_check(p != null and main.coins == main.START_COINS, "setup")

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
	main._handle_tap(Vector2(wiz_x + 300.0, 500.0))
	print("TEST taproute: left_jumps=%s (expect true) coins=%d (expect 0, right tap built)" % [
		left_jumps, main.coins])
	_check(left_jumps and main.coins == 0, "tap routing")
	p.jump_buffer = 0.0

	# stomp bounty: squishing a blob pays +1 mana and bounces the player
	main.coins = 2
	var blob := SpikeBlob.new(0.0, 100.0)
	blob.global_position = p.global_position + Vector2(0.0, 60.0)
	main.add_child(blob)
	p.velocity.y = 300.0  # falling onto it
	blob._on_body_entered(p)
	print("TEST stomp: coins=%d (expect 3) blob_dying=%s vel_y=%.0f (expect -880) player_alive=%s" % [
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

	# park the wizard on a fresh platform so the star test starts grounded
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
	_check(granted == 1 and airborne and p.velocity.y < -500.0 and p.air_jumps == 0,
			"star of levity")

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

	# audio: 5 synthesized SFX plus a looping music track
	print("TEST audio: sfx=%d (expect 5) music_len=%.1fs (expect ~8.7) looping=%s" % [
		main.audio.players.size(), main.audio.music.stream.get_length(),
		main.audio.music.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD])
	_check(main.audio.players.size() == 5, "audio")

	# stall crush: a player stuck behind the advancing camera dies
	p.global_position.x = main.cam.global_position.x - 1300.0
	await create_timer(0.3).timeout
	print("TEST crush: dead=%s game_over=%s (expect true true)" % [p.dead, main.game_over])
	_check(p.dead and main.game_over, "crush")

	await create_timer(1.0).timeout
	print("TEST endrun: game_over=%s distance=%dm" % [main.game_over, int(main.distance_m)])

	# difficulty phase probes + beatability audit: 80 chunks per distance band
	print("TEST phases (80 chunks each):")
	print("  band     mega enem maxEnt climb void pilr star  minTop  pace  gap/reach mana/ch builds/ch  bad")
	for d: float in [15.0, 45.0, 80.0, 130.0, 190.0, 280.0, 380.0, 550.0]:
		var s := _probe(d, 80)
		print("  d=%4dm  %3d  %3d  %4d  %4d  %3d  %3d  %3d  %5d  %.2f/s  %.2f      %.2f    %.2f      %3d" % [
			int(d), s["mega"], s["enemies"], s["max_entities"], s["climbs"],
			s["voids"], s["pillars"], s["stars"], int(s["min_top"]), s["pace"],
			s["gap_ratio"], s["mana"], s["builds"], s["bad"]])
		_check(s["bad"] == 0, "beatability at d=%d" % int(d))
		_check(s["max_entities"] <= (3 if d >= TerrainSpawner.PHASE_RICH else 2) or s["voids"] > 0,
				"entity budget at d=%d" % int(d))
	# phase-shape expectations, derived from the PHASE_* constants so they
	# stay valid while tuning configs
	var pre := _probe(TerrainSpawner.PHASE_BUILD - 10.0, 80)
	_check(pre["mega"] == 0 and pre["enemies"] == 0 and pre["climbs"] == 0, "pre-phase calm")
	_check(pre["stars"] == 0, "no stars pre-enemy")
	var early := _probe((TerrainSpawner.PHASE_BUILD + TerrainSpawner.PHASE_ENEMY) * 0.5, 80)
	_check(early["mega"] >= 20 and early["enemies"] == 0, "megas live before enemies")
	var mid := _probe((TerrainSpawner.PHASE_ENEMY + TerrainSpawner.PHASE_CLIMB) * 0.5, 80)
	_check(mid["enemies"] > 0 and mid["climbs"] == 0, "enemies live before climbs")
	var climbb := _probe(TerrainSpawner.PHASE_CLIMB + 30.0, 80)
	_check(climbb["climbs"] > 0 and climbb["min_top"] < 650.0, "climb waves live")
	# compare enemies per ELIGIBLE chunk (climb waves carry no enemies and
	# would dilute a raw count into a coin flip)
	var swarm := _probe(TerrainSpawner.PHASE_SWARM + 60.0, 80)
	_check(swarm["enemy_rate"] > mid["enemy_rate"], "swarms denser than early enemies")
	# Star of Levity spawns are rare but 240 post-enemy chunks make 0 near-impossible
	_check(mid["stars"] + climbb["stars"] + swarm["stars"] > 0, "stars spawn after enemy phase")
	var voidb := _probe(TerrainSpawner.PHASE_VOID + 120.0, 80)
	_check(voidb["voids"] > 20 and voidb["mega"] == 0 and voidb["enemies"] == 0, "void endgame")

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
	var stats := {"mega": 0, "enemies": 0, "max_entities": 0, "climbs": 0,
			"voids": 0, "pillars": 0, "stars": 0, "min_top": 9999.0, "bad": 0,
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
		stats["min_top"] = minf(stats["min_top"], s["top_y"])
		if s["climb"] == 0 and not s["void"] and not s["pillar"]:
			eligible += 1
		span += s["gap"] + s["width"]
		stats["mana"] += float(s["entities"] - s["enemies"] - s["stars"])
		# --- beatability audit ---
		var one_build := 1.418 * v + 240.0  # jump + platform deck + jump
		if s["void"]:
			stats["builds"] += ceilf(s["gap"] / one_build)
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
