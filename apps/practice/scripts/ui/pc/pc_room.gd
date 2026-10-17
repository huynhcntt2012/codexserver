extends "res://scripts/ui/pc/pc_kit.gd"
## Practice room: the player's card (host, hero switcher), three bot cards that
## turn ready one by one, locked invite slots, the map picker and the room chat.
## BẮT ĐẦU only enables once every occupied seat is ready, then calls `_new_round`.
const READY_STEP := 0.35
const CHAT_POLL := 3.0
const BOT_LINES := [
	"Sẵn sàng rồi, chơi thôi!",
	"Coi chừng bom của mình nhé!",
	"Hẹn gặp ở giữa bản đồ!",
	"Ai thắng thì khao trà sữa nha.",
	"Lần này mình không nhường đâu!",
	"Nhớ né bom liên hoàn đó.",
]

var game: Node
var parts: Dictionary
var maps: Array[Dictionary] = []
var cards: Array[Dictionary] = []
var map_art: TextureRect
var map_name: Label
var map_info: Label
var start_button: Button
var ready_label: Label
var ready_clock := 0.0
var chat_scroll: ScrollContainer
var chat_list: VBoxContainer
var chat_input: LineEdit
var chat_hint: Label
var chat_lines: Array[Dictionary] = []
var announced := 0
var chat_after := 0
var chat_clock := 0.0
var chat_polling := false
var rng := RandomNumberGenerator.new()

func _init() -> void:
	super("sky")

## Built-in maps plus admin-published ones (MapCatalog), in catalog order.
func load_maps() -> void:
	maps.clear()
	for data in MapCatalog.all():
		var subtitle := str(data.get("subtitle", ""))
		if bool(data.get("custom", false)):
			subtitle += " · Bản đồ mới (admin)"
		maps.append({"id": str(data.get("id", "?")), "name": str(data.get("name", "?")).capitalize(), "subtitle": subtitle})
	if is_inside_tree() and map_art:
		refresh()

func _ready() -> void:
	name = "PcRoom"
	setup()
	load_maps()
	MapCatalog.changed.connect(load_maps)
	var root := page(canvas)
	parts = top_bar("Phòng luyện tập", leave, func(): open_settings(game.music_enabled, game._toggle_audio))
	root.add_child(parts.bar)
	var body := row(16, root)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left := card(Color(GLASS, 0.92), Color.WHITE, 24, 4, 16)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	var left_stack := column(12, left)
	var head := row(10, left_stack)
	stretch(text("Phòng vui vẻ · 1 người + 3 bot", 22, INK, head))
	pill("ĐẤU BOT", LAVENDER, Color.WHITE, 14, head)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_stack.add_child(grid)
	for i in 4:
		grid.add_child(fighter_card(i))
	for i in 4:
		grid.add_child(invite_card())
	var right := card(CREAM, Color.WHITE, 24, 4, 16)
	right.custom_minimum_size = Vector2(330, 0)
	body.add_child(right)
	var side := column(10, right)
	text("Bản đồ", 22, INK, side)
	var frame := card(Color.WHITE, Color("bfe3fb"), 18, 4, 6)
	side.add_child(frame)
	map_art = picture("", Vector2(290, 170))
	frame.add_child(map_art)
	var switch := row(8, side)
	switch.add_child(round_icon("left", func(): pick_map(-1), "sun", 44))
	var words := column(0, switch)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_name = text("", 20, INK, words)
	map_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_info = text("", 13, MUTED, words)
	map_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	switch.add_child(round_icon("right", func(): pick_map(1), "sun", 44))
	build_chat(side)
	ready_label = text("", 15, INK, side)
	ready_label.name = "ReadyStatus"
	ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_button = candy("", start, "sun", 26)
	start_button.name = "Start"
	start_button.custom_minimum_size = Vector2(0, 68)
	side.add_child(start_button)
	build_modal()
	visibility_changed.connect(_on_visibility)

