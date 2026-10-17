extends "res://scripts/ui/pc/pc_kit.gd"
## Online room (protocol v2) on PC: the waiting room (8 seats, Sẵn sàng, room
## chat) and the match, both drawn only from server snapshots (OnlineArena).
## The keyboard sends intents (up/down/left/right/bomb/ready); positions, bombs,
## blasts, deaths, timer and winner always come from the server.
const TILE := 64
const MOVE_SECONDS := 0.15
const RESEND := 0.09
const CHAT_POLL := 3.0

var game: Node
var parts: Dictionary
var levels: Dictionary = {}  # map id -> level JSON (theme, wall, crate, bomb, fx, name)
var room_view: Control
var battle_view: Control
var title_label: Label
var seats: Array[Dictionary] = []
var map_art: TextureRect
var map_name: Label
var map_info: Label
var ready_button: Button
var status_label: Label
var chat_scroll: ScrollContainer
var chat_list: VBoxContainer
var chat_input: LineEdit
var chat_after := 0
var chat_clock := 0.0
var chat_polling := false
var chat_key := ""
# Battle
var board_area: Control
var board: Node2D
var floor_layer: Node2D
var block_layer: Node2D
var piece_layer: Node2D
var side_map: Label
var side_room: Label
var side_timer: Label
var side_alive: Label
var side_cards: Array[Dictionary] = []
var stat_round: Label
var stat_status: Label
var backdrop: TextureRect
var board_frame: Panel
var banner: Label
var result_box: PanelContainer
var result_title: Label
var result_detail: Label
var built_key := ""  # "<map>:<round>" the board was built for
var grid: Array = []
var walls: Dictionary = {}
var crates: Dictionary = {}  # Vector2i -> Sprite2D
var bombs: Dictionary = {}  # bomb id -> Sprite2D
var flames: Dictionary = {}  # Vector2i -> AnimatedSprite2D
var fighters: Dictionary = {}  # session id -> {root, sprite, name, from, to, t}
var held := ""
var resend := 0.0
var last_phase := ""

func _init() -> void:
	super("sky")

func _ready() -> void:
	name = "PcOnline"
	setup()
	for path in game.LEVEL_FILES:
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			levels[str(data.id)] = data
	var root := page(canvas)
	parts = top_bar("Phòng online", ask_leave, func(): open_settings(game.music_enabled, game._toggle_audio))
	title_label = parts.title
	root.add_child(parts.bar)
	build_room(root)
	build_battle(root)
	build_modal()
	OnlineArena.snapshot_received.connect(_on_snapshot)
	OnlineArena.closed.connect(_on_closed)
	visibility_changed.connect(_on_visibility)

# ------------------------------------------------------------------ waiting room

