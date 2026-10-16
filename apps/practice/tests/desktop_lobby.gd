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
	check(lobby.room_cards.size() == lobby.PAGE_SIZE and lobby.maps.size() == game.LEVEL_FILES.size(), "Eight room slots; maps come from level files")
	var arena_for: Callable = root.get_node("OnlineArena").arena_for
	check(arena_for.call("https://api.sunifactory.com") == "https://arena.sunifactory.com" and arena_for.call("http://127.0.0.1:8081/api/") == "http://127.0.0.1:8081/arena" and arena_for.call("http://127.0.0.1:8000") == "http://127.0.0.1:2567", "Arena URL follows the API URL")
	check(lobby.fold("LÂU ĐÀI Băng") == "lau dai bang", "Vietnamese text folds without diacritics")
	check(lobby.rooms_state == "signed_out" or lobby.rooms.is_empty(), "Guest has no online rooms")
	await process_frame
	lobby.refresh()
	check(lobby.empty.visible and lobby.empty.text.begins_with("Đăng nhập"), "Guest is asked to sign in for online rooms")
	var bar_text := ""
	for label in lobby.find_children("*", "Label", true, false):
		bar_text += (label as Label).text + "|"
	check(not bar_text.contains("bot"), "No bot wording on the online room list")
	check(lobby.search.placeholder_text == "Tìm phòng…" and lobby.open_toggle.get_parent() == lobby.tier_select.get_parent() and lobby.friends_toggle.get_parent() == lobby.tier_select.get_parent(), "Filter bar: selects, two checkboxes and search")
	# Ten fake listings in the v2 shape: 2 pages, one full room, one playing, one with a friend.
	var fake := []
	for i in 10:
		fake.append({"roomId": "r%d" % i, "number": i + 1, "map": ["park", "frost", "coast"][i % 3], "phase": "waiting", "players": 3, "maxPlayers": 8, "joinable": true, "accountIds": ["acc%d" % i]})
	fake[1].players = 8
	fake[1].joinable = false
	fake[2].phase = "playing"
	fake[2].joinable = false
	lobby.friend_ids = ["acc4"]
	lobby.apply_rooms({"ok": true, "rooms": fake})
	check(lobby.visible_rooms().size() == 10 and lobby.page_label.text == "1 / 2" and lobby.prev_page.disabled and not lobby.next_page.disabled, "Ten rooms span two pages")
	var first: Dictionary = lobby.room_cards[0]
	check(first.holder.visible and first.number.text == "001" and first.title.text == "Công Viên Kẹo" and first.count.text == "3/8" and first.button.text == "Vào" and not first.button.disabled, "Open room card: number, map, x/8, Vào")
	check(lobby.room_cards[1].button.text == "Đầy" and lobby.room_cards[1].button.disabled and lobby.room_cards[1].count.text == "8/8", "Full room shows Đầy, disabled")
	check(lobby.room_cards[2].button.text == "Đang chơi" and lobby.room_cards[2].button.disabled, "Playing room cannot be joined")
	lobby.next_page.pressed.emit()
	check(lobby.page_label.text == "2 / 2" and lobby.room_cards[0].holder.visible and lobby.room_cards[1].holder.visible and not lobby.room_cards[2].holder.visible, "Second page holds the last two rooms")
	lobby.open_toggle.button_pressed = true
	check(lobby.visible_rooms().size() == 8 and lobby.page_label.text == "1 / 1", "Chỉ phòng trống hides full and playing rooms")
	lobby.friends_toggle.button_pressed = true
	check(lobby.visible_rooms().size() == 1 and lobby.visible_rooms()[0].roomId == "r4", "Chỉ bạn bè keeps rooms with a friend")
	lobby.open_toggle.button_pressed = false
	lobby.friends_toggle.button_pressed = false
	lobby.search.text = "Băng"
	lobby.search.text_changed.emit("Băng")
	check(lobby.visible_rooms().all(func(r): return r.map == "frost") and lobby.visible_rooms().size() == 3, "Search by map name ignores diacritics")
	lobby.search.text = "007"
	lobby.search.text_changed.emit("007")
	check(lobby.visible_rooms().size() == 1 and lobby.visible_rooms()[0].number == 7, "Search by room number")
	lobby.search.clear()
	check(lobby.tier_select.item_count == 4, "All plus one entry per difficulty")
	lobby.tier_select.select(3)
	lobby.tier_select.item_selected.emit(3)
	check(lobby.tier_filter == "Khó" and lobby.visible_rooms().all(func(r): return r.map == "coast"), "Difficulty filter")
	lobby.set_tier("")
	check(lobby.map_select.item_count == lobby.maps.size() + 1, "Map dropdown lists every map")
	lobby.map_select.select(2)
	lobby.map_select.item_selected.emit(2)
	check(lobby.visible_rooms().all(func(r): return r.map == "frost"), "Map dropdown filters one map")
	lobby.set_map(-1)
	lobby.search.text = "khong co phong nay"
	lobby.search.text_changed.emit(lobby.search.text)
	check(lobby.visible_rooms().is_empty() and lobby.empty.visible and lobby.empty.text.begins_with("Không có phòng"), "No match is announced")
	lobby.search.clear()
	lobby.apply_rooms({"ok": true, "rooms": []})
	check(lobby.empty.visible and lobby.empty.text.contains("TẠO PHÒNG"), "Empty server list invites to create a room")
	lobby.open_create()
	check(lobby.modal.visible and lobby.modal_message.text.begins_with("Đăng nhập"), "Guest cannot create an online room")
	lobby.close_modal()
	check(lobby.grouped(12560) == "12.560", "Wallet uses dot grouping")
	check(root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND, "Lobby fills the screen")
	lobby.show_social(1)
	await process_frame
	check(lobby.friends_panel.is_visible_in_tree() and lobby.friends_panel.offline.visible and not lobby.hero_list.is_visible_in_tree(), "Guest friends tab asks to sign in")
	lobby.show_social(0)
	check(lobby.hero_list.get_parent().get_parent() == lobby.hero_scroll and lobby.hero_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "Character list scrolls")
	check(lobby.friends_panel.list.get_parent().get_parent() is ScrollContainer, "Friend list scrolls")
	lobby.chat.pick_channel("world")
	await process_frame
	check(lobby.chat.visible and not lobby.chat.input.editable and lobby.chat.input.placeholder_text.contains("Đăng nhập"), "Guest chat asks to sign in")
	check(lobby.chat.system_line.text.begins_with("[Hệ thống]"), "Chat log keeps the system line")
	lobby.chat.close()
	check(lobby.find_child("ProfileCard", true, false) != null and lobby.xp_percent.text.ends_with("%"), "Profile card shows level and XP percent")
	lobby.find_child("RenameButton", true, false).pressed.emit()
	check(lobby.modal.visible and lobby.name_input.visible and lobby.modal_extra.visible, "Pencil opens the rename popup")
	lobby.name_input.text = "x"
	lobby.save_name()
	check(lobby.modal.visible and lobby.modal_message.text.begins_with("Tên chưa hợp lệ"), "Too-short name is refused")
	lobby.name_input.text = "  Bụp   Khách  "
	lobby.save_name()
	await process_frame
	check(not lobby.modal.visible and lobby.profile.text == "Bụp Khách", "Guest nickname saved on this computer")
	var prefs := ConfigFile.new()
	prefs.load("user://launch_preferences.cfg")
	prefs.set_value("profile", "guest_name", "Khách")
	prefs.save("user://launch_preferences.cfg")
	lobby.refresh()
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
	lobby.practice()
	check(game.pc_screens["matchmaking"].is_visible_in_tree() and not lobby.is_visible_in_tree(), "Practice opens bot matchmaking")
	game.pc_screens["matchmaking"].clock = 99.0
	var room = game.pc_screens["room"]
	for i in 10:
		await process_frame
		if room.is_visible_in_tree():
			break
	check(room.is_visible_in_tree(), "Matchmaking opens the room")
	room.ready_clock = 99.0
	room.start()
	check(game.game_state == "playing" and not game.menu.visible, "Room start begins the game")
	await process_frame
	check(root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND, "Arena fills the screen")
	check(game.fighters.size() == 4, "Player and three bots")
	game._show_menu()
	check(lobby.is_visible_in_tree(), "Return to lobby")
	await process_frame
	check(root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND, "Lobby fills again")
	lobby.open_shop("equipment")
	await process_frame
	check(current_scene == game and lobby.store.visible and lobby.store_pages.equipment.visible and lobby.nav_index == lobby.NAV_EQUIPMENT, "PC equipment opens as a popup")
	lobby.close_store()
	check(not lobby.store.visible and lobby.nav_index == lobby.NAV_HOME, "Closing the popup returns to the lobby")
	lobby.leave()
	await process_frame
	await process_frame
	check(current_scene.scene_file_path.ends_with("launch_screen.tscn"), "Logout returns to launch")
	print("PRACTICE_DESKTOP_LOBBY_OK" if not failed else "PRACTICE_DESKTOP_LOBBY_FAILED")
	quit(1 if failed else 0)
