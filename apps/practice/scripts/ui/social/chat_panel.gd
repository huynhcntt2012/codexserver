extends PanelContainer
## Lobby chat: the bottom bar (channel tabs, friend picker, input, send) and the
## message log that opens above it. World needs an account, guild needs a guild,
## private needs a friend; the API enforces the same rules.
const CHANNELS := [["Tất cả", "all"], ["Thế giới", "world"], ["Bang hội", "guild"], ["Riêng", "private"]]
const TAGS := {"world": ["Thế giới", Color("ffffff")], "guild": ["Bang", Color("9ff0c8")], "private": ["Riêng", Color("ffb3d1")]}
const SYSTEM := Color("ffe17b")
var ui: Control  # desktop_lobby.gd
var social: Node
var channel := "all"
var tabs: Dictionary = {}
var input: LineEdit
var send_button: Button
var target: OptionButton
var target_ids: Array[String] = []
var bar: Control
var title: Label
var log_list: VBoxContainer
var log_scroll: ScrollContainer
var system_line: Label
var guild_box: HBoxContainer
var guild_name: LineEdit
var guild_info: Label
var leave_button: Button
var sending := false
var unread := 0

func _init(lobby: Control, client: Node) -> void:
	ui = lobby
	social = client
	name = "ChatLog"
	add_theme_stylebox_override("panel", ui.box(Color(0.04, 0.2, 0.42, 0.93), ui.LINE, 22, 3, 14))
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()

## Bottom bar, added to the lobby page; the log itself goes on the canvas.
func build_bar(parent: Control) -> void:
	bar = ui.card(Color("1572bd"), Color("74d3f0"), 0, 0, 10)
	bar.get_theme_stylebox("panel").border_width_top = 4
	bar.get_theme_stylebox("panel").content_margin_left = 20
	bar.get_theme_stylebox("panel").content_margin_right = 20
	parent.add_child(bar)
	var line: HBoxContainer = ui.row(12, bar)
	var group := ButtonGroup.new()
	for spec in CHANNELS:
		var key: String = spec[1]
		var tab: Button = ui.button(spec[0], func(): pick_channel(key), Color("56d2c9"), ui.INK, 20, 14, Color("9be9f0"))
		tab.name = "Channel_" + key
		tab.toggle_mode = true
		tab.button_group = group
		tab.button_pressed = key == channel
		tab.add_theme_stylebox_override("normal", ui.box(Color("1d5f9e"), Color("4f9fd8"), 14, 3, 8))
		tab.add_theme_color_override("font_color", Color.WHITE)
		tab.custom_minimum_size = Vector2(118, 58)
		line.add_child(tab)
		tabs[key] = tab
	var sound: Button = ui.icon_button("speaker", func(): ui.game._toggle_audio(); ui.refresh(), 58, Color("2a86d0"), 14)
	ui.speaker = sound.get_child(0)
	line.add_child(sound)
	target = OptionButton.new()
	target.name = "PrivateTarget"
	target.custom_minimum_size = Vector2(220, 58)
	target.add_theme_font_size_override("font_size", 19)
	target.add_theme_stylebox_override("normal", ui.box(Color("c2407a"), Color("ffb3d1"), 14, 3, 10))
	target.add_theme_stylebox_override("hover", ui.box(Color("d24d89"), Color("ffb3d1"), 14, 3, 10))
	target.add_theme_stylebox_override("pressed", ui.box(Color("b0356d"), Color("ffb3d1"), 14, 3, 10))
	target.add_theme_stylebox_override("focus", ui.box(Color.TRANSPARENT, Color("ffe17b"), 14, 3, 10))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		target.add_theme_color_override(state, Color.WHITE)
	target.get_popup().add_theme_font_size_override("font_size", 19)
	target.hide()
	line.add_child(target)
	var field: PanelContainer = ui.card(Color("0f5a9c"), Color("4f9fd8"), 14, 3, 4)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(field)
	input = LineEdit.new()
	input.name = "ChatInput"
	input.max_length = 200
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.add_theme_stylebox_override("normal", ui.box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 10))
	input.add_theme_stylebox_override("focus", ui.box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 10))
	input.add_theme_stylebox_override("read_only", ui.box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 10))
	input.add_theme_font_size_override("font_size", 20)
	input.add_theme_color_override("font_color", Color.WHITE)
	input.add_theme_color_override("font_uneditable_color", Color("b9dcf3"))
	input.add_theme_color_override("font_placeholder_color", Color("b9dcf3"))
	input.text_submitted.connect(func(_value): submit())
	input.focus_entered.connect(open)
	field.add_child(input)
	send_button = ui.icon_button("send", submit, 62, Color("4fc3f0"), 16)
	send_button.name = "Send"
	line.add_child(send_button)