func build_room(root: VBoxContainer) -> void:
	var body := row(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	room_view = body
	var left := card(Color(GLASS, 0.92), Color.WHITE, 24, 4, 16)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	var left_stack := column(12, left)
	var head := row(10, left_stack)
	stretch(text("Người chơi trong phòng · tối đa 8", 22, INK, head))
	pill("ONLINE", MINT, Color.WHITE, 14, head)
	var grid_box := GridContainer.new()
	grid_box.columns = 4
	grid_box.add_theme_constant_override("h_separation", 12)
	grid_box.add_theme_constant_override("v_separation", 12)
	grid_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_stack.add_child(grid_box)
	for i in 8:
		grid_box.add_child(seat_card(i))
	var right := column(12, body)
	right.custom_minimum_size = Vector2(380, 0)
	var map_card := card(Color.WHITE, Color("bfe3fb"), 20, 3, 12)
	right.add_child(map_card)
	var map_stack := column(6, map_card)
	map_art = picture("", Vector2(340, 150))
	map_stack.add_child(map_art)
	map_name = title_text("", 24, INK, map_stack)
	map_info = text("", 15, MUTED, map_stack)
	map_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label = text("", 17, INK, right)
	status_label.name = "RoomStatus"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ready_button = sized(candy("SẴN SÀNG", press_ready, "sun", 24), Vector2(0, 64)) as Button
	ready_button.name = "Ready"
	right.add_child(ready_button)
	build_chat(right)

func seat_card(index: int) -> PanelContainer:
	var holder := card(Color.WHITE, Color("cfe6fb"), 18, 3, 8)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.custom_minimum_size = Vector2(150, 0)
	var stack := column(4, holder)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	var face := picture("", Vector2(96, 96))
	face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(face)
	var who := text("Ghế trống", 16, MUTED, stack)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.clip_text = true
	who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var state := pill("", MUTED, Color.WHITE, 13, stack)
	seats.append({"holder": holder, "face": face, "name": who, "state": state, "index": index})
	return holder

func build_chat(parent: Control) -> void:
	var holder := card(Color.WHITE, Color("bfe3fb"), 16, 3, 8)
	holder.name = "RoomChat"
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(holder)
	var stack := column(6, holder)
	text("Chat phòng", 15, INK, stack)
	chat_scroll = ScrollContainer.new()
	chat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_scroll.custom_minimum_size = Vector2(0, 90)
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
	chat_input.add_theme_stylebox_override("normal", box(Color("f3f9ff"), Color("cfe6fb"), 10, 2, 8))
	chat_input.add_theme_stylebox_override("focus", box(Color.WHITE, SKY, 10, 2, 8))
	chat_input.text_submitted.connect(func(_value): send_chat())
	line.add_child(chat_input)
	line.add_child(round_icon("send", send_chat, "sky", 38))

func add_chat(line_text: String, color := INK) -> void:
	var label := text(line_text, 13, color, chat_list)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	while chat_list.get_child_count() > 80:
		chat_list.get_child(0).free()
	await get_tree().process_frame
	if is_instance_valid(chat_scroll):
		chat_scroll.scroll_vertical = int(chat_scroll.get_v_scroll_bar().max_value)

func send_chat() -> void:
	var message := chat_input.text.strip_edges()
	if message.is_empty() or chat_key.is_empty():
		return
	chat_input.clear()
	add_chat("%s: %s" % [AuthSession.account_name, message], Color("d9890b"))
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_POST, "/v1/chat", {"channel": "room", "room": chat_key, "body": message})
	if reply.status == 201 and reply.data is Dictionary:
		chat_after = maxi(chat_after, int(reply.data.get("id", 0)))
	else:
		add_chat("Hệ thống: chưa gửi được tin nhắn (%s)" % str(reply.error), Color("2b88cf"))

func poll_chat() -> void:
	if chat_polling or chat_key.is_empty() or not AuthSession.has_session():
		return
	chat_polling = true
	var path := "/v1/chat?channel=room&room=%s&after=%d" % [chat_key.uri_encode(), chat_after]
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_GET, path)
	chat_polling = false
	if reply.status != 200 or not reply.data is Dictionary:
		return
	for message in reply.data.get("messages", []):
		chat_after = maxi(chat_after, int(message.id))
		if not bool(message.get("mine", false)):
			add_chat("%s: %s" % [str(message.sender.name), str(message.body)])

func press_ready() -> void:
	OnlineArena.send_action("ready")
	ready_button.disabled = true
	ready_button.text = "ĐÃ SẴN SÀNG"

