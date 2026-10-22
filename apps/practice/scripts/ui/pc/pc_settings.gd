extends "res://scripts/ui/pc/pc_kit.gd"
## PC settings window (docs/SETTINGS.md): Tài khoản, Hình ảnh, Âm thanh, Thiết bị
## điều khiển, Trò chơi, Ngôn ngữ. Options edit a draft of the Settings autoload;
## volumes preview at once, LƯU applies and stores everything (and a new display
## name), HỦY / closing puts the saved values back. Options the game cannot do yet
## are shown greyed with "Sắp có" instead of pretending to work.
signal navigate(destination: String)

const SECTIONS := [
	["account", "user", "Tài khoản", "Thông tin và bảo mật"],
	["display", "monitor", "Hình ảnh", "Đồ họa và hiển thị"],
	["audio", "speaker", "Âm thanh", "Nhạc, hiệu ứng, giao diện"],
	["controls", "pad", "Điều khiển", "Bàn phím và tay cầm"],
	["game", "gear", "Trò chơi", "Thiết lập gameplay"],
	["language", "globe", "Ngôn ngữ", "Ngôn ngữ và khu vực"],
]
const INTRO := {
	"account": "Quản lý thông tin tài khoản và bảo mật của bạn.",
	"display": "Tùy chỉnh đồ họa và hiển thị để chơi mượt nhất trên máy của bạn.",
	"audio": "Điều chỉnh âm lượng và thiết bị âm thanh.",
	"controls": "Chọn 1 loại thiết bị để chơi game. Chỉ có thể chọn một.",
	"game": "Tùy chỉnh các thiết lập trong trận.",
	"language": "Ngôn ngữ hiển thị, máy chủ và trò chuyện.",
}
## [icon, action, keys, icon colour] for the two device tables.
const KEY_ROWS := [
	["plus", "Di chuyển", ["W", "A", "S", "D", "/", "↑", "←", "↓", "→"], "3b9bf0"],
	["dot", "Đặt bom", ["Space"], "2d4a7a"],
	["star", "Dùng vật phẩm", ["Ctrl"], "ffb432"],
	["gem", "Chọn vật phẩm", ["1 – 6"], "a98bf0"],
	["people", "Cưỡi thú", ["Q"], "44cf9e"],
	["close", "Tạm dừng / rời trận", ["Esc"], "ff7083"],
	["home", "Chơi lại (luyện tập)", ["R"], "4fb7f5"],
]
const PAD_ROWS := [
	["plus", "Di chuyển", [["Cần trái / D-pad", Color("5a6b8c")]], "a98bf0"],
	["dot", "Đặt bom", [["A", Color("3fb95a")]], "2d4a7a"],
	["star", "Dùng vật phẩm", [["X", Color("2f8cf0")]], "ffb432"],
	["people", "Cưỡi thú", [["B", Color("e5484d")]], "44cf9e"],
	["gem", "Chọn vật phẩm", [["LB", Color("2d4a7a")], ["RB", Color("2d4a7a")]], "a98bf0"],
	["close", "Tạm dừng / rời trận", [["Start", Color("5a6b8c")]], "ff7083"],
	["check", "Trong menu: xác nhận / quay lại", [["A", Color("3fb95a")], ["B", Color("e5484d")]], "44cf9e"],
]
const PREVIEW := {"master": "collect", "sfx": "explosion", "ui": "ui_select"}
const FIELD := Color("e4f1ff")
const PANEL_BG := Color("f2f8ff")

## Toggle switch (pill + knob), sky blue when on.
class Switch extends Button:
	func _init(on := false) -> void:
		toggle_mode = true
		button_pressed = on
		flat = true
		focus_mode = Control.FOCUS_ALL
		custom_minimum_size = Vector2(74, 38)
		toggled.connect(func(_v): queue_redraw())

	func _draw() -> void:
		var r := Rect2(Vector2(0, (size.y - 34) / 2), Vector2(size.x, 34))
		var fill := Color("2f8cf0") if button_pressed else Color("c9d3e2")
		if disabled:
			fill = Color("dfe5ee")
		draw_rect(Rect2(r.position + Vector2(17, 0), Vector2(r.size.x - 34, 34)), fill)
		draw_circle(r.position + Vector2(17, 17), 17, fill)
		draw_circle(r.position + Vector2(r.size.x - 17, 17), 17, fill)
		var knob := r.position + Vector2(r.size.x - 17 if button_pressed else 17, 17)
		draw_circle(knob, 13, Color.WHITE)

var draft: Dictionary = {}
var current := "account"
var nav_buttons: Dictionary = {}
var head_icon: Control
var head_title: Label
var head_intro: Label
var body: VBoxContainer
var scroll: ScrollContainer
var extra_button: Button
var status_label: Label
var account: Dictionary = {}  # /v1/me
var standing: Dictionary = {}  # /v1/leaderboards "me"
var account_state := "idle"
var name_field: LineEdit
var preview_player: AudioStreamPlayer
var hero_id := "bombo"
var row_parent: Control  # where option_row() puts rows (body, or a two-column grid)  # portrait on the account card; set by whoever opens the window

func _init() -> void:
	super("sky")