## One of the four seats: 0 is the player (host), 1–3 are bots.
func fighter_card(index: int) -> PanelContainer:
	var holder := card(Color.WHITE, Color("cfe6fb"), 20, 4, 10)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var stack := column(4, holder)
	var top := row(6, stack)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(dot)
	var tag := text("", 13, MUTED, top)
	spacer(top)
	text("★ Chủ phòng" if index == 0 else "", 13, Color("e39b14"), top)
	var face := picture("", Vector2(120, 120))
	face.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(face)
	var who := text("", 18, INK, stack)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var entry := {"frame": holder, "dot": dot, "tag": tag, "face": face, "name": who}
	if index == 0:
		var switch := row(6, stack)
		switch.alignment = BoxContainer.ALIGNMENT_CENTER
		switch.add_child(round_icon("left", func(): pick_hero(-1), "sky", 34))
		entry.hero = text("", 13, MUTED, switch)
		switch.add_child(round_icon("right", func(): pick_hero(1), "sky", 34))
	else:
		entry.badge = pill("", MINT, Color.WHITE, 12, stack)
	cards.append(entry)
	return holder

func invite_card() -> PanelContainer:
	var holder := card(Color("dfe6f0"), Color("eef2f8"), 20, 3, 10)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var stack := column(10, holder)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	var label := text("Ô trống", 15, MUTED, stack)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var invite := sized(candy("+ Mời", invite_friends, "ghost", 16), Vector2(110, 46))
	invite.name = "InviteSlot"
	invite.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(invite)
	return holder

## Room chat: scrollable log, input and send. Signed-in players chat through the
## server room channel (other people in the room see it); bots answer locally.
func build_chat(parent: Control) -> void:
	var box := card(Color.WHITE, Color("bfe3fb"), 16, 3, 8)
	box.name = "RoomChat"
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	var stack := column(6, box)
	var head := row(6, stack)
	text("Chat phòng", 15, INK, head)
	spacer(head)
	chat_hint = text("", 11, MUTED, head)
	chat_scroll = ScrollContainer.new()
	chat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(chat_scroll)
	chat_list = column(4)
	chat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_scroll.add_child(chat_list)
	var line := row(6, stack)
	chat_input = LineEdit.new()
	chat_input.name = "ChatInput"
	chat_input.placeholder_text = "Nhắn cho cả phòng… (Enter)"
	chat_input.max_length = 200
	chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_input.add_theme_font_size_override("font_size", 14)
	chat_input.add_theme_color_override("font_color", INK)
	chat_input.add_theme_color_override("font_placeholder_color", MUTED)
	chat_input.add_theme_stylebox_override("normal", box_style(Color("f3f9ff"), Color("cfe6fb")))
	chat_input.add_theme_stylebox_override("focus", box_style(Color.WHITE, SKY))
	chat_input.text_submitted.connect(func(_value): send_chat())
	line.add_child(chat_input)
	var send := round_icon("send", send_chat, "sky", 38)
	send.name = "ChatSend"
	line.add_child(send)

func box_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := box(fill, border, 10, 2, 8)
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

func reset_chat() -> void:
	chat_lines.clear()
	announced = 0
	chat_after = 0
	if chat_input:
		chat_input.clear()
	render_chat()

## kind: system, me, bot or player (another person, from the server).
func add_chat(who: String, message: String, kind: String) -> void:
	chat_lines.append({"who": who, "text": message, "kind": kind})
	if chat_lines.size() > 80:
		chat_lines.pop_front()
	render_chat()