func render_room(snap: Dictionary) -> void:
	var map_id := str(snap.get("map", ""))
	var level: Dictionary = levels.get(map_id, {})
	var number := "%03d" % int(snap.get("number", 0))
	title_label.text = "Phòng %s · %s" % [number, str(level.get("name", map_id)).capitalize()]
	map_art.texture = load("res://assets/level_previews/%s.png" % map_id) if levels.has(map_id) else null
	map_name.text = str(level.get("name", map_id)).capitalize()
	var tier := str(level.get("subtitle", "")).get_slice("•", 0).strip_edges()
	map_info.text = "%s · Phòng %s · Ván %d · Mỗi người 1 bom, tầm nổ 2 ô. Người cuối cùng còn sống thắng." % [tier, number, int(snap.get("round", 1))]
	var players: Array = snap.get("players", [])
	players.sort_custom(func(a, b): return int(a.slot) < int(b.slot))
	var ready := 0
	for p in players:
		ready += 1 if bool(p.get("ready", false)) else 0
	for i in seats.size():
		var seat: Dictionary = seats[i]
		var frame := seat.holder.get_theme_stylebox("panel") as StyleBoxFlat
		if i < players.size():
			var p: Dictionary = players[i]
			var mine := str(p.id) == OnlineArena.session_id
			seat.face.texture = load("res://assets/characters/portraits/%s.png" % hero_of(p))
			seat.name.text = str(p.name) + (" (Bạn)" if mine else "")
			seat.name.add_theme_color_override("font_color", INK)
			seat.state.text = "Sẵn sàng" if p.ready else "Chưa sẵn sàng"
			(seat.state.get_parent().get_theme_stylebox("panel") as StyleBoxFlat).bg_color = MINT if p.ready else Color("ffaa45")
			seat.state.get_parent().show()
			frame.border_color = SUN if mine else Color("cfe6fb")
		else:
			seat.face.texture = null
			seat.name.text = "Ghế trống"
			seat.name.add_theme_color_override("font_color", MUTED)
			seat.state.get_parent().hide()
			frame.border_color = Color("cfe6fb")
	var me: Dictionary = OnlineArena.me()
	var phase := str(snap.get("phase", "waiting"))
	ready_button.disabled = phase != "waiting" or bool(me.get("ready", false))
	ready_button.text = "ĐÃ SẴN SÀNG" if bool(me.get("ready", false)) else "SẴN SÀNG"
	if phase == "countdown":
		status_label.text = "Bắt đầu sau %d…" % ceili(maxf(0.0, float(snap.deadline) - float(snap.now)) / 1000.0)
	elif players.size() < 2:
		status_label.text = "%d/8 người · Cần ít nhất 2 người. Mời bạn bè vào phòng %s!" % [players.size(), number]
	else:
		status_label.text = "%d/8 người · %d/%d đã sẵn sàng. Ván bắt đầu khi tất cả sẵn sàng." % [players.size(), ready, players.size()]

func hero_of(p: Dictionary) -> String:
	var hero := str(p.get("hero", ""))
	return hero if hero in game.HEROES else game.HEROES[int(p.get("slot", 0)) % game.HEROES.size()]

# ------------------------------------------------------------------ battle

## Same layout as the bot battle (pc_battle_hud): the board in a dark frame on
## the left with a CHỈ SỐ bar below it, and a sidebar on the right with the map,
## the time limit, players still alive, player cards and THOÁT RA.
func build_battle(root: VBoxContainer) -> void:
	backdrop = TextureRect.new()
	backdrop.texture = load("res://assets/backdrop.png")
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.hide()
	add_child(backdrop)
	move_child(backdrop, sky.get_index() + 1)
	battle_view = row(14)
	battle_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle_view.hide()
	root.add_child(battle_view)
	var left := column(12, battle_view)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_area = Control.new()
	board_area.name = "Board"
	board_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_area.custom_minimum_size = Vector2(700, 480)
	board_area.resized.connect(fit_board)
	left.add_child(board_area)
	# Thin frame around the board, transparent inside (as in the bot battle).
	board_frame = Panel.new()
	var rim := box(Color.TRANSPARENT, Color("0d2f5c"), 18, 8, 0)
	rim.draw_center = false
	rim.shadow_color = Color(0.02, 0.12, 0.3, 0.35)
	rim.shadow_size = 10
	board_frame.add_theme_stylebox_override("panel", rim)
	board_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_area.add_child(board_frame)
	board = Node2D.new()
	board_area.add_child(board)
	floor_layer = Node2D.new()
	block_layer = Node2D.new()
	piece_layer = Node2D.new()
	piece_layer.y_sort_enabled = true
	for layer in [floor_layer, block_layer, piece_layer]:
		board.add_child(layer)
	banner = title_text("", 96, Color.WHITE, board_area)
	banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.add_theme_constant_override("outline_size", 22)
	result_box = card(CREAM, Color.WHITE, 28, 5, 22)
	result_box.name = "Result"
	result_box.hide()
	board_area.add_child(result_box)
	var result_stack := column(8, result_box)
	result_title = title_text("", 48, SUN, result_stack)
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_detail = text("", 19, INK, result_stack)
	result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_detail.custom_minimum_size = Vector2(460, 0)
	build_stats_bar(left)
	build_sidebar(battle_view)

