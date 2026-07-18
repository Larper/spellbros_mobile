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

	# no-mana path must refuse to build
	main.coins = 0
	main.build_cooldown = 0.0
	main._try_build(Vector2(p.global_position.x + 300.0, 500.0))
	print("TEST nomana: coins=%d (expect 0, no free platform)" % main.coins)

	# speed phases: flat until 190 m, then ramps, capped at 780
	print("TEST speed: d=100 %.0f (expect 390) | d=260 %.0f (expect 453) | d=700 %.0f (expect 780)" % [
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

	# audio: 5 synthesized SFX plus a looping music track
	print("TEST audio: sfx=%d (expect 5) music_len=%.1fs (expect ~8.7) looping=%s" % [
		main.audio.players.size(), main.audio.music.stream.get_length(),
		main.audio.music.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD])

	# let the run play out to a natural death
	await create_timer(12.0).timeout
	print("TEST endrun: game_over=%s distance=%dm" % [main.game_over, int(main.distance_m)])

	# difficulty phase probes: 40 chunks per distance band
	print("TEST phases (40 chunks each):")
	for d: float in [20.0, 60.0, 100.0, 160.0, 350.0]:
		var s := _probe(d, 40)
		print("  d=%4dm  mega=%2d  enemies=%2d  maxPerChunk=%d  climbChunks=%2d  minTopY=%4d" % [
			int(d), s["mega"], s["enemies"], s["max_entities"], s["climbs"], int(s["min_top"])])
	print("  expect: d=20 all zeros | d=60 mega~14+ enemies=0 | d=100 enemies>0 climb=0")
	print("  expect: d=160 climbChunks>0 minTopY<650 | d=350 more enemies | maxPerChunk<=2")
	quit()


func _probe(d: float, n: int) -> Dictionary:
	main.distance_m = d
	var stats := {"mega": 0, "enemies": 0, "max_entities": 0, "climbs": 0, "min_top": 9999.0}
	for i in range(n):
		var s: Dictionary = main.spawner._spawn_chunk()
		if s["mega"]:
			stats["mega"] += 1
		stats["enemies"] += s["enemies"]
		stats["max_entities"] = maxi(stats["max_entities"], int(s["entities"]))
		if s["climb"] != 0:
			stats["climbs"] += 1
		stats["min_top"] = minf(stats["min_top"], s["top_y"])
	return stats