func _ready() -> void:
	name = "PcSettings"
	setup()
	preview_player = AudioStreamPlayer.new()
	add_child(preview_player)
	var root := page(canvas, 0)
	var split := row(16, root)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Left: sections.
	var nav_card := card(Color("1d4f96"), Color("123b75"), 22, 2, 10)
	nav_card.custom_minimum_size = Vector2(300, 0)
	split.add_child(nav_card)
	var nav := column(10, nav_card)
	for spec in SECTIONS:
		var key: String = spec[0]
		var button := nav_button(spec)
		button.pressed.connect(func(): show_section(key))
		nav.add_child(button)
		nav_buttons[key] = button
	# Right: header, options, footer.
	var panel := card(PANEL_BG, Color("cfe3f7"), 22, 2, 16)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(panel)
	var col := column(10, panel)
	var head := row(16, col)
	head_icon = Glyph.new("user", NAVY, 56)
	head.add_child(head_icon)
	var titles := column(2, head)
	head_title = title_text("", 30, NAVY, titles)
	head_title.remove_theme_constant_override("outline_size")
	head_intro = text("", 17, INK, titles)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	body = column(8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var foot := row(14, col)
	extra_button = candy("", func(): pass, "ghost", 17)
	extra_button.name = "Extra"
	extra_button.custom_minimum_size = Vector2(230, 52)
	foot.add_child(extra_button)
	status_label = stretch(text("", 15, MUTED, foot))
	var cancel := candy("HỦY", cancel_changes, "sky", 20)
	cancel.name = "Cancel"
	cancel.custom_minimum_size = Vector2(170, 52)
	foot.add_child(cancel)
	var save := candy("LƯU", save_changes, "sun", 22)
	save.name = "Save"
	save.custom_minimum_size = Vector2(220, 52)
	foot.add_child(save)
	build_modal()
	visibility_changed.connect(_on_visibility)
	draft = Settings.draft()
	show_section(current)

func _on_visibility() -> void:
	if is_visible_in_tree():
		draft = Settings.draft()
		account_state = "idle"
		show_section(current)
	else:
		# Closed without LƯU: the saved values come back (previewed volumes too).
		Settings.apply(Settings.values)
		preview_player.stop()

func nav_button(spec: Array) -> Button:
	var button := Button.new()
	button.name = "Nav_" + str(spec[0])
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(0, 92)
	button.focus_mode = Control.FOCUS_ALL
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var on: bool = state in ["pressed", "hover_pressed"]
		var style := box(SUN if on else Color("2a63b5"), Color("e39b14") if on else Color("3b78cc"), 16, 2, 10)
		if state == "hover":
			style.bg_color = Color("3270c4")
		if state == "focus":
			style = box(Color.TRANSPARENT, Color(1, 1, 1, 0.8), 16, 3, 10)
		button.add_theme_stylebox_override(state, style)
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 16
	line.offset_right = -14
	line.add_theme_constant_override("separation", 14)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(line)
	var icon := Glyph.new(str(spec[1]), Color.WHITE, 40)
	icon.name = "Icon"
	line.add_child(icon)
	var words := column(0, line)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := text(str(spec[2]), 20, Color.WHITE, words)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.name = "Title"
	var sub := text(str(spec[3]), 14, Color("d6e8ff"), words)
	sub.name = "Sub"
	var arrow := Glyph.new("right", Color.WHITE, 22)
	arrow.name = "Arrow"
	line.add_child(arrow)
	return button

func show_section(key: String) -> void:
	current = key
	for k in nav_buttons:
		var button: Button = nav_buttons[k]
		var on: bool = k == key
		button.set_pressed_no_signal(on)
		var ink := NAVY if on else Color.WHITE
		(button.find_child("Icon", true, false) as Control).set("tint", ink)
		(button.find_child("Arrow", true, false) as Control).set("tint", ink)
		(button.find_child("Title", true, false) as Label).add_theme_color_override("font_color", ink)
		(button.find_child("Sub", true, false) as Label).add_theme_color_override("font_color", NAVY.lightened(0.15) if on else Color("d6e8ff"))
	var spec: Array = SECTIONS.filter(func(s): return s[0] == key)[0]
	head_icon.set_kind(str(spec[1]))
	head_title.text = str(spec[2]).to_upper()
	head_intro.text = INTRO[key]
	status_label.text = ""
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	for connection in extra_button.pressed.get_connections():
		extra_button.pressed.disconnect(connection.callable)
	extra_button.visible = true
	if key == "audio":
		extra_button.text = "▶  Nghe thử tất cả"
		extra_button.pressed.connect(preview_all)
	elif key in ["display", "game", "audio", "language", "controls"]:
		extra_button.text = "↺  Khôi phục mặc định"
		extra_button.pressed.connect(reset_section)
	else:
		extra_button.visible = false
	row_parent = body
	call("build_" + key)
	scroll.scroll_vertical = 0

# ---------------------------------------------------------------- building blocks

## A white option row: icon, title + hint, then the control on the right.
func option_row(icon: String, title: String, hint: String, control: Control = null, soon := false) -> HBoxContainer:
	var holder := card(Color.WHITE, Color("dbe8f6"), 16, 2, 10)
	holder.name = "Row_" + title
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_parent.add_child(holder)
	var line := row(14, holder)
	line.add_child(Glyph.new(icon, Color("8fa3c0") if soon else NAVY, 34))
	var words := column(0, line)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := text(title, 19, MUTED if soon else NAVY, words)
	t.add_theme_constant_override("outline_size", 0)
	if hint != "":
		var h := text(hint, 14, MUTED, words)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if soon:
		pill("Sắp có", Color("b3c1d6"), Color.WHITE, 14, line)
	if control:
		line.add_child(control)
	return line

func switch(section: String, key: String, live := Callable()) -> Switch:
	var node := Switch.new(bool(draft[section][key]))
	node.name = "Switch_" + key
	node.toggled.connect(func(on: bool):
		draft[section][key] = on
		if live.is_valid():
			live.call())
	return node

func choice_list(items: Array, selected: int, on_pick: Callable, width := 280.0) -> OptionButton:
	var node := OptionButton.new()
	node.custom_minimum_size = Vector2(width, 46)
	node.add_theme_font_size_override("font_size", 17)
	node.add_theme_color_override("font_color", NAVY)
	node.add_theme_color_override("font_hover_color", NAVY)
	node.add_theme_color_override("font_focus_color", NAVY)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var fill := FIELD if state != "hover" else Color("d6e9ff")
		if state == "disabled":
			fill = Color("eef2f7")
		node.add_theme_stylebox_override(state, box(fill, Color("b9d4f2") if state != "disabled" else Color("dfe5ee"), 12, 2, 10))
	node.add_theme_color_override("font_disabled_color", Color("9aa9c0"))
	for item in items:
		node.add_item(str(item))
	node.select(clampi(selected, 0, maxi(0, items.size() - 1)))
	node.item_selected.connect(on_pick)
	return node

## Slider 0..100 with its number; `live` runs on every change (volume preview).
func percent_slider(section: String, key: String, live := Callable()) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	line.custom_minimum_size = Vector2(620, 0)
	var slider := HSlider.new()
	slider.name = "Slider_" + key
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = float(draft[section][key])
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var track := box(Color("c9d9ec"), Color.TRANSPARENT, 8, 0, 0)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	slider.add_theme_stylebox_override("slider", track)
	var filled := box(Color("2f8cf0"), Color.TRANSPARENT, 8, 0, 0)
	slider.add_theme_stylebox_override("grabber_area", filled)
	slider.add_theme_stylebox_override("grabber_area_highlight", filled)
	line.add_child(slider)
	var number := text("%d%%" % int(slider.value), 18, NAVY, line)
	number.custom_minimum_size = Vector2(58, 0)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider.value_changed.connect(func(value: float):
		draft[section][key] = int(value)
		number.text = "%d%%" % int(value)
		if live.is_valid():
			live.call())
	return line

## Big selectable tiles (window mode, quality, language).
func tiles(items: Array, selected: String, on_pick: Callable, side := Vector2(170, 92), art := "", stretch_tiles := false) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL if stretch_tiles else Control.SIZE_FILL
	line.add_theme_constant_override("separation", 12)
	var group := ButtonGroup.new()
	for item in items:
		var key: String = item[0]
		var soon: bool = item.size() > 2 and bool(item[2])
		var button := Button.new()
		button.name = "Tile_" + key
		button.toggle_mode = true
		button.button_group = group
		button.disabled = soon
		button.custom_minimum_size = side
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL if stretch_tiles else Control.SIZE_FILL
		button.button_pressed = key == selected
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			var on: bool = state in ["pressed", "hover_pressed"]
			var style := box(Color("fff3c4") if on else (Color("eef2f7") if state == "disabled" else FIELD), SUN if on else Color("b9d4f2"), 14, 3 if on else 2, 6)
			if state == "focus":
				style = box(Color.TRANSPARENT, Color(SKY, 0.8), 14, 2, 6)
			button.add_theme_stylebox_override(state, style)
		var stack := VBoxContainer.new()
		stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(stack)
		if art != "" and ResourceLoader.exists(art):
			var picture_node := picture(art, Vector2(side.x - 16, side.y - 40))
			picture_node.modulate = Color(1, 1, 1, 1) if not soon else Color(1, 1, 1, 0.5)
			stack.add_child(picture_node)
		var label := text(str(item[1]), 17, MUTED if soon else NAVY, stack)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if soon:
			var badge := text("Sắp có", 13, MUTED, stack)
			badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.pressed.connect(func(): on_pick.call(key))
		line.add_child(button)
	return line

## Section heading. Room above it: capitals with two marks (Ề, Ằ, Ầ) draw above
## the line on some Windows fonts and the scroll area would cut them off.
func heading(value: String) -> void:
	var label := text(value, 18, Color("2b6fc4"), body)
	label.add_theme_constant_override("outline_size", 0)
	label.custom_minimum_size = Vector2(0, 34)
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

# ---------------------------------------------------------------- sections

func build_account() -> void:
	extra_button.visible = false
	if not AuthSession.has_session():
		option_row("user", "Chế độ khách", "Bạn đang chơi bằng tên khách trên máy này. Đăng nhập để có tài khoản, đổi mật khẩu và email.")
		var back := candy("Đăng nhập / Đăng ký", func(): navigate.emit("logout"), "sky", 17)
		back.custom_minimum_size = Vector2(240, 46)
		option_row("logout", "Về màn hình đăng nhập", "Thoát chế độ khách.", back)
		return
	if account_state == "idle":
		load_account()
	var top := card(Color.WHITE, Color("dbe8f6"), 18, 2, 12)
	body.add_child(top)
	var line := row(18, top)
	var face_box := card(Color("bfe3ff"), Color("8fc8f4"), 18, 2, 4)
	face_box.custom_minimum_size = Vector2(170, 170)
	line.add_child(face_box)
	face_box.add_child(picture("res://assets/characters/portraits/%s.png" % game_hero(), Vector2(160, 160)))
	var info := column(10, line)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_line := row(12, info)
	sized(text("Tên hiển thị", 18, NAVY, name_line), Vector2(150, 0))
	name_field = LineEdit.new()
	name_field.name = "DisplayName"
	name_field.max_length = 24
	name_field.text = str(account.get("name", AuthSession.account_name))
	name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_field.custom_minimum_size = Vector2(0, 46)
	name_field.add_theme_font_size_override("font_size", 19)
	name_field.add_theme_color_override("font_color", NAVY)
	name_field.add_theme_stylebox_override("normal", box(FIELD, Color("b9d4f2"), 12, 2, 10))
	name_field.add_theme_stylebox_override("focus", box(Color.WHITE, SKY, 12, 2, 10))
	name_line.add_child(name_field)
	var id_line := row(12, info)
	sized(text("ID người chơi", 18, NAVY, id_line), Vector2(150, 0))
	var full_id := str(account.get("id", AuthSession.account_id))
	var id_label := stretch(text("#" + full_id.substr(0, 8).to_upper(), 19, INK, id_line))
	id_label.name = "PlayerId"
	var copy := candy("Sao chép", func():
		DisplayServer.clipboard_set(full_id)
		status_label.text = "Đã sao chép ID người chơi.", "ghost", 15)
	copy.custom_minimum_size = Vector2(120, 42)
	id_line.add_child(copy)
	var stats := row(12, info)
	var exp: Dictionary = standing.get("exp", {})
	pill("EXP %s" % grouped(int(exp.get("value", 0))), Color("ff9a3c"), Color.WHITE, 17, stats)
	pill("Hạng EXP: %s" % (str(exp.get("rank")) if exp.get("rank") != null else "chưa có"), Color("2f8cf0"), Color.WHITE, 17, stats)
	if account_state == "loading":
		text("Đang tải thông tin tài khoản…", 15, MUTED, stats)
	elif account_state == "error":
		text("Chưa tải được thông tin tài khoản.", 15, CORAL, stats)
	var password := candy("Đổi mật khẩu  ›", open_password, "sky", 17)
	password.name = "ChangePassword"
	password.custom_minimum_size = Vector2(200, 46)
	option_row("lock", "Đổi mật khẩu", "Cần mật khẩu hiện tại; mật khẩu mới từ 10 ký tự.", password)
	option_row("link", "Liên kết tài khoản", "Google, Facebook", null, true)
	var email_text := str(account.get("email")) if account.get("email") != null else "Chưa có email"
	var email := candy("Thay đổi", open_email, "ghost", 16)
	email.name = "ChangeEmail"
	email.custom_minimum_size = Vector2(130, 44)
	var email_line := option_row("mail", "Email", "Dùng để khôi phục mật khẩu · " + email_text, email)
	email_line.name = "EmailRow"
	option_row("phone", "Số điện thoại", "Bảo mật và nhận thông báo", null, true)
	option_row("shield", "Bảo mật 2 lớp (2FA)", "Mã xác thực khi đăng nhập", null, true)
	var out := candy("Đăng xuất", func(): navigate.emit("logout"), "coral", 17)
	out.name = "Logout"
	out.custom_minimum_size = Vector2(170, 46)
	option_row("logout", "Đăng xuất", "Đăng xuất tài khoản hiện tại.", out)

func game_hero() -> String:
	return hero_id

func load_account() -> void:
	account_state = "loading"
	var me: Dictionary = await AuthSession.api(HTTPClient.METHOD_GET, "/v1/me")
	var board: Dictionary = await AuthSession.api(HTTPClient.METHOD_GET, "/v1/leaderboards?limit=1")
	if me.status == 200 and me.data is Dictionary:
		account = me.data
		account_state = "ok"
	else:
		account_state = "error"
	if board.status == 200 and board.data is Dictionary:
		standing = board.data.get("me", {})
	if current == "account" and is_visible_in_tree():
		show_section("account")

## Small form in the kit modal: fields + one action.
func form(title: String, fields: Array, action_label: String, on_send: Callable) -> Array:
	notice(title, "")
	for child in modal_actions.get_children():
		child.queue_free()
	var inputs := []
	var stack := modal_message.get_parent()
	for spec in fields:
		var field := LineEdit.new()
		field.placeholder_text = str(spec[0])
		field.secret = bool(spec[1])
		field.custom_minimum_size = Vector2(420, 46)
		field.add_theme_font_size_override("font_size", 18)
		field.add_theme_stylebox_override("normal", box(FIELD, Color("b9d4f2"), 12, 2, 10))
		stack.add_child(field)
		stack.move_child(field, modal_actions.get_index())
		field.set_meta("form_field", true)
		inputs.append(field)
	modal_actions.add_child(sized(candy("Hủy", close_form, "ghost", 17), Vector2(120, 50)))
	modal_actions.add_child(sized(candy(action_label, func(): on_send.call(inputs), "sky", 17), Vector2(200, 50)))
	if not inputs.is_empty():
		(inputs[0] as LineEdit).grab_focus()
	return inputs

func close_form() -> void:
	for child in modal_message.get_parent().get_children():
		if child.has_meta("form_field"):
			child.queue_free()
	close_modal()

func open_password() -> void:
	form("ĐỔI MẬT KHẨU", [["Mật khẩu hiện tại", true], ["Mật khẩu mới (từ 10 ký tự)", true], ["Nhập lại mật khẩu mới", true]], "ĐỔI MẬT KHẨU", send_password)

func send_password(inputs: Array) -> void:
	var old: String = inputs[0].text
	var fresh: String = inputs[1].text
	if fresh.length() < 10 or fresh != inputs[2].text:
		modal_message.text = "Mật khẩu mới cần từ 10 ký tự và hai lần nhập phải giống nhau."
		return
	modal_message.text = "Đang đổi mật khẩu…"
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_POST, "/v1/me/password", {"password": old, "new_password": fresh})
	if reply.status == 204:
		close_form()
		status_label.text = "Đã đổi mật khẩu."
	else:
		modal_message.text = "Mật khẩu hiện tại không đúng." if reply.status == 401 else "Chưa đổi được: " + str(reply.error)

