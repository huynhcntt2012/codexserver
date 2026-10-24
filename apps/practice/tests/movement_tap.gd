extends SceneTree
## Practice movement: a short tap moves exactly one cell (also mounted, +25 %
## speed); holding the key keeps walking.
var failed := false

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

## Runs the round by hand for `seconds` (60 fps) and returns the cells moved.
func play(game: Node, seconds: float) -> int:
	var start: Vector2i = game.player.cell
	for i in int(seconds * 60.0):
		game._process(1.0 / 60.0)
		await process_frame
	var now: Vector2i = game.player.cell
	return absi(now.x - start.x) + absi(now.y - start.y)

func open_board(game: Node) -> void:
	game._new_round()
	game.set_process(false)
	for cell in game.terrain.keys():
		if cell.y == 5 and cell.x > 0 and cell.x < 14:
			game.terrain[cell].queue_free()
			game.terrain.erase(cell)
	for cell in game.crates.keys():
		game.crates[cell].queue_free()
	game.crates.clear()
	game.player.cell = Vector2i(2, 5)
	for i in range(1, 4):
		game.fighters[i].cell = Vector2i(12, 1 + i * 2)

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._select_level(0)
	for mounted in [false, true]:
		open_board(game)
		game.battle_items.mounted = mounted
		key(KEY_RIGHT, true)
		var moved: int = await play(game, 0.15)
		key(KEY_RIGHT, false)
		moved += await play(game, 0.3)
		check(moved == 1, "A 0.15 s tap moves one cell (mounted=%s), moved %d" % [mounted, moved])
		key(KEY_RIGHT, true)
		var held: int = await play(game, 1.0)
		key(KEY_RIGHT, false)
		check(held >= 4, "Holding 1 s keeps walking (mounted=%s), moved %d" % [mounted, held])
	if not failed:
		print("MOVEMENT_TAP_OK")
	quit(1 if failed else 0)
