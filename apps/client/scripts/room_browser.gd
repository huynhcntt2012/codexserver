extends Control
## Desktop lobby. All rooms and occupancy originate from the arena API.
signal join_requested(room_id: String)
signal create_requested
signal refresh_requested
signal back_requested
const THUMB = preload("res://art/room-garden.svg")
var canvas := Control.new()
var background := ColorRect.new()
var grid: GridContainer
var summary: Label
var profile: Label
var status: Label
var refresh_button: Button
var create_button: Button
var back_button: Button
var quick_button: Button
var previous: Button
var next: Button
var page_label: Label
var search: LineEdit
var slots: CheckBox
var rooms: Array = []
var page := 0
var locked := false
var info := AcceptDialog.new()

func box(color: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color)
	style.border_color = Color("79e4f3")
	style.set_border_width_all(3)
	style.set_corner_radius_all(20)
	style.content_margin_left = 12
	style.content_margin_right = 12
	return style

func place(node: Control, rect: Rect2) -> void:
	canvas.add_child(node)
	node.position = rect.position
	node.size = rect.size

func panel(rect: Rect2, color: String) -> void:
	var node := Panel.new()
	node.add_theme_stylebox_override("panel", box(color))
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(node, rect)

func label(text: String, rect: Rect2, font_size := 18) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", Color("effaff"))
	node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(node, rect)
	return node

func style_button(node: Button, color := "fff0ac") -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var fill := color
		if state == "hover": fill = "fff9e9"
		if state == "pressed": fill = "50cfcb"
		if state == "disabled": fill = "88b5ce"
		node.add_theme_stylebox_override(state, box(fill))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		node.add_theme_color_override(state, Color("554b77"))
	node.add_theme_font_size_override("font_size", 17)

func button(text: String, rect: Rect2, action: Callable, color := "fff0ac") -> Button:
	var node := Button.new()
	node.text = text
	style_button(node, color)
	place(node, rect)
	node.pressed.connect(action)
	return node

func unavailable(feature: String) -> void:
	info.dialog_text = feature + " chưa được máy chủ hỗ trợ."
	info.popup_centered(Vector2i(460, 160))

func _ready() -> void:
	background.color = Color("1688c7")
	add_child(background)
	add_child(canvas)
	add_child(info)
	panel(Rect2(0, 0, 1280, 720), "1688c7")
	panel(Rect2(0, 0, 1280, 77), "126aa9")
	label("BỤP BỤP!", Rect2(26, 10, 240, 46), 36)
	label("ĐẤU TRƯỜNG BÓNG NƯỚC", Rect2(29, 53, 240, 20), 12)
	button("Sảnh chính", Rect2(280, 12, 135, 53), func(): refresh_requested.emit(), "dffaff")
	var nav := ["Cửa hàng", "Trang bị", "Nhiệm vụ", "Xếp hạng"]
	for i in nav.size():
		var feature: String = nav[i]
		button(feature, Rect2(425 + i * 145, 12, 135, 53), func(): unavailable(feature), "bceef7")
	back_button = button("Đăng xuất", Rect2(1110, 12, 150, 53), func(): back_requested.emit())
	panel(Rect2(14, 90, 257, 178), "126aa9")
	var avatar := TextureRect.new()
	avatar.texture = preload("res://art/launch/mascot_pip.png")
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(avatar, Rect2(171, 102, 80, 115))
	profile = label("Người chơi", Rect2(32, 108, 135, 42), 23)
	label("Đang ở Sảnh chính", Rect2(32, 164, 220, 30))
	label("● ONLINE", Rect2(32, 207, 220, 30))
	panel(Rect2(14, 280, 257, 370), "126aa9")
	button("Bạn bè", Rect2(24, 290, 114, 40), func(): unavailable("Bạn bè"), "50cfcb")
	button("Bang hội", Rect2(144, 290, 114, 40), func(): unavailable("Bang hội"), "bceef7")
	label("Kết nối cùng bạn bè", Rect2(32, 350, 220, 32))
	label("Tính năng đang phát triển", Rect2(32, 388, 220, 32), 15)
	label("Chọn phòng bên phải\nđể chơi cùng nhau!", Rect2(32, 450, 220, 80), 17)
	quick_button = button("TÌM TRẬN NHANH", Rect2(287, 85, 310, 85), _quick_match)
	create_button = button("TẠO PHÒNG", Rect2(609, 85, 310, 85), func(): create_requested.emit(), "50cfcb")
	button("ĐẤU XẾP HẠNG", Rect2(931, 85, 330, 85), func(): unavailable("Đấu xếp hạng"), "c6adf1")
	panel(Rect2(287, 182, 974, 52), "126aa9")
	label("Đấu thường · Neon Garden", Rect2(302, 190, 300, 36), 17)
	slots = CheckBox.new()
	slots.text = "Còn chỗ"
	place(slots, Rect2(610, 188, 130, 40))
	slots.toggled.connect(func(_value): page = 0; _render())
	search = LineEdit.new()
	search.placeholder_text = "Tìm ID phòng…"
	place(search, Rect2(752, 190, 350, 36))
	search.text_changed.connect(func(_value): page = 0; _render())
	refresh_button = button("Làm mới", Rect2(1112, 188, 138, 40), func(): refresh_requested.emit(), "bceef7")
	grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	place(grid, Rect2(287, 243, 974, 346))
	summary = label("Đang tải phòng…", Rect2(291, 600, 560, 44), 16)
	previous = button("‹", Rect2(883, 608, 60, 42), func(): page -= 1; _render(), "50cfcb")
	page_label = label("", Rect2(958, 608, 216, 42))
	next = button("›", Rect2(1190, 608, 60, 42), func(): page += 1; _render(), "50cfcb")
	panel(Rect2(0, 661, 1280, 59), "0d5791")
	button("Âm thanh", Rect2(16, 672, 140, 38), func(): AudioServer.set_bus_mute(0, not AudioServer.is_bus_mute(0)), "50cfcb")
	status = label("Chào mừng bạn đến với BỤP BỤP!", Rect2(176, 668, 1080, 44), 16)

