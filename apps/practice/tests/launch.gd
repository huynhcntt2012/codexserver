extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/ui/launch/launch_screen.tscn")
	change_scene_to_file("res://scenes/ui/launch/launch_screen.tscn")
	await process_frame
	await process_frame
	var launch = current_scene
	assert(launch.auth_panel.password_field.secret)
	launch.auth_panel.get_node("Login").pressed.emit()
	assert(launch.info_dialog.visible)
	launch.info_dialog.hide_dialog()
	launch.mode_selector.select_mode("duo")
	launch.auth_panel.get_node("Guest").pressed.emit()
	assert(launch.info_dialog.visible)
	assert(current_scene == launch)
	launch.info_dialog.hide_dialog()
	launch.get_node("CanvasRoot/ShopEquipment").pressed.emit()
	await process_frame
	await process_frame
	assert(current_scene.scene_file_path == "res://scenes/ui/ui_showcase.tscn")
	current_scene.open_page("home")
	await process_frame
	await process_frame
	assert(current_scene.scene_file_path == "res://scenes/ui/launch/launch_screen.tscn")
	current_scene.auth_panel.get_node("Guest").pressed.emit()
	await process_frame
	await process_frame
	assert(current_scene.scene_file_path == "res://scenes/main.tscn")
	print("PRACTICE_LAUNCH_OK: startup, validation, unsupported duo, shop, home, guest")
	if current_scene.music_enabled:
		current_scene._toggle_audio()
	current_scene.queue_free()
	await create_timer(0.15).timeout
	quit()
