extends SceneTree
var account: Node
var user_name := "pc_" + Crypto.new().generate_random_bytes(7).hex_encode()
var password := "verify-" + Crypto.new().generate_random_bytes(12).hex_encode()

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		push_error(message)
		quit(1)

func launch() -> void:
	change_scene_to_file("res://scenes/ui/launch/launch_screen.tscn")
	await process_frame
	await process_frame

func settle() -> void:
	while account.busy:
		await process_frame
	await process_frame
	await process_frame

func _run() -> void:
	create_timer(55).timeout.connect(func(): push_error("Auth test timed out"); quit(1))
	account = root.get_node("AuthSession")
	account.api_url = "http://127.0.0.1:8000"
	await launch()
	var screen = current_scene
	screen._on_register()
	screen.auth_panel.username_field.text = user_name
	screen.auth_panel.password_field.text = password
	screen.auth_panel.confirm_field.text = "mismatch"
	screen.auth_panel._submit()
	check(not account.busy and screen.info_dialog.visible, "Confirmation mismatch must not call API")
	screen.info_dialog.hide_dialog()
	screen.auth_panel.confirm_field.text = password
	screen.auth_panel._submit()
	check(account.busy and screen.auth_panel.get_node("Login").disabled, "Submitting must disable form")
	await settle()
	check(account.has_session(), "Registration establishes account session")
	check(current_scene.scene_file_path == "res://scenes/main.tscn", "Successful auth opens game menu")
	check(current_scene.menu.has_node("DesktopMainLobby"), "Successful login displays new PC lobby")
	await launch()
	check(account.has_session(), "Session survives scene navigation")
	current_scene.get_node("CanvasRoot/Logout").pressed.emit()
	check(not account.has_session(), "Logout clears token")
	screen = current_scene
	screen.auth_panel.username_field.text = user_name
	screen.auth_panel.password_field.text = "incorrect-password"
	screen.auth_panel._submit()
	await settle()
	check(current_scene == screen and not account.has_session() and screen.info_dialog.visible, "Wrong credentials stay on Launch")
	check(screen.auth_panel.password_field.text.is_empty(), "Password cleared after response")
	screen.info_dialog.hide_dialog()
	screen.auth_panel.password_field.text = password
	screen.auth_panel._submit()
	await settle()
	check(account.has_session() and current_scene.scene_file_path == "res://scenes/main.tscn", "Existing account login succeeds")
	await launch()
	account._deadline = 0
	check(not account.has_session(), "Expired token removed")
	account.api_url = "http://127.0.0.1:1"
	screen = current_scene
	screen.auth_panel.username_field.text = user_name
	screen.auth_panel.password_field.text = password
	screen.auth_panel._submit()
	await settle()
	check(not account.has_session() and current_scene == screen and not screen.auth_panel.get_node("Login").disabled, "Connection failure allows retry")
	check(not account.configure("http://example.com"), "Remote HTTP credentials forbidden")
	# Restore the local test endpoint, never persist secrets.
	account.configure("http://127.0.0.1:8000")
	print("PRACTICE_AUTH_OK: register, busy state, navigation, logout, wrong password, login, expiry, connection failure")
	current_scene.queue_free()
	await create_timer(0.15).timeout
	quit()
