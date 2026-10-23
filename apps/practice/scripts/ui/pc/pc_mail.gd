extends "res://scripts/ui/pc/pc_kit.gd"
## PC mailbox (docs/MAIL.md): messages an admin sent to this player or to the
## whole server, from GET /v1/mail. Tabs Tất cả / Chưa đọc / Đã nhận quà, a list
## on the left, the open message on the right with its attached rewards and
## NHẬN QUÀ. Opening a message marks it read; the server grants the rewards
## (once) and the wallet / bag are reloaded after a claim.
signal navigate(destination: String)
signal unread_changed(count: int)

const CATEGORY := {  # category -> [kit sticker, label]
	"admin": ["cat_admin", "Ban điều hành"],
	"system": ["cat_system", "Hệ thống"],
	"event": ["cat_event", "Sự kiện"],
	"maintenance": ["cat_maintenance", "Bảo trì"],
	"reward": ["cat_reward", "Quà tặng"],
}
const TABS := [["all", "Tất cả", "mail_navy"], ["unread", "Chưa đọc", "dot"], ["claimed", "Đã nhận quà", "gift_sky"]]

var data: Dictionary = {}
var state := "idle"  # idle | loading | ok | error | signed_out
var error_text := ""
var busy := false
var current_tab := "all"
var open_id := ""
var tab_buttons: Dictionary = {}
var list: VBoxContainer
var detail: VBoxContainer
var footer_note: Label

func _init() -> void:
	super("sky")

func _ready() -> void:
	name = "PcMail"
	setup()
	var root := page(canvas, 12)
	var split := row(16, root)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Left: tabs, list, bulk actions.
	var left := card(Color("e8f3ff"), Color("cfe3f7"), 22, 2, 12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(left)
	var left_col := column(10, left)
	var tabs := row(10, left_col)
	var group := ButtonGroup.new()
	for spec in TABS:
		var key: String = spec[0]
		var button := tab(str(spec[1]), func(): set_tab(key), group, str(spec[2]))
		button.name = "Tab_" + key
		button.custom_minimum_size = Vector2(0, 52)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 19)
		button.button_pressed = key == current_tab
		tabs.add_child(button)
		tab_buttons[key] = button
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_col.add_child(scroll)
	list = column(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var actions := row(10, left_col)
	var read_all := candy("Đọc tất cả", func(): bulk("/v1/mail/read-all"), "sky", 19, "mail_white")
	read_all.name = "ReadAll"
	read_all.custom_minimum_size = Vector2(210, 56)
	actions.add_child(read_all)
	var claim_all := candy("Nhận tất cả", func(): bulk("/v1/mail/claim-all"), "mint", 19, "gift_mint")
	claim_all.name = "ClaimAll"
	claim_all.custom_minimum_size = Vector2(220, 56)
	actions.add_child(claim_all)
	footer_note = stretch(text("", 14, MUTED, actions))
	var clean := candy("Xóa đã đọc", func(): bulk("/v1/mail/delete-read"), "coral", 16, "trash")
	clean.name = "DeleteRead"
	clean.tooltip_text = "Xóa các thư đã đọc (và đã nhận quà)"
	clean.custom_minimum_size = Vector2(170, 56)
	actions.add_child(clean)
	# Right: the open message.
	var right := card(Color.WHITE, Color("cfe3f7"), 22, 2, 16)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	var right_scroll := ScrollContainer.new()
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(right_scroll)
	detail = column(12)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(detail)
	build_modal()
	visibility_changed.connect(func(): if is_visible_in_tree(): load_mail())
	render()

func set_tab(key: String) -> void:
	current_tab = key
	for k in tab_buttons:
		(tab_buttons[k] as Button).set_pressed_no_signal(k == key)
	render()

func load_mail() -> void:
	if busy:
		return
	if not AuthSession.has_session():
		state = "signed_out"
		data = {}
		render()
		return
	busy = true
	if state != "ok":
		state = "loading"
		render()
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_GET, "/v1/mail")
	busy = false
	if reply.status == 200 and reply.data is Dictionary:
		apply(reply.data)
	else:
		state = "error"
		error_text = str(reply.error)
		render()

func apply(payload: Dictionary) -> void:
	data = payload
	state = "ok"
	unread_changed.emit(int(payload.get("unread", 0)))
	var ids: Array = messages().map(func(m): return str(m.id))
	if not open_id in ids:
		open_id = str(ids[0]) if not ids.is_empty() else ""
	render()

func messages() -> Array:
	return data.get("messages", [])

func shown() -> Array:
	match current_tab:
		"unread":
			return messages().filter(func(m): return not bool(m.read))
		"claimed":
			return messages().filter(func(m): return bool(m.claimed))
	return messages()

