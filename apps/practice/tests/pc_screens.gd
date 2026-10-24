extends SceneTree
## PC flow after the lobby: matchmaking -> room -> battle HUD -> pause/result ->
## shop -> equipment. Set SUNI_CAPTURE_DIR to save screenshots (needs a display).
var failed := false
var capture_dir := OS.get_environment("SUNI_CAPTURE_DIR")

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func frames(count := 2) -> void:
	for i in count:
		await process_frame

func capture(file: String) -> void:
	if capture_dir.is_empty():
		return
	await frames(3)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(capture_dir + "/" + file) == OK, "Screenshot " + file)

func run() -> void:
	create_timer(60).timeout.connect(func(): quit(1))
	change_scene_to_file("res://scenes/main.tscn")
	await frames()
	var game = current_scene
	var ui = root.get_node("UIState")
	game.set_process(false)
	var lobby = game.pc_screens["lobby"]
	var matchmaking = game.pc_screens["matchmaking"]
	var room = game.pc_screens["room"]
	lobby.practice()
	await frames()
	check(matchmaking.is_visible_in_tree() and not lobby.is_visible_in_tree(), "Quick play opens matchmaking")
	check(root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND, "Matchmaking fills the screen")
	matchmaking.clock = 1.5
	matchmaking.refresh()
	check(matchmaking.seated() == 3 and matchmaking.found_label.text.begins_with("Đã có 3/4"), "Bots join one by one")
	await capture("pc-matchmaking.png")
	matchmaking.cancel_search()
	check(lobby.is_visible_in_tree() and not matchmaking.is_visible_in_tree(), "Cancel returns to lobby")
	lobby.practice()
	await frames()
	check(matchmaking.clock < 1.0, "Matchmaking restarts its clock")
	matchmaking.clock = 99.0
	await frames()
	check(room.is_visible_in_tree() and not matchmaking.is_visible_in_tree(), "Seated bots open the room")
	check(room.start_button.disabled and room.start_button.text.begins_with("CHỜ"), "Start waits for bots")
	check(room.ready_label.text.ends_with("0/3 người chơi") and not room.all_ready(), "Ready counter starts at 0/3")
	room.chat_input.text = "Chào cả phòng"
	room.send_chat()
	check(room.chat_lines.back().kind == "me" and room.chat_lines.back().text == "Chào cả phòng" and room.chat_input.text.is_empty(), "Room chat posts the player's line")
	room.start()
	check(game.game_state == "menu", "Room cannot start before bots are ready")
	var level_before: int = game.selected_level
	room.pick_map(1)
	check(game.selected_level == (level_before + 1) % game.LEVEL_FILES.size(), "Room map switch reaches gameplay")
	var hero_before: int = game.selected_hero
	room.pick_hero(1)
	check(game.selected_hero == (hero_before + 1) % game.HEROES.size(), "Room hero switch reaches gameplay")
	check(not game.bot_heroes().has(game.HEROES[game.selected_hero]) and game.bot_heroes().size() == 3, "Bots never copy the player's hero")
	room.ready_clock = 99.0
	room.refresh()
	check(not room.start_button.disabled and room.start_button.text == "BẮT ĐẦU", "Ready bots enable start")
	check(room.ready_label.text.ends_with("3/3 người chơi") and room.all_ready(), "Every seat ready")
	check(room.chat_lines.filter(func(l): return l.kind == "system" and str(l.text).ends_with("đã sẵn sàng.")).size() == 3, "Chat announces each ready bot once")
	room.chat_input.text = "Sẵn sàng chưa?"
	room.send_chat()
	await create_timer(1.6).timeout
	check(room.chat_lines.back().kind == "bot", "A ready bot answers in chat")
	check(room.cards[1].badge.text == "SẴN SÀNG", "Bot badge shows ready")
	await capture("pc-room.png")
	room.start()
	await frames()
	check(game.game_state == "playing" and game.hud.visible and not game.menu.visible, "Room start begins battle")
	check(root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND, "Arena fills the screen")
	var hud = game.hud.get_node("PcBattleHud")
	hud.refresh()
	await frames()
	var board: Rect2 = game.arena_layout
	var view: Vector2 = root.get_visible_rect().size
	check(board.size.x > 960.0 * 0.9 and board.end.x <= view.x and board.end.y <= view.y and is_equal_approx(board.size.x / board.size.y, 960.0 / 704.0), "Arena scales to fill the window")
	check(is_equal_approx(game.world.scale.x, board.size.x / 960.0) and game.world.position.is_equal_approx(board.position), "World follows the HUD layout")
	check(hud.find_child("Leave", true, false) != null, "Sidebar has THOÁT RA")
	check(hud.bots_label.text == "3" and hud.timer_label.text == "3:00" and hud.banner.visible, "HUD shows bots, timer and start banner")
	check(hud.players[0].name.text == game.HERO_NAMES[game.selected_hero].capitalize(), "HUD lists the player first")
	await capture("pc-battle.png")
	game._pause_game()
	var result = game.result.get_node("PcResult")
	check(game.game_state == "paused" and result.is_visible_in_tree() and result.title.text == "TẠM DỪNG", "Pause uses PC overlay")
	check(result.actions.get_child_count() == 3, "Pause offers lobby, restart and resume")
	game._resume_game()
	check(game.game_state == "playing" and not game.result.visible, "Resume hides overlay")
	for actor in game.fighters:
		if actor.bot:
			game._hit_fighter(actor, game.player)
	game._resolve_outcome()
	await frames()
	check(game.game_state == "ended" and game.last_won and result.title.text == "CHIẾN THẮNG!", "Victory result")
	check(int(game.player.kills) == 3, "Knockouts credited to bomb owner")
	check(result.rows.get_child_count() == 4, "Result lists four fighters")
	check(result.summary.text.contains("không cộng vàng/XP"), "Offline result grants no rewards")
	await capture("pc-result.png")
	var gold_before := int(ui.profile.gold)
	result.actions.get_child(1).pressed.emit()
	await frames()
	check(room.is_visible_in_tree() and game.game_state == "menu", "CHƠI TIẾP returns to the room")
	check(int(ui.profile.gold) == gold_before, "Result does not change wallet")
	room.leave()
	check(lobby.is_visible_in_tree(), "Room back returns to lobby")
	check(lobby.nav_index == lobby.NAV_HOME, "Home tab lit in the lobby")
	lobby.nav_tabs[1].button.pressed.emit()
	await frames()
	check(current_scene == game and lobby.store.visible and lobby.is_visible_in_tree(), "Shop opens as a popup over the lobby")
	var shop = lobby.store_pages.shop
	check(shop.visible and shop.embedded and shop.parts.is_empty() and not shop.sky.visible, "Popup shop has no own backdrop or top bar")
	check(lobby.nav_index == lobby.NAV_SHOP and lobby.store_title.text == "CỬA HÀNG", "Shop tab lit while shop is open")
	await create_timer(0.4).timeout
	var shop_style: StyleBoxFlat = lobby.nav_tabs[1].button.get_theme_stylebox("normal")
	var home_style: StyleBoxFlat = lobby.nav_tabs[0].button.get_theme_stylebox("normal")
	check(shop_style.bg_color.is_equal_approx(lobby.NAV_ON[0]) and home_style.bg_color.is_equal_approx(lobby.NAV_OFF[0]), "Highlight fades to the shop tab")
	check(lobby.nav_tabs[1].glyph.tint.is_equal_approx(lobby.NAV_ON[2]) and lobby.nav_tabs[1].glyph.scale.is_equal_approx(Vector2.ONE), "Shop icon recolors and settles")
	shop.set_category("hat")
	check(shop.selected == "hat_ice" and shop.buy_button.text == "MUA", "Hat tab selects the unowned hat")
	var gem := int(ui.profile.gem)
	shop.request_buy()
	check(shop.modal.visible, "Purchase asks for confirmation")
	shop.modal_actions.get_child(1).pressed.emit()
	await frames()
	check(ui.owned("hat_ice") and int(ui.profile.gem) == gem - 95, "Confirmed purchase uses demo wallet")
	check(not shop.buy_button.disabled and shop.buy_button.text == "MẶC NGAY", "Bought hat can be worn from the shop")
	shop.set_category("consumable")
	shop.select("bomb_basic_pack")
	check(shop.buy_button.text == "MUA THÊM", "Consumables can be bought again")
	shop.select("outfit_mimi")
	check(shop.buy_button.disabled and shop.buy_button.text == "ĐÃ SỞ HỮU", "Owned item cannot be bought twice")
	shop.set_category("wings")
	shop.select("wings_blue_angel")
	check(shop.preview_hero.wings != null and shop.buy_button.text == "MUA" and shop.preview_desc.text.contains("Đang mặc thử"), "Shop tries wings on before buying")
	check(lobby.portrait.wings == null, "Try-on does not dress the lobby hero")
	shop.request_buy()
	shop.modal_actions.get_child(1).pressed.emit()
	await frames()
	check(ui.owned("wings_blue_angel") and shop.buy_button.text == "MẶC NGAY", "Bought wings can be worn at once")
	shop.request_buy()
	check(ui.profile.loadout.wings == "wings_blue_angel" and shop.buy_button.disabled, "MẶC NGAY wears the wings")
	check(lobby.portrait.wings != null, "Lobby hero wears the bought wings")
	ui.equip("pet_bunny")
	check(lobby.portrait.pet != null, "Lobby hero shows the equipped pet")
	shop.set_category("pet")
	shop.select("pet_dragon")
	check(shop.preview_hero.pet != null and shop.buy_button.text == "MUA" and shop.preview_desc.text.contains("Đang mặc thử"), "Shop tries a pet on before buying")
	await capture("pc-shop-pet.png")
	shop.set_category("")
	await capture("pc-shop.png")
	shop.navigate.emit("equipment")
	await frames()
	var equipment = lobby.store_pages.equipment
	check(equipment.visible and not shop.visible and lobby.store.visible, "Equipment opens in the same popup")
	check(lobby.nav_index == lobby.NAV_EQUIPMENT and lobby.store_title.text == "TRANG BỊ", "Equipment tab lit")
	equipment.set_category("hat")
	await frames()
	check(equipment.grid.get_child_count() == 1, "Inventory shows owned hats")
	var hat_before := str(ui.profile.loadout.get("hat", ""))
	equipment.equip("hat_ice")
	check(ui.profile.loadout.hat == "hat_ice", "Equip from inventory")
	equipment.undo_loadout()
	check(str(ui.profile.loadout.get("hat", "")) == hat_before, "Undo restores saved loadout")
	equipment.equip("hat_ice")
	equipment.save_loadout()
	equipment.undo_loadout()
	check(ui.profile.loadout.hat == "hat_ice", "Save keeps loadout")
	check(equipment.hero_art.wings != null, "Equipment hero wears its wings")
	equipment.set_category("wings")
	await frames()
	var take_off: Button = equipment.grid.get_child(0).find_child("Equip", true, false)
	check(take_off.text == "THÁO" and not take_off.disabled, "Worn wings offer THÁO")
	take_off.pressed.emit()
	await frames()
	check(str(ui.profile.loadout.wings) == "" and equipment.hero_art.wings == null, "THÁO shows the hero without wings")
	equipment.equip("wings_blue_angel")
	check(equipment.hero_art.wings != null, "Wings back on")
	var hero := str(ui.profile.selected_character)
	equipment.cycle_hero(1)
	check(str(ui.profile.selected_character) != hero, "Hero switcher changes hero")
	equipment.cycle_hero(-1)
	equipment.set_category("")
	await capture("pc-equipment.png")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	root.push_input(esc)
	await frames()
	check(not lobby.store.visible and lobby.nav_index == lobby.NAV_HOME, "Esc closes the popup and lights home again")
	lobby.nav_tabs[3].button.pressed.emit()
	await frames()
	check(lobby.store.visible and lobby.store_pages.missions.visible and lobby.nav_index == 3, "Missions tab opens the mission window")
	await capture("pc-missions-guest.png")
	lobby.close_store()
	lobby.nav_tabs[4].button.pressed.emit()
	await frames()
	var ranking = lobby.store_pages.get("ranking")
	check(lobby.store.visible and ranking != null and ranking.visible and lobby.nav_index == lobby.NAV_RANKING, "Ranking tab opens the leaderboard")
	check(lobby.store_title.text == "BẢNG XẾP HẠNG" and ranking.state == "signed_out", "Guest sees the sign-in note (%s)" % ranking.state)
	await capture("pc-ranking-guest.png")
	var names := ["BéBômCute", "GàQuẩyPro", "BoomMaster", "MèoBông", "XukaDễThương", "RồngLửa", "CáHeoXanh", "Pikachu97", "NấmLùn", "BoomNo1"]
	var heroes := ["bombo", "mimi", "kai", "lala", "mimi", "zin", "bombo", "lala", "kai", "zin"]
	var boards := {"exp": [], "skin": [], "gold": []}
	for i in 10:
		boards.exp.append({"rank": i + 1, "name": names[i], "hero": heroes[i], "value": 1520300 - i * 110000})
	for i in 5:
		boards.skin.append({"rank": i + 1, "name": names[9 - i], "hero": heroes[9 - i], "value": 12450 - i * 1100})
		boards.gold.append({"rank": i + 1, "name": names[(i + 3) % 10], "hero": heroes[(i + 3) % 10], "value": 5230500 - i * 600000})
	ranking.apply({"boards": boards, "me": {"name": "Khách", "hero": "zin", "hidden": false, "exp": {"rank": 42, "value": 1200}, "skin": {"rank": null, "value": 0}, "gold": {"rank": 7, "value": 83250}}})
	await frames()
	check(ranking.table.get_child_count() == 10 and ranking.table.get_child(0).name == "Row_1", "Experience tab: top 10")
	check(ranking.value_head.text == "Kinh nghiệm" and ranking.find_child("Side_*", true, false) == null, "Only the open board shows (%s)" % ranking.value_head.text)
	await capture("pc-ranking.png")
	for spec in [["skin", "Điểm skin"], ["gold", "Tiền"]]:
		ranking.tab_buttons[spec[0]].pressed.emit()
		await frames()
		check(ranking.current == spec[0] and ranking.tab_buttons[spec[0]].button_pressed and ranking.table.get_child_count() == 5, "%s tab shows its board" % spec[1])
		check(ranking.value_head.text == spec[1] and ranking.tab_labels[spec[0]].get_theme_color("font_color") == Color.WHITE, "%s header and lit tab" % spec[1])
		await capture("pc-ranking-%s.png" % spec[0])
	ranking.find_child("Done", true, false).pressed.emit()
	await frames()
	check(not lobby.store.visible and lobby.nav_index == lobby.NAV_HOME, "ĐÃ HIỂU closes the leaderboard and lights home")
	lobby.notice("Thử", "THÔNG BÁO", "trophy", 4)
	await capture("pc-notice.png")
	lobby.close_modal()
	check(lobby.nav_index == lobby.NAV_HOME, "Closing a notice lights home")
	lobby.open_shop("shop")
	lobby.open_settings()
	check(lobby.store_pages.settings.visible and not lobby.store_pages.shop.visible and lobby.nav_index == lobby.NAV_HOME, "Settings replaces the shop in the popup")
	lobby.nav_tabs[0].button.pressed.emit()
	check(not lobby.modal.visible and not lobby.store.visible and lobby.nav_index == lobby.NAV_HOME, "Home tab closes every popup")
	print("PRACTICE_PC_SCREENS_OK" if not failed else "PRACTICE_PC_SCREENS_FAILED")
	quit(1 if failed else 0)