func render_chat() -> void:
	if chat_list == null:
		return
	for child in chat_list.get_children():
		chat_list.remove_child(child)
		child.queue_free()
	var colors := {"system": Color("2b88cf"), "me": Color("d9890b"), "bot": MUTED, "player": INK}
	for entry in chat_lines:
		var prefix: String = "Hệ thống: " if entry.kind == "system" else str(entry.who) + ": "
		var label := text(prefix + str(entry.text), 13, colors.get(entry.kind, INK), chat_list)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_hint.text = "đồng bộ máy chủ" if online_chat() else "chỉ trên máy"
	await get_tree().process_frame
	if is_instance_valid(chat_scroll):
		chat_scroll.scroll_vertical = int(chat_scroll.get_v_scroll_bar().max_value)

func online_chat() -> bool:
	return AuthSession.has_session() and str(game.reporter.room_key) != ""

func send_chat() -> void:
	var message := chat_input.text.strip_edges()
	if message.is_empty():
		return
	chat_input.clear()
	var me: String = AuthSession.account_name if AuthSession.has_session() else "Bạn"
	add_chat(me, message, "me")
	if online_chat():
		var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_POST, "/v1/chat", {"channel": "room", "room": game.reporter.room_key, "body": message})
		if reply.status == 201 and reply.data is Dictionary:
			chat_after = maxi(chat_after, int(reply.data.get("id", 0)))
		elif reply.status != 201:
			add_chat("", "Chưa gửi được lên máy chủ: " + str(reply.error), "system")
	# A ready bot answers after a short pause (bots are local, never sent to the server).
	var ready := bots_ready()
	if ready > 0:
		await get_tree().create_timer(rng.randf_range(0.7, 1.4)).timeout
		if is_visible_in_tree() and not chat_lines.is_empty():
			add_chat(bot_name(rng.randi_range(1, ready)), BOT_LINES[rng.randi() % BOT_LINES.size()], "bot")

func bot_name(seat: int) -> String:
	var heroes: Array = game.bot_heroes()
	return "Bot " + game.HERO_NAMES[game.HEROES.find(heroes[seat - 1])].capitalize()

## Messages from other people in the same room (none yet in bot practice, but the
## channel is shared with any member the server knows about).
func poll_chat() -> void:
	if chat_polling or not online_chat():
		return
	chat_polling = true
	var path := "/v1/chat?channel=room&room=%s&after=%d" % [str(game.reporter.room_key).uri_encode(), chat_after]
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_GET, path)
	chat_polling = false
	if reply.status != 200 or not reply.data is Dictionary:
		return
	for message in reply.data.get("messages", []):
		chat_after = maxi(chat_after, int(message.id))
		if not bool(message.get("mine", false)):
			add_chat(str(message.sender.name), str(message.body), "player")

func _on_visibility() -> void:
	ScreenFill.set_fill(get_tree(), is_visible_in_tree())
	if is_visible_in_tree():
		ready_clock = 0.0
		announced = 0
		if chat_lines.is_empty():
			add_chat("", "Đã tạo phòng luyện tập.", "system")
		refresh()

func bots_ready() -> int:
	return mini(3, int(ready_clock / READY_STEP))

## Seats that must be ready before the host can start: every occupied seat except the host.
func ready_count() -> Vector2i:
	return Vector2i(bots_ready(), cards.size() - 1)

func all_ready() -> bool:
	var count := ready_count()
	return count.y > 0 and count.x >= count.y