func _ready() -> void:
	var stack: VBoxContainer = ui.column(10, self)
	var head: HBoxContainer = ui.row(10, stack)
	title = ui.stretch(ui.text("", 22, Color.WHITE, head))
	guild_info = ui.text("", 17, Color("9ff0c8"), head)
	leave_button = ui.button("Rời bang", leave_guild, Color("f4738d"), Color.WHITE, 16, 14)
	leave_button.name = "LeaveGuild"
	leave_button.custom_minimum_size = Vector2(110, 40)
	head.add_child(leave_button)
	head.add_child(ui.icon_button("close", close, 40, Color("f4738d"), 20))
	guild_box = ui.row(10, stack)
	var ask: Label = ui.text("Chưa có bang hội. Nhập tên để tạo hoặc gia nhập:", 17, Color("d5f3ff"), guild_box)
	ask.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ask.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guild_name = LineEdit.new()
	guild_name.name = "GuildName"
	guild_name.placeholder_text = "Tên bang (3–24 ký tự)"
	guild_name.max_length = 24
	guild_name.custom_minimum_size = Vector2(260, 44)
	guild_name.add_theme_font_size_override("font_size", 18)
	guild_name.add_theme_stylebox_override("normal", ui.box(Color("0f4f8f"), ui.LINE, 12, 2, 10))
	guild_name.add_theme_stylebox_override("focus", ui.box(Color("0f4f8f"), Color("ffe17b"), 12, 2, 10))
	guild_name.add_theme_color_override("font_color", Color.WHITE)
	guild_name.text_submitted.connect(func(_value): join_guild())
	guild_box.add_child(guild_name)
	var join: Button = ui.button("THAM GIA", join_guild, Color("3fd39a"), Color("0d4b3a"), 17, 14)
	join.name = "JoinGuild"
	join.custom_minimum_size = Vector2(130, 44)
	guild_box.add_child(join)
	log_scroll = ScrollContainer.new()
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(log_scroll)
	log_list = ui.column(4)
	log_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.add_child(log_list)
	system_line = line_label("", SYSTEM)
	social.messages_changed.connect(_on_messages)
	social.friends_changed.connect(refresh_targets)
	social.guild_changed.connect(render)
	render()

func _process(_delta: float) -> void:
	# Sits just above the chat bar, right of the friends column so both stay usable.
	if bar == null:
		return
	var bottom: float = bar.get_global_rect().position.y / maxf(0.001, ui.canvas.scale.y)
	size = Vector2(minf(1000.0, ui.canvas.size.x - 440.0), 360.0)
	position = Vector2(422.0, bottom - size.y - 10.0)
	var signed_in: bool = social.online()
	input.editable = signed_in and not sending
	send_button.disabled = not signed_in or sending
	var hint := "Nhập tin nhắn… (Enter để gửi)"
	if not signed_in:
		hint = "Đăng nhập tài khoản để chat"
	elif channel == "private" and target_ids.is_empty():
		hint = "Kết bạn trước để nhắn riêng"
	input.placeholder_text = hint

func set_system(message: String) -> void:
	if system_line:
		system_line.text = message

func pick_channel(key: String) -> void:
	channel = key
	(tabs[key] as Button).set_pressed_no_signal(true)
	if key == "all":
		unread = 0
	target.visible = key == "private"
	open()
	render()

func open() -> void:
	show()
	render()

func close() -> void:
	hide()

func open_private(friend_id: String) -> void:
	ui.close_modal()
	refresh_targets()
	pick_channel("private")
	var index := target_ids.find(friend_id)
	if index >= 0:
		target.select(index)
	input.grab_focus()

func refresh_targets() -> void:
	var keep := target_ids[target.selected] if target.selected >= 0 and target.selected < target_ids.size() else ""
	target.clear()
	target_ids.clear()
	for friend in social.friends:
		target.add_item(str(friend.name))
		target_ids.append(str(friend.id))
	if target_ids.is_empty():
		target.add_item("Chưa có bạn")
		target.disabled = true
	else:
		target.disabled = false
		target.select(maxi(0, target_ids.find(keep)))

