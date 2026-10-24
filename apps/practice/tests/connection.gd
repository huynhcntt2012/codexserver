extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	create_timer(30).timeout.connect(func(): push_error("Connection test timeout"); quit(1))
	change_scene_to_file("res://scenes/ui/launch/launch_screen.tscn")
	await process_frame
	await process_frame
	var settings = current_scene.settings_dialog
	settings.open()
	assert(settings.api_field.is_visible_in_tree())
	assert(settings.get_node("Card").get_rect().encloses(settings.api_field.get_rect()))
	settings.public_button.pressed.emit()
	assert(settings.api_field.text == "https://api.sunifactory.com")
	settings._check()
	assert(settings.check_button.disabled and not settings.api_field.editable)
	while settings.checking:
		await process_frame
	assert("thành công" in settings.connection_status.text)
	assert(not settings.check_button.disabled)
	var auth = root.get_node("AuthSession")
	assert("máy PC" in auth.connection_error(HTTPRequest.RESULT_TIMEOUT, "http://127.0.0.1:8000"))
	print("PRACTICE_CONNECTION_OK: visible API, public preset, live Godot HTTPS health, actionable local timeout")
	current_scene.queue_free()
	await process_frame
	quit()