func open_email() -> void:
	form("EMAIL KHÔI PHỤC", [["Email mới", false], ["Mật khẩu hiện tại", true]], "LƯU EMAIL", send_email)
	modal_message.text = "Mã khôi phục mật khẩu sẽ gửi tới email này."

func send_email(inputs: Array) -> void:
	modal_message.text = "Đang lưu…"
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_PUT, "/v1/me/email", {"email": str(inputs[0].text).strip_edges(), "password": inputs[1].text})
	if reply.status == 200 and reply.data is Dictionary:
		account["email"] = reply.data.get("email")
		close_form()
		status_label.text = "Đã lưu email khôi phục."
		show_section("account")
	else:
		modal_message.text = {401: "Mật khẩu hiện tại không đúng.", 409: "Email này đã được tài khoản khác dùng.", 422: "Email chưa đúng định dạng."}.get(reply.status, "Chưa lưu được: " + str(reply.error))

func build_display() -> void:
	var d: Dictionary = draft.display
	heading("ĐỘ PHÂN GIẢI VÀ CHẾ ĐỘ HIỂN THỊ")
	var size_list := choice_list(Settings.RESOLUTIONS.map(func(r): return r.replace("x", " × ")), Settings.RESOLUTIONS.find(str(d.resolution)), func(i): d.resolution = Settings.RESOLUTIONS[i])
	size_list.name = "Resolution"
	size_list.disabled = str(d.mode) == "fullscreen"
	option_row("monitor", "Độ phân giải cửa sổ", "Dùng khi chơi ở chế độ cửa sổ.", size_list)
	var modes := tiles([["window", "Cửa sổ"], ["fullscreen", "Toàn màn hình"]], str(d.mode), func(key):
		d.mode = key
		size_list.disabled = key == "fullscreen", Vector2(170, 56))
	option_row("monitor", "Chế độ hiển thị", "", modes)
	heading("CHẤT LƯỢNG HÌNH ẢNH (khử răng cưa)")
	var levels := []
	for key in Settings.QUALITY:
		levels.append([key, Settings.QUALITY[key][0]])
	var quality := tiles(levels, str(d.quality), func(key): d.quality = key, Vector2(190, 120), "res://assets/level_previews/park.png", true)
	quality.name = "Quality"
	body.add_child(quality)
	var fps_labels := Settings.FPS.map(func(f): return "%d FPS" % f if f > 0 else "Không giới hạn")
	var fps := choice_list(fps_labels, Settings.FPS.find(int(d.fps)), func(i): d.fps = Settings.FPS[i], 220)
	fps.name = "Fps"
	option_row("star", "Giới hạn FPS", "Khung hình tối đa mỗi giây.", fps)
	option_row("check", "V-Sync", "Hình mượt, không xé hình; có thể giảm FPS.", switch("display", "vsync"))
	option_row("sun", "Độ sáng", "50 là mặc định.", percent_slider("display", "brightness"))
	option_row("user", "Hiển thị tên người chơi", "Tên phía trên nhân vật trong trận online.", switch("display", "show_names"))

