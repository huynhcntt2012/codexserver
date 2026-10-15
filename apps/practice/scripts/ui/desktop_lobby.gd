extends Control
## PC-only home for the practice game. Cards represent real local maps, not online rooms.
var game: Node
var canvas := Control.new()
var backdrop := ColorRect.new()
var profile: Label
var portrait: TextureRect
var status: Label
var map_buttons: Array[Button] = []
var hero_buttons: Array[Button] = []
var info := AcceptDialog.new()
var search := LineEdit.new()
var signed_in_on_entry := false

func style(color: String) -> StyleBoxFlat:
	var value := StyleBoxFlat.new()
	value.bg_color = Color(color)
	value.border_color = Color("80e5ef")
	value.set_border_width_all(3)
	value.set_corner_radius_all(20)
	return value

func place(node: Control, rect: Rect2) -> void:
	canvas.add_child(node)
	node.position = rect.position
	node.size = rect.size

func panel(rect: Rect2, color := "126aa9") -> void:
	var node := Panel.new()
	node.add_theme_stylebox_override("panel", style(color))
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(node, rect)

func label(text: String, rect: Rect2, font_size := 18, color := "effaff") -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_color_override("font_color", Color(color))
	node.add_theme_font_size_override("font_size", font_size)
	node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(node, rect)
	return node

func art(path: String, rect: Rect2) -> TextureRect:
	var node := TextureRect.new()
	node.texture = load(path)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(node, rect)
	return node

func button(text: String, rect: Rect2, action: Callable, color := "fff0ac") -> Button:
	var node := Button.new()
	node.text = text
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var fill := color
		if state == "hover": fill = "fff9e9"
		if state == "pressed": fill = "50cfcb"
		if state == "disabled": fill = "8bc5df"
		node.add_theme_stylebox_override(state, style(fill))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		node.add_theme_color_override(state, Color("554b77"))
	node.add_theme_font_size_override("font_size", 18)
	place(node, rect)
	node.pressed.connect(action)
	return node