func message(id: String) -> Dictionary:
	for m in messages():
		if str(m.id) == id:
			return m
	return {}

func clear(node: Control) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func render() -> void:
	if list == null:
		return
	clear(list)
	clear(detail)
	var all := messages()
	var unread := all.filter(func(m): return not bool(m.read)).size()
	(tab_buttons.all as Button).text = "Tất cả (%d)" % all.size()
	(tab_buttons.unread as Button).text = "Chưa đọc (%d)" % unread
	footer_note.text = ""
	match state:
		"signed_out":
			note(list, "Đăng nhập tài khoản để nhận thư và quà từ ban điều hành. Chế độ khách không có hộp thư.")
			return
		"loading", "idle":
			var spin := Spinner.new(56)
			spin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			list.add_child(spin)
			return
		"error":
			note(list, "Không tải được hộp thư: %s" % error_text)
			return
	var rows := shown()
	if rows.is_empty():
		note(list, "Không có thư nào ở mục này.")
	for m in rows:
		list.add_child(mail_row(m))
	var claimable := all.filter(func(m): return bool(m.claimable)).size()
	(find_child("ClaimAll", true, false) as Button).disabled = claimable == 0 or busy
	(find_child("ReadAll", true, false) as Button).disabled = unread == 0 or busy
	if claimable > 0:
		footer_note.text = "%d thư có quà chờ nhận" % claimable
	render_detail(message(open_id))

func note(parent: Control, value: String) -> void:
	var label := text(value, 18, MUTED, parent)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

## "Hôm nay 10:30", "Hôm qua 18:20" or "24/06 16:00" in local time.
static func when(iso: String) -> String:
	var unix: float = Time.get_unix_time_from_datetime_string(iso.substr(0, 19)) + Time.get_time_zone_from_system().bias * 60
	var at := Time.get_datetime_dict_from_unix_time(int(unix))
	var today := Time.get_datetime_dict_from_system()
	var yesterday := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system() + Time.get_time_zone_from_system().bias * 60 - 86400))
	var clock := "%02d:%02d" % [at.hour, at.minute]
	if at.year == today.year and at.month == today.month and at.day == today.day:
		return "Hôm nay " + clock
	if at.year == yesterday.year and at.month == yesterday.month and at.day == yesterday.day:
		return "Hôm qua " + clock
	return "%02d/%02d %s" % [at.day, at.month, clock]

func badge(category: String, side: float) -> Control:
	return sticker(str(CATEGORY.get(category, CATEGORY.admin)[0]), side)

func mail_row(m: Dictionary) -> Control:
	var id := str(m.id)
	var selected := id == open_id
	var button := Button.new()
	button.name = "Mail_" + id.substr(0, 8)
	button.toggle_mode = true
	button.button_pressed = selected
	button.custom_minimum_size = Vector2(0, 96)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var on: bool = st in ["pressed", "hover_pressed"]
		var style := box(Color("fff7dc") if on else Color.WHITE, SUN if on else Color("dbe8f6"), 18, 3 if on else 2, 10)
		if st == "hover":
			style.bg_color = Color("f4f9ff")
		if st == "focus":
			style = box(Color.TRANSPARENT, Color(SKY, 0.7), 18, 2, 10)
		button.add_theme_stylebox_override(st, style)
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 12
	line.offset_right = -14
	line.add_theme_constant_override("separation", 14)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(line)
	var icon := badge(str(m.category), 68)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(icon)
	var words := column(2, line)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := row(8, words)
	stretch(text(str(m.sender), 20, NAVY, top))
	text(when(str(m.created_at)), 15, Color("3b7fd6"), top)
	var bottom := row(8, words)
	stretch(text(str(m.title), 17, INK, bottom))
	if bool(m.claimed):
		pill("Đã nhận quà", Color("ffb432"), Color.WHITE, 14, bottom)
	elif bool(m.claimable):
		bottom.add_child(sticker("gift", 26))
		pill("Có quà", MINT, Color.WHITE, 14, bottom)
	line.add_child(sticker("dot_red" if not bool(m.read) else "dot_grey", 22))
	button.pressed.connect(func(): open(id))
	return button

func open(id: String) -> void:
	open_id = id
	var m := message(id)
	render()
	if not m.is_empty() and not bool(m.read):
		m["read"] = true
		data["unread"] = maxi(0, int(data.get("unread", 0)) - 1)
		unread_changed.emit(int(data.unread))
		render()
		await AuthSession.api(HTTPClient.METHOD_POST, "/v1/mail/%s/read" % id)

