extends SceneTree
## Starts two actual Godot adapters, authenticates via API, joins a room,
## moves, places a bomb, observes death and server winner. Run against Compose.

const Network = preload("res://scripts/network.gd")
var first = Network.new()
var second = Network.new()
var stage := 0
var saw_bomb := false
var timeout_timer: Timer


func _initialize() -> void:
	root.add_child.call_deferred(first)
	root.add_child.call_deferred(second)
	first.snapshot_received.connect(_snapshot)
	_start.call_deferred()


func _start() -> void:
	timeout_timer = Timer.new()
	timeout_timer.one_shot = true
	timeout_timer.timeout.connect(func():
		push_error("Godot multiplayer smoke timed out at stage %d" % stage)
		quit(1)
	)
	root.add_child(timeout_timer)
	timeout_timer.start(20)
	var api := OS.get_environment("SUNI_API_URL")
	var arena := OS.get_environment("SUNI_ARENA_URL")
	if api.is_empty():
		api = "http://127.0.0.1:8000"
	if arena.is_empty():
		arena = "http://127.0.0.1:2567"
	first.join_game(api, arena)
	while not first.connected:
		await process_frame
	second.join_game(api, arena)


func _snapshot(state: Dictionary) -> void:
	if stage == 0 and state.players.size() == 2 and second.connected:
		first.send_action("ready")
		second.send_action("ready")
		stage = 1
	elif stage == 1 and state.phase == "playing":
		first.send_action("right")
		stage = 2
	elif stage == 2:
		for player in state.players:
			if player.id == first.session_id and player.x == 2:
				first.send_action("bomb")
				stage = 3
	elif stage == 3:
		if state.bombs.size() == 1:
			saw_bomb = true
		if state.phase == "finished":
			if not saw_bomb or state.winner != second.session_id:
				push_error("Wrong authoritative match result")
				quit(1)
				return
			print("GODOT_MULTIPLAYER_SMOKE_OK: auth, join, move, bomb, winner")
			first.disconnect_game()
			second.disconnect_game()
			stage = 4
			timeout_timer.stop()
			_finish.call_deferred()


func _finish() -> void:
	first.queue_free()
	second.queue_free()
	timeout_timer.queue_free()
	await process_frame
	quit(0)