func _process(_delta: float) -> void:
	var viewport := get_viewport_rect().size
	background.size = viewport
	var ratio := minf(viewport.x / 1280.0, viewport.y / 720.0)
	canvas.scale = Vector2.ONE * ratio
	canvas.position = (viewport - Vector2(1280, 720) * ratio) / 2

func render_rooms(value: Array) -> void:
	rooms = value.filter(func(room): return room is Dictionary and room.get("roomId") is String)
	_render()

func _render() -> void:
	var filtered := rooms.filter(func(room): return (not slots.button_pressed or room.get("joinable", false)) and (search.text.strip_edges().is_empty() or search.text.strip_edges().to_lower() in str(room.roomId).to_lower()))
	var pages := maxi(1, ceili(filtered.size() / 6.0))
	page = clampi(page, 0, pages - 1)
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	for room in filtered.slice(page * 6, page * 6 + 6):
		var room_id: String = room.roomId
		var tile := Button.new()
		tile.name = "Room_" + room_id
		tile.custom_minimum_size = Vector2(481, 106)
		tile.text = "Phòng %s\nĐấu thường   ·   %d/%d người   ·   %s" % [room_id, int(room.get("players", 0)), int(room.get("maxPlayers", 8)), "THAM GIA" if room.get("joinable", false) else "ĐÃ ĐẦY"]
		tile.icon = THUMB
		tile.expand_icon = true
		tile.add_theme_constant_override("icon_max_width", 95)
		tile.clip_text = true
		tile.tooltip_text = tile.text
		tile.set_meta("joinable", room.get("joinable", false))
		style_button(tile, "dffaff")
		grid.add_child(tile)
		tile.pressed.connect(func(): join_requested.emit(room_id))
	summary.text = "%d phòng chờ · %d kết quả" % [rooms.size(), filtered.size()]
	if rooms.is_empty(): summary.text = "Chưa có phòng chờ. Hãy tạo phòng mới!"
	elif filtered.is_empty(): summary.text = "Không tìm thấy phòng phù hợp."
	page_label.text = "TRANG %d / %d" % [page + 1, pages]
	previous.set_meta("available", page > 0)
	next.set_meta("available", page < pages - 1)
	set_busy(locked)

func _quick_match() -> void:
	for room in rooms:
		if room.get("joinable", false):
			join_requested.emit(room.roomId)
			return
	create_requested.emit()

func set_busy(value: bool) -> void:
	if not is_instance_valid(grid): return
	locked = value
	for node in [refresh_button, create_button, back_button, quick_button]:
		node.disabled = value
	previous.disabled = value or not previous.get_meta("available", false)
	next.disabled = value or not next.get_meta("available", false)
	for tile in grid.get_children():
		tile.disabled = value or not tile.get_meta("joinable", false)
