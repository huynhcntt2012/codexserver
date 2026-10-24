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
	check(lobby.map_cards.size() == lobby.PAGE_SIZE and lobby.maps.size() == game.LEVEL_FILES.size(), "Eight map slots; maps come from level files")
	var arena_for: Callable = root.get_node("OnlineArena").arena_for
	check(arena_for.call("https://api.sunifactory.com") == "https://arena.sunifactory.com" and arena_for.call("http://127.0.0.1:8081/api/") == "http://127.0.0.1:8081/arena" and arena_for.call("http://127.0.0.1:8000") == "http://127.0.0.1:2567", "Arena URL follows the API URL")
	check(lobby.fold("LÂU ĐÀI Băng") == "lau dai bang", "Vietnamese text folds without diacritics")
	check(lobby.rooms_state == "signed_out" or lobby.rooms.is_empty(), "Guest has no online rooms")
	await process_frame
	lobby.refresh()
	# The map list is always there, even for a guest with no rooms.
	check(not lobby.empty.visible and lobby.map_cards[0].holder.visible and lobby.map_cards[0].art.texture != null and lobby.summary.text.contains("Đăng nhập"), "Guest sees the map list and is asked to sign in for online play")
	var bar_text := ""
	for label in lobby.find_children("*", "Label", true, false):
		bar_text += (label as Label).text + "|"
	check(not bar_text.contains("bot"), "No bot wording on the lobby list")
	check(lobby.search.placeholder_text == "Tìm bản đồ…" and lobby.open_toggle.get_parent() == lobby.tier_select.get_parent() and lobby.friends_toggle.get_parent() == lobby.tier_select.get_parent(), "Filter bar: selects, two checkboxes and search")
	check(lobby.visible_maps().size() == 15 and lobby.page_label.text == "1 / 2" and lobby.prev_page.disabled and not lobby.next_page.disabled, "15 maps span two pages")
	# Live rooms in the v2 shape: park has an open room with a friend, frost a full one,
	# coast a playing one.
	lobby.friend_ids = ["friend"]
	lobby.apply_rooms({"ok": true, "rooms": [
		{"roomId": "r1", "number": 1, "map": "park", "phase": "waiting", "players": 3, "maxPlayers": 8, "joinable": true, "accountIds": ["friend"]},
		{"roomId": "r2", "number": 2, "map": "park", "phase": "waiting", "players": 1, "maxPlayers": 8, "joinable": true, "accountIds": ["x"]},
		{"roomId": "r3", "number": 3, "map": "frost", "phase": "waiting", "players": 8, "maxPlayers": 8, "joinable": false, "accountIds": []},
		{"roomId": "r4", "number": 4, "map": "coast", "phase": "playing", "players": 2, "maxPlayers": 8, "joinable": false, "accountIds": []},
	]})
	var first: Dictionary = lobby.map_cards[0]
	check(first.number.text == "001" and first.title.text == "Công Viên Kẹo" and first.count.text == "4 người · 2 phòng" and first.button.text == "Vào" and not first.button.disabled, "Map card: number, name, people and rooms, Vào")
	check(lobby.map_stats("park").join.roomId == "r1", "Vào prefers the friend's open room")
	check(lobby.map_stats("frost").join.is_empty() and lobby.map_cards[1].button.text == "Vào", "A map with only full rooms still offers Vào (opens a new room)")
	check(lobby.map_cards[3].count.text == "Chưa có phòng", "Maps without rooms say so")
	check(lobby.summary.text.begins_with("15/15 bản đồ · 4 phòng đang mở · 14 người"), "Summary counts maps, rooms and people")
	lobby.next_page.pressed.emit()
	check(lobby.page_label.text == "2 / 2" and lobby.map_cards[6].holder.visible and not lobby.map_cards[7].holder.visible, "Second page holds the last seven maps")
	lobby.open_toggle.button_pressed = true
	check(lobby.visible_maps() == [0] and lobby.page_label.text == "1 / 1", "Chỉ phòng trống keeps maps with an open room")
	lobby.open_toggle.button_pressed = false
	lobby.friends_toggle.button_pressed = true
	check(lobby.visible_maps() == [0], "Chỉ bạn bè keeps maps where a friend plays")
	lobby.friends_toggle.button_pressed = false
	lobby.search.text = "Băng"
	lobby.search.text_changed.emit("Băng")
	check(lobby.visible_maps() == [1], "Search by map name ignores diacritics")
	lobby.search.text = "015"
	lobby.search.text_changed.emit("015")
	check(lobby.visible_maps() == [14], "Search by map number")
	lobby.search.clear()
	check(lobby.tier_select.item_count == 4, "All plus one entry per difficulty")
	lobby.tier_select.select(3)
	lobby.tier_select.item_selected.emit(3)
	check(lobby.tier_filter == "Khó" and lobby.visible_maps().all(func(i): return lobby.maps[i].tier == "Khó"), "Difficulty filter")
	lobby.set_tier("")
	check(lobby.map_select.item_count == lobby.maps.size() + 1, "Map dropdown lists every map")
	lobby.map_select.select(2)
	lobby.map_select.item_selected.emit(2)
	check(lobby.visible_maps() == [1], "Map dropdown filters one map")
	lobby.set_map(-1)
	lobby.search.text = "khong co ban do nay"
	lobby.search.text_changed.emit(lobby.search.text)
	check(lobby.visible_maps().is_empty() and lobby.empty.visible and lobby.empty.text.begins_with("Không có bản đồ"), "No match is announced")
	lobby.search.clear()
	lobby.apply_rooms({"ok": true, "rooms": []})
	check(not lobby.empty.visible and lobby.map_cards[0].count.text == "Chưa có phòng", "No rooms: maps stay listed, rooms open on demand")
	lobby.map_cards[0].button.pressed.emit()
	check(lobby.modal.visible and lobby.modal_message.text.begins_with("Đăng nhập"), "Guest Vào asks to sign in")
	lobby.close_modal()
	lobby.open_create()
	check(lobby.modal.visible and lobby.modal_message.text.begins_with("Đăng nhập"), "Guest cannot create an online room")
	lobby.close_modal()
	lobby.nav_tabs[lobby.NAV_MISSIONS].button.pressed.emit()
	await process_frame
	var missions = lobby.store_pages.missions
	check(lobby.store.visible and missions.visible and lobby.store_title.text == "NHIỆM VỤ & SỰ KIỆN" and lobby.nav_index == lobby.NAV_MISSIONS, "Nhiệm vụ opens the mission window")
	check(missions.state == "signed_out" and missions.list.get_child_count() == 1 and not lobby.mission_dot.visible, "Guest is asked to sign in for missions")
	check(missions.countdown(90061) == "1 ngày 1 giờ" and missions.parse_time("2026-10-17T00:00:00+07:00") == missions.parse_time("2026-10-16T17:00:00+00:00"), "Countdown and server time parsing")
	lobby.close_store()
	var quit_button = lobby.find_child("QuitGame", true, false)
	check(quit_button != null and quit_button.get_global_rect().end.x > lobby.top_bar.get_global_rect().end.x - 120 and quit_button.get_index() == quit_button.get_parent().get_child_count() - 1, "X button sits at the top right, after settings")
	check(not lobby.top_bar.find_children("*", "Glyph", true, false).any(func(g): return g.kind == "people"), "No friends button in the top bar")
	quit_button.pressed.emit()
	check(lobby.modal.visible and lobby.modal_title.text == "THOÁT GAME" and lobby.modal_extra.visible and lobby.modal_extra.text == "THOÁT" and lobby.modal_ok.text == "Ở LẠI" and lobby.modal_ok.has_focus(), "X asks to confirm, Ở LẠI focused")
	lobby.modal_ok.pressed.emit()
	check(not lobby.modal.visible and current_scene == game, "Ở LẠI keeps the game open")
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
	check(lobby.modal.visible and lobby.modal_title.text == "HỘP THƯ" and lobby.modal_message.text == "Hộp thư trống.", "Notice uses in-game modal")
	lobby.modal_ok.pressed.emit()
	check(not lobby.modal.visible, "Notice closes")
	lobby.open_settings()
	check(lobby.store.visible and lobby.store_pages.settings.visible and lobby.store_title.text == "CÀI ĐẶT", "Gear opens the settings window")
	lobby.close_store()
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
	# Opening a page for the first time from another open popup still loads it.
	if lobby.store_pages.has("missions"):
		lobby.store_pages.missions.free()
		lobby.store_pages.erase("missions")
	lobby.open_shop("missions")
	await process_frame
	await process_frame
	check(lobby.store_pages.missions.state != "idle", "Missions load when opened from another popup")
	lobby.close_store()
	check(not lobby.store.visible and lobby.nav_index == lobby.NAV_HOME, "Closing the popup returns to the lobby")
	lobby.leave()
	await process_frame
	await process_frame
	check(current_scene.scene_file_path.ends_with("launch_screen.tscn"), "Logout returns to launch")
	print("PRACTICE_DESKTOP_LOBBY_OK" if not failed else "PRACTICE_DESKTOP_LOBBY_FAILED")
	quit(1 if failed else 0)
