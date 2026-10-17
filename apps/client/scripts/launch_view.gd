extends Control
## Launch presentation reuses the existing account adapter and form controls.

const INK := Color("554b77")
const AQUA := Color("50cfcb")
const CREAM := Color("fff9e9")
var host: Node
var canvas := Control.new()
var backdrop: TextureRect
var title: Label
var subtitle: Label
var server: Label
var status: Label
var remember := CheckBox.new()
var forgot: Button
var info := AcceptDialog.new()
var settings := AcceptDialog.new()
var sound: Button
var preferences := ConfigFile.new()


func setup(owner_node: Node) -> void:
	host = owner_node


func box(color: Color, border := Color.WHITE, radius := 20) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16
	style.content_margin_right = 16
	return style


func place(node: Control, rect: Rect2) -> void:
	node.position = rect.position
	node.size = rect.size


func label(text: String, rect: Rect2, font_size := 16) -> Label:
	var node := Label.new()
	node.text = text
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.add_theme_color_override("font_color", INK)
	node.add_theme_font_size_override("font_size", font_size)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(node)
	place(node, rect)
	return node


func style_button(node: Button, color := CREAM) -> void:
	node.focus_mode = Control.FOCUS_ALL
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var fill := color.lightened(0.15) if state == "hover" else color
		node.add_theme_stylebox_override(state, box(fill, Color("259fb2") if state == "focus" else Color.WHITE))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		node.add_theme_color_override(state, INK)
	node.add_theme_font_size_override("font_size", 16)


func button(text: String, rect: Rect2, action: Callable, color := CREAM) -> Button:
	var node := Button.new()
	node.text = text
	canvas.add_child(node)
	style_button(node, color)
	place(node, rect)
	node.pressed.connect(action)
	return node


func art(asset: String, rect: Rect2) -> TextureRect:
	var node := TextureRect.new()
	node.texture = load("res://art/launch/" + asset + ".png")
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(node)
	place(node, rect)
	return node


func message(text: String) -> void:
	info.dialog_text = text
	info.popup_centered(Vector2i(520, 180))


func _ready() -> void:
	name = "LaunchScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(canvas)
	backdrop = art("bg_lagoon", Rect2(0, 0, 1280, 720))
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art("mascot_pip", Rect2(65, 203, 304, 335))
	art("mascot_nop", Rect2(912, 203, 304, 335))
	art("logo_bupbup", Rect2(380, 11, 520, 177))
	for rect in [Rect2(94, 255, 42, 42), Rect2(343, 224, 23, 23), Rect2(910, 184, 31, 31), Rect2(1170, 298, 46, 46), Rect2(373, 465, 20, 20), Rect2(869, 431, 18, 18), Rect2(1031, 566, 28, 28)]:
		art("fx_bubble", rect)
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", box(CREAM))
	canvas.add_child(panel)
	place(panel, Rect2(398, 287, 484, 323))
	title = label("ĐĂNG NHẬP", Rect2(430, 300, 420, 42), 30)
	subtitle = label("Sẵn sàng vào đấu trường bóng nước?", Rect2(430, 344, 420, 26))
	for child in host.form.get_children():
		child.hide()
	for field in [host.username_input, host.password_input, host.confirm_input]:
		field.reparent(canvas)
		field.add_theme_color_override("font_color", INK)
		field.add_theme_color_override("font_placeholder_color", Color("958ab2"))
		field.add_theme_color_override("caret_color", INK)
		field.add_theme_stylebox_override("normal", box(Color.WHITE, Color("ddd6f4"), 16))
		field.add_theme_stylebox_override("focus", box(Color.WHITE, AQUA, 16))
	place(host.username_input, Rect2(432, 378, 416, 46))
	place(host.password_input, Rect2(432, 432, 416, 46))
	place(host.confirm_input, Rect2(432, 483, 416, 40))
	host.username_input.placeholder_text = "Tên tài khoản"
	host.username_input.max_length = 24
	host.password_input.placeholder_text = "Mật khẩu"
	host.password_input.max_length = 128
	host.confirm_input.max_length = 128
	for connection in host.username_input.text_submitted.get_connections():
		host.username_input.text_submitted.disconnect(connection.callable)
	host.username_input.text_submitted.connect(func(_text): host.password_input.grab_focus())
	for node in [host.join_button, host.guest_button, host.login_button, host.register_button, host.logout_button]:
		node.reparent(canvas)
		node.show()
		style_button(node)
	place(host.join_button, Rect2(432, 530, 262, 58))
	style_button(host.join_button, Color("ffce75"))
	place(host.guest_button, Rect2(706, 530, 142, 58))
	style_button(host.guest_button, Color("9ce8df"))
	host.guest_button.pressed.connect(func(): host._join())
	place(host.login_button, Rect2(476, 655, 160, 45))
	place(host.register_button, Rect2(646, 655, 160, 45))
	place(host.logout_button, Rect2(1035, 105, 210, 40))
	canvas.add_child(remember)
	remember.text = "Nhớ tên đăng nhập"
	remember.add_theme_color_override("font_color", INK)
	place(remember, Rect2(432, 483, 220, 36))
	preferences.load("user://launch_preferences.cfg")
	remember.button_pressed = preferences.get_value("login", "remember", false)
	if remember.button_pressed:
		host.username_input.text = preferences.get_value("login", "username", "")
	remember.toggled.connect(func(_enabled): save_preferences())
	host.username_input.text_changed.connect(func(_text): save_preferences())
	forgot = button("Quên mật khẩu?", Rect2(684, 483, 164, 36), func(): message("Chưa hỗ trợ đặt lại mật khẩu trong phiên bản này."))
	var chip := Panel.new()
	chip.add_theme_stylebox_override("panel", box(CREAM))
	canvas.add_child(chip)
	place(chip, Rect2(35, 39, 229, 63))
	label("MÁY CHỦ BỤP BỤP", Rect2(45, 44, 209, 22), 14)
	server = label("Chưa kết nối", Rect2(45, 70, 209, 25), 14)
	button("CÀI ĐẶT", Rect2(1008, 45, 116, 48), func(): settings.popup_centered(Vector2i(560, 320)))
	sound = button("ÂM: BẬT", Rect2(1132, 45, 116, 48), toggle_sound)
	AudioServer.set_bus_mute(0, preferences.get_value("audio", "muted", false))
	button("1P\nCHƠI ĐƠN", Rect2(266, 485, 116, 68), func(): message("Mỗi máy điều khiển một nhân vật. Chọn Chơi thử để vào phòng bằng tài khoản khách."), AQUA)
	button("2P\nCHƠI ĐÔI", Rect2(899, 485, 116, 68), func(): message("Chơi cùng bạn bằng hai máy: đăng nhập, rồi chọn cùng một phòng. Chưa hỗ trợ hai người trên một bàn phím."), Color("e4d6f6"))
	button("HƯỚNG DẪN", Rect2(306, 655, 160, 45), func(): message("WASD / phím mũi tên: di chuyển\nSpace: đặt bóng nước · R: sẵn sàng\nChọn phòng hoặc tạo phòng để chơi cùng bạn."))
	button("THOÁT", Rect2(816, 655, 160, 45), func(): get_tree().quit())
	status = label("", Rect2(398, 615, 484, 32), 13)
	status.clip_text = true
	status.add_theme_stylebox_override("normal", box(CREAM, Color.WHITE, 10))
	add_child(info)
	info.title = "Bụp Bụp!"
	add_child(settings)
	settings.title = "Cài đặt"
	var content := VBoxContainer.new()
	settings.add_child(content)
	var full := CheckButton.new()
	full.text = "Toàn màn hình"
	full.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	full.toggled.connect(func(enabled): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED))
	content.add_child(full)
	var caption := Label.new()
	caption.text = "Âm lượng"
	content.add_child(caption)
	var volume := HSlider.new()
	volume.max_value = 100
	volume.value = preferences.get_value("audio", "volume", 80.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(volume.value / 100.0))
	volume.value_changed.connect(func(value):
		AudioServer.set_bus_volume_db(0, linear_to_db(value / 100.0))
		preferences.set_value("audio", "volume", value)
		preferences.save("user://launch_preferences.cfg")
	)
	content.add_child(volume)
	for field in [host.api_input, host.arena_input]:
		field.reparent(content)
		field.show()
		field.custom_minimum_size = Vector2(500, 44)
	button("SỰ KIỆN", Rect2(35, 115, 229, 44), func(): message("Chưa có sự kiện đang diễn ra. Hẹn gặp bạn trong đấu trường bóng nước!"))
	status.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			message(host.status_label.text)
	)
	var focus_order: Array[Control] = [host.username_input, host.password_input, remember, forgot, host.join_button, host.guest_button]
	for i in range(focus_order.size()):
		focus_order[i].focus_next = focus_order[i].get_path_to(focus_order[(i + 1) % focus_order.size()])
		focus_order[i].focus_previous = focus_order[i].get_path_to(focus_order[(i - 1 + focus_order.size()) % focus_order.size()])
	host.password_input.focus_next = host.password_input.get_path_to(remember)
	host.username_input.grab_focus()


