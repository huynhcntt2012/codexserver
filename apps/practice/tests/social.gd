extends SceneTree
## Change password, friends and chat against a real API (SUNI_API_URL, default
## http://127.0.0.1:8000). Other players are driven with raw HTTP calls.
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

func capture(file: String) -> void:
	if capture_dir.is_empty():
		return
	await frames(4)
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

func register(user: String) -> Dictionary:
	var reply := await http(HTTPClient.METHOD_POST, "/v1/register", {"username": user, "password": "first-password-1", "email": user + "@example.com"})
	check(reply.status == 201, "Register " + user)
	return reply.data

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Social test timed out"); quit(1))
	if api.is_empty():
		api = "http://127.0.0.1:8000"
	var account = root.get_node("AuthSession")
	var saved_url: String = account.api_url
	account.api_url = api
	var ana_name := "ana_" + tag
	var bo := await register("bo_" + tag)
	await register(ana_name)
	var cursor: Image = root.get_node("GameCursor").draw_cursor(Color("fff6c9"), Color("ffd257"))
	check(cursor.get_size() == Vector2i(36, 36) and cursor.get_pixel(0, 35).a == 0.0 and cursor.get_pixel(6, 12).a > 0.9, "Game cursor image is drawn")
	var beam: Image = root.get_node("GameCursor").draw_cursor(Color("fff6c9"), Color("ffd257"), root.get_node("GameCursor").BEAM)
	check(beam.get_pixel(18, 18).a > 0.9 and beam.get_pixel(4, 18).a == 0.0, "Text-field cursor is an I-beam")
	change_scene_to_file("res://scenes/ui/launch/launch_screen.tscn")
	await frames()
	var screen = current_scene
	check(not screen.get_node("CanvasRoot/ShopEquipment").visible, "No shop before login")
	screen._on_forgot()
	var forgot = screen.forgot_dialog
	check(forgot.visible and forgot.email_field.visible and not forgot.code_field.visible, "Forgot opens on the email step")
	forgot.email_field.text = "not-an-email"
	check((await forgot.submit()).begins_with("Email chưa hợp lệ") and forgot.step == "email", "Invalid email stays on step one")
	forgot.email_field.text = ana_name + "@EXAMPLE.com"
	check(await forgot.submit() == "" and forgot.step == "code" and forgot.code_field.visible and forgot.link.visible, "Code step after sending")
	forgot.code_field.text = "12ab34"
	forgot.code_field.text_changed.emit(forgot.code_field.text)
	check(forgot.code_field.text == "1234", "Code field keeps digits only")
	forgot.code_field.text = "000000"
	forgot.new_field.text = "second-password-2"
	forgot.confirm_field.text = "second-password-2"
	check((await forgot.submit()).begins_with("Mã không đúng") and forgot.visible, "Wrong code is refused")
	await capture("forgot-dialog.png")
	forgot.cancel_button.pressed.emit()
	check(forgot.step == "email" and forgot.code_field.text.is_empty(), "Back returns to the email step")
	forgot.close()
	screen.auth_panel.username_field.text = ana_name
	screen.get_node("CanvasRoot/FooterNav/ChangePassword").pressed.emit()
	var dialog = screen.password_dialog
	check(dialog.visible and dialog.username_field.text == ana_name, "Change password opens with the typed name")
	dialog.current_field.text = "first-password-1"
	dialog.new_field.text = "second-password-2"
	dialog.confirm_field.text = "mismatch-password"
	check(await dialog.submit() == "Mật khẩu mới nhập lại chưa khớp." and not account.busy, "Mismatch never calls the API")
	dialog.current_field.text = "wrong-password-0"
	dialog.confirm_field.text = "second-password-2"
	check((await dialog.submit()).contains("không đúng") and dialog.visible, "Wrong current password is refused")
	await capture("password-dialog.png")
	dialog.current_field.text = "first-password-1"
	dialog.new_field.text = "second-password-2"
	dialog.confirm_field.text = "second-password-2"
	check(await dialog.submit() == "" and not dialog.visible and screen.info_dialog.visible, "Password changed")
	screen.info_dialog.hide_dialog()
	check(not await account.authenticate(ana_name, "first-password-1"), "Old password no longer works")
	screen.auth_panel.password_field.text = "second-password-2"
	screen.auth_panel._submit()
	while account.busy:
		await process_frame
	await frames()
	check(current_scene.scene_file_path == "res://scenes/main.tscn" and account.has_session(), "New password signs in")
	var lobby = current_scene.menu.get_node("DesktopMainLobby")
	var social = lobby.social
	var panel = lobby.friends_panel
	var chat = lobby.chat
	await social.poll()
	lobby.show_social(1)
	await frames()
	check(panel.online_box.visible and not panel.offline.visible, "Signed-in friends tab is live")
	panel.search.text = "bo_" + tag
	await panel.run_search()
	await frames()
	check(panel.results.size() == 1 and panel.list.has_node("User_bo_" + tag), "Search shows the player")
	var row = panel.list.get_node("User_bo_" + tag)
	panel.open_profile(panel.results[0])
	check(lobby.modal.visible and lobby.modal_title.text == "THÔNG TIN NGƯỜI CHƠI" and lobby.modal_message.text.contains("Chưa là bạn bè") and lobby.modal_extra.visible, "Profile shows info and add action")
	lobby.close_modal()
	row.find_child("Add", true, false).pressed.emit()
	while social.outgoing.is_empty():
		await process_frame
	await frames()
	check(social.outgoing[0].user.name == "bo_" + tag, "Friend request sent")
	var bo_friends := await http(HTTPClient.METHOD_GET, "/v1/friends", null, bo.access_token)
	check(bo_friends.data.incoming.size() == 1 and bo_friends.data.incoming[0].user.name == ana_name, "Other player receives the request")
	await http(HTTPClient.METHOD_POST, "/v1/friends/requests/%s/accept" % bo_friends.data.incoming[0].request_id, null, bo.access_token)
	await social.poll()
	await frames()
	check(social.friends.size() == 1 and panel.list.get_node("User_bo_" + tag).find_child("Chat", true, false) != null, "Accepted friend listed with chat")
	var cy := await register("cy_" + tag)
	await http(HTTPClient.METHOD_POST, "/v1/friends/requests", {"account_id": account.account_id}, cy.access_token)
	await social.poll()
	await frames()
	check(social.incoming.size() == 1 and panel.list.get_node("User_cy_" + tag).find_child("Accept", true, false) != null, "Incoming request can be answered")
	await capture("friends.png")
	await panel.answer(social.incoming[0].request_id, true, "cy_" + tag)
	check(social.friends.size() == 2 and social.incoming.is_empty(), "Accepting adds the friend")
	chat.pick_channel("world")
	chat.input.text = "xin chào " + tag
	await chat.submit()
	check(chat.input.text.is_empty(), "World message sent")
	var seen := await http(HTTPClient.METHOD_GET, "/v1/chat?channel=world", null, bo.access_token)
	check(seen.data.messages.any(func(m): return m.body == "xin chào " + tag), "Other player sees world chat")
	await http(HTTPClient.METHOD_POST, "/v1/chat", {"channel": "private", "body": "riêng " + tag, "to": account.account_id}, bo.access_token)
	await social.poll()
	chat.pick_channel("private")
	await frames()
	var lines: Array = chat.log_list.get_children().map(func(label): return label.text)
	check(lines.any(func(text): return text.contains("bo_%s → Bạn: riêng %s" % [tag, tag])), "Private message from friend shown")
	chat.open_private(bo.account_id)
	check(chat.target.visible and chat.target_ids[chat.target.selected] == bo.account_id, "Chat icon picks the friend")
	chat.input.text = "trả lời " + tag
	await chat.submit()
	var thread := await http(HTTPClient.METHOD_GET, "/v1/chat?channel=private", null, bo.access_token)
	check(thread.data.messages.any(func(m): return m.body == "trả lời " + tag and m.sender.name == ana_name), "Friend receives private reply")
	chat.pick_channel("guild")
	await frames()
	check(chat.guild_box.visible, "Guild tab offers create/join")
	chat.guild_name.text = "Bang " + tag
	await chat.join_guild()
	await frames()
	check(social.guild != null and not chat.guild_box.visible and chat.leave_button.visible, "Guild joined")
	chat.input.text = "bang ơi " + tag
	await chat.submit()
	check(social.messages.any(func(m): return m.channel == "guild" and m.body == "bang ơi " + tag), "Guild chat sent")
	chat.pick_channel("all")
	await capture("chat.png")
	await chat.leave_guild()
	check(social.guild == null, "Left guild")
	lobby.leave()
	# Logging in saves the API URL; put the configured one back.
	account.configure(saved_url)
	print("PRACTICE_SOCIAL_OK" if not failed else "PRACTICE_SOCIAL_FAILED")
	quit(1 if failed else 0)