func _on_messages() -> void:
	if not visible:
		unread += 1
	render()

func shown_messages() -> Array:
	if channel == "all":
		return social.messages
	return social.messages.filter(func(message): return str(message.channel) == channel)

func render() -> void:
	if log_list == null:
		return
	var label := "Tất cả" if unread == 0 else "Tất cả •%d" % mini(unread, 99)
	(tabs["all"] as Button).text = label
	var in_guild: bool = social.guild != null
	title.text = {"all": "Tất cả kênh", "world": "Kênh Thế giới", "guild": "Kênh Bang hội", "private": "Tin nhắn riêng"}[channel]
	guild_info.text = "Bang %s · %d thành viên" % [social.guild.name, int(social.guild.members)] if in_guild and channel == "guild" else ""
	leave_button.visible = in_guild and channel == "guild"
	guild_box.visible = social.online() and channel == "guild" and not in_guild
	for child in log_list.get_children():
		if child != system_line:
			log_list.remove_child(child)
			child.queue_free()
	if not social.online():
		line_label("Đăng nhập tài khoản để chat Thế giới, Bang hội và nhắn riêng với bạn bè.", Color("b9dcf3"))
	for message in shown_messages():
		line_label(format(message), color_of(message))
	if shown_messages().is_empty() and social.online():
		line_label("Chưa có tin nhắn ở kênh này.", Color("b9dcf3"))
	await get_tree().process_frame
	if is_instance_valid(log_scroll):
		log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)

func line_label(value: String, color: Color) -> Label:
	var label: Label = ui.text(value, 18, color, log_list)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func color_of(message: Dictionary) -> Color:
	if bool(message.get("mine", false)):
		return SYSTEM
	return TAGS.get(str(message.channel), TAGS.world)[1]

func format(message: Dictionary) -> String:
	var tag: String = TAGS.get(str(message.channel), TAGS.world)[0]
	var who := "Bạn" if bool(message.get("mine", false)) else str(message.sender.name)
	if str(message.channel) == "private" and message.get("to") != null:
		var to := "Bạn" if str(message.to.id) == AuthSession.account_id else str(message.to.name)
		who = "%s → %s" % [who, to]
	return "%s [%s] %s: %s" % [clock_text(str(message.get("created_at", ""))), tag, who, str(message.body)]

## "HH:MM" in the player's local time from the server's UTC timestamp.
static func clock_text(stamp: String) -> String:
	if stamp.length() < 19:
		return ""
	var unix := Time.get_unix_time_from_datetime_string(stamp.left(19))
	unix += int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return Time.get_time_string_from_unix_time(unix).left(5)

func submit() -> void:
	var body := input.text.strip_edges()
	if sending or body.is_empty():
		return
	if not social.online():
		UIState.toast_requested.emit("Đăng nhập tài khoản để chat.")
		return
	var send_to := "world" if channel in ["all", "world"] else channel
	var friend := ""
	if send_to == "guild" and social.guild == null:
		open()
		UIState.toast_requested.emit("Tham gia bang hội trước khi chat kênh Bang.")
		return
	if send_to == "private":
		if target_ids.is_empty() or target.selected < 0:
			UIState.toast_requested.emit("Kết bạn rồi chọn người nhận để nhắn riêng.")
			return
		friend = target_ids[target.selected]
	sending = true
	var reply: Dictionary = await social.send(send_to, body, friend)
	sending = false
	if reply.status == 201:
		input.clear()
		open()
	else:
		UIState.toast_requested.emit(reply.error)
	input.grab_focus()

func join_guild() -> void:
	var value := guild_name.text.strip_edges()
	if value.length() < 3:
		UIState.toast_requested.emit("Tên bang cần ít nhất 3 ký tự.")
		return
	var reply: Dictionary = await social.join_guild(value)
	if reply.status == 201:
		guild_name.clear()
		UIState.toast_requested.emit("Đã vào bang %s" % reply.data.guild.name)
	else:
		UIState.toast_requested.emit(reply.error)
	render()

func leave_guild() -> void:
	var reply: Dictionary = await social.leave_guild()
	UIState.toast_requested.emit("Đã rời bang" if reply.status == 204 else reply.error)
	render()