func build_audio() -> void:
	var a: Dictionary = draft.audio
	for spec in [["speaker", "Âm lượng tổng", "master", "Master"], ["music", "Nhạc nền", "music", "Music"], ["star", "Hiệu ứng âm thanh", "sfx", "SFX"], ["bell", "Âm thanh giao diện", "ui", "UI"]]:
		var key: String = spec[2]
		var bus: String = spec[3]
		var line := percent_slider("audio", key, func(): Settings.set_volume(bus, float(a[key])))
		var try := candy("▶ Nghe thử", func(): preview(key), "sky", 15)
		try.name = "Try_" + key
		try.custom_minimum_size = Vector2(140, 42)
		line.add_child(try)
		option_row(str(spec[0]), str(spec[1]), "", line)
	option_row("mic", "Giọng nói", "Âm lượng chat thoại", null, true)
	var outputs := AudioServer.get_output_device_list()
	var speaker := choice_list(Array(outputs).map(func(n): return "Loa mặc định" if n == "Default" else n), maxi(0, outputs.find(str(a.output_device))), func(i): a.output_device = outputs[i], 340)
	speaker.name = "Output"
	option_row("speaker", "Thiết bị loa", "", speaker)
	var inputs := AudioServer.get_input_device_list()
	var mic := choice_list(Array(inputs).map(func(n): return "Micro mặc định" if n == "Default" else n), maxi(0, inputs.find(str(a.input_device))), func(i): a.input_device = inputs[i], 340)
	mic.name = "Input"
	option_row("mic", "Thiết bị micro", "Dùng cho chat thoại khi có.", mic)
	option_row("monitor", "Tắt tiếng khi thu nhỏ cửa sổ", "Tự tắt âm khi game không được chọn.", switch("audio", "mute_unfocused"))

