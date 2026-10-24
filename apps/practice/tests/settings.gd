extends SceneTree
## Settings window and the Settings autoload (docs/SETTINGS.md): every section
## opens from the lobby gear, switches edit a draft, LƯU stores and applies,
## HỦY / closing put the saved values back, "Sắp có" items cannot be used, the
## chat filter and audio buses work, and rooms open the same window.
## Set SUNI_CAPTURE_DIR to save one screenshot per section (needs a display).
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

func run() -> void:
	create_timer(90).timeout.connect(func(): quit(1))
	var settings = root.get_node("Settings")
	# Keep the tester's own settings file.
	var backup := FileAccess.get_file_as_string(settings.PATH) if FileAccess.file_exists(settings.PATH) else ""
	settings.save(settings.defaults())

	# Autoload: buses, values, filter.
	for bus in ["Music", "SFX", "UI"]:
		check(AudioServer.get_bus_index(bus) > 0 and AudioServer.get_bus_send(AudioServer.get_bus_index(bus)) == "Master", "%s bus sends to Master" % bus)
	check(settings.bus_for("ui_select") == "UI" and settings.bus_for("explosion") == "SFX", "Sounds go to their bus")
	check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))), 0.7), "Music bus at 70 %")
	check(settings.clean_chat("vcl quá đỉnh, Fuck!") == "✱✱✱ quá đỉnh, ✱✱✱✱!", "Chat filter hides blocked words: " + settings.clean_chat("vcl quá đỉnh, Fuck!"))
	check(settings.clean_chat("các bạn ơi cac lon") == "các bạn ơi cac lon", "Filter leaves normal words")
	var custom: Dictionary = settings.defaults()
	custom.audio.music = 30
	custom.game.chat_filter = false
	custom.display.brightness = 20
	settings.save(custom)
	settings.load_values()
	check(int(settings.get_value("audio", "music")) == 30 and not settings.on("game", "chat_filter"), "Saved values load back")
	check(settings.clean_chat("vcl") == "vcl", "Filter off keeps the text")
	check(settings._overlay.visible and settings._overlay.color.a > 0.1, "Low brightness darkens the screen")
	settings.save(settings.defaults())

	change_scene_to_file("res://scenes/main.tscn")
	await frames()
	var game = current_scene
	game.set_process(false)
	var lobby = game.pc_screens["lobby"]
	lobby.open_settings()
	await frames()
	var page = lobby.store_pages.get("settings")
	check(lobby.store.visible and page != null and page.visible and lobby.store_title.text == "CÀI ĐẶT", "Gear opens the settings window")
	check(page.current == "account" and page.find_child("Row_Chế độ khách", true, false) != null, "Guest sees the sign-in row")
	await capture("settings-account-guest.png")

	# Each section builds; "Sắp có" items are greyed and cannot be pressed.
	for key in ["display", "audio", "controls", "game", "language"]:
		page.nav_buttons[key].pressed.emit()
		await frames()
		check(page.current == key and page.nav_buttons[key].button_pressed and page.body.find_children("Row_*", "", true, false).size() >= 3, "%s section builds" % key)
		await capture("settings-%s.png" % key)
	page.show_section("language")
	await frames()
	for code in ["en", "ko", "ja", "zh"]:
		var tile: Button = page.find_child("Tile_" + code, true, false)
		check(tile != null and tile.disabled, "Language %s is marked Sắp có" % code)
	check(not (page.find_child("Tile_vi", true, false) as Button).disabled, "Vietnamese is usable")

	# Điều khiển: one device; its table and options load below.
	page.show_section("controls")
	await frames()
	check(page.find_child("Device_keyboard", true, false).button_pressed and not page.find_child("Device_gamepad", true, false).button_pressed, "Keyboard is the default device")
	check(page.find_child("Panel_keyboard", true, false) != null and page.find_child("Row_Đặt bom", true, false) != null, "Keyboard panel and table")
	check(page.find_child("Slider_deadzone", true, false) == null and page.find_child("Option_vibration", true, false) == null and page.find_child("Option_show_hints", true, false) != null, "Keyboard options: no pad-only ones")
	await capture("settings-controls-keyboard.png")
	page.scroll.scroll_vertical = 300
	await capture("settings-controls-keyboard-details.png")
	page.scroll.scroll_vertical = 0
	page.find_child("Device_gamepad", true, false).pressed.emit()
	await frames()
	check(page.draft.controls.device == "gamepad" and page.find_child("Panel_gamepad", true, false) != null and page.find_child("Panel_keyboard", true, false) == null, "Gamepad panel replaces the keyboard one")
	check(page.find_child("Slider_deadzone", true, false) != null and page.find_child("Option_vibration", true, false) != null, "Gamepad options: vibration and deadzone")
	check(page.find_child("PadStatus", true, false) != null, "Pad status line shows")
	await capture("settings-controls-gamepad.png")
	page.scroll.scroll_vertical = 300
	await capture("settings-controls-gamepad-details.png")
	page.scroll.scroll_vertical = 5000
	await capture("settings-controls-gamepad-options.png")
	page.scroll.scroll_vertical = 0
	check(not settings.gamepad(), "Not applied before LƯU")
	page.find_child("Save", true, false).pressed.emit()
	await frames()
	check(settings.gamepad() and not settings.keyboard(), "LƯU selects the gamepad")
	var press := InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_X
	press.pressed = true
	check(settings.pad_action(press) == "use" and settings.hint("use") == "X", "X uses an item, hint X")
	press.button_index = JOY_BUTTON_A
	check(settings.pad_action(press) == "bomb", "A places a bomb")
	check(load("res://scripts/ui/pc/battle_item_ui.gd").keyed("use", "DÙNG") == "X  DÙNG", "HUD button shows the pad button")
	page.find_child("Device_keyboard", true, false).pressed.emit()
	await frames()
	page.find_child("Save", true, false).pressed.emit()
	await frames()
	check(settings.keyboard() and settings.pad_action(press) == "" and settings.hint("use") == "Ctrl", "Keyboard again: pad ignored, hint Ctrl")
	lobby.open_settings()

	# Draft, LƯU, HỦY.
	page.show_section("game")
	await frames()
	var auto: Button = page.find_child("Switch_auto_ready", true, false)
	auto.button_pressed = true
	check(page.draft.game.auto_ready and not settings.on("game", "auto_ready"), "A switch edits only the draft")
	page.find_child("Save", true, false).pressed.emit()
	await frames()
	check(settings.on("game", "auto_ready") and page.status_label.text == "Đã lưu cài đặt.", "LƯU stores the draft")
	page.show_section("audio")
	await frames()
	var music: HSlider = page.find_child("Slider_music", true, false)
	music.value = 10
	check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))), 0.1), "Volume previews at once")
	page.find_child("Cancel", true, false).pressed.emit()
	await frames()
	check(not lobby.store.visible and int(settings.get_value("audio", "music")) == 70, "HỦY closes without saving")
	check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))), 0.7), "HỦY restores the previewed volume")
	lobby.open_settings()
	page.show_section("display")
	await frames()
	page.find_child("Tile_window", true, false).pressed.emit()
	check(page.draft.display.mode == "window" and not (page.find_child("Resolution", true, false) as OptionButton).disabled, "Window mode enables the resolution list")
	page.find_child("Extra", true, false).pressed.emit()
	await frames()
	check(page.draft.display.mode == "fullscreen" and page.status_label.text.begins_with("Đã đặt lại"), "Khôi phục mặc định resets the section")
	lobby.close_store()
	await frames()
	check(settings.on("game", "auto_ready"), "Saved values survive closing")

	# Signed in (account filled as /v1/me would): name, ID, EXP, password, email, logout.
	var auth = root.get_node("AuthSession")
	auth._token = "test-token"
	auth._deadline = Time.get_ticks_msec() + 600000
	lobby.open_settings()
	page.account_state = "ok"
	page.account = {"id": "a1b2c3d4-0000-4000-8000-000000000001", "name": "BoomPlayer", "guest": false, "username": "boomplayer", "email": "b***@example.com"}
	page.standing = {"exp": {"rank": 1, "value": 700}}
	page.show_section("account")
	await frames()
	check((page.find_child("DisplayName", true, false) as LineEdit).text == "BoomPlayer" and (page.find_child("PlayerId", true, false) as Label).text == "#A1B2C3D4", "Account shows name and short ID")
	for row_name in ["Row_Đổi mật khẩu", "Row_Email", "Row_Đăng xuất", "Row_Liên kết tài khoản", "Row_Bảo mật 2 lớp (2FA)"]:
		check(page.find_child(row_name, true, false) != null, row_name)
	page.open_password()
	check(page.modal.visible and page.modal_title.text == "ĐỔI MẬT KHẨU", "Password form opens")
	page.close_form()
	await capture("settings-account.png")
	auth._token = ""
	lobby.close_store()
	# Rooms and matches open the same window as an overlay.
	var room = game.pc_screens["room"]
	room.open_settings()
	await frames()
	check(room.settings_overlay.visible and room.settings_page.visible, "Room gear opens the settings overlay")
	room.close_settings()
	check(not room.settings_overlay.visible, "Overlay closes")

	settings.save(settings.defaults())
	if backup != "":
		var file := FileAccess.open(settings.PATH, FileAccess.WRITE)
		file.store_string(backup)
		file.close()
	print("SETTINGS_OK checks=%d" % checks if not failed else "SETTINGS_FAILED")
	quit(1 if failed else 0)