func refresh() -> void:
	var heroes: Array = [game.HEROES[game.selected_hero]] + game.bot_heroes()
	refresh_top_bar(parts, heroes[0])
	var ready := bots_ready()
	for i in cards.size():
		var entry: Dictionary = cards[i]
		var hero_index: int = game.HEROES.find(heroes[i])
		var color: Color = game.HERO_COLORS[hero_index]
		var style := (entry.frame as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
		style.border_color = color
		style.bg_color = Color("fff2df") if i == 0 else Color.WHITE
		(entry.dot as ColorRect).color = color
		(entry.face as TextureRect).texture = load("res://assets/characters/portraits/%s.png" % heroes[i])
		var hero_name: String = game.HERO_NAMES[hero_index].capitalize()
		if i == 0:
			(entry.tag as Label).text = "Lv.%d" % int(UIState.profile.get("level", 1))
			(entry.name as Label).text = AuthSession.account_name if AuthSession.has_session() else "Bạn"
			(entry.hero as Label).text = hero_name
		else:
			(entry.tag as Label).text = "BOT"
			(entry.name as Label).text = "Bot " + hero_name
			var is_ready := i <= ready
			(entry.badge as Label).text = "SẴN SÀNG" if is_ready else "Đang vào…"
			((entry.badge as Label).get_parent().get_theme_stylebox("panel") as StyleBoxFlat).bg_color = MINT if is_ready else Color("b3c1d6")
	var map: Dictionary = maps[clampi(game.selected_level, 0, maps.size() - 1)]
	map_art.texture = MapCatalog.preview(map.id)
	map_name.text = map.name
	map_info.text = map.subtitle
	while announced < ready:
		announced += 1
		add_chat("", "Bot %s đã sẵn sàng." % game.HERO_NAMES[game.HEROES.find(heroes[announced])].capitalize(), "system")
	var count := ready_count()
	ready_label.text = "Đã sẵn sàng: %d/%d người chơi" % [count.x, count.y]
	ready_label.add_theme_color_override("font_color", MINT.darkened(0.25) if all_ready() else MUTED)
	start_button.disabled = not all_ready()
	start_button.text = "BẮT ĐẦU" if all_ready() else "CHỜ SẴN SÀNG…"
	start_button.tooltip_text = "" if all_ready() else "Tất cả người chơi phải sẵn sàng"

## A practice match runs on this computer, so friends play in a practice room on
## the arena instead: same map, server bots fill the empty seats and give theirs
## up to each friend who accepts the invite.
func invite_friends() -> void:
	if not AuthSession.has_session():
		notice("MỜI BẠN", "Đăng nhập tài khoản để mời bạn bè chơi cùng.")
		return
	var map: Dictionary = maps[clampi(game.selected_level, 0, maps.size() - 1)]
	notice("LUYỆN TẬP CÙNG BẠN BÈ", "Mở phòng luyện tập online trên %s: bạn + 3 bot, tối đa 4 người. Bạn bè vào sẽ thay ghế của bot. Mở phòng và mời bạn?" % map.name, func(): open_online(str(map.id)), "MỞ PHÒNG")

func open_online(map_id: String) -> void:
	if await OnlineArena.create_room(map_id, game.HEROES[game.selected_hero], true):
		game.pc_screens["online"].invite_on_open = true
		game.show_pc_screen("online")
	else:
		notice("PHÒNG LUYỆN TẬP", OnlineArena.last_error)

func pick_map(step: int) -> void:
	game._select_level(posmod(game.selected_level + step, maps.size()))
	refresh()

## Changing hero reshuffles the bot line-up, so bots re-confirm readiness.
func pick_hero(step: int) -> void:
	game._select_hero(posmod(game.selected_hero + step, game.HEROES.size()))
	game._sound("ui_select")
	ready_clock = 0.0
	announced = 0
	add_chat("", "Đổi nhân vật: các bot xác nhận sẵn sàng lại.", "system")
	refresh()

func start() -> void:
	if all_ready():
		game._new_round()

func leave() -> void:
	game.show_pc_screen("lobby")

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_action_pressed("ui_cancel"):
		return
	if chat_input.has_focus():
		chat_input.release_focus()
		get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()
	if modal.visible:
		close_modal()
	else:
		leave()

func _process(delta: float) -> void:
	super._process(delta)
	if not is_visible_in_tree():
		return
	var before := bots_ready()
	ready_clock += delta
	if bots_ready() != before:
		game._sound("ui_select")
		refresh()
	chat_clock += delta
	if chat_clock >= CHAT_POLL:
		chat_clock = 0.0
		poll_chat()
