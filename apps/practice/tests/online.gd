extends SceneTree
## Real online play against a running stack (SUNI_API_URL, optional SUNI_ARENA_URL):
## two registered players, friends, the lobby room list and filters, a v2 room on
## a chosen map, Sẵn sàng, a server-authoritative round and the result, then leave.
## Player A drives the real PC lobby/room/battle screens; player B is a second
## OnlineArena adapter in the same process with its own token.
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
	else:
		print("  ok - ", message)

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
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(capture_dir + "/" + file) == OK, "Screenshot " + file)

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
	create_timer(90).timeout.connect(func(): push_error("timeout"); quit(1))
	if api.is_empty():
		push_error("Set SUNI_API_URL to a running stack")
		quit(1)
		return
	var account = root.get_node("AuthSession")
	var arena = root.get_node("OnlineArena")
	check(account.configure(api), "API URL accepted")
	var a_name := "on_a_" + tag
	var b_name := "on_b_" + tag
	var reg_a := await http(HTTPClient.METHOD_POST, "/v1/register", {"username": a_name, "password": "online-password-1", "email": a_name + "@example.com"})
	var reg_b := await http(HTTPClient.METHOD_POST, "/v1/register", {"username": b_name, "password": "online-password-1", "email": b_name + "@example.com"})
	check(reg_a.status == 201 and reg_b.status == 201, "Two players registered")
	var b_token: String = reg_b.data.access_token
	check(await account.authenticate(a_name, "online-password-1"), "Player A signs in")
	# Friends: A asks, B accepts (through the API, as B).
	var b_me := await http(HTTPClient.METHOD_GET, "/v1/me", null, b_token)
	var b_id: String = str(b_me.data.get("id", b_me.data.get("account_id", "")))
	var ask: Dictionary = await account.api(HTTPClient.METHOD_POST, "/v1/friends/requests", {"account_id": b_id})
	check(ask.status == 201, "Friend request sent")
	var accepted := await http(HTTPClient.METHOD_POST, "/v1/friends/requests/%s/accept" % str(ask.data.request_id), null, b_token)
	check(accepted.status == 200, "Friend request accepted")
	# Player B opens a room (SUNI_ONLINE_MAP, default frost) with its own adapter.
	var map_id := OS.get_environment("SUNI_ONLINE_MAP")
	if map_id.is_empty():
		map_id = "frost"
	var level: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://levels/%s.json" % map_id))
	var b_arena: Node = load("res://scripts/online_arena.gd").new()
	b_arena.token_override = b_token
	root.add_child(b_arena)
	check(await b_arena.create_room(map_id, "mimi"), "B creates a %s room: %s" % [map_id, b_arena.last_error])
	var room_number := int(b_arena.snapshot.get("number", 0))
	check(b_arena.snapshot.map == map_id and room_number > 0 and int(b_arena.snapshot.width) == int(level.columns) and int(b_arena.snapshot.height) == int(level.rows), "v2 snapshot with map and number")
	# Player A sees it in the real lobby, with the friend filter.
	change_scene_to_file("res://scenes/main.tscn")
	await process_frame
	await process_frame
	var game = current_scene
	var lobby = game.menu.get_node("DesktopMainLobby")
	lobby.friends_clock = 0.0
	lobby.rooms_clock = 0.0
	check(await until(func(): return lobby.rooms_state == "ok" and lobby.rooms.any(func(r): return int(r.number) == room_number), 15.0), "Lobby lists B's room from the arena")
	check(lobby.friend_ids.has(b_id), "Lobby knows B is a friend")
	lobby.friends_toggle.button_pressed = true
	check(lobby.visible_rooms().any(func(r): return int(r.number) == room_number), "Chỉ bạn bè shows the friend's room")
	lobby.open_toggle.button_pressed = true
	var slot := -1
	for i in lobby.room_cards.size():
		if lobby.room_cards[i].holder.visible and int(lobby.room_cards[i].room.get("number", 0)) == room_number:
			slot = i
	check(slot >= 0 and lobby.room_cards[slot].button.text == "Vào" and lobby.room_cards[slot].count.text == "1/8", "Card shows Vào and 1/8")
	await capture("online-lobby.png")
	# Every map (classic and Boom World) is offered when creating a room.
	lobby.open_create()
	var cards: Array = lobby.modal_packs.find_children("Create_*", "Button", true, false)
	check(cards.size() == game.LEVEL_FILES.size() and lobby.find_child("Create_moon", true, false) != null, "Create popup lists all %d maps" % game.LEVEL_FILES.size())
	await capture("online-create.png")
	lobby.close_modal()
	lobby.room_cards[slot].button.pressed.emit()
	var online = game.pc_screens["online"]
	check(await until(func(): return online.is_visible_in_tree() and arena.connected, 15.0), "A joins through Vào: " + arena.last_error)
	check(await until(func(): return arena.snapshot.get("players", []).size() == 2 and online.status_label.text.begins_with("2/8")), "Room shows both players")
	check(online.seats[1].name.text.begins_with(a_name) or online.seats[0].name.text.begins_with(a_name), "Seat shows A's name")
	# Room chat goes through the API room channel (membership from arena ingest).
	if await until(func(): return online.chat_key != "", 5.0):
		await create_timer(1.5).timeout
		online.chat_input.text = "xin chao " + tag
		online.send_chat()
		var b_read := {}
		for attempt in 10:
			b_read = await http(HTTPClient.METHOD_GET, "/v1/chat?channel=room&room=%s&after=0" % online.chat_key.uri_encode(), null, b_token)
			if b_read.status == 200 and b_read.data.messages.any(func(m): return str(m.body).ends_with(tag)):
				break
			await create_timer(0.5).timeout
		check(b_read.status == 200 and b_read.data.messages.any(func(m): return str(m.body).ends_with(tag)), "B reads A's room chat")
	await capture("online-room.png")
	# Lobby list now says 2/8 for B (seen from B's token).
	var listed: Dictionary = await b_arena.list_rooms()
	check(listed.ok and listed.rooms.any(func(r): return int(r.number) == room_number and int(r.players) == 2), "List counts 2/8")
	# Ready: B first, then A through the real button.
	b_arena.send_action("ready")
	online.ready_button.pressed.emit()
	check(online.ready_button.disabled, "Ready button locks after press")
	check(await until(func(): return str(arena.snapshot.get("phase", "")) == "playing", 10.0), "Round starts after both ready")
	check(await until(func(): return online.battle_view.visible and online.fighters.size() == 2 and online.crates.size() > 0), "Battle board drawn from the snapshot")
	var me: Dictionary = arena.me()
	check(not me.is_empty() and me.alive, "A is alive at the start")
	# A walks one step (intent), the server moves it.
	var start_cell := Vector2i(int(me.x), int(me.y))
	var step := "right" if start_cell.x < 7 else "left"
	arena.send_action(step)
	check(await until(func(): return Vector2i(int(arena.me().x), int(arena.me().y)) != start_cell, 3.0), "Server moved A after a move intent")
	await capture("online-battle.png")
	# A bombs itself in place: the server explodes it and B wins.
	arena.send_action("bomb")
	check(await until(func(): return arena.snapshot.get("bombs", []).size() == 1 and online.bombs.size() == 1, 3.0), "Bomb comes back in the snapshot and is drawn")
	check(await until(func(): return str(arena.snapshot.get("phase", "")) == "finished", 6.0), "Round finishes")
	check(str(arena.snapshot.get("winner", "")) == b_arena.session_id, "Server picked B as winner")
	check(await until(func(): return online.result_box.visible and online.result_title.text == "THUA RỒI!"), "A sees the loss")
	await capture("online-result.png")
	# The finished round is recorded by the API as a verified match.
	check(await until(func(): return str(arena.snapshot.get("phase", "")) == "waiting", 12.0) and online.room_view.visible, "Back to the waiting room after the round")
	online.leave()
	check(await until(func(): return lobby.is_visible_in_tree() and not arena.connected, 5.0), "Leave returns to the lobby")
	b_arena.leave()
	print("PRACTICE_ONLINE_OK" if not failed else "PRACTICE_ONLINE_FAILED")
	quit(1 if failed else 0)
