extends SceneTree
## Optional graphical smoke/PR screenshot. Requires a display (or xvfb-run).

const Network = preload("res://scripts/network.gd")
var scene = preload("res://main.tscn").instantiate()
var second = Network.new()
var stage := 0


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	root.add_child(scene)
	root.add_child(second)
	scene.net.snapshot_received.connect(_snapshot)
	var timeout := Timer.new()
	timeout.one_shot = true
	timeout.timeout.connect(func(): quit(1))
	root.add_child(timeout)
	timeout.start(30)
	scene._join()
	while not scene.net.connected:
		await process_frame
	second.join_game(scene.api_input.text, scene.arena_input.text)


func _snapshot(value: Dictionary) -> void:
	if stage == 0 and value.players.size() == 2 and second.connected:
		scene.net.send_action("ready")
		second.send_action("ready")
		stage = 1
	elif stage == 1 and value.phase == "playing":
		scene.net.send_action("bomb")
		stage = 2
	elif stage == 2 and value.bombs.size() == 1:
		stage = 3
		_capture.call_deferred()


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("SUNI_SCREENSHOT")
	if output.is_empty():
		output = "res://build/gameplay.png"
	var error := root.get_texture().get_image().save_png(output)
	scene.net.disconnect_game()
	second.disconnect_game()
	scene.queue_free()
	second.queue_free()
	await process_frame
	quit(0 if error == OK else 1)
