extends SceneTree
## PC mailbox (docs/MAIL.md): the mail button opens it, guests see the sign-in
## note, a server reply fills the list, tabs filter, opening marks read and
## lowers the badge, rewards show with NHẬN QUÀ (disabled once claimed).
## Set SUNI_CAPTURE_DIR to save a screenshot (needs a display).
var failed := false
var checks := 0
var capture_dir := OS.get_environment("SUNI_CAPTURE_DIR")

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
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

func iso(hours_ago: float) -> String:
	return Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system() - hours_ago * 3600.0)) + "+00:00"

func run() -> void:
	create_timer(60).timeout.connect(func(): quit(1))
	change_scene_to_file("res://scenes/main.tscn")
	await frames()
	var game = current_scene
	game.set_process(false)
	var lobby = game.pc_screens["lobby"]
	var button: Button = lobby.find_child("Mail", true, false)
	button.pressed.emit()
	await frames()
	var page = lobby.store_pages.get("mail")
	check(lobby.store.visible and page != null and page.visible and lobby.store_title.text == "HỘP THƯ", "Mail button opens the mailbox")
	check(page.state == "signed_out", "Guest sees the sign-in note")
	page.apply({"unread": 3, "claimable": 2, "messages": [
		{"id": "m1", "category": "admin", "sender": "Ban điều hành", "title": "Quà tặng tri ân cộng đồng mừng phiên bản mới!", "body": "Xin chào các Boom thủ!\nCảm ơn các bạn đã luôn đồng hành cùng BỤP BỤP!", "rewards": [{"type": "gold", "amount": 2000, "name": "Vàng"}, {"type": "gem", "amount": 50, "name": "Kim cương"}, {"type": "item", "amount": 5, "item_id": "bomb", "name": "Bom", "icon": "bombs/strong_black.png"}, {"type": "item", "amount": 3, "item_id": "star", "name": "Sao", "icon": "bombs/star.png"}], "has_rewards": true, "read": false, "claimed": false, "claimable": true, "created_at": iso(0.5), "expires_at": iso(-700)},
		{"id": "m2", "category": "system", "sender": "Hệ thống", "title": "Bạn đã nhận được phần thưởng đăng nhập ngày 7", "body": "", "rewards": [], "has_rewards": false, "read": false, "claimed": false, "claimable": false, "created_at": iso(1.5), "expires_at": iso(-700)},
		{"id": "m3", "category": "event", "sender": "Sự kiện", "title": "Tham gia sự kiện Lễ Hội Nước – Nhận quà cực hot!", "body": "", "rewards": [{"type": "gem", "amount": 10, "name": "Kim cương"}], "has_rewards": true, "read": false, "claimed": false, "claimable": true, "created_at": iso(26), "expires_at": iso(-700)},
		{"id": "m4", "category": "maintenance", "sender": "Bảo trì máy chủ", "title": "Thông báo bảo trì định kỳ ngày 25/06", "body": "", "rewards": [], "has_rewards": false, "read": true, "claimed": false, "claimable": false, "created_at": iso(80), "expires_at": iso(-700)},
		{"id": "m5", "category": "reward", "sender": "Quà đăng nhập", "title": "Phần thưởng đăng nhập ngày 6 của bạn", "body": "", "rewards": [{"type": "gold", "amount": 500, "name": "Vàng"}], "has_rewards": true, "read": true, "claimed": true, "claimable": false, "created_at": iso(100), "expires_at": iso(-700)},
	]})
	lobby.set_mail_badge(3)
	await frames()
	check(page.list.get_child_count() == 5 and page.open_id == "m1", "List shows 5 mails, the newest open")
	check(page.tab_buttons.all.text == "Tất cả (5)" and page.tab_buttons.unread.text == "Chưa đọc (3)", "Tab counts")
	check(page.find_child("Claim", true, false) != null and not page.find_child("Claim", true, false).disabled, "Rewards show with NHẬN QUÀ")
	check(lobby.mail_badge.visible and lobby.mail_badge.text == "3", "Badge shows 3 unread")
	await capture("pc-mail.png")
	page.set_tab("unread")
	await frames()
	check(page.list.get_child_count() == 3, "Unread tab filters")
	page.set_tab("claimed")
	await frames()
	check(page.list.get_child_count() == 1, "Claimed tab filters")
	page.set_tab("all")
	page.open("m2")
	await frames()
	check(page.message("m2").read and lobby.mail_badge.text == "2", "Opening marks read and lowers the badge")
	check(page.find_child("Claim", true, false) == null and page.find_child("Delete", true, false) != null, "No rewards: delete instead of claim")
	page.open("m5")
	await frames()
	var claimed: Button = page.find_child("Claim", true, false)
	check(claimed.disabled and claimed.text == "ĐÃ NHẬN", "Claimed mail shows ĐÃ NHẬN")
	lobby.close_store()
	print("MAIL_OK checks=%d" % checks if not failed else "MAIL_FAILED")
	quit(1 if failed else 0)