func preview(key: String) -> void:
	if key == "music":
		preview_player.bus = "Music"
		preview_player.stream = load("res://assets/audio/music_loop.wav")
		preview_player.play()
		get_tree().create_timer(2.5).timeout.connect(func(): if preview_player.bus == "Music": preview_player.stop())
		return
	preview_player.stop()
	var sound: String = PREVIEW.get(key, "collect")
	preview_player.bus = "Master" if key == "master" else Settings.bus_for(sound)
	preview_player.stream = load("res://assets/audio/%s.wav" % sound)
	preview_player.play()

func preview_all() -> void:
	for i in 3:
		var key: String = ["sfx", "ui", "master"][i]
		get_tree().create_timer(0.7 * i).timeout.connect(func(): preview(key))

## Pick one device (cards), then its keys / buttons and options load below.
func build_controls() -> void:
	var c: Dictionary = draft.controls
	var pick := HBoxContainer.new()
	pick.name = "Devices"
	pick.add_theme_constant_override("separation", 16)
	body.add_child(pick)
	var group := ButtonGroup.new()
	for spec in [
		["keyboard", "keyboard", "BÀN PHÍM", "Điều khiển bằng bàn phím truyền thống", ["Phổ biến", "Chính xác", "Hợp thi đấu"], "bombo", SUN],
		["gamepad", "pad", "TAY CẦM", "Gamepad / Controller (kiểu Xbox)", ["Thoải mái", "Linh hoạt", "Hợp giải trí"], "zin", SKY],
	]:
		pick.add_child(device_card(spec, str(c.device) == str(spec[0]), group))
	var pads := Input.get_connected_joypads()
	var note := text("Bạn chỉ chọn được một loại thiết bị; bấm LƯU để áp dụng cho mọi chế độ chơi.", 15, NAVY, body)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if str(c.device) == "gamepad":
		var found := "Đã nhận %d tay cầm: %s" % [pads.size(), Input.get_joy_name(pads[0])] if not pads.is_empty() else "Chưa thấy tay cầm nào: hãy cắm tay cầm vào máy."
		var pad_note := text(found, 15, MINT.darkened(0.3) if not pads.is_empty() else CORAL, body)
		pad_note.name = "PadStatus"
	body.add_child(device_panel(str(c.device)))
	body.add_child(control_options(str(c.device)))

