extends SceneTree
## Practice quick slot items, mount and the battle HUD (docs/BATTLE_ITEMS.md).

var game: Node
var checks := 0
var failed := false
var state: Node

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error(message)
		failed = true

## An open board: no walls or crates, player at (2, 5), bots far away.
func open_round() -> void:
	state.profile["consumables"] = {"throw_bomb": 2, "dart": 1, "blue_shield": 1, "speed_shoes": 1, "freeze_bomb": 1, "push_glove": 1}
	game._new_round()
	game.set_process(false)
	for cell in game.terrain.keys():
		game.terrain[cell].queue_free()
	game.terrain.clear()
	for cell in game.crates.keys():
		game.crates[cell].queue_free()
	game.crates.clear()
	game.player.cell = Vector2i(2, 5)
	for i in range(1, 4):
		game.fighters[i].cell = Vector2i(12, 1 + i * 2)

func _run() -> void:
	state = root.get_node("UIState")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var items: Node = game.battle_items
	game._select_level(0)
	open_round()
	check(items.view().slots.size() == 6, "Six quick slots")
	check(items.counts.throw_bomb == 2 and items.counts.dart == 1, "Counts come from the stock")

	# 1-6 selects; Ctrl uses the selected item in the facing direction.
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_1
	game._input(key)
	items.facing = Vector2i.RIGHT
	key.keycode = KEY_CTRL
	game._input(key)
	check(game.bombs.size() == 1 and game.bombs[0].cell == Vector2i(5, 5), "Thrown bomb lands 3 cells ahead")
	check(game.bombs[0].thrown and items.counts.throw_bomb == 1, "Throw consumes one")
	check(int(state.profile.consumables.throw_bomb) == 1, "Stock follows the use")
	check(not items.use_item("throw_bomb"), "Throw on cooldown")
	game._place_bomb(game.player)
	check(game.bombs.size() == 2, "A thrown bomb does not take the bomb slot")

	# Dart detonates the first bomb on its line, once.
	var target: Dictionary = game._bomb_at(Vector2i(5, 5))
	game.player.cell = Vector2i(5, 8)
	items.facing = Vector2i.UP
	check(items.use_item("dart"), "Dart flies")
	check(not game.bombs.has(target), "Dart detonates the bomb it hits")
	check(items.counts.dart == 0 and not items.use_item("dart"), "Empty slot cannot be used")
	game.bombs.clear()
	game.bursts.clear()

	# Shield absorbs one hit, then lives drop again.
	var lives: int = game.player.lives
	check(items.use_item("blue_shield"), "Shield up")
	game._hit_fighter(game.player)
	check(game.player.lives == lives, "Shield absorbs a hit")
	game.elapsed += 1.0
	game._hit_fighter(game.player)
	check(game.player.lives == lives - 1, "Shield is gone after one hit")

	# Speed boots and the freeze bomb.
	check(items.use_item("speed_shoes") and is_equal_approx(items.speed_factor(), 1.35), "Speed +35%")
	var bot: Dictionary = game.fighters[1]
	bot.cell = game.player.cell + Vector2i(0, -2)
	items.facing = Vector2i.UP
	check(items.use_item("freeze_bomb"), "Freeze thrown")
	check(items.bot_step_factor(bot) > 1.0, "Freeze slows the bot")
	game.elapsed += 3.5
	check(items.bot_step_factor(bot) == 1.0, "Slow ends after 3 s")

	# Push glove slides the bomb in front.
	game.player.cell = Vector2i(2, 3)
	game._spawn_bomb(game.player, Vector2i(3, 3), false)
	items.facing = Vector2i.RIGHT
	check(items.use_item("push_glove"), "Push accepted")
	check(game.bombs[0].cell.x > 3, "Bomb slid forward")

	# Mount: needs a pet, +25% speed, absorbs one hit then is gone for the round.
	items.pet = ""
	check(not items.toggle_mount(), "No pet, no mount")
	items.pet = "pet_bunny"
	game.elapsed += 2.0  # boots from above have run out
	key.keycode = KEY_Q
	game._input(key)
	check(items.mounted and is_equal_approx(items.speed_factor(), 1.25), "Mounted +25%")
	game.elapsed += 3.0
	lives = game.player.lives
	game.player.invulnerable = 0.0
	game._hit_fighter(game.player)
	check(game.player.lives == lives and not items.mounted and items.pet_used, "Mount absorbs one hit")
	check(not items.toggle_mount(), "Mount used up this round")

	# HUD shows the panel and the six slots with the yellow selection.
	check(game.find_children("BattleItemPanel", "", true, false).size() >= 1, "VẬT PHẨM panel present")
	check(game.find_children("QuickSlot6", "", true, false).size() >= 1, "Quick slot 6 present")
	if not failed:
		print("BATTLE_ITEMS_OK checks=", checks)
	quit(1 if failed else 0)