func save_preferences() -> void:
	preferences.set_value("login", "remember", remember.button_pressed)
	preferences.set_value("login", "username", host.username_input.text if remember.button_pressed else "")
	preferences.save("user://launch_preferences.cfg")


func toggle_sound() -> void:
	AudioServer.set_bus_mute(0, not AudioServer.is_bus_mute(0))
	preferences.set_value("audio", "muted", AudioServer.is_bus_mute(0))
	preferences.save("user://launch_preferences.cfg")


func _process(_delta: float) -> void:
	visible = host.form.visible
	var viewport := get_viewport_rect().size
	var ratio := minf(viewport.x / 1280.0, viewport.y / 720.0)
	canvas.scale = Vector2.ONE * ratio
	canvas.position = (viewport - Vector2(1280, 720) * ratio) / 2
	place(backdrop, Rect2(-canvas.position / ratio, viewport / ratio))
	if not visible:
		return
	title.text = "ĐĂNG KÝ" if host.register_mode else ("ĐĂNG NHẬP" if host.login_mode else "CHƠI THỬ")
	host.username_input.visible = host.login_mode
	host.password_input.visible = host.login_mode
	host.confirm_input.visible = host.register_mode
	host.password_input.focus_next = host.password_input.get_path_to(host.confirm_input if host.register_mode else remember)
	host.confirm_input.focus_next = host.confirm_input.get_path_to(host.join_button)
	remember.visible = host.login_mode and not host.register_mode
	forgot.visible = remember.visible
	host.join_button.text = "ĐANG KẾT NỐI…" if host.net.busy else ("TẠO TÀI KHOẢN" if host.register_mode else "VÀO TRẬN")
	host.guest_button.text = "CHƠI THỬ"
	host.login_button.text = "ĐĂNG NHẬP"
	host.register_button.text = "ĐĂNG KÝ"
	subtitle.text = "Chơi khách · Không cần tạo tài khoản" if not host.login_mode else "Sẵn sàng vào đấu trường bóng nước?"
	server.text = "Đang kết nối…" if host.net.busy else "Chưa kết nối"
	status.text = host.status_label.text
	status.tooltip_text = status.text
	status.mouse_filter = Control.MOUSE_FILTER_STOP
	sound.text = "ÂM: TẮT" if AudioServer.is_bus_mute(0) else "ÂM: BẬT"