## The chosen device's panel: icon, title, description, then a striped table
## "Hành động / Phím (Nút) mặc định" (as the controls mockup).
func device_panel(device: String) -> Control:
	var pad := device == "gamepad"
	var tone := Color("ff7aa8") if pad else Color("4fb7f5")
	var panel := card(tone.lerp(Color.WHITE, 0.86), tone.lerp(Color.WHITE, 0.45), 22, 2, 14)
	panel.name = "Panel_" + device
	var col := column(8, panel)
	var head := row(16, col)
	var icon_box := card(tone.lerp(Color.WHITE, 0.6), Color.WHITE, 18, 3, 8)
	icon_box.custom_minimum_size = Vector2(150, 104)
	head.add_child(icon_box)
	var icon := Glyph.new("pad" if pad else "keyboard", Color.WHITE if pad else Color("3b7fd6"), 86)
	icon_box.add_child(icon)
	var words := column(4, head)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := title_text("Điều khiển bằng " + ("Tay cầm" if pad else "Bàn phím"), 26, tone.darkened(0.35) if pad else Color("1f5fb4"), words)
	title.remove_theme_constant_override("outline_size")
	title.custom_minimum_size = Vector2(0, 40)
	title.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	var desc := text("Trải nghiệm thoải mái, mượt mà với tay cầm game (kiểu Xbox)." if pad else "Phù hợp với người chơi quen thao tác nhanh và chính xác.", 17, INK, words)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var strip := card(tone.lerp(Color.WHITE, 0.55), Color.TRANSPARENT, 12, 0, 8)
	col.add_child(strip)
	var strip_line := row(10, strip)
	sized(text("", 1, INK, strip_line), Vector2(34, 0))
	stretch(text("Hành động", 18, tone.darkened(0.45), strip_line))
	var key_head := text("Nút mặc định" if pad else "Phím mặc định", 18, tone.darkened(0.45), strip_line)
	key_head.custom_minimum_size = Vector2(420, 0)
	key_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rows: Array = PAD_ROWS if pad else KEY_ROWS
	for i in rows.size():
		var spec: Array = rows[i]
		var line_card := card(Color(1, 1, 1, 0.75) if i % 2 == 0 else tone.lerp(Color.WHITE, 0.78), Color.TRANSPARENT, 12, 0, 6)
		line_card.name = "Row_" + str(spec[1])
		col.add_child(line_card)
		var line := row(10, line_card)
		line.add_child(Glyph.new(str(spec[0]), Color(spec[3]), 30))
		var name_label := stretch(text(str(spec[1]), 19, NAVY, line))
		name_label.add_theme_constant_override("outline_size", 0)
		var caps := HBoxContainer.new()
		caps.custom_minimum_size = Vector2(420, 40)
		caps.alignment = BoxContainer.ALIGNMENT_CENTER
		caps.add_theme_constant_override("separation", 6)
		line.add_child(caps)
		for cap in spec[2]:
			if pad:
				pad_button(cap, caps)
			else:
				key_cap(str(cap), caps)
	return panel

