extends SceneTree
## Real UI flow: guest selection, lobby, ready, round result, leave and rejoin.
## Set SUNI_CAPTURE_DIR with a graphical display to capture review screenshots.

const Network = preload("res://scripts/network.gd")
var scene = preload("res://main.tscn").instantiate()
var second = Network.new()
var failed := false


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _capture(name: String) -> void:
	var directory := OS.get_environment("SUNI_CAPTURE_DIR")
	if directory.is_empty():
		return
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(directory.path_join(name + ".png"))
	_check(error == OK, "Could not capture " + name)


func _run() -> void:
	root.add_child(scene)
	root.add_child(second)
	var timeout := Timer.new()
	timeout.one_shot = true
	timeout.timeout.connect(func():
		push_error("Lobby UI test timed out")
		quit(1)
	)
	root.add_child(timeout)
	timeout.start(35)
	var api := OS.get_environment("SUNI_API_URL")
	var arena := OS.get_environment("SUNI_ARENA_URL")
	scene.api_input.text = "http://127.0.0.1:8000" if api.is_empty() else api
	scene.arena_input.text = "http://127.0.0.1:2567" if arena.is_empty() else arena
	_check(scene.form.visible and not scene.lobby.visible, "Home must display the join form")
	_check(scene.lobby_view.visible and not scene.arena_view.visible, "Home must display the pilot lounge")
	_check(not scene.username_input.visible, "Guest mode must hide account fields")
	await _capture("lobby-home")
	scene._set_login_mode(true)
	scene._join()
	_check(not scene.net.busy and not scene.net.connected, "Empty login must not silently create a guest")
	_check("tài khoản" in scene.status_label.text, "Login must explain the required account")
	await _capture("lobby-login")
	# Guest mode must ignore any username left over from the login tab.
	scene.username_input.text = "not_registered_ui_test"
	scene.password_input.text = "not-a-real-password"
	scene._set_login_mode(false)
	_check(scene.password_input.text.is_empty(), "Switching to guest must clear the password")
	scene._join()
	while scene.net.busy:
		await process_frame
	_check(scene.room_browser.visible, "Room picker must open")
	scene._enter_room("", true)
	while not scene.net.connected or scene.snapshot.get("players", []).size() != 1:
		await process_frame
	await process_frame
	_check(scene.lobby.visible and not scene.form.visible, "Joined clients must see the lobby")
	_check(scene.lobby_view.visible and not scene.overlay.visible, "Waiting room must show unobscured pilot platforms")
	second.join_game(scene.api_input.text, scene.arena_input.text)
	while not second.connected or scene.snapshot.get("players", []).size() != 2:
		await process_frame
	await _capture("lobby-ready")
	scene.ready_button.pressed.emit()
	while not scene.ready_button.disabled:
		await process_frame
	_check("Đã sẵn sàng" in scene.ready_button.text, "Local readiness must be visible")
	second.send_action("ready")
	while scene.snapshot.get("phase") != "countdown":
		await process_frame
	_check(scene.overlay.visible, "Countdown must be visible")
	_check(scene.arena_view.visible and not scene.lobby_view.visible, "Countdown must reveal the arena")
	await _capture("lobby-countdown")
	while scene.snapshot.get("phase") != "playing":
		await process_frame
	_check(not scene.overlay.visible, "Gameplay must not be obscured by the overlay")
	scene.net.send_action("bomb")
	while scene.snapshot.get("bombs", []).is_empty():
		await process_frame
	await _capture("gameplay")
	while scene.snapshot.get("flames", []).is_empty():
		await process_frame
	await _capture("gameplay-flames")
	while scene.snapshot.get("phase") != "finished":
		await process_frame
	_check(scene.overlay.visible and scene.snapshot.winner == second.session_id, "Result must reflect the server winner")
	await _capture("lobby-result")
	while scene.snapshot.get("phase") != "waiting":
		await process_frame
	_check(scene.lobby_view.visible and not scene.overlay.visible, "Next round must return to the lounge")
	_check(scene.arena_view.sparks.is_empty() and scene.arena_view.rings.is_empty(), "New rounds must clear transient effects")
	_check(not scene.ready_button.disabled, "Players must be able to ready for the next round")
	scene._leave()
	while scene.net.busy:
		await process_frame
	_check(not scene.net.connected and scene.snapshot.is_empty(), "Leave must clear match state")
	_check(scene.form.visible and scene.arena_view.snapshot.is_empty(), "Leave must restore the preview and form")
	_check(scene.lobby_view.visible and scene.arena_view.sparks.is_empty(), "Leave must restore the lounge and clear effects")
	second.disconnect_game()
	scene._join()
	while scene.net.busy:
		await process_frame
	_check(scene.room_browser.visible, "Room picker must open")
	scene._enter_room("", true)
	while not scene.net.connected:
		await process_frame
	scene._leave()
	while scene.net.busy:
		await process_frame
	timeout.stop()
	scene.queue_free()
	second.queue_free()
	timeout.queue_free()
	await process_frame
	if not failed:
		print("GODOT_LOBBY_UI_OK: guest, login guard, ready, countdown, result, next round, leave, rejoin")
	quit(1 if failed else 0)
