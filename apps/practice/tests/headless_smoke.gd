extends SceneTree
## Optional integration test: godot --headless --path . --script res://tests/headless_smoke.gd

func _initialize() -> void:
	call_deferred("_smoke")

func _smoke() -> void:
	var packed = load("res://scenes/main.tscn")
	if packed == null:
		push_error("Cannot load main.tscn")
		quit(1)
		return
	var game = packed.instantiate()
	root.add_child(game)
	await process_frame
	for level_index in range(3):
		game._select_level(level_index)
		game._new_round()
		await process_frame
		assert(game.terrain.size() > 20, "Missing solid walls")
		assert(game.crates.size() > 10, "Missing breakables")
		assert(game.fighters.size() == 4, "Wrong fighter count")
		var start_cell: Vector2i = game.player["cell"]
		game._place_bomb(game.player)
		assert(game.bombs.size() == 1, "Bomb not created")
		assert(game.bombs[0]["cell"] == start_cell, "Bomb on wrong cell")
		game.bombs[0]["timer"] = 0.03
		await create_timer(0.12).timeout
		assert(game.bursts.size() >= 1, "Bomb did not explode")
		print("SMOKE PASS ", game.current_level["id"])
	print("ALL GAME BOOM STEP 3 SMOKE TESTS PASSED")
	if game.music_enabled:
		game._toggle_audio()
	game.queue_free()
	await create_timer(0.15).timeout
	quit(0)
