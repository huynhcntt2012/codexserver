extends Node2D
## Lobby and match presentation. The server remains the only gameplay authority.

const Network = preload("res://scripts/network.gd")
const ArenaView = preload("res://scripts/arena_view.gd")
const LobbyView = preload("res://scripts/lobby_view.gd")
const INK := Color("113f6b")
const PANEL := Color("0e365d")
const MUTED := Color("b8d9ed")
const MINT := Color("ffe17b")
const WHITE := Color("effaff")

var net = Network.new()
var arena_view = ArenaView.new()
var lobby_view = LobbyView.new()
var snapshot: Dictionary = {}
var status_label: Label
var phase_label: Label
var panel_title: Label
var panel_subtitle: Label
var connection_label: Label
var room_label: Label
var roster_rows: Array[Panel] = []
var api_input := LineEdit.new()
var arena_input := LineEdit.new()
var username_input := LineEdit.new()
var password_input := LineEdit.new()
var confirm_input := LineEdit.new()
var join_button: Button
var ready_button: Button
var leave_button: Button
var guest_button: Button
var login_button: Button
var register_button: Button
var logout_button: Button
var account_hint: Label
var login_mode := false
var register_mode := false
var form := Control.new()
var lobby := Control.new()
var guest_hint: Label
var overlay: Panel
var overlay_title: Label
var overlay_detail: Label
var overlay_tag: Label
var move_timer := 0.0
var move_direction := ""
var was_connected := false
var elapsed := 0.0
var readiness: ColorRect
var readiness_fill: ColorRect
var readiness_label: Label
var last_overlay_key := ""
var character_dialog: AcceptDialog
var result_avatar: TextureRect
var room_browser = preload("res://scripts/room_browser.gd").new()
var room_poll := 0.0
var launch_view: Control


func _ready() -> void:
	add_child(net)
	add_child(arena_view)
	add_child(lobby_view)
	_build_ui()
	_build_characters()
	add_child(room_browser)
	room_browser.hide()
	room_browser.join_requested.connect(_enter_room)
	room_browser.create_requested.connect(func(): _enter_room("", true))
	room_browser.refresh_requested.connect(func(): net.list_rooms(arena_input.text))
	room_browser.back_requested.connect(func(): net.logout(); room_browser.hide(); _refresh_lobby())
	net.rooms_opened.connect(func(): room_browser.profile.text = net.account_name if not net.account_name.is_empty() else "Khách"; room_browser.show(); _refresh_lobby())
	net.rooms_received.connect(room_browser.render_rooms)
	_setup_inputs()
	net.snapshot_received.connect(_on_snapshot)
	net.status_changed.connect(_on_status)
	net.account_changed.connect(_on_account_changed)
	_set_login_mode(true)
	launch_view = preload("res://scripts/launch_view.gd").new()
	launch_view.setup(self)
	add_child(launch_view)
	_refresh_lobby()


func _style(background: Color, border: Color, radius := 24) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 14
	box.content_margin_right = 14
	return box


func _panel(parent: Node, rect: Rect2, color := PANEL) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(color, Color("376c91"), 28))
	parent.add_child(panel)
	return panel


