extends VBoxContainer
## "Bạn bè" tab of the PC lobby: search players, view a profile, send a friend
## request (the other player must accept), answer requests, open private chat.
const Glyph := preload("res://scripts/ui/desktop_lobby.gd").Glyph
var ui: Control  # desktop_lobby.gd, for its shared widget helpers and modal
var social: Node
var search: LineEdit
var list: VBoxContainer
var offline: VBoxContainer
var online_box: VBoxContainer
var results: Array = []
var searched := ""
var searching := false
var result_note: Label

func _init(lobby: Control, client: Node) -> void:
	ui = lobby
	social = client
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)

func _ready() -> void:
	offline = ui.column(12, self)
	offline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	offline.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon := Glyph.new("people", Color("8fd7f5"), 70)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	offline.add_child(icon)
	var note: Label = ui.text("Đăng nhập tài khoản để tìm bạn,\nkết bạn và nhắn tin riêng.", 18, Color("d5f3ff"), offline)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	online_box = ui.column(10, self)
	online_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var field: PanelContainer = ui.card(Color("0f4f8f"), ui.LINE, 22, 3, 4)
	online_box.add_child(field)
	var line: HBoxContainer = ui.row(6, field)
	search = LineEdit.new()
	search.name = "FriendSearch"
	search.placeholder_text = "Tìm người chơi theo tên…"
	search.max_length = 24
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.add_theme_stylebox_override("normal", ui.box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 10))
	search.add_theme_stylebox_override("focus", ui.box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 10))
	search.add_theme_font_size_override("font_size", 19)
	search.add_theme_color_override("font_color", Color.WHITE)
	search.add_theme_color_override("font_placeholder_color", Color("b9dcf3"))
	search.text_submitted.connect(func(_value): run_search())
	line.add_child(search)
	line.add_child(ui.icon_button("search", run_search, 44, Color("2fa8ec"), 22))
	result_note = ui.text("", 16, Color("ffe17b"), online_box)
	result_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_note.hide()
	var scroll: ScrollContainer = ui.scroll_list(online_box)
	list = scroll.get_child(0).get_child(0)
	social.friends_changed.connect(render)
	render()

func _process(_delta: float) -> void:
	var signed_in: bool = social.online()
	if offline.visible == signed_in:
		offline.visible = not signed_in
		online_box.visible = signed_in
		if not signed_in:
			results.clear()
			searched = ""
		render()

func run_search() -> void:
	var query := search.text.strip_edges()
	if query.length() < 2:
		show_note("Nhập ít nhất 2 ký tự tên tài khoản.")
		return
	if searching:
		return
	searching = true
	show_note("Đang tìm…")
	var reply: Dictionary = await social.search(query)
	searching = false
	if reply.status != 200:
		show_note(reply.error)
		return
	searched = query
	results = reply.data.get("users", [])
	show_note("Không tìm thấy \"%s\"." % query if results.is_empty() else "")
	render()

func show_note(message: String) -> void:
	result_note.text = message
	result_note.visible = message != ""

## Search results show the latest relation known from the friend list.
func relation_of(user: Dictionary) -> String:
	var id := str(user.id)
	for friend in social.friends:
		if str(friend.id) == id:
			return "friend"
	for entry in social.incoming:
		if str(entry.user.id) == id:
			return "incoming"
	for entry in social.outgoing:
		if str(entry.user.id) == id:
			return "outgoing"
	return "none" if str(user.get("relation", "none")) == "friend" else str(user.get("relation", "none"))

func request_for(user_id: String, entries: Array) -> String:
	for entry in entries:
		if str(entry.user.id) == user_id:
			return str(entry.request_id)
	return ""

func render() -> void:
	if list == null:
		return
	# Detach now so rebuilt rows keep their names within the same frame.
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	if not social.online():
		return
	if searched != "" and not results.is_empty():
		heading("KẾT QUẢ TÌM KIẾM")
		for user in results:
			user_row(user, relation_of(user))
	heading("LỜI MỜI KẾT BẠN (%d)" % social.incoming.size())
	for entry in social.incoming:
		user_row(entry.user, "incoming")
	if social.incoming.is_empty():
		hint("Chưa có lời mời nào.")
	heading("BẠN BÈ (%d)" % social.friends.size())
	for friend in social.friends:
		user_row(friend, "friend")
	if social.friends.is_empty():
		hint("Tìm tên người chơi ở trên rồi bấm biểu tượng kết bạn.")
	if not social.outgoing.is_empty():
		heading("ĐÃ GỬI LỜI MỜI (%d)" % social.outgoing.size())
		for entry in social.outgoing:
			user_row(entry.user, "outgoing")

func heading(value: String) -> void:
	ui.text(value, 16, Color("ffe17b"), list)

func hint(value: String) -> void:
	var label: Label = ui.text(value, 15, Color("b9dcf3"), list)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