## Options under the panel, in one strip (gamepad-only ones only for the pad).
func control_options(device: String) -> Control:
	var holder := card(Color.WHITE, Color("dbe8f6"), 18, 2, 12)
	holder.name = "ControlOptions"
	var col := column(10, holder)
	var line := row(18, col)
	var items := [["star", "Hiển thị gợi ý phím", "controls", "show_hints"], ["pad", "Tự động nhận tay cầm", "controls", "auto_detect"]]
	if device == "gamepad":
		items.push_front(["pad", "Rung tay cầm", "game", "vibration"])
	for i in items.size():
		var item: Array = items[i]
		if i > 0:
			var sep := ColorRect.new()
			sep.color = Color("dbe8f6")
			sep.custom_minimum_size = Vector2(2, 40)
			line.add_child(sep)
		var cell := row(10, line)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.name = "Option_" + str(item[3])
		cell.add_child(Glyph.new(str(item[0]), Color("3b7fd6"), 30))
		stretch(text(str(item[1]), 18, NAVY, cell))
		cell.add_child(switch(str(item[2]), str(item[3])))
	if device == "gamepad":
		var dead := row(12, col)
		dead.name = "Option_deadzone"
		dead.add_child(Glyph.new("gear", NAVY, 30))
		var label := text("Độ nhạy / Deadzone", 18, NAVY, dead)
		label.tooltip_text = "Cần nghiêng ít hơn mức này sẽ không tính là di chuyển."
		var slider := percent_slider("controls", "deadzone")
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dead.add_child(slider)
	return holder

## Keyboard key: light 3D cap (darker bottom edge), dark letter.
func key_cap(value: String, parent: Control) -> void:
	if value == "/":
		text("/", 20, MUTED, parent)
		return
	var holder := PanelContainer.new()
	var style := box(Color("f6f8fc"), Color("9aa9c0"), 8, 2, 4, 5)
	style.content_margin_left = 12 if value.length() > 1 else 8
	style.content_margin_right = style.content_margin_left
	holder.add_theme_stylebox_override("panel", style)
	holder.custom_minimum_size = Vector2(36 if value.length() <= 1 else 96, 36)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := text(value, 17, NAVY, holder)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(holder)

## Gamepad button: round coloured face (A green, X blue, B red...), or a pill
## for shoulder / stick / start labels.
func pad_button(cap: Array, parent: Control) -> void:
	var value: String = cap[0]
	var fill: Color = cap[1]
	var holder := PanelContainer.new()
	var round := value.length() == 1
	var style := box(fill, fill.darkened(0.3), 20 if round else 12, 3, 4)
	style.content_margin_left = 6 if round else 14
	style.content_margin_right = style.content_margin_left
	holder.add_theme_stylebox_override("panel", style)
	holder.custom_minimum_size = Vector2(40, 40) if round else Vector2(0, 38)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := text(value, 18, Color.WHITE, holder)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_outline_color", fill.darkened(0.45))
	label.add_theme_constant_override("outline_size", 4)
	parent.add_child(holder)