## CHỈ SỐ: the server's fixed rules (one bomb, range 2, one tile per 150 ms; no
## items online yet), the round, and a status line.
func build_stats_bar(parent: Control) -> void:
	var bar := card(Color("1567ae", 0.96), Color("74d3f0"), 20, 4, 8)
	bar.custom_minimum_size = Vector2(0, 66)
	parent.add_child(bar)
	var line := row(10, bar)
	title_text("CHỈ SỐ", 18, Color.WHITE, line)
	for spec in [["Bom ×1", "res://assets/items/extra_bomb.png"], ["Tầm 2", "res://assets/items/flame.png"], ["Tốc độ 1.0", "res://assets/items/shoe.png"]]:
		var chip := card(Color("e9f6ff"), Color("9fd7ff"), 14, 2, 4)
		line.add_child(chip)
		var chip_line := row(4, chip)
		chip_line.add_child(picture(spec[1], Vector2(30, 30)))
		text(spec[0], 15, INK, chip_line)
	var round_chip := card(Color("fff4d4"), SUN, 14, 2, 4)
	line.add_child(round_chip)
	var round_line := row(6, round_chip)
	text("Ván", 14, INK, round_line)
	stat_round = title_text("1", 22, SUN, round_line)
	stat_status = stretch(text("", 15, Color.WHITE, line))
	stat_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func build_sidebar(parent: Control) -> void:
	var side := card(Color("1567ae", 0.96), Color("74d3f0"), 22, 4, 12)
	side.custom_minimum_size = Vector2(270, 0)
	parent.add_child(side)
	var stack := column(10, side)
	var head := row(6, stack)
	side_map = stretch(title_text("", 20, Color.WHITE, head))
	var gear := round_icon("gear", func(): open_settings(game.music_enabled, game._toggle_audio), "ghost", 40)
	gear.tooltip_text = "Cài đặt"
	gear.focus_mode = Control.FOCUS_NONE
	head.add_child(gear)
	side_room = text("", 13, Color("7ff0c2"), stack)
	var clock := PanelContainer.new()
	clock.add_theme_stylebox_override("panel", lipped(Color("0d3f78"), Color("08284f"), 5))
	stack.add_child(clock)
	var clock_line := row(8, clock)
	text("GIỚI HẠN", 15, Color("9fd7ff"), clock_line)
	side_timer = title_text("3:00", 34, Color.WHITE, clock_line)
	side_timer.name = "Timer"
	side_timer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var alive_line := row(6, stack)
	text("Còn sống", 15, Color("d5f3ff"), alive_line)
	spacer(alive_line)
	side_alive = title_text("", 26, CORAL, alive_line)
	text("NGƯỜI CHƠI", 14, Color("9fd7ff"), stack)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)
	var list := column(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for i in 8:
		var entry := card(Color("e9f6ff"), Color("9fd7ff"), 14, 3, 6)
		list.add_child(entry)
		var line := row(8, entry)
		var face_frame := card(Color("ffe9b0"), Color.WHITE, 24, 2, 0)
		face_frame.custom_minimum_size = Vector2(48, 48)
		line.add_child(face_frame)
		var face := picture("", Vector2(46, 46))
		face_frame.add_child(face)
		var words := column(-2, line)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var who := stretch(text("", 15, INK, words))
		var state := text("", 12, MINT, words)
		side_cards.append({"line": entry, "face": face, "name": who, "state": state})
	var keys := text("WASD / mũi tên: di chuyển · Space: đặt bom\nEsc: rời phòng · M: âm thanh", 11, Color("d5f3ff"), stack)
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var leave_button := candy("THOÁT RA", ask_leave, "coral", 22)
	leave_button.name = "Leave"
	leave_button.tooltip_text = "Rời phòng online, về sảnh"
	leave_button.focus_mode = Control.FOCUS_NONE
	leave_button.custom_minimum_size = Vector2(0, 56)
	stack.add_child(leave_button)

func fit_board() -> void:
	if board == null or result_box == null:
		return
	var columns: int = grid[0].size() if not grid.is_empty() else 15
	var rows: int = grid.size() if not grid.is_empty() else 11
	var art := Vector2(columns * TILE, rows * TILE)
	var room := board_area.size - Vector2(16, 16)
	var scale_by := minf(room.x / art.x, room.y / art.y)
	board.scale = Vector2.ONE * scale_by
	board.position = (board_area.size - art * scale_by) / 2.0
	board_frame.position = board.position - Vector2(8, 8)
	board_frame.size = art * scale_by + Vector2(16, 16)
	result_box.reset_size()
	result_box.position = (board_area.size - result_box.size) / 2.0

func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE * 0.5, cell.y * TILE + TILE * 0.5)