const STATUS := {
	"none": ["Chưa là bạn bè", Color("b9dcf3")],
	"friend": ["Bạn bè", Color("aef5c8")],
	"outgoing": ["Đã gửi lời mời", Color("ffe17b")],
	"incoming": ["Muốn kết bạn với bạn", Color("ffb3d1")],
}

func user_row(user: Dictionary, kind: String) -> void:
	var id := str(user.id)
	var entry: PanelContainer = ui.card(Color("1b77c0"), Color("5aa9de"), 18, 3, 8)
	entry.name = "User_" + str(user.name)
	entry.mouse_filter = Control.MOUSE_FILTER_STOP
	entry.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	entry.tooltip_text = "Xem thông tin " + str(user.name)
	entry.gui_input.connect(func(event): if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: open_profile(user))
	list.add_child(entry)
	var line: HBoxContainer = ui.row(10, entry)
	line.add_child(avatar(str(user.name)))
	var who: VBoxContainer = ui.column(0, line)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	ui.stretch(ui.text(str(user.name), 20, Color.WHITE, who))
	var sub := str(STATUS[kind][0])
	if user.get("guild") != null:
		sub += " · Bang " + str(user.guild)
	ui.stretch(ui.text(sub, 14, STATUS[kind][1], who))
	match kind:
		"none":
			var add: Button = ui.icon_button("add_user", func(): add_friend(user), 46, Color("3fd39a"), 23)
			add.name = "Add"
			add.tooltip_text = "Gửi lời mời kết bạn"
			line.add_child(add)
		"incoming":
			var yes: Button = ui.icon_button("check", func(): answer(request_for(id, social.incoming), true, str(user.name)), 44, Color("3fd39a"), 22)
			yes.name = "Accept"
			yes.tooltip_text = "Đồng ý kết bạn"
			line.add_child(yes)
			var no: Button = ui.icon_button("close", func(): answer(request_for(id, social.incoming), false, str(user.name)), 44, Color("f4738d"), 22)
			no.name = "Decline"
			no.tooltip_text = "Từ chối"
			line.add_child(no)
		"friend":
			var talk: Button = ui.icon_button("send", func(): ui.chat.open_private(id), 44, Color("4fc3f0"), 22)
			talk.name = "Chat"
			talk.tooltip_text = "Nhắn riêng"
			line.add_child(talk)
		"outgoing":
			var cancel: Button = ui.icon_button("close", func(): answer(request_for(id, social.outgoing), false, str(user.name)), 44, Color("f4738d"), 22)
			cancel.name = "Cancel"
			cancel.tooltip_text = "Hủy lời mời"
			line.add_child(cancel)

## Round badge with the player's initial; accounts have no portrait yet.
func avatar(player_name: String) -> PanelContainer:
	var hue := float(player_name.hash() % 360) / 360.0
	var face: PanelContainer = ui.card(Color.from_hsv(absf(hue), 0.45, 0.95), Color.WHITE, 26, 3, 0)
	face.custom_minimum_size = Vector2(52, 52)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var letter: Label = ui.text(player_name.left(1).to_upper(), 24, ui.INK, face)
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return face

func open_profile(user: Dictionary) -> void:
	var id := str(user.id)
	var kind := relation_of(user)
	var lines := [
		"Tên: " + str(user.name),
		"Bang hội: " + (str(user.guild) if user.get("guild") != null else "Chưa có"),
		"Quan hệ: " + str(STATUS[kind][0]),
	]
	ui.open_modal("THÔNG TIN NGƯỜI CHƠI", "people", "\n".join(lines))
	match kind:
		"none": ui.modal_action("KẾT BẠN", func(): add_friend(user))
		"incoming": ui.modal_action("ĐỒNG Ý KẾT BẠN", func(): answer(request_for(id, social.incoming), true, str(user.name)))
		"friend": ui.modal_action("NHẮN RIÊNG", func(): ui.chat.open_private(id))

func add_friend(user: Dictionary) -> void:
	ui.close_modal()
	var reply: Dictionary = await social.add_friend(str(user.id))
	if reply.status == 201:
		var accepted: bool = reply.data.get("status") == "accepted"
		UIState.toast_requested.emit(("Đã kết bạn với %s" if accepted else "Đã gửi lời mời kết bạn tới %s") % user.name)
	else:
		UIState.toast_requested.emit(reply.error)
	render()

func answer(request_id: String, accept: bool, player_name: String) -> void:
	ui.close_modal()
	if request_id == "":
		return
	var reply: Dictionary = await social.respond(request_id, accept)
	if reply.status in [200, 204]:
		UIState.toast_requested.emit(("Đã kết bạn với %s" if accept else "Đã bỏ lời mời với %s") % player_name)
	else:
		UIState.toast_requested.emit(reply.error)
