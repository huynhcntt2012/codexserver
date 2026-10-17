extends SceneTree
## Exercise account forms against the real API, database and arena.

var scene = preload("res://main.tscn").instantiate()
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
	_check(root.get_texture().get_image().save_png(directory.path_join(name + ".png")) == OK, "Screenshot failed")


func _settle() -> void:
	while scene.net.busy:
		await process_frame
	await process_frame


func _run() -> void:
	root.add_child(scene)
	var timeout := create_timer(55)
	timeout.timeout.connect(func():
		push_error("Account UI test timed out")
		quit(1)
	)
	var api := OS.get_environment("SUNI_API_URL")
	var arena := OS.get_environment("SUNI_ARENA_URL")
	scene.api_input.text = "http://127.0.0.1:8000" if api.is_empty() else api
	arena = "http://127.0.0.1:2567" if arena.is_empty() else arena
	scene.arena_input.text = arena
	var username := "ui_" + Crypto.new().generate_random_bytes(8).hex_encode()
	var password := "test-only-" + Crypto.new().generate_random_bytes(12).hex_encode()
	scene.register_button.pressed.emit()
	_check(scene.confirm_input.visible and scene.password_input.secret and scene.confirm_input.secret, "Registration must show masked password confirmation")
	await _capture("account-register")
	scene.username_input.text = "Invalid Name"
	scene.password_input.text = password
	scene.confirm_input.text = password
	scene._join()
	_check(not scene.net.busy and "tài khoản" in scene.status_label.text, "Invalid username must fail locally")
	scene.username_input.text = username
	scene.confirm_input.text = "different-password"
	scene._join()
	_check(not scene.net.busy and "chưa khớp" in scene.status_label.text, "Confirmation mismatch must fail locally")
	scene.confirm_input.text = password
	# Successful registration with unavailable arena must preserve the new session.
	scene.arena_input.text = "http://127.0.0.1:1"
	scene._join()
	await _settle()
	_check(not scene.net.connected and scene.net.has_account_session(scene.api_input.text, username), "Arena failure must preserve registered account")
	_check(not scene.register_mode, "Registration retry must not create another account")
	_check(scene.password_input.text.is_empty() and scene.confirm_input.text.is_empty(), "Submitting must clear password controls")
	_check(not scene.net.has_account_session("http://different-server:8000", username), "Session must be bound to API URL")
	scene.arena_input.text = arena
	scene._join()
	await _settle()
	_check(scene.room_browser.visible and not scene.net.connected, "Authentication opens room picker")
	scene._enter_room("", true)
	await _settle()
	_check(scene.net.connected, "Registered account must join arena with retained session")
	while scene.snapshot.get("players", []).is_empty() and scene.net.connected:
		await process_frame
	var found_name := false
	for player in scene.snapshot.get("players", []):
		if player.id == scene.net.session_id and player.name == username:
			found_name = true
	_check(found_name, "Arena must use the authenticated account name")
	scene._leave()
	await _settle()
	_check(scene.net.has_account_session(scene.api_input.text, username), "Leaving room must preserve account session")
	await _capture("account-session")
	scene.logout_button.pressed.emit()
	_check(scene.net.account_name.is_empty() and not scene.net.has_account_session(scene.api_input.text, username), "Logout must erase session")
	scene.password_input.text = "incorrect-password"
	scene._join()
	await _settle()
	_check(not scene.net.connected and "401" in scene.status_label.text, "Incorrect password must be rejected")
	await _capture("account-login-error")
	scene.password_input.text = password
	scene.password_input.text_submitted.emit(password)
	await _settle()
	_check(scene.room_browser.visible and not scene.net.connected, "Authentication opens room picker")
	scene._enter_room("", true)
	await _settle()
	_check(scene.net.connected and scene.net.account_name == username, "Enter must log into the registered account")
	scene._leave()
	await _settle()
	scene.logout_button.pressed.emit()
	scene.register_button.pressed.emit()
	scene.password_input.text = password
	scene.confirm_input.text = password
	scene._join()
	await _settle()
	_check(not scene.net.connected and "409" in scene.status_label.text, "Duplicate account must be rejected clearly")
	scene.login_button.pressed.emit()
	scene.password_input.text = password
	scene._join()
	await _settle()
	_check(scene.room_browser.visible and not scene.net.connected, "Authentication opens room picker")
	scene._enter_room("", true)
	await _settle()
	_check(scene.net.connected, "Login must recover after duplicate registration")
	scene._leave()
	await _settle()
	scene.net._token_deadline = 0
	scene._join()
	_check(not scene.net.busy and "Mật khẩu" in scene.status_label.text, "Expired session must require password")
	scene.net.logout()
	scene.queue_free()
	await process_frame
	if not failed:
		print("GODOT_ACCOUNTS_OK: validation, register, arena retry, session, logout, login, duplicate, expiry")
	quit(1 if failed else 0)