func clear_board() -> void:
	for layer in [floor_layer, block_layer, piece_layer]:
		for child in layer.get_children():
			child.queue_free()
	walls.clear()
	crates.clear()
	bombs.clear()
	flames.clear()
	fighters.clear()

## Floor, walls and crates come from the snapshot grid (0 floor, 1 wall, 2 crate),
## textured with the map's own theme.
func build_board(snap: Dictionary) -> void:
	clear_board()
	var level: Dictionary = levels.get(str(snap.map), levels.get("park", {}))
	grid = snap.grid.duplicate(true)
	var floors: Array = []
	for n in range(2):
		for m in range(4):
			floors.append(load("res://assets/tiles/%s/%d_%d.png" % [level.get("theme", "grass"), n, m]))
	var wall_tex: Texture2D = load("res://assets/obstacles/%s/00.png" % level.get("wall", "stone_wall"))
	var crate_tex: Texture2D = load("res://assets/obstacles/%s/00.png" % level.get("crate", "wood_crate"))
	for y in grid.size():
		for x in grid[y].size():
			var cell := Vector2i(x, y)
			var ground := Sprite2D.new()
			ground.texture = floors[(y % 2) * 4 + ((x + y) % 4)]
			ground.position = cell_center(cell)
			floor_layer.add_child(ground)
			var tile := int(grid[y][x])
			if tile == 1 or tile == 2:
				var block := Sprite2D.new()
				block.texture = wall_tex if tile == 1 else crate_tex
				block.position = cell_center(cell)
				block_layer.add_child(block)
				if tile == 1:
					walls[cell] = block
				else:
					crates[cell] = block
	fit_board()

func render_battle(snap: Dictionary) -> void:
	var key := "%s:%d" % [snap.get("map", ""), int(snap.get("round", 0))]
	if key != built_key:
		built_key = key
		build_board(snap)
	var level: Dictionary = levels.get(str(snap.map), {})
	side_map.text = str(level.get("name", snap.map)).capitalize()
	# Crates destroyed by the server.
	for y in snap.grid.size():
		for x in snap.grid[y].size():
			var cell := Vector2i(x, y)
			if int(snap.grid[y][x]) != 2 and crates.has(cell):
				crates[cell].queue_free()
				crates.erase(cell)
	# Bombs.
	var seen := {}
	for b in snap.get("bombs", []):
		var id := int(b.id)
		seen[id] = true
		if not bombs.has(id):
			var sprite := Sprite2D.new()
			sprite.texture = load("res://assets/bombs/%s.png" % level.get("bomb", "water_blue"))
			sprite.scale = Vector2(0.68, 0.68)
			sprite.position = cell_center(Vector2i(int(b.x), int(b.y)))
			piece_layer.add_child(sprite)
			bombs[id] = sprite
			game._sound("place_bomb")
	for id in bombs.keys():
		if not seen.has(id):
			bombs[id].queue_free()
			bombs.erase(id)
	# Flames.
	var lit := {}
	var fresh := false
	for f in snap.get("flames", []):
		var cell := Vector2i(int(f.x), int(f.y))
		lit[cell] = true
		if not flames.has(cell):
			fresh = true
			flames[cell] = splash(cell, str(level.get("fx", "water_splash")))
	for cell in flames.keys():
		if not lit.has(cell):
			flames[cell].queue_free()
			flames.erase(cell)
	if fresh:
		game._sound("explosion")
	# Players: smooth 150 ms slide toward the server cell.
	var present := {}
	for p in snap.get("players", []):
		var id := str(p.id)
		present[id] = true
		var cell := Vector2i(int(p.x), int(p.y))
		if not fighters.has(id):
			fighters[id] = spawn_fighter(p, cell)
		var f: Dictionary = fighters[id]
		if f.to != cell:
			var step: Vector2i = cell - f.to
			f.from = f.root.position
			f.to = cell
			f.t = 0.0
			f.rest = 0.0
			f.sprite.action("walk_right" if step.x > 0 else "walk_left" if step.x < 0 else "walk_down" if step.y > 0 else "walk_up")
		f.alive = bool(p.alive)
		f.root.modulate = Color.WHITE if f.alive else Color(1, 1, 1, 0.35)
		if not f.alive:
			f.sprite.action("lose")
	for id in fighters.keys():
		if not present.has(id):
			fighters[id].root.queue_free()
			fighters.erase(id)
	render_side(snap)

