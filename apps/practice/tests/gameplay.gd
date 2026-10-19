extends SceneTree

var game: Node
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error(message)
		quit(1)

func fresh() -> void:
	game._new_round()
	game.set_process(false)
	# Core rules without the pet mount (it would absorb the first hit; see battle_items.gd).
	game.battle_items.mounted = false

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	for level_index in range(3):
		game._select_level(level_index)
		fresh()
		check(game.fighters.size() == 4, "Expected one player and three bots")
		check(game.player["lives"] == 3 and game.remaining == 180.0, "Lives/timer")
		for actor in game.fighters:
			check(game._has_escape_route(actor), "Every spawn must have an escape")
			if actor["bot"]:
				check(actor["lives"] == 1, "Bot should have one life")
		check(not game._move_fighter(game.player, Vector2i.UP), "Wall collision")
		game._place_bomb(game.player)
		game._place_bomb(game.player)
		check(game.bombs.size() == 1, "Capacity prevents duplicate bombs")
		check(game._move_fighter(game.player, Vector2i.RIGHT), "Leave own bomb")
		check(not game._move_fighter(game.player, Vector2i.LEFT), "Cannot reenter bomb")
		game._hit_fighter(game.player)
		game._hit_fighter(game.player)
		check(game.player["lives"] == 2, "Invulnerability prevents repeated damage")
		for kind in ["extra_bomb", "flame", "shoe"]:
			var node := Node2D.new()
			game.world.add_child(node)
			game.items[game.player["cell"]] = {"node": node, "kind": kind}
			game._collect_item(game.player)
		check(game.player["bomb_capacity"] == 2, "Extra bomb pickup")
		check(game.player["bomb_range"] == 3, "Range pickup")
		check(game.player["speed"] > 1.0 and game.items.is_empty(), "Speed/pickup removal")
		for hero in game.HEROES:
			game.player["sprite"].configure(hero)
			for direction in ["walk_up", "walk_down", "walk_left", "walk_right"]:
				check(game.player["sprite"].sprite_frames.get_frame_count(direction) == 6, "Six frames per direction")
		print("GAMEPLAY MAP OK ", game.current_level["id"])

	game._select_level(0)
	fresh()
	# A late bomb is accelerated by an earlier bomb, in either placement order.
	var rival: Dictionary = game.fighters[1]
	rival["cell"] = Vector2i(3, 1)
	game._place_bomb(rival)
	game._place_bomb(game.player)
	game.bombs[1]["timer"] = 0.1
	check(game._danger_at(Vector2i(5, 1), 0.2), "Forecast includes chained bombs")
	game.player["lives"] = 1
	for actor in game.fighters:
		if actor != game.player and actor != rival:
			actor["alive"] = false
	game.remaining_bots = 1
	game._explode_bomb(game.bombs[1])
	check(game.bombs.is_empty(), "All chained bombs removed")
	check(not game.player["alive"] and not rival["alive"], "Resolve all chain victims")
	check(game.result_title.text == "THUA RỒI!", "Simultaneous last bot/player death is not a victory")

	fresh()
	# Independent bombs expiring in the same frame must also resolve together.
	rival = game.fighters[1]
	for actor in game.fighters:
		if actor != game.player and actor != rival:
			actor["alive"] = false
	game.remaining_bots = 1
	game.player["lives"] = 1
	game._place_bomb(rival)
	game._place_bomb(game.player)
	for bomb in game.bombs:
		bomb["timer"] = 0.01
	game._update_bombs(0.02)
	check(not game.player["alive"] and not rival["alive"], "Independent simultaneous victims")
	check(game.result_title.text == "THUA RỒI!", "No premature victory between independent explosions")

	fresh()
	var crate_cell: Vector2i = game.crates.keys()[0]
	var origin: Vector2i = crate_cell + Vector2i.LEFT
	game.player["cell"] = origin
	game._place_bomb(game.player)
	game._explode_bomb(game.bombs[0])
	check(not game.crates.has(crate_cell), "Explosion destroys crate")

	fresh()
	var bot: Dictionary = game.fighters[1]
	bot["cell"] = Vector2i(3, 1)
	game._place_bomb(bot)
	var step: Vector2i = game._escape_step(bot)
	check(step != Vector2i.ZERO, "BFS finds first escape step")
	game.bursts.append({"cells": [Vector2i(4, 1)], "duration": 0.5, "visuals": []})
	check(not game._safe_path_cell(Vector2i(4, 1), 0.1), "BFS never walks through live flames")
	# Enclose all neighboring cells without allocating visuals.
	for d in game.DIRECTIONS:
		game.terrain[bot["cell"] + d] = null
	check(not game._has_escape_route(bot), "Trapped bot must not plant a bomb")

	fresh()
	game.remaining = 0.01
	game._process(0.02)
	check(game.game_state == "ended" and game.result_title.text == "THUA RỒI!", "180-second timeout loses")
	var restart := InputEventKey.new()
	restart.keycode = KEY_R
	restart.pressed = true
	game._input(restart)
	check(game.game_state == "playing" and game.remaining == 180.0 and game.player["lives"] == 3, "R restarts a finished round")
	var pause := InputEventKey.new()
	pause.keycode = KEY_ESCAPE
	pause.pressed = true
	game._input(pause)
	check(game.game_state == "paused", "Escape pauses a round")
	game._input(restart)
	check(game.game_state == "playing" and not game.result.visible, "R restarts a paused round and hides overlay")
	game._toggle_audio()
	check(not game.music_enabled and not game.music.playing, "Mute stops background music")
	game._toggle_audio()
	check(game.music_enabled and game.music.playing, "Unmute restarts music")
	print("STEP3_GAMEPLAY_OK checks=", checks)
	if game.music_enabled:
		game._toggle_audio()
	game.queue_free()
	await create_timer(0.15).timeout
	quit(0)