func _label(parent: Node, text: String, rect: Rect2, size := 18, color := WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, rect: Rect2, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", INK if primary else WHITE)
	button.add_theme_color_override("font_hover_color", INK if primary else WHITE)
	button.add_theme_color_override("font_pressed_color", INK if primary else WHITE)
	button.add_theme_color_override("font_disabled_color", Color("68838b"))
	button.add_theme_stylebox_override("normal", _style(Color("ffda6c") if primary else Color("18527d"), MINT if primary else Color("376c91")))
	button.add_theme_stylebox_override("hover", _style(Color("ffe89a") if primary else Color("246b94"), MINT))
	button.add_theme_stylebox_override("pressed", _style(Color("ffd16a") if primary else Color("16466c"), MINT))
	button.add_theme_stylebox_override("disabled", _style(Color("244561"), Color("376c91")))
	parent.add_child(button)
	return button


func _field(field: LineEdit, hint: String, value: String, y: float) -> void:
	field.position = Vector2(784, y)
	field.size = Vector2(440, 40)
	field.placeholder_text = hint
	field.text = value
	field.add_theme_font_size_override("font_size", 16)
	field.add_theme_color_override("font_color", WHITE)
	field.add_theme_color_override("font_placeholder_color", MUTED)
	field.add_theme_stylebox_override("normal", _style(Color("102f50"), Color("376c91"), 8))
	field.add_theme_stylebox_override("focus", _style(Color("102f50"), MINT, 8))
	form.add_child(field)


func _build_ui() -> void:
	# Background panels sit behind the separately rendered arena.
	var board_panel := _panel(self, Rect2(28, 124, 704, 624), Color("0e365d"))
	move_child(board_panel, 0)
	_panel(self, Rect2(756, 124, 496, 624))
	_label(self, "BỤP BỤP!", Rect2(30, 24, 270, 52), 38, MINT)
	_label(self, "ĐẤU TRƯỜNG BÓNG NƯỚC", Rect2(280, 36, 500, 36), 22)
	_label(self, "ĐẶT BÓNG. NÉ NHANH. CHƠI CÙNG NHAU.", Rect2(32, 78, 660, 26), 14, MUTED)
	_panel(self, Rect2(1018, 34, 234, 42), Color("18527d"))
	connection_label = _label(self, "●  CHƯA KẾT NỐI", Rect2(1034, 40, 210, 30), 14, MINT)
	phase_label = _label(self, "VƯỜN KẸO NGỌT   /   SÂN ĐẤU 01", Rect2(50, 721, 660, 23), 13, MUTED)
	panel_title = _label(self, "VÀO SÂN ĐẤU", Rect2(784, 148, 440, 32), 26)
	panel_subtitle = _label(self, "Một trận vui, thêm vài người bạn.", Rect2(784, 183, 440, 24), 15, MUTED)
	add_child(form)
	guest_button = _button(form, "Chơi khách", Rect2(784, 222, 140, 42))
	login_button = _button(form, "Đăng nhập", Rect2(934, 222, 140, 42))
	register_button = _button(form, "Đăng ký", Rect2(1084, 222, 140, 42))
	guest_button.pressed.connect(func(): _set_login_mode(false))
	login_button.pressed.connect(func(): _set_login_mode(true))
	register_button.pressed.connect(func(): _set_auth_mode("register"))
	guest_hint = _label(form, "Vào chơi ngay, không cần tài khoản.\nTên người chơi sẽ được tạo tự động.", Rect2(800, 286, 408, 80), 18, MINT)
	_field(username_input, "Tên tài khoản (3–24 ký tự: a-z, 0-9, _)", "", 278)
	_field(password_input, "Mật khẩu (10–128 ký tự)", "", 326)
	password_input.secret = true
	_field(confirm_input, "Nhập lại mật khẩu", "", 374)
	confirm_input.secret = true
	for field in [username_input, password_input, confirm_input]:
		field.text_submitted.connect(func(_value: String): _join())
	_label(form, "ĐỊA CHỈ MÁY CHỦ", Rect2(784, 424, 440, 22), 12, MUTED)
	_field(api_input, "API URL", _env("SUNI_API_URL", "https://api.sunifactory.com"), 450)
	_field(arena_input, "Arena URL", _env("SUNI_ARENA_URL", "https://arena.sunifactory.com"), 498)
	api_input.tooltip_text = "API: đăng nhập và tài khoản"
	arena_input.tooltip_text = "Arena: kết nối trận đấu"
	join_button = _button(form, "Chọn phòng  →", Rect2(784, 550, 440, 52), true)
	join_button.pressed.connect(_join)
	account_hint = _label(form, "", Rect2(784, 608, 440, 36), 13, MUTED)
	account_hint.clip_text = true
	logout_button = _button(form, "Đăng xuất", Rect2(784, 648, 440, 32))
	logout_button.pressed.connect(func():
		net.logout()
		_clear_match()
		_set_login_mode(true)
		_on_status("Đã đăng xuất. Nhập tài khoản để đăng nhập lại.")
	)
	add_child(lobby)
	room_label = _label(lobby, "", Rect2(784, 217, 440, 23), 14, MINT)
	readiness = ColorRect.new()
	readiness.position = Vector2(784, 536)
	readiness.size = Vector2(440, 4)
	readiness.color = Color("376c91")
	readiness.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lobby.add_child(readiness)
	readiness_fill = ColorRect.new()
	readiness_fill.color = MINT
	readiness_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readiness.add_child(readiness_fill)
	readiness_label = _label(lobby, "", Rect2(784, 661, 440, 22), 12, MUTED)
	for i in range(8):
		var row := _panel(lobby, Rect2(784, 249 + i * 36, 440, 32), Color("18527d"))
		_label(row, "", Rect2(12, 3, 276, 26), 15)
		var state := _label(row, "", Rect2(286, 3, 142, 26), 12, MUTED)
		state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		roster_rows.append(row)
		var accent := ColorRect.new()
		accent.position = Vector2(0, 9)
		accent.size = Vector2(3, 14)
		accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(accent)
	ready_button = _button(lobby, "Sẵn sàng  [R]", Rect2(784, 554, 440, 50), true)
	ready_button.pressed.connect(func(): net.send_action("ready"))
	leave_button = _button(lobby, "Rời phòng", Rect2(784, 616, 440, 42))
	leave_button.pressed.connect(_leave)
	var credits_button := _button(self, "Thông tin & bản quyền", Rect2(784, 688, 440, 36))
	credits_button.add_theme_font_size_override("font_size", 13)
	var credits := AcceptDialog.new()
	credits.title = "Bụp Bụp! / Credits & licenses"
	credits.min_size = Vector2i(720, 480)
	var text := RichTextLabel.new()
	text.custom_minimum_size = Vector2(680, 420)
	text.text = "Suni Bomb Arena / Original code and vector companions\n"
	text.text += "Copyright (c) 2026 Suni Bomb Arena contributors / MIT\n\n"
	text.text += Engine.get_license_text() + "\n\n"
	text.text += FileAccess.get_file_as_string("res://licenses/GODOT_COPYRIGHT.txt")
	credits.add_child(text)
	add_child(credits)
	credits_button.pressed.connect(func(): credits.popup_centered())
	overlay = _panel(self, Rect2(176, 334, 408, 168), Color("0e365d"))
	overlay_tag = _label(overlay, "VƯỜN KẸO NGỌT", Rect2(16, 14, 376, 24), 13, MINT)
	overlay_title = _label(overlay, "CHƠI CÙNG BẠN BÈ", Rect2(16, 42, 376, 52), 27)
	overlay_detail = _label(overlay, "Chọn Chơi khách để vào sảnh chờ.\n2–8 người chơi · Một người sống cuối cùng.", Rect2(16, 102, 376, 52), 15, MUTED)
	result_avatar = TextureRect.new()
	result_avatar.position = Vector2(220, 128)
	result_avatar.size = Vector2(140, 182)
	result_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	overlay.add_child(result_avatar)
	for label in [overlay_tag, overlay_title, overlay_detail]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		overlay_title.clip_text = true
	_panel(self, Rect2(28, 764, 1224, 40), Color("0e365d"))
	status_label = _label(self, "Chào bạn! Đăng nhập hoặc chọn Chơi thử để bắt đầu.", Rect2(44, 768, 770, 32), 13, MUTED)
	status_label.clip_text = true
	status_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_label(self, "WASD / ↑↓←→   Di chuyển      SPACE   Đặt bóng", Rect2(830, 774, 412, 24), 13, MINT)


func _setup_inputs() -> void:
	var bindings := {"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"place_bomb": [KEY_SPACE], "ready_match": [KEY_R]}
	for action in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)


func _env(key: String, fallback: String) -> String:
	var value := OS.get_environment(key)
	return fallback if value.is_empty() else value


func _set_login_mode(enabled: bool) -> void:
	_set_auth_mode("login" if enabled else "guest")


func _set_auth_mode(mode: String) -> void:
	if net.busy:
		return
	login_mode = mode != "guest"
	register_mode = mode == "register"
	username_input.visible = login_mode
	password_input.visible = login_mode
	confirm_input.visible = register_mode
	guest_hint.visible = not login_mode
	guest_button.text = "Chơi khách" if login_mode else "● Chơi khách"
	login_button.text = "● Đăng nhập" if mode == "login" else "Đăng nhập"
	register_button.text = "● Đăng ký" if register_mode else "Đăng ký"
	password_input.clear()
	confirm_input.clear()
	_refresh_account()


func _on_account_changed() -> void:
	if net._access_token.is_empty():
		room_browser.hide()
		_refresh_lobby()
	# Registration may succeed even if the arena is offline. Retrying joins with
	# the issued session instead of accidentally registering the same name twice.
	if not net.account_name.is_empty() and register_mode:
		register_mode = false
		confirm_input.hide()
		login_button.text = "● Đăng nhập"
		register_button.text = "Đăng ký"
	_refresh_account()


func _refresh_account() -> void:
	var signed_in: bool = login_mode and not register_mode and net.has_account_session(api_input.text, username_input.text)
	logout_button.visible = not net.account_name.is_empty()
	logout_button.disabled = net.busy
	account_hint.text = "2–8 người / 3 phút mỗi ván / Chơi trực tuyến"
	if register_mode:
		account_hint.text = "Tạo tài khoản xong sẽ chọn phòng hoặc tạo phòng mới."
	elif signed_in:
		account_hint.text = "Đã đăng nhập: %s · Phiên chỉ lưu khi mở game." % net.account_name
	elif login_mode:
		account_hint.text = "Chưa có tài khoản? Chọn Đăng ký để tạo mới."
	account_hint.tooltip_text = account_hint.text
	join_button.text = "Chọn phòng  →"
	if register_mode:
		join_button.text = "Đăng ký & chọn phòng"
	elif login_mode:
		join_button.text = "Chọn phòng  →" if signed_in else "Đăng nhập & chọn phòng"


func _join() -> void:
	if net.busy or net.connected:
		return
	if login_mode:
		var username := username_input.text.strip_edges()
		var valid_name := RegEx.new()
		valid_name.compile("^[a-z0-9_]{3,24}$")
		if valid_name.search(username) == null:
			_on_status("Tên tài khoản cần 3–24 ký tự: chữ thường a-z, số hoặc dấu _.")
			username_input.grab_focus()
			return
		var reuse_session: bool = not register_mode and password_input.text.is_empty() and net.has_account_session(api_input.text, username)
		if not reuse_session and (password_input.text.length() < 10 or password_input.text.length() > 128):
			_on_status("Mật khẩu cần từ 10 đến 128 ký tự. Hãy nhập lại để đăng nhập.")
			password_input.grab_focus()
			return
		if register_mode and password_input.text != confirm_input.text:
			_on_status("Mật khẩu nhập lại chưa khớp.")
			confirm_input.grab_focus()
			return
	get_viewport().gui_release_focus()
	snapshot = {}
	arena_view.clear()
	var username := username_input.text if login_mode else ""
	var password := password_input.text if login_mode else ""
	net.join_game(api_input.text, arena_input.text, username, password, register_mode, true)
	password_input.clear()
	confirm_input.clear()


func _enter_room(room_id: String, create := false) -> void:
	net.join_selected(arena_input.text, room_id, create)


func _leave() -> void:
	net.disconnect_game()
	_clear_match()
	room_browser.show()
	_refresh_lobby()
	net.list_rooms(arena_input.text)


func _clear_match() -> void:
	snapshot = {}
	arena_view.clear()
	move_timer = 0
	move_direction = ""
	_refresh_lobby()


func _on_status(message: String) -> void:
	status_label.text = message
	room_browser.status.text = message
	status_label.tooltip_text = message
	if not net.connected and was_connected:
		_clear_match()


func _on_snapshot(value: Dictionary) -> void:
	snapshot = value
	arena_view.set_snapshot(value, net.session_id)
	_refresh_lobby()


func _refresh_lobby() -> void:
	var connected: bool = net.connected
	if connected:
		room_browser.hide()
	form.visible = not connected and not room_browser.visible
	lobby.visible = connected
	var phase: String = snapshot.get("phase", "waiting")
	var players: Array = snapshot.get("players", [])
	lobby_view.visible = not connected or phase == "waiting"
	lobby_view.connected = connected
	lobby_view.snapshot = snapshot
	lobby_view.local_id = net.session_id
	arena_view.visible = not lobby_view.visible
	var seconds := maxi(0, int(ceil((float(snapshot.get("deadline", 0)) - float(snapshot.get("now", 0))) / 1000.0)))
	panel_title.text = "VÀO SÂN ĐẤU" if not connected else ("SẢNH CHỜ" if phase == "waiting" else "TRẬN ĐẤU")
	panel_subtitle.text = "Một trận vui, thêm vài người bạn." if not connected else "Ván %d  ·  %d / 8 người chơi" % [int(snapshot.get("round", 1)), players.size()]
	room_label.text = "PHÒNG  " + net.room_id.to_upper()
	room_label.tooltip_text = room_label.text
	room_label.clip_text = true
	var own_ready := false
	var ready_count := 0
	var alive_count := 0
	for i in range(8):
		var row := roster_rows[i]
		var name_label := row.get_child(0) as Label
		var state_label := row.get_child(1) as Label
		var accent := row.get_child(2) as ColorRect
		name_label.clip_text = true
		if i >= players.size():
			accent.color = Color("376c91")
			name_label.tooltip_text = ""
			name_label.text = "%02d   Đang chờ người chơi…" % (i + 1)
			name_label.add_theme_color_override("font_color", Color("527481"))
			state_label.text = "TRỐNG"
			state_label.add_theme_color_override("font_color", Color("527481"))
			continue
		var player: Dictionary = players[i]
		var is_you: bool = player.id == net.session_id
		accent.color = ArenaView.COLORS[int(player.slot) % 8]
		name_label.text = "%02d   %s%s" % [int(player.slot) + 1, player.name, "  (bạn)" if is_you else ""]
		name_label.tooltip_text = name_label.text
		name_label.add_theme_color_override("font_color", WHITE)
		var ready: bool = player.ready
		if ready:
			ready_count += 1
		if player.alive:
			alive_count += 1
		if is_you:
			own_ready = ready
		state_label.text = "SẴN SÀNG" if ready else "CHƯA SẴN SÀNG"
		if phase == "playing" or phase == "finished":
			state_label.text = "ĐANG CHƠI" if player.alive else "ĐÃ BỊ LOẠI"
			state_label.add_theme_color_override("font_color", MINT if player.alive else Color("ff927e"))
		else:
			state_label.add_theme_color_override("font_color", MINT if ready else MUTED)
	readiness_fill.size = Vector2(440.0 * ready_count / maxi(2, players.size()), 4)
	readiness_label.text = "%d / %d đã sẵn sàng · Cần ít nhất 2 người chơi" % [ready_count, players.size()]
	if phase != "waiting":
		readiness_fill.size.x = 440.0 * alive_count / maxi(1, players.size())
		readiness_label.text = "%d / %d người chơi còn lại · Space để đặt bóng" % [alive_count, players.size()]
	ready_button.disabled = not connected or phase != "waiting" or own_ready
	ready_button.text = "Đã sẵn sàng · Chờ bạn bè" if own_ready else "Sẵn sàng  [R]"
	if phase == "playing":
		ready_button.text = "Đang thi đấu  ·  %02d:%02d" % [seconds / 60, seconds % 60]
	elif phase == "countdown":
		ready_button.text = "Bắt đầu trong %d…" % seconds
	elif phase == "finished":
		ready_button.text = "Ván tiếp theo sau %d giây" % seconds
	phase_label.text = "VƯỜN KẸO NGỌT   /   SÂN ĐẤU 01"
	if connected:
		phase_label.text = "VƯỜN KẸO NGỌT   /   VÁN %d   /   %s" % [int(snapshot.get("round", 1)), "CHỜ SẴN SÀNG" if phase == "waiting" else "%02d:%02d" % [seconds / 60, seconds % 60]]
	overlay.visible = connected and (phase == "countdown" or phase == "finished")
	var result := phase == "finished"
	overlay.position = Vector2(90, 220) if result else Vector2(176, 334)
	overlay.size = Vector2(580, 420) if result else Vector2(408, 168)
	for label in [overlay_tag, overlay_title, overlay_detail]:
		label.size.x = overlay.size.x - 32
	overlay_detail.position.y = 340 if result else 102
	result_avatar.visible = false
	overlay_tag.text = "VƯỜN KẸO NGỌT"
	overlay_title.text = "CHƠI CÙNG BẠN BÈ"
	overlay_detail.text = "Chọn Chơi khách để vào sảnh chờ.\n2–8 người chơi · Một người sống cuối cùng."
	if connected and phase == "countdown":
		overlay_tag.text = "TẤT CẢ ĐÃ SẴN SÀNG"
		overlay_title.text = str(seconds)
		overlay_detail.text = "Chuẩn bị di chuyển.\nSpace để đặt bóng, nhớ tìm đường thoát!"
	elif connected and phase == "finished":
		overlay_tag.text = "KẾT QUẢ VÁN ĐẤU"
		var winner_name := "HÒA!"
		for player in players:
			if player.id == snapshot.get("winner"):
				result_avatar.texture = ArenaView.Pilot.ART[ArenaView.Pilot.selected if player.id == net.session_id and ArenaView.Pilot.selected >= 0 else int(player.slot) % 5]
				result_avatar.visible = true
				winner_name = "BẠN THẮNG!" if player.id == net.session_id else player.name + " thắng!"
		if snapshot.get("winner") != null and winner_name == "HÒA!":
			winner_name = "Người thắng đã rời phòng"
		overlay_title.text = winner_name
		overlay_title.tooltip_text = winner_name
		overlay_detail.text = "Một ván hay! Chơi thêm ván nữa nhé.\nVề sảnh chờ sau %d giây." % seconds
	var overlay_key := phase + (str(seconds) if phase == "countdown" else "")
	if overlay.visible and overlay_key != last_overlay_key:
		overlay.pivot_offset = overlay.size / 2
		overlay.scale = Vector2.ONE * 0.94
		var tween := create_tween()
		tween.tween_property(overlay, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	last_overlay_key = overlay_key


func _process(delta: float) -> void:
	elapsed += delta
	room_browser.set_busy(net.busy)
	room_poll += delta
	if room_poll >= 5.0 and room_browser.visible and not net.busy and not net.connected:
		room_poll = 0.0
		net.list_rooms(arena_input.text)
	if was_connected != net.connected:
		was_connected = net.connected
		_refresh_lobby()
	join_button.disabled = net.busy or net.connected
	guest_button.disabled = net.busy
	login_button.disabled = net.busy
	register_button.disabled = net.busy
	for field in [api_input, arena_input, username_input, password_input, confirm_input]:
		field.editable = not net.busy
	_refresh_account()
	connection_label.text = "●  ĐÃ KẾT NỐI" if net.connected else ("●  ĐANG KẾT NỐI…" if net.busy else "●  CHƯA KẾT NỐI")
	if net.busy:
		join_button.text = "Đang kết nối…"
	if character_dialog.visible or get_viewport().gui_get_focus_owner() is LineEdit or not net.connected:
		return
	if Input.is_action_just_pressed("ready_match") and not ready_button.disabled:
		net.send_action("ready")
	if snapshot.get("phase") != "playing":
		return
	if Input.is_action_just_pressed("place_bomb"):
		net.send_action("bomb")
	move_timer -= delta
	var direction := ""
	for candidate in ["up", "down", "left", "right"]:
		if Input.is_action_just_pressed("move_" + candidate):
			direction = candidate
			break
	if direction.is_empty() and not move_direction.is_empty() and Input.is_action_pressed("move_" + move_direction):
		direction = move_direction
	if direction.is_empty():
		for candidate in ["up", "down", "left", "right"]:
			if Input.is_action_pressed("move_" + candidate):
				direction = candidate
				break
	if not direction.is_empty() and (direction != move_direction or move_timer <= 0):
		net.send_action(direction)
		arena_view.movement_intent(direction)
		move_timer = 0.15
	move_direction = direction



func _build_characters() -> void:
	character_dialog = AcceptDialog.new()
	character_dialog.title = "Chọn người bạn đồng hành"
	character_dialog.min_size = Vector2i(1080, 380)
	character_dialog.ok_button_text = "Xác nhận chọn"
	character_dialog.add_theme_stylebox_override("panel", _style(Color("0e365d"), Color("376c91")))
	var frame := _style(Color("0e365d"), Color("376c91"))
	frame.set_border_width_all(2)
	frame.border_width_top = 32
	character_dialog.add_theme_stylebox_override("embedded_border", frame)
	character_dialog.add_theme_color_override("title_color", WHITE)
	var confirm := character_dialog.get_ok_button()
	confirm.add_theme_stylebox_override("normal", _style(Color("ffda6c"), Color("ffda6c")))
	confirm.add_theme_color_override("font_color", INK)
	confirm.custom_minimum_size = Vector2(260, 44)
	var content := VBoxContainer.new()
	var hint := Label.new()
	hint.text = "Diện mạo trên máy bạn · Không thay đổi sức mạnh"
	hint.add_theme_color_override("font_color", MUTED)
	content.add_child(hint)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 16)
	content.add_child(cards)
	var names = ArenaView.Pilot.NAMES
	var group := ButtonGroup.new()
	for i in range(5):
		var card := Button.new()
		card.text = names[i]
		card.icon = ArenaView.Pilot.ART[i]
		card.expand_icon = true
		card.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_theme_font_size_override("font_size", 18)
		card.custom_minimum_size = Vector2(196, 280)
		card.toggle_mode = true
		card.button_group = group
		card.add_theme_color_override("font_color", WHITE)
		card.add_theme_stylebox_override("normal", _style(ArenaView.COLORS[i].darkened(0.65), Color("376c91")))
		card.add_theme_stylebox_override("pressed", _style(ArenaView.COLORS[i].darkened(0.35), MINT))
		card.pressed.connect(func(): ArenaView.Pilot.selected = i)
		cards.add_child(card)
	character_dialog.add_child(content)
	add_child(character_dialog)
	var choose := _button(self, "Nhân vật", Rect2(828, 34, 170, 42))
	choose.pressed.connect(func(): character_dialog.popup_centered())


func _draw() -> void:
	draw_texture_rect(preload("res://art/boom/backdrop.png"), Rect2(0, 0, 1280, 820), false)