func _ready() -> void:
	name = "DesktopMainLobby"
	signed_in_on_entry = AuthSession.has_session()
	add_child(backdrop)
	backdrop.color = Color("1688c7")
	add_child(canvas)
	add_child(info)
	panel(Rect2(0, 0, 1280, 78))
	label("BỤP BỤP!", Rect2(22, 10, 245, 48), 36, "ffe17b")
	label("ĐẤU TRƯỜNG BÓNG NƯỚC", Rect2(24, 54, 245, 20), 12)
	button("Sảnh chính", Rect2(280, 12, 145, 54), refresh, "dffaff")
	button("Cửa hàng", Rect2(437, 12, 145, 54), func(): open_shop("shop"), "bceef7")
	button("Trang bị", Rect2(594, 12, 145, 54), func(): open_shop("equipment"), "bceef7")
	button("Nhiệm vụ", Rect2(751, 12, 145, 54), func(): notice("Nhiệm vụ đang được phát triển."), "bceef7")
	button("Xếp hạng", Rect2(908, 12, 145, 54), func(): notice("Chế độ bot chưa có xếp hạng online."), "c6adf1")
	button("Đăng xuất" if signed_in_on_entry else "Đăng nhập", Rect2(1080, 12, 180, 54), leave)
	panel(Rect2(14, 90, 257, 180))
	portrait = art("res://assets/characters/portraits/bombo.png", Rect2(24, 108, 100, 112))
	profile = label("", Rect2(130, 112, 130, 35), 22)
	label("SẢNH CHÍNH", Rect2(130, 157, 130, 28), 15)
	label("Bản PC · Chơi với bot", Rect2(30, 230, 225, 25), 16)
	panel(Rect2(14, 282, 257, 368))
	label("CHỌN NHÂN VẬT", Rect2(32, 292, 222, 30), 20)
	for i in game.HEROES.size():
		var index: int = i
		art("res://assets/characters/portraits/%s.png" % game.HEROES[i], Rect2(28, 335 + i * 59, 45, 49))
		hero_buttons.append(button(game.HERO_NAMES[i], Rect2(84, 338 + i * 59, 170, 44), func(): game._select_hero(index); refresh(), "bceef7"))
	button("CHƠI NHANH", Rect2(287, 90, 310, 82), start)
	button("CHỌN BẢN ĐỒ", Rect2(609, 90, 310, 82), func(): search.grab_focus(), "50cfcb")
	button("ĐẤU XẾP HẠNG", Rect2(931, 90, 330, 82), func(): notice("Chế độ bot chưa có xếp hạng online."), "c6adf1")
	panel(Rect2(287, 184, 974, 52))
	label("Đấu với bot · 1 người + 3 bot", Rect2(304, 193, 400, 36))
	search.placeholder_text = "Tìm bản đồ…"
	place(search, Rect2(830, 192, 412, 36))
	search.text_changed.connect(func(_value): refresh())
	var names := ["Công Viên Kẹo", "Lâu Đài Băng", "Đảo Nắng Vàng"]
	var ids := ["park", "frost", "coast"]
	for i in 3:
		var index: int = i
		var y := 248 + i * 118
		panel(Rect2(287, y, 974, 106), "dffaff")
		art("res://assets/level_previews/%s.png" % ids[i], Rect2(300, y + 9, 140, 88))
		label(names[i], Rect2(464, y + 12, 490, 34), 25, "345581")
		label("Đấu với bot   •   3 phút   •   3 đối thủ", Rect2(465, y + 55, 490, 30), 17, "259fb2")
		var choice := button("CHỌN", Rect2(1064, y + 28, 176, 52), func(): game._select_level(index); refresh())
		choice.set_meta("map_name", names[i])
		map_buttons.append(choice)
	label("3 bản đồ luyện tập · Không phải phòng online", Rect2(292, 609, 760, 36), 17)
	panel(Rect2(0, 662, 1280, 58))
	button("Âm thanh", Rect2(15, 672, 143, 38), func(): game._toggle_audio(); refresh(), "50cfcb")
	status = label("", Rect2(177, 670, 1070, 42), 16)
	refresh()

func refresh() -> void:
	profile.text = AuthSession.account_name if AuthSession.has_session() else "Khách"
	profile.tooltip_text = profile.text
	portrait.texture = load("res://assets/characters/portraits/%s.png" % game.HEROES[game.selected_hero])
	for i in hero_buttons.size():
		hero_buttons[i].text = game.HERO_NAMES[i] + (" ✓" if game.selected_hero == i else "")
	for i in map_buttons.size():
		map_buttons[i].text = "ĐÃ CHỌN" if game.selected_level == i else "CHỌN"
		var query := search.text.strip_edges().to_lower()
		map_buttons[i].disabled = not query.is_empty() and not str(map_buttons[i].get_meta("map_name")).to_lower().contains(query)
	status.text = "Chọn bản đồ rồi CHƠI NHANH · Nhân vật: %s · Âm thanh: %s" % [game.HERO_NAMES[game.selected_hero], "Bật" if game.music_enabled else "Tắt"]

func start() -> void:
	game._new_round()

func notice(text: String) -> void:
	info.dialog_text = text
	info.popup_centered(Vector2i(500, 170))

func leave() -> void:
	UIState.remove_meta("from_desktop_lobby")
	AuthSession.logout()
	get_tree().change_scene_to_file("res://scenes/ui/launch/launch_screen.tscn")

func open_shop(page: String) -> void:
	UIState.set_meta("desktop_page", page)
	UIState.set_meta("from_desktop_lobby", true)
	get_tree().change_scene_to_file("res://scenes/ui/ui_showcase.tscn")

func _process(_delta: float) -> void:
	var viewport := get_viewport_rect().size
	backdrop.size = viewport
	var ratio := minf(viewport.x / 1280.0, viewport.y / 720.0)
	canvas.scale = Vector2.ONE * ratio
	canvas.position = (viewport - Vector2(1280, 720) * ratio) / 2
	if is_visible_in_tree() and signed_in_on_entry and not AuthSession.has_session():
		leave()
