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
	# Built-in level file, or a map an admin published (fetched by MapCatalog).
	var catalog = root.get_node("MapCatalog")
	await catalog.refresh(true)
	var level: Dictionary = catalog.find(map_id)
	check(not level.is_empty(), "Map %s is known to the app" % map_id)
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
	await capture("online-lobby-maps.png")
	lobby.friends_toggle.button_pressed = true
	var map_at: int = lobby.map_index(map_id)
	check(lobby.visible_maps() == [map_at], "Chỉ bạn bè shows the map with the friend's room")
	lobby.open_toggle.button_pressed = true
	check(lobby.visible_maps() == [map_at] and lobby.map_stats(map_id).join.get("number", 0) == room_number, "Chỉ phòng trống keeps it; Vào targets B's room")
	var slot := 0
	check(lobby.map_cards[slot].holder.visible and lobby.map_cards[slot].map.id == map_id and lobby.map_cards[slot].button.text == "Vào" and lobby.map_cards[slot].count.text == "1 người · 1 phòng", "Map card shows Vào and 1 người · 1 phòng")
	await capture("online-lobby.png")
	# Every map (classic and Boom World) is offered when creating a room.
	lobby.open_create()
	var cards: Array = lobby.modal_packs.find_children("Create_*", "Button", true, false)
	check(cards.size() == catalog.all().size() and lobby.find_child("Create_moon", true, false) != null and lobby.find_child("Create_" + map_id, true, false) != null, "Create popup lists all %d maps" % catalog.all().size())
	await capture("online-create.png")
	lobby.close_modal()
	var online = game.pc_screens["online"]
	if OS.get_environment("SUNI_JOIN_BY") == "card":
		lobby.map_cards[slot].button.pressed.emit()
		check(await until(func(): return online.is_visible_in_tree() and arena.connected, 15.0), "A joins through Vào: " + arena.last_error)
	else:
		# B (in the room) invites A; A's inbox card shows up in the lobby and joins.
		var invite := await http(HTTPClient.METHOD_POST, "/v1/invites", {"account_id": str(account.account_id), "room_key": str(b_arena.snapshot.roomKey), "number": room_number}, b_token)
		check(invite.status == 201, "B invites A (HTTP %d)" % invite.status)
		var inbox = root.get_node("InviteInbox")
		inbox.clock = 0.0
		check(await until(func(): return inbox.card.visible and inbox.title.text.begins_with(b_name), 10.0), "A sees B's invite card in the lobby")
		await capture("online-invite-card.png")
		inbox.accept_button.pressed.emit()
		check(await until(func(): return online.is_visible_in_tree() and arena.connected and arena.room_id == b_arena.room_id, 15.0), "A joins B's room from the invite: " + arena.last_error)
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
	# A invites B from the waiting room's MỜI BẠN panel.
	online.invite_button.pressed.emit()
	check(await until(func(): return online.invite_panel.visible and online.invite_list.find_child("Friend_" + b_id, true, false) != null, 10.0), "MỜI BẠN lists friend B")
	await capture("online-invite-panel.png")
	online.invite_list.find_child("Friend_" + b_id, true, false).find_child("Invite", true, false).pressed.emit()
	var got := false
	for attempt in 20:
		var inbox_b := await http(HTTPClient.METHOD_GET, "/v1/invites", null, b_token)
		got = inbox_b.status == 200 and inbox_b.data.invites.any(func(i): return i["from"].name == a_name)
		if got:
			break
		await create_timer(0.3).timeout
	check(got, "B receives A's invite")
	online.invite_panel.hide()
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
	# The verified round reached the API and counted for both players' missions.
	var counted := false
	for attempt in 20:
		var quests := await http(HTTPClient.METHOD_GET, "/v1/quests", null, b_token)
		for quest in quests.data.get("daily", {}).get("quests", []) if quests.status == 200 else []:
			if quest.key == "D02" and int(quest.objectives[0].progress) >= 1:
				counted = true
		if counted:
			break
		await create_timer(0.5).timeout
	check(counted, "Online round counted for mission D02")
	online.leave()
	check(await until(func(): return lobby.is_visible_in_tree() and not arena.connected, 5.0), "Leave returns to the lobby")
	b_arena.leave()
	await until(func(): return not b_arena.connected, 5.0)
	# Practice room "+ Mời": confirm, an online room opens on the same map with the picker.
	lobby.practice_on("park")
	game.pc_screens["matchmaking"].clock = 99.0
	var room = game.pc_screens["room"]
	check(await until(func(): return room.is_visible_in_tree(), 5.0), "Practice room opens")
	room.find_child("InviteSlot", true, false).pressed.emit()
	check(room.modal.visible and room.modal_title.text == "LUYỆN TẬP CÙNG BẠN BÈ", "+ Mời offers a practice room with bots")
	room.modal_actions.get_child(1).pressed.emit()
	check(await until(func(): return online.is_visible_in_tree() and arena.connected and str(arena.snapshot.get("map", "")) == "park", 15.0), "An online room opens on the practice map")
	check(await until(func(): return online.invite_panel.visible and online.invite_list.find_child("Friend_" + b_id, true, false) != null, 10.0), "Friend picker opens by itself")
	var bots := func() -> int: return arena.snapshot.get("players", []).filter(func(p): return bool(p.get("bot", false))).size()
	check(bool(arena.snapshot.get("practice", false)) and bots.call() == 3 and arena.snapshot.players.size() == 4, "Practice room: me + 3 server bots")
	await capture("online-practice-invite.png")
	online.invite_list.find_child("Friend_" + b_id, true, false).find_child("Invite", true, false).pressed.emit()
	var practice_invite := {}
	for attempt in 20:
		var inbox_b := await http(HTTPClient.METHOD_GET, "/v1/invites", null, b_token)
		for i in inbox_b.data.get("invites", []) if inbox_b.status == 200 else []:
			if i.room_id == arena.room_id:
				practice_invite = i
		if not practice_invite.is_empty():
			break
		await create_timer(0.3).timeout
	check(not practice_invite.is_empty(), "B gets the practice room invite")
	online.invite_panel.hide()
	var practice_ok := await http(HTTPClient.METHOD_POST, "/v1/invites/%s/accept" % practice_invite.get("id", "x"), {}, b_token)
	check(practice_ok.status == 200 and await b_arena.join_room(str(practice_ok.data.room_id), "zin"), "B accepts and joins the practice room: " + b_arena.last_error)
	check(await until(func(): return arena.snapshot.players.size() == 4 and bots.call() == 2, 5.0), "B takes a bot's seat (2 people + 2 bots)")
	await capture("online-practice-room.png")
	online.ready_button.pressed.emit()
	b_arena.send_action("ready")
	check(await until(func(): return str(arena.snapshot.get("phase", "")) == "playing", 8.0), "Friends + bots round starts")
	var starts := {}
	for p in arena.snapshot.players:
		starts[str(p.id)] = Vector2i(int(p.x), int(p.y))
	check(await until(func(): return arena.snapshot.players.any(func(p): return bool(p.get("bot", false)) and Vector2i(int(p.x), int(p.y)) != starts.get(str(p.id))), 6.0), "Server bots move in the shared match")
	await create_timer(1.5).timeout
	await capture("online-practice-battle.png")
	b_arena.leave()
	online.leave()
	await until(func(): return not arena.connected, 5.0)
	b_arena.leave()
	print("PRACTICE_ONLINE_OK" if not failed else "PRACTICE_ONLINE_FAILED")
	quit(1 if failed else 0)
