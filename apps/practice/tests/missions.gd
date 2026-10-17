extends SceneTree
## Missions and events against a real stack (SUNI_API_URL + SUNI_ADMIN_USER /
## SUNI_ADMIN_PASSWORD of a test admin): the admin seeds D01–W03 and publishes the
## sample story event; a player opens Nhiệm vụ, claims the check-in reward and sees
## chapters, the event banner and the Event Shop. Set SUNI_CAPTURE_DIR for screenshots.
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
	root.get_texture().get_image().save_png(capture_dir + "/" + file)

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

func find_quest(missions, key: String) -> Dictionary:
	for scope in ["daily", "weekly"]:
		for quest in missions.data.get(scope, {}).get("quests", []):
			if quest.key == key:
				return quest
	return {}

func run() -> void:
	create_timer(120).timeout.connect(func(): push_error("timeout"); quit(1))
	var login := await http(HTTPClient.METHOD_POST, "/admin/v1/auth/login", {"username": OS.get_environment("SUNI_ADMIN_USER"), "password": OS.get_environment("SUNI_ADMIN_PASSWORD")})
	check(login.status == 200, "Admin signs in")
	var admin: String = login.data.access_token
	var seeded := await http(HTTPClient.METHOD_POST, "/admin/v1/quests/seed", {}, admin)
	check(seeded.status == 200, "Default missions seeded (%s new)" % str(seeded.data.get("added", "?")))
	var events := await http(HTTPClient.METHOD_GET, "/admin/v1/events", null, admin)
	var running := false
	for event in events.data.events:
		running = running or (event.kind == "story" and event.phase == "running")
	if not running:
		var template := await http(HTTPClient.METHOD_GET, "/admin/v1/events/template", null, admin)
		var created := await http(HTTPClient.METHOD_POST, "/admin/v1/events", template.data, admin)
		check(created.status == 201, "Sample story event created")
		var published := await http(HTTPClient.METHOD_POST, "/admin/v1/events/%s/publish" % created.data.id, {}, admin)
		check(published.status == 200 and published.data.phase == "running", "Sample story event published")
	var account = root.get_node("AuthSession")
	check(account.configure(api), "API URL accepted")
	var name := "mission_" + tag
	var reg := await http(HTTPClient.METHOD_POST, "/v1/register", {"username": name, "password": "mission-pass-1", "email": name + "@example.com"})
	check(reg.status == 201 and await account.authenticate(name, "mission-pass-1"), "Player signs in")
	change_scene_to_file("res://scenes/main.tscn")
	await process_frame
	await process_frame
	var lobby = current_scene.menu.get_node("DesktopMainLobby")
	lobby.missions_clock = 0.0
	check(await until(func(): return lobby.mission_dot.visible, 10.0), "Red dot: the check-in reward is waiting")
	lobby.nav_tabs[lobby.NAV_MISSIONS].button.pressed.emit()
	var missions = lobby.store_pages.missions
	check(await until(func(): return missions.state == "ok", 10.0), "Mission window loads from the API")
	check(missions.data.daily.quests.size() >= 5 and missions.data.weekly.quests.size() >= 3, "Daily and weekly missions listed")
	var d01 := find_quest(missions, "D01")
	check(d01.get("status", "") == "completed", "D01 check-in completed")
	await capture("missions-daily.png")
	var gold := int(root.get_node("UIState").profile.get("gold", 0))
	var card = missions.list.find_child("Quest_D01", true, false)
	card.find_child("Claim", true, false).pressed.emit()
	check(await until(func(): return not missions.busy and find_quest(missions, "D01").get("status", "") == "claimed", 10.0), "D01 claimed through the button")
	check(await until(func(): return int(root.get_node("UIState").profile.get("gold", 0)) == gold + 100, 5.0), "Wallet +100 xu")
	check(await until(func(): return not lobby.mission_dot.visible or int(missions.data.claimable) == 0, 3.0), "Red dot clears when nothing is left to claim")
	missions.set_tab("story")
	check(missions.list.find_child("Chapter_CH01", true, false) != null and missions.list.find_child("Chapter_CH07", true, false) != null, "Story tab shows 7 chapters")
	await capture("missions-story.png")
	missions.set_tab("event")
	check(missions.list.find_child("EventBanner", true, false) != null and missions.list.find_child("EventShop", true, false) != null, "Event tab: banner and shop")
	var buy = missions.list.find_child("Sku_star_fx", true, false).find_child("Buy", true, false)
	check(buy.disabled and buy.text == "THIẾU VÉ", "Shop item needs more tickets")
	await capture("missions-event.png")
	missions.set_tab("weekly")
	await capture("missions-weekly.png")
	print("PRACTICE_MISSIONS_OK" if not failed else "PRACTICE_MISSIONS_FAILED")
	quit(1 if failed else 0)
