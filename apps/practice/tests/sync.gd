extends SceneTree
## Admin <-> client sync against a real API (SUNI_API_URL): catalog + icon cache,
## server wallet, purchase, sandbox top-up, practice room/match report, presence.
## Admin checks need SUNI_ADMIN_USER / SUNI_ADMIN_PASSWORD (a test admin).
## Set SUNI_CAPTURE_DIR to save screenshots (needs a display).
var failed := false
var api := OS.get_environment("SUNI_API_URL")
var capture_dir := OS.get_environment("SUNI_CAPTURE_DIR")
var tag := Crypto.new().generate_random_bytes(4).hex_encode()

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func frames(count := 3) -> void:
	for i in count:
		await process_frame

func until(condition: Callable, seconds := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call():
		if Time.get_ticks_msec() > end:
			return false
		await process_frame
	return true

func capture(file: String) -> void:
	if capture_dir.is_empty():
		return
	await frames(4)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(capture_dir + "/" + file) == OK, "Screenshot " + file)

func wipe(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		wipe(path + "/" + sub)
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(path)

func http(method: int, path: String, body: Variant = null, token := "") -> Dictionary:
	var request := HTTPRequest.new()
	root.add_child(request)
	var headers := PackedStringArray()
	if token != "":
		headers.append("Authorization: Bearer " + token)
	if body != null:
		headers.append("Content-Type: application/json")
	request.request(api + path, headers, method, JSON.stringify(body) if body != null else "")
	var response: Array = await request.request_completed
	request.queue_free()
	var raw: String = response[3].get_string_from_utf8()
	return {"status": response[1], "data": JSON.parse_string(raw) if not raw.is_empty() else null}

func run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Sync test timed out"); quit(1))
	var account = root.get_node("AuthSession")
	var ui = root.get_node("UIState")
	var catalog = root.get_node("CatalogSync")
	var saved_url: String = account.api_url
	account.api_url = api
	# Start from an empty icon cache so every download is exercised.
	wipe(catalog.DIR)
	DirAccess.make_dir_recursive_absolute(catalog.ICONS)
	catalog.etag = ""
	catalog.queue.clear()
	await catalog.sync()
	check(catalog.server_items.size() >= 18 and catalog.etag != "", "Catalog downloaded with ETag")
	check(await until(func(): return catalog.queue.is_empty() and catalog.active == 0), "Icon queue drains")
	var cached := 0
	for entry in catalog.server_items:
		if FileAccess.file_exists(catalog.icon_path(entry)):
			cached += 1
	check(cached == catalog.server_items.size(), "Every server icon cached (%d/%d)" % [cached, catalog.server_items.size()])
	var hat: Dictionary = ui.get_item("hat_ice")
	check(str(hat.icon).begins_with("user://catalog/icons/") and load("res://scripts/ui/pc/pc_kit.gd").icon_texture(str(hat.icon)) != null, "Items use cached server art")
	var downloads_before: int = cached
	await catalog.sync()
	check(catalog.queue.is_empty() and catalog.active == 0 and downloads_before == cached, "Second sync is a 304 with no downloads")

	var name := "sync_" + tag
	var reg := await http(HTTPClient.METHOD_POST, "/v1/register", {"username": name, "password": "sync-password-1", "email": name + "@example.com"})
	check(reg.status == 201, "Register player")
	check(await account.authenticate(name, "sync-password-1"), "Player signs in")
	check(await until(func(): return ui.online_wallet), "Server wallet loaded")
	check(int(ui.profile.gold) == 5000 and int(ui.profile.gem) == 100 and ui.owned("outfit_mimi"), "Welcome wallet and starter items")
	ui.buy("hat_ice")
	check(await until(func(): return ui.owned("hat_ice")), "Server purchase")
	check(int(ui.profile.gem) == 5, "Server priced the hat (95 gem)")
	ui.buy("hat_ice")
	await create_timer(1.0).timeout
	check(int(ui.profile.gem) == 5, "Owned hat cannot be bought twice")

	change_scene_to_file("res://scenes/main.tscn")
	await frames()
	var game = current_scene
	var lobby = game.pc_screens["lobby"]
	lobby.open_topup()
	check(await until(func(): return lobby.modal_packs.visible and lobby.modal_packs.get_child_count() == 5), "Top-up packs listed")
	await capture("topup.png")
	lobby.modal_packs.get_node("Pack_gem_60").pressed.emit()
	check(await until(func(): return int(ui.profile.gem) == 65), "Sandbox top-up credits gems")
	lobby.close_modal()
	lobby.open_shop("shop")
	await frames()
	lobby.store_pages.shop.set_category("hat")
	await capture("shop-server-icons.png")
	lobby.close_store()

	game.show_pc_screen("room")
	check(await until(func(): return game.reporter.room_id != ""), "Practice room reported")
	var room = game.pc_screens["room"]
	check(await until(func(): return room.online_chat()), "Room chat goes through the server")
	room.chat_input.text = "chào phòng " + tag
	room.send_chat()
	var room_key: String = game.reporter.room_key
	var stored: Dictionary = {}
	await until(func(): return room.chat_after > 0)
	stored = await account.api(HTTPClient.METHOD_GET, "/v1/chat?channel=room&room=" + room_key.uri_encode())
	check(stored.status == 200 and stored.data.messages.size() == 1 and stored.data.messages[0].body == "chào phòng " + tag, "Room message stored for room members")
	room.ready_clock = 99.0
	room.refresh()
	await capture("room-chat.png")
	room.start()
	await frames()
	check(game.game_state == "playing" and catalog.paused, "Downloads pause during a round")
	for actor in game.fighters:
		if actor.bot:
			game._hit_fighter(actor, game.player)
	game._resolve_outcome()
	await frames()
	check(game.game_state == "ended" and not catalog.paused and game.reporter.round_no == 1, "Round reported")
	await create_timer(1.5).timeout

	var admin_user := OS.get_environment("SUNI_ADMIN_USER")
	if admin_user != "":
		var login := await http(HTTPClient.METHOD_POST, "/admin/v1/auth/login", {"username": admin_user, "password": OS.get_environment("SUNI_ADMIN_PASSWORD")})
		check(login.status == 200, "Test admin signs in")
		var token: String = login.data.get("access_token", "") if login.data is Dictionary else ""
		var online := await http(HTTPClient.METHOD_GET, "/admin/v1/accounts?status=online&q=" + name, null, token)
		check(online.status == 200 and online.data.total == 1 and online.data.items[0].gem == 65, "Admin sees player online with wallet")
		var history := await http(HTTPClient.METHOD_GET, "/admin/v1/matches?source=practice&account_id=" + account.account_id, null, token)
		check(history.status == 200 and history.data.total == 1, "Admin sees the practice match")
		if history.data is Dictionary and history.data.total == 1:
			var match: Dictionary = history.data.items[0]
			var humans: Array = match.participants.filter(func(p): return not p.is_bot)
			check(match.participants.size() == 4 and not match.verified and humans.size() == 1 and humans[0].account_id == account.account_id and humans[0].winner, "Match lists 4 fighters, unverified, human winner")
		var tx := await http(HTTPClient.METHOD_GET, "/admin/v1/transactions?account_id=" + account.account_id, null, token)
		var kinds: Array = tx.data.items.map(func(e): return e.kind) if tx.data is Dictionary else []
		check(kinds.has("topup") and kinds.has("purchase") and kinds.has("welcome"), "Admin sees top-up, purchase and welcome entries")
	game.show_pc_screen("lobby")
	await create_timer(0.5).timeout
	account.logout()
	check(await until(func(): return not ui.online_wallet and int(ui.profile.gold) == 12560), "Sign-out returns to the demo wallet")
	account.configure(saved_url)
	print("PRACTICE_SYNC_OK" if not failed else "PRACTICE_SYNC_FAILED")
	quit(1 if failed else 0)
