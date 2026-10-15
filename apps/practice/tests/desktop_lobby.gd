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
	check(lobby.maps.size() == game.LEVEL_FILES.size() and lobby.map_cards.size() == lobby.maps.size(), "Map cards come from level files")
	check(lobby.fold("LÂU ĐÀI Băng") == "lau dai bang", "Vietnamese text folds without diacritics")
	lobby.search.text = "Băng"
	lobby.search.text_changed.emit("Băng")
	check(lobby.map_cards[1].visible and not lobby.map_cards[0].visible and not lobby.map_cards[2].visible, "Map search hides other maps")
	lobby.search.text = "dao nang"
	lobby.search.text_changed.emit("dao nang")
	check(lobby.visible_maps() == [2], "Search ignores diacritics and needs every word")
	lobby.search.text_submitted.emit("dao nang")
	check(game.selected_level == 2, "Enter selects first matching map")
	lobby.search.text = "khong co map nay"
	lobby.search.text_changed.emit(lobby.search.text)
	check(lobby.visible_maps().is_empty() and lobby.empty.visible and lobby.summary.text.begins_with("0/3"), "Empty search result is announced")
	lobby.search.clear()
	check(lobby.tier_select.item_count == 4, "All plus one entry per difficulty")
	lobby.tier_select.select(3)
	lobby.tier_select.item_selected.emit(3)
	check(lobby.tier_filter == "Khó" and lobby.visible_maps() == [2], "Difficulty filter")
	lobby.search.text = "bang"
	lobby.search.text_changed.emit("bang")
	check(lobby.visible_maps().is_empty(), "Search and difficulty combine")
	lobby.search.clear()
	lobby.set_tier("")
	check(lobby.map_select.item_count == lobby.maps.size() + 1, "Map dropdown lists every map")
	lobby.map_select.select(2)
	lobby.map_select.item_selected.emit(2)
	check(lobby.visible_maps() == [1] and lobby.map_cards[1].visible and not lobby.map_cards[0].visible, "Map dropdown filters one map")
	lobby.set_map(-1)
	check(lobby.visible_maps() == [0, 1, 2] and not lobby.empty.visible, "Clearing filters restores every map")
	check(lobby.page_label.text == "TRANG 1 / 1" and lobby.prev_page.disabled and lobby.next_page.disabled, "Pagination for three maps")
	check(lobby.grouped(12560) == "12.560", "Wallet uses dot grouping")
	check(root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND, "Lobby fills the screen")
	lobby.show_social(1)
	check(lobby.friend_list.is_visible_in_tree() and not lobby.hero_list.is_visible_in_tree(), "Friends tab shows empty state")
	lobby.show_social(0)
	check(lobby.hero_list.get_parent().get_parent() == lobby.hero_scroll and lobby.hero_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "Character list scrolls")
	check(lobby.friend_list.get_parent().get_parent() == lobby.friend_scroll, "Friend list scrolls")
	lobby.notice("Hộp thư trống.", "HỘP THƯ", "mail")
	check(lobby.modal.visible and lobby.modal_title.text == "HỘP THƯ" and lobby.modal_message.text == "Hộp thư trống." and not lobby.modal_settings.visible, "Notice uses in-game modal")
	lobby.modal_ok.pressed.emit()
	check(not lobby.modal.visible, "Notice closes")
	lobby.open_settings()
	check(lobby.modal.visible and lobby.modal_settings.visible and lobby.audio_toggle.text == ("BẬT" if game.music_enabled else "TẮT"), "Settings modal shows game toggles")
	var audio_before: bool = game.music_enabled
	lobby.audio_toggle.button_pressed = not audio_before
	check(game.music_enabled != audio_before and lobby.audio_toggle.text == ("BẬT" if game.music_enabled else "TẮT"), "Audio toggle works")
	lobby.audio_toggle.button_pressed = audio_before
	lobby.close_modal()
	if not OS.get_environment("SUNI_CAPTURE_DIR").is_empty():
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(OS.get_environment("SUNI_CAPTURE_DIR") + "/practice-main-lobby.png") == OK, "Screenshot saved")
	lobby.start()
	check(game.game_state == "playing" and not game.menu.visible, "Quick play starts game")
	await process_frame
	check(root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_KEEP, "Arena keeps its fixed frame")
	check(game.fighters.size() == 4, "Player and three bots")
	game._show_menu()
	check(lobby.is_visible_in_tree(), "Return to lobby")
	await process_frame
	check(root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND, "Lobby fills again")
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
