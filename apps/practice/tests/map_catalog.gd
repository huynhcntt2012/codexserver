extends SceneTree
## Admin-published maps in the PC app (no server needed): MapCatalog keeps valid
## maps, the lobby lists them, previews render and practice plays them.
var failed := false

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func admin_map(id: String) -> Dictionary:
	return {
		"id": id, "name": "MÊ CUNG KẸO", "subtitle": "Dễ • Thử nghiệm", "theme": "pastry",
		"wall": "stone_wall", "crate": "wood_crate", "bomb": "pink", "fx": "heart",
		"bot_step": 0.39, "bot_bomb": 3.0, "columns": 13, "rows": 11, "revision": 1, "custom": true,
		"layout": [
			"#############", "#...........#", "#.#.#C#C#.#.#", "#.....C.....#", "#.#C#.#.#C#.#",
			"#...........#", "#.#C#.#.#C#.#", "#.....C.....#", "#.#.#C#C#.#.#", "#...........#",
			"#############",
		],
		"spawns": [[1, 1], [11, 1], [11, 9], [1, 9]],
	}

func run() -> void:
	create_timer(60).timeout.connect(func(): quit(1))
	var catalog = root.get_node("MapCatalog")
	var builtin: int = catalog.all().size()
	check(builtin == 15, "15 built-in maps")
	var missing_art := admin_map("bad_art")
	missing_art.theme = "rainbow"
	var walled := admin_map("bad_spawn")
	walled.spawns[0] = [0, 0]
	var clash := admin_map("moon")
	catalog.apply([admin_map("candy_maze"), missing_art, walled, clash, "junk"])
	check(catalog.all().size() == builtin + 1 and catalog.index_of("candy_maze") == builtin, "Only the valid admin map is added")
	var art: Texture2D = catalog.preview("candy_maze")
	check(art != null and art.get_size() == Vector2(13 * 16, 11 * 16), "Admin map preview is rendered")
	check(catalog.preview("moon") is CompressedTexture2D, "Built-in maps keep their PNG preview")
	change_scene_to_file("res://scenes/main.tscn")
	await process_frame
	await process_frame
	var game = current_scene
	var lobby = game.menu.get_node("DesktopMainLobby")
	check(lobby.map_index("candy_maze") == builtin and lobby.map_select.item_count == builtin + 2, "Lobby lists the admin map (plus \"Tất cả\")")
	lobby.apply_rooms({"ok": true, "rooms": [{"roomId": "r1", "number": 1, "map": "candy_maze", "phase": "waiting", "players": 2, "maxPlayers": 8, "joinable": true, "accountIds": []}]})
	var index: int = lobby.map_index("candy_maze")
	lobby.set_map(index)
	check(lobby.visible_maps() == [index] and lobby.map_cards[0].title.text == "Mê Cung Kẹo" and lobby.map_cards[0].art.texture != null and lobby.map_cards[0].count.text == "2 người · 1 phòng" and (lobby.map_cards[0].fresh as Label).get_parent().visible, "The admin map has a card with its room and a Mới tag")
	lobby.set_map(-1)
	# A newer catalog without the map drops it again.
	catalog.apply([])
	check(lobby.map_select.item_count == builtin + 1 and lobby.map_index("candy_maze") < 0 and lobby.visible_maps().size() == builtin, "Unpublished map disappears from the lobby")
	catalog.apply([admin_map("candy_maze")])
	# "LUYỆN TẬP" opens a map grid that includes the admin map; picking it starts there.
	lobby.find_child("Mode_luyen_tap", true, false).pressed.emit()
	var practice_card = lobby.find_child("Practice_candy_maze", true, false)
	check(lobby.modal.visible and practice_card != null and lobby.modal_packs.find_children("Practice_*", "Button", true, false).size() == builtin + 1, "Practice map grid lists the admin map")
	practice_card.pressed.emit()
	await process_frame
	check(game.selected_level == catalog.index_of("candy_maze") and game.pc_screens["matchmaking"].is_visible_in_tree(), "Picking the admin map starts practice on it")
	game.pc_screens["matchmaking"].clock = 99.0
	for i in 10:
		await process_frame
	var room = game.pc_screens["room"]
	check(room.is_visible_in_tree() and room.map_name.text == "Mê Cung Kẹo" and room.map_info.text.contains("admin") and room.map_art.texture != null, "Practice room shows the admin map")
	game._select_level(catalog.index_of("candy_maze"))
	game._new_round()
	await process_frame
	check(game.columns == 13 and game.rows == 11 and game.fighters.size() == 4 and game.fighters[2].cell == Vector2i(11, 9), "Practice plays the admin map")
	game._show_menu()
	print("PRACTICE_MAP_CATALOG_OK" if not failed else "PRACTICE_MAP_CATALOG_FAILED")
	quit(1 if failed else 0)
