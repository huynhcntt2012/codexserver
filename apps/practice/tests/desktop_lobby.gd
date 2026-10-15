extends SceneTree
var failed := false

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func run() -> void:
	create_timer(40).timeout.connect(func(): quit(1))
	change_scene_to_file("res://scenes/ui/launch/launch_screen.tscn")
	await process_frame
	await process_frame
	current_scene._on_guest()
	await process_frame
	await process_frame
	var game = current_scene
	var lobby = game.menu.get_node("DesktopMainLobby")
	check(lobby.is_visible_in_tree(), "Guest opens desktop lobby")
	lobby.hero_buttons[1].pressed.emit()
	check(game.selected_hero == 1, "Character selection reaches gameplay")
	lobby.map_buttons[2].pressed.emit()
	check(game.selected_level == 2, "Map selection reaches gameplay")
	lobby.search.text = "Băng"
	lobby.search.text_changed.emit("Băng")
	check(not lobby.map_buttons[1].disabled and lobby.map_buttons[0].disabled, "Map search")
	lobby.search.clear()
	lobby.refresh()
	if not OS.get_environment("SUNI_CAPTURE_DIR").is_empty():
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(OS.get_environment("SUNI_CAPTURE_DIR") + "/practice-main-lobby.png") == OK, "Screenshot saved")
	lobby.start()
	check(game.game_state == "playing" and not game.menu.visible, "Quick play starts game")
	check(game.fighters.size() == 4, "Player and three bots")
	game._show_menu()
	check(lobby.is_visible_in_tree(), "Return to lobby")
	lobby.open_shop("equipment")
	await process_frame
	await process_frame
	check(current_scene.equipment.visible, "Equipment tab opens directly")
	current_scene.open_page("home")
	await process_frame
	await process_frame
	check(current_scene.menu.has_node("DesktopMainLobby"), "Shop home returns to lobby")
	current_scene.menu.get_node("DesktopMainLobby").leave()
	await process_frame
	await process_frame
	check(current_scene.scene_file_path.ends_with("launch_screen.tscn"), "Logout returns to launch")
	print("PRACTICE_DESKTOP_LOBBY_OK" if not failed else "PRACTICE_DESKTOP_LOBBY_FAILED")
	quit(1 if failed else 0)