func render_detail(m: Dictionary) -> void:
	if m.is_empty():
		note(detail, "Chọn một thư để đọc.")
		return
	var head := row(16, detail)
	head.add_child(badge(str(m.category), 96))
	var who := column(4, head)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := title_text(str(m.sender), 28, NAVY, who)
	name_label.remove_theme_constant_override("outline_size")
	var meta := row(12, who)
	text(when(str(m.created_at)), 17, MUTED, meta)
	meta.add_child(sticker("dot_red" if not bool(m.read) else "dot_grey", 18))
	text("Chưa đọc" if not bool(m.read) else "Đã đọc", 17, CORAL if not bool(m.read) else MUTED, meta)
	var banner := card(Color("fff1c4"), Color.TRANSPARENT, 16, 0, 12)
	detail.add_child(banner)
	var banner_line := row(12, banner)
	banner_line.add_child(sticker("winged_mail", 48))
	var title := title_text(str(m.title), 24, Color("d9531e"), banner_line)
	title.remove_theme_constant_override("outline_size")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(560, 0)
	var body_box := card(Color("f8fbff"), Color("dbe8f6"), 16, 2, 14)
	detail.add_child(body_box)
	var body := text(str(m.body) if str(m.body) != "" else "(Không có nội dung)", 18, INK, body_box)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(560, 0)
	var rewards: Array = m.get("rewards", [])
	if rewards.is_empty():
		var del := candy("Xóa thư", func(): remove(str(m.id)), "coral", 18, "trash")
		del.name = "Delete"
		del.custom_minimum_size = Vector2(180, 52)
		del.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		detail.add_child(del)
		return
	var gifts := card(Color("e4f1ff"), Color.TRANSPARENT, 16, 0, 12)
	detail.add_child(gifts)
	var gifts_col := column(10, gifts)
	var gifts_head := row(8, gifts_col)
	gifts_head.add_child(sticker("gift_box", 30))
	text("Phần thưởng đính kèm", 19, Color("2b6fc4"), gifts_head)
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	gifts_col.add_child(grid)
	for r in rewards:
		grid.add_child(reward_tile(r))
	var claim := candy("ĐÃ NHẬN" if bool(m.claimed) else "NHẬN QUÀ", func(): claim_one(str(m.id)), "mint", 22, "gift")
	claim.name = "Claim"
	claim.disabled = bool(m.claimed) or busy
	claim.custom_minimum_size = Vector2(300, 60)
	claim.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	detail.add_child(claim)

func reward_tile(r: Dictionary) -> Control:
	var tile := card(Color.WHITE, Color("cfe3f7"), 16, 2, 8)
	tile.custom_minimum_size = Vector2(104, 112)
	tile.tooltip_text = str(r.get("name", ""))
	var col := column(2, tile)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	match str(r.type):
		"gold", "gem":
			var g := sticker("coin" if str(r.type) == "gold" else "gem", 60)
			g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			col.add_child(g)
		_:
			var icon := str(r.get("icon", ""))
			var path := "res://assets/" + icon if icon != "" and not icon.begins_with("res://") else icon
			var art := picture(path, Vector2(60, 60))
			art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			col.add_child(art)
	var amount := title_text("x" + grouped(int(r.get("amount", 1))), 19, NAVY, col)
	amount.remove_theme_constant_override("outline_size")
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return tile

func claim_one(id: String) -> void:
	if busy:
		return
	busy = true
	render()
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_POST, "/v1/mail/%s/claim" % id)
	busy = false
	if reply.status == 200:
		await after_claim("Đã nhận quà vào ví và kho đồ.")
	else:
		notice("CHƯA NHẬN ĐƯỢC", "Đã nhận trước đó." if reply.status == 409 else str(reply.error))
		load_mail()

func bulk(path: String) -> void:
	if busy:
		return
	busy = true
	render()
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_POST, path)
	busy = false
	if reply.status in [200, 204]:
		if path.ends_with("claim-all"):
			await after_claim("Đã nhận quà của %d thư." % int(reply.data.get("claimed", 0)) if reply.data is Dictionary else "Đã nhận quà.")
		else:
			load_mail()
	else:
		notice("HỘP THƯ", "Chưa làm được: " + str(reply.error))

## Rewards change the wallet and bag: reload them, then the mailbox.
func after_claim(message_text: String) -> void:
	await UIState.sync_wallet()
	notice("NHẬN QUÀ", message_text)
	load_mail()

func remove(id: String) -> void:
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_DELETE, "/v1/mail/" + id)
	if reply.status == 204:
		open_id = ""
		load_mail()
	else:
		notice("HỘP THƯ", "Chưa xóa được: " + str(reply.error))