func splash(cell: Vector2i, effect: String) -> AnimatedSprite2D:
	var node := AnimatedSprite2D.new()
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("blast")
	frames.set_animation_speed("blast", 15.0)
	frames.set_animation_loop("blast", false)
	for n in range(6 if effect == "water_splash" else 8):
		frames.add_frame("blast", load("res://assets/effects/%s/%02d.png" % [effect, n]))
	node.sprite_frames = frames
	node.position = cell_center(cell)
	node.scale = Vector2(0.8, 0.8)
	node.z_index = 4
	block_layer.add_child(node)
	node.play("blast")
	return node

func spawn_fighter(p: Dictionary, cell: Vector2i) -> Dictionary:
	var holder := Node2D.new()
	holder.position = cell_center(cell)
	piece_layer.add_child(holder)
	var visual: AnimatedSprite2D = game.HERO_SCRIPT.new()
	holder.add_child(visual)
	visual.configure(hero_of(p))
	var mine := str(p.id) == OnlineArena.session_id
	var tag := Label.new()
	tag.text = ("▼ " if mine else "") + str(p.name)
	tag.add_theme_font_size_override("font_size", 18)
	tag.add_theme_color_override("font_color", SUN if mine else Color.WHITE)
	tag.add_theme_color_override("font_outline_color", Color("0d2f5c"))
	tag.add_theme_constant_override("outline_size", 6)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.size = Vector2(160, 24)
	tag.position = Vector2(-80, -66)
	holder.add_child(tag)
	return {"root": holder, "sprite": visual, "from": holder.position, "to": cell, "t": 1.0, "rest": 0.0, "alive": true}

func render_side(snap: Dictionary) -> void:
	var phase := str(snap.get("phase", ""))
	var left := maxf(0.0, float(snap.get("deadline", 0)) - float(snap.get("now", 0))) / 1000.0
	side_room.text = "● Phòng online %03d" % int(snap.get("number", 0))
	side_timer.text = "%d:%02d" % [int(left) / 60, int(left) % 60] if phase == "playing" else "0:00"
	side_timer.add_theme_color_override("font_color", Color("ffe17b") if phase == "playing" and left <= 30.0 else Color.WHITE)
	stat_round.text = str(int(snap.get("round", 1)))
	var players: Array = snap.get("players", [])
	players.sort_custom(func(a, b): return int(a.slot) < int(b.slot))
	var alive := 0
	for p in players:
		alive += 1 if p.alive else 0
	side_alive.text = "%d/%d" % [alive, players.size()]
	for i in side_cards.size():
		var entry: Dictionary = side_cards[i]
		entry.line.visible = i < players.size()
		if i >= players.size():
			continue
		var p: Dictionary = players[i]
		var hero := hero_of(p)
		var mine := str(p.id) == OnlineArena.session_id
		entry.face.texture = load("res://assets/characters/portraits/%s.png" % hero)
		entry.face.modulate.a = 1.0 if p.alive else 0.45
		entry.name.text = str(p.name) + (" (Bạn)" if mine else "")
		entry.name.tooltip_text = entry.name.text
		entry.name.add_theme_color_override("font_color", game.HERO_COLORS[maxi(0, game.HEROES.find(hero))].darkened(0.25))
		entry.state.text = ("Đang chơi" if p.alive else "Bị loại")
		entry.state.add_theme_color_override("font_color", MINT.darkened(0.15) if p.alive else CORAL)
		(entry.line.get_theme_stylebox("panel") as StyleBoxFlat).border_color = SUN if mine else Color("9fd7ff")
	var me: Dictionary = OnlineArena.me()
	if phase == "finished":
		stat_status.text = "Ván đã kết thúc."
	elif not me.is_empty() and not me.get("alive", true):
		stat_status.text = "Bạn đã bị loại · đang xem trận."
	else:
		stat_status.text = "Phá thùng và hạ %d đối thủ!" % maxi(0, alive - 1)
	if phase == "finished":
		var winner := str(snap.get("winner", "")) if snap.get("winner") != null else ""
		var name := ""
		for p in players:
			if str(p.id) == winner:
				name = str(p.name)
		if winner == "":
			result_title.text = "HÒA!"
			result_detail.text = "Không ai trụ lại cuối cùng."
		elif winner == OnlineArena.session_id:
			result_title.text = "BẠN THẮNG!"
			result_detail.text = "Bạn là người cuối cùng còn trụ lại."
		else:
			result_title.text = "THUA RỒI!"
			result_detail.text = "%s thắng ván này." % name
		result_detail.text += "\nVề phòng chờ sau %d giây, bấm SẴN SÀNG để chơi ván mới." % ceili(left)
		result_box.show()
		fit_board()
	else:
		result_box.hide()