func device_card(spec: Array, selected: bool, group: ButtonGroup) -> Button:
	var key: String = spec[0]
	var accent: Color = spec[6]
	var button := Button.new()
	button.name = "Device_" + key
	button.toggle_mode = true
	button.button_group = group
	button.button_pressed = selected
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 250)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var on: bool = state in ["pressed", "hover_pressed"]
		var style := box(Color("fff3c4") if on else Color("e6f0fc"), SUN if on else Color("b9d4f2"), 22, 4 if on else 2, 12)
		if state == "hover":
			style.bg_color = Color("eef5ff")
		if state == "focus":
			style = box(Color.TRANSPARENT, Color(SKY, 0.8), 22, 2, 12)
		button.add_theme_stylebox_override(state, style)
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.offset_top = 12
	stack.offset_bottom = -12
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 6)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(stack)
	# The hero with the device in front of them.
	var art := Control.new()
	art.custom_minimum_size = Vector2(0, 120)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(art)
	var face := picture("res://assets/characters/portraits/%s.png" % str(spec[5]), Vector2(120, 120))
	face.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	face.offset_left = -60
	face.offset_right = 60
	face.offset_bottom = 120
	art.add_child(face)
	var device := Glyph.new(str(spec[1]), Color("26324f") if key == "keyboard" else Color.WHITE, 80)
	device.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	device.offset_left = -40
	device.offset_right = 40
	device.offset_top = -52
	device.offset_bottom = 28
	art.add_child(device)
	var title := title_text(str(spec[2]), 26, accent.darkened(0.45) if key == "keyboard" else NAVY, stack)
	title.remove_theme_constant_override("outline_size")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var desc := text(str(spec[3]), 16, MUTED, stack)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var chips := HBoxContainer.new()
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_theme_constant_override("separation", 8)
	stack.add_child(chips)
	for chip in spec[4]:
		pill("✓ " + str(chip), accent.darkened(0.15) if selected else Color("8fa3c0"), Color.WHITE, 14, chips)
	var mark := Glyph.new("check" if selected else "dot", SUN.darkened(0.1) if selected else Color("b9d4f2"), 38)
	mark.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	mark.offset_left = -54
	mark.offset_top = 14
	mark.offset_right = -16
	mark.offset_bottom = 52
	button.add_child(mark)
	button.pressed.connect(func():
		draft.controls.device = key
		show_section("controls"))
	return button

func build_game() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(grid)
	row_parent = grid
	option_row("check", "Tự động sẵn sàng", "Tự bấm SẴN SÀNG khi vào phòng online.", switch("game", "auto_ready"))
	option_row("star", "Rung màn hình khi bom nổ", "Bàn chơi rung nhẹ khi có vụ nổ.", switch("game", "screen_shake"))
	option_row("logout", "Xác nhận rời trận", "Hỏi lại trước khi rời trận đang diễn ra.", switch("game", "confirm_leave"))

func build_language() -> void:
	var langs := tiles([["vi", "Tiếng Việt"], ["en", "English", true], ["ko", "한국어", true], ["ja", "日本語", true], ["zh", "中文", true]], str(draft.language.ui), func(key): draft.language.ui = key, Vector2(130, 74))
	langs.name = "Languages"
	option_row("monitor", "Ngôn ngữ giao diện", "Toàn bộ chữ trong game.", langs)
	var server := "Máy chủ BỤP BỤP (online)" if not "127.0.0.1" in AuthSession.api_url and not "localhost" in AuthSession.api_url else "Máy này (127.0.0.1)"
	var server_label := pill(server, Color("2f8cf0"), Color.WHITE, 16)
	var holder := server_label.get_parent()
	option_row("globe", "Máy chủ", "Đổi ở nút CÀI ĐẶT của màn hình đăng nhập.", holder)
	option_row("mic", "Ngôn ngữ thoại và phụ đề", "", null, true)
	option_row("people", "Bộ lọc chat", "Ẩn từ ngữ không phù hợp trong trò chuyện.", switch("game", "chat_filter"))

# ---------------------------------------------------------------- footer

func reset_section() -> void:
	var fresh := Settings.defaults()
	var sections: Array = {"display": ["display"], "audio": ["audio"], "game": ["game"], "language": ["language"], "controls": ["controls"]}.get(current, [])
	for section in sections:
		draft[section] = fresh[section]
	if current == "language":
		draft.game.chat_filter = fresh.game.chat_filter
	if current == "controls":
		draft.game.vibration = fresh.game.vibration
	if current == "audio":
		Settings.apply(draft)
	show_section(current)
	status_label.text = "Đã đặt lại mặc định (bấm LƯU để giữ)."

func cancel_changes() -> void:
	draft = Settings.draft()
	Settings.apply(Settings.values)
	preview_player.stop()
	navigate.emit("home")

func save_changes() -> void:
	Settings.save(draft)
	if current == "account" and name_field and AuthSession.has_session():
		var value := " ".join(name_field.text.strip_edges().split(" ", false))
		if value != str(account.get("name", "")) and value.length() >= 2:
			var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_PATCH, "/v1/me", {"display_name": value})
			if reply.status == 200 and reply.data is Dictionary:
				AuthSession.account_name = str(reply.data.get("name", value))
				account["name"] = AuthSession.account_name
			else:
				status_label.text = "Đã lưu cài đặt, nhưng chưa đổi được tên: " + str(reply.error)
				return
	status_label.text = "Đã lưu cài đặt."