# ------------------------------------------------------------------ flow

func _on_snapshot(snap: Dictionary) -> void:
	if not is_inside_tree():
		return
	chat_key = str(snap.get("roomKey", ""))
	var phase := str(snap.get("phase", "waiting"))
	var in_battle := phase in ["playing", "finished"]
	room_view.visible = not in_battle
	battle_view.visible = in_battle
	parts.bar.visible = not in_battle
	# The match uses the bot battle's dark backdrop; the waiting room keeps the sky.
	sky.visible = not in_battle
	backdrop.visible = in_battle
	if in_battle:
		render_battle(snap)
		if phase == "playing" and last_phase != "playing":
			show_banner("BẮT ĐẦU!")
			game._sound("round_start")
	else:
		built_key = ""
		render_room(snap)
	last_phase = phase

func show_banner(message: String) -> void:
	banner.text = message
	banner.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(0.9)
	tween.tween_property(banner, "modulate:a", 0.0, 0.4)

func _on_closed(reason: String) -> void:
	if not visible:
		return
	clear_board()
	built_key = ""
	game.show_pc_screen("lobby")
	if reason != "":
		game.pc_screens["lobby"].notice(reason + " Chọn phòng khác hoặc tạo phòng mới.", "PHÒNG ONLINE", "people")

func ask_leave() -> void:
	if str(OnlineArena.snapshot.get("phase", "")) == "playing" and OnlineArena.me().get("alive", false):
		notice("RỜI TRẬN?", "Trận đang diễn ra. Rời phòng sẽ bị tính là bị hạ.", leave, "RỜI PHÒNG")
	else:
		leave()

func leave() -> void:
	OnlineArena.leave()

func _on_visibility() -> void:
	if is_visible_in_tree():
		chat_after = 0
		chat_clock = 0.0
		last_phase = ""
		for child in chat_list.get_children():
			child.queue_free()
		add_chat("Hệ thống: bạn đã vào phòng. Bấm SẴN SÀNG khi muốn chơi.", Color("2b88cf"))
		refresh_top_bar(parts, game.HEROES[game.selected_hero])
		if not OnlineArena.snapshot.is_empty():
			_on_snapshot(OnlineArena.snapshot)

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		if modal.visible:
			close_modal()
		else:
			ask_leave()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_SPACE and battle_view.visible:
		OnlineArena.send_action("bomb")
		get_viewport().set_input_as_handled()

func held_direction() -> String:
	if chat_input.has_focus():
		return ""
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		return "left"
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		return "right"
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		return "up"
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		return "down"
	return ""

func _process(delta: float) -> void:
	super(delta)
	backdrop.position = Vector2.ZERO
	backdrop.size = sky.size
	if not is_visible_in_tree():
		return
	if room_view.visible:
		chat_clock -= delta
		if chat_clock <= 0.0:
			chat_clock = CHAT_POLL
			poll_chat()
	if battle_view.visible:
		# Intent only: a held key is re-sent so the server's one-step buffer stays full.
		var direction := held_direction()
		resend -= delta
		if direction != "" and (direction != held or resend <= 0.0):
			OnlineArena.send_action(direction)
			resend = RESEND
		held = direction
		for f in fighters.values():
			f.t = minf(1.0, f.t + delta / MOVE_SECONDS)
			f.root.position = f.from.lerp(cell_center(f.to), f.t)
			# Idle only after a short rest, so steady walking does not flicker.
			f.rest = f.rest + delta if f.t >= 1.0 else 0.0
			if f.rest > 0.12 and f.alive and str(f.sprite.animation).begins_with("walk"):
				f.sprite.action("idle")
